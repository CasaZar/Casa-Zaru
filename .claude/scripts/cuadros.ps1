param([string]$Video,[string]$OutDir,[int]$N=4)
# Saca N cuadros de un video con WinRT (sin ffmpeg)
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | ? { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($op,[Type]$t){ $task=$asTask.MakeGenericMethod($t).Invoke($null,@($op)); $task.Wait(-1)|Out-Null; $task.Result }
[Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime]|Out-Null
[Windows.Media.Editing.MediaClip,Windows.Media.Editing,ContentType=WindowsRuntime]|Out-Null
[Windows.Media.Editing.MediaComposition,Windows.Media.Editing,ContentType=WindowsRuntime]|Out-Null
[Windows.Graphics.Imaging.ImageStream,Windows.Graphics.Imaging,ContentType=WindowsRuntime]|Out-Null
$file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($Video)) ([Windows.Storage.StorageFile])
$clip = Await ([Windows.Media.Editing.MediaClip]::CreateFromFileAsync($file)) ([Windows.Media.Editing.MediaClip])
$comp = New-Object Windows.Media.Editing.MediaComposition
$cl=$comp.Clips
try { ([System.Collections.Generic.ICollection[Windows.Media.Editing.MediaClip]]$cl).Add($clip) } catch { try { ([System.Collections.IList]$cl).Add($clip)|Out-Null } catch { [System.Collections.Generic.ICollection[Windows.Media.Editing.MediaClip]].GetMethod('Add').Invoke($cl,@($clip)) } }
if($comp.Duration.TotalSeconds -le 0){ throw "no se pudo agregar el clip" }
$dur = $clip.OriginalDuration.TotalSeconds
New-Item -ItemType Directory -Force $OutDir | Out-Null
$base=[IO.Path]::GetFileNameWithoutExtension($Video)
for($i=1;$i -le $N;$i++){
  $t=[TimeSpan]::FromSeconds($dur*$i/($N+1))
  $st = Await ($comp.GetThumbnailAsync($t,480,0,[Windows.Media.Editing.VideoFramePrecision]::NearestKeyFrame)) ([Windows.Graphics.Imaging.ImageStream])
  $s=[System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($st)
  $fs=[IO.File]::Create((Join-Path $OutDir ("{0}_{1}.jpg" -f $base,$i))); $s.CopyTo($fs); $fs.Close(); $s.Close()
}
"{0} | {1:N0} s | {2} cuadros" -f $base,$dur,$N
