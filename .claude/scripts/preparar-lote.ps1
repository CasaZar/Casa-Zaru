param([string]$W,[string]$Lote,[string[]]$Ids)
# Arma las hojas de contacto y el índice (id | carpeta | nombre) de un lote para el clasificador.
$inv=Import-Csv "$W\inventario.csv"; $set=@{}; $Ids|%{$set[$_]=1}
$sub=$inv|?{$set[$_.id]}
$d="$W\lotes\$Lote"; New-Item -ItemType Directory -Force $d | Out-Null
& "$PSScriptRoot\hojas-contacto.ps1" -Inventario "$W\inventario.csv" -FotosDir "$W\fotos" -VideosDir "$W\videos" -OutDir "$d\hojas" -Ids ($Ids -join ',') | Out-Null
$dur=@{}; foreach($l in 'fotos','videos'){ if(Test-Path "$W\$l\_log.csv"){ Import-Csv "$W\$l\_log.csv"|%{ $dur[$_.id]=$_ } } }
$txt=$sub|%{ $x=$dur[$_.id]; $extra= if($_.tipo -eq 'video'){" | video $($x.duracion_s)s $($x.ancho)x$($x.alto)"}else{''}; "$($_.id) | $($_.ruta)$extra" }
[IO.File]::WriteAllLines("$d\indice.txt",$txt,[Text.UTF8Encoding]::new($false))
$hojas=Get-ChildItem "$d\hojas" -Filter *.jpg | Sort-Object Name
$falta=@($sub|?{ if($_.tipo -eq 'foto'){ -not (Test-Path "$W\fotos\$($_.id).jpg") } else { -not (Test-Path "$W\videos\$($_.id)_1.jpg") } })
"$Lote : $($sub.Count) archivos, $($hojas.Count) hojas" + $(if($falta.Count){"  ¡FALTAN $($falta.Count) miniaturas!"}else{''})
