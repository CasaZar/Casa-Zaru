param([string]$Lista="$env:LOCALAPPDATA\CasaZaru\fototeca\lista-pc.csv",[string]$OutDir="$env:LOCALAPPDATA\CasaZaru\fototeca\mini",[int]$Lado=512,[int]$Cuadros=4)
# Miniaturas de 512 px (WinRT: lee HEIC) y 4 cuadros por video, directo desde las rutas del PC. Retomable vía _log.csv.
Add-Type -AssemblyName System.Runtime.WindowsRuntime
Add-Type -AssemblyName System.Drawing
$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | ? { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($op,[Type]$t){ $task=$asTask.MakeGenericMethod($t).Invoke($null,@($op)); $task.Wait(-1)|Out-Null; $task.Result }
[Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime]|Out-Null
[Windows.Storage.FileProperties.StorageItemThumbnail,Windows.Storage,ContentType=WindowsRuntime]|Out-Null
[Windows.Media.Editing.MediaClip,Windows.Media.Editing,ContentType=WindowsRuntime]|Out-Null
[Windows.Media.Editing.MediaComposition,Windows.Media.Editing,ContentType=WindowsRuntime]|Out-Null
[Windows.Graphics.Imaging.ImageStream,Windows.Graphics.Imaging,ContentType=WindowsRuntime]|Out-Null
$jpg=[System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders()|?{$_.MimeType -eq 'image/jpeg'}
$ep=New-Object System.Drawing.Imaging.EncoderParameters 1; $ep.Param[0]=New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality,[long]80)
function GuardarAchicado([IO.Stream]$s,[string]$dest,[int]$lado){
  $im=[System.Drawing.Image]::FromStream($s)
  $k=[math]::Min(1.0,$lado/[math]::Max($im.Width,$im.Height)); $w=[int]($im.Width*$k); $h=[int]($im.Height*$k)
  $bm=New-Object System.Drawing.Bitmap $w,$h; $g=[System.Drawing.Graphics]::FromImage($bm); $g.InterpolationMode='HighQualityBicubic'; $g.DrawImage($im,0,0,$w,$h); $g.Dispose()
  $bm.Save($dest,$jpg,$ep); $bm.Dispose(); $im.Dispose()
}
New-Item -ItemType Directory -Force $OutDir | Out-Null
$log=Join-Path $OutDir '_log.csv'
if(-not (Test-Path $log)){ 'id,estado,duracion_s,ancho,alto,nota' | Out-File $log -Encoding utf8 }
$hechos=@{}; Import-Csv $log | % { $hechos[$_.id]=1 }
$rows=@(Import-Csv $Lista | ? { -not $hechos[$_.id] })
"Pendientes: $($rows.Count)"; $i=0
foreach($r in $rows){
  $i++; $dur='';$an='';$al='';$nota=''
  try{
    $file=Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($r.ruta)) ([Windows.Storage.StorageFile])
    if($r.tipo -eq 'foto'){
      $th=Await ($file.GetScaledImageAsThumbnailAsync([Windows.Storage.FileProperties.ThumbnailMode]::SingleItem,[uint32]$Lado,[Windows.Storage.FileProperties.ThumbnailOptions]::ResizeThumbnail)) ([Windows.Storage.FileProperties.StorageItemThumbnail])
      $an=$th.OriginalWidth; $al=$th.OriginalHeight
      $s=[System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($th); GuardarAchicado $s (Join-Path $OutDir "$($r.id).jpg") $Lado; $s.Close(); $th.Dispose()
    } else {
      $clip=Await ([Windows.Media.Editing.MediaClip]::CreateFromFileAsync($file)) ([Windows.Media.Editing.MediaClip])
      $comp=New-Object Windows.Media.Editing.MediaComposition; $cl=$comp.Clips
      try { ([System.Collections.IList]$cl).Add($clip)|Out-Null } catch { [System.Collections.Generic.ICollection[Windows.Media.Editing.MediaClip]].GetMethod('Add').Invoke($cl,@($clip)) }
      if($comp.Duration.TotalSeconds -le 0){ throw 'no se pudo agregar el clip' }
      $d=$clip.OriginalDuration.TotalSeconds; $dur=[int]$d
      $n= if($d -gt 60){$Cuadros+2}else{$Cuadros}
      for($k=1;$k -le $n;$k++){
        $st=Await ($comp.GetThumbnailAsync([TimeSpan]::FromSeconds($d*$k/($n+1)),[int]$Lado,0,[Windows.Media.Editing.VideoFramePrecision]::NearestKeyFrame)) ([Windows.Graphics.Imaging.ImageStream])
        $s=[System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($st)
        if($k -eq 1){ $im=[System.Drawing.Image]::FromStream($s); $an=$im.Width; $al=$im.Height; $im.Dispose(); $s.Position=0 }
        GuardarAchicado $s (Join-Path $OutDir ("{0}_{1}.jpg" -f $r.id,$k)) $Lado; $s.Close()
      }
      $comp=$null; $clip=$null
    }
    $est='ok'
  } catch { $est='error'; $m=$_.Exception.Message -replace '[\r\n,]',' '; $nota=$m.Substring(0,[math]::Min(120,$m.Length)) }
  $file=$null
  if($i % 50 -eq 0){ [GC]::Collect() }
  ('{0},{1},{2},{3},{4},{5}' -f $r.id,$est,$dur,$an,$al,$nota) | Out-File $log -Append -Encoding utf8
  if($i % 250 -eq 0){ "$i / $($rows.Count)  $(Get-Date -f HH:mm)" }
}
"FIN $(Get-Date -f HH:mm)"
