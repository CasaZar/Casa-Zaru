# Prueba de restauración mensual · Casa Zaru
# Carga el respaldo del día (Drive) en el esquema restore_test del MISMO proyecto, por PostgREST,
# y compara filas y sumas por columna numérica contra el archivo. Anota el resultado en
# G:\Mi unidad\Casa Zaru\Informes Gestion\restauraciones.csv (fecha,proyecto,resultado,notas).
# Requiere haber aplicado supabase/migrations/0020_restore_test.sql (Gestión) o
# supabase-cotizador/restore-test.sql (Cotizador) en el SQL Editor.
#
#   restaurar-prueba.ps1 -Proyecto cotizador              # usa la llave secreta de .casazaru\config.ps1
#   restaurar-prueba.ps1 -Proyecto gestion -Email hola@casazaru.cl   # pide la clave en pantalla, no la guarda
#   -Simular    no toca la base: lee el archivo, lo trocea y resume (sirve para probar el script)
#   -Conservar  deja restore_test cargado para mirarlo en el SQL Editor (si no, se borra al final)
#   -Archivo    un respaldo puntual en vez del último de Drive
param(
  [Parameter(Mandatory=$true)][ValidateSet('gestion','cotizador')][string]$Proyecto,
  [string]$Archivo,
  [string]$Email,
  [switch]$Simular,
  [switch]$Conservar
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$ua = 'casazaru-restore-test/1.0'
$hoy = Get-Date
$drive = 'G:\Mi unidad\Casa Zaru'
$dirInf = "$drive\Informes Gestion"
$tmp = Join-Path $env:TEMP ('restore-' + $hoy.ToString('yyyyMMdd-HHmmss')); New-Item -ItemType Directory -Force $tmp | Out-Null
$FILAS_POR_LOTE = 300; $BYTES_POR_LOTE = 400KB

function Http($m,$u,$hdr,$body){
  $a=@{Uri=$u;Method=$m;Headers=$hdr;UseBasicParsing=$true;UserAgent=$ua;TimeoutSec=120}
  if($body -ne $null){ $a.Body=[Text.Encoding]::UTF8.GetBytes($body); $a.ContentType='application/json; charset=utf-8' }
  try { $r=Invoke-WebRequest @a; return @{code=[int]$r.StatusCode;body=[string]$r.Content;hdr=$r.Headers} }
  catch { $resp=$_.Exception.Response; $code=0; $txt=$_.Exception.Message
    if($resp){ $code=[int]$resp.StatusCode.value__; try{ $txt=(New-Object IO.StreamReader($resp.GetResponseStream())).ReadToEnd() }catch{} }
    return @{code=$code;body=$txt;hdr=$null} } }
function Rpc($fn,$body){ $r=Http 'POST' "$url/rest/v1/rpc/$fn" $hdr $body
  if($r.code -lt 200 -or $r.code -ge 300){ throw "rpc $fn -> HTTP $($r.code): $($r.body)" }
  if([string]::IsNullOrWhiteSpace($r.body)){ return $null }; return ($r.body | ConvertFrom-Json) }
function Filas($obj,$n){ $v=$obj.PSObject.Properties[$n].Value; if($v -eq $null){ return ,@() }; return ,@($v | ? { $_ -ne $null }) }

# ── 1. Archivo del respaldo ───────────────────────────────────────────────────
if($Proyecto -eq 'gestion'){
  $dir="$drive\Boletas y Facturas - Ventas 2026\Respaldos Gestion"; $patron='respaldo-gestion-*.json'
} else { $dir="$drive\Boletas y Facturas - Ventas 2026\Respaldos Cotizador"; $patron='respaldo-cotizador-*.zip' }   # desde 26-10 (Edge Function respaldo-cotizador)
if(-not $Archivo){ $f=Get-ChildItem "$dir\$patron" | sort LastWriteTime -desc | select -First 1; if(-not $f){ throw "No hay respaldos en $dir" }; $Archivo=$f.FullName }
$f=Get-Item $Archivo; Copy-Item $f.FullName "$tmp\" ; $local=Join-Path $tmp $f.Name
if($local -like '*.zip'){ Expand-Archive $local "$tmp\z" -Force; $local=(Get-ChildItem "$tmp\z\*.json" | select -First 1).FullName }
Write-Output "Respaldo: $($f.Name) ($([math]::Round($f.Length/1KB)) KB, $($f.LastWriteTime.ToString('dd-MM-yyyy HH:mm')))"
$J=[string](Get-Content -Raw -Encoding UTF8 $local) | ConvertFrom-Json
$TAB=$J.tablas; $tablasArchivo=@($TAB.PSObject.Properties.Name | sort)
Write-Output "Generado: $($J.generado) · origen $($J.origen) · $($tablasArchivo.Count) tablas/vistas en el archivo"

# ── 2. Credenciales ───────────────────────────────────────────────────────────
$url=$null; $hdr=$null
if($Proyecto -eq 'cotizador'){
  . "$env:USERPROFILE\.casazaru\config.ps1"; $url=$SB_URL; $hdr=@{apikey=$SB_KEY;Authorization="Bearer $SB_KEY"}
} else {
  $url='https://padnttpgzuotxeipjrry.supabase.co'
  $m=Select-String -Path "$env:USERPROFILE\Casa Zaru - Claude\index.html" -Pattern "WASABIL_ANON_KEY='(eyJ[A-Za-z0-9._-]+)'" | select -First 1
  $anon=$m.Matches[0].Groups[1].Value
  if(-not $Simular){
    if(-not $Email){ $Email=Read-Host 'Correo del admin de la Gestión' }
    $sec=Read-Host "Clave de $Email (no se guarda)" -AsSecureString
    $plain=[Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
    $r=Http 'POST' "$url/auth/v1/token?grant_type=password" @{apikey=$anon} (@{email=$Email;password=$plain} | ConvertTo-Json -Compress)
    $plain=$null; $sec=$null
    if($r.code -ne 200){ throw "Login falló (HTTP $($r.code)): $($r.body)" }
    $tok=($r.body | ConvertFrom-Json).access_token
    $hdr=@{apikey=$anon;Authorization="Bearer $tok"}
  } }
if($J.origen -and $url -and ($J.origen -notlike "$url*")){ throw "El respaldo es de $($J.origen) y el proyecto elegido es $url. No se carga nada." }

# ── 3. Lotes ──────────────────────────────────────────────────────────────────
function Lotes($filas){
  $out=New-Object System.Collections.ArrayList; $lote=New-Object System.Collections.ArrayList; $bytes=0
  foreach($fila in $filas){ $js=ConvertTo-Json -InputObject $fila -Depth 64 -Compress; $b=[Text.Encoding]::UTF8.GetByteCount($js)
    if($lote.Count -ge $FILAS_POR_LOTE -or ($bytes+$b) -gt $BYTES_POR_LOTE -and $lote.Count -gt 0){ [void]$out.Add(@($lote.ToArray())); $lote=New-Object System.Collections.ArrayList; $bytes=0 }
    [void]$lote.Add($js); $bytes+=$b }
  if($lote.Count){ [void]$out.Add(@($lote.ToArray())) }
  return ,$out }

$conteoArchivo=@{}; $lotesPorTabla=@{}; $totalLotes=0
foreach($t in $tablasArchivo){ $filas=Filas $TAB $t; $conteoArchivo[$t]=$filas.Count; $l=Lotes $filas; $lotesPorTabla[$t]=$l; $totalLotes+=$l.Count }
Write-Output ("Lotes: {0} (hasta {1} filas o {2} KB cada uno)" -f $totalLotes,$FILAS_POR_LOTE,($BYTES_POR_LOTE/1KB))
if($Simular){
  foreach($t in $tablasArchivo){ "{0,-30} {1,6} filas  {2,3} lotes" -f $t,$conteoArchivo[$t],$lotesPorTabla[$t].Count }
  Write-Output "`nSIMULACIÓN: no se tocó la base. Para la prueba real, sin -Simular."; exit 0 }

# ── 4. Preparar, cargar, resumir ──────────────────────────────────────────────
Write-Output 'Preparando restore_test…'
try { $creadas=@(Rpc 'restore_test_preparar' '{}') } catch { if("$_" -match 'PGRST202'){ throw "Las funciones restore_test_* no existen en ${Proyecto}: aplicar primero el SQL (0020_restore_test.sql / restore-test.sql)." }; throw }
Write-Output "  $($creadas.Count) tablas vacías creadas"
$omitidas=@($tablasArchivo | ? { $creadas -notcontains $_ })
if($omitidas.Count){ Write-Output "  en el archivo pero no son tablas (vistas, se omiten): $($omitidas -join ', ')" }
$sinRespaldo=@($creadas | ? { $tablasArchivo -notcontains $_ })
if($sinRespaldo.Count){ Write-Output "  ⚠ TABLAS SIN RESPALDO en el archivo: $($sinRespaldo -join ', ')" }

$cargadas=@{}; $errores=@{}
foreach($t in ($tablasArchivo | ? { $creadas -contains $_ })){
  $n=0; $i=0
  foreach($lote in $lotesPorTabla[$t]){ $i++
    $body='{"tabla":"' + $t + '","filas":[' + ($lote -join ',') + ']}'
    try { $n+=[int](Rpc 'restore_test_cargar' $body) } catch { $errores[$t]="lote ${i}: $_"; break } }
  $cargadas[$t]=$n
  $marca=$(if($errores[$t]){'✗'}elseif($n -eq $conteoArchivo[$t]){'✓'}else{'≠'})
  Write-Output ("  {0} {1,-30} archivo {2,6}  cargadas {3,6}" -f $marca,$t,$conteoArchivo[$t],$n)
  if($errores[$t]){ Write-Output "      $($errores[$t].Substring(0,[math]::Min(300,$errores[$t].Length)))" } }

Write-Output 'Comparando…'
$res=@(Rpc 'restore_test_resumen' '{}')
$difSumas=@(); $difFilas=@()
foreach($r in $res){ $t=$r.tabla; if($tablasArchivo -notcontains $t){ continue }
  if([int64]$r.filas -ne $conteoArchivo[$t]){ $difFilas+="$t ($($conteoArchivo[$t]) vs $($r.filas))" }
  $filas=Filas $TAB $t
  foreach($p in $r.sumas.PSObject.Properties){ $col=$p.Name; $sumaArchivo=[decimal]0
    foreach($fila in $filas){ $v=$fila.$col; if($v -ne $null -and "$v" -ne ''){ $sumaArchivo+=[decimal]$v } }
    $sumaRest=[decimal]$p.Value
    if([math]::Abs($sumaArchivo-$sumaRest) -gt 0.001){ $difSumas+="$t.$col archivo=$sumaArchivo restore=$sumaRest" } } }
# cambios desde el respaldo (la base viva hoy vs el archivo): informativo, no es falla
$vivos=@()
foreach($t in ($tablasArchivo | ? { $creadas -contains $_ })){ $r=Http 'GET' "$url/rest/v1/${t}?select=*&limit=1" ($hdr+@{Prefer='count=exact'}) $null
  if($r.code -eq 200 -and $r.hdr['Content-Range']){ $n=[int](($r.hdr['Content-Range'] -split '/')[1]); if($n -ne $conteoArchivo[$t]){ $vivos+="$t $($conteoArchivo[$t])→$n" } } }

# ── 5. Veredicto y registro ───────────────────────────────────────────────────
$ok = ($errores.Count -eq 0 -and $difFilas.Count -eq 0 -and $difSumas.Count -eq 0 -and $sinRespaldo.Count -eq 0)
$totFilas=($cargadas.Values | measure -Sum).Sum
$notas=@("$($cargadas.Count) tablas, $totFilas filas restauradas desde $($f.Name)")
if($errores.Count){ $notas+="ERRORES: " + (($errores.Keys | % { "$_ ($($errores[$_].Substring(0,[math]::Min(80,$errores[$_].Length))))" }) -join '; ') }
if($difFilas.Count){ $notas+="filas distintas: " + ($difFilas -join ', ') }
if($difSumas.Count){ $notas+="sumas distintas: " + ($difSumas -join ', ') }
if($sinRespaldo.Count){ $notas+="tablas sin respaldo: " + ($sinRespaldo -join ', ') }
if($vivos.Count){ $notas+="archivo vs lo que esta sesión ve hoy en la base (actividad posterior o RLS; informativo): " + ($vivos -join ', ') }
Write-Output ''
Write-Output ($(if($ok){'✅ RESTAURACIÓN OK'}else{'❌ RESTAURACIÓN CON FALLAS'}) + " · " + ($notas -join ' · '))
if(Test-Path $dirInf){
  $csv="$dirInf\restauraciones.csv"
  if(-not (Test-Path $csv)){ [IO.File]::WriteAllText($csv, "fecha,proyecto,resultado,notas`r`n", (New-Object Text.UTF8Encoding $true)) }
  $linea='"' + $hoy.ToString('yyyy-MM-dd HH:mm') + '","' + $Proyecto + '","' + $(if($ok){'OK'}else{'FALLA'}) + '","' + (($notas -join ' · ') -replace '"','''') + '"'
  [IO.File]::AppendAllText($csv, $linea + "`r`n", (New-Object Text.UTF8Encoding $true))
  Write-Output "Anotado en $csv" } else { Write-Output '⚠ Sin Drive: no se anotó en restauraciones.csv' }
if($Conservar){ Write-Output 'restore_test queda cargado (-Conservar). Borrarlo después con select restore_test_limpiar();' }
else { try { Rpc 'restore_test_limpiar' '{}' | Out-Null; Write-Output 'restore_test borrado.' } catch { Write-Output "⚠ no se pudo borrar restore_test: $_" } }
if(-not $ok){ exit 1 }
