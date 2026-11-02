# Lanzador de la tarea programada "CasaZaru - Respaldo PC" (todos los días 14:00).
# Deja el registro de la última corrida en %LOCALAPPDATA%\CasaZaru\respaldo-pc.log
$log = Join-Path $env:LOCALAPPDATA 'CasaZaru\respaldo-pc.log'
New-Item -ItemType Directory -Force (Split-Path $log) | Out-Null
Start-Transcript -Path $log -Force | Out-Null
try {
  & (Join-Path $PSScriptRoot 'respaldo-pc.ps1')
} catch {
  Write-Output "ERROR: $($_.Exception.Message)"
  $code = 1
} finally {
  Stop-Transcript | Out-Null
}
exit $(if ($code) { $code } else { 0 })
