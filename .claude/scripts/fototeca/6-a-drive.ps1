param([string]$Plan="$env:LOCALAPPDATA\CasaZaru\fototeca\a-drive.csv",[string]$Log="$env:LOCALAPPDATA\CasaZaru\fototeca\a-drive-log.csv")
# Copia los originales del PC al Drive según a-drive.csv. No borra ni mueve nada del PC. Retomable: salta lo que ya está con el mismo tamaño.
if(-not (Test-Path $Log)){ 'id,estado' | Out-File $Log -Encoding utf8 }
$hechos=@{}; Import-Csv $Log | ?{ $_.estado -eq 'ok' } | %{ $hechos[$_.id]=1 }
$rows=@(Import-Csv $Plan | ?{ -not $hechos[$_.id] }); "Pendientes: $($rows.Count)"; $i=0
foreach($r in $rows){ $i++
  try{
    $d=Split-Path $r.destino -Parent; if(-not (Test-Path -LiteralPath $d)){ New-Item -ItemType Directory -Force -Path $d | Out-Null }
    if(-not ((Test-Path -LiteralPath $r.destino) -and (Get-Item -LiteralPath $r.destino).Length -eq [long]$r.bytes)){ Copy-Item -LiteralPath $r.origen -Destination $r.destino -Force }
    $est= if((Get-Item -LiteralPath $r.destino).Length -eq [long]$r.bytes){'ok'}else{'tamaño distinto'}
  } catch { $est='error: '+($_.Exception.Message -replace '[\r\n,]',' ') }
  "$($r.id),$est" | Out-File $Log -Append -Encoding utf8
  if($i % 200 -eq 0){ "$i / $($rows.Count)  $(Get-Date -f HH:mm)" }
}
$l=Import-Csv $Log; "FIN $(Get-Date -f HH:mm)  ok: $(@($l|?{$_.estado -eq 'ok'}).Count)  otros: $(@($l|?{$_.estado -ne 'ok'}).Count)"
