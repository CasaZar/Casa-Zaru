# Lanzador de la tarea programada "CasaZaru - Informe Semanal Gestion" (lunes 08:30).
# Deja el registro de la última corrida en %LOCALAPPDATA%\CasaZaru\informe-semanal.log
$log = Join-Path $env:LOCALAPPDATA 'CasaZaru\informe-semanal.log'
New-Item -ItemType Directory -Force (Split-Path $log) | Out-Null
Start-Transcript -Path $log -Force | Out-Null
try {
  & (Join-Path $PSScriptRoot 'informe-semanal.ps1')
} catch {
  Write-Output "ERROR: $($_.Exception.Message)"
  $code = 1
} finally {
  Stop-Transcript | Out-Null
}
exit $(if ($code) { $code } else { 0 })
