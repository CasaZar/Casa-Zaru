# Retención mensual de los respaldos de Supabase (contrato: 30 diarios + 12 mensuales).
#
# Los diarios de Gestión los deja la Edge Function gestion-respaldo-v2 y el Apps Script de las
# boletas se queda solo con los últimos 30: sin esto, nada tiene más de 30 días. Este script
# guarda el PRIMER respaldo de cada mes en una carpeta aparte, que nadie poda:
#   G:\Mi unidad\Casa Zaru\Respaldos Mensuales\Gestion\    respaldo-gestion-AAAA-MM-DD.json
#   G:\Mi unidad\Casa Zaru\Respaldos Mensuales\Cotizador\  respaldo-cotizador-AAAA-MM-DD.zip
#
# - Nunca borra nada (ni en los diarios ni en los mensuales). 12 es el mínimo, no un tope:
#   cada mensual pesa ~2-3 MB.
# - Nunca pisa: si el mes ya tiene su mensual, no se toca.
# - Basta con que corra una vez dentro de los 30 días que dura el diario del día 1, así que
#   aguanta semanas con el PC apagado. Lo llama respaldo-pc.ps1 (tarea diaria de las 14:00).
# - Copia exacta: compara tamaño después de copiar.
#
# No toca el Apps Script de las boletas a propósito: ese script también emite al SII.

$ErrorActionPreference = 'Stop'
$drive = 'G:\Mi unidad\Casa Zaru'
if (-not (Test-Path $drive)) { throw "Drive no está montado en G:\ (¿Google Drive para escritorio está abierto?)" }

$fuentes = @(
  @{ Nombre = 'Gestion';   Patron = 'respaldo-gestion-*.json'
     Dirs = @("$drive\Finanzas\Boletas y Facturas - Ventas 2026\Respaldos Gestion") }
  @{ Nombre = 'Cotizador'; Patron = 'respaldo-cotizador-*.zip'
     Dirs = @("$drive\Finanzas\Boletas y Facturas - Ventas 2026\Respaldos Cotizador", "$drive\Respaldos Cotizador") }
)

$salida = @()
foreach ($f in $fuentes) {
  $dest = Join-Path "$drive\Respaldos Mensuales" $f.Nombre
  New-Item -ItemType Directory -Force $dest | Out-Null

  # Diarios disponibles, por fecha del NOMBRE (la de Chile), no por fecha de modificación.
  $diarios = @(foreach ($d in $f.Dirs) { if (Test-Path $d) { Get-ChildItem $d -Filter $f.Patron -File } }) |
    Where-Object { $_.Name -match '(\d{4}-\d{2})-\d{2}\.' -and $_.Length -gt 0 } |
    Sort-Object Name
  $ya = @(Get-ChildItem $dest -Filter $f.Patron -File | ForEach-Object { if ($_.Name -match '(\d{4}-\d{2})-\d{2}\.') { $Matches[1] } })

  $nuevos = 0
  foreach ($grupo in ($diarios | Group-Object { if ($_.Name -match '(\d{4}-\d{2})-\d{2}\.') { $Matches[1] } })) {
    if ($ya -contains $grupo.Name) { continue }
    $primero = $grupo.Group | Sort-Object Name | Select-Object -First 1
    $destino = Join-Path $dest $primero.Name
    Copy-Item $primero.FullName $destino
    if ((Get-Item $destino).Length -ne $primero.Length) { throw "Copia incompleta: $destino" }
    $salida += "  + $($f.Nombre) $($grupo.Name) <- $($primero.Name)"
    $nuevos++
  }
  $total = @(Get-ChildItem $dest -Filter $f.Patron -File).Count
  $salida += "Mensuales $($f.Nombre): $total (nuevos hoy: $nuevos)"
}
$salida | Write-Output
