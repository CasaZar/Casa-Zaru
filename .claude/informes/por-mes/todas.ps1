# Genera las cinco planillas "por mes" (madera, Starken, sueldos, bencina, publicidad) y las deja en
# Casa Zaru Planillas\ y en Drive\Casa Zaru\Finanzas\. Las corre correr-cierre.ps1 el día 2; también a mano:
#   .\todas.ps1            -> año del mes pasado
#   .\todas.ps1 -Anio 2026
param([int]$Anio = 0)
$ErrorActionPreference = 'Stop'
foreach ($s in 'madera-mes.ps1', 'starken-mes.ps1', 'sueldos-mes.ps1', 'bencina-mes.ps1', 'publicidad-mes.ps1') {
  try { & (Join-Path $PSScriptRoot $s) -Anio $Anio }
  catch { Write-Output "ERROR en ${s}: $($_.Exception.Message)" }
}
