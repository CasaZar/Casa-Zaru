param(
  [string]$Base = "$env:LOCALAPPDATA\CasaZaru\fototeca\fototeca-local",
  [string]$Out  = "$env:LOCALAPPDATA\CasaZaru\fototeca\huellas-fototeca.csv"
)
# Huella (dHash 8x8 = 64 bits, en hex) de cada celda de los sprites de la Fototeca.
# h1 = celda entera; h2 = el 80 % central (Instagram suele recortar los bordes).
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
. "$PSScriptRoot\dhash.ps1"
$j = Get-Content "$Base\datos.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$cel = [int]$j.meta.celda
$porHoja = $j.items | Group-Object s
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('id,h1,h2')
foreach ($g in $porHoja) {
  $bmp = [System.Drawing.Bitmap]::FromFile(("$Base\s{0:D2}.jpg" -f [int]$g.Name))
  foreach ($d in $g.Group) {
    $r1 = New-Object System.Drawing.Rectangle ([int]$d.x * $cel), ([int]$d.y * $cel), $cel, $cel
    $m = [int]($cel * 0.1)
    $r2 = New-Object System.Drawing.Rectangle ([int]$d.x * $cel + $m), ([int]$d.y * $cel + $m), ($cel - 2*$m), ($cel - 2*$m)
    [void]$sb.AppendLine("$($d.id),$(DHash $bmp $r1),$(DHash $bmp $r2)")
  }
  $bmp.Dispose()
}
[IO.File]::WriteAllText($Out, $sb.ToString(), [Text.UTF8Encoding]::new($false))
"huellas: $($j.items.Count) -> $Out"
