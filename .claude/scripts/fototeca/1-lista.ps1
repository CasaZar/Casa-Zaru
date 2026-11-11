param(
  [string]$Out = "$env:LOCALAPPDATA\CasaZaru\fototeca\lista-pc.csv",
  [string]$Wt  = "$env:LOCALAPPDATA\CasaZaru\fototeca\wt",
  [int]$Desde  = 2603
)
# Lista de fotos y videos del PC que NO están en el Drive (mismo tamaño en bytes = mismo archivo).
# Saca capturas, boletas de bencina, créditos y documentos; deja un solo archivo por tamaño.
# Extrae a $Wt los WeTransfer (.zip) que estén en Descargas (solo lee el zip, no lo borra).
$ErrorActionPreference = 'Stop'
$ext = '\.(jpe?g|png|heic|webp|mp4|mov|m4v|avi)$'
Add-Type -AssemblyName System.IO.Compression.FileSystem
foreach ($n in @(Get-ChildItem "$env:USERPROFILE\Downloads" -Filter 'wetransfer_*.zip' | % Name)) {
  $d = Join-Path $Wt ([IO.Path]::GetFileNameWithoutExtension($n))
  if (-not (Test-Path $d)) { [IO.Compression.ZipFile]::ExtractToDirectory((Join-Path "$env:USERPROFILE\Downloads" $n), $d) }
}
$drive = @{}
Get-ChildItem 'G:\Mi unidad' -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $ext } | ForEach-Object { $drive["$($_.Length)"] = 1 }
$vistos = @{}; $filas = New-Object System.Collections.ArrayList; $id = $Desde
$raices = "$env:USERPROFILE\OneDrive\Desktop\Casa Zaru", $Wt, "$env:USERPROFILE\Downloads",
          "$env:USERPROFILE\OneDrive\Desktop\Respaldos", "$env:USERPROFILE\OneDrive\Pictures"
foreach ($r in $raices) {
  Get-ChildItem $r -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match $ext -and $_.FullName -notmatch '(?i)screenshot|captura|Grabaci|gastos bencina|\\CREDITO\\|\\documentos\\' -and $_.Length -gt 50KB } |
    Sort-Object FullName | ForEach-Object {
      $k = "$($_.Length)"
      if ($drive.ContainsKey($k) -or $vistos.ContainsKey($k)) { return }
      $vistos[$k] = 1
      $tipo = if ($_.Extension -match '(?i)mp4|mov|m4v|avi') { 'video' } else { 'foto' }
      [void]$filas.Add([pscustomobject]@{ id = ('M{0:D4}' -f $id); tipo = $tipo; ruta = $_.FullName; bytes = $_.Length; fecha = $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm') })
      $id++
    }
}
$filas | Export-Csv $Out -NoTypeInformation -Encoding UTF8
"lista: $($filas.Count) ($(@($filas | ? tipo -eq 'video').Count) videos)  ids M$Desde..M$($id-1)"
