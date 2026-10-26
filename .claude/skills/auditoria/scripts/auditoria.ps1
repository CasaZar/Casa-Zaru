# /auditoria — auditoría semanal de confiabilidad de Casa Zaru. SOLO LECTURA.
# No inserta, no modifica, no borra nada en ninguna base. Informe en Drive (Informes Gestion).
# Requiere: %USERPROFILE%\.casazaru\config.ps1 ($SB_URL, $SB_KEY del Cotizador), Drive montado en G:.
param([switch]$SinDrive)   # -SinDrive: no copia el informe a Drive (lo deja en %TEMP%)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$ua   = 'casazaru-auditoria/1.0'
$hoy  = Get-Date
$repo = "$env:USERPROFILE\Casa Zaru - Claude"
$repoCot = "$env:USERPROFILE\Cotizador"
$drive = 'G:\Mi unidad\Casa Zaru'
$dirG  = "$drive\Boletas y Facturas - Ventas 2026\Respaldos Gestion"
$dirC  = "$drive\Boletas y Facturas - Ventas 2026\Respaldos Cotizador"   # desde 26-10 lo deja la Edge Function respaldo-cotizador; la tarea local sigue en $drive\Respaldos Cotizador
$dirInf = "$drive\Informes Gestion"
$urlG = 'https://padnttpgzuotxeipjrry.supabase.co'
$tmp = Join-Path $env:TEMP ('auditoria-' + $hoy.ToString('yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force $tmp | Out-Null

$SEM_V='🟢'; $SEM_A='🟡'; $SEM_R='🔴'; $SEM_B='⚪'
$filas = New-Object System.Collections.ArrayList   # filas del semáforo
$det   = New-Object System.Collections.ArrayList   # detalle
$prop  = New-Object System.Collections.ArrayList   # propuestas por rojo
function Sem($p,$g,$c){ [void]$filas.Add("| $p | $g | $c |") }
function Det($t){ [void]$det.Add($t) }
function Prop($t){ [void]$prop.Add("- $t") }
function Http($m,$u,$hdr,$body){
  $args=@{Uri=$u;Method=$m;Headers=$hdr;UseBasicParsing=$true;UserAgent=$ua;TimeoutSec=40}
  if($body -ne $null){ $args.Body=$body; $args.ContentType='application/json' }
  try { $r=Invoke-WebRequest @args; return @{code=[int]$r.StatusCode;body=[string]$r.Content;hdr=$r.Headers} }
  catch { $resp=$_.Exception.Response; $code=0; $txt=$_.Exception.Message
    if($resp){ $code=[int]$resp.StatusCode.value__; try{ $txt=(New-Object IO.StreamReader($resp.GetResponseStream())).ReadToEnd() }catch{} }
    return @{code=$code;body=$txt;hdr=$null} } }
function Tablas($obj){ return ,@($obj.PSObject.Properties.Name | Sort-Object) }
function Filas($obj,$n){ return ,@($obj.PSObject.Properties[$n].Value) }
function Horas($f){ return [math]::Round(($hoy - $f.LastWriteTime).TotalHours,1) }

# ── llaves ────────────────────────────────────────────────────────────────────
$cfg="$env:USERPROFILE\.casazaru\config.ps1"; $SB_URL=$null; $SB_KEY=$null
if(Test-Path $cfg){ . $cfg }
$anonG=$null; $m=Select-String -Path "$repo\index.html" -Pattern "WASABIL_ANON_KEY='(eyJ[A-Za-z0-9._-]+)'" | select -First 1
if($m){ $anonG=$m.Matches[0].Groups[1].Value }
$anonC=$null; $m=Select-String -Path "$repoCot\index.html" -Pattern 'sb_publishable_[A-Za-z0-9_-]+' | select -First 1
if($m){ $anonC=$m.Matches[0].Value }
$hG=@{apikey=$anonG;Authorization="Bearer $anonG"}
$hC=@{apikey=$anonC;Authorization="Bearer $anonC"}
$hS=@{apikey=$SB_KEY;Authorization="Bearer $SB_KEY"}

Write-Output "Auditoría de confiabilidad · $($hoy.ToString('dd-MM-yyyy HH:mm'))"

# ── 1. Respaldos ──────────────────────────────────────────────────────────────
Write-Output '1/8 respaldos…'
$JG=$null; $JC=$null; $sG="$SEM_B sin acceso a Drive"; $sC="$SEM_B sin acceso a Drive"; $rG="$SEM_B"; $rC="$SEM_B"
if(Test-Path $dirG){
  $fs=@(Get-ChildItem "$dirG\respaldo-gestion-*.json" | sort LastWriteTime -desc)
  if($fs.Count){ $f=$fs[0]; Copy-Item $f.FullName "$tmp\gestion.json"
    $JG=([string](Get-Content -Raw -Encoding UTF8 "$tmp\gestion.json") | ConvertFrom-Json)
    $h=Horas $f; $kb=[math]::Round($f.Length/1KB); $nt=(Tablas $JG.tablas).Count
    $sG = $(if($h -le 36){$SEM_V}else{$SEM_R}) + " $($f.LastWriteTime.ToString('dd-MM HH:mm')), $kb KB, $nt tablas; generado $($JG.generado)"
    $rG = $(if($fs.Count -ge 28){$SEM_A}else{$SEM_R}) + " $($fs.Count) diarios, sin mensuales"
    if($h -gt 36){ Prop "Respaldo de Gestión con $h h: revisar cron gestion-respaldo-diario / gestion-respaldo-tarde y net._http_response." }
  } else { $sG="$SEM_R no hay archivos"; Prop 'No hay respaldos de Gestión en Drive.' } }
if(Test-Path $dirC){
  $fs=@(Get-ChildItem "$dirC\respaldo-cotizador-*.zip" | sort LastWriteTime -desc)
  if($fs.Count){ $f=$fs[0]; Copy-Item $f.FullName "$tmp\cotizador.zip"
    try { Expand-Archive "$tmp\cotizador.zip" "$tmp\cz" -Force; $j=Get-ChildItem "$tmp\cz\*.json" | select -First 1
      $JC=([string](Get-Content -Raw -Encoding UTF8 $j.FullName) | ConvertFrom-Json); $zipOk=$true } catch { $zipOk=$false }
    $h=Horas $f; $kb=[math]::Round($f.Length/1KB)
    $sC = $(if($h -le 36 -and $zipOk){$SEM_V}else{$SEM_R}) + " $($f.LastWriteTime.ToString('dd-MM HH:mm')), $kb KB, zip " + $(if($zipOk){'íntegro'}else{'CORRUPTO'})
    $rC = "$SEM_A $($fs.Count) zips desde $($fs[-1].LastWriteTime.ToString('dd-MM-yyyy')), sin regla de retención"
    if($h -gt 36){ Prop "Respaldo del Cotizador con $h h: la tarea 'CasaZaru - Respaldo Cotizador' (13:30) no corrió; ver respaldo-cotizador.log." }
  } else { $sC="$SEM_R no hay archivos"; Prop 'No hay respaldos del Cotizador en Drive.' } }
Sem '1 Respaldo: frescura' $sG $sC
Sem '1 Respaldo: retención' $rG $rC
# conteo zip vs base (solo Cotizador, con llave secreta)
$cnt="$SEM_B sin llave secreta local"
if($JC -and $SB_KEY){
  $dif=@(); foreach($t in (Tablas $JC.tablas)){ $r=Http 'GET' "$SB_URL/rest/v1/${t}?select=*&limit=1" ($hS+@{Prefer='count=exact'}) $null
    if($r.code -eq 200 -and $r.hdr['Content-Range']){ $n=[int](($r.hdr['Content-Range'] -split '/')[1]); $z=(Filas $JC.tablas $t).Count; if($n -ne $z){ $dif+="$t $z→$n" } } }
  $cnt="$SEM_V base vs zip: " + $(if($dif.Count){ $dif -join ', ' }else{ 'idénticos' }) }
Sem '1 Respaldo: filas zip vs base' "$SEM_A sin llave admin local; se audita el JSON" $cnt

# ── 2. Restauración ───────────────────────────────────────────────────────────
Write-Output '2/8 restauración…'
$reg="$dirInf\restauraciones.csv"; $resG="$SEM_R nunca ensayada"; $resC="$SEM_R nunca ensayada"
if(Test-Path $reg){ $rows=Import-Csv $reg
  foreach($p in 'gestion','cotizador'){ $u=@($rows | ? { $_.proyecto -eq $p } | sort fecha | select -Last 1)
    if($u.Count){ $d=[datetime]$u[0].fecha; $dias=[int]($hoy-$d).TotalDays; $s=$(if($dias -le 30){$SEM_V}else{$SEM_R}) + " $($u[0].fecha) ($dias días) $($u[0].resultado)"; if($p -eq 'gestion'){$resG=$s}else{$resC=$s} } } }
if($resG -like "$SEM_R*" -or $resC -like "$SEM_R*"){ Prop 'Restauración: cargar el respaldo del día en un esquema restore_test (o proyecto vacío), comparar conteos y sumas por tabla y anotar fecha,proyecto,resultado,notas en Informes Gestion/restauraciones.csv.' }
Sem '2 Restauración ensayada' $resG $resC

# ── 3. Migraciones ────────────────────────────────────────────────────────────
Write-Output '3/8 migraciones…'
$migs=@(Get-ChildItem "$repo\supabase\migrations\*.sql" | sort Name); $ult=$(if($migs.Count){$migs[-1].Name}else{'ninguna'})
$faltan=@(); $creadas=@{}; $borradas=@{}
foreach($mf in $migs){ $txt=Get-Content -Raw $mf.FullName
  foreach($mm in [regex]::Matches($txt,'(?i)create table (?:if not exists )?(?:public\.)?([a-z_0-9]+)(?![a-z_0-9.])')){ $creadas[$mm.Groups[1].Value]=$mf.Name.Substring(0,4) }
  foreach($mm in [regex]::Matches($txt,'(?i)drop table (?:if exists )?(?:public\.)?([a-z_0-9]+)')){ $borradas[$mm.Groups[1].Value]=$true } }
foreach($t in ($creadas.Keys | sort)){ if($borradas.ContainsKey($t)){ continue }   # creada y luego revertida por otra migración
  $r=Http 'GET' "$urlG/rest/v1/${t}?select=*&limit=1" $hG $null; if($r.code -eq 404){ $faltan+="$t ($($creadas[$t]))" } }
$mG=$(if($faltan.Count){ "$SEM_R tablas sin aplicar: $($faltan -join ', ')" }else{ "$SEM_A repo hasta $ult; schema_migrations solo por SQL Editor" })
if($faltan.Count){ Prop "Migraciones Gestión: aplicar en el SQL Editor la(s) migración(es) de $($faltan -join ', ') e insertar su fila en supabase_migrations.schema_migrations." }
$mC=$(if(Test-Path "$repo\supabase-cotizador\migrations"){ "$SEM_A hay carpeta migrations; comparar con schema_migrations" }else{ "$SEM_R sin migraciones numeradas (solo .sql sueltos)" })
if($mC -like "$SEM_R*"){ Prop 'Migraciones Cotizador: crear supabase-cotizador/migrations/0001_estado_actual.sql con el esquema vigente y numerar todo lo que venga.' }
Sem '3 Migraciones' $mG $mC

# ── 4. RLS con la llave pública ───────────────────────────────────────────────
Write-Output '4/8 RLS…'
function Rls($url,$hdr,$tablas,$cols,$lecturaOk){
  $abiertas=@(); $grants=@(); $cerradas=0
  foreach($t in $tablas){ $col=$cols[$t]; if(-not $col){ $col='id' }
    $g=Http 'GET' "$url/rest/v1/${t}?select=*&limit=1" $hdr $null
    $f="and=($col.is.null,$col.not.is.null)"
    $p=Http 'PATCH' "$url/rest/v1/${t}?$f" $hdr '{}'
    $d=Http 'DELETE' "$url/rest/v1/${t}?$f" $hdr $null
    $lee = ($g.code -eq 200 -and $g.body.Trim() -ne '[]')
    if($lee -and ($lecturaOk -notcontains $t)){ $abiertas+=$t }
    elseif($g.code -eq 200 -or $p.code -lt 300 -or $d.code -lt 300){ $grants+=$t }
    else { $cerradas++ } }
  $s=$(if($abiertas.Count){$SEM_R}elseif($grants.Count){$SEM_A}else{$SEM_V}) + " $cerradas sin grants"
  if($grants.Count){ $s+="; con grant (ver policy): $($grants -join ', ')" }
  if($abiertas.Count){ $s+="; LECTURA PÚBLICA: $($abiertas -join ', ')" }
  return $s }
$rlsG="$SEM_B sin respaldo para listar tablas"; $rlsC="$SEM_B sin llave"
if($JG -and $anonG){ $tabs=@((Tablas $JG.tablas) | ? { $_ -notlike 'v_*' -and $_ -ne 'gestion_ventas' -and $_ -ne 'gestion_clientes' }); $cols=@{}
  foreach($t in $tabs){ $f=Filas $JG.tablas $t; if($f.Count -and $f[0]){ $cols[$t]=@($f[0].PSObject.Properties.Name)[0] } }
  $rlsG=Rls $urlG $hG $tabs $cols @('quote_links') }
if($JC -and $anonC){ $tabs=Tablas $JC.tablas; $cols=@{}; foreach($t in $tabs){ $f=Filas $JC.tablas $t; if($f.Count -and $f[0]){ $cols[$t]=@($f[0].PSObject.Properties.Name)[0] } }
  $rlsC=Rls $SB_URL $hC $tabs $cols @('cotizador_valores','biblioteca_copiloto') }
if($rlsG -like "*LECTURA*" -or $rlsC -like "*LECTURA*"){ Prop 'RLS: hay tablas legibles con la llave pública que no deberían serlo. Revisar pg_policies y revocar.' }
Sem '4 RLS: llave pública' $rlsG $rlsC
Sem '4 RLS + FORCE, policies' "$SEM_B solo por SQL Editor (ver SKILL.md)" "$SEM_B solo por SQL Editor (ver SKILL.md)"

# ── 5. Secretos ───────────────────────────────────────────────────────────────
Write-Output '5/8 secretos…'
function Secretos($dir){
  $hall=@(); $arch=Get-ChildItem $dir -Recurse -File -Include *.html,*.js,*.ps1,*.md,*.sql,*.json,*.toml,*.ts,*.css | ? { $_.FullName -notmatch '\\(\.git|node_modules|worktrees)\\' }
  foreach($a in $arch){ $hits=Select-String -Path $a.FullName -Pattern 'sk-ant-api0[0-9]-[A-Za-z0-9_-]{20,}|sb_secret_[A-Za-z0-9_-]{10,}|eyJhbGciOi[A-Za-z0-9._-]{60,}' -AllMatches
    foreach($h in $hits){ foreach($mm in $h.Matches){ $v=$mm.Value; $rol=''
      if($v -like 'eyJ*'){ try { $pl=($v -split '\.')[1].Replace('-','+').Replace('_','/'); while($pl.Length % 4){ $pl+='=' }; $rol=([regex]::Match([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($pl)),'"role":"([a-z_]+)"')).Groups[1].Value } catch { $rol='?' }
        if($rol -eq 'anon'){ continue } }
      $hall+="$($a.FullName.Replace($dir,'').TrimStart('\')):$($h.LineNumber) $($v.Substring(0,12))… $rol" } } }
  $log=& git -C $dir log -60 -p --all 2>$null | Select-String -Pattern '^\+.*(sk-ant-api0[0-9]-[A-Za-z0-9_-]{20,}|sb_secret_[A-Za-z0-9_-]{10,})' | select -First 5
  foreach($l in $log){ $hall+="historial git: $($l.Line.Substring(0,[math]::Min(40,$l.Line.Length)))…" }
  return ,$hall }
$sg=Secretos $repo; $sc=Secretos $repoCot
Sem '5 Secretos en repo e historial' $(if($sg.Count){"$SEM_R $($sg -join '; ')"}else{"$SEM_V limpio (solo llaves públicas)"}) $(if($sc.Count){"$SEM_R $($sc -join '; ')"}else{"$SEM_V limpio"})
if($sg.Count -or $sc.Count){ Prop 'Secretos: rotar la llave expuesta hoy mismo y sacarla del archivo; en git no se borra, así que la rotación es lo que cuenta.' }

# ── 6. Integridad ─────────────────────────────────────────────────────────────
Write-Output '6/8 integridad…'
$iG="$SEM_B sin respaldo"; $iC="$SEM_B sin respaldo"
if($JG){ $TAB=$JG.tablas; function Idx($n){ $s=@{}; foreach($r in (Filas $TAB $n)){ $s[[string]$r.num]=$r }; return $s }
  $ped=Idx 'gestion_pedidos'; $pro=Idx 'gestion_produccion'; $fin=Idx 'gestion_finanzas'
  $noNum=@($pro.Keys | ? { $_ -notmatch '^[0-9]+$' -and $_ -notlike 'PV*' -and $_ -notlike 'D*' })
  $finSinPro=@($fin.Keys | ? { -not $pro.ContainsKey($_) }); $proSinFin=@($pro.Keys | ? { -not $fin.ContainsKey($_) -and $_ -notlike 'PV*' })
  $docs=@{}; foreach($d in (Filas $TAB 'gestion_documentos')){ $docs[[string]$d.num]=$true }
  $sinDoc=@($fin.Values | ? { $_.data.doc1_emitida -and -not $docs.ContainsKey([string]$_.num) })
  $neg=@($fin.Values | ? { ([double]$_.data.total - ([double]$_.data.abono1+[double]$_.data.abono2+[double]$_.data.abono3)) -lt -1 } | % { $_.num })
  $sinSem=@($ped.Values | ? { -not $_.data.semana } | % { $_.num })
  $vv=(Filas $TAB 'gestion_ventas').Count; $vf=$fin.Count
  Det "**Gestión** (respaldo $($JG.generado)): producción $($pro.Count), pedidos $($ped.Count), finanzas $($fin.Count)."
  Det "- producción con clave no numérica (Firebase): $($noNum.Count); finanzas sin producción por clave: $($finSinPro.Count); producción sin finanzas: $($proSinFin.Count)."
  Det "- emitidas sin fila en gestion_documentos: $($sinDoc.Count); pedidos sin semana: $($sinSem.Count) $(if($sinSem.Count){'('+(($sinSem|select -First 8) -join ', ')+')'})."
  Det "- abonos que superan el total (suele ser el recargo de tarjeta cobrado al cliente; revisar los que no): $($neg.Count) $(if($neg.Count){'('+(($neg | sort) -join ', ')+')'}); gestion_ventas $vv vs finanzas $vf $(if($vv -eq $vf){'✓'}else{'✗'})."
  $iG=$(if($sinSem.Count -or $vv -ne $vf){$SEM_R}elseif($noNum.Count -or $sinDoc.Count -or $neg.Count){$SEM_A}else{$SEM_V}) + " ver detalle"
  if($noNum.Count){ Prop "Integridad Gestión: $($noNum.Count) filas de producción con clave Firebase → migración que las renombre a data.pedido, con respaldo previo de esas filas." }
  if($sinDoc.Count){ Prop "Integridad Gestión: $($sinDoc.Count) emisiones sin fila en gestion_documentos → relleno histórico desde Wasabil (como la 0014 para septiembre)." }
  }
if($JC){ $TAB=$JC.tablas; $cot=Filas $TAB 'cotizaciones'; $ids=@{}; foreach($c in $cot){ $ids[[string]$c.id]=$true }
  $toq=Filas $TAB 'toques'; $lin=Filas $TAB 'cotizacion_lineas'
  $oT=@($toq | ? { -not $ids.ContainsKey([string]$_.cotizacion_id) }).Count; $oL=@($lin | ? { -not $ids.ContainsKey([string]$_.cotizacion_id) }).Count
  $vivas=@($cot | ? { -not $_.eliminada }); $dup=@($vivas | ? { $_.numero } | group numero | ? { $_.Count -gt 1 })
  $ganSin=@($vivas | ? { $_.estado -eq 'ganado' -and -not $_.monto_cierre }).Count; $sinNum=@($vivas | ? { -not $_.numero }).Count
  $tocadas=@{}; foreach($t in $toq){ $tocadas[[string]$t.cotizacion_id]=$true }; $sinToque=@($vivas | ? { -not $tocadas.ContainsKey([string]$_.id) }).Count
  Det "**Cotizador** (respaldo $($JC.generado)): cotizaciones $($cot.Count) ($($vivas.Count) vivas, $($cot.Count-$vivas.Count) eliminadas), toques $($toq.Count), líneas $($lin.Count)."
  Det "- toques huérfanos: $oT; líneas huérfanas: $oL; vivas sin número: $sinNum; ganadas sin monto_cierre: $ganSin; vivas sin ningún toque: $sinToque."
  Det "- números repetidos entre vivas: $($dup.Count) grupos, $(($dup | measure Count -Sum).Sum) cotizaciones $(if($dup.Count){'(peor: '+(($dup | sort Count -desc | select -First 1 | % { "$($_.Name) x$($_.Count)" }))+')'})."
  $iC=$(if($oT -or $oL){$SEM_R}elseif($dup.Count -or $ganSin){$SEM_A}else{$SEM_V}) + " ver detalle"
  if($oT -or $oL){ Prop "Integridad Cotizador: $oT toques y $oL líneas huérfanos → FK con on delete restrict y limpieza con respaldo." }
  if($dup.Count){ Prop "Integridad Cotizador: números de cotización repetidos → next_quote_number con unique en (numero) donde eliminada=false." } }
Sem '6 Integridad' $iG $iC

# ── 7. Errores del cliente ────────────────────────────────────────────────────
Write-Output '7/8 errores del cliente…'
# Existe la tabla (404 = no; 401 = sí, sin acceso para la llave pública, que es lo esperado) y qué hay en
# los últimos 7 días según el respaldo diario, que descubre la tabla solo. Sin llave admin no hace falta.
$eG=Http 'GET' "$urlG/rest/v1/errores_cliente?select=*&limit=1" $hG $null
$eC=$(if($anonC){ Http 'GET' "$SB_URL/rest/v1/errores_cliente?select=*&limit=1" $hC $null }else{ @{code=0} })
function Errores7($J,$lbl){
  if(-not $J){ return "$SEM_B sin respaldo" }
  if(-not ($J.tablas.PSObject.Properties.Name -contains 'errores_cliente')){ return "$SEM_A la tabla aún no está en el respaldo (entra en el próximo)" }
  $f=Filas $J.tablas 'errores_cliente'; $desde=$hoy.AddDays(-7); $rec=@($f | ? { [datetime]$_.ts -ge $desde })
  if(-not $rec.Count){ return "$SEM_V 0 errores en 7 días (respaldo $($J.generado.Substring(0,10)))" }
  $g=@($rec | group { "$($_.app) · " + ([string]$_.mensaje).Substring(0,[math]::Min(70,([string]$_.mensaje).Length)) } | sort Count -desc)
  Det "**Errores $lbl (7 días, según respaldo):** $($rec.Count) en $($g.Count) mensajes distintos."
  foreach($x in ($g | select -First 5)){ Det "- $($x.Count)× $($x.Name)" }
  return "$SEM_A $($rec.Count) errores / $($g.Count) mensajes; ver detalle" }
$sEG=$(if($eG.code -eq 404){"$SEM_R no existe la tabla"}else{ Errores7 $JG 'Gestión' })
$sEC=$(if($eC.code -eq 404){"$SEM_R no existe la tabla"}else{ Errores7 $JC 'Cotizador' })
if($eG.code -eq 404){ Prop 'Errores Gestión: aplicar supabase/migrations/0021_errores_cliente.sql.' }
if($eC.code -eq 404){ Prop 'Errores Cotizador: aplicar supabase-cotizador/errores-cliente.sql.' }
Sem '7 Errores del cliente' $sEG $sEC

# ── 8. Sitios vivos ───────────────────────────────────────────────────────────
Write-Output '8/8 sitios…'
function Sitio($u){ $r=Http 'GET' $u @{} $null; return $r }
$sG=Sitio 'https://casazar.github.io/Casa-Zaru/'; $sC=Sitio 'https://cotizador.casazaru.cl/'; $sW=Sitio 'https://casazaru.cl/'
$pG=Http 'GET' "$urlG/rest/v1/" $hG $null; $pC=Http 'GET' "$SB_URL/rest/v1/" $hC $null
$sha=[Security.Cryptography.SHA1]::Create()
function Sha($s){ return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($s -replace "`r",''))))).Replace('-','').Substring(0,10) }
$igualG=$(if($sG.code -eq 200){ (Sha $sG.body) -eq (Sha ([IO.File]::ReadAllText("$repo\index.html"))) }else{$false})
$igualC=$(if($sC.code -eq 200){ (Sha $sC.body) -eq (Sha ([IO.File]::ReadAllText("$repoCot\index.html"))) }else{$false})
# PostgREST «vivo» = contesta JSON con cualquier código < 500 (la raíz da 401 a anon y eso es normal)
$vivoG=($pG.code -ge 200 -and $pG.code -lt 500); $vivoC=($pC.code -ge 200 -and $pC.code -lt 500)
$stG=$(if($sG.code -eq 200 -and $vivoG){$SEM_V}else{$SEM_R}) + " Pages $($sG.code)" + $(if($igualG){' = local'}else{' ≠ local'}) + ", PostgREST " + $(if($vivoG){'responde'}else{"CAÍDO ($($pG.code))"})
$stC=$(if($sC.code -eq 200 -and $vivoC){$SEM_V}else{$SEM_R}) + " cotizador.casazaru.cl $($sC.code)" + $(if($igualC){' = local'}else{' ≠ local'}) + ", casazaru.cl $($sW.code), PostgREST " + $(if($vivoC){'responde'}else{"CAÍDO ($($pC.code))"})
if(-not $vivoG -or -not $vivoC){ Prop 'PostgREST no responde: mirar status.supabase.com y el panel del proyecto (un proyecto Free se pausa tras una semana sin uso).' }
if($sG.code -ne 200){ Prop 'Sitio Gestión caído: revisar que el repo Casa-Zaru siga público (Pages gratis exige repo público) y el último deploy en Actions.' }
if($sC.code -ne 200){ Prop 'Cotizador caído: revisar DNS de cotizador.casazaru.cl y GitHub Pages del repo Cotizador.' }
Sem '8 Sitios y API' $stG $stC

# ── Informe ───────────────────────────────────────────────────────────────────
$md=@("# Auditoría de confiabilidad · Casa Zaru · $($hoy.ToString('dd-MM-yyyy HH:mm'))","",
 "Solo lectura. Lo marcado $SEM_B exige el SQL Editor (ver .claude/skills/auditoria/SKILL.md).","",
 "| Punto | Gestión | Cotizador |","|---|---|---|") + @($filas) + @("","## Detalle de integridad","") + @($det) + @("","## Propuestas por cada rojo","") + @($(if($prop.Count){ $prop }else{ @('- Sin rojos esta semana.') }))
$out="$tmp\auditoria-confiabilidad-$($hoy.ToString('yyyy-MM-dd')).md"
[IO.File]::WriteAllLines($out, [string[]]$md, (New-Object Text.UTF8Encoding $false))
if(-not $SinDrive -and (Test-Path $dirInf)){ Copy-Item $out $dirInf -Force; $out="$dirInf\auditoria-confiabilidad-$($hoy.ToString('yyyy-MM-dd')).md" }
Write-Output ''; $md | Write-Output; Write-Output ''; Write-Output "Informe: $out"
