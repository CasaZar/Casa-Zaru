# Lanzador de la tarea programada "CasaZaru - Tablero Diario" (todos los días 08:30, desde el 27-11-2026; antes
# "Tablero Semanal", lunes 10:15). Va después del respaldo de Gestión (03:00) y del reporte de gastos Wasabil (08:07).
# Genera el libro del mes EN CURSO y el tablero en Drive con las cartolas que haya en Descargas y los archivos de
# ~\.casazaru (movs-extra, mp-AAAA-MM). Del día 1 al 5 regenera también el mes anterior, que sigue recibiendo facturas
# y movimientos hasta el cierre. El libro deja lo que queda POR CLASIFICAR en Cerebro\por-clasificar.csv, que la
# corrida de «Mi día» (07:30) vuelve pendiente. Registro en %LOCALAPPDATA%\CasaZaru\tablero-diario.log
$log = Join-Path $env:LOCALAPPDATA 'CasaZaru\tablero-diario.log'
New-Item -ItemType Directory -Force (Split-Path $log) | Out-Null
Start-Transcript -Path $log -Force | Out-Null
$code = 0
$meses = @((Get-Date).ToString('yyyy-MM'))
if ((Get-Date).Day -le 5) { $meses = @((Get-Date).AddMonths(-1).ToString('yyyy-MM')) + $meses }
foreach ($m in $meses) {
  try {
    Write-Output "== $m $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    & (Join-Path $PSScriptRoot 'libro-mensual.ps1') -Mes $m
  } catch {
    Write-Output "ERROR $m : $($_.Exception.Message)"
    $code = 1
  }
}
Stop-Transcript | Out-Null
exit $code
