param([double]$Max=22,[string]$Out="$env:LOCALAPPDATA\CasaZaru\fototeca\rafagas.csv")
# Tomas casi iguales entre las nuevas a publicar (ráfagas): compara todas contra todas en 24x24 a color,
# con el cuadrado central y con la imagen entera estirada; se queda con la menor diferencia media por canal.
$ErrorActionPreference='Stop'
$P="$env:LOCALAPPDATA\CasaZaru\fototeca"
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
public static class Rf {
  public static double D(byte[] a, byte[] b){ long s=0; for(int i=0;i<a.Length;i++){ int d=a[i]-b[i]; s+= d<0?-d:d; } return (double)s/a.Length; }
}
'@
$j=Get-Content "$P\publicar\datos-2.json" -Raw -Encoding UTF8 | ConvertFrom-Json
function Vec($f,[bool]$cuad){
  $im=[System.Drawing.Image]::FromFile($f); $b=New-Object System.Drawing.Bitmap 24,24; $g=[System.Drawing.Graphics]::FromImage($b); $g.InterpolationMode='HighQualityBilinear'
  if($cuad){ $l=[math]::Min($im.Width,$im.Height); $src=New-Object System.Drawing.Rectangle ([int](($im.Width-$l)/2)),([int](($im.Height-$l)/2)),$l,$l } else { $src=New-Object System.Drawing.Rectangle 0,0,$im.Width,$im.Height }
  $g.DrawImage($im,(New-Object System.Drawing.Rectangle 0,0,24,24),$src,[System.Drawing.GraphicsUnit]::Pixel); $g.Dispose(); $im.Dispose()
  $v=New-Object byte[] (24*24*3); $k=0
  for($y=0;$y -lt 24;$y++){ for($x=0;$x -lt 24;$x++){ $c=$b.GetPixel($x,$y); $v[$k++]=$c.R; $v[$k++]=$c.G; $v[$k++]=$c.B } }
  $b.Dispose(); ,$v
}
$ids=@(); $va=@(); $vb=@()
foreach($d in $j.items){
  $f="$P\mini\$($d.id).jpg"; if(-not (Test-Path $f)){ $cu=@(Get-ChildItem "$P\mini" -Filter "$($d.id)_*.jpg" | Sort-Object Name); $f=$cu[[math]::Floor(($cu.Count-1)/2)].FullName }
  $ids+=$d.id; $va+=,(Vec $f $true); $vb+=,(Vec $f $false)
}
$sal=New-Object System.Collections.Generic.List[string]; $sal.Add('a,b,dif')
for($i=0;$i -lt $ids.Count;$i++){ for($k=$i+1;$k -lt $ids.Count;$k++){
  $d=[math]::Min([Rf]::D($va[$i],$va[$k]),[Rf]::D($vb[$i],$vb[$k]))
  if($d -le $Max){ $sal.Add("$($ids[$i]),$($ids[$k]),"+([math]::Round($d,1)).ToString([Globalization.CultureInfo]::InvariantCulture)) } } }
[IO.File]::WriteAllLines($Out,$sal,[Text.UTF8Encoding]::new($false))
"pares con dif <= ${Max}: $($sal.Count-1)"
