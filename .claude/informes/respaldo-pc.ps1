# Respaldo diario a Drive de lo que vive SOLO en este PC (no está en GitHub ni en Supabase):
# planillas privadas, ~\.casazaru, la memoria y las skills de Claude, archivos sin commit del
# repo, finanzas-casa y las definiciones de las tareas programadas.
#
# Destino: G:\Mi unidad\Casa Zaru\Respaldo PC\  (Google Drive para escritorio lo sube solo).
# Copia con robocopy /E SIN /PURGE: nunca borra nada en Drive, aunque se borre acá.
# Lo que se pisa queda en el historial de versiones de Drive (30 días).
#
# Fuera de la copia, a propósito:
#   - Llaves: ~\.casazaru\config.ps1 (se guarda una copia con la llave en blanco) y los
#     respaldos de código de Apps Script. La llave se vuelve a sacar del panel de Supabase.
#   - ~\.casazaru\snapshots (155 MB, se regeneran) y los worktrees de Claude.
#   - Respaldo-WhatsApp-CasaZaru (8,9 GB; está en el celular).
#
# Corre con la tarea "CasaZaru - Respaldo PC" vía correr-respaldo-pc.ps1.
# Para restaurar en un PC nuevo: copiar cada subcarpeta de vuelta a su ruta (ver ultimo-respaldo.txt).

$ErrorActionPreference = 'Stop'
$h       = $env:USERPROFILE
$destino = 'G:\Mi unidad\Casa Zaru\Respaldo PC'

if (-not (Test-Path 'G:\Mi unidad\Casa Zaru')) {
  throw "Drive no está montado en G:\ (¿Google Drive para escritorio está abierto?)"
}
New-Item -ItemType Directory -Force $destino | Out-Null

# Origen -> subcarpeta de destino, con exclusiones propias de cada uno.
$fuentes = @(
  @{ De = "$h\Casa Zaru - Claude";   A = 'repo-Casa-Zaru'
     XD = @('.git', 'worktrees', 'node_modules'); XF = @('.mcp.json', 'settings.local.json') }
  @{ De = "$h\.casazaru";            A = 'casazaru'
     XD = @('snapshots'); XF = @('config.ps1', 'codigo_fixed.gs', 'apps-script-*.json', 'cerebro-token.txt') }
  @{ De = "$h\Casa Zaru Planillas";  A = 'planillas';      XD = @(); XF = @() }
  @{ De = "$h\finanzas-casa";        A = 'finanzas-casa';  XD = @('.git', 'node_modules'); XF = @() }
  @{ De = "$h\.claude\projects\C--Users-dell-Casa-Zaru---Claude\memory"; A = 'claude\memoria'; XD = @(); XF = @() }
  @{ De = "$h\.claude\skills";          A = 'claude\skills';          XD = @(); XF = @() }
  @{ De = "$h\.claude\scheduled-tasks"; A = 'claude\scheduled-tasks'; XD = @(); XF = @() }
)

$fallas  = @()
$resumen = @()
foreach ($f in $fuentes) {
  if (-not (Test-Path $f.De)) { $fallas += "no existe $($f.De)"; continue }
  $a   = Join-Path $destino $f.A
  $arg = @($f.De, $a, '/E', '/R:1', '/W:2', '/NP', '/NFL', '/NDL', '/NJH', '/NJS')
  if ($f.XD.Count) { $arg += '/XD'; $arg += $f.XD }
  if ($f.XF.Count) { $arg += '/XF'; $arg += $f.XF }
  & robocopy @arg | Out-Null
  $rc = $LASTEXITCODE                      # 0-7 = bien; 8+ = hubo archivos que no se copiaron
  $n  = @(Get-ChildItem $a -Recurse -File -Force -ErrorAction SilentlyContinue).Count
  $resumen += "{0,-24} <- {1}  ({2} archivos, robocopy {3})" -f $f.A, $f.De, $n, $rc
  if ($rc -ge 8) { $fallas += "robocopy $rc en $($f.De)" }
}

# Archivos sueltos
$sueltos = @(
  @{ De = "$h\.claude\conciliacion-excluir.txt"; A = 'claude' }
  @{ De = "$h\.claude\settings.json";            A = 'claude' }
)
foreach ($s in $sueltos) {
  if (-not (Test-Path $s.De)) { $fallas += "no existe $($s.De)"; continue }
  $a = Join-Path $destino $s.A
  New-Item -ItemType Directory -Force $a | Out-Null
  Copy-Item $s.De $a -Force
  $resumen += "{0,-24} <- {1}" -f $s.A, $s.De
}

# config.ps1 con la llave en blanco: se conservan las instrucciones para volver a sacarla.
$cfg = "$h\.casazaru\config.ps1"
if (Test-Path $cfg) {
  $txt = [IO.File]::ReadAllText($cfg)
  $txt = [regex]::Replace($txt, '(?m)^(\s*\$SB_KEY\s*=\s*).*$', '$1"<pegar la llave secreta del panel de Supabase>"')
  [IO.File]::WriteAllText((Join-Path $destino 'casazaru\config.SIN-LLAVE.ps1'), $txt, (New-Object Text.UTF8Encoding $true))
}

# Definiciones de las tareas programadas, para volver a registrarlas en un PC nuevo:
#   Register-ScheduledTask -Xml (Get-Content <xml> -Raw) -TaskName '<nombre>'
$dt = Join-Path $destino 'tareas-windows'
New-Item -ItemType Directory -Force $dt | Out-Null
Get-ScheduledTask -TaskName 'CasaZaru*' | ForEach-Object {
  [IO.File]::WriteAllText((Join-Path $dt ($_.TaskName + '.xml')), (Export-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath))
}
$resumen += "{0,-24} <- {1} tareas CasaZaru*" -f 'tareas-windows', @(Get-ChildItem $dt -Filter *.xml).Count

$estado = if ($fallas.Count) { 'CON FALLAS: ' + ($fallas -join '; ') } else { 'OK' }
$marca  = @(
  "Respaldo PC $(Get-Date -Format 'yyyy-MM-dd HH:mm') - $estado"
  "Equipo: $env:COMPUTERNAME"
  ''
) + $resumen
[IO.File]::WriteAllLines((Join-Path $destino 'ultimo-respaldo.txt'), $marca, (New-Object Text.UTF8Encoding $true))
$marca | Write-Output

if ($fallas.Count) { throw $estado }
