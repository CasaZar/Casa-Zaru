# Muestra filas de un CSV exportado como "fila: A=.. | B=.." (solo celdas con valor)
param([Parameter(Mandatory=$true)][string[]]$Files, [int]$Head = 0, [int]$Tail = 0, [int]$MaxLen = 40)
foreach ($f in $Files) {
  Write-Output ('######## ' + (Split-Path $f -Leaf))
  $rows = @(Import-Csv -LiteralPath $f -Delimiter ';' -Encoding UTF8)
  $sel = $rows
  if ($Head -gt 0 -and $Tail -gt 0 -and $rows.Count -gt ($Head + $Tail)) { $sel = @($rows | Select-Object -First $Head) + @([pscustomobject]@{fila='...'}) + @($rows | Select-Object -Last $Tail) }
  elseif ($Head -gt 0 -and $rows.Count -gt $Head) { $sel = @($rows | Select-Object -First $Head) + @([pscustomobject]@{fila=('... (' + $rows.Count + ' filas)')}) }
  foreach ($r in $sel) {
    $parts = @()
    foreach ($p in $r.PSObject.Properties) {
      if ($p.Name -eq 'fila') { continue }
      $v = [string]$p.Value
      if ($v -ne '') { if ($v.Length -gt $MaxLen) { $v = $v.Substring(0, $MaxLen) + '~' }; $parts += ($p.Name + '=' + $v) }
    }
    Write-Output ($r.fila + ': ' + ($parts -join ' | '))
  }
}
