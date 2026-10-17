# Lanzador de la tarea programada "CasaZaru - Cierre Mensual Gestion" (día 2 de cada mes, 10:30).
# Cierra el mes anterior. Registro de la última corrida en %LOCALAPPDATA%\CasaZaru\cierre-mensual.log
$log = Join-Path $env:LOCALAPPDATA 'CasaZaru\cierre-mensual.log'
New-Item -ItemType Directory -Force (Split-Path $log) | Out-Null
Start-Transcript -Path $log -Force | Out-Null
try {
  & (Join-Path $PSScriptRoot 'cierre-mensual.ps1')
  # Libro Excel y tablero del mes que acaba de cerrar (día 2 → mes anterior)
  & (Join-Path $PSScriptRoot 'libro-mensual.ps1') -Mes (Get-Date).AddMonths(-1).ToString('yyyy-MM')
} catch {
  Write-Output "ERROR: $($_.Exception.Message)"
  $code = 1
} finally {
  Stop-Transcript | Out-Null
}
exit $(if ($code) { $code } else { 0 })