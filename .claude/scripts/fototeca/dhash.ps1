# dHash: reduce el rectángulo a 9x8 en grises y compara cada píxel con el de su derecha.
function DHash([System.Drawing.Image]$img, [System.Drawing.Rectangle]$src) {
  $b = New-Object System.Drawing.Bitmap 9, 8
  $g = [System.Drawing.Graphics]::FromImage($b)
  $g.InterpolationMode = 'HighQualityBilinear'
  $g.DrawImage($img, (New-Object System.Drawing.Rectangle 0, 0, 9, 8), $src, [System.Drawing.GraphicsUnit]::Pixel)
  $g.Dispose()
  $v = [uint64]0
  for ($y = 0; $y -lt 8; $y++) {
    $prev = $null
    for ($x = 0; $x -lt 9; $x++) {
      $p = $b.GetPixel($x, $y); $l = 0.299*$p.R + 0.587*$p.G + 0.114*$p.B
      if ($x -gt 0) { $v = $v -shl 1; if ($l -gt $prev) { $v = $v -bor 1 } }
      $prev = $l
    }
  }
  $b.Dispose()
  return ('{0:x16}' -f $v)
}
# Cuadrado central de una imagen (para comparar contra las celdas cuadradas de los sprites).
function Cuadrado([System.Drawing.Image]$img, [double]$frac = 1.0) {
  $lado = [int]([math]::Min($img.Width, $img.Height) * $frac)
  return New-Object System.Drawing.Rectangle ([int](($img.Width - $lado)/2)), ([int](($img.Height - $lado)/2)), $lado, $lado
}
