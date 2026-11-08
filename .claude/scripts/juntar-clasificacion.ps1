param([string]$W,[string]$SpritesDir)
# Junta inventario + resultados de los lotes -> clasificacion.csv (planilla) y datos.json (app de búsqueda).
$inv=Import-Csv "$W\inventario.csv"
$res=@{}; Get-ChildItem "$W\lotes" -Directory | % { $f="$($_.FullName)\resultado.jsonl"
  if(Test-Path $f){ Get-Content $f -Encoding UTF8 | ? { $_.Trim() } | % { try{ $o=$_|ConvertFrom-Json; $res[$o.id]=$o }catch{ Write-Warning "JSON malo en $($_.Name)" } } } }
# la guía sumó «pino (por confirmar)» a mitad de camino: igualar lo que se anotó antes solo en la descripción
foreach($o in $res.Values){ if($o.madera -eq 'no se distingue' -and "$($o.descripcion) $($o.etiquetas)" -match '\bpino\b'){ $o.madera='pino (por confirmar)'; $o.confianza='baja' } }
# marca IA: la revisión dedicada (lotes\*\ia.jsonl) manda; si no, el campo del clasificador o la etiqueta «imagen ia»
$iaRev=@{}; Get-ChildItem "$W\lotes" -Directory | % { $f="$($_.FullName)\ia.jsonl"; if(Test-Path $f){ Get-Content $f -Encoding UTF8 | ? { $_.Trim() } | % { $o=$_|ConvertFrom-Json; $iaRev[$o.id]=$o } } }
function MarcaIA($id,$c){ if($iaRev[$id]){ return $iaRev[$id].ia }; if($c.ia){ return $c.ia }; if(@($c.etiquetas) -contains 'imagen ia'){ return 'sí' }; if($c){ 'no' }else{ '' } }
$log=@{}; foreach($l in 'fotos','videos'){ Import-Csv "$W\$l\_log.csv" | % { $log[$_.id]=$_ } }
# copias con otro nombre: mismo tamaño y mismo nombre sin " (n)"
$base=@{}; foreach($r in $inv){ $k=(($r.nombre -replace ' \(\d+\)(?=\.[^.]+$)','').ToLower())+'|'+$r.mb; if(-not $base[$k]){ $base[$k]=$r.id } ; $r | Add-Member copia_de ($(if($base[$k] -ne $r.id){$base[$k]}else{''})) -Force }
$map=@{}; if($SpritesDir -and (Test-Path "$SpritesDir\mapa.csv")){ Import-Csv "$SpritesDir\mapa.csv" | % { $map[$_.id]=$_ } }
$filas=New-Object System.Collections.Generic.List[object]; $items=New-Object System.Collections.Generic.List[object]
foreach($r in $inv){
  $c=$res[$r.id]; $l=$log[$r.id]
  $uso= if($r.copia_de){'descartar'}elseif($c){$c.uso}else{''}
  $fila=[ordered]@{
    id=$r.id; tipo=$r.tipo; producto=$c.producto; madera=$c.madera; confianza=$c.confianza; etapa=$c.etapa; ambiente=$c.ambiente
    forma=$c.forma; uso=$uso; calidad=$c.calidad; ia=(MarcaIA $r.id $c); ia_nota=$iaRev[$r.id].nota; orientacion=$c.orientacion; personas=$c.personas; texto_encima=$c.texto_encima
    descripcion=$c.descripcion; gancho=$c.gancho; que_pasa=$c.que_pasa; tipo_video=$c.tipo_video; etiquetas=(@($c.etiquetas) -join ', ')
    duracion_s=$l.duracion_s; copia_de=$r.copia_de; nombre=$r.nombre; carpeta=(Split-Path $r.ruta -Parent); fecha=$r.fecha; mb=$r.mb
    link='https://drive.google.com/file/d/'+$r.drive_id+'/view'; drive_id=$r.drive_id; otras_ubicaciones=$r.copias
    clasificado= if($c){'sí'}else{'no'} }
  $filas.Add([pscustomobject]$fila)
  $s=$map[$r.id]
  if($c -and $s -and -not $r.copia_de){
    $items.Add([ordered]@{ id=$r.id; tipo=$r.tipo; producto=$c.producto; madera=$c.madera; confianza=$c.confianza; etapa=$c.etapa; ambiente=$c.ambiente
      forma=$c.forma; uso=$c.uso; calidad=[int]$c.calidad; ia=(MarcaIA $r.id $c); ia_nota=$iaRev[$r.id].nota; orientacion=$c.orientacion; personas=[bool]$c.personas; descripcion=$c.descripcion
      gancho=$c.gancho; que_pasa=$c.que_pasa; tipo_video=$c.tipo_video; etiquetas=@($c.etiquetas); dur=[int]("0"+$l.duracion_s)
      nombre=$r.nombre; ruta=(Split-Path $r.ruta -Parent); drive=$r.drive_id; s=[int]$s.hoja; x=[int]$s.col; y=[int]$s.fila })
  }
}
$filas | Export-Csv "$W\clasificacion.csv" -NoTypeInformation -Encoding UTF8
$meta=[ordered]@{ celda=280; cols=10; filas=10; generado=(Get-Date -f 'yyyy-MM-dd HH:mm')
  sugerencias=@('isla castaño','peldaños','cubremuro','mesa de centro','vanitorio','puerta','proceso aceite','quincho') }
$json=[ordered]@{ meta=$meta; items=$items } | ConvertTo-Json -Depth 5 -Compress
if($SpritesDir){ [IO.File]::WriteAllText("$SpritesDir\..\datos.json",$json,[Text.UTF8Encoding]::new($false)) }
"filas: $($filas.Count)  clasificadas: $(($filas|?{$_.clasificado -eq 'sí'}).Count)  copias por nombre: $(($filas|?{$_.copia_de}).Count)  en la app: $($items.Count)"
