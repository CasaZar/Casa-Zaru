param(
  [string]$Lista,          # csv: id,tipo,origen,fecha,imgs (rutas separadas por |)
  [string]$Modelo,
  [string]$Out,
  [int]$Grupo=9,
  [string]$Esfuerzo='',
  [switch]$Batch,          # arma y envía por Batch en vez de llamar directo
  [string]$Carpeta,        # para Batch: estado y crudos
  [int]$Lote=300,          # pedidos (grupos) por batch
  [string]$Guia="$PSScriptRoot\..\..\prompts\clasificador-guia.md",
  [string]$Refs="G:\Mi unidad\Casa Zaru\Biblioteca\_referencias-madera"
)
# Clasificación igual a la de la Fototeca: guía completa, todos los campos, hojas de referencia de madera
# (en caché) y varias fotos por pedido. Directo (para medir) o por Batch (mitad de precio). Retomable.
# La llave sale de ANTHROPIC_API_KEY (variable de usuario); nunca se imprime ni se escribe.
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
$key=[Environment]::GetEnvironmentVariable('ANTHROPIC_API_KEY','User'); if(-not $key){$key=$env:ANTHROPIC_API_KEY}
if(-not $key){ throw 'Falta ANTHROPIC_API_KEY' }
$H=@{'x-api-key'=$key;'anthropic-version'='2026-10-21'}
Add-Type -AssemblyName System.Web.Extensions
$ser=New-Object System.Web.Script.Serialization.JavaScriptSerializer; $ser.MaxJsonLength=[int]::MaxValue
$utf8=New-Object Text.UTF8Encoding $false
function B64($p){ [Convert]::ToBase64String([IO.File]::ReadAllBytes($p)) }

$sistema=[IO.File]::ReadAllText($Guia,[Text.Encoding]::UTF8)+@'


## Para este trabajo
Al inicio del mensaje van las hojas de referencia de madera, rotuladas por el equipo: úsalas para comparar color y veta.
Después vienen varias fotos o videos, cada uno precedido por su id, origen y fecha. Los videos traen varios cuadros en orden.
No hay ruta de carpeta como pista. Mucho puede NO ser de Casa Zaru (familia, viajes, comida, mascotas, comprobantes, memes): para eso producto "sin producto", uso "descartar", madera "no se distingue", calidad 1, descripcion "foto personal" o qué documento es, sin describir a las personas, etiquetas [].
Agrega a cada uno el campo "zaru":"sí|no|duda" (¿es material de Casa Zaru?).
Responde SOLO con una línea JSON por cada id, en el mismo orden, con todos los campos de la guía. Nada antes ni después, sin ```.
'@
$refBloques=New-Object System.Collections.ArrayList
foreach($dir in Get-ChildItem $Refs -Directory | sort Name){
  [void]$refBloques.Add(@{type='text';text="Referencia: $($dir.Name)"})
  [void]$refBloques.Add(@{type='image';source=@{type='base64';media_type='image/jpeg';data=(B64 "$($dir.FullName)\F001.jpg")}})
}
$refBloques[$refBloques.Count-1]['cache_control']=@{type='ephemeral'}

function Params($grupo){
  $c=New-Object System.Collections.ArrayList; foreach($x in $refBloques){ [void]$c.Add($x) }
  [void]$c.Add(@{type='text';text="--- A CLASIFICAR ($($grupo.Count)) ---"})
  foreach($f in $grupo){
    $imgs=@($f.imgs -split '\|' | ?{ $_ })
    $t="id: $($f.id) | origen: $($f.origen) | fecha: $($f.fecha) | $($f.tipo)"; if($f.tipo -eq 'video'){ $t+=" ($($imgs.Count) cuadros en orden)" }
    [void]$c.Add(@{type='text';text=$t})
    foreach($p in $imgs){ [void]$c.Add(@{type='image';source=@{type='base64';media_type='image/jpeg';data=(B64 $p)}}) }
  }
  $pr=@{model=$Modelo;max_tokens=(1500+700*$grupo.Count);system=$sistema;messages=@(@{role='user';content=$c.ToArray()})}
  if($Esfuerzo){ $pr['output_config']=@{effort=$Esfuerzo} }
  $pr
}
function Guardar($ids,$msg){
  $u=$msg['usage']; $tok=@{in=$u['input_tokens'];out=$u['output_tokens'];cw=$u['cache_creation_input_tokens'];cr=$u['cache_read_input_tokens'];n=$ids.Count}
  $t=(@($msg['content']) | ?{ $_['type'] -eq 'text' } | %{ $_['text'] }) -join "`n"
  $vistos=@{}
  foreach($ln in ($t -split "`n")){ $ln=$ln.Trim(); if(-not $ln.StartsWith('{')){continue}
    try{ $o=$ser.DeserializeObject($ln) }catch{ continue }
    if(-not ($ids -contains $o['id'])){ continue }
    if(-not $vistos.Count){ $o['_tok']=$tok }; $vistos[$o['id']]=1
    [IO.File]::AppendAllText($Out,$ser.Serialize($o)+"`n",$utf8) }
  foreach($i in $ids){ if(-not $vistos[$i]){ [IO.File]::AppendAllText($Out,$ser.Serialize(@{id=$i;_falta=1})+"`n",$utf8) } }
  if(-not $vistos.Count){ [IO.File]::AppendAllText($Out,$ser.Serialize(@{id='_grupo';_tok=$tok})+"`n",$utf8) }
}

$hechos=@{}; if(Test-Path $Out){ Get-Content $Out -Encoding UTF8 | %{ try{ $hechos[($ser.DeserializeObject($_))['id']]=1 }catch{} } }
$filas=@(Import-Csv $Lista | ?{ -not $hechos[$_.id] })
$grupos=@(); for($i=0;$i -lt $filas.Count;$i+=$Grupo){ $grupos+=,@($filas[$i..([math]::Min($filas.Count,$i+$Grupo)-1)]) }
"Pendientes: $($filas.Count) en $($grupos.Count) pedidos  modelo: $Modelo  batch: $Batch"

if(-not $Batch){
  $k=0
  foreach($g in $grupos){ $k++
    $json=$ser.Serialize((Params $g)); $intento=0
    while($true){ try{
        $wr=Invoke-WebRequest -Uri 'https://api.anthropic.com/v1/messages' -Method Post -UseBasicParsing -ContentType 'application/json; charset=utf-8' -Headers $H -Body $utf8.GetBytes($json)
        $sr=New-Object IO.StreamReader($wr.RawContentStream,[Text.Encoding]::UTF8); $raw=$sr.ReadToEnd(); break
      } catch { $intento++; if($intento -ge 4){ "ERROR pedido $k : $($_.Exception.Message)"; $raw=$null; break }; Start-Sleep (10*$intento) } }
    if($raw){ Guardar @($g | % id) ($ser.DeserializeObject($raw)) }
    if($k % 5 -eq 0){ "$k / $($grupos.Count)  $(Get-Date -f HH:mm)" }
  }
  "FIN $(Get-Date -f HH:mm)"; return
}

# ---- Batch ----
New-Item -ItemType Directory -Force $Carpeta | Out-Null
$estado=Join-Path $Carpeta 'lotes.csv'; $mapa=Join-Path $Carpeta 'grupos.csv'
if(-not (Test-Path $estado)){
  # numerar grupos una sola vez, para poder retomar
  $n=0; $grupos | %{ $n++; [pscustomobject]@{g="g$n";ids=(($_ | % id) -join ' ')} } | Export-Csv $mapa -NoTypeInformation -Encoding UTF8
}
$gm=@{}; Import-Csv $mapa | %{ $gm[$_.g]=@($_.ids -split ' ') }
$filaPorId=@{}; Import-Csv $Lista | %{ $filaPorId[$_.id]=$_ }
$orden=@(Import-Csv $mapa | % g)
$lotes=@(); if(Test-Path $estado){ $lotes=@(Import-Csv $estado) }
$nL=[math]::Ceiling($orden.Count/$Lote)
for($k=$lotes.Count;$k -lt $nL;$k++){
  $parte=$orden[($k*$Lote)..([math]::Min($orden.Count,($k+1)*$Lote)-1)]
  $sb=New-Object Text.StringBuilder; [void]$sb.Append('{"requests":[')
  $j=0; foreach($g in $parte){ if($j++){[void]$sb.Append(',')}; $grp=@($gm[$g] | %{ $filaPorId[$_] }); [void]$sb.Append($ser.Serialize(@{custom_id=[string]$g;params=(Params $grp)})) }
  [void]$sb.Append(']}'); $bytes=$utf8.GetBytes($sb.ToString()); $sb=$null
  "lote $($k+1)/$nL : $($parte.Count) pedidos, $([math]::Round($bytes.Length/1MB,1)) MB"
  if($bytes.Length -gt 250MB){ throw 'lote demasiado grande; bajar -Lote' }
  $r=Invoke-RestMethod -Uri 'https://api.anthropic.com/v1/messages/batches' -Method Post -Headers $H -ContentType 'application/json; charset=utf-8' -Body $bytes
  $bytes=$null; [GC]::Collect()
  [pscustomobject]@{lote=$k+1;batch_id=$r.id;n=$parte.Count;estado='enviado'} | Export-Csv $estado -NoTypeInformation -Encoding UTF8 -Append
  "  enviado: $($r.id)"
}
$lotes=@(Import-Csv $estado)
while(@($lotes | ?{ $_.estado -ne 'bajado' }).Count){
  foreach($l in @($lotes | ?{ $_.estado -ne 'bajado' })){
    $b=Invoke-RestMethod -Uri "https://api.anthropic.com/v1/messages/batches/$($l.batch_id)" -Headers $H
    if($b.processing_status -ne 'ended'){ continue }
    $crudo=Join-Path $Carpeta "crudo-$($l.lote).jsonl"
    $wr=Invoke-WebRequest -Uri $b.results_url -Headers $H -UseBasicParsing
    $sr=New-Object IO.StreamReader($wr.RawContentStream,[Text.Encoding]::UTF8); [IO.File]::WriteAllText($crudo,$sr.ReadToEnd(),$utf8)
    $mal=0
    foreach($ln in [IO.File]::ReadAllLines($crudo,[Text.Encoding]::UTF8)){ if(-not $ln.Trim()){continue}
      $x=$ser.DeserializeObject($ln); $ids=$gm[$x['custom_id']]
      if($x['result']['type'] -eq 'succeeded'){ Guardar $ids $x['result']['message'] } else { $mal++; foreach($i in $ids){ [IO.File]::AppendAllText($Out,$ser.Serialize(@{id=$i;_error=$x['result']['type']})+"`n",$utf8) } } }
    $l.estado='bajado'; $lotes | Export-Csv $estado -NoTypeInformation -Encoding UTF8
    "lote $($l.lote) bajado ($mal pedidos con error)  $(Get-Date -f HH:mm)"
  }
  if(@($lotes | ?{ $_.estado -ne 'bajado' }).Count){ Start-Sleep 120 }
}
"FIN $(Get-Date -f HH:mm)"
