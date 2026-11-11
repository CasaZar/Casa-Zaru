# Cerebro Zaru - aplica el cierre de un día a pendientes.csv y a la bitácora.
# Uso (desde Bash):
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .claude/cerebro/cerrar-dia.ps1 -Fecha 2026-11-11 -Marcas <marcas.json>
# Lee el día mostrado desde Cerebro\dias\<Fecha>.json (campo «mostrados»).
# Idempotente: un día ya cerrado (Cerebro\cierres.txt) no vuelve a sumar saltos.
# Antes de escribir deja respaldo de pendientes.csv en Cerebro\respaldos\.
# Este archivo no lleva datos: el repo es público.
param(
  [Parameter(Mandatory=$true)][string]$Fecha,
  [Parameter(Mandatory=$true)][string]$Marcas,
  [string]$Cerebro = 'G:\Mi unidad\Casa Zaru\Cerebro'
)
$ErrorActionPreference = 'Stop'
$pendRuta = Join-Path $Cerebro 'pendientes.csv'
$diaRuta = Join-Path $Cerebro "dias\$Fecha.json"
$cierres = Join-Path $Cerebro 'cierres.txt'
$bitacora = Join-Path $Cerebro 'bitacora.md'

if ((Test-Path -LiteralPath $cierres) -and (Select-String -LiteralPath $cierres -SimpleMatch $Fecha -Quiet)) {
  Write-Output "YA_CERRADO $Fecha"; exit 0
}
$m = Get-Content -LiteralPath $Marcas -Raw -Encoding UTF8 | ConvertFrom-Json
$mostrados = @()
if (Test-Path -LiteralPath $diaRuta) { $d = Get-Content -LiteralPath $diaRuta -Raw -Encoding UTF8 | ConvertFrom-Json; if ($d.mostrados) { $mostrados = @($d.mostrados) } }

$hechos = @{}; if ($m.hechos) { $m.hechos.PSObject.Properties | ForEach-Object { if ($_.Value) { $hechos[$_.Name] = $true } } }
$dec = @{}; if ($m.decisiones) { $m.decisiones.PSObject.Properties | ForEach-Object { $dec[$_.Name] = [string]$_.Value } }

$resp = Join-Path $Cerebro 'respaldos'; if (-not (Test-Path -LiteralPath $resp)) { New-Item -ItemType Directory -Path $resp | Out-Null }
Copy-Item -LiteralPath $pendRuta -Destination (Join-Path $resp ("pendientes-{0}.csv" -f (Get-Date -Format 'yyyy-MM-dd-HHmmss')))

$filas = @(Import-Csv -LiteralPath $pendRuta -Encoding UTF8)
$cambios = New-Object System.Collections.ArrayList
$cinco = New-Object System.Collections.ArrayList
foreach ($f in $filas) {
  if ($f.estado -notin @('abierto','esperando')) { continue }
  $id = $f.id
  if ($hechos.ContainsKey($id)) { $f.estado = 'hecho'; $f.ultima_verificacion = $Fecha; [void]$cambios.Add("$id hecho"); continue }
  if ($dec.ContainsKey($id)) {
    switch ($dec[$id]) {
      'matar'   { $f.estado = 'matado';   [void]$cambios.Add("$id matado") }
      'delegar' { $f.estado = 'delegado'; [void]$cambios.Add("$id delegado") }
      'hacer'   { $f.proxima_revision = $Fecha; [void]$cambios.Add("$id hacer (confirmado)") }
    }
    $f.ultima_verificacion = $Fecha; continue
  }
  if ($mostrados -contains $id) {
    $s = 0; [int]::TryParse([string]$f.saltos, [ref]$s) | Out-Null
    $f.saltos = [string]($s + 1)
    if ($s + 1 -ge 5) { [void]$cinco.Add($id) }
  }
}
$filas | Export-Csv -LiteralPath $pendRuta -NoTypeInformation -Encoding UTF8

$lin = New-Object System.Collections.ArrayList
[void]$lin.Add(''); [void]$lin.Add("## $Fecha")
if ($cambios.Count) { [void]$lin.Add('- Cambios: ' + ($cambios -join '; ')) } else { [void]$lin.Add('- Sin marcas.') }
if ($cinco.Count) { [void]$lin.Add('- Con 5 o más saltos (van a Decidir): ' + ($cinco -join ', ')) }
if ($m.notas) { [void]$lin.Add('- Lo nuevo dictado:'); ([string]$m.notas -split "`n") | ForEach-Object { if ($_.Trim()) { [void]$lin.Add('  - ' + $_.Trim()) } } }
$enc = New-Object System.Text.UTF8Encoding($true)
if (-not (Test-Path -LiteralPath $bitacora)) { [System.IO.File]::WriteAllText($bitacora, "# Bitácora del Cerebro Zaru`r`n", $enc) }
[System.IO.File]::AppendAllText($bitacora, (($lin -join "`r`n") + "`r`n"), $enc)
[System.IO.File]::AppendAllText($cierres, "$Fecha`r`n", (New-Object System.Text.UTF8Encoding($false)))
Write-Output ("CERRADO {0} cambios={1} cinco_saltos={2} notas={3}" -f $Fecha, $cambios.Count, ($cinco -join ','), [bool]$m.notas)
