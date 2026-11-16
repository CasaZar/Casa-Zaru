# Cerebro Zaru - cruce de datos del dia (seccion «Cruce de datos» de Mi dia).
# Etapa 1 (16-11-2026): cotizaciones GANADAS en el Cotizador que no tienen pedido en la Gestion.
# Uso (desde Bash):
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .claude/cerebro/cruzar-dia.ps1 -Fecha 2026-11-16 `
#     -Cotizador <scratchpad>/cruce-cotizador.json -Gestion <scratchpad>/cruce-gestion.json `
#     -Marcas <scratchpad>/marcas-<dia anterior>.json -Salida <scratchpad>/cruce-<hoy>.json
# -Cotizador y -Gestion son los resultados de sql/cotizador-cruce.sql y sql/gestion-cruce.sql, guardados tal cual.
# -Marcas (opcional, se puede repetir separando con coma): lo que el usuario descarto en la pestaña pasa a
#   cruce-descartes.csv y no vuelve a salir.
# Solo lee las fuentes; escribe la salida y cruce-descartes.csv (en Drive). Sin datos ni secretos: el repo es publico.
param(
  [Parameter(Mandatory=$true)][string]$Fecha,
  [Parameter(Mandatory=$true)][string]$Cotizador,
  [Parameter(Mandatory=$true)][string]$Gestion,
  [Parameter(Mandatory=$true)][string]$Salida,
  [string[]]$Marcas = @(),
  [string]$Descartes = 'G:\Mi unidad\Casa Zaru\Cerebro\cruce-descartes.csv'
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Leer-Filas([string]$ruta) {
  $j = Get-Content -LiteralPath $ruta -Raw -Encoding UTF8 | ConvertFrom-Json
  # Acepta el arreglo directo o la fila de la consulta: [{ "cruce": [...] }]
  $j = @($j)
  if ($j.Count -eq 1 -and $j[0].PSObject.Properties.Name -contains 'cruce') { return @($j[0].cruce) }
  return $j
}
function Sin-Tildes([string]$s) {
  if (-not $s) { return '' }
  $n = $s.ToLowerInvariant().Normalize([Text.NormalizationForm]::FormD)
  $sb = New-Object System.Text.StringBuilder
  foreach ($ch in $n.ToCharArray()) { if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne 'NonSpacingMark') { [void]$sb.Append($ch) } }
  return $sb.ToString()
}
function Fono8([string]$s) { $d = ($s -replace '\D', ''); if ($d.Length -ge 8) { return $d.Substring($d.Length - 8) } return '' }
function Palabras([string]$s) { return @((Sin-Tildes $s) -split '[^a-z]+' | Where-Object { $_.Length -ge 3 }) }
function Mismo-Nombre($a, $b) {
  # Un solo nombre en comun no alcanza: primer nombre igual y ademas otro apellido en comun.
  if ($a.Count -lt 2 -or $b.Count -lt 2) { return $false }
  if ($a[0] -ne $b[0]) { return $false }
  foreach ($x in $a[1..($a.Count - 1)]) { if ($b[1..($b.Count - 1)] -contains $x) { return $true } }
  return $false
}
function Plata($n) { return '$' + ([math]::Round([double]$n)).ToString('N0', [Globalization.CultureInfo]::GetCultureInfo('es-CL')) }
function Corta([string]$iso) { if ($iso -match '^(\d{4})-(\d{2})-(\d{2})') { return "$($Matches[3])-$($Matches[2])" } return $iso }

$cot = Leer-Filas $Cotizador
$ped = Leer-Filas $Gestion

# 1. Descartes: lo que el usuario marco «No es venta» en la pestaña queda para siempre en el CSV.
$desc = @{}
if (Test-Path -LiteralPath $Descartes) { Import-Csv -LiteralPath $Descartes -Encoding UTF8 | ForEach-Object { $desc[$_.id] = $_ } }
$nuevos = 0
foreach ($m in $Marcas) {
  if (-not $m -or -not (Test-Path -LiteralPath $m)) { continue }
  $mj = Get-Content -LiteralPath $m -Raw -Encoding UTF8 | ConvertFrom-Json
  if (-not $mj -or -not $mj.cruce) { continue }
  foreach ($p in $mj.cruce.PSObject.Properties) {
    if ($p.Value.accion -eq 'descartar' -and -not $desc.ContainsKey($p.Name)) {
      $desc[$p.Name] = [pscustomobject]@{ id = $p.Name; fecha = $Fecha; motivo = [string]$p.Value.motivo }
      $nuevos++
    }
  }
}
if ($nuevos -gt 0) {
  $lin = New-Object System.Collections.ArrayList
  [void]$lin.Add('id,fecha,motivo')
  foreach ($d in ($desc.Values | Sort-Object fecha, id)) { [void]$lin.Add(('"{0}","{1}","{2}"' -f $d.id, $d.fecha, (([string]$d.motivo) -replace '"', '""'))) }
  [System.IO.File]::WriteAllText($Descartes, ($lin -join "`r`n") + "`r`n", (New-Object System.Text.UTF8Encoding($true)))
}

# 2. Cada ganada busca UN pedido del mismo cliente (telefono, o nombre y apellido), el de monto mas parecido.
#    Un pedido justifica una sola cotizacion: un cliente con dos ganadas y un pedido deja una sin pedido.
function Dia([string]$s) { if ($s -and $s.Length -ge 10) { return [datetime]::ParseExact($s.Substring(0, 10), 'yyyy-MM-dd', $null) } return $null }
$C = @($cot | ForEach-Object { [pscustomobject]@{ c = $_; f8 = (Fono8 ([string]$_.contacto)); pal = (Palabras ([string]$_.cliente)); creada = (Dia ([string]$_.creada)); monto = [double]$_.monto; pedido = $null } })
$P = @($ped | Where-Object { -not $_.tipo -or $_.tipo -eq 'VENTA' } | ForEach-Object { [pscustomobject]@{ p = $_; f8 = (Fono8 ([string]$_.celular)); pal = (Palabras ("$($_.nombre) $($_.apellido)")); fecha = (Dia ([string]$_.fecha)); usado = $false } })
function Mismo-Cliente($a, $b) { return ($a.f8 -and $a.f8 -eq $b.f8) -or (Mismo-Nombre $a.pal $b.pal) }

# Pares posibles: mismo cliente y pedido no anterior a la cotizacion (salvo que el monto calce casi exacto:
# un pedido que se amplio despues conserva su fecha original). Se asignan del monto mas parecido al menos.
$pares = New-Object System.Collections.ArrayList
foreach ($x in $C) {
  foreach ($y in $P) {
    if (-not (Mismo-Cliente $x $y)) { continue }
    $dif = [math]::Min([math]::Abs($x.monto - [double]$y.p.val_prod), [math]::Abs($x.monto - [double]$y.p.total))
    $despues = (-not $x.creada) -or (-not $y.fecha) -or ($y.fecha -ge $x.creada.AddDays(-3))
    if ($despues -or $dif -le ($x.monto * 0.01)) { [void]$pares.Add([pscustomobject]@{ x = $x; y = $y; dif = $dif }) }
  }
}
foreach ($par in ($pares | Sort-Object dif)) {
  if ($par.x.pedido -or $par.y.usado) { continue }
  $par.x.pedido = $par.y; $par.y.usado = $true
}

$sinPedido = New-Object System.Collections.ArrayList
$calzan = 0
foreach ($x in $C) {
  if ($x.pedido) { $calzan++; continue }
  # Cotizacion repetida: otra ganada del mismo cliente por el mismo monto ya tiene su pedido.
  $repetida = @($C | Where-Object { $_.pedido -and $_.monto -eq $x.monto -and (Mismo-Cliente $_ $x) }).Count -gt 0
  # Absorbida: el cliente tiene un pedido de esa fecha o posterior por un monto igual o mayor (se amplio la compra).
  $absorbida = @($P | Where-Object { (Mismo-Cliente $x $_) -and [double]$_.p.total -ge $x.monto -and ((-not $x.creada) -or (-not $_.fecha) -or ($_.fecha -ge $x.creada.AddDays(-3))) }).Count -gt 0
  if ($repetida -or $absorbida) { $calzan++; continue }
  $c = $x.c
  $num = ([string]$c.numero) -replace '^N°\s*', ''
  $id = 'cot:' + $num
  if ($desc.ContainsKey($id)) { continue }
  [void]$sinPedido.Add([pscustomobject]@{
    id = $id
    tono = 'rojo'
    titulo = [string]$c.cliente
    monto = $c.monto
    lineas = @("Ganada el $(Corta ([string]$c.concretada)) · cotización $num" + $(if ($c.producto) { " · $($c.producto)" } else { '' }))
    acciones = @('cargar', 'descartar')
    cot = [pscustomobject]@{ numero = $num; cliente = [string]$c.cliente; contacto = [string]$c.contacto; monto = $c.monto; producto = [string]$c.producto; concretada = [string]$c.concretada; link = [string]$c.link; canal = [string]$c.canal }
  })
}

$grupos = New-Object System.Collections.ArrayList
if ($sinPedido.Count) { [void]$grupos.Add([pscustomobject]@{ k = 'sin_pedido'; titulo = 'Vendida en el Cotizador y sin pedido'; items = $sinPedido.ToArray() }) }
$total = 0; foreach ($i in $sinPedido) { $total += [double]$i.monto }
$res = [pscustomobject]@{
  generado = (Get-Date).ToString('o')
  etapa = 1
  grupos = $grupos.ToArray()
  calzan = "Calzan: $calzan de $(@($cot).Count) ventas del Cotizador de los últimos 30 días tienen su pedido."
  fuentes = @([pscustomobject]@{ nombre = 'Cotizador y Gestión'; cuando = (Get-Date).ToString('o') })
}
$dir = Split-Path -Parent $Salida; if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
[System.IO.File]::WriteAllText($Salida, ($res | ConvertTo-Json -Depth 10), $utf8)
Write-Output "OK $Salida sin_pedido=$($sinPedido.Count) por=$(Plata $total) calzan=$calzan de=$(@($cot).Count) descartes_nuevos=$nuevos"
