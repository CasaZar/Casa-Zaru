# Lanzador de la tarea programada "CasaZaru - Tablero Semanal" (lunes 10:15).
# Genera el libro del mes EN CURSO y el tablero en Drive con las cartolas que haya en Descargas
# (el usuario las baja el lunes temprano). Registro en %LOCALAPPDATA%\CasaZaru\tablero-semanal.log
$log = Join-Path $env:LOCALAPPDATA 'CasaZaru\tablero-semanal.log'
New-Item -ItemType Directory -Force (Split-Path $log) | Out-Null
Start-Transcript -Path $log -Force | Out-Null
try {
  & (Join-Path $PSScriptRoot 'libro-mensual.ps1') -Mes (Get-Date).ToString('yyyy-MM')
} catch {
  Write-Output "ERROR: $($_.Exception.Message)"
  $code = 1
} finally {
  Stop-Transcript | Out-Null
}
exit $(if ($code) { $code } else { 0 })
