# Sube a la bandeja de mensajes (proyecto Cotizador) lo que la revision del 5558 aprendio:
# las respuestas "modelo" y "evitar" de corpus-respuestas.jsonl y la guia-respuestas.md.
# Los borradores de la bandeja las usan como ejemplo (funcion mensajes-webhook, ruta /conocimiento).
#
#   powershell -ExecutionPolicy Bypass -File .claude\skills\revision-whatsapp\subir-conocimiento.ps1 -Simular
#   powershell -ExecutionPolicy Bypass -File .claude\skills\revision-whatsapp\subir-conocimiento.ps1
#
# - Subir dos veces no duplica: cada ejemplo lleva una clave (fecha + cliente + respuesta). Si una linea
#   se reevalua (calidad, resultado a 7 dias), se actualiza.
# - NO sube lineas "ok" (la bandeja no las usa) ni lineas con algo que parezca telefono, correo, RUT o link.
# - Quita los signos de apertura de las respuestas y de la guia: en la bandeja estan prohibidos y la base
#   rechaza un envio que los traiga. El corpus de Drive NO se toca.
# - El secreto se lee de %USERPROFILE%\.casazaru\conocimiento-token.txt y nunca se imprime.
# Solo ASCII en este archivo (PowerShell 5.1 lee los .ps1 sin BOM como ANSI).
param(
  [string]$Carpeta = 'G:\Mi unidad\Casa Zaru\Revision WhatsApp',
  [string]$Url = 'https://cmxqorsyxoltrakxawro.supabase.co/functions/v1/mensajes-webhook/conocimiento',
  [string]$TokenRuta = (Join-Path $env:USERPROFILE '.casazaru\conocimiento-token.txt'),
  [switch]$Simular
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$corpus = Join-Path $Carpeta 'corpus-respuestas.jsonl'
$guiaRuta = Join-Path $Carpeta 'guia-respuestas.md'
if (-not (Test-Path -LiteralPath $corpus)) { throw "No existe $corpus" }

$utf8 = New-Object System.Text.UTF8Encoding($false)
$abre = '[' + [char]0x00BF + [char]0x00A1 + ']'      # signos de apertura de pregunta y de exclamacion
function Limpiar([string]$t) {
  if ($null -eq $t) { return $null }
  return ($t -replace $abre, '').Trim()
}
# Algo que parezca dato personal: telefono, correo, RUT o link. La linea que calce no se sube.
$personal = '(\+?56\s?)?9\s?\d{4}\s?\d{4}|\d{9,}|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}|\d{1,2}\.?\d{3}\.?\d{3}-[\dkK]|https?://'
$resultados = @(('compr' + [char]0x00F3), ('sigui' + [char]0x00F3), 'silencio', 'perdido', 'pendiente')

$ej = New-Object System.Collections.Generic.List[object]
$total = 0; $noUsa = 0; $conPersonal = 0; $incompletas = 0; $malJson = 0; $limpiadas = 0; $modelos = 0; $evitar = 0
foreach ($l in [System.IO.File]::ReadAllLines($corpus, $utf8)) {
  if (-not $l.Trim()) { continue }
  $total++
  try { $o = $l | ConvertFrom-Json } catch { $malJson++; continue }
  if (@('modelo', 'evitar') -notcontains $o.calidad) { $noUsa++; continue }
  if (-not $o.cliente -or -not $o.respuesta -or -not $o.intencion -or ([string]$o.fecha -notmatch '^\d{4}-\d{2}-\d{2}$')) { $incompletas++; continue }
  if (("$($o.cliente) $($o.respuesta) $($o.por_que)") -match $personal) { $conPersonal++; continue }
  $resp = Limpiar ([string]$o.respuesta)
  if (-not $resp) { $incompletas++; continue }
  if ($resp -ne ([string]$o.respuesta).Trim()) { $limpiadas++ }
  if ($o.calidad -eq 'modelo') { $modelos++ } else { $evitar++ }
  $res7 = $null
  if ($resultados -contains $o.resultado_7d) { $res7 = [string]$o.resultado_7d }
  $ej.Add([ordered]@{
    fecha = [string]$o.fecha; intencion = [string]$o.intencion; producto = $o.producto
    cliente = [string]$o.cliente; respuesta = $resp; calidad = [string]$o.calidad
    resultado_7d = $res7; por_que = $o.por_que
  })
}

$guia = $null
if (Test-Path -LiteralPath $guiaRuta) { $guia = Limpiar ([System.IO.File]::ReadAllText($guiaRuta, $utf8)) }
$guiaLargo = 0
if ($guia) { $guiaLargo = $guia.Length }

Write-Output ("Corpus: {0} lineas. Suben {1} ({2} modelo, {3} evitar). No se usan (ok): {4}. Con posible dato personal: {5}. Incompletas: {6}. JSON malo: {7}. Con signos de apertura quitados: {8}." -f $total, $ej.Count, $modelos, $evitar, $noUsa, $conPersonal, $incompletas, $malJson, $limpiadas)
Write-Output ("Guia: {0} caracteres." -f $guiaLargo)
if ($Simular) { Write-Output 'SIMULADO: no se subio nada.'; exit 0 }
if ($ej.Count -eq 0 -and -not $guia) { Write-Output 'Nada que subir.'; exit 0 }

if (-not (Test-Path -LiteralPath $TokenRuta)) { throw "Falta el secreto en $TokenRuta" }
$token = (Get-Content -LiteralPath $TokenRuta -Raw).Trim()
$cuerpo = @{ ejemplos = $ej.ToArray(); guia = $guia } | ConvertTo-Json -Depth 6 -Compress
$bytes = $utf8.GetBytes($cuerpo)
try {
  $r = Invoke-WebRequest -Uri $Url -Method Post -Body $bytes -ContentType 'application/json; charset=utf-8' -Headers @{ 'x-conocimiento-token' = $token } -UseBasicParsing -TimeoutSec 60
  Write-Output ("Subido: {0} {1}" -f $r.StatusCode, $r.Content)
} catch {
  $resp = $_.Exception.Response
  if ($resp) {
    $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
    throw ("La bandeja rechazo la subida: {0} {1}" -f [int]$resp.StatusCode, $sr.ReadToEnd())
  }
  throw
}
