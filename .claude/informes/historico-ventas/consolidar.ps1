# Historico de ventas de Casa Zaru (jul 2021 -> oct 2026) a partir de las planillas viejas + el respaldo de Gestion.
# Entrada: los CSV exportados por export-xlsx.ps1 (carpeta datos\<archivo>\NN_<hoja>.csv) y el respaldo de Gestion en Drive.
# Salida: CSV + xlsx en Casa Zaru Planillas\historico y copia en Drive\Finanzas. Nunca al repo (trae nombres y correos).
param(
  [string]$Datos = (Join-Path $PSScriptRoot '..\datos'),
  [string]$Salida = 'C:\Users\dell\Casa Zaru Planillas\historico',
  [string]$Drive = 'G:\Mi unidad\Casa Zaru\Finanzas\Historico ventas',
  [string]$Respaldo = '',
  [switch]$SinDrive
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib-hist.ps1')
$Datos = (Resolve-Path $Datos).Path
New-Item -ItemType Directory -Force $Salida | Out-Null
$IVA = 0.19
$avisos = New-Object System.Collections.ArrayList
function Aviso($t) { [void]$avisos.Add($t) }

# ============================================================
#  A. VENTAS: una configuracion por hoja (columnas por letra)
# ============================================================
# p = principal (entra a la serie oficial del mes); si no, queda como alternativa para cruzar.
$CFG = @(
  # --- VENTAS CASA ZARU 2024 (sep 2024 -> jun 2025) ---
  @{ a='v2024'; h='12_SEPTIEMBRE'; mes='2024-09'; p=$true; desde=3; cliente='B'; semana='C'; num='D'; valor='E'; obs='valor unico por fila (varias filas = varios items)' },
  @{ a='v2024'; h='11_OCTUBRE';    mes='2024-10'; p=$true; desde=6; cliente='C'; semana='D'; num='E'; valor='F'; obs='valor unico por fila' },
  @{ a='v2024'; h='10_NOVIEMBRE';  mes='2024-11'; p=$true; desde=4; cliente='B'; valor='C'; num='D'; medio='E'; abono1='F'; abono2='G'; totalAbonos='H'; pendiente='I'; envio='J' },
  @{ a='v2024'; h='09_DICIEMBRE';  mes='2024-12'; p=$true; desde=5; cliente='B'; num='D'; valor='E'; abono1='F'; abono2='G'; totalAbonos='H'; pendiente='I'; envio='J' },
  @{ a='v2024'; h='08_ENERO';      mes='2025-01'; p=$true; desde=7; cliente='C'; num='E'; valor='F'; nota='G'; doc='K' },
  @{ a='v2024'; h='07_FEBRERO';    mes='2025-02'; p=$true; desde=7; cliente='B'; valor='C'; valorAlt='F'; comision='D'; num='E'; total='F'; envio='G'; abono1='H'; abono2='I'; totalAbonos='J'; pendiente='K'; doc='L'; obs='VALOR solo en algunas filas; si falta se usa PAGO' },
  @{ a='v2024'; h='06_MARZO';      mes='2025-03'; p=$true; desde=8; num='B'; cliente='C'; medio='D'; producto='E'; valor='F'; comision='G'; envio='H'; abono1='I'; abono2='J'; totalAbonos='K'; pendiente='L'; total='M'; doc='N' },
  @{ a='v2024'; h='05_ABRIL';      mes='2025-04'; p=$true; desde=7; num='B'; cliente='C'; medio='D'; nota='E'; abono1='F'; abono2='G'; envio='H'; valor='P'; doc='Q' },
  @{ a='v2024'; h='04_MAYO';       mes='2025-05'; p=$true; desde=7; num='B'; cliente='C'; medio='D'; nota='E'; abono1='F'; abono2='G'; abono3='H'; comision='I'; envio='J'; valor='R'; doc='S' },
  @{ a='v2024'; h='03_JUNIO';      mes='2025-06'; p=$true; desde=7; num='B'; cliente='C'; medio='D'; nota='E'; abono1='F'; abono2='G'; abono3='H'; comision='I'; envio='J'; total='K'; valor='R'; doc='S' },
  @{ a='v2024'; h='02_JULIO';      mes='2025-07'; p=$false; desde=7; num='B'; cliente='C'; medio='D'; nota='E'; abono1='F'; abono2='G'; abono3='H'; comision='I'; envio='J'; total='K'; valor='R'; doc='S' },
  # --- VENTAS CASA ZARU 2025 (jul -> oct 2025) ---
  @{ a='v2025'; h='05_VENTAS JULIO 2025';      mes='2025-07'; p=$true; desde=10; vendedor='A'; num='B'; cliente='C'; medio='D'; nota='E'; abono1='F'; abono2='G'; abono3='H'; comision='I'; envio='J'; total='K'; valor='R'; doc='S' },
  @{ a='v2025'; h='04_VENTAS AGOSTO 2025';     mes='2025-08'; p=$true; desde=66; num='B'; cliente='C'; correo='D'; celular='E'; rut='F'; medio='H'; como='I'; abono1='J'; abono2='K'; abono3='L'; comision='M'; envio='N'; total='O'; totalAbonos='Q'; pendiente='R'; valor='S'; doc='T' },
  @{ a='v2025'; h='03_VENTAS SEPTIEMBRE 2025'; mes='2025-09'; p=$true; desde=6; num='B'; cliente='C'; correo='D'; celular='E'; rut='F'; medio='H'; como='I'; abono1='J'; abono2='K'; abono3='L'; comision='M'; envio='N'; total='O'; totalAbonos='Q'; pendiente='R'; valor='S'; doc='T'; excluirNum='---' },
  @{ a='v2025'; h='02_VENTAS OCTUBRE 2025';    mes='2025-10'; p=$false; desde=5; num='C'; cliente='D'; pendiente='T'; valor='U'; doc='V' },
  # --- VENTAS GENERAL 2025-2026 (ago 2025 -> ago 2026) ---
  @{ a='vgen'; h='01_AGOSTO 2025';     mes='2025-08'; p=$false; desde=1; correo='A'; nombre='C'; apellido='D'; wtsp='J'; fecha='K'; valor='L'; doc='N' },
  @{ a='vgen'; h='02_SEPTIEMBRE 2025'; mes='2025-09'; p=$false; desde=1; correo='A'; nombre='C'; apellido='D'; wtsp='J'; fecha='K'; valor='L'; doc='N' },
  @{ a='vgen'; h='03_OCTUBRE 2025';    mes='2025-10'; p=$true;  desde=2; correo='A'; nombre='B'; apellido='C'; wtsp='H'; fecha='I'; valor='J'; doc='L'; envio='O' },
  @{ a='vgen'; h='04_NOVIEMBRE 2025';  mes='2025-11'; p=$true;  desde=2; seccion='A'; correo='A'; num='B'; nombre='C'; apellido='D'; valor='L'; doc='N'; envio='Q' },
  @{ a='vgen'; h='06_DICIEMBRE 2025';  mes='2025-12'; p=$true;  desde=3; seccion='A'; correo='A'; num='C'; nombre='D'; apellido='E'; valor='M'; medio='N'; doc='O'; doc2='P'; envio='T'; continuar=$true },
  @{ a='vgen'; h='05_DETALLE DICIEMBRE 2025'; mes='2025-12'; p=$false; desde=5; num='B'; nombre='C'; apellido='D'; medio='H'; abono1='J'; abono2='K'; pendiente='R'; valor='S'; doc='T' },
  @{ a='vgen'; h='07_ENERO';   mes='2026-01'; p=$true; desde=8; num='B'; cliente='C'; correo='D'; celular='E'; rut='F'; medio='H'; como='I'; abono1='J'; abono2='K'; abono3='L'; comision='M'; envio='N'; total='O'; totalAbonos='Q'; pendiente='R'; valor='S'; doc='U'; doc2='V'; estado='W' },
  @{ a='vgen'; h='08_FEBRERO'; mes='2026-02'; p=$true; desde=8; vendedor='A'; num='B'; cliente='C'; correo='D'; celular='E'; rut='F'; medio='H'; tipoDoc='I'; como='L'; abono1='M'; abono2='N'; abono3='O'; comision='P'; envio='Q'; totalAbonos='T'; pendiente='U'; total='V'; valor='W'; doc='Y'; doc2='Z'; estado='AA' },
  @{ a='vgen'; h='09_MARZO';   mes='2026-03'; p=$true; desde=8; vendedor='A'; num='B'; cliente='C'; correo='D'; celular='E'; rut='F'; medio='H'; tipoDoc='I'; como='L'; abono1='M'; abono2='N'; abono3='O'; comision='P'; envio='Q'; totalAbonos='T'; pendiente='U'; total='V'; valor='W'; doc='Y'; doc2='Z'; estado='AA' },
  @{ a='vgen'; h='11_ABRIL';   mes='2026-04'; p=$true; desde=8; vendedor='A'; num='B'; cliente='C'; correo='D'; celular='E'; rut='F'; medio='H'; tipoDoc='I'; como='L'; abono1='M'; abono2='N'; abono3='O'; comision='P'; envio='Q'; totalAbonos='T'; pendiente='U'; total='V'; valor='W'; doc='Y'; doc2='Z'; estado='AA' },
  @{ a='vgen'; h='13_MAYO';    mes='2026-05'; p=$true; desde=2; num='A'; fecha='B'; semana='C'; cliente='D'; correo='E'; celular='F'; producto='G'; medio='H'; como='I'; valor='J'; envio='L'; comision='M'; total='N'; abono1='O'; abono2='P'; abono3='Q'; pendiente='R'; doc='U'; doc2='V'; estado='W' },
  @{ a='vgen'; h='15_JUNIO';   mes='2026-06'; p=$true; desde=2; num='A'; fecha='B'; semana='C'; cliente='D'; correo='E'; celular='F'; producto='G'; medio='H'; como='I'; valor='J'; envio='K'; comision='L'; total='M'; abono1='N'; abono2='O'; abono3='P'; pendiente='Q'; doc='T'; doc2='U'; estado='V' },
  @{ a='vgen'; h='17_JULIO';   mes='2026-07'; p=$true; desde=2; num='A'; fecha='B'; semana='C'; cliente='D'; correo='E'; celular='F'; producto='G'; medio='H'; como='I'; valor='J'; envio='K'; comision='L'; total='M'; abono1='N'; abono2='O'; abono3='P'; pendiente='Q'; doc='T'; doc2='U'; estado='V' },
  @{ a='vgen'; h='19_AGOSTO 2026'; mes='2026-08'; p=$true; desde=2; num='A'; fecha='B'; semana='C'; cliente='D'; vendedor='E'; tipo='F'; valor='G' }
)
$ARCHIVOS = @{ v2024 = 'VENTAS CASA ZARU 2024 .xlsx'; v2025 = 'VENTAS CASA ZARU 2025 (1).xlsx'; vgen = 'VENTAS GENERAL 2025 - 2026 (4).xlsx'; taller2024 = 'PEDIDOS CASA ZARU TALLER 2024.xlsx'; gestion = 'respaldo Gestion (Drive)' }

function SumaAbonos($r, $cfg) {
  $hay = $false; $s = 0.0
  foreach ($k in @('abono1', 'abono2', 'abono3')) { if ($cfg[$k]) { $v = Num (Celda $r $cfg[$k]); if ($null -ne $v) { $s += $v; $hay = $true } } }
  if ($hay) { return $s }
  if ($cfg.totalAbonos) { return (Num (Celda $r $cfg.totalAbonos)) }
  return $null
}
function TituloCaso([string]$s) { if (-not $s) { return '' }; $s = $s.Trim().ToLower(); return ($s.Substring(0, 1).ToUpper() + $s.Substring(1)) }

function ParseVentas($cfg) {
  $path = Join-Path $Datos ("{0}\{1}.csv" -f $cfg.a, $cfg.h)
  if (-not (Test-Path -LiteralPath $path)) { Aviso "No existe $path"; return @() }
  $rows = LeerHoja $path
  $out = New-Object System.Collections.ArrayList
  $canalSeccion = ''; $prev = $null; $prevFila = -9
  foreach ($r in $rows) {
    $fila = [int]$r.fila
    if ($cfg.desde -and $fila -lt $cfg.desde) { continue }
    if ($cfg.seccion) {
      $m = Limpio (Celda $r $cfg.seccion)
      if ($m -match '^VENTAS\s+WHATSAPP') { $canalSeccion = 'WhatsApp'; $prev = $null; continue }
      if ($m -match '^VENTAS\s+WEB') { $canalSeccion = 'Web'; $prev = $null; continue }
    }
    $numRaw = Limpio (Celda $r $cfg.num)
    if ($cfg.cliente) { $cliente = Limpio (Celda $r $cfg.cliente) } else { $cliente = ((Limpio (Celda $r $cfg.nombre)) + ' ' + (Limpio (Celda $r $cfg.apellido))).Trim() }
    $nc = Norm $cliente
    if ($numRaw -match '^(TOTAL|TOTALES|NUMERO)' -or $nc -match '^(TOTAL|TOTALES|NETO|BRUTO|CLIENTE|NOMBRE|VENTAS|COMISION|BASE|TICKET|PUBLICIDAD|CLIENTES|ADQUISICION|PEDIDOS|VENTA|SEGUIMIENTO|FN)$' -or $nc -match '^(VENTAS|COMISION|TOTAL)') { $prev = $null; continue }
    if ($cfg.excluirNum -and $numRaw -eq $cfg.excluirNum) { $prev = $null; continue }
    $txtAb = Limpio (Celda $r $cfg.abono1); if ($txtAb -match 'MUESTRA') { $prev = $null; continue }
    $valor = Num (Celda $r $cfg.valor)
    if ($null -eq $valor -and $cfg.valorAlt) { $valor = Num (Celda $r $cfg.valorAlt) }
    $num = $null; $numTxt = ''
    if ($numRaw -match '^[Pp]?\s*(\d+)(\.0+)?$') { $num = [int]$matches[1]; $numTxt = "$num" }
    $extra = $false
    if ($cliente -eq '' -and $null -eq $num) {
      if ($cfg.continuar -and $prev -and $fila -eq ($prevFila + 1) -and $null -ne $valor) { $cliente = $prev.cliente; $num = $prev.num; $numTxt = $prev.numTxt; $extra = $true }
      else { continue }
    }
    $total = $null; if ($cfg.total) { $total = Num (Celda $r $cfg.total) }
    if ($null -eq $valor -and $null -eq $total) { continue }   # numero reservado sin venta (ej. 257-259, P276-P286)
    if ($null -eq $valor) { $valor = $total; $nota2 = 'valor tomado del total pagado' } else { $nota2 = '' }
    $tipo = Limpio (Celda $r $cfg.tipo); if (-not $tipo) { $tipo = 'VENTA' }
    $vend = Limpio (Celda $r $cfg.vendedor); $canal = $canalSeccion
    $medio = Limpio (Celda $r $cfg.medio)
    if ($vend -match '^WEB$') { $canal = 'Web'; $vend = '' }
    if ($medio -match '^WEB' -or $medio -match 'MP WEB') { $canal = 'Web' }
    if ($cfg.wtsp) { $w = Limpio (Celda $r $cfg.wtsp); if ($w -match '^WTSP') { if (-not $canal) { $canal = 'WhatsApp' } } elseif ((Limpio (Celda $r $cfg.doc)) -match 'WEB') { $canal = 'Web' } }
    if (-not $canal -and $medio -match 'MERCADO LIBRE|^ML') { $canal = 'Mercado Libre' }
    if ($vend) { $vend = TituloCaso $vend; if ($vend -eq 'Cesar') { $vend = 'César' } }
    $fecha = ''; if ($cfg.fecha) { $fd = FechaDe (Celda $r $cfg.fecha); if ($fd) { $fecha = $fd.ToString('yyyy-MM-dd') } }
    $doc = ((Limpio (Celda $r $cfg.doc)) + ' ' + (Limpio (Celda $r $cfg.doc2))).Trim()
    $nota = Limpio (Celda $r $cfg.nota); if ($nota2) { $nota = ($nota + ' ' + $nota2).Trim() }
    $o = [pscustomobject]@{
      mes = $cfg.mes; fuente = $cfg.a; archivo = $ARCHIVOS[$cfg.a]; hoja = ($cfg.h -replace '^\d+_', ''); fila = $fila; principal = [int][bool]$cfg.p
      num = $numTxt; cliente = $cliente; fecha = $fecha; semana = (Limpio (Celda $r $cfg.semana)); canal = $canal; vendedor = $vend; tipo = $tipo
      medio = $medio; producto = (Limpio (Celda $r $cfg.producto)); como = (Limpio (Celda $r $cfg.como))
      valor = (Entero $valor); total = (Entero $total); envio = (Entero (Num (Celda $r $cfg.envio))); comision = (Entero (Num (Celda $r $cfg.comision)))
      abonos = (Entero (SumaAbonos $r $cfg)); pendiente = (Entero (Num (Celda $r $cfg.pendiente))); doc = $doc; estado = (Limpio (Celda $r $cfg.estado))
      correo = (Limpio (Celda $r $cfg.correo)); celular = (Limpio (Celda $r $cfg.celular)); item_extra = [int]$extra; nota = $nota; numTxt = $numTxt
    }
    [void]$out.Add($o); $prev = $o; $prevFila = $fila
  }
  return @($out)
}

$ventasTodas = New-Object System.Collections.ArrayList
foreach ($cfg in $CFG) { $vs = ParseVentas $cfg; foreach ($v in $vs) { [void]$ventasTodas.Add($v) } }

# --- Gestion (respaldo diario en Drive): may 2026 -> hoy. Principal desde sep 2026 (antes manda la planilla). ---
$dirResp = 'G:\Mi unidad\Casa Zaru\Boletas y Facturas - Ventas 2026\Respaldos Gestion'
if ($Respaldo) { $resp = Get-Item -LiteralPath $Respaldo } else { $resp = Get-ChildItem $dirResp -Filter 'respaldo-gestion-*.json' | Sort-Object LastWriteTime -Descending | Select-Object -First 1 }
$respNombre = ''
if ($resp) {
  $respNombre = $resp.Name
  $j = [IO.File]::ReadAllText($resp.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json
  foreach ($f in @($j.tablas.gestion_finanzas)) {
    $d = $f.data
    $fs = if ($d.fecha_creacion) { "$($d.fecha_creacion)" } else { "$($d.fecha)" }
    $fd = FechaDe $fs; if (-not $fd) { Aviso "Gestion #$($f.num): fecha ilegible '$fs'"; continue }
    $mes = $fd.ToString('yyyy-MM')
    $tipo = if ("$($d.tipo)") { "$($d.tipo)" } else { 'VENTA' }
    $vp = Num $d.val_prod; $tot = Num $d.total
    if ($null -eq $vp) { $vp = $tot }
    $canal = if ("$($d.canal_pago)" -match 'SHOPIFY') { 'Web' } else { '' }
    $vend = Limpio "$($d.vendedor)"; if ($vend -match '^WEB$') { $canal = 'Web'; $vend = '' }
    if ($vend) { $vend = TituloCaso $vend; if ($vend -eq 'Cesar') { $vend = 'César' } }
    $ab = 0.0; foreach ($k in @('abono1', 'abono2', 'abono3')) { $x = Num $d.$k; if ($null -ne $x) { $ab += $x } }
    $o = [pscustomobject]@{
      mes = $mes; fuente = 'gestion'; archivo = $respNombre; hoja = 'gestion_finanzas'; fila = 0; principal = [int]($mes -ge '2026-09')
      num = "$($f.num)"; cliente = (Limpio ("$($d.nombre) $($d.apellido)")); fecha = $fd.ToString('yyyy-MM-dd'); semana = "$($d.semana)"; canal = $canal; vendedor = $vend; tipo = $tipo
      medio = "$($d.medio_pago)"; producto = "$($d.producto)"; como = "$($d.como)"
      valor = (Entero $vp); total = (Entero $tot); envio = (Entero (Num $d.val_envio)); comision = (Entero (Num $d.val_comision))
      abonos = (Entero $ab); pendiente = (Entero ($tot - $ab)); doc = (Limpio "$($d.doc1_tipo) $($d.doc1_num)"); estado = ''
      correo = "$($d.email)"; celular = "$($d.celular)"; item_extra = 0; nota = ''; numTxt = "$($f.num)"
    }
    [void]$ventasTodas.Add($o)
  }
} else { Aviso 'No se encontro respaldo de Gestion: faltan sep y oct 2026.' }

# --- Vendedor desde las hojas de Cesar / Antonio ---
$setCesar = @{}; $setAntonio = @{}
function NumsDeHoja($a, $h, $colNum, $colValor) {
  $p = Join-Path $Datos ("{0}\{1}.csv" -f $a, $h); if (-not (Test-Path -LiteralPath $p)) { return @() }
  $res = @()
  foreach ($r in (LeerHoja $p)) { $n = Num (Celda $r $colNum); if ($null -eq $n) { continue }; if ($colValor -and $null -eq (Num (Celda $r $colValor))) { continue }; $res += [int]$n }
  return $res
}
foreach ($n in (NumsDeHoja 'vgen' '10_CESAR MARZO' 'B' $null)) { $setCesar["2026-03|$n"] = 1 }
foreach ($n in (NumsDeHoja 'vgen' '12_CESAR ABRIL' 'B' $null)) { $setCesar["2026-04|$n"] = 1 }
foreach ($n in (NumsDeHoja 'vgen' '14_MAYO CESAR' 'A' 'J')) { $setCesar["2026-05|$n"] = 1 }
foreach ($n in (NumsDeHoja 'vgen' '16_CÉSAR JUNIO' 'A' 'J')) { $setCesar["2026-06|$n"] = 1 }
foreach ($n in (NumsDeHoja 'vgen' '18_CÉSAR JULIO' 'A' 'J')) { $setCesar["2026-07|$n"] = 1 }
foreach ($n in (NumsDeHoja 'v2025' '07_VENTAS SEPTIEMBRE ANTONIO' 'B' 'S')) { $setAntonio["2025-09|$n"] = 1 }
foreach ($v in $ventasTodas) {
  if ($v.vendedor) { continue }
  $k = "$($v.mes)|$($v.num)"
  if ($setCesar.ContainsKey($k)) { $v.vendedor = 'César' } elseif ($setAntonio.ContainsKey($k)) { $v.vendedor = 'Antonio' }
}
$ventas = @($ventasTodas | Where-Object { $_.principal -eq 1 })
$ventasAlt = @($ventasTodas | Where-Object { $_.principal -eq 0 })

# ============================================================
#  B. TALLER: hojas semanales + hoja maestra PEDIDOS CUBIERTAS
# ============================================================
$dirT = Join-Path $Datos 'taller2024'
$EXCLUIR = @('NUEVO TALLER', 'CAJA', 'BOLETAS', 'FACTURAS', 'COTIZADOR', 'PUERTAS', 'Hoja 8', 'Hoja 18', 'MARIO', 'COLEGIO PV', 'MAITENCILLO', 'JUNIO')
$hojasT = @(Get-ChildItem -LiteralPath $dirT -Filter '*.csv' | ForEach-Object {
  $n = $_.BaseName; $idx = [int]($n.Substring(0, 2)); $nombre = $n.Substring(3)
  [pscustomobject]@{ archivo = $_.FullName; idx = $idx; nombre = $nombre }
} | Where-Object { $EXCLUIR -notcontains $_.nombre })

function AnioPorIndice($idx) { if ($idx -le 31) { return 2025 }; if ($idx -le 52) { return 2024 }; if ($idx -eq 84) { return 2023 }; return 0 }
function FechaDeNombre([string]$nombre, [int]$idx) {
  # 'JULIO 1 2024', 'ENE 8 - 2024', 'ENE 22 - 24', '14 OCTUBRE', 'SEPTIEMBRE 2', 'AGOSTO 5 JULIO', 'JULIO 7.1'
  $toks = @(($nombre -replace '[-\.]', ' ') -split '\s+' | Where-Object { $_ })
  $mes = 0; $dia = 0; $anio = 0
  foreach ($t in $toks) {
    if ($t -match '^\d+$') { $n = [int]$t; if ($n -ge 2020) { $anio = $n } elseif ($n -ge 1 -and $n -le 31 -and $dia -eq 0) { $dia = $n } elseif ($n -ge 22 -and $n -le 30 -and $anio -eq 0 -and $dia -gt 0) { $anio = 2000 + $n } }
    elseif ($mes -eq 0) { $m = MesDeTexto $t; if ($m) { $mes = $m } }
  }
  if ($mes -eq 0 -or $dia -eq 0) { return $null }
  if ($anio -eq 0) { $anio = AnioPorIndice $idx }
  if ($anio -eq 0) { return $null }
  try { return (Get-Date -Year $anio -Month $mes -Day $dia).Date } catch { return $null }
}
function FechaDeTitulo($rows, [int]$anio) {
  foreach ($r in ($rows | Select-Object -First 6)) {
    foreach ($p in $r.PSObject.Properties) {
      $v = Limpio "$($p.Value)"
      if ($v -match '^SEMANA\s+(\d{1,2})\s+(\p{L}+)(\s+(\d{4}))?') {
        $m = MesDeTexto $matches[2]; if (-not $m) { continue }
        $y = if ($matches[4]) { [int]$matches[4] } else { $anio }
        try { return (Get-Date -Year $y -Month $m -Day ([int]$matches[1])).Date } catch { }
      }
    }
  }
  return $null
}
function MapaCabecera($row) {
  $map = @{}; $vioDireccion = $false
  foreach ($p in $row.PSObject.Properties) {
    if ($p.Name -eq 'fila') { continue }
    $h = Norm "$($p.Value)"; if (-not $h) { continue }
    if ($vioDireccion) { break }
    if ($h -eq 'DIRECCION') { $vioDireccion = $true }
    if (-not $map.ContainsKey($h)) { $map[$h] = @() }
    $map[$h] += $p.Name
  }
  return $map
}
function EsCabecera($row) { foreach ($p in $row.PSObject.Properties) { if ($p.Name -ne 'fila' -and (Norm "$($p.Value)") -eq 'COMPRADOR') { return $true } }; return $false }
function Roles($map, $data) {
  $R = @{}
  foreach ($k in @('COMPRADOR', 'MADERA', 'MEDIDA', 'CANTO', 'ACABADO', 'ESPESOR', 'MTRS2', 'CANTIDAD', 'OBSERVACION', 'ESTADO', 'CRISTIAN', 'SEMANAENVIO', 'TRANSFERENCIA', 'MEDIO')) { if ($map.ContainsKey($k)) { $R[$k] = $map[$k][0] } }
  if ($R.MEDIDA) { $R.MEDIDA2 = ColSig $R.MEDIDA }
  # hoja maestra vieja: la columna de m2 (cm2) existe pero el encabezado quedo vacio; esta 5 columnas a la derecha de MEDIDA
  if (-not $R.MTRS2 -and $R.MEDIDA) { $cand = ColDeIdx ((ColIdx $R.MEDIDA) + 5); $nn = @($data | ForEach-Object { Num (Celda $_ $cand) } | Where-Object { $null -ne $_ -and $_ -gt 0 }).Count; if ($nn -ge 3) { $R.MTRS2 = $cand } }
  if (-not $R.SEMANAENVIO -and $map.ContainsKey('ENVIO')) {
    $best = $null; $bestN = 0
    foreach ($c in $map['ENVIO']) { $n = @($data | Where-Object { $null -ne (FechaDe (Celda $_ $c)) -or ((Limpio (Celda $_ $c)) -match '^(LUNES|MARTES|MIERCOLES|MIÉRCOLES|JUEVES|VIERNES|SABADO|SÁBADO|POR DEFINIR)') }).Count; if ($n -gt $bestN) { $bestN = $n; $best = $c } }
    if ($bestN -gt 0) { $R.SEMANAENVIO = $best }
  }
  $R.NUM = $null; $R.VENTAPEDIDO = $null; $R.NUMTEXTO = $false
  if ($map.ContainsKey('NVENTA')) {
    foreach ($c in $map['NVENTA']) {
      $vals = @($data | ForEach-Object { Num (Celda $_ $c) } | Where-Object { $null -ne $_ })
      if ($vals.Count -eq 0) { continue }
      $small = @($vals | Where-Object { $_ -ge 1 -and $_ -le 5000 }).Count
      if ($small -ge ($vals.Count / 2)) { if (-not $R.NUM) { $R.NUM = $c } } else { $R.VENTAPEDIDO = $c }
    }
  }
  $ventas = @(); if ($map.ContainsKey('VENTA')) { $ventas = @($map['VENTA']) }
  if (-not $R.NUM -and $map.ContainsKey('PEDIDO')) { $R.NUM = $map['PEDIDO'][0]; if ($ventas.Count) { $R.VENTAPEDIDO = $ventas[0] } }
  if (-not $R.NUM) {
    foreach ($c in $ventas) {
      $txt = @($data | Where-Object { (Limpio (Celda $_ $c)) -match '^VENTA\s*\d+$' }).Count
      $nums = @($data | ForEach-Object { Num (Celda $_ $c) } | Where-Object { $null -ne $_ })
      $chicos = @($nums | Where-Object { $_ -ge 1 -and $_ -le 3000 }).Count
      $grandes = @($nums | Where-Object { $_ -gt 3000 }).Count
      if ($txt -gt 0 -or ($chicos -gt 0 -and $grandes -eq 0 -and $map.ContainsKey('VALORVENTA'))) { $R.NUM = $c; $R.NUMTEXTO = $true; break }
    }
  }
  $otras = @($ventas | Where-Object { $_ -ne $R.NUM -and $_ -ne $R.VENTAPEDIDO })
  $R.PRECIO = $null; $R.PRECIOTIPO = ''
  if ($map.ContainsKey('VENTAITEM')) { $R.PRECIO = $map['VENTAITEM'][0]; $R.PRECIOTIPO = 'venta_item' }
  elseif ($map.ContainsKey('TOTALITEM')) { $R.PRECIO = $map['TOTALITEM'][0]; $R.PRECIOTIPO = 'venta_item' }
  elseif ($map.ContainsKey('VENTATOTAL') -and $otras.Count -gt 0) { $cT = $map['VENTATOTAL'][0]; $der = @($otras | Where-Object { (ColIdx $_) -gt (ColIdx $cT) }); if ($der.Count) { $R.PRECIO = $der[0]; $R.PRECIOTIPO = 'venta_item' } }
  elseif ($map.ContainsKey('PEDIDO')) { }
  elseif ($map.ContainsKey('NVENTA') -and $otras.Count -gt 0) { $R.PRECIO = $otras[0]; $R.PRECIOTIPO = 'venta_item' }
  elseif ($map.ContainsKey('VALORVENTA') -and $R.CRISTIAN) { $R.PRECIO = $map['VALORVENTA'][0]; $R.PRECIOTIPO = 'valor_venta' }
  elseif ($otras.Count -gt 0 -and $R.CRISTIAN) { $R.PRECIO = $otras[0]; $R.PRECIOTIPO = 'formula' }
  if (-not $R.VENTAPEDIDO) { foreach ($k in @('TOTALVENTA', 'VENTATOTAL')) { if ($map.ContainsKey($k)) { $R.VENTAPEDIDO = $map[$k][0]; break } } }
  if ($R.VENTAPEDIDO -and $R.PRECIO -eq $R.VENTAPEDIDO) { $R.PRECIO = $null; $R.PRECIOTIPO = '' }
  if ($map.ContainsKey('TOTAL')) { $R.TOTAL = $map['TOTAL'][0] }
  $R.ABONOS = @(); foreach ($k in @('ABONO1', 'ABONO2', 'ABONO3')) { if ($map.ContainsKey($k)) { $R.ABONOS += $map[$k][0] } }
  $R.PAGADO = $null; foreach ($k in @('PAGOTOTAL', 'TOTALPAGADO', 'PAGADO', 'PAGO')) { if ($map.ContainsKey($k)) { $R.PAGADO = $map[$k][0]; break } }
  return $R
}
# Semana en texto de la hoja maestra: '12 de julio', '2 DE AGOSTO', '27 DE SEP', '4 DE SEP', '8 DE AGOOSTO'
function ParseSemanaTexto([string]$t) {
  $t = Limpio $t
  if ($t -match '^(\d{1,2})\s*(de\s+)?(\p{L}+)') { $m = MesDeTexto $matches[3]; if ($m) { return @{ dia = [int]$matches[1]; mes = $m } } }
  return $null
}

$taller = New-Object System.Collections.ArrayList
$vistos = @{}        # clave de pieza -> max repeticiones vistas en una hoja anterior
$resumenHojas = New-Object System.Collections.ArrayList

function ProcesarHojaTaller($hojaInfo, $rows, $esMaestra, $semanaHoja) {
  $map = $null; $ROL = $null; $bloque = @(); $filasOut = New-Object System.Collections.ArrayList
  # separar en bloques (cabecera + datos)
  $bloques = @(); $actual = $null
  foreach ($r in $rows) {
    if (EsCabecera $r) { if ($actual) { $bloques += ,$actual }; $actual = @{ cab = $r; datos = @() } ; continue }
    if ($actual) { $actual.datos += $r }
  }
  if ($actual) { $bloques += ,$actual }
  $debug = ($env:HIST_DEBUG -and $env:HIST_DEBUG -eq $hojaInfo.nombre)
  if ($debug) { Write-Host ("DEBUG {0}: {1} filas, {2} bloques" -f $hojaInfo.nombre, @($rows).Count, @($bloques).Count) }
  foreach ($b in $bloques) {
    $map = MapaCabecera $b.cab
    $ROL = Roles $map $b.datos
    if ($debug) { Write-Host ("  mapa: " + (($map.Keys | Sort-Object | ForEach-Object { $_ + '=' + ($map[$_] -join ',') }) -join ' ')); Write-Host ("  roles: " + (($ROL.Keys | Sort-Object | ForEach-Object { $_ + '=' + ($ROL[$_] -join ',') }) -join ' ')); Write-Host ("  datos: " + @($b.datos).Count) }
    if (-not $ROL.COMPRADOR) { continue }
    $prev = $null; $semanaFila = $null
    foreach ($r in $b.datos) {
      $fila = [int]$r.fila
      $comprador = Limpio (Celda $r $ROL.COMPRADOR)
      if (-not $comprador) { $prev = $null; continue }
      $nc = Norm $comprador
      if ($nc -match '^(TOTAL|TOTALES|COMPRADOR|NOMBRE|GANANCIA)$' -or $nc -eq '') { $prev = $null; continue }
      $numRaw = Limpio (Celda $r $ROL.NUM)
      if ($numRaw -match '^PENDIENTE') { continue }
      $num = $null
      if ($numRaw -match '(\d+)') { $n = [int]$matches[1]; if ($n -ge 1 -and $n -le 5000) { $num = $n } }
      $madera = Limpio (Celda $r $ROL.MADERA)
      $med1raw = Limpio (Celda $r $ROL.MEDIDA); $med2raw = Limpio (Celda $r $ROL.MEDIDA2)
      $med1 = Num $med1raw; $med2 = Num $med2raw
      $medTxt = ''; if ($null -eq $med1 -and $med1raw) { $medTxt = $med1raw }
      $m2 = Num (Celda $r $ROL.MTRS2); if ($null -ne $m2 -and $m2 -gt 50) { $m2 = $m2 / 10000 }
      if ($null -ne $m2) { $m2 = [math]::Round($m2, 4) }
      $costo = Num (Celda $r $ROL.CRISTIAN)
      $precio = Num (Celda $r $ROL.PRECIO); $precioTipo = $ROL.PRECIOTIPO
      $ventaPedido = Num (Celda $r $ROL.VENTAPEDIDO)
      $tipoPed = ''
      # fecha de la fila
      $semRaw = Limpio (Celda $r $ROL.SEMANAENVIO)
      $fechaFila = FechaDe $semRaw
      $origen = 'hoja'
      if ($esMaestra) {
        if ($fechaFila) { $semanaFila = Lunes $fechaFila; $origen = 'fila' }
        else {
          $pt = ParseSemanaTexto $semRaw
          if ($pt) { $semanaFila = [pscustomobject]@{ texto = $semRaw; dia = $pt.dia; mes = $pt.mes; fila = $fila }; $origen = 'texto' }
          elseif (-not $semanaFila) { continue }
        }
        # bloque 2021: col B con el tipo (Premium/Clasica) y C con el numero viejo
        $b2 = Limpio (Celda $r 'B'); $c2 = Num (Celda $r 'C')
        if ($b2 -and $null -eq (Num $b2) -and $null -ne $c2 -and $c2 -le 2000 -and $origen -eq 'texto') { $tipoPed = $b2; $num = [int]$c2; $precio = $null; $precioTipo = '' }
        if ($origen -eq 'texto') {
          $tot = Num (Celda $r 'T'); $u = Num (Celda $r 'U')
          if ($null -ne $tot -and $tot -gt 1000) { $precio = $tot; $precioTipo = 'lista'; $ventaPedido = $tot }
          elseif ($null -ne $u -and $u -gt 1000) { $precio = $u; $precioTipo = 'lista' }
        }
      } else {
        $semanaFila = $semanaHoja
        if ($fechaFila) { $lf = Lunes $fechaFila; if ([math]::Abs(($lf - $semanaHoja).TotalDays) -gt 21) { $semanaFila = $lf; $origen = 'fila' } }
      }
      if ($null -eq $num -and $prev -and $prev.comprador -eq $comprador -and $prev.num) { $num = $prev.num }
      if ($debug) { Write-Host ("  fila {0}: comprador=[{1}] num={2} madera=[{3}] precio={4} costo={5} m2={6} vp={7} semana={8}" -f $fila, $comprador, $num, $madera, $precio, $costo, $m2, $ventaPedido, $semanaFila) }
      if (-not $madera -and $null -eq $precio -and $null -eq $costo -and $null -eq $m2 -and $null -eq $ventaPedido) { continue }
      $ab = $null; foreach ($c in $ROL.ABONOS) { $x = Num (Celda $r $c); if ($null -ne $x) { if ($null -eq $ab) { $ab = 0.0 }; $ab += $x } }
      $o = [pscustomobject]@{
        semana = $semanaFila; semana_origen = $origen; mes = ''; hoja = $hojaInfo.nombre; fila = $fila
        num = $num; comprador = $comprador; tipo = $tipoPed; madera = $madera; medida1 = $med1; medida2 = $med2; medida_txt = $medTxt
        canto = (Limpio (Celda $r $ROL.CANTO)); acabado = (Limpio (Celda $r $ROL.ACABADO)); espesor = (Limpio (Celda $r $ROL.ESPESOR)); cantidad = (Num (Celda $r $ROL.CANTIDAD))
        m2 = $m2; costo_cristian = (Entero $costo); precio_pieza = (Entero $precio); precio_tipo = $precioTipo; venta_pedido = (Entero $ventaPedido)
        abonos = (Entero $ab); pagado = (Entero (Num (Celda $r $ROL.PAGADO))); medio = (Limpio (Celda $r $ROL.MEDIO)); estado = (Limpio (Celda $r $ROL.ESTADO)); obs = (Limpio (Celda $r $ROL.OBSERVACION))
        duplicado = 0
      }
      [void]$filasOut.Add($o); $prev = $o
    }
  }
  return @($filasOut)
}

# 1) maestra primero (es la mas vieja): resolver las semanas en texto por posicion (la hoja va de nuevo a viejo)
$maestra = $hojasT | Where-Object { $_.nombre -eq 'PEDIDOS CUBIERTAS' } | Select-Object -First 1
$filasM = @()
if ($maestra) {
  $rowsM = LeerHoja $maestra.archivo
  $filasM = ProcesarHojaTaller $maestra $rowsM $true $null
  # cotas: para cada fila con texto, la fecha ISO mas cercana arriba (mas nueva) y abajo (mas vieja)
  $isoPorFila = @{}; foreach ($f in $filasM) { if ($f.semana_origen -eq 'fila') { $isoPorFila[$f.fila] = $f.semana } }
  $filasIso = @($isoPorFila.Keys | Sort-Object)
  $mapaTexto = @{}
  foreach ($f in $filasM) {
    if ($f.semana -is [datetime]) { continue }
    $t = $f.semana
    if (-not $t) { continue }
    $arriba = @($filasIso | Where-Object { $_ -lt $t.fila }); $abajo = @($filasIso | Where-Object { $_ -gt $t.fila })
    $sup = $null; if ($arriba.Count) { $sup = $isoPorFila[$arriba[-1]] }   # mas nueva
    $inf = $null; if ($abajo.Count) { $inf = $isoPorFila[$abajo[0]] }      # mas vieja
    $mejor = $null; $mejorScore = [double]::MaxValue
    foreach ($y in @(2021, 2022, 2023)) {
      try { $d = (Get-Date -Year $y -Month $t.mes -Day $t.dia).Date } catch { continue }
      $ok = $true
      if ($sup -and $d -gt $sup.AddDays(10)) { $ok = $false }
      if ($inf -and $d -lt $inf.AddDays(-10)) { $ok = $false }
      if (-not $ok) { continue }
      $ref = if ($sup) { $sup } elseif ($inf) { $inf } else { $d }
      $score = [math]::Abs(($d - $ref).TotalDays) + $(if ($d.DayOfWeek -eq 'Monday') { 0 } else { 400 })
      if ($score -lt $mejorScore) { $mejorScore = $score; $mejor = $d }
    }
    if (-not $mejor) { try { $mejor = (Get-Date -Year 2021 -Month $t.mes -Day $t.dia).Date } catch { $mejor = $null } }
    if ($mejor) { $k = "$($t.texto)"; if (-not $mapaTexto.ContainsKey($k)) { $mapaTexto[$k] = @{} }; $kk = $mejor.ToString('yyyy-MM-dd'); if (-not $mapaTexto[$k].ContainsKey($kk)) { $mapaTexto[$k][$kk] = 0 }; $mapaTexto[$k][$kk]++; $f.semana = Lunes $mejor } else { $f.semana = $null }
  }
  $filasM = @($filasM | Where-Object { $_.semana -ne $null })
  foreach ($k in ($mapaTexto.Keys | Sort-Object)) { $v = $mapaTexto[$k]; [void]$resumenHojas.Add(('texto "{0}" -> {1}' -f $k, (($v.Keys | Sort-Object | ForEach-Object { '{0} ({1})' -f $_, $v[$_] }) -join ', '))) }
}
# 2) hojas semanales, de la mas vieja a la mas nueva
$semanales = @()
foreach ($h in $hojasT) {
  if ($h.nombre -eq 'PEDIDOS CUBIERTAS') { continue }
  $rows = LeerHoja $h.archivo
  $anio = AnioPorIndice $h.idx
  $fn = FechaDeNombre $h.nombre $h.idx
  $ft = FechaDeTitulo $rows $(if ($anio) { $anio } elseif ($fn) { $fn.Year } else { 2024 })
  # moda de las fechas ISO de la hoja
  $fechasIso = @(); foreach ($r in $rows) { foreach ($p in $r.PSObject.Properties) { if ($p.Name -ne 'fila') { $d = FechaDe "$($p.Value)"; if ($d -and $d.Year -ge 2021 -and $d.Year -le 2026) { $fechasIso += $d } } } }
  $moda = $null; if ($fechasIso.Count) { $moda = ($fechasIso | Group-Object { $_.ToString('yyyy-MM-dd') } | Sort-Object Count -Descending | Select-Object -First 1).Group[0] }
  $sem = $null; $como = ''
  if ($fn -and $fn.DayOfWeek -eq 'Monday') { $sem = $fn; $como = 'nombre' }
  elseif ($moda -and $moda.DayOfWeek -eq 'Monday' -and $fn -and [math]::Abs(($moda - $fn).TotalDays) -le 14) { $sem = $moda; $como = 'fechas de la hoja' }
  elseif ($ft -and $ft.DayOfWeek -eq 'Monday' -and $fn -and [math]::Abs(($ft - $fn).TotalDays) -le 45) { $sem = $ft; $como = 'titulo' }
  elseif ($fn) { $sem = Lunes $fn; $como = 'nombre (ajustado al lunes)' }
  elseif ($ft) { $sem = Lunes $ft; $como = 'titulo (ajustado)' }
  elseif ($moda) { $sem = Lunes $moda; $como = 'fechas (ajustado)' }
  if (-not $sem) { Aviso "Taller: no pude fechar la hoja '$($h.nombre)'"; continue }
  $semanales += [pscustomobject]@{ info = $h; rows = $rows; semana = $sem; como = $como }
}
$semanales = @($semanales | Sort-Object semana, { $_.info.idx })

function RegistrarYDedup($filas, $nombreHoja) {
  $conteo = @{}
  foreach ($f in $filas) { $k = '{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}' -f (Norm $f.comprador), (Norm $f.madera), $f.medida1, $f.medida2, $f.m2, $f.costo_cristian, $f.precio_pieza, $f.num; $f | Add-Member -NotePropertyName clave -NotePropertyValue $k -Force; if (-not $conteo.ContainsKey($k)) { $conteo[$k] = 0 }; $conteo[$k]++ }
  $marcados = @{}; $dups = 0
  foreach ($f in $filas) {
    $k = $f.clave; $previas = 0; if ($vistos.ContainsKey($k)) { $previas = $vistos[$k] }
    if (-not $marcados.ContainsKey($k)) { $marcados[$k] = 0 }
    if ($marcados[$k] -lt $previas) { $f.duplicado = 1; $dups++ }
    $marcados[$k]++
  }
  foreach ($k in $conteo.Keys) { $prev = 0; if ($vistos.ContainsKey($k)) { $prev = $vistos[$k] }; if ($conteo[$k] -gt $prev) { $vistos[$k] = $conteo[$k] } }
  return $dups
}
$dupsM = RegistrarYDedup $filasM 'PEDIDOS CUBIERTAS'
foreach ($f in $filasM) { [void]$taller.Add($f) }
[void]$resumenHojas.Add(('PEDIDOS CUBIERTAS: {0} piezas, {1} duplicadas' -f $filasM.Count, $dupsM))
foreach ($s in $semanales) {
  $fs = ProcesarHojaTaller $s.info $s.rows $false $s.semana
  $d = RegistrarYDedup $fs $s.info.nombre
  foreach ($f in $fs) { [void]$taller.Add($f) }
  [void]$resumenHojas.Add(('{0,-22} semana {1} ({2}) {3} piezas, {4} dup' -f $s.info.nombre, $s.semana.ToString('yyyy-MM-dd'), $s.como, $fs.Count, $d))
}
foreach ($f in $taller) { $f.mes = $f.semana.ToString('yyyy-MM'); $f.semana = $f.semana.ToString('yyyy-MM-dd') }
$tallerOk = @($taller | Where-Object { $_.duplicado -eq 0 })

# Precio estimado para las piezas que solo traen el costo de Cristian: razon precio/costo mediana del mismo mes
# (o del mes mas cercano con datos). La razon no fue fija: 1,2 en 2023-marzo 2024, 1,3 en 2022 y abril 2024, 1,35 desde junio 2024.
$ratioMes = @{}
foreach ($g in ($tallerOk | Where-Object { $_.precio_pieza -and $_.costo_cristian -and $_.costo_cristian -gt 0 -and $_.precio_pieza -gt 0 } | Group-Object mes)) {
  $rs = @($g.Group | ForEach-Object { [double]$_.precio_pieza / [double]$_.costo_cristian } | Where-Object { $_ -ge 1.0 -and $_ -le 2.0 } | Sort-Object)
  if ($rs.Count -ge 4) { $ratioMes[$g.Name] = [math]::Round($rs[[math]::Floor($rs.Count / 2)], 2) }
}
$mesesRatio = @($ratioMes.Keys | Sort-Object)
function RatioPara($mes) {
  if ($ratioMes.ContainsKey($mes)) { return $ratioMes[$mes] }
  $best = $null; $bd = 99999
  $dm = [datetime]::ParseExact($mes + '-01', 'yyyy-MM-dd', $INV)
  foreach ($k in $mesesRatio) { $dk = [datetime]::ParseExact($k + '-01', 'yyyy-MM-dd', $INV); $d = [math]::Abs(($dk - $dm).TotalDays); if ($d -lt $bd) { $bd = $d; $best = $k } }
  if ($best) { return $ratioMes[$best] } return $null
}
foreach ($f in $taller) {
  $f | Add-Member -NotePropertyName precio_est -NotePropertyValue $null -Force
  $f | Add-Member -NotePropertyName precio_est_tipo -NotePropertyValue '' -Force
  if ($f.precio_pieza) { $f.precio_est = $f.precio_pieza; $f.precio_est_tipo = $f.precio_tipo }
  elseif ($f.costo_cristian -and $f.costo_cristian -gt 0) { $rt = RatioPara $f.mes; if ($rt) { $f.precio_est = [math]::Round($f.costo_cristian * $rt); $f.precio_est_tipo = ('estimado x' + $rt.ToString('0.00', $INV)) } }
}
foreach ($k in $mesesRatio) { [void]$resumenHojas.Add(('razon precio/costo {0}: x{1}' -f $k, $ratioMes[$k].ToString('0.00', $INV))) }

# ============================================================
#  C. RESUMEN MENSUAL
# ============================================================
function Suma($lista, $campo) { $s = (@($lista) | Measure-Object $campo -Sum).Sum; if ($s) { return [double]$s } return 0.0 }
$histPath = 'C:\Users\dell\Casa Zaru Planillas\historial-mensual.csv'
$libro = @{}; if (Test-Path $histPath) { foreach ($r in (Import-Csv $histPath -Delimiter ';' -Encoding UTF8)) { $libro["$($r.Mes)"] = [double]("0" + ("$($r.VentaNeta)" -replace '[^\d\.-]', '')) } }
# SII: resumen del Registro de Ventas por mes y tipo de documento (sii-ventas-mensual.csv: periodo;tipo;docs;exento;neto;iva;total).
# Documentado = facturas (33) + boletas (39) + boletas exentas (41) + comprobantes de pago electronico (48) - notas de credito (61).
$sii = @{}
$siiPath = Join-Path $Salida 'sii-ventas-mensual.csv'
if (Test-Path -LiteralPath $siiPath) {
  foreach ($r in (Import-Csv -LiteralPath $siiPath -Delimiter ';' -Encoding UTF8)) {
    $p = "$($r.periodo)"; if ($p.Length -ne 6) { continue }
    $m = $p.Substring(0, 4) + '-' + $p.Substring(4, 2)
    if (-not $sii.ContainsKey($m)) { $sii[$m] = @{ docs = 0; neto = 0.0; total = 0.0; nc = 0.0; ncDocs = 0; facturas = 0.0; boletas = 0.0 } }
    $t = [int]$r.tipo; $docs = [int]("0" + $r.docs); $neto = [double]("0" + $r.neto); $tot = [double]("0" + $r.total)
    if ($t -eq 61) { $sii[$m].nc += $tot; $sii[$m].ncDocs += $docs; $sii[$m].neto -= $neto; $sii[$m].total -= $tot }
    elseif ($t -in @(33, 39, 41, 48)) { $sii[$m].docs += $docs; $sii[$m].neto += $neto; $sii[$m].total += $tot; if ($t -eq 33) { $sii[$m].facturas += $tot } else { $sii[$m].boletas += $tot } }
  }
}
$meses = @(); $d0 = Get-Date -Year 2021 -Month 7 -Day 1; $d1 = Get-Date -Year 2026 -Month 10 -Day 1
for ($d = $d0; $d -le $d1; $d = $d.AddMonths(1)) { $meses += $d.ToString('yyyy-MM') }
$resumen = @()
foreach ($m in $meses) {
  $vm = @($ventas | Where-Object { $_.mes -eq $m -and $_.tipo -eq 'VENTA' })
  $nV = 0; if ($vm.Count) { $nV = @($vm | ForEach-Object { if ($_.num) { 'n' + $_.num } else { 'f' + $_.fuente + $_.fila } } | Sort-Object -Unique).Count }
  $venta = Suma $vm 'valor'; $total = Suma $vm 'total'; $envio = Suma $vm 'envio'
  $fuentes = (@($vm | ForEach-Object { $_.fuente } | Sort-Object -Unique) -join '+')
  $tm = @($tallerOk | Where-Object { $_.mes -eq $m })
  $piezas = $tm.Count; $m2 = Suma $tm 'm2'; $costo = Suma $tm 'costo_cristian'; $precioT = Suma $tm 'precio_pieza'
  $pedidosT = 0; $ventaPed = 0.0
  if ($piezas) {
    $conNum = @($tm | Where-Object { $_.num })
    $grupos = @($conNum | Group-Object num)
    $pedidosT = $grupos.Count + @($tm | Where-Object { -not $_.num } | Group-Object { Norm $_.comprador }).Count
    foreach ($g in $grupos) { $vp = @($g.Group | Where-Object { $_.venta_pedido } | Select-Object -First 1); if ($vp.Count) { $ventaPed += [double]$vp[0].venta_pedido } }
  }
  $tipos = (@($tm | Where-Object { $_.precio_est_tipo } | Group-Object precio_est_tipo | Sort-Object Count -Descending | ForEach-Object { $_.Name + ' ' + $_.Count }) -join ' / ')
  $conPrecio = @($tm | Where-Object { $_.precio_pieza }).Count
  $ventaEst = Suma $tm 'precio_est'
  $serie = $null; $calidad = ''
  if ($vm.Count) { $serie = $venta; $calidad = 'planilla de ventas' + $(if ($fuentes -eq 'gestion') { ' (Gestion)' } else { '' }) }
  elseif ($ventaEst -gt 0) { $serie = $ventaEst; $calidad = ('taller: {0} de {1} piezas con precio; {2}' -f $conPrecio, $piezas, $tipos) }
  elseif ($ventaPed -gt 0) { $serie = $ventaPed; $calidad = 'taller: total por pedido' }
  $resumen += [pscustomobject]@{
    mes = $m; ventas_n = $nV; venta_bruta = [math]::Round($venta); venta_neta = [math]::Round($venta / (1 + $IVA)); total_pagado = [math]::Round($total); envio = [math]::Round($envio); fuente_ventas = $fuentes
    taller_pedidos = $pedidosT; taller_piezas = $piezas; taller_piezas_con_precio = $conPrecio; taller_m2 = [math]::Round($m2, 2); taller_costo = [math]::Round($costo); taller_venta_piezas = [math]::Round($precioT); taller_venta_estimada = [math]::Round($ventaEst); taller_venta_pedidos = [math]::Round($ventaPed); taller_precio_tipo = $tipos
    serie_bruta = $(if ($null -ne $serie) { [math]::Round($serie) } else { $null }); serie_neta = $(if ($null -ne $serie) { [math]::Round($serie / (1 + $IVA)) } else { $null }); calidad = $calidad
    libro_venta_neta = $(if ($libro.ContainsKey($m)) { [math]::Round($libro[$m]) } else { $null })
    sii_docs = $(if ($sii.ContainsKey($m)) { [int]$sii[$m].docs } else { $null })
    sii_facturas = $(if ($sii.ContainsKey($m)) { [math]::Round($sii[$m].facturas) } else { $null })
    sii_boletas = $(if ($sii.ContainsKey($m)) { [math]::Round($sii[$m].boletas) } else { $null })
    sii_notas_credito = $(if ($sii.ContainsKey($m)) { [math]::Round($sii[$m].nc) } else { $null })
    sii_total = $(if ($sii.ContainsKey($m)) { [math]::Round($sii[$m].total) } else { $null })
    sii_neto = $(if ($sii.ContainsKey($m)) { [math]::Round($sii[$m].neto) } else { $null })
    pct_documentado = $(if ($sii.ContainsKey($m) -and $null -ne $serie -and $serie -gt 0) { [math]::Round($sii[$m].total / $serie, 3) } else { $null })
  }
}
$porAnio = @()
foreach ($g in ($resumen | Group-Object { $_.mes.Substring(0, 4) })) {
  $con = @($g.Group | Where-Object { $null -ne $_.serie_bruta })
  $porAnio += [pscustomobject]@{
    anio = $g.Name; meses_con_datos = $con.Count; meses = (($con | ForEach-Object { $_.mes.Substring(5) }) -join ' ')
    ventas_n = (Suma $con 'ventas_n'); venta_bruta_planillas = [math]::Round((Suma $con 'venta_bruta')); serie_bruta = [math]::Round((Suma $con 'serie_bruta')); serie_neta = [math]::Round((Suma $con 'serie_neta'))
    taller_pedidos = (Suma $con 'taller_pedidos'); taller_piezas = (Suma $con 'taller_piezas'); taller_m2 = [math]::Round((Suma $con 'taller_m2'), 1); taller_costo = [math]::Round((Suma $con 'taller_costo')); taller_venta_estimada = [math]::Round((Suma $con 'taller_venta_estimada'))
    sii_docs = (Suma $con 'sii_docs'); sii_total = [math]::Round((Suma $con 'sii_total')); sii_neto = [math]::Round((Suma $con 'sii_neto'))
    pct_documentado = $(if ((Suma $con 'serie_bruta') -gt 0) { [math]::Round((Suma $con 'sii_total') / (Suma $con 'serie_bruta'), 3) } else { $null })
    calidades = ((@($con | ForEach-Object { $_.calidad }) | Sort-Object -Unique) -join ' | ')
  }
}

# ============================================================
#  D. CRUCES
# ============================================================
# 1) ventas (planilla) vs taller por numero de venta
$cruce1 = @()
$tPorNum = @{}; foreach ($f in $tallerOk) { if ($f.num -and $f.mes -ge '2024-07') { $k = "$($f.num)"; if (-not $tPorNum.ContainsKey($k)) { $tPorNum[$k] = @() }; $tPorNum[$k] += $f } }
foreach ($g in ($ventas | Where-Object { $_.num -and $_.mes -ge '2024-09' -and $_.mes -le '2025-07' -and $_.fuente -ne 'gestion' } | Group-Object num)) {
  $vv = Suma $g.Group 'valor'; $k = $g.Name
  $tp = $null; $tpz = $null; $comp = ''; $semT = ''
  if ($tPorNum.ContainsKey($k)) {
    $tf = $tPorNum[$k]; $comp = $tf[0].comprador; $semT = $tf[0].semana
    $vp = @($tf | Where-Object { $_.venta_pedido } | Select-Object -First 1); if ($vp.Count) { $tp = [double]$vp[0].venta_pedido }
    $tpz = Suma $tf 'precio_pieza'
  }
  $ref = if ($null -ne $tp -and $tp -gt 0) { $tp } else { $tpz }
  $dif = $null; if ($null -ne $ref -and $ref -gt 0) { $dif = [math]::Round($vv - $ref) }
  $cruce1 += [pscustomobject]@{ num = [int]$k; mes_venta = $g.Group[0].mes; cliente = $g.Group[0].cliente; valor_planilla = [math]::Round($vv); taller_semana = $semT; taller_comprador = $comp; taller_total_pedido = $(if ($null -ne $tp) { [math]::Round($tp) } else { $null }); taller_suma_piezas = $(if ($null -ne $tpz) { [math]::Round($tpz) } else { $null }); diferencia = $dif; estado = $(if (-not $tPorNum.ContainsKey($k)) { 'sin taller' } elseif ($null -ne $dif -and [math]::Abs($dif) -le [math]::Max(5000, 0.05 * $vv)) { 'calza' } else { 'revisar' }) }
}
$cruce1 = @($cruce1 | Sort-Object num)
# 2) totales por mes y fuente (principal y alternativas)
$cruce2 = @()
foreach ($g in ($ventasTodas | Where-Object { $_.tipo -eq 'VENTA' } | Group-Object mes, fuente, principal | Sort-Object Name)) {
  $cruce2 += [pscustomobject]@{ mes = $g.Group[0].mes; fuente = $g.Group[0].fuente; principal = $g.Group[0].principal; hojas = ((@($g.Group | ForEach-Object { $_.hoja }) | Sort-Object -Unique) -join ', '); ventas_n = @($g.Group | ForEach-Object { if ($_.num) { 'n' + $_.num } else { 'f' + $_.fila } } | Sort-Object -Unique).Count; valor = [math]::Round((Suma $g.Group 'valor')) }
}
# 3) planilla 2026 vs Gestion por numero (may-ago 2026)
$cruce3 = @()
$gest = @{}; foreach ($v in $ventasAlt) { if ($v.fuente -eq 'gestion' -and $v.num) { $gest[$v.num] = $v } }
foreach ($g in ($ventas | Where-Object { $_.fuente -eq 'vgen' -and $_.mes -ge '2026-05' -and $_.num } | Group-Object num)) {
  $vv = Suma $g.Group 'valor'; $k = $g.Name; $gv = $null; $gc = ''
  if ($gest.ContainsKey($k)) { $gv = [double]$gest[$k].valor; $gc = $gest[$k].cliente }
  $cruce3 += [pscustomobject]@{ num = $k; mes = $g.Group[0].mes; cliente_planilla = $g.Group[0].cliente; valor_planilla = [math]::Round($vv); cliente_gestion = $gc; valor_gestion = $(if ($null -ne $gv) { [math]::Round($gv) } else { $null }); diferencia = $(if ($null -ne $gv) { [math]::Round($vv - $gv) } else { $null }); estado = $(if ($null -eq $gv) { 'no esta en Gestion' } elseif ([math]::Abs($vv - $gv) -le 1000) { 'calza' } else { 'revisar' }) }
}
foreach ($k in $gest.Keys) { if (-not ($cruce3 | Where-Object { "$($_.num)" -eq $k })) { $x = $gest[$k]; if ($x.mes -le '2026-08' -and $x.tipo -eq 'VENTA') { $cruce3 += [pscustomobject]@{ num = $k; mes = $x.mes; cliente_planilla = ''; valor_planilla = $null; cliente_gestion = $x.cliente; valor_gestion = $x.valor; diferencia = $null; estado = 'solo en Gestion' } } } }
$cruce3 = @($cruce3 | Sort-Object { [int]('0' + ("$($_.num)" -replace '\D', '')) }, num)

# ============================================================
#  E. SALIDAS
# ============================================================
$colsV = @('mes', 'num', 'fecha', 'semana', 'cliente', 'vendedor', 'canal', 'medio', 'producto', 'como', 'valor', 'total', 'envio', 'comision', 'abonos', 'pendiente', 'doc', 'estado', 'tipo', 'correo', 'celular', 'item_extra', 'nota', 'fuente', 'archivo', 'hoja', 'fila', 'principal')
$ventasCsv = @($ventasTodas | Sort-Object mes, { [int]('0' + ("$($_.num)" -replace '\D', '')) }, fila | Select-Object $colsV)
GuardarCsv $ventasCsv (Join-Path $Salida 'ventas-historico.csv')
$colsT = @('mes', 'semana', 'num', 'comprador', 'tipo', 'madera', 'medida1', 'medida2', 'medida_txt', 'canto', 'acabado', 'espesor', 'cantidad', 'm2', 'costo_cristian', 'precio_pieza', 'precio_tipo', 'precio_est', 'precio_est_tipo', 'venta_pedido', 'abonos', 'pagado', 'medio', 'estado', 'obs', 'semana_origen', 'duplicado', 'hoja', 'fila')
GuardarCsv @($taller | Sort-Object semana, hoja, fila | Select-Object $colsT) (Join-Path $Salida 'taller-historico.csv')
GuardarCsv $resumen (Join-Path $Salida 'resumen-mensual.csv')
GuardarCsv $porAnio (Join-Path $Salida 'resumen-anual.csv')
GuardarCsv $cruce1 (Join-Path $Salida 'cruce-ventas-vs-taller.csv')
GuardarCsv $cruce2 (Join-Path $Salida 'cruce-fuentes-por-mes.csv')
GuardarCsv $cruce3 (Join-Path $Salida 'cruce-planilla-vs-gestion-2026.csv')
[IO.File]::WriteAllLines((Join-Path $Salida 'hojas-taller-fechadas.txt'), @($resumenHojas), (New-Object Text.UTF8Encoding $true))

# --- Excel ---
$gen = (Get-Date).ToString('dd-MM-yyyy HH:mm')
$NOTAS = @(
  'Qué es: todas las ventas y pedidos de Casa Zaru que quedaron en planillas antes de la app de Gestión, más Gestión desde septiembre 2026, en un solo formato.',
  'Serie oficial por mes (hoja Resumen mensual, columna Serie bruta): desde septiembre 2024 es la planilla de ventas (valor del producto, con IVA, sin envío ni comisiones). Antes de eso solo existe el registro del taller, y el valor depende de la época: 2021 = precio de lista anotado en la hoja; enero-febrero 2022 = precio en la columna de la derecha; marzo 2022 a mayo 2024 = fórmula costo Cristián × 1,2 o 1,3 según el mes (no es el precio cobrado); junio-octubre 2024 = VALOR VENTA (costo × 1,35 o precio real); desde noviembre 2024 = precio real por ítem. Las piezas que solo traen costo se estiman con la razón precio/costo mediana de su mes (columna Taller venta estimada y hoja Fuentes y notas); la columna Calidad dice cuántas piezas del mes tienen precio de verdad.',
  'Las semanas se nombran por su lunes. La planilla "2024" en realidad va de septiembre 2024 a junio 2025: sus semanas 2, 9, 23 y 30 de septiembre son lunes de 2024 y las fechas de octubre dicen 2024.',
  'Numeración de ventas: la actual parte en la semana del 1 de abril de 2024 (VENTA 1 en la hoja del taller); #61 el 2 de septiembre de 2024; #205 en julio 2025; #346 en diciembre 2025; #446 en abril 2026; en mayo 2026 saltó a #1447 con la app de Gestión. En 2021 había otra numeración (142 a 187 entre julio y agosto de 2021).',
  'Fuentes: VENTAS CASA ZARU 2024 .xlsx (sep 2024-jun 2025), VENTAS CASA ZARU 2025 (1).xlsx (jul-sep 2025; octubre incompleto y noviembre vacío), VENTAS GENERAL 2025 - 2026 (4).xlsx (ago 2025-ago 2026; agosto-noviembre 2025 en formato Meta con WTSP), PEDIDOS CASA ZARU TALLER 2024.xlsx (semanas del 20-11-2023 al 14-07-2025 y la hoja PEDIDOS CUBIERTAS con el registro desde julio 2021), respaldo diario de Gestión (may-oct 2026).',
  'Cuando dos fuentes cubren el mismo mes, manda una (columna principal = 1) y la otra queda en Ventas alternativas para cruzar: julio 2025 manda la planilla 2025; agosto-septiembre 2025 manda la planilla 2025 (la general trae lo mismo en formato Meta); octubre 2025 en adelante manda la general; mayo-agosto 2026 manda la general y Gestión queda de cruce; septiembre 2026 en adelante manda Gestión.',
  'Taller: una fila por pieza. Las piezas que aparecen en dos hojas (la maestra y la semanal, o una semana y la siguiente como pendiente) se marcan duplicado = 1 y no se cuentan. m² normalizado (las hojas viejas anotaban cm²).',
  'No está: enero-agosto 2024 como ventas (solo taller). Devoluciones y muestrarios no suman como venta.',
  'SII (columnas SII y % documentado): Registro de Ventas del SII de Muvale Diseño SpA leído el 31-10-2026 mes a mes (sii-ventas-mensual.csv): facturas electrónicas (33) + boletas electrónicas (39) + boletas exentas (41) + comprobantes de pago electrónico (48) menos notas de crédito (61), en estado Registro. % documentado = SII total con IVA / serie bruta del mes. Es lo que el SII tiene registrado, no necesariamente lo declarado en el F29.',
  'Generado el ' + $gen + ' con scratchpad\ventas-hist\scripts\consolidar.ps1. Privado: trae nombres, correos y celulares. No va al repo.'
)
$f = New-Object System.Collections.ArrayList
Titulo $f 'Casa Zaru - Histórico de ventas 2021-2026' "Resumen por mes. serie_bruta = venta del mes con IVA según la mejor fuente disponible (ver columna calidad y la hoja Fuentes y notas). Generado $gen."
$colsR = @('Mes', 'Ventas (n)', 'Venta bruta planilla', 'Venta neta planilla', 'Total pagado', 'Envío', 'Fuente', 'Taller pedidos', 'Taller piezas', 'Piezas con precio', 'Taller m²', 'Costo Cristián', 'Taller venta piezas', 'Taller venta estimada', 'Taller venta pedidos', 'Tipo precio taller', 'Serie bruta', 'Serie neta', 'Calidad', 'Libro mensual (neto, con ML y ferias)', 'SII docs', 'SII facturas', 'SII boletas y comprobantes', 'SII notas de crédito', 'SII total (con IVA)', 'SII neto', '% documentado')
$datosR = foreach ($r in $resumen) { ,@((C $r.mes), (C ([int]$r.ventas_n)), (C ([double]$r.venta_bruta) 2), (C ([double]$r.venta_neta) 2), (C ([double]$r.total_pagado) 2), (C ([double]$r.envio) 2), (C $r.fuente_ventas), (C ([int]$r.taller_pedidos)), (C ([int]$r.taller_piezas)), (C ([int]$r.taller_piezas_con_precio)), (C ([double]$r.taller_m2) 8), (C ([double]$r.taller_costo) 2), (C ([double]$r.taller_venta_piezas) 2), (C ([double]$r.taller_venta_estimada) 2), (C ([double]$r.taller_venta_pedidos) 2), (C $r.taller_precio_tipo), (C $(if ($null -ne $r.serie_bruta) { [double]$r.serie_bruta } else { '' }) 2), (C $(if ($null -ne $r.serie_neta) { [double]$r.serie_neta } else { '' }) 2), (C $r.calidad), (C $(if ($null -ne $r.libro_venta_neta) { [double]$r.libro_venta_neta } else { '' }) 2), (C $(if ($null -ne $r.sii_docs) { [int]$r.sii_docs } else { '' })), (C $(if ($null -ne $r.sii_facturas) { [double]$r.sii_facturas } else { '' }) 2), (C $(if ($null -ne $r.sii_boletas) { [double]$r.sii_boletas } else { '' }) 2), (C $(if ($null -ne $r.sii_notas_credito) { [double]$r.sii_notas_credito } else { '' }) 2), (C $(if ($null -ne $r.sii_total) { [double]$r.sii_total } else { '' }) 2), (C $(if ($null -ne $r.sii_neto) { [double]$r.sii_neto } else { '' }) 2), (C $(if ($null -ne $r.pct_documentado) { [double]$r.pct_documentado } else { '' }) 4)) }
Tabla $f $colsR $datosR @(1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 20, 21, 22, 23, 24, 25)
Hoja 'Resumen mensual' $f @(9, 9, 15, 15, 13, 10, 12, 9, 9, 9, 9, 13, 14, 14, 14, 30, 14, 14, 44, 14, 8, 13, 14, 13, 14, 14, 10) 4
$f = New-Object System.Collections.ArrayList
Titulo $f 'Por año' 'Suma de los meses con datos. Un año parcial (2021, 2026) se nota en la columna meses.'
$colsA = @('Año', 'Meses con datos', 'Meses', 'Ventas (n)', 'Venta bruta planillas', 'Serie bruta', 'Serie neta', 'Taller pedidos', 'Taller piezas', 'Taller m²', 'Costo Cristián', 'Taller venta estimada', 'SII docs', 'SII total (con IVA)', 'SII neto', '% documentado', 'Calidad')
$datosA = foreach ($r in $porAnio) { ,@((C $r.anio), (C ([int]$r.meses_con_datos)), (C $r.meses), (C ([int]$r.ventas_n)), (C ([double]$r.venta_bruta_planillas) 2), (C ([double]$r.serie_bruta) 2), (C ([double]$r.serie_neta) 2), (C ([int]$r.taller_pedidos)), (C ([int]$r.taller_piezas)), (C ([double]$r.taller_m2) 8), (C ([double]$r.taller_costo) 2), (C ([double]$r.taller_venta_estimada) 2), (C ([int]$r.sii_docs)), (C ([double]$r.sii_total) 2), (C ([double]$r.sii_neto) 2), (C $(if ($null -ne $r.pct_documentado) { [double]$r.pct_documentado } else { '' }) 4), (C $r.calidades 14)) }
Tabla $f $colsA $datosA @(3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14)
Hoja 'Por año' $f @(8, 9, 34, 9, 16, 15, 15, 9, 9, 9, 14, 14, 8, 15, 14, 10, 60) 4
$f = New-Object System.Collections.ArrayList
Titulo $f 'Ventas (fuente principal de cada mes)' 'Una fila por venta o por ítem (item_extra = 1 cuando la planilla traía una segunda línea para la misma venta). valor = producto con IVA, sin envío ni comisiones cuando la planilla lo separaba.'
$colsVx = @('Mes', 'N°', 'Fecha', 'Semana', 'Cliente', 'Vendedor', 'Canal', 'Medio pago', 'Producto', 'Cómo nos conoció', 'Valor', 'Total pagado', 'Envío', 'Comisión', 'Abonos', 'Pendiente', 'Documento', 'Estado', 'Tipo', 'Correo', 'Celular', 'Ítem extra', 'Nota', 'Fuente', 'Hoja', 'Fila')
function FilaV($v) { ,@((C $v.mes), (C $v.num), (C $v.fecha), (C $v.semana), (C $v.cliente), (C $v.vendedor), (C $v.canal), (C $v.medio), (C $v.producto), (C $v.como), (C ([double]$v.valor) 2), (C $(if ($null -ne $v.total) { [double]$v.total } else { '' }) 2), (C $(if ($null -ne $v.envio) { [double]$v.envio } else { '' }) 2), (C $(if ($null -ne $v.comision) { [double]$v.comision } else { '' }) 2), (C $(if ($null -ne $v.abonos) { [double]$v.abonos } else { '' }) 2), (C $(if ($null -ne $v.pendiente) { [double]$v.pendiente } else { '' }) 2), (C $v.doc), (C $v.estado), (C $v.tipo), (C $v.correo), (C $v.celular), (C ([int]$v.item_extra)), (C $v.nota), (C $v.fuente), (C $v.hoja), (C ([int]$v.fila))) }
$datosV = foreach ($v in ($ventas | Sort-Object mes, { [int]('0' + ("$($_.num)" -replace '\D', '')) }, fila)) { FilaV $v }
Tabla $f $colsVx $datosV @(10, 11, 12, 13, 14, 15)
Hoja 'Ventas' $f @(8, 6, 11, 18, 26, 9, 10, 14, 22, 16, 13, 13, 10, 10, 13, 12, 16, 10, 10, 26, 14, 6, 24, 8, 20, 5) 4
$f = New-Object System.Collections.ArrayList
Titulo $f 'Ventas alternativas (otra fuente del mismo mes, solo para cruzar)' 'No suman en el resumen. Sirven para comparar: julio 2025 (planilla 2024), agosto-septiembre 2025 (general, formato Meta), octubre 2025 (planilla 2025, incompleta), diciembre 2025 (detalle), mayo-agosto 2026 (Gestión).'
$datosV2 = foreach ($v in ($ventasAlt | Sort-Object mes, { [int]('0' + ("$($_.num)" -replace '\D', '')) }, fila)) { FilaV $v }
Tabla $f $colsVx $datosV2 @(10, 11, 12, 13, 14, 15)
Hoja 'Ventas alternativas' $f @(8, 6, 11, 18, 26, 9, 10, 14, 22, 16, 13, 13, 10, 10, 13, 12, 16, 10, 10, 26, 14, 6, 24, 8, 20, 5) 4
$f = New-Object System.Collections.ArrayList
Titulo $f 'Taller (una fila por pieza)' 'Semanas por su lunes. Tipo precio: venta_item (precio real por ítem), valor_venta (costo × 1,35 o precio real), formula (costo Cristián × 1,2 o 1,3, según la época), lista (precio anotado en 2021-2022). Precio estimado = el precio cuando existe; si no, costo × la razón precio/costo de ese mes. Las piezas duplicadas quedaron fuera.'
$colsTx = @('Mes', 'Semana', 'N° venta', 'Comprador', 'Tipo', 'Madera', 'Medida 1', 'Medida 2', 'Medida (texto)', 'Canto', 'Acabado', 'Espesor', 'Cantidad', 'm²', 'Costo Cristián', 'Precio pieza', 'Tipo precio', 'Precio estimado', 'Tipo estimado', 'Venta pedido', 'Abonos', 'Pagado', 'Medio', 'Estado', 'Obs', 'Origen semana', 'Hoja', 'Fila')
$datosT = foreach ($t in ($tallerOk | Sort-Object semana, hoja, fila)) { ,@((C $t.mes), (C $t.semana), (C $(if ($t.num) { [int]$t.num } else { '' })), (C $t.comprador), (C $t.tipo), (C $t.madera), (C $(if ($null -ne $t.medida1) { [double]$t.medida1 } else { '' }) 8), (C $(if ($null -ne $t.medida2) { [double]$t.medida2 } else { '' }) 8), (C $t.medida_txt), (C $t.canto), (C $t.acabado), (C $t.espesor), (C $(if ($null -ne $t.cantidad) { [double]$t.cantidad } else { '' }) 8), (C $(if ($null -ne $t.m2) { [double]$t.m2 } else { '' }) 8), (C $(if ($null -ne $t.costo_cristian) { [double]$t.costo_cristian } else { '' }) 2), (C $(if ($null -ne $t.precio_pieza) { [double]$t.precio_pieza } else { '' }) 2), (C $t.precio_tipo), (C $(if ($null -ne $t.precio_est) { [double]$t.precio_est } else { '' }) 2), (C $t.precio_est_tipo), (C $(if ($null -ne $t.venta_pedido) { [double]$t.venta_pedido } else { '' }) 2), (C $(if ($null -ne $t.abonos) { [double]$t.abonos } else { '' }) 2), (C $(if ($null -ne $t.pagado) { [double]$t.pagado } else { '' }) 2), (C $t.medio), (C $t.estado), (C $t.obs), (C $t.semana_origen), (C $t.hoja), (C ([int]$t.fila))) }
Tabla $f $colsTx $datosT @(13, 14, 15, 17, 19)
Hoja 'Taller' $f @(8, 11, 7, 22, 9, 18, 8, 8, 22, 16, 16, 8, 8, 8, 13, 13, 12, 13, 14, 13, 12, 12, 12, 10, 18, 9, 18, 5) 4
$f = New-Object System.Collections.ArrayList
Titulo $f 'Cruces' 'Tres controles: planilla de ventas vs taller por número (sep 2024-jul 2025); totales por mes según cada fuente; planilla 2026 vs Gestión por número (may-ago 2026).'
Sub $f '1. Planilla de ventas vs taller (por número de venta)'
Tabla $f @('N°', 'Mes venta', 'Cliente', 'Valor planilla', 'Semana taller', 'Comprador taller', 'Total pedido taller', 'Suma piezas taller', 'Diferencia', 'Estado') @(foreach ($c in $cruce1) { ,@((C $c.num), (C $c.mes_venta), (C $c.cliente), (C ([double]$c.valor_planilla) 2), (C $c.taller_semana), (C $c.taller_comprador), (C $(if ($null -ne $c.taller_total_pedido) { [double]$c.taller_total_pedido } else { '' }) 2), (C $(if ($null -ne $c.taller_suma_piezas) { [double]$c.taller_suma_piezas } else { '' }) 2), (C $(if ($null -ne $c.diferencia) { [double]$c.diferencia } else { '' }) 2), (C $c.estado)) })
Sub $f '2. Totales por mes y fuente (principal = 1 es la que manda)'
Tabla $f @('Mes', 'Fuente', 'Principal', 'Hojas', 'Ventas (n)', 'Valor') @(foreach ($c in $cruce2) { ,@((C $c.mes), (C $c.fuente), (C ([int]$c.principal)), (C $c.hojas), (C ([int]$c.ventas_n)), (C ([double]$c.valor) 2)) })
Sub $f '3. Planilla general 2026 vs Gestión (por número)'
Tabla $f @('N°', 'Mes', 'Cliente planilla', 'Valor planilla', 'Cliente Gestión', 'Valor Gestión', 'Diferencia', 'Estado') @(foreach ($c in $cruce3) { ,@((C $c.num), (C $c.mes), (C $c.cliente_planilla), (C $(if ($null -ne $c.valor_planilla) { [double]$c.valor_planilla } else { '' }) 2), (C $c.cliente_gestion), (C $(if ($null -ne $c.valor_gestion) { [double]$c.valor_gestion } else { '' }) 2), (C $(if ($null -ne $c.diferencia) { [double]$c.diferencia } else { '' }) 2), (C $c.estado)) })
Hoja 'Cruces' $f @(8, 10, 26, 14, 14, 22, 14, 14, 12, 14) 0
$f = New-Object System.Collections.ArrayList
Titulo $f 'Fuentes y notas' ''
foreach ($n in $NOTAS) { [void]$f.Add(@(C $n 14)) }
[void]$f.Add(@())
Sub $f 'Cómo se fechó cada hoja del taller'
foreach ($l in $resumenHojas) { [void]$f.Add(@(C $l)) }
if ($avisos.Count) { [void]$f.Add(@()); Sub $f 'Avisos'; foreach ($a in $avisos) { [void]$f.Add(@(C $a 10)) } }
Hoja 'Fuentes y notas' $f @(140) 0
$xlsx = Join-Path $Salida 'Historico ventas Casa Zaru 2021-2026.xlsx'
GuardarXlsx $xlsx

if (-not $SinDrive -and (Test-Path 'G:\Mi unidad\Casa Zaru')) {
  New-Item -ItemType Directory -Force $Drive | Out-Null
  foreach ($x in (Get-ChildItem -LiteralPath $Salida -File)) { Copy-Item -LiteralPath $x.FullName -Destination (Join-Path $Drive $x.Name) -Force }
}

# --- consola ---
Write-Output ('Ventas principales: {0} filas; alternativas: {1}; taller: {2} piezas ({3} duplicadas fuera)' -f $ventas.Count, $ventasAlt.Count, $tallerOk.Count, (@($taller | Where-Object { $_.duplicado -eq 1 }).Count))
Write-Output ('Respaldo Gestion: ' + $respNombre)
Write-Output ''
Write-Output ('{0,-8} {1,4} {2,14} {3,5} {4,4} {5,4} {6,7} {7,12} {8,12} {9,14}  {10}' -f 'Mes', 'n', 'venta_bruta', 'tPed', 'tPz', 'cP', 'm2', 'costo', 'taller_est', 'serie_bruta', 'calidad')
foreach ($r in $resumen) { Write-Output ('{0,-8} {1,4} {2,14:N0} {3,5} {4,4} {5,4} {6,7:N1} {7,12:N0} {8,12:N0} {9,14:N0}  {10}' -f $r.mes, $r.ventas_n, $r.venta_bruta, $r.taller_pedidos, $r.taller_piezas, $r.taller_piezas_con_precio, $r.taller_m2, $r.taller_costo, $r.taller_venta_estimada, $r.serie_bruta, $r.calidad) }
Write-Output ''
foreach ($r in $porAnio) { Write-Output ('{0}: {1} meses [{2}] ventas_n={3} serie_bruta={4:N0} serie_neta={5:N0} taller_pedidos={6} piezas={7} m2={8} sii_docs={9} sii_total={10:N0} pct_doc={11:P1}' -f $r.anio, $r.meses_con_datos, $r.meses, $r.ventas_n, $r.serie_bruta, $r.serie_neta, $r.taller_pedidos, $r.taller_piezas, $r.taller_m2, $r.sii_docs, $r.sii_total, $r.pct_documentado) }
Write-Output ''
Write-Output 'SII por mes: mes | serie_bruta | sii_total | % documentado'
foreach ($r in $resumen) { if ($null -ne $r.sii_total) { Write-Output ('{0} {1,14:N0} {2,14:N0} {3,8:P1}' -f $r.mes, $r.serie_bruta, $r.sii_total, $r.pct_documentado) } }
Write-Output ''
Write-Output ('Cruce ventas vs taller: {0} numeros; calza={1} revisar={2} sin taller={3}' -f $cruce1.Count, @($cruce1 | Where-Object { $_.estado -eq 'calza' }).Count, @($cruce1 | Where-Object { $_.estado -eq 'revisar' }).Count, @($cruce1 | Where-Object { $_.estado -eq 'sin taller' }).Count)
Write-Output ('Cruce planilla vs Gestion 2026: {0} numeros; calza={1} revisar={2} no en Gestion={3} solo Gestion={4}' -f $cruce3.Count, @($cruce3 | Where-Object { $_.estado -eq 'calza' }).Count, @($cruce3 | Where-Object { $_.estado -eq 'revisar' }).Count, @($cruce3 | Where-Object { $_.estado -eq 'no esta en Gestion' }).Count, @($cruce3 | Where-Object { $_.estado -eq 'solo en Gestion' }).Count)
if ($avisos.Count) { Write-Output ''; Write-Output 'AVISOS:'; $avisos | ForEach-Object { Write-Output ('  - ' + $_) } }
Write-Output ''
Write-Output ('Archivos en ' + $Salida)
