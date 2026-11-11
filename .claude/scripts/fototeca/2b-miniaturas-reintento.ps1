param([string]$Lista="$env:LOCALAPPDATA\CasaZaru\fototeca\lista-pc.csv",[string]$OutDir="$env:LOCALAPPDATA\CasaZaru\fototeca\mini",[int]$Lado=512,[int]$Icono=13704)
# Rehace las miniaturas que salieron como ícono genérico (archivos de OneDrive) y las que dieron error,
# decodificando el archivo entero con WinRT BitmapDecoder (lee JPG, PNG y HEIC, aplica la orientación EXIF).
Add-Type -AssemblyName System.Runtime.WindowsRuntime
Add-Type -AssemblyName System.Drawing
$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | ? { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($op,[Type]$t){ $task=$asTask.MakeGenericMethod($t).Invoke($null,@($op)); $task.Wait(-1)|Out-Null; $task.Result }
[Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime]|Out-Null
[Windows.Storage.Streams.IRandomAccessStreamWithContentType,Windows.Storage.Streams,ContentType=WindowsRuntime]|Out-Null
[Windows.Graphics.Imaging.BitmapDecoder,Windows.Graphics.Imaging,ContentType=WindowsRuntime]|Out-Null
[Windows.Graphics.Imaging.SoftwareBitmap,Windows.Graphics.Imaging,ContentType=WindowsRuntime]|Out-Null
[Windows.Graphics.Imaging.BitmapEncoder,Windows.Graphics.Imaging,ContentType=WindowsRuntime]|Out-Null
[Windows.Storage.Streams.InMemoryRandomAccessStream,Windows.Storage.Streams,ContentType=WindowsRuntime]|Out-Null
$asAct = ([System.WindowsRuntimeSystemExtensions].GetMethods() | ? { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction' })[0]
function AwaitA($op){ $asAct.Invoke($null,@($op)).Wait(-1)|Out-Null }
$jpg=[System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders()|?{$_.MimeType -eq 'image/jpeg'}
$ep=New-Object System.Drawing.Imaging.EncoderParameters 1; $ep.Param[0]=New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality,[long]80)
$log=Join-Path $OutDir '_log.csv'; $lg=@{}; Import-Csv $log | %{ $lg[$_.id]=$_ }
$rows=@(Import-Csv $Lista | ?{ $_.tipo -eq 'foto' -and ( $lg[$_.id].estado -ne 'ok' -or (Get-Item "$OutDir\$($_.id).jpg" -EA SilentlyContinue).Length -eq $Icono ) })
"A rehacer: $($rows.Count)"; $i=0; $nuevo=@{}
foreach($r in $rows){
  $i++
  try{
    $file=Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($r.ruta)) ([Windows.Storage.StorageFile])
    $st=Await ($file.OpenReadAsync()) ([Windows.Storage.Streams.IRandomAccessStreamWithContentType])
    $dec=Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($st)) ([Windows.Graphics.Imaging.BitmapDecoder])
    $w=$dec.OrientedPixelWidth; $h=$dec.OrientedPixelHeight; $k=[math]::Min(1.0,$Lado/[math]::Max($w,$h))
    $tr=New-Object Windows.Graphics.Imaging.BitmapTransform
    # ScaledWidth/Height se aplican antes de rotar: van en las dimensiones sin orientar
    $tr.ScaledWidth=[uint32][math]::Max(1,[int]($dec.PixelWidth*$k)); $tr.ScaledHeight=[uint32][math]::Max(1,[int]($dec.PixelHeight*$k)); $tr.InterpolationMode='Fant'
    $sb=Await ($dec.GetSoftwareBitmapAsync([Windows.Graphics.Imaging.BitmapPixelFormat]::Bgra8,[Windows.Graphics.Imaging.BitmapAlphaMode]::Premultiplied,$tr,[Windows.Graphics.Imaging.ExifOrientationMode]::RespectExifOrientation,[Windows.Graphics.Imaging.ColorManagementMode]::ColorManageToSRgb)) ([Windows.Graphics.Imaging.SoftwareBitmap])
    $ms=New-Object Windows.Storage.Streams.InMemoryRandomAccessStream
    $enc=Await ([Windows.Graphics.Imaging.BitmapEncoder]::CreateAsync([Windows.Graphics.Imaging.BitmapEncoder]::BmpEncoderId,$ms)) ([Windows.Graphics.Imaging.BitmapEncoder])
    $enc.SetSoftwareBitmap($sb); AwaitA ($enc.FlushAsync())
    $s=[System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($ms.GetInputStreamAt(0))
    $im=[System.Drawing.Image]::FromStream($s); $im.Save("$OutDir\$($r.id).jpg",$jpg,$ep); $im.Dispose(); $s.Close()
    $sb.Dispose(); $st.Dispose(); $ms.Dispose()
    $nuevo[$r.id]="$($r.id),ok,,$w,$h,reintento"
  } catch { $m=$_.Exception.Message -replace '[\r\n,]',' '; $nuevo[$r.id]="$($r.id),error,,,,reintento: $($m.Substring(0,[math]::Min(100,$m.Length)))" }
  if($i % 50 -eq 0){ [GC]::Collect() }
  if($i % 250 -eq 0){ "$i / $($rows.Count)  $(Get-Date -f HH:mm)" }
}
# reescribe el log con los resultados nuevos
$sal=New-Object System.Collections.Generic.List[string]; $sal.Add('id,estado,duracion_s,ancho,alto,nota')
foreach($x in Import-Csv $log){ if($nuevo[$x.id]){ $sal.Add($nuevo[$x.id]) } else { $sal.Add("$($x.id),$($x.estado),$($x.duracion_s),$($x.ancho),$($x.alto),$($x.nota)") } }
[IO.File]::WriteAllLines($log,$sal,[Text.UTF8Encoding]::new($false))
"FIN $(Get-Date -f HH:mm)  ok: $(@($nuevo.Values|?{$_ -like '*,ok,*'}).Count)  error: $(@($nuevo.Values|?{$_ -like '*,error,*'}).Count)"
