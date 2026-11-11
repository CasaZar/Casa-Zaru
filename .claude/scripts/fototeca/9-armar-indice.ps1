param([int]$Desde=65,[string]$Out="$env:LOCALAPPDATA\CasaZaru\fototeca\publicar")
# Arma lo que se sube al bucket «fototeca» para las fotos del PC: sprites s65… y datos-2.json (segundo índice,
# para no pasar el límite de 5 MB del bucket con datos.json). No toca el bucket ni el Drive.
$ErrorActionPreference='Stop'
$P="$env:LOCALAPPDATA\CasaZaru\fototeca"
Add-Type -AssemblyName System.Drawing
$sq="$PSScriptRoot\..\sqlite-lectura.ps1"
$db=(Get-ChildItem "$env:LOCALAPPDATA\Google\DriveFS" -Directory | ?{ Test-Path "$($_.FullName)\metadata_sqlite_db" } | select -First 1).FullName+"\metadata_sqlite_db"
New-Item -ItemType Directory -Force $Out | Out-Null
$fuera=@{}; Import-Csv "$P\repetidas-finales.csv" | %{ $fuera[$_.id]=1 }
$cl=@{}; Get-Content "$P\resultado.jsonl" -Encoding UTF8 | ?{ $_.Trim() } | %{ $o=$_ | ConvertFrom-Json; if($o.id -ne '_grupo'){ $cl[$o.id]=$o } }
$lg=@{}; Import-Csv "$P\mini\_log.csv" | %{ $lg[$_.id]=$_ }
$dr=@{}; & $sq -Db $db -Sql "select local_title t, id from items where is_folder=0 and id not like 'local%' and local_title like '20__\_M____.%' escape '\'" | %{ $dr[$_.t]=$_.id }
$sel=@(Import-Csv "$P\a-drive.csv" | ?{ $_.destino -like '*\1 Utiles\*' -and -not $fuera[$_.id] } | Sort-Object id)
$jpg=[System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders()|?{$_.MimeType -eq 'image/jpeg'}
$ep=New-Object System.Drawing.Imaging.EncoderParameters 1; $ep.Param[0]=New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality,[long]72)
$items=New-Object System.Collections.Generic.List[object]; $sinId=0
for($s=0;$s*100 -lt $sel.Count;$s++){
  $bm=New-Object System.Drawing.Bitmap 2800,2800; $g=[System.Drawing.Graphics]::FromImage($bm); $g.Clear([System.Drawing.Color]::FromArgb(235,232,226)); $g.InterpolationMode='HighQualityBicubic'
  for($k=0;$k -lt 100 -and ($s*100+$k) -lt $sel.Count;$k++){
    $a=$sel[$s*100+$k]; $c=$cl[$a.id]; $x=$k%10; $y=[math]::Floor($k/10)
    $f="$P\mini\$($a.id).jpg"; if(-not (Test-Path $f)){ $cu=@(Get-ChildItem "$P\mini" -Filter "$($a.id)_*.jpg" | Sort-Object Name); $f=$cu[[math]::Floor(($cu.Count-1)/2)].FullName }
    $im=[System.Drawing.Image]::FromFile($f); $l=[math]::Min($im.Width,$im.Height)
    $g.DrawImage($im,(New-Object System.Drawing.Rectangle ($x*280),($y*280),280,280),(New-Object System.Drawing.Rectangle ([int](($im.Width-$l)/2)),([int](($im.Height-$l)/2)),$l,$l),[System.Drawing.GraphicsUnit]::Pixel); $im.Dispose()
    $nom=Split-Path $a.destino -Leaf; $id=$dr[$nom]; if(-not $id){ $sinId++ }
    $tipo= if($a.origen -match '(?i)\.(mp4|mov|m4v|avi)$'){'video'}else{'foto'}
    $items.Add([ordered]@{ id=$a.id; tipo=$tipo; producto=$c.producto; madera=$c.madera; confianza=$c.confianza; etapa=$c.etapa; ambiente=$c.ambiente
      forma=$c.forma; uso=$c.uso; calidad=[int]$c.calidad; ia=$c.ia; ia_nota=''; orientacion=$c.orientacion; personas=[bool]$c.personas; descripcion=$c.descripcion
      gancho=$c.gancho; que_pasa=$c.que_pasa; tipo_video=$c.tipo_video; etiquetas=@($c.etiquetas); dur=[int]("0"+$lg[$a.id].duracion_s)
      nombre=$nom; ruta=('Casa Zaru\'+((Split-Path $a.destino -Parent) -replace '^G:\\Mi unidad\\Casa Zaru\\','')); drive=$id; s=$Desde+$s; x=$x; y=$y; anio=$nom.Substring(0,4) })
  }
  $g.Dispose(); $bm.Save((Join-Path $Out ('s{0:D2}.jpg' -f ($Desde+$s))),$jpg,$ep); $bm.Dispose()
}
$json=[ordered]@{ meta=[ordered]@{ generado=(Get-Date -f 'yyyy-MM-dd HH:mm'); origen='PC 2026-11' }; items=$items } | ConvertTo-Json -Depth 5 -Compress
[IO.File]::WriteAllText("$Out\datos-2.json",$json,[Text.UTF8Encoding]::new($false))
"items: $($items.Count)  hojas: s$Desde..s$($Desde+$s-1)  sin id de Drive todavía: $sinId  datos-2.json: {0:N0} KB" -f ((Get-Item "$Out\datos-2.json").Length/1KB)
