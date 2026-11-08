param([string]$W,[string]$OutDir,[int]$Celda=280,[int]$Cols=10,[int]$Filas=10,[string]$SoloIds='')
# -SoloIds: archivo con un id por línea; solo esos entran a los sprites (así no viajan capturas con datos de clientes).
# Junta las miniaturas en hojas (sprites) de Cols x Filas para la app de búsqueda. Devuelve el mapa id -> hoja, x, y.
Add-Type -AssemblyName System.Drawing
$jpg=[System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders()|?{$_.MimeType -eq 'image/jpeg'}
$ep=New-Object System.Drawing.Imaging.EncoderParameters 1; $ep.Param[0]=New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality,[long]72)
New-Item -ItemType Directory -Force $OutDir | Out-Null
$inv=Import-Csv "$W\inventario.csv"
if($SoloIds){ $ok=@{}; Get-Content $SoloIds | ? { $_.Trim() } | % { $ok[$_.Trim()]=1 }; $inv=$inv | ? { $ok[$_.id] } }
$items=foreach($r in $inv){
  $p= if($r.tipo -eq 'foto'){ "$W\fotos\$($r.id).jpg" } else { $c=@(Get-ChildItem "$W\videos" -Filter "$($r.id)_*.jpg" -EA SilentlyContinue|Sort-Object Name); if($c.Count){ $c[[math]::Floor(($c.Count-1)/2)].FullName } }
  if($p -and (Test-Path $p)){ [pscustomobject]@{id=$r.id;file=$p} }
}
$por=$Cols*$Filas; $mapa=New-Object System.Collections.Generic.List[string]
for($s=0;$s*$por -lt $items.Count;$s++){
  $bm=New-Object System.Drawing.Bitmap ($Cols*$Celda),($Filas*$Celda); $g=[System.Drawing.Graphics]::FromImage($bm); $g.Clear([System.Drawing.Color]::FromArgb(235,232,226)); $g.InterpolationMode='HighQualityBicubic'
  for($k=0;$k -lt $por -and ($s*$por+$k) -lt $items.Count;$k++){
    $it=$items[$s*$por+$k]; $x=($k % $Cols)*$Celda; $y=[math]::Floor($k/$Cols)*$Celda
    try{ $im=[System.Drawing.Image]::FromFile($it.file)
      # recorte centrado cuadrado (cover)
      $lado=[math]::Min($im.Width,$im.Height); $sx=[int](($im.Width-$lado)/2); $sy=[int](($im.Height-$lado)/2)
      $g.DrawImage($im,(New-Object System.Drawing.Rectangle $x,$y,$Celda,$Celda),(New-Object System.Drawing.Rectangle $sx,$sy,$lado,$lado),[System.Drawing.GraphicsUnit]::Pixel); $im.Dispose() } catch {}
    $mapa.Add("$($it.id),$s,$($k % $Cols),$([math]::Floor($k/$Cols))")
  }
  $g.Dispose(); $bm.Save((Join-Path $OutDir ('s{0:D2}.jpg' -f $s)),$jpg,$ep); $bm.Dispose()
}
[IO.File]::WriteAllLines((Join-Path $OutDir 'mapa.csv'),(@('id,hoja,col,fila')+$mapa),[Text.UTF8Encoding]::new($false))
"sprites: $s  miniaturas: $($mapa.Count)"
