# Lee la cartola "Movimientos_Detallado_Cuenta_7175_MUVALE DISENO SPA.xlsx" del BCI
# y deja un CSV con una fila por movimiento (ingresos y egresos).
# No hay Python ni Excel en esta máquina: el xlsx se abre como ZIP.
#
# Uso:
#   .\leer-cartola-bci.ps1 -Ruta "C:\Users\dell\Downloads\2026-09-28_Movimientos_...xlsx" -Salida bci.csv
#   (-Ruta se puede omitir: toma la cartola más reciente de Descargas)
param(
  [string]$Ruta,
  [Parameter(Mandatory=$true)][string]$Salida
)
$ErrorActionPreference = 'Stop'
if (-not $Ruta) {
  $f = Get-ChildItem "$env:USERPROFILE\Downloads" -Filter '*Movimientos_Detallado_Cuenta_7175*.xlsx' |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $f) { throw 'No encontré ninguna cartola BCI (…Movimientos_Detallado_Cuenta_7175….xlsx) en Descargas.' }
  $Ruta = $f.FullName
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$z = [IO.Compression.ZipFile]::OpenRead($Ruta)
# OJO: no llamar a esta función "rd" — es alias de Remove-Item.
function LeerEntrada($n) {
  $e = $z.GetEntry($n); if (-not $e) { return $null }
  $s = New-Object IO.StreamReader($e.Open(), [Text.Encoding]::UTF8); $t = $s.ReadToEnd(); $s.Close(); $t
}
try {
  $ssXml = LeerEntrada 'xl/sharedStrings.xml'
  $strs = @(); if ($ssXml) { [xml]$ss = $ssXml; $strs = @($ss.sst.si | ForEach-Object { $_.InnerText }) }
  [xml]$sh = LeerEntrada 'xl/worksheets/sheet1.xml'
} finally { $z.Dispose() }

$filas = foreach ($row in $sh.worksheet.sheetData.row) {
  $h = @{}
  foreach ($c in $row.c) {
    $col = ($c.r -replace '\d', ''); $v = $c.v
    if ($c.t -eq 's') { $v = $strs[[int]$v] } elseif ($c.t -eq 'inlineStr') { $v = $c.is.InnerText }
    $h[$col] = $v
  }
  , $h
}
# Columnas de la cartola (fila 1): A fecha transacción (serial Excel), B hora,
# F tipo, H glosa, I ingreso, J egreso, L nombre, M rut, P banco, R comentario.
$enc = $filas[0]
if ($enc['A'] -notmatch 'Fecha' -or $enc['I'] -notmatch 'Ingreso') {
  throw "La cartola no tiene el formato esperado (A='$($enc['A'])', I='$($enc['I'])'). Revisar columnas antes de seguir."
}
$base = [datetime]'1899-12-30'; $inv = [Globalization.CultureInfo]::InvariantCulture
$num = { param($x) if ($x) { [int64][math]::Round([double]::Parse($x, $inv)) } else { 0 } }
$res = $filas | Select-Object -Skip 1 | Where-Object { $_['A'] } | ForEach-Object {
  [pscustomobject]@{
    fecha      = $base.AddDays([double]::Parse($_['A'], $inv)).ToString('yyyy-MM-dd')
    hora       = $_['B']
    tipo       = $_['F']
    glosa      = $_['H']
    ingreso    = & $num $_['I']
    egreso     = & $num $_['J']
    nombre     = $_['L']
    rut        = $_['M']
    banco      = $_['P']
    comentario = $_['R']
  }
}
$res | Sort-Object fecha, hora | Export-Csv -Encoding UTF8 -NoTypeInformation $Salida
$ing = @($res | Where-Object { $_.ingreso -gt 0 })
"Cartola: $Ruta"
"Movimientos: $($res.Count) | ingresos: $($ing.Count) por {0:N0} | desde {1} hasta {2}" -f `
  ($ing | Measure-Object ingreso -Sum).Sum, ($res | Sort-Object fecha | Select-Object -First 1).fecha, ($res | Sort-Object fecha | Select-Object -Last 1).fecha
