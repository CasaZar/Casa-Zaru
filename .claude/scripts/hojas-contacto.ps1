param([string]$Inventario,[string]$FotosDir,[string]$VideosDir,[string]$OutDir,[int]$Celda=420,[int]$Cols=3,[string]$Ids='')
# Hojas de contacto: fotos de a 9 (3x3) y una hoja por video con sus cuadros. Cada recuadro lleva el id.
Add-Type -AssemblyName System.Drawing
$jpg=[System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders()|?{$_.MimeType -eq 'image/jpeg'}
$ep=New-Object System.Drawing.Imaging.EncoderParameters 1; $ep.Param[0]=New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality,[long]85)
$font=New-Object System.Drawing.Font('Segoe UI',13,[System.Drawing.FontStyle]::Bold)
$barra=24
function Hoja([object[]]$items,[string]$dest,[int]$cols,[string]$titulo){
  $rowsN=[math]::Ceiling($items.Count/$cols); $top= if($titulo){30}else{0}
  $W=$cols*$Celda; $H=$top+$rowsN*($Celda+$barra)
  $bm=New-Object System.Drawing.Bitmap $W,$H; $g=[System.Drawing.Graphics]::FromImage($bm); $g.Clear([System.Drawing.Color]::FromArgb(30,30,30)); $g.InterpolationMode='HighQualityBicubic'
  if($titulo){ $g.DrawString($titulo,$font,[System.Drawing.Brushes]::Yellow,6,4) }
  for($k=0;$k -lt $items.Count;$k++){
    $x=($k % $cols)*$Celda; $y=$top+[math]::Floor($k/$cols)*($Celda+$barra)
    $g.DrawString($items[$k].label,$font,[System.Drawing.Brushes]::White,$x+4,$y+1)
    try{ $im=[System.Drawing.Image]::FromFile($items[$k].file)
      $s=[math]::Min(($Celda-6)/$im.Width,($Celda-6)/$im.Height); $w=[int]($im.Width*$s); $h=[int]($im.Height*$s)
      $g.DrawImage($im,$x+[int](($Celda-$w)/2),$y+$barra+[int](($Celda-$h)/2),$w,$h); $im.Dispose() } catch {}
  }
  $g.Dispose(); $bm.Save($dest,$jpg,$ep); $bm.Dispose()
}
New-Item -ItemType Directory -Force $OutDir | Out-Null
$inv=Import-Csv $Inventario; if($Ids){ $set=@{}; $Ids.Split(',')|%{$set[$_]=1}; $inv=$inv|?{$set[$_.id]} }
# Fotos
$f=@($inv|?{$_.tipo -eq 'foto'}|%{ $p=Join-Path $FotosDir "$($_.id).jpg"; if(Test-Path $p){ [pscustomobject]@{label=$_.id;file=$p} } })
$n=0; for($i=0;$i -lt $f.Count;$i+=9){ $n++; Hoja $f[$i..([math]::Min($i+8,$f.Count-1))] (Join-Path $OutDir ('F{0:D3}.jpg' -f $n)) $Cols '' }
# Videos
$v=0; foreach($r in ($inv|?{$_.tipo -eq 'video'})){
  $fr=@(Get-ChildItem $VideosDir -Filter "$($r.id)_*.jpg" -ErrorAction SilentlyContinue | Sort-Object Name | %{ [pscustomobject]@{label=$_.BaseName;file=$_.FullName} })
  if($fr.Count){ $v++; $c= if($fr.Count -gt 4){3}else{2}; Hoja $fr (Join-Path $OutDir "V_$($r.id).jpg") $c "$($r.id)" }
}
"Hojas de fotos: $n  Hojas de videos: $v"
