param([string]$Pares="$env:LOCALAPPDATA\CasaZaru\fototeca\repetidas-utiles.csv",[string]$Out="$env:LOCALAPPDATA\CasaZaru\fototeca\pares-diferencia.csv")
# Para cada par candidato: diferencia media por píxel (0-255) entre las dos imágenes reducidas a 32x32 en color
# (cuadrado central). Repetidas de verdad dan poco; tablas distintas parecidas dan mucho.
Add-Type -AssemblyName System.Drawing
$P="$env:LOCALAPPDATA\CasaZaru\fototeca"
$spr="$env:LOCALAPPDATA\CasaZaru\fototeca\fototeca-local"
$pos=@{}; (Get-Content "$spr\datos.json" -Raw -Encoding UTF8 | ConvertFrom-Json).items | %{ $pos[$_.id]=$_ }
$hojas=@{}
function Chica($id){
  $b=New-Object System.Drawing.Bitmap 32,32; $g=[System.Drawing.Graphics]::FromImage($b); $g.InterpolationMode='HighQualityBilinear'
  if($id -match '^M(\d+)$' -and [int]$matches[1] -ge 2603){
    $f="$P\mini\$id.jpg"; if(-not (Test-Path $f)){ $f=(Get-ChildItem "$P\mini" -Filter "${id}_2.jpg" | select -First 1).FullName }
    $im=[System.Drawing.Image]::FromFile($f); $l=[math]::Min($im.Width,$im.Height)
    $g.DrawImage($im,(New-Object System.Drawing.Rectangle 0,0,32,32),(New-Object System.Drawing.Rectangle ([int](($im.Width-$l)/2)),([int](($im.Height-$l)/2)),$l,$l),[System.Drawing.GraphicsUnit]::Pixel); $im.Dispose()
  } else {
    $d=$pos[$id]; $k=[int]$d.s; if(-not $hojas[$k]){ $hojas[$k]=[System.Drawing.Image]::FromFile(("$spr\s{0:D2}.jpg" -f $k)) }
    $g.DrawImage($hojas[$k],(New-Object System.Drawing.Rectangle 0,0,32,32),(New-Object System.Drawing.Rectangle ([int]$d.x*280),([int]$d.y*280),280,280),[System.Drawing.GraphicsUnit]::Pixel)
  }
  $g.Dispose(); $b
}
$sal=New-Object System.Collections.Generic.List[string]; $sal.Add('id,repite_a,distancia,motivo,dif')
foreach($r in Import-Csv $Pares){
  $a=Chica $r.id; $b=Chica $r.repite_a; $s=0
  for($y=0;$y -lt 32;$y++){ for($x=0;$x -lt 32;$x++){ $c1=$a.GetPixel($x,$y); $c2=$b.GetPixel($x,$y); $s+=[math]::Abs($c1.R-$c2.R)+[math]::Abs($c1.G-$c2.G)+[math]::Abs($c1.B-$c2.B) } }
  $a.Dispose(); $b.Dispose()
  $sal.Add("$($r.id),$($r.repite_a),$($r.distancia),$($r.motivo),"+([math]::Round($s/3072,1)).ToString([Globalization.CultureInfo]::InvariantCulture))
}
[IO.File]::WriteAllLines($Out,$sal,[Text.UTF8Encoding]::new($false))
$t=Import-Csv $Out
foreach($c in 5,10,15,20,25,30){ "dif <= ${c}: $(@($t|?{[double]::Parse($_.dif,[Globalization.CultureInfo]::InvariantCulture) -le $c}).Count)" }
