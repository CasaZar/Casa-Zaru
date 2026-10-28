# Libro mensual de Casa Zaru (Excel, 19 hojas) + tablero HTML y PDF — el cierre con números de gerente de finanzas
#
# Junta: ventas (respaldo de Gestión), facturas recibidas (planilla de gastos Wasabil, ya clasificada
# con las categorías oficiales), pagos sin factura (cartolas BCI + Banco de Chile vía cargar-cartolas.ps1),
# Mercado Pago, documentos emitidos y el gasto real de Meta. Las clasificaciones salen de la planilla y de
# reglas-cierre.csv; este script no inventa categorías ni escribe números a mano.
#
# El repo es PÚBLICO: este script no lleva datos. Los datos viven en:
#   C:\Users\dell\Casa Zaru Planillas  planilla de gastos, reglas-cierre.csv, ferias.csv, por-pagar-manual.csv
#   %USERPROFILE%\.casazaru             mp-AAAA-MM.csv/.json, emitidas-AAAA-MM.csv, meta-AAAA-MM.json,
#                                       sii-AAAA-MM.json, kpis-cotizador.json
#   Descargas                           cartolas BCI 7175 y Banco de Chile
#   Drive                               respaldo diario de Gestión
#
# Uso:  .\libro-mensual.ps1 -Mes 2026-09
param(
  [string]$Mes,
  [string]$Salida = 'G:\Mi unidad\Casa Zaru\Informes Gestion',
  [string]$Respaldo   # ruta de un respaldo-gestion-*.json puntual (por defecto, el más nuevo de Drive)
)
$ErrorActionPreference = 'Stop'
$cl  = [Globalization.CultureInfo]'es-CL'
$INV = [Globalization.CultureInfo]::InvariantCulture
$PLAN = 'C:\Users\dell\Casa Zaru Planillas'
$CZ   = Join-Path $env:USERPROFILE '.casazaru'
$MESES = @('Enero','Febrero','Marzo','Abril','Mayo','Junio','Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre')
$TRAMOS = @(@(0, 0.02), @(15000000, 0.025), @(25000000, 0.035))   # comisión César: tramo por val_prod, % sobre sin IVA
$IVA = 0.19
$RUT_PROPIO = '77157082'
$PAGO_FACTURA = 'Pago de factura ya contada'   # el gasto se cuenta con la factura; el pago no se suma otra vez
$UMBRAL_OTROS = 20000   # un gasto sin identificar bajo este monto (con IVA) va a "Otros gastos" sin preguntar

$iniMes = if ($Mes) { [datetime]::ParseExact("$Mes-01", 'yyyy-MM-dd', $INV) } else { (Get-Date -Day 1).Date.AddMonths(-1) }
$finMes = $iniMes.AddMonths(1).AddDays(-1)
$tag = $iniMes.ToString('yyyy-MM')
$mesNom = $MESES[$iniMes.Month - 1]
function EnMes($d) { $d -and $d -ge $iniMes -and $d -le $finMes }

function N($x) { if ($x -eq $null -or "$x".Trim() -eq '') { 0 } else { [double]("$x" -replace '[^\d\.-]', '') } }
function Fecha($s) {
  if ("$s" -match '^(\d{4})-(\d{1,2})-(\d{1,2})') { $y = $matches[1]; $m = $matches[2]; $d = $matches[3] }
  elseif ("$s" -match '^(\d{1,2})[/-](\d{1,2})[/-](\d{4})') { $d = $matches[1]; $m = $matches[2]; $y = $matches[3] }
  else { return $null }
  try { return (Get-Date -Year ([int]$y) -Month ([int]$m) -Day ([int]$d)).Date } catch { return $null }
}
function Suma($lista, $campo) { $s = (@($lista) | Measure-Object $campo -Sum).Sum; if ($s) { $s } else { 0 } }
function Neto($total) { [math]::Round($total / (1 + $IVA)) }
function Plata($v) { '$' + ([double]$v).ToString('N0', $cl) }
function LeerCsv($path) { if (Test-Path $path) { @(Import-Csv $path -Delimiter ';' -Encoding UTF8) } else { @() } }
function LeerJson($path) { if (Test-Path $path) { [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json } else { $null } }
$avisos = New-Object System.Collections.ArrayList
function Aviso($texto) { [void]$avisos.Add($texto) }

# ═════════════════════════════ DATOS ═════════════════════════════

# ── Gestión (respaldo diario) ──
$dirResp = 'G:\Mi unidad\Casa Zaru\Boletas y Facturas - Ventas 2026\Respaldos Gestion'
$resp = if ($Respaldo) { Get-Item $Respaldo } else { Get-ChildItem $dirResp -Filter 'respaldo-gestion-*.json' | Sort-Object LastWriteTime -Descending | Select-Object -First 1 }
if (-not $resp) { throw "No hay respaldos en $dirResp" }
$j = [IO.File]::ReadAllText($resp.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json
$prod = @{}; @($j.tablas.gestion_produccion) | ForEach-Object { $prod[$_.num] = $_.data }
$ventasTodas = @(@($j.tablas.gestion_finanzas) | ForEach-Object {
  $d = $_.data; $tipo = if ("$($d.tipo)") { "$($d.tipo)" } else { 'VENTA' }
  $a = (N $d.abono1) + (N $d.abono2) + (N $d.abono3); $tot = N $d.total
  [pscustomobject]@{
    num = $_.num; cliente = ("$($d.nombre) $($d.apellido)").Trim(); apellido = "$($d.apellido)"; tipo = $tipo
    fecha = Fecha $(if ($d.fecha_creacion) { $d.fecha_creacion } else { $d.fecha })
    total = $tot; vp = (N $d.val_prod); envio = (N $d.val_envio); abonado = $a; saldo = $tot - $a; semana = "$($d.semana)"
    vendedor = $(if ("$($d.vendedor)") { "$($d.vendedor)" } else { '(sin asignar)' })
    producto = "$($d.producto)"; web = ("$($d.canal_pago)" -match 'SHOPIFY')
    d1 = [bool]$d.doc1_emitida; d2 = [bool]$d.doc2_emitida; ab = @((N $d.abono1), (N $d.abono2), (N $d.abono3)); a1 = (N $d.abono1); a23 = (N $d.abono2) + (N $d.abono3); tipoDoc = $d.doc1_tipo
  }
} | Where-Object { $_.tipo -eq 'VENTA' })
$vMes = @($ventasTodas | Where-Object { EnMes $_.fecha } | Sort-Object fecha)
$vAnt = @($ventasTodas | Where-Object { $_.fecha -and $_.fecha -ge $iniMes.AddMonths(-1) -and $_.fecha -lt $iniMes })

# ── Pedidos que salieron en el mes (para la hoja Starken) ──
# Starken factura una vez al mes todos los despachos del período, así que el envío cobrado se cuenta en el mes en
# que SALE el pedido, no en el que se vendió. Por mes de venta, septiembre 2026 dio −$393 mil, pero varias ventas de
# fin de agosto se despacharon y pagaron en septiembre (#1537: $360.000 de envío cobrado en agosto, flete pagado el 21-09).
# Día de salida = dia_envio de Seguimiento (gestion_pedidos): es el que se mueve cuando cambia la fecha; Producción y
# Finanzas se quedan con la original (#1556: 28-09 en Producción, 07-10 en Seguimiento). Si no está, el de Producción;
# si tampoco, el lunes de la semana del pedido + 7 días (sale la semana siguiente).
# La estimación falla cuando se movió la fecha (check "cambio" de Seguimiento): por eso esos casos van a los avisos.
# Va acá y no en la hoja porque el Resumen, que muestra los avisos, se arma antes.
$MES_NUM = @{}; for ($i = 0; $i -lt 12; $i++) { $MES_NUM[$MESES[$i].ToUpper()] = $i + 1 }
$seg = @{}; @($j.tablas.gestion_pedidos) | ForEach-Object { $seg["$($_.num)"] = $_.data }
$cambioFecha = @{}; foreach ($k in $seg.Keys) { if ($seg[$k].checks.cambio) { $cambioFecha[$k] = $true } }
function Despacho($v) {
  $s = $seg["$($v.num)"]; $p = $prod[$v.num]
  foreach ($x in @($s, $p)) { if ($x -and $x.dia_envio) { $d = Fecha $x.dia_envio; if ($d) { return @{ fecha = $d; estimada = $false } } } }
  $sem = if ($s -and $s.semana) { "$($s.semana)" } elseif ($v.semana) { $v.semana } elseif ($p) { "$($p.envio)" } else { '' }
  if (-not $v.fecha -or $sem -notmatch 'SEMANA\s+(\d{1,2})\s+(\p{L}+)') { return $null }
  $m = $MES_NUM["$($matches[2])".ToUpper()]; if (-not $m) { return $null }
  try { $lunes = (Get-Date -Year $v.fecha.Year -Month $m -Day ([int]$matches[1])).Date } catch { return $null }
  if ($lunes -lt $v.fecha.AddDays(-60)) { $lunes = $lunes.AddYears(1) }   # vendido en diciembre, semana de enero
  @{ fecha = $lunes.AddDays(7); estimada = $true }
}
$desp = @($ventasTodas | ForEach-Object { $d = Despacho $_; if ($d -and (EnMes $d.fecha)) {
  [pscustomobject]@{ num = $_.num; cliente = $_.cliente; venta = $_.fecha; salida = $d.fecha; estimada = $d.estimada; envio = (Neto $_.envio) } } } | Sort-Object salida)
$sinDia = @()
foreach ($v in @($ventasTodas | Where-Object { $_.envio -gt 0 -and $_.fecha -and $_.fecha -ge $iniMes.AddMonths(-2) -and $_.fecha -le $finMes })) {
  $d = Despacho $v
  if (-not $d) { Aviso "Venta #$($v.num) ($($v.cliente)) cobró $(Plata $v.envio) de envío pero no tiene día de envío ni semana: no entra en la hoja Starken." }
  elseif ($d.estimada -and $cambioFecha["$($v.num)"] -and $d.fecha -ge $iniMes.AddMonths(-1) -and $d.fecha -le $finMes.AddMonths(1)) { $sinDia += "#$($v.num) $($v.cliente) ($(Plata $v.envio))" }
}
# Un solo aviso para todos: son el mismo problema y la misma acción.
if ($sinDia.Count) { Aviso "$($sinDia.Count) ventas con cambio de fecha y sin día de envío cargado: $($sinDia -join ', '). Su envío se estimó por la semana; cargar el día real en Seguimiento para que caiga en el mes correcto de la hoja Starken." }

# m² vendidos en el mes (líneas de producción de las ventas del mes)
$m2Mes = 0.0
foreach ($v in $vMes) { $p = $prod[$v.num]; if ($p) { foreach ($l in @($p.lineas)) { $m2Mes += (N $l.largo) / 100 * (N $l.ancho) / 100 * [math]::Max(1, (N $l.cantidad)) } } }

# Comisión César
$vCesar = @($vMes | Where-Object { $_.vendedor -match 'sar' })
$vpCesar = Suma $vCesar 'vp'
$tramo = $TRAMOS[0]; foreach ($t in $TRAMOS) { if ($vpCesar -ge $t[0]) { $tramo = $t } }
$sinIvaCesar = 0; foreach ($v in $vCesar) { $sinIvaCesar += Neto $v.vp }
$comCesar = [math]::Round($sinIvaCesar * $tramo[1])

# ── Documentos emitidos (Wasabil) ──
$emit = @(LeerCsv (Join-Path $CZ "emitidas-$tag.csv") | ForEach-Object {
  [pscustomobject]@{ fecha = Fecha $_.fecha; tipo = $_.tipo; folio = $_.folio; rut = $_.rut; cliente = $_.cliente; plataforma = $_.plataforma
    neto = (N $_.neto); iva = (N $_.iva); total = (N $_.total) } })
if (-not $emit.Count) { Aviso "Falta emitidas-$tag.csv (documentos emitidos según Wasabil): las hojas Facturas emitidas e IVA quedan incompletas." }

# ── Mercado Pago ──
$mp = @(LeerCsv (Join-Path $CZ "mp-$tag.csv"))
$mp = @($mp | ForEach-Object { [pscustomobject]@{ fecha = Fecha $_.fecha; mov = $_.mov; tipo = $_.tipo; id = "$($_.id)"; monto = (N $_.monto); comision = -(N $_.otros) } })
$mpSaldos = LeerJson (Join-Path $CZ "mp-$tag.json")
if (-not $mp.Count) { Aviso "Falta el movimiento de Mercado Pago de $mesNom (mp-$tag.csv): la caja y las ventas de feria quedan incompletas." }

# ── Liquidaciones de Mercado Pago (settlement_v2-<cuenta>-*.xlsx en Descargas) ──
# El usuario lo baja los lunes. Trae el canal de cada cobro (Point, Link de Pago, Checkout Pro, Mercado Libre) y las
# salidas. Se toma el archivo de la cuenta de Casa Zaru con más filas dentro del mes. Columnas por posición:
# 0 id, 1 medio, 2 tipo, 3 valor, 4 fecha origen, 5 comisiones, 7 neto, 9 canal, 10 plataforma.
. (Join-Path $PLAN 'lib-xls.ps1')
$MP_CUENTA = '1038334230'
# Viene en xlsx (columnas en español) o en csv (en inglés: SOURCE_ID;...;TRANSACTION_TYPE=SETTLEMENT/CREDIT;BUSINESS_UNIT;SUB_UNIT=Link/Checkout Pro/Point).
# Mismo orden de columnas en los dos.
function FilasLiq($path) {
  $crudas = if ($path -match '\.csv$') { @(Import-Csv $path -Delimiter ';' -Encoding UTF8 | ForEach-Object { ,@($_.PSObject.Properties | ForEach-Object { "$($_.Value)" }) }) } else { @(Read-XlsxRows $path | Select-Object -Skip 1) }
  @($crudas | Where-Object { $_.Count -gt 10 -and "$($_[4])" -match '^\d{4}-\d{2}-\d{2}' } | ForEach-Object {
    $f = Fecha "$($_[4])".Substring(0, 10); $plat = "$($_[10])"; if ($plat -eq 'Link') { $plat = 'Link de Pago' }; if (-not $plat -and "$($_[9])" -eq 'Mercado Libre') { $plat = 'Mercado Libre' }
    $tipo = "$($_[2])"; if ($tipo -eq 'SETTLEMENT') { $tipo = 'Pago aprobado' }
    # monto = lo cobrado o pagado; real = lo que de verdad entró o salió (con la comisión). En un pago con la tarjeta, la
    # web de Mercado Pago muestra el real (Claude: 97.985 + 1.959 de comisión = 99.944).
    [pscustomobject]@{ id = "$($_[0])"; medio = "$($_[1])"; tipo = $tipo; monto = (N $_[3]); real = (N $_[7]); fecha = $f; comision = -(N $_[5]); canal = "$($_[9])"; plataforma = $plat } } | Where-Object { EnMes $_.fecha })
}
# Se queda el archivo que llega más lejos en el mes; a igual fecha, el que tiene más filas.
$liq = @(); $liqArchivo = $null; $liqHasta = [datetime]::MinValue
foreach ($fx in @(Get-ChildItem "$env:USERPROFILE\Downloads" -Filter "settlement_v2-$MP_CUENTA-*" | Where-Object { $_.Extension -in '.xlsx', '.csv' -and $_.LastWriteTime -ge $iniMes } | Sort-Object LastWriteTime -Descending)) {
  $r = @(FilasLiq $fx.FullName); if (-not $r.Count) { continue }
  $hasta = ($r | ForEach-Object { $_.fecha } | Measure-Object -Maximum).Maximum
  if ($hasta -gt $liqHasta -or ($hasta -eq $liqHasta -and $r.Count -gt $liq.Count)) { $liq = $r; $liqArchivo = $fx; $liqHasta = $hasta }
}

# ── Ventas de feria (Point de Mercado Pago en las fechas de cada feria) ──
# Solo cobros con Point. En las mismas fechas también se liberan ventas de Mercado Libre y cobros con link,
# que ya se cuentan por otro lado. El canal sale de las liquidaciones (o de mp-AAAA-MM-canal.csv, el formato
# anterior). Sin ninguno de los dos se separa por la comisión: Point cobra ~2-3 %, Mercado Libre ~17 %, el link ~4 %.
$ferias = @(LeerCsv (Join-Path $PLAN 'ferias.csv') | ForEach-Object { [pscustomobject]@{ nombre = $_.Nombre; desde = Fecha $_.Desde; hasta = Fecha $_.Hasta; costos = "$($_.Costos)" } } | Where-Object { (EnMes $_.desde) -or (EnMes $_.hasta) })
$mpCanal = @{}; foreach ($x in $liq) { if ($x.plataforma) { $mpCanal[$x.id] = $x.plataforma } }
LeerCsv (Join-Path $CZ "mp-$tag-canal.csv") | ForEach-Object { if (-not $mpCanal.ContainsKey("$($_.id)")) { $mpCanal["$($_.id)"] = "$($_.plataforma)" } }
function EsPoint($m) { if ($mpCanal.Count) { $mpCanal["$($m.id)"] -eq 'Point' } else { $m.monto -gt 0 -and $m.comision / $m.monto -le 0.035 } }
$ventasFeria = @()
foreach ($f in $ferias) {
  $ventasFeria += @($mp | Where-Object { $_.tipo -eq 'Liberación de dinero' -and $_.fecha -ge $f.desde -and $_.fecha -le $f.hasta -and $_.monto -gt 1000 -and (EsPoint $_) } |
    ForEach-Object { [pscustomobject]@{ feria = $f.nombre; fecha = $_.fecha; bruto = $_.monto; comision = $_.comision } })
}
if ($ferias.Count -and -not $mpCanal.Count) { Aviso "Faltan las liquidaciones de Mercado Pago de $mesNom en Descargas (settlement_v2-$MP_CUENTA-*.xlsx): las ventas de feria se separaron de Mercado Libre por la comisión." }
$ventasML = @($emit | Where-Object { $_.plataforma -eq 'MercadoLibre' })

# ── Reglas de clasificación (privadas) ──
$reglas = @(LeerCsv (Join-Path $PLAN 'reglas-cierre.csv'))
function Clasificar($fuente, $texto, $monto) {
  foreach ($r in $reglas) {
    if ($r.Fuente -ne $fuente) { continue }
    if ($r.Monto -and [double]$r.Monto -ne [double]$monto) { continue }
    if ($texto -match $r.Patron) { return $r }
  }
  return $null
}

# ── Facturas recibidas (planilla de gastos Wasabil: Monto = total con IVA) ──
$planilla = @(LeerCsv (Join-Path $PLAN 'Gastos Wasabil 2026.csv'))
$fechaFactura = @{}; foreach ($x in $planilla) { $fechaFactura["$($x.Folio)"] = Fecha $x.Fecha }
$gastos = @($planilla | Where-Object { EnMes (Fecha $_.Fecha) } | ForEach-Object {
  $tot = N $_.Monto; $td = "$($_.'Tipo doc')"
  $neto = if ($td -match 'compra|exenta') { $tot } else { Neto $tot }
  $cat = "$($_.'Categoría')"; $sub = ''
  $r = Clasificar 'planilla' "$($_.RUT)" $tot; if ($r) { $cat = $r.Categoria; $sub = $r.Subcategoria }
  if ($cat -in '', 'POR CLASIFICAR' -and $tot -lt $UMBRAL_OTROS) { $cat = 'Otros gastos'; $sub = 'sin identificar' }
  [pscustomobject]@{ fuente = 'Factura'; fecha = Fecha $_.Fecha; proveedor = $_.Proveedor; rut = $_.RUT; doc = "$td $($_.Folio)"; folio = "$($_.Folio)"
    categoria = $cat; sub = $sub; neto = $neto; iva = $(if ($td -match 'compra|exenta') { 0 } else { $tot - $neto }); total = $tot; detalle = "$($_.'Detalle (glosa)')" }
})

# ── Cartolas: la que mejor cubre el mes, no la más nueva ──
# En Descargas conviven cartolas parciales y exports de "solo ingresos" (el 06-10 uno así dio un resultado
# falso de +$5M). Por cuenta se elige la que tiene más movimientos dentro del mes (empate: la más nueva).
. (Join-Path $PLAN 'lib-xls.ps1')
function FilasBci($path) {
  @(Read-XlsxRows $path | Select-Object -Skip 1 | Where-Object { $_.Count -gt 10 -and $_[0] -match '^\d' } | ForEach-Object {
    [pscustomobject]@{ fecha = [datetime]::FromOADate([double]::Parse($_[0], $INV)).Date; hora = $_[1]; ing = (N $_[8]); egr = (N $_[9]); saldo = (N $_[10]); rut = "$($_[12])"; nombre = "$($_[11])"; nota = "$($_[17])" } } |
    Where-Object { EnMes $_.fecha })
}
function FilasBdc($path) {
  $b = [IO.File]::ReadAllBytes($path)
  if ($b.Length -lt 8 -or (($b[0..7] | ForEach-Object { $_.ToString('x2') }) -join '') -ne 'd0cf11e0a1b11ae1') { return @() }
  if ([Text.Encoding]::GetEncoding(28591).GetString($b) -notmatch '77\.157\.082-8') { return @() }   # solo cartolas de Muvale
  try { $raw = @(Read-XlsRows $path) } catch { return @() }
  @($raw | Where-Object { $_.Count -gt 9 -and "$($_[1])" -match '^\d{2}/\d{2}/\d{4}$' } | ForEach-Object {
    [pscustomobject]@{ fecha = [datetime]::ParseExact($_[1], 'dd/MM/yyyy', $INV); glosa = "$($_[3])"; cargo = (N $_[7]); abono = (N $_[8]); saldo = (N $_[9]) } } | Where-Object { EnMes $_.fecha })
}
function MejorCartola($filtro, $leer) {
  $mejor = $null; $filas = @()
  foreach ($f in @(Get-ChildItem "$env:USERPROFILE\Downloads" -Filter $filtro | Where-Object { $_.LastWriteTime -ge $iniMes } | Sort-Object LastWriteTime -Descending)) {
    $r = @(& $leer $f.FullName)
    if ($r.Count -gt $filas.Count) { $mejor = $f; $filas = $r }
  }
  [pscustomobject]@{ archivo = $mejor; filas = $filas }
}
# BCI: se juntan TODAS las cartolas del mes sin repetir movimientos (fecha, hora, montos y saldo). Cada export cubre un
# rango distinto: el del 28-10 empezaba el 02-10 y, tomando solo una, se perdían los pagos del 01-10 ($3,7M el 28-10).
$bciArchivos = @(Get-ChildItem "$env:USERPROFILE\Downloads" -Filter '*Movimientos_Detallado_Cuenta_7175*.xlsx' | Where-Object { $_.LastWriteTime -ge $iniMes } | Sort-Object LastWriteTime -Descending)
$bciVistos = @{}; $bciFilas = @()
foreach ($a in $bciArchivos) { foreach ($x in @(FilasBci $a.FullName)) { $k = "$($x.fecha.ToString('yyyyMMdd'))|$($x.hora)|$($x.ing)|$($x.egr)|$($x.saldo)"; if (-not $bciVistos.ContainsKey($k)) { $bciVistos[$k] = 1; $bciFilas += $x } } }
$cBci = [pscustomobject]@{ archivo = $(if ($bciArchivos.Count) { $bciArchivos[0] } else { $null }); filas = $bciFilas; archivos = $bciArchivos }
$cBdc = MejorCartola 'cartola*.xls' ${function:FilasBdc}
# Lo leído en la web del banco después de la última fecha de la cartola se suma a la caja del taller (más nuevo primero).
$fExtra = Join-Path $CZ "movs-extra-$tag.csv"; if (-not (Test-Path $fExtra)) { $fExtra = $null }
if ($fExtra -and $cBdc.archivo) {
  $hasta = ($cBdc.filas | ForEach-Object { $_.fecha } | Measure-Object -Maximum).Maximum
  $extra = @(LeerCsv $fExtra | Where-Object { "$($_.Cuenta)" -match '75243' -and (Fecha $_.Fecha) -gt $hasta } | ForEach-Object {
    [pscustomobject]@{ fecha = Fecha $_.Fecha; glosa = "$($_.Glosa)"; cargo = (N $_.Cargo); abono = (N $_.Abono); saldo = (N $_.Saldo) } } | Where-Object { EnMes $_.fecha })
  if ($extra.Count) {
    $cBdc.filas = @($extra) + @($cBdc.filas)
    Aviso "Banco de Chile: $($extra.Count) movimientos del $($extra[-1].fecha.ToString('dd-MM')) al $($extra[0].fecha.ToString('dd-MM')) se leyeron en la web del banco (movs-extra-$tag.csv), no de una cartola."
  }
}
foreach ($c in @(@('BCI 7175', $cBci, 'egr'), @('Banco de Chile', $cBdc, 'cargo'))) {
  if (-not $c[1].archivo) { Aviso "Falta la cartola de $($c[0]) de $mesNom en Descargas: la caja y los pagos sin factura quedan incompletos."; continue }
  $fs = @($c[1].filas | ForEach-Object { $_.fecha }); $min = ($fs | Measure-Object -Minimum).Minimum; $max = ($fs | Measure-Object -Maximum).Maximum
  # En un mes en curso es normal que la cartola termine antes del 30: solo se avisa si le faltan días al principio o, en un mes cerrado, al final.
  $mesCerrado = ($finMes -lt (Get-Date).Date)
  if ($min -gt $iniMes.AddDays(6) -or ($mesCerrado -and $max -lt $finMes.AddDays(-6))) { Aviso "La cartola de $($c[0]) ($($c[1].archivo.Name)) cubre solo del $($min.ToString('dd-MM')) al $($max.ToString('dd-MM')): faltan días del mes." }
  if (-not (Suma $c[1].filas $c[2])) { Aviso "La cartola de $($c[0]) ($($c[1].archivo.Name)) no trae egresos: parece un export de solo ingresos." }
}

# ── Bancos: pagos del mes cruzados con las facturas (cargar-cartolas.ps1 en modo simulación) ──
# cargar-cartolas.ps1 toma la cartola más nueva de la carpeta que se le pasa: se le pasa una con las dos elegidas.
$dirCart = Join-Path $env:TEMP ('libro-cartolas-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $dirCart | Out-Null
foreach ($a in @(@($cBci.archivos) + @($cBdc.archivo)) | Where-Object { $_ }) { Copy-Item $a.FullName $dirCart }
# Tarjeta Visa 8340 de Banco de Chile (export "Movimientos[No]Facturados.xls") y movimientos leídos en la web del banco
# cuando la cartola no alcanza (movs-extra-AAAA-MM.csv, privado).
$tarjetas = @(Get-ChildItem "$env:USERPROFILE\Downloads" -Filter 'Movimientos*Facturados*.xls' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $iniMes })
foreach ($a in $tarjetas) { Copy-Item $a.FullName $dirCart }
if ($fExtra) { Copy-Item $fExtra (Join-Path $dirCart "movs-extra-$tag.csv") }
$tmpBanco = Join-Path $env:TEMP "banco-$tag.csv"
& (Join-Path $PLAN 'cargar-cartolas.ps1') -Desde $iniMes.ToString('yyyy-MM-dd') -Descargas $dirCart -Simular -ExportarCsv $tmpBanco *> $null
Remove-Item $dirCart -Recurse -Force -ErrorAction SilentlyContinue
$banco = @(LeerCsv $tmpBanco | Where-Object { EnMes (Fecha $_.Fecha) } | ForEach-Object {
  $txt = "$($_.Glosa) | $($_.Contraparte) | $($_.Nota)"; $monto = N $_.Monto
  $conFactura = "$($_.Factura)" -match '\[(\d+)\]'; $folio = if ($conFactura) { $matches[1] } else { '' }
  # "≈" = solo calzaron el monto y la fecha. No basta si (1) es una transferencia a una persona: en septiembre
  # quincenas, horas y rendiciones calzaron con fletes de Céspedes; o (2) la factura es posterior al pago: un
  # cargo de tarjeta del 28-09 calzó con una factura de bencina del 09-10. Se tratan como pagos sin factura.
  $aprox = $false
  if ($conFactura -and "$($_.Factura)" -match '≈') {
    $ff = $fechaFactura[$folio]
    if ("$($_.Glosa)" -match '^Transferencia enviada' -or ($ff -and $ff -gt (Fecha $_.Fecha).AddDays(3))) { $conFactura = $false; $folio = '' } else { $aprox = $true }
  }
  # origen = de dónde sale la justificación del pago (hoja Semanas): traspaso, factura, cargador, regla, menor o ninguno
  $cat = "$($_.Categoria)"; $sub = ''; $origen = if ($cat) { 'cargador' } else { 'ninguno' }
  if ("$($_.Factura)" -match 'traspaso') { $cat = 'Traspaso interno (no es gasto)'; $origen = 'traspaso' }
  elseif ($conFactura) { $g = $gastos | Where-Object { $_.folio -eq $folio } | Select-Object -First 1; $cat = if ($g) { $g.categoria } else { $PAGO_FACTURA }; $origen = 'factura' }
  elseif (-not $cat) { $r = Clasificar 'banco' $txt $monto; if ($r) { $cat = $r.Categoria; $sub = $r.Subcategoria; $origen = 'regla' } elseif ($monto -lt $UMBRAL_OTROS) { $cat = 'Otros gastos'; $sub = 'sin identificar'; $origen = 'menor' } else { $cat = 'POR CLASIFICAR' } }
  [pscustomobject]@{ fuente = 'Banco sin factura'; fecha = Fecha $_.Fecha; cuenta = ($_.Cuenta -replace '\s+75243-30$', ''); proveedor = $(if ($_.Contraparte) { $_.Contraparte } else { ($_.Glosa -replace '^Pago:\s*', '') })
    rut = $_.RUT; doc = ''; conFactura = $conFactura; categoria = $cat; sub = $sub; neto = $monto; iva = 0; total = $monto; detalle = "$($_.Nota)"; glosa = $_.Glosa; folio = $folio; aprox = $aprox; origen = $origen }
})
Remove-Item $tmpBanco -ErrorAction SilentlyContinue
# Una factura justifica un solo pago. Si dos cargos calzan con el mismo folio (dos cargas de bencina de $30.000 y una
# sola factura), se queda el calce exacto o el más antiguo; los demás vuelven a ser pagos sin factura (el 22-10 dos
# cargas de Copec se "pagaban" con la misma factura de NAHUEN y una quedaba fuera del gasto).
foreach ($g in @($banco | Where-Object { $_.conFactura -and $_.folio } | Group-Object folio | Where-Object { $_.Count -gt 1 })) {
  foreach ($d in @($g.Group | Sort-Object aprox, fecha | Select-Object -Skip 1)) {
    $d.conFactura = $false; $d.aprox = $false; $d.folio = ''
    $r = Clasificar 'banco' "$($d.glosa) | $($d.proveedor) | $($d.detalle)" $d.neto
    if ($r) { $d.categoria = $r.Categoria; $d.sub = $r.Subcategoria; $d.origen = 'regla' } elseif ($d.neto -lt $UMBRAL_OTROS) { $d.categoria = 'Otros gastos'; $d.sub = 'sin identificar'; $d.origen = 'menor' } else { $d.categoria = 'POR CLASIFICAR'; $d.sub = ''; $d.origen = 'ninguno' }
  }
}
$sinFactura = @($banco | Where-Object { -not $_.conFactura -and $_.categoria -ne 'Traspaso interno (no es gasto)' })

# ── Cuadre semanal: cada peso que salió de las cuentas, con su justificación (hoja Semanas y tablero) ──
# "Que todo gasto esté justificado" (17-10). Un pago está justificado si tiene factura, si lo explica una regla
# (reglas-cierre.csv o el cargador de cartolas), si es un traspaso entre cuentas propias o si es menor a $20.000.
# Lo demás sale como SIN JUSTIFICAR, y eso es lo único que hay que mirar el lunes.
$cuadre = New-Object System.Collections.ArrayList
function Salida($fecha, $cuenta, $aQuien, $monto, $cat, $just, $ok, $detalle = '') { [void]$cuadre.Add([pscustomobject]@{ fecha = $fecha; cuenta = $cuenta; aQuien = "$aQuien"; monto = [double]$monto; categoria = $cat; justificacion = $just; ok = [bool]$ok; detalle = "$detalle" }) }
$provFactura = @{}; foreach ($x in $planilla) { $provFactura["$($x.Folio)"] = "$($x.Proveedor)" }
foreach ($b in $banco) {
  $just = switch ($b.origen) {
    'traspaso' { 'Traspaso entre cuentas propias' }
    'factura'  { "Factura $($b.folio)$(if ($provFactura[$b.folio]) { " de $($provFactura[$b.folio])" })$(if ($b.aprox) { ' (calza monto y fecha)' })" }
    'regla'    { "Regla: $($b.categoria)$(if ($b.sub) { " · $($b.sub)" })" }
    'cargador' { "Regla del cargador: $($b.categoria)" }
    'menor'    { "Menor a $(Plata $UMBRAL_OTROS): va a Otros gastos" }
    default    { 'SIN JUSTIFICAR: ni factura ni regla' }
  }
  Salida $b.fecha $b.cuenta $b.proveedor $b.neto $b.categoria $just ($b.origen -ne 'ninguno') $b.detalle
}

# ── Saldos de las cuentas ──
$caja = @()
if ($cBci.archivo) {
  $rows = @($cBci.filas)
  if ($rows.Count) {
    $ult = $rows | Sort-Object fecha, hora | Select-Object -Last 1
    $ing = Suma $rows 'ing'; $egr = Suma $rows 'egr'
    $trI = Suma @($rows | Where-Object { $_.rut -match $RUT_PROPIO -and $_.ing -gt 0 }) 'ing'; $trE = Suma @($rows | Where-Object { $_.rut -match $RUT_PROPIO -and $_.egr -gt 0 }) 'egr'
    $caja += [pscustomobject]@{ cuenta = 'BCI 7175 (cuenta principal)'; inicial = $ult.saldo - $ing + $egr; ent = $ing; sal = $egr; final = $ult.saldo; trI = $trI; trE = $trE }
    $bciIngresos = @($rows | Where-Object { $_.ing -gt 0 -and $_.rut -notmatch $RUT_PROPIO })
  }
}
foreach ($x in @(1)) {
  $rows = @($cBdc.filas)
  if (-not $rows.Count) { continue }
  $ult = $rows[0]   # la cartola viene de la más nueva a la más vieja
  $ing = Suma $rows 'abono'; $egr = Suma $rows 'cargo'
  $trI = Suma @($rows | Where-Object { $_.glosa -match 'Muvale' }) 'abono'
  $caja += [pscustomobject]@{ cuenta = 'Banco de Chile (caja chica del taller)'; inicial = $ult.saldo - $ing + $egr; ent = $ing; sal = $egr; final = $ult.saldo; trI = $trI; trE = 0 }
  break
}
if ($mp.Count -and $mpSaldos) {
  $ing = Suma @($mp | Where-Object { $_.monto -gt 0 }) 'monto'; $egr = -(Suma @($mp | Where-Object { $_.monto -lt 0 }) 'monto') + (Suma $mp 'comision')
  $trI = Suma @($mp | Where-Object { $_.tipo -eq 'Transferencia recibida' }) 'monto'; $trE = -(Suma @($mp | Where-Object { $_.tipo -eq 'Transferencia enviada' }) 'monto')
  $caja += [pscustomobject]@{ cuenta = 'Mercado Pago'; inicial = $mpSaldos.saldo_inicial; ent = $ing; sal = $egr; final = $mpSaldos.saldo_final; trI = $trI; trE = $trE }
  $calc = $mpSaldos.saldo_inicial + $ing - $egr
  if ([math]::Abs($calc - $mpSaldos.saldo_final) -gt 1) { Aviso "Mercado Pago no cuadra: saldo calculado $(Plata $calc) vs informado $(Plata $mpSaldos.saldo_final)." }
}
# ── Salidas de Mercado Pago: la tarjeta prepago y las compras ──
# Con la tarjeta prepago de Mercado Pago se paga Facebook (Meta), Claude, Manychat, bencina, cursos y compras en Mercado
# Libre. Ni el estado de cuenta ni las liquidaciones traen el nombre del comercio: lo traen las capturas de la actividad
# en la web de Mercado Pago, que se transcriben a mp-nombres.csv (Fecha;Monto;Nombre). Con el nombre, cada pago se
# clasifica con las reglas; Facebook es el gasto real de Meta; sin nombre, queda en una bolsa "sin nombre".
$mpNombres = @(LeerCsv (Join-Path $CZ 'mp-nombres.csv') | ForEach-Object { [pscustomobject]@{ fecha = Fecha $_.Fecha; monto = (N $_.Monto); nombre = "$($_.Nombre)" } })
function NombreMP($fecha, $monto) { $x = $mpNombres | Where-Object { $_.fecha -eq $fecha -and [math]::Abs($_.monto - $monto) -le 1 } | Select-Object -First 1; if ($x) { $x.nombre } else { '' } }
$salidasMP = if ($mp.Count) { @($mp | Where-Object { $_.tipo -in 'Pago', 'Compra' } | ForEach-Object { [pscustomobject]@{ fecha = $_.fecha; monto = -$_.monto; plataforma = $(if ($_.tipo -eq 'Compra') { 'Mercado Libre' } else { '' }) } }) }
             else { @($liq | Where-Object { $_.tipo -eq 'Pago aprobado' -and $_.monto -lt 0 -and $_.medio -eq 'available_money' } | ForEach-Object { [pscustomobject]@{ fecha = $_.fecha; monto = $(if ($_.real) { -$_.real } else { -$_.monto }); plataforma = $_.plataforma } }) }
# Lo que las capturas de la actividad muestran DESPUÉS de la última liquidación o estado de cuenta también salió: entra
# con el nombre de la captura (el 26-10 la liquidación llegaba al 19-10 y Meta cobró dos veces el 26).
$hastaMP = ((@($mp) + @($liq)) | Where-Object { $_ -and $_.fecha } | ForEach-Object { $_.fecha } | Measure-Object -Maximum).Maximum
if ($hastaMP) {
  $tarde = @($mpNombres | Where-Object { $_.fecha -gt $hastaMP -and (EnMes $_.fecha) } | ForEach-Object { [pscustomobject]@{ fecha = $_.fecha; monto = $_.monto; plataforma = $(if ($_.nombre -match 'Mercado Libre') { 'Mercado Libre' } else { '' }) } })
  if ($tarde.Count) { $salidasMP = @($salidasMP) + $tarde; Aviso "Mercado Pago: $($tarde.Count) pagos posteriores al $($hastaMP.ToString('dd-MM')) salen solo de las capturas de la actividad (mp-nombres.csv); la próxima liquidación los confirma." }
}
$mpSinNombre = 0; $mpSinNombreN = 0; $mpGastos = @()
# Desde el 26-10 Meta también se cobra a la Visa 8340: esos cargos (regla FACEBK) son gasto real de Meta igual que los de Mercado Pago.
$mpMeta = Suma @($banco | Where-Object { $_.categoria -eq 'Publicidad Meta' -and $_.cuenta -match 'Visa' }) 'neto'
$visa = @($banco | Where-Object { $_.cuenta -match 'Visa' })
if ($visa.Count) { Aviso "Tarjeta Visa 8340: $(Plata (Suma $visa 'neto')) cargados en el mes. Es deuda con Banco de Chile: el gasto se cuenta al cargarse y el pago de la tarjeta, cuando llegue, es un traspaso." }
$MP_TARJETA = 'Mercado Pago (tarjeta)'
foreach ($s in $salidasMP) {
  $nom = NombreMP $s.fecha $s.monto
  if ($nom -match 'Facebook|Meta') { $mpMeta += $s.monto; Salida $s.fecha $MP_TARJETA $nom $s.monto 'Publicidad Meta' 'Facebook: es el gasto real de Meta' $true; continue }
  if ($nom -match 'Muvale') { Salida $s.fecha $MP_TARJETA $nom $s.monto 'Traspaso interno (no es gasto)' 'Traspaso entre cuentas propias' $true; continue }
  if ($nom -match 'Pr.stamo|cuota') { Salida $s.fecha $MP_TARJETA $nom $s.monto 'Créditos y deudas (cuotas)' 'Capital del crédito de Mercado Pago (creditos.csv): no es gasto' $true; continue }
  if (-not $nom) { if ($s.plataforma -eq 'Mercado Libre') { $nom = 'Mercado Libre (compra)' } else { $mpSinNombre += $s.monto; $mpSinNombreN++; Salida $s.fecha $MP_TARJETA '(sin nombre del comercio)' $s.monto 'POR CLASIFICAR' 'SIN JUSTIFICAR: falta el nombre del comercio (capturas de Mercado Pago → mp-nombres.csv)' $false; continue } }
  $r = Clasificar 'banco' $nom $s.monto
  $cat = if ($nom -match 'Mercado Libre') { $PAGO_FACTURA } elseif ($r) { $r.Categoria } elseif ($s.monto -lt $UMBRAL_OTROS) { 'Otros gastos' } else { 'POR CLASIFICAR' }
  $just = if ($cat -eq $PAGO_FACTURA) { 'Compra en Mercado Libre: la factura llega a Wasabil' } elseif ($r) { "Regla: $cat$(if ("$($r.Subcategoria)") { " · $($r.Subcategoria)" })" } elseif ($cat -eq 'Otros gastos') { "Menor a $(Plata $UMBRAL_OTROS): va a Otros gastos" } else { "SIN JUSTIFICAR: no hay regla para '$nom' en reglas-cierre.csv" }
  Salida $s.fecha $MP_TARJETA $nom $s.monto $cat $just ($cat -ne 'POR CLASIFICAR') 'pagado con la tarjeta de Mercado Pago'
  $mpGastos += [pscustomobject]@{ fuente = 'Banco sin factura'; fecha = $s.fecha; cuenta = $MP_TARJETA; proveedor = $nom; rut = ''; doc = ''; conFactura = ($cat -eq $PAGO_FACTURA); categoria = $cat; sub = $(if ($r) { "$($r.Subcategoria)" } else { '' }); neto = $s.monto; iva = 0; total = $s.monto; detalle = 'pagado con la tarjeta de Mercado Pago'; glosa = $nom }
}
foreach ($c in @($mp | Where-Object { $_.tipo -eq 'Pago de cuota' })) { Salida $c.fecha 'Mercado Pago' 'Mercado Pago (crédito)' (-$c.monto) 'Créditos y deudas (cuotas)' 'Cuota del crédito de Mercado Pago: capital, no es gasto' $true }
$sinFactura = @($sinFactura) + @($mpGastos | Where-Object { -not $_.conFactura })
$banco = @($banco) + @($mpGastos)
$mpCompras = Suma @($mpGastos | Where-Object { $_.conFactura }) 'neto'
$mpCuotas = -(Suma @($mp | Where-Object { $_.tipo -eq 'Pago de cuota' }) 'monto')
if ($mpSinNombreN) { Aviso "$mpSinNombreN pagos con la tarjeta de Mercado Pago por $(Plata $mpSinNombre) sin nombre del comercio: mandar las capturas de la actividad de Mercado Pago para clasificarlos (van a mp-nombres.csv)." }

# ── Créditos recibidos (creditos.csv, privado) ──
# Un crédito no es venta. Si al recibirlo se pagó el crédito anterior, ese pago sale como un "Pago" más en Mercado
# Pago: es capital, se saca de los pagos de publicidad y se suma a las cuotas.
$creditos = @(LeerCsv (Join-Path $PLAN 'creditos.csv') | Where-Object { EnMes (Fecha $_.Fecha) } | ForEach-Object {
  [pscustomobject]@{ fecha = Fecha $_.Fecha; acreedor = "$($_.Acreedor)"; recibido = (N $_.Recibido); pagoAnterior = (N $_.PagoCreditoAnterior); nota = "$($_.Nota)" } })
$credPagoMP = Suma @($creditos | Where-Object { $_.acreedor -match 'Mercado Pago' }) 'pagoAnterior'
$yaEnCuotas = @($mp | Where-Object { $_.tipo -eq 'Pago de cuota' -and [math]::Abs($_.monto + $credPagoMP) -le 1 }).Count   # el estado de cuenta ya lo trae como cuota
if ($credPagoMP -gt 0 -and -not $yaEnCuotas) { $quita = [math]::Min($credPagoMP, [math]::Max(0, $mpSinNombre)); $mpSinNombre -= $quita; $mpCuotas += $credPagoMP }
# En el cuadre semanal ese pago deja de estar "sin nombre": es el pago del crédito anterior.
foreach ($c in @($creditos | Where-Object { $_.pagoAnterior -gt 0 })) {
  $x = $cuadre | Where-Object { -not $_.ok -and $_.cuenta -eq $MP_TARJETA -and [math]::Abs($_.monto - $c.pagoAnterior) -le 1 -and [math]::Abs(($_.fecha - $c.fecha).TotalDays) -le 3 } | Select-Object -First 1
  if ($x) { $x.ok = $true; $x.aQuien = $c.acreedor; $x.categoria = 'Créditos y deudas (cuotas)'; $x.justificacion = 'Pago del crédito anterior al renovarlo (creditos.csv): capital, no es gasto' }
}

# ── Ajustes manuales (ajustes.csv, privado): decisiones del usuario que no están en ningún sistema ──
# Ej.: el resto de una devolución que no pasó por el banco. Fecha;Concepto;Monto;Categoria;Nota
$ajustes = @(LeerCsv (Join-Path $PLAN 'ajustes.csv') | Where-Object { EnMes (Fecha $_.Fecha) } | ForEach-Object {
  [pscustomobject]@{ fuente = 'Ajuste'; fecha = Fecha $_.Fecha; cuenta = ''; proveedor = "$($_.Concepto)"; rut = ''; doc = ''; conFactura = $false; categoria = "$($_.Categoria)"; sub = ''; neto = (N $_.Monto); iva = 0; total = (N $_.Monto); detalle = "$($_.Nota)"; glosa = '' } })

# ── Meta, SII, cotizador ──
# Gasto real de Meta: el reporte mensual (meta-AAAA-MM.json). Si no está, lo pagado a Facebook con la tarjeta de Mercado
# Pago (mp-nombres.csv). Si tampoco hay nombres, los pagos sin nombre de la tarjeta, como estimación gruesa.
$meta = LeerJson (Join-Path $CZ "meta-$tag.json")
$google = Suma @($gastos | Where-Object { $_.categoria -eq 'Publicidad Google' }) 'neto'
$metaEstimado = $false
if (-not $meta -and $mpMeta -gt 0) { $meta = [pscustomobject]@{ gasto = $mpMeta; fuente = 'pagos a Facebook con las tarjetas (Mercado Pago y Visa 8340)' } }
elseif (-not $meta -and $mpSinNombre -gt 0) { $meta = [pscustomobject]@{ gasto = $mpSinNombre; fuente = 'estimado: pagos sin nombre de la tarjeta de Mercado Pago' }; $metaEstimado = $true }
if ($meta -and $mpMeta -gt 0 -and -not $metaEstimado -and $meta.fuente -notmatch 'tarjeta' -and [math]::Abs($mpMeta / 1.19 - [double]$meta.gasto) -gt 0.1 * [double]$meta.gasto) { Aviso "Meta: el reporte dice $(Plata ([double]$meta.gasto)) sin IVA y las tarjetas (Mercado Pago y Visa 8340) pagaron a Facebook $(Plata $mpMeta) con IVA ($(Plata ($mpMeta / 1.19)) sin IVA). Revisar cuál es el gasto del mes." }
$sii = LeerJson (Join-Path $CZ "sii-$tag.json")
$kpi = LeerJson (Join-Path $CZ 'kpis-cotizador.json')

# ═════════════════════════════ RESULTADO ═════════════════════════════
$SECCION = @{
  'Madera (proveedores)' = 'costo'; 'Materiales e insumos' = 'costo'; 'Bases de fierro (mesas)' = 'costo'; 'Embalaje' = 'costo'; 'Maquinaria y herramientas' = 'costo'
  'Fletes y logística' = 'venta'; 'Devoluciones a clientes' = 'venta'; 'Comisiones marketplace' = 'venta'; 'Comisiones bancarias' = 'venta'; 'Publicidad Meta' = 'venta'; 'Publicidad Google' = 'venta'; 'Ferias' = 'venta'
  'Sueldos y remuneraciones' = 'fijo'; 'Imposiciones (Previred)' = 'fijo'; 'Arriendo' = 'fijo'; 'Servicios básicos' = 'fijo'; 'Combustible (bencina)' = 'fijo'
  'Transporte / viajes' = 'fijo'; 'Software y suscripciones' = 'fijo'; 'Gastos administrativos' = 'fijo'; 'Mantención y reparaciones' = 'fijo'
  'Colación y alimentación equipo' = 'fijo'; 'Post venta' = 'fijo'; 'Reforestación' = 'fijo'; 'POR CLASIFICAR' = 'fijo'; 'Otros gastos' = 'fijo'
}
$todo = @($gastos) + @($sinFactura) + @($ajustes)
foreach ($m in $todo) {
  $s = $SECCION[$m.categoria]
  if ($m.categoria -eq 'Créditos y deudas (cuotas)') { $s = if ($m.fuente -eq 'Factura') { 'fin' } else { $null } }   # factura = interés; cuota del banco = capital
  if ($m.categoria -eq 'Publicidad Meta' -and $meta) { $s = $null }                                                   # se usa el gasto real
  $m | Add-Member -NotePropertyName seccion -NotePropertyValue $s -Force
}
$metaReal = if ($meta) { [double]$meta.gasto } else { Suma @($todo | Where-Object { $_.categoria -eq 'Publicidad Meta' }) 'neto' }
$metaFact = Suma @($gastos | Where-Object { $_.categoria -eq 'Publicidad Meta' }) 'neto'
function PorCat($sec) {
  $g = @($todo | Where-Object { $_.seccion -eq $sec } | Group-Object categoria | ForEach-Object { [pscustomobject]@{ cat = $_.Name; monto = (Suma $_.Group 'neto') } })
  if ($sec -eq 'venta' -and $meta) { $g += [pscustomobject]@{ cat = 'Publicidad Meta'; monto = $metaReal } }
  @($g | Sort-Object monto -Descending)
}
$vNetaPedidos = Neto (Suma $vMes 'total'); $vNetaML = Suma $ventasML 'neto'; $vNetaFeria = Neto (Suma $ventasFeria 'bruto')
$ventaNeta = $vNetaPedidos + $vNetaML + $vNetaFeria
$lCosto = @(PorCat 'costo'); $lVenta = @(PorCat 'venta'); $lFijo = @(PorCat 'fijo'); $lFin = @(PorCat 'fin')
$tCosto = Suma $lCosto 'monto'; $tVenta = Suma $lVenta 'monto'; $tFijo = Suma $lFijo 'monto'; $tFin = Suma $lFin 'monto'
$margenBruto = $ventaNeta - $tCosto; $contrib = $margenBruto - $tVenta; $operac = $contrib - $tFijo; $resultado = $operac - $tFin
$ads = $metaReal + $google
$feriaCosto = Suma @($todo | Where-Object { $_.categoria -eq 'Ferias' }) 'neto'
# IVA del mes: lo mismo en la hoja IVA y en "Por pagar"
$debito = Suma $emit 'iva'; $credito = if ($sii) { $sii.compras.facturas.iva } else { Suma $gastos 'iva' }
$ivaFeria = (Suma $ventasFeria 'bruto') - $vNetaFeria
$ivaMes = $debito + $ivaFeria - $credito

# ═════════════════════════════ AVISOS ═════════════════════════════
# Boletas repetidas: mismo cliente, mismo monto, mismo día, sin nota de crédito que la anule
# Las notas de crédito pueden salir el mes siguiente (la de Buneder, del 25-09, salió el 06-10): se miran también ahí.
$tagSig = $iniMes.AddMonths(1).ToString('yyyy-MM')
$ncExtra = @(LeerCsv (Join-Path $CZ "emitidas-$tagSig.csv") | Where-Object { "$($_.tipo)" -match 'cr.dito' } | ForEach-Object { [pscustomobject]@{ rut = $_.rut; total = (N $_.total) } })
$nc = @($emit | Where-Object { $_.tipo -match 'cr.dito' }) + $ncExtra
foreach ($g in @($emit | Where-Object { $_.tipo -eq 'Boleta' -and $_.rut } | Group-Object rut, total, fecha | Where-Object { $_.Count -gt 1 })) {
  $b = $g.Group[0]; $anuladas = @($nc | Where-Object { $_.rut -eq $b.rut -and $_.total -eq -$b.total }).Count
  if ($g.Count - $anuladas -gt 1) { Aviso "Boletas repetidas a $($b.cliente): folios $((@($g.Group | ForEach-Object folio)) -join ' y ') por $(Plata $b.total) cada una, el $($b.fecha.ToString('dd-MM')). Revisar y anular la que sobra con nota de crédito." }
}
# Emisiones registradas en la app sin folio, que sí salieron en Wasabil
foreach ($r in @($j.tablas.gestion_documentos | Where-Object { -not $_.folio -and -not $_.anulada -and ((EnMes (Fecha $_.fecha)) -or (EnMes (Fecha "$($_.creado)"))) })) {
  $w = $emit | Where-Object { $_.total -eq (N $r.monto) -and $_.tipo.ToUpper() -eq "$($r.tipo)".ToUpper() } | Select-Object -First 1
  if ($w) { Aviso "Venta #$($r.num) ($($r.cliente)): la $("$($r.tipo)".ToLower()) salió en Wasabil (folio $($w.folio), $(Plata $w.total)) pero en Gestión quedó sin folio ni marcada como emitida." }
}
# Saldos por cobrar que parecen pagados en el banco
$cobrar = @($ventasTodas | Where-Object { $_.saldo -gt 1000 -and -not $_.web -and $_.fecha -and $_.fecha -le $finMes } | Sort-Object fecha)
foreach ($v in $cobrar) {
  $tok = @(("$($v.apellido) $($v.cliente)".ToUpper() -replace '[^A-ZÁÉÍÓÚÑ ]', ' ').Split(' ') | Where-Object { $_.Length -ge 4 } | Select-Object -Unique)
  # de más antiguo a más nuevo: los primeros pagos son los abonos que ya están registrados
  $p = @($bciIngresos | Where-Object { $n = $_.nombre.ToUpper(); [math]::Abs($_.ing - $v.saldo) -le 1000 -and @($tok | Where-Object { $n -match [regex]::Escape($_) }).Count -ge 1 } | Sort-Object fecha, hora)
  foreach ($x in @($v.ab | Where-Object { $_ -gt 0 })) { $i = -1; for ($k = 0; $k -lt $p.Count; $k++) { if ([math]::Abs($p[$k].ing - $x) -le 1000) { $i = $k; break } }; if ($i -ge 0) { $quitar = $p[$i]; $p = @($p | Where-Object { $_ -ne $quitar }) } }
  $p = @($p | Sort-Object fecha -Descending)
  if ($p.Count) { $v | Add-Member -NotePropertyName pagadoBanco -NotePropertyValue $p[0].fecha -Force
    Aviso "Venta #$($v.num) ($($v.cliente)): el saldo de $(Plata $v.saldo) parece pagado el $($p[0].fecha.ToString('dd-MM')) en BCI ($($p[0].nombre)), pero Gestión lo sigue mostrando como deuda." }
}
# Compras a proveedores sin factura (un solo aviso)
$sinFactProv = @($sinFactura | Where-Object { $_.seccion -eq 'costo' -and $_.sub -ne 'Rendición taller' } | Group-Object proveedor | Where-Object { (Suma $_.Group 'neto') -ge 100000 } | Sort-Object { -(Suma $_.Group 'neto') })
if ($sinFactProv.Count) {
  $det = @($sinFactProv | ForEach-Object { "$($_.Name) $(Plata (Suma $_.Group 'neto'))" })
  Aviso "Compras sin factura por $(Plata (Suma @($sinFactProv | ForEach-Object { $_.Group }) 'neto')): $($det -join ', '). No dan crédito de IVA; pedir factura cuando se pueda." }
$porClas = @($todo | Where-Object { $_.categoria -eq 'POR CLASIFICAR' })
if ($porClas.Count) { Aviso "$($porClas.Count) gastos por $(Plata (Suma $porClas 'neto')) siguen POR CLASIFICAR (hojas Semanas y Facturas recibidas). Clasificarlos en la planilla o en reglas-cierre.csv." }
if ($meta -and $metaReal - $metaFact -gt 1000) { Aviso "Meta: gasto real $(Plata $metaReal) pero solo $(Plata $metaFact) tienen factura de compra. Revisar con el contador las facturas que faltan (IVA no recuperado)." }
if ($ventasFeria.Count) { Aviso "Ventas de feria con Point: $(Plata (Suma $ventasFeria 'bruto')) sin boleta electrónica (el voucher vale como boleta). Su IVA ($(Plata ((Suma $ventasFeria 'bruto') - $vNetaFeria))) no está en el débito de Wasabil: confirmar que entre al F29." }
foreach ($v in $vMes) {
  # Un total MAYOR que producto + envío es un cobro extra (instalación, marco): no es error. Uno menor sí.
  if (-not $v.web -and $v.total -gt 0 -and ($v.vp + $v.envio - $v.total) -gt 1000) { Aviso "Venta #$($v.num) ($($v.cliente)): total $(Plata $v.total) es menor que valor producto $(Plata $v.vp) + envío $(Plata $v.envio). Cambia la comisión de César." }
  if ($v.vendedor -eq '(sin asignar)') { Aviso "Venta #$($v.num) ($($v.cliente)) sin vendedor." }
}

# ═════════════════════════════ INDICADORES, SEMÁFORO E HISTORIAL ═════════════════════════════
$metas = @{ VentaNetaMes = 0; MargenBrutoMin = 0.55; CACMaxPct = 0.10; PorCobrarMaxPct = 0.25; MesesCajaMin = 1 }
foreach ($m in LeerCsv (Join-Path $PLAN 'metas.csv')) { if ("$($m.Indicador)") { $metas["$($m.Indicador)"] = [double]::Parse("$($m.Valor)".Replace(',', '.'), $INV) } }
$cajaFin = Suma $caja 'final'
$porCobrar = Suma $cobrar 'saldo'
$cac = if ($vMes.Count) { $ads / $vMes.Count } else { 0 }
$ticket = if ($vMes.Count) { (Suma $vMes 'total') / $vMes.Count } else { 0 }
$tFijosTot = $tFijo + $tFin
$maderaTot = Suma @($todo | Where-Object { $_.categoria -eq 'Madera (proveedores)' }) 'neto'
$pctMB = if ($ventaNeta) { $margenBruto / $ventaNeta } else { 0 }
# Documentos pendientes de emitir según Gestión (pago marcado sin su boleta o factura)
$pend = @()
foreach ($r in ($ventasTodas | Where-Object { -not $_.web -and $_.fecha -and $_.fecha -le $finMes })) {
  if ($r.a1 -gt 0 -and -not $r.d1) { $pend += ,@("#$($r.num)", $r.cliente, 'Doc 1', $r.tipoDoc, $r.a1) }
  if ($r.a23 -gt 0 -and -not $r.d2) { $pend += ,@("#$($r.num)", $r.cliente, 'Doc 2', $r.tipoDoc, $r.a23) }
}
$pendTot = 0; foreach ($p in $pend) { $pendTot += $p[4] }
$porClasTot = Suma @($todo | Where-Object { $_.categoria -eq 'POR CLASIFICAR' }) 'neto'
$sinFactTot = Suma @($sinFactura | Where-Object { $_.seccion -eq 'costo' -and $_.sub -ne 'Rendición taller' }) 'neto'
$hoy = (Get-Date).Date
$esFinal = ($finMes -lt $hoy)
$datosAl = if ($esFinal) { $finMes } elseif ($cBci.filas.Count) { ($cBci.filas | ForEach-Object { $_.fecha } | Measure-Object -Maximum).Maximum } else { $hoy }
$estadoMes = if ($esFinal) { 'final' } else { "parcial (datos al $($datosAl.ToString('dd-MM')))" }
if ($esFinal -and (-not $mp.Count -or -not $meta)) { $estadoMes = 'parcial (faltan ' + ((@($(if (-not $mp.Count) { 'Mercado Pago' }), $(if (-not $meta) { 'gasto real de Meta' })) | Where-Object { $_ }) -join ' y ') + ')' }

# Semanas del cuadre: de lunes a domingo (para que no se pierda ningún pago), recortadas al mes.
# "completa" = su último día ya está cubierto por los datos (cartola y, si no hay estado de cuenta, liquidaciones de MP).
function Lunes($d) { $d.Date.AddDays(-(([int]$d.DayOfWeek + 6) % 7)) }
# Las capturas de la actividad de Mercado Pago (mp-nombres.csv) cubren hasta su fecha más nueva: alargan lo que dicen las liquidaciones.
$capHasta = ($mpNombres | Where-Object { EnMes $_.fecha } | ForEach-Object { $_.fecha } | Measure-Object -Maximum).Maximum
$mpHasta = if ($liq.Count) { $liqHasta } else { $null }; if ($capHasta -and (-not $mpHasta -or $capHasta -gt $mpHasta)) { $mpHasta = $capHasta }
$datosHasta = $datosAl; if (-not $mp.Count -and $mpHasta -and $mpHasta -lt $datosHasta) { $datosHasta = $mpHasta }
$semanas = @($cuadre | Where-Object { $_.fecha } | Group-Object { (Lunes $_.fecha).ToString('yyyy-MM-dd') } | Sort-Object Name | ForEach-Object {
  $lun = [datetime]::ParseExact($_.Name, 'yyyy-MM-dd', $INV); $d1 = if ($lun -lt $iniMes) { $iniMes } else { $lun }; $d2 = $lun.AddDays(6); if ($d2 -gt $finMes) { $d2 = $finMes }
  $sin = @($_.Group | Where-Object { -not $_.ok })
  [pscustomobject]@{ lunes = $lun; desde = $d1; hasta = $d2; nombre = "Semana del $($d1.ToString('dd-MM')) al $($d2.ToString('dd-MM'))"; movs = @($_.Group | Sort-Object fecha, cuenta, aQuien)
    n = $_.Count; salio = (Suma $_.Group 'monto'); sinJust = (Suma $sin 'monto'); nSin = $sin.Count; completa = ($d2 -le $datosHasta) } })
$sinJustTot = Suma @($cuadre | Where-Object { -not $_.ok }) 'monto'; $nSinJust = @($cuadre | Where-Object { -not $_.ok }).Count

# Semáforo: cada línea dice qué pasa y qué hacer. Los umbrales viven en metas.csv.
$semaforo = New-Object System.Collections.ArrayList
function Luz($nombre, $estado, $valor, $accion) { [void]$semaforo.Add([pscustomobject]@{ nombre = $nombre; estado = $estado; icono = @{ bien = '✓'; ojo = '!'; mal = '✗' }[$estado]; valor = $valor; accion = $accion }) }
if ($metas.VentaNetaMes -gt 0) {
  $pctMeta = $ventaNeta / $metas.VentaNetaMes
  Luz 'Venta frente a la meta' $(if ($pctMeta -ge 1) { 'bien' } elseif ($pctMeta -ge 0.8) { 'ojo' } else { 'mal' }) "$(Plata $ventaNeta) de $(Plata $metas.VentaNetaMes) ($([math]::Round($pctMeta * 100)) %)" $(if ($pctMeta -ge 1) { 'Meta cumplida.' } else { "Faltan $(Plata ($metas.VentaNetaMes - $ventaNeta)) para la meta$(if (-not $esFinal) { ' (mes en curso)' })." })
}
Luz 'Margen bruto' $(if ($pctMB -ge $metas.MargenBrutoMin) { 'bien' } elseif ($pctMB -ge $metas.MargenBrutoMin - 0.1) { 'ojo' } else { 'mal' }) "$([math]::Round($pctMB * 100)) % de la venta (mínimo $([math]::Round($metas.MargenBrutoMin * 100)) %)" $(if ($pctMB -ge $metas.MargenBrutoMin) { 'Los materiales están bajo control.' } else { 'Revisar precio de la madera por m² y los descuentos.' })
Luz 'Gastos fijos cubiertos' $(if ($contrib -ge $tFijosTot) { 'bien' } elseif ($contrib -ge $tFijosTot * 0.7) { 'ojo' } else { 'mal' }) "cada venta deja $(Plata $contrib) y los fijos son $(Plata $tFijosTot)" $(if ($contrib -ge $tFijosTot) { 'El mes se paga solo.' } else { "Faltaron $(Plata ($tFijosTot - $contrib)) de margen: vender más o bajar fijos." })
$pctAds = if ($ventaNeta) { $ads / $ventaNeta } else { 0 }
Luz 'Publicidad' $(if ($pctAds -le $metas.CACMaxPct) { 'bien' } elseif ($pctAds -le $metas.CACMaxPct * 1.5) { 'ojo' } else { 'mal' }) "$([math]::Round($pctAds * 100)) % de la venta, $(Plata $cac) por pedido" $(if ($pctAds -le $metas.CACMaxPct) { 'Dentro del máximo.' } else { 'Supera el máximo: revisar campañas que no convierten.' })
$pctCobrar = if ($ventaNeta) { $porCobrar / $ventaNeta } else { 0 }
Luz 'Plata por cobrar' $(if ($pctCobrar -le $metas.PorCobrarMaxPct) { 'bien' } elseif ($pctCobrar -le $metas.PorCobrarMaxPct * 1.5) { 'ojo' } else { 'mal' }) "$(Plata $porCobrar) en $($cobrar.Count) pedidos" $(if ($cobrar.Count) { 'Cobrar antes de despachar; los más viejos primero.' } else { 'Nada pendiente.' })
$mesesCaja = if ($tFijosTot) { $cajaFin / $tFijosTot } else { 0 }
Luz 'Caja' $(if ($mesesCaja -ge $metas.MesesCajaMin) { 'bien' } elseif ($mesesCaja -ge $metas.MesesCajaMin / 2) { 'ojo' } else { 'mal' }) "$(Plata $cajaFin), alcanza para $($mesesCaja.ToString('N1', $cl)) meses de gastos fijos" $(if ($mesesCaja -ge $metas.MesesCajaMin) { 'Colchón suficiente.' } else { 'Colchón corto: cuidar los pagos grandes y cobrar lo pendiente.' })
$ordenCount = $pend.Count + @($todo | Where-Object { $_.categoria -eq 'POR CLASIFICAR' }).Count
Luz 'Orden administrativo' $(if ($ordenCount -eq 0 -and $sinFactTot -lt 300000) { 'bien' } elseif ($ordenCount -le 5) { 'ojo' } else { 'mal' }) "$($pend.Count) documentos sin emitir ($(Plata $pendTot)), $(Plata $porClasTot) sin clasificar, $(Plata $sinFactTot) comprado sin factura" $(if ($ordenCount -eq 0) { 'Todo al día.' } else { 'Emitir lo pendiente y pedir factura a los proveedores.' })

# Historial: una fila por mes, se reescribe la del mes que se está generando.
$histPath = Join-Path $PLAN 'historial-mensual.csv'
$esReal = ($Salida -eq 'G:\Mi unidad\Casa Zaru\Informes Gestion')
function FilaHist($r) { [pscustomobject]@{ Mes = "$($r.Mes)"; Estado = "$($r.Estado)"; VentaNeta = (N $r.VentaNeta); Pedidos = (N $r.Pedidos); Ticket = (N $r.Ticket); MargenBruto = (N $r.MargenBruto); Contribucion = (N $r.Contribucion); GastosFijos = (N $r.GastosFijos); Resultado = (N $r.Resultado); Caja = (N $r.Caja); PorCobrar = (N $r.PorCobrar); CAC = (N $r.CAC); Publicidad = (N $r.Publicidad); Madera = (N $r.Madera); Generado = "$($r.Generado)" } }
$hist = @(LeerCsv $histPath | Where-Object { "$($_.Mes)" -ne $tag } | ForEach-Object { FilaHist $_ })
$filaMes = [pscustomobject]@{ Mes = $tag; Estado = $estadoMes; VentaNeta = [math]::Round($ventaNeta); Pedidos = $vMes.Count; Ticket = [math]::Round($ticket); MargenBruto = [math]::Round($margenBruto); Contribucion = [math]::Round($contrib); GastosFijos = [math]::Round($tFijosTot); Resultado = [math]::Round($resultado); Caja = [math]::Round($cajaFin); PorCobrar = [math]::Round($porCobrar); CAC = [math]::Round($cac); Publicidad = [math]::Round($ads); Madera = [math]::Round($maderaTot); Generado = (Get-Date).ToString('yyyy-MM-dd HH:mm') }
$histTodo = @(@($hist) + @($filaMes) | Sort-Object Mes)
if ($esReal) { $histTodo | Export-Csv $histPath -Delimiter ';' -NoTypeInformation -Encoding UTF8 }
$tagAnt = $iniMes.AddMonths(-1).ToString('yyyy-MM')
$ant = $histTodo | Where-Object { $_.Mes -eq $tagAnt } | Select-Object -First 1

# ═════════════════════════════ EXCEL ═════════════════════════════
function X($s) { [Security.SecurityElement]::Escape("$s") }
function ColL($i) { $s = ''; $i++; while ($i -gt 0) { $m = ($i - 1) % 26; $s = "$([char](65 + $m))$s"; $i = [math]::Floor(($i - 1) / 26) }; $s }
# Estilos: 0 normal · 1 encabezado · 2 pesos · 3 pesos total · 4 % · 5 título · 6 nota · 7 entero · 8 decimal
#          9 texto total · 10 aviso · 11 negrita · 12 % total · 13 pesos negrita · 14 texto ajustado · 15 subtítulo
function C($v, $s = $null) { @{ v = $v; s = $s } }
function F($f, $s = 2) { @{ f = $f; s = $s } }
$hojas = New-Object System.Collections.ArrayList
function Hoja($nombre, $filas, $anchos, $congelar = 0) { [void]$hojas.Add(@{ nombre = $nombre; filas = $filas; anchos = $anchos; congelar = $congelar }) }
function CeldaXml($ref, $c) {
  if ($c -eq $null) { return '' }
  if ($c -isnot [hashtable]) { $c = @{ v = $c } }
  $s = $c.s; $v = $c.v
  if ($c.f) { return "<c r=""$ref"" s=""$(if ($s -ne $null) { $s } else { 2 })""><f>$(X $c.f)</f></c>" }
  if ($v -eq $null -or "$v" -eq '') { if ($s) { return "<c r=""$ref"" s=""$s""/>" } else { return '' } }
  if ($v -is [int] -or $v -is [long] -or $v -is [double] -or $v -is [decimal]) {
    if ($s -eq $null) { $s = if ($v -is [int] -or $v -is [long]) { 7 } else { 2 } }
    return "<c r=""$ref"" s=""$s""><v>$(([double]$v).ToString('R', $INV))</v></c>"
  }
  if ($v -is [datetime]) { $v = $v.ToString('dd-MM-yyyy') }
  if ($s -eq $null) { $s = 0 }
  "<c r=""$ref"" s=""$s"" t=""inlineStr""><is><t xml:space=""preserve"">$(X $v)</t></is></c>"
}
function HojaXml($h) {
  $sb = New-Object Text.StringBuilder
  [void]$sb.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">')
  [void]$sb.Append('<sheetViews><sheetView workbookViewId="0" showGridLines="0">')
  if ($h.congelar) { [void]$sb.Append("<pane ySplit=""$($h.congelar)"" topLeftCell=""A$($h.congelar + 1)"" activePane=""bottomLeft"" state=""frozen""/>") }
  [void]$sb.Append('</sheetView></sheetViews><cols>')
  for ($i = 0; $i -lt $h.anchos.Count; $i++) { [void]$sb.Append("<col min=""$($i+1)"" max=""$($i+1)"" width=""$($h.anchos[$i])"" customWidth=""1""/>") }
  [void]$sb.Append('</cols><sheetData>')
  $r = 0
  foreach ($fila in $h.filas) {
    $r++; [void]$sb.Append("<row r=""$r"">")
    $cI = 0; foreach ($c in @($fila)) { [void]$sb.Append((CeldaXml "$(ColL $cI)$r" $c)); $cI++ }
    [void]$sb.Append('</row>')
  }
  [void]$sb.Append('</sheetData><pageMargins left="0.5" right="0.5" top="0.6" bottom="0.6" header="0.3" footer="0.3"/><pageSetup orientation="landscape" fitToWidth="1" fitToHeight="0"/></worksheet>')
  $sb.ToString()
}
function GuardarXlsx($ruta) {
  $tmp = Join-Path $env:TEMP ("libro-" + [guid]::NewGuid()); New-Item -ItemType Directory $tmp | Out-Null
  New-Item -ItemType Directory "$tmp\_rels", "$tmp\xl", "$tmp\xl\_rels", "$tmp\xl\worksheets" | Out-Null
  $u = New-Object Text.UTF8Encoding($false)
  $ct = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
  $wbS = ''; $wbR = ''
  for ($i = 0; $i -lt $hojas.Count; $i++) {
    $n = $i + 1
    [IO.File]::WriteAllText("$tmp\xl\worksheets\sheet$n.xml", (HojaXml $hojas[$i]), $u)
    $ct += "<Override PartName=""/xl/worksheets/sheet$n.xml"" ContentType=""application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml""/>"
    $wbS += "<sheet name=""$(X $hojas[$i].nombre)"" sheetId=""$n"" r:id=""rId$n""/>"
    $wbR += "<Relationship Id=""rId$n"" Type=""http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"" Target=""worksheets/sheet$n.xml""/>"
  }
  $ct += '</Types>'
  [IO.File]::WriteAllText("$tmp\[Content_Types].xml", $ct, $u)
  [IO.File]::WriteAllText("$tmp\_rels\.rels", '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>', $u)
  [IO.File]::WriteAllText("$tmp\xl\workbook.xml", "<?xml version=""1.0"" encoding=""UTF-8"" standalone=""yes""?><workbook xmlns=""http://schemas.openxmlformats.org/spreadsheetml/2006/main"" xmlns:r=""http://schemas.openxmlformats.org/officeDocument/2006/relationships""><sheets>$wbS</sheets><calcPr calcId=""191029"" fullCalcOnLoad=""1""/></workbook>", $u)
  $n = $hojas.Count + 1
  [IO.File]::WriteAllText("$tmp\xl\_rels\workbook.xml.rels", "<?xml version=""1.0"" encoding=""UTF-8"" standalone=""yes""?><Relationships xmlns=""http://schemas.openxmlformats.org/package/2006/relationships"">$wbR<Relationship Id=""rId$n"" Type=""http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles"" Target=""styles.xml""/></Relationships>", $u)
  $st = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<numFmts count="3"><numFmt numFmtId="164" formatCode="&quot;$&quot;#,##0;[Red]-&quot;$&quot;#,##0"/><numFmt numFmtId="165" formatCode="0.0%"/><numFmt numFmtId="166" formatCode="#,##0.00"/></numFmts>
<fonts count="7"><font><sz val="10"/><name val="Arial"/></font><font><b/><sz val="10"/><name val="Arial"/></font><font><b/><sz val="15"/><color rgb="FF5C3D20"/><name val="Arial"/></font><font><i/><sz val="9"/><color rgb="FF8A7960"/><name val="Arial"/></font><font><b/><sz val="10"/><color rgb="FFFFFFFF"/><name val="Arial"/></font><font><sz val="10"/><color rgb="FF8A3B12"/><name val="Arial"/></font><font><b/><sz val="11"/><color rgb="FF7B5B3A"/><name val="Arial"/></font></fonts>
<fills count="6"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFF2ECE4"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFF7F2EC"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FF5C3D20"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFFDF6E8"/></patternFill></fill></fills>
<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left/><right/><top style="thin"><color rgb="FFB8A890"/></top><bottom/><diagonal/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="16">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>
<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="164" fontId="1" fillId="3" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1"/>
<xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>
<xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment wrapText="1" vertical="top"/></xf>
<xf numFmtId="3" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="166" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="0" fontId="1" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/>
<xf numFmtId="0" fontId="5" fillId="5" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment wrapText="1" vertical="top"/></xf>
<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
<xf numFmtId="165" fontId="1" fillId="3" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1"/>
<xf numFmtId="164" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/>
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment wrapText="1" vertical="top"/></xf>
<xf numFmtId="0" fontId="6" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>
'@
  [IO.File]::WriteAllText("$tmp\xl\styles.xml", $st, $u)
  if (Test-Path $ruta) { Remove-Item $ruta }
  # A mano y no con CreateFromDirectory: en .NET Framework esa deja rutas con "\" y Excel no abre el archivo.
  Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
  $zip = [IO.Compression.ZipFile]::Open($ruta, 'Create')
  try {
    foreach ($a in Get-ChildItem -LiteralPath $tmp -Recurse -File) {
      $nombre = $a.FullName.Substring($tmp.Length + 1).Replace('\', '/')
      [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $a.FullName, $nombre)
    }
  } finally { $zip.Dispose() }
  Remove-Item -LiteralPath $tmp -Recurse
}
# Tabla con encabezado y fila de total (fórmulas SUM) a partir de la fila $r0 (1-based) de la hoja
function Tabla([System.Collections.ArrayList]$filas, $cols, $datos, $sumar = @()) {
  [void]$filas.Add(@($cols | ForEach-Object { C $_ 1 }))
  $ini = $filas.Count + 1
  foreach ($d in $datos) { [void]$filas.Add(@($d)) }
  $fin = $filas.Count
  if ($sumar.Count) {
    $tot = for ($i = 0; $i -lt $cols.Count; $i++) {
      if ($i -eq 0) { C 'Total' 9 } elseif ($sumar -contains $i) { if ($fin -ge $ini) { F "SUM($(ColL $i)$($ini):$(ColL $i)$fin)" 3 } else { C 0 3 } } else { C '' 9 }
    }
    [void]$filas.Add(@($tot))
  }
  [void]$filas.Add(@())
}
function Titulo([System.Collections.ArrayList]$filas, $t, $sub) { [void]$filas.Add(@(C $t 5)); if ($sub) { [void]$filas.Add(@(C $sub 6)) }; [void]$filas.Add(@()) }
function Sub([System.Collections.ArrayList]$filas, $t) { [void]$filas.Add(@(C $t 15)) }
function Nota([System.Collections.ArrayList]$filas, $t) { [void]$filas.Add(@(C $t 6)) }

$gen = (Get-Date).ToString('dd-MM-yyyy HH:mm')

# ── 1. Resumen ──
$f = New-Object System.Collections.ArrayList
Titulo $f "Casa Zaru — Cierre de $mesNom $($iniMes.Year) ($estadoMes)" "Montos sin IVA. Generado $gen. Fuentes: Gestión, planilla de gastos Wasabil, cartolas BCI y Banco de Chile, Mercado Pago, Wasabil y Meta. Este archivo se genera solo: lo que haya que corregir se corrige en Gestión, en la planilla de gastos o en las reglas, no acá."
Sub $f 'Los números del mes'
[void]$f.Add(@((C 'Indicador' 1), (C 'Este mes' 1), (C 'Mes anterior' 1), (C 'De dónde sale' 1)))
function Ant($campo) { if ($ant) { $ant.$campo } else { '' } }
$kp = @(
  @('Venta neta', $ventaNeta, (Ant 'VentaNeta'), "$($vMes.Count) pedidos + $($ventasML.Count) Mercado Libre + $($ventasFeria.Count) ventas de feria"),
  @('Margen bruto', $margenBruto, (Ant 'MargenBruto'), "venta − materiales ($([math]::Round($pctMB * 100)) % de la venta)"),
  @('Resultado del mes', $resultado, (Ant 'Resultado'), 'después de todos los gastos del mes'),
  @('Caja al cierre', $cajaFin, (Ant 'Caja'), 'BCI + Banco de Chile + Mercado Pago'),
  @('Por cobrar', $porCobrar, (Ant 'PorCobrar'), "$($cobrar.Count) pedidos con saldo"),
  @('Publicidad por pedido (CAC)', [math]::Round($cac), (Ant 'CAC'), 'Meta + Google ÷ pedidos del mes'),
  @('Madera por m² vendido', $(if ($m2Mes -gt 0) { [math]::Round($maderaTot / $m2Mes) } else { 0 }), '', "$($m2Mes.ToString('N1', $cl)) m² vendidos")
)
foreach ($k in $kp) { [void]$f.Add(@((C $k[0] 11), (C $k[1] 13), (C $k[2] 2), (C $k[3] 6))) }
[void]$f.Add(@())
Sub $f 'Semáforo: dónde estamos bien y dónde fallamos'
foreach ($s in $semaforo) { [void]$f.Add(@((C "$($s.icono)  $($s.nombre)" 11), (C $s.estado.ToUpper() 6), (C $s.valor 6), (C $s.accion 6))) }
Nota $f 'Los umbrales (meta de venta, margen mínimo, publicidad máxima, por cobrar, meses de caja) están en metas.csv.'
[void]$f.Add(@())
Sub $f 'Qué falta para cerrar el mes'
$falta = @()
if ($pend.Count) { $falta += "Emitir $($pend.Count) documentos por $(Plata $pendTot) (hoja Facturas emitidas, al final)." }
if ($cobrar.Count) { $falta += "Cobrar $(Plata $porCobrar) de $($cobrar.Count) pedidos (hoja Por cobrar y pagar)." }
$porClasFact = Suma @($gastos | Where-Object { $_.categoria -eq 'POR CLASIFICAR' }) 'neto'
if ($porClasFact) { $falta += "Clasificar $(Plata $porClasFact) de facturas sin categoría (hoja Facturas recibidas)." }
if ($nSinJust) { $falta += "Justificar $nSinJust pagos por $(Plata $sinJustTot) (hoja Semanas: los que dicen SIN JUSTIFICAR)." }
if (-not $esFinal) { $falta += "El mes sigue abierto: faltan los movimientos desde el $($datosAl.AddDays(1).ToString('dd-MM'))." }
if (-not $falta.Count) { $falta += 'Nada: el mes está cerrado.' }
foreach ($x in $falta) { [void]$f.Add(@(C "• $x")) }
[void]$f.Add(@())
Sub $f 'Estado de resultados'
[void]$f.Add(@((C 'Concepto' 1), (C 'Monto' 1), (C '% venta' 1), (C 'De dónde sale' 1)))
$rVenta = $f.Count + 1
$lineas = New-Object System.Collections.ArrayList
function L($t, $m, $nota = '') { [void]$f.Add(@((C "   $t"), (C $m 2), (F "IFERROR(B$($f.Count + 1)/`$B`$$script:rVentaTot,0)" 4), (C $nota 6))) }
function Rango($a) { if ($f.Count -ge $a) { "+SUM(B$($a):B$($f.Count))" } else { '' } }
function Total($t, $formula, $nota = '') { [void]$f.Add(@((C $t 9), (F $formula 3), (F "IFERROR(B$($f.Count + 1)/`$B`$$script:rVentaTot,0)" 12), (C $nota 9))); $f.Count }
$script:rVentaTot = $rVenta + 3
L 'Pedidos (Gestión)' $vNetaPedidos "$($vMes.Count) ventas por fecha de venta"
L 'Mercado Libre' $vNetaML "$($ventasML.Count) boletas (Wasabil)"
L 'Ferias (Point Mercado Pago)' $vNetaFeria "$($ventasFeria.Count) ventas"
$rV = Total 'Venta neta' "SUM(B$($rVenta):B$($rVenta + 2))"
$a = $f.Count + 1; foreach ($l in $lCosto) { L $l.cat (-$l.monto) }
$rMB = Total 'Margen bruto' "B$rV$(Rango $a)" 'venta − materiales'
$a = $f.Count + 1; foreach ($l in $lVenta) { L $l.cat (-$l.monto) $(if ($l.cat -eq 'Publicidad Meta' -and $meta) { if ($metaEstimado) { 'estimado: lo pagado por Mercado Pago menos Google' } else { 'gasto real (no solo lo facturado)' } }) }
$rMC = Total 'Margen de contribución' "B$rMB$(Rango $a)" 'lo que deja cada venta para pagar los gastos fijos'
$a = $f.Count + 1; foreach ($l in $lFijo) { L $l.cat (-$l.monto) $(if ($l.cat -eq 'Sueldos y remuneraciones') { 'pagados en el mes (los sueldos se pagan a mes vencido)' }) }
$rRO = Total 'Resultado operacional' "B$rMC$(Rango $a)"
$a = $f.Count + 1; foreach ($l in $lFin) { L $(if ($l.cat -eq 'Créditos y deudas (cuotas)') { 'Intereses de créditos' } else { $l.cat }) (-$l.monto) }
if (-not $lFin.Count) { L 'Intereses de créditos' 0 }
[void](Total 'Resultado del mes' "B$rRO$(Rango $a)")
[void]$f.Add(@())
# Solo plata que de verdad salió de las cuentas. Una factura de activo (la camioneta) no es un pago: va en una nota.
Sub $f 'Plata que salió y no es gasto del mes'
$salio = @($todo | Where-Object { -not $_.seccion -and $_.fuente -ne 'Factura' -and $_.categoria -ne 'Publicidad Meta' })   # Meta ya está en el resultado como gasto real + @($banco | Where-Object { $_.conFactura -and $_.categoria -eq $PAGO_FACTURA })
$fuera = @($salio | Group-Object categoria | ForEach-Object { [pscustomobject]@{ cat = $_.Name; monto = (Suma $_.Group 'neto') } })
if ($mpCuotas) {
  $c = $fuera | Where-Object { $_.cat -eq 'Créditos y deudas (cuotas)' } | Select-Object -First 1
  if ($c) { $c.monto += $mpCuotas } else { $fuera += [pscustomobject]@{ cat = 'Créditos y deudas (cuotas)'; monto = $mpCuotas } }
}
$NOMBRE_FUERA = @{ 'Créditos y deudas (cuotas)' = 'Cuotas de créditos (capital)'; 'Préstamos de socios (no es gasto)' = 'Devolución de préstamos a socios'; 'Impuestos (SII)' = 'Impuestos (IVA y PPM del mes anterior)' }
foreach ($x in @($fuera | Sort-Object monto -Descending)) { [void]$f.Add(@((C "   $(if ($NOMBRE_FUERA[$x.cat]) { $NOMBRE_FUERA[$x.cat] } else { $x.cat })"), (C $x.monto 2))) }
$activo = Suma @($gastos | Where-Object { $_.categoria -eq 'Inversión (activo fijo)' }) 'neto'
if ($ajustes.Count) { Nota $f "Ajustes manuales del mes (ajustes.csv): $((@($ajustes | ForEach-Object { "$($_.proveedor) $(Plata $_.neto) → $($_.categoria)" })) -join '; ')." }
if ($creditos.Count) { Nota $f "Entraron $(Plata (Suma $creditos 'recibido')) de créditos ($((@($creditos | ForEach-Object { $_.acreedor } | Select-Object -Unique)) -join ', ')): no es venta$(if (Suma $creditos 'pagoAnterior') { "; de eso, $(Plata (Suma $creditos 'pagoAnterior')) pagaron el crédito anterior (incluido arriba en las cuotas)" })." }
if ($activo) { Nota $f "Además llegaron facturas de activos por $(Plata $activo) neto ($((@($gastos | Where-Object { $_.categoria -eq 'Inversión (activo fijo)' } | ForEach-Object { $_.sub } | Where-Object { $_ } | Select-Object -Unique)) -join ', ')). No son gasto del mes ni plata que salió: se pagan aparte." }
[void]$f.Add(@())
Sub $f "Para revisar antes de cerrar ($($avisos.Count))"
foreach ($t in $avisos) { [void]$f.Add(@(C "• $t" 10)) }
Hoja 'Resumen' $f @(48, 16, 16, 70)

# ── 1b. Semanas (cuadre semanal: cada peso que salió, con su justificación) ──
$f = New-Object System.Collections.ArrayList
Titulo $f "Semanas — $mesNom" 'Cuadre semanal: cada peso que salió de BCI, Banco de Chile, la tarjeta Visa 8340 y la tarjeta de Mercado Pago, con su justificación (factura, regla o traspaso). Las semanas van de lunes a domingo para que no se pierda ningún pago. Lo único que hay que mirar es lo que dice SIN JUSTIFICAR.'
Sub $f 'Resumen por semana'
Tabla $f @('Semana', 'Pagos', 'Salió', 'Sin justificar', 'Pagos sin justificar', 'Estado') @($semanas | ForEach-Object { ,@($_.nombre, (C $_.n 7), $_.salio, $_.sinJust, (C $_.nSin 7), $(if ($_.nSin) { 'Revisar' } elseif (-not $_.completa) { 'En curso' } else { 'Cerrada ✓' })) }) @(2, 3)
$fuentesSem = @("cartolas BCI $((@($cBci.archivos) | ForEach-Object { $_.Name }) -join ', ') (unidas sin repetir) y $(if ($cBdc.archivo) { $cBdc.archivo.Name } else { 'sin Banco de Chile' })")
$fuentesSem += if ($mp.Count) { 'Mercado Pago: estado de cuenta del mes' } elseif ($liq.Count) { "Mercado Pago: liquidaciones hasta el $($liqHasta.ToString('dd-MM')) ($($liqArchivo.Name))$(if ($capHasta -and $capHasta -gt $liqHasta) { " + capturas de la actividad hasta el $($capHasta.ToString('dd-MM'))" })" } else { 'Mercado Pago: SIN DATOS (faltan las liquidaciones en Descargas), los pagos de la tarjeta no están' }
if ($tarjetas.Count) { $fuentesSem += "tarjeta Visa 8340: $(($tarjetas | ForEach-Object { $_.Name }) -join ' y ')" }
if ($fExtra) { $fuentesSem += "movimientos leídos en la web del banco (movs-extra-$tag.csv)" }
Nota $f "Fuentes: $($fuentesSem -join '; '). Datos hasta el $($datosHasta.ToString('dd-MM'))."
foreach ($s in $semanas) {
  Sub $f "$($s.nombre): $(Plata $s.salio) en $($s.n) pagos$(if ($s.nSin) { " — $($s.nSin) sin justificar por $(Plata $s.sinJust)" } else { ' — todo justificado' })"
  Tabla $f @('Fecha', 'Cuenta', 'A quién', 'Monto', 'Categoría', 'Justificación', 'Detalle') @($s.movs | ForEach-Object { ,@($_.fecha, $_.cuenta, $_.aQuien, $_.monto, $_.categoria, (C $_.justificacion $(if ($_.ok) { $null } else { 10 })), $_.detalle) }) @(3)
}
if (-not $semanas.Count) { Nota $f 'Sin pagos en el mes: ¿faltan las cartolas en Descargas?' }
Nota $f "Para justificar un pago: si tiene factura, cargarla en Wasabil; si se repite todos los meses, agregar la regla en reglas-cierre.csv; si es de la tarjeta de Mercado Pago, poner el nombre del comercio en mp-nombres.csv. Los menores a $(Plata $UMBRAL_OTROS) sin identificar van solos a Otros gastos."
Hoja 'Semanas' $f @(11, 16, 36, 13, 28, 58, 40)

# ── 2. Caja ──
$f = New-Object System.Collections.ArrayList
Titulo $f "Caja — $mesNom" 'Cuánta plata había, cuánta entró, cuánta salió y cuánta quedó. Los traspasos entre cuentas propias se muestran aparte porque no son ingresos ni gastos.'
Tabla $f @('Cuenta', 'Saldo inicial', 'Entradas', 'Salidas', 'Saldo final', 'Traspasos recibidos', 'Traspasos enviados') @($caja | ForEach-Object { ,@($_.cuenta, $_.inicial, $_.ent, $_.sal, $_.final, $_.trI, $_.trE) }) @(1, 2, 3, 4, 5, 6)
Sub $f 'Salidas de los bancos por categoría (con y sin factura, sin traspasos)'
$salCat = @($banco | Where-Object { $_.categoria -ne 'Traspaso interno (no es gasto)' } | Group-Object categoria | ForEach-Object { ,@($_.Name, $_.Count, (Suma $_.Group 'total')) } | Sort-Object { -$_[2] })
Tabla $f @('Categoría', 'Pagos', 'Monto') $salCat @(1, 2)
if ($mp.Count) {
  Sub $f 'Mercado Pago por tipo de movimiento'
  Tabla $f @('Movimiento', 'Cantidad', 'Monto', 'Comisión') @($mp | Group-Object tipo | ForEach-Object { ,@($_.Name, $_.Count, (Suma $_.Group 'monto'), (Suma $_.Group 'comision')) }) @(1, 2, 3)
}
Nota $f 'BCI y Banco de Chile: saldos tomados de la cartola. Mercado Pago: saldos del estado de cuenta.'
Hoja 'Caja' $f @(38, 15, 15, 15, 15, 17, 17)

# ── 3. Ventas ──
$f = New-Object System.Collections.ArrayList
Titulo $f "Ventas — $mesNom" "Pedidos por fecha de venta (solo tipo venta). Mes anterior: $($vAnt.Count) ventas por $(Plata (Suma $vAnt 'total')) con IVA."
Tabla $f @('N°', 'Fecha', 'Cliente', 'Producto', 'Vendedor', 'Total con IVA', 'Neto', 'Valor producto', 'Envío', 'Abonado', 'Saldo') @($vMes | ForEach-Object { ,@("#$($_.num)", $_.fecha, $_.cliente, $_.producto, $_.vendedor, $_.total, (Neto $_.total), $_.vp, $_.envio, $_.abonado, $(if ($_.web) { 0 } else { $_.saldo })) }) @(5, 6, 7, 8, 9, 10)
Sub $f 'Por vendedor'
Tabla $f @('Vendedor', 'Ventas', 'Total con IVA') @($vMes | Group-Object vendedor | ForEach-Object { ,@($_.Name, $_.Count, (Suma $_.Group 'total')) }) @(1, 2)
Sub $f "Comisión de César (tramo $([math]::Round($tramo[1]*100,1).ToString($cl))%)"
[void]$f.Add(@((C 'Valor producto vendido (con IVA)'), (C $vpCesar 2), (C "$($vCesar.Count) ventas; el tramo se elige con este monto" 6)))
[void]$f.Add(@((C 'Valor producto sin IVA'), (C $sinIvaCesar 2), (C 'el % se aplica sobre este monto' 6)))
[void]$f.Add(@((C 'Comisión a pagar' 11), (C $comCesar 13)))
[void]$f.Add(@())
Sub $f 'Otras ventas'
Tabla $f @('Canal', 'Ventas', 'Bruto con IVA', 'Neto') @(
  @('Mercado Libre (boletas Wasabil)', $ventasML.Count, (Suma $ventasML 'total'), (Suma $ventasML 'neto')),
  @('Ferias (Point Mercado Pago)', $ventasFeria.Count, (Suma $ventasFeria 'bruto'), $vNetaFeria)) @(1, 2, 3)
Hoja 'Ventas' $f @(8, 11, 26, 32, 12, 14, 13, 14, 11, 13, 13) 0

# ── 4. Por cobrar y por pagar ──
$f = New-Object System.Collections.ArrayList
Titulo $f 'Por cobrar y por pagar' "Por cobrar: ventas hasta el $($finMes.ToString('dd-MM')) que todavía tienen saldo según Gestión ($($resp.LastWriteTime.ToString('dd-MM HH:mm'))). Por pagar: lo que se debe por $mesNom."
Sub $f 'Por cobrar (sin ventas web)'
Tabla $f @('N°', 'Fecha', 'Cliente', 'Total', 'Abonado', 'Saldo', 'Ojo') @($cobrar | ForEach-Object { ,@("#$($_.num)", $_.fecha, $_.cliente, $_.total, $_.abonado, $_.saldo, $(if ($_.pagadoBanco) { "parece pagado el $($_.pagadoBanco.ToString('dd-MM')) en BCI" })) }) @(3, 4, 5)
Sub $f 'Por pagar'
$pagar = @()
$suel = Suma @($sinFactura | Where-Object { $_.categoria -eq 'Sueldos y remuneraciones' }) 'neto'; $prev = Suma @($sinFactura | Where-Object { $_.categoria -eq 'Imposiciones (Previred)' }) 'neto'
if ($suel) { $pagar += ,@("Sueldos de $mesNom (estimado)", $suel, "igual a lo pagado este mes; ya incluye la comisión de César ($(Plata $comCesar))") }
if ($prev) { $pagar += ,@('Previred (estimado)', $prev, 'igual a lo pagado este mes') }
$pagar += ,@('IVA del mes', [math]::Max(0, $ivaMes), $(if ($ivaMes -lt 0) { "crédito a favor de $(Plata (-$ivaMes)) para el mes siguiente" } else { 'incluye el IVA de las ventas de feria; ver hoja IVA' }))
foreach ($m in LeerCsv (Join-Path $PLAN 'por-pagar-manual.csv')) { $pagar += ,@($m.Concepto, (N $m.Monto), $m.Nota) }
Tabla $f @('Concepto', 'Monto', 'Nota') $pagar @(1)
Hoja 'Por cobrar y pagar' $f @(30, 12, 30, 14, 14, 14, 30)

# ── 5. Madera ──
$f = New-Object System.Collections.ArrayList
$mad = @($todo | Where-Object { $_.categoria -eq 'Madera (proveedores)' } | Sort-Object fecha)
$madTot = Suma $mad 'neto'
Titulo $f "Proveedores de madera — $mesNom" "Montos sin IVA. Madera del mes: $(Plata $madTot), el $([math]::Round($(if ($ventaNeta) { 100 * $madTot / $ventaNeta } else { 0 }))) % de la venta neta. $($m2Mes.ToString('N1', $cl)) m² vendidos → $(Plata $(if ($m2Mes) { $madTot / $m2Mes } else { 0 })) de madera por m²."
Sub $f 'Por proveedor'
Tabla $f @('Proveedor', 'Compras', 'Monto', 'Sin factura') @($mad | Group-Object proveedor | ForEach-Object { ,@($_.Name, $_.Count, (Suma $_.Group 'neto'), (Suma @($_.Group | Where-Object { $_.fuente -ne 'Factura' }) 'neto')) } | Sort-Object { -$_[2] }) @(1, 2, 3)
Sub $f 'Cada compra'
Tabla $f @('Proveedor', 'Fecha', 'Monto', 'Con factura', 'Especie / detalle', 'Documento') @($mad | ForEach-Object { ,@($_.proveedor, $_.fecha, $_.neto, $(if ($_.fuente -eq 'Factura') { 'Sí' } else { 'NO' }), $(if ($_.sub) { "$($_.sub) · $($_.detalle)" } else { $_.detalle }), $_.doc) }) @(2)
Hoja 'Madera' $f @(44, 11, 14, 12, 60, 18)

# ── Starken ──
# Envío cobrado por mes de salida: ver $desp en la sección de ventas.
$f = New-Object System.Collections.ArrayList
$fletes =@($todo | Where-Object { $_.categoria -eq 'Fletes y logística' })
$stk = @($fletes | Where-Object { "$($_.proveedor)" -match 'STARKEN' } | Sort-Object fecha)
$stkTot = Suma $stk 'neto'; $envCobrado = Suma $desp 'envio'
$otrosFletes = @($fletes | Where-Object { $stk -notcontains $_ }); $otrosTot = Suma $otrosFletes 'neto'
Titulo $f "Starken — $mesNom" 'Montos sin IVA. Starken factura a fin de mes todos los despachos del período.'
Sub $f 'Lo que costó y lo que se cobró'
[void]$f.Add(@((C 'Envío cobrado de los pedidos que salieron en el mes' 11), (C $envCobrado 13)))
[void]$f.Add(@((C 'Starken (facturas del mes)' 11), (C $stkTot 13)))
[void]$f.Add(@((C 'Otros fletes (cargo a Santiago y locales)' 11), (C $otrosTot 13)))
[void]$f.Add(@((C 'Diferencia: cobrado menos todos los fletes' 11), (C ($envCobrado - $stkTot - $otrosTot) 13)))
Nota $f 'El envío cuenta en el mes en que sale el pedido (día de envío de Seguimiento o de Producción; si falta, el lunes de su semana + 7 días), igual que el flete. Un pedido vendido a fin de mes cuenta en el mes siguiente.'
[void]$f.Add(@())
Sub $f 'Pedidos que salieron en el mes'
Tabla $f @('Pedido', 'Salida', 'Detalle', 'Envío neto') @($desp | ForEach-Object { ,@("#$($_.num) $($_.cliente)", $_.salida, "Vendido el $($_.venta.ToString('dd-MM-yyyy'))$(if ($_.estimada) { ' · salida estimada (semana + 7 días)' })$(if ($_.estimada -and $cambioFecha["$($_.num)"]) { ', con cambio de fecha: revisar' })", $_.envio) }) @(3)
[void]$f.Add(@())
Sub $f 'Facturas de Starken'
Tabla $f @('Fecha', 'Documento', 'Detalle', 'Neto') @($stk | ForEach-Object { ,@($_.fecha, $_.doc, $_.detalle, $_.neto) }) @(3)
$pagosStk = @($banco | Where-Object { "$($_.proveedor) $($_.glosa)" -match 'Starken' } | Sort-Object fecha)
if ($pagosStk.Count) { Sub $f 'Pagos a Starken en el mes'; Tabla $f @('Fecha', 'Cuenta', 'Detalle', 'Monto') @($pagosStk | ForEach-Object { ,@($_.fecha, $_.cuenta, $(if ($_.detalle) { $_.detalle } else { $_.glosa }), $_.total) }) @(3) }
if ($otrosFletes.Count) { Sub $f 'Otros fletes (cargo a Santiago y locales)'; Tabla $f @('Proveedor', 'Viajes', 'Neto') @($otrosFletes | Group-Object proveedor | ForEach-Object { ,@($_.Name, $_.Count, (Suma $_.Group 'neto')) } | Sort-Object { -$_[2] }) @(1, 2) }
Hoja 'Starken' $f @(48, 18, 60, 14)

# ── 6. Bencina ──
$f = New-Object System.Collections.ArrayList
$ben = @($todo | Where-Object { $_.categoria -eq 'Combustible (bencina)' } | Sort-Object fecha)
Titulo $f "Bencina — $mesNom" 'Cargas con tarjeta y rendiciones que dicen "bencina". Las rendiciones del jefe de taller que mezclan bencina con insumos quedan en Materiales: para separarlas hay que leer sus boletas.'
Tabla $f @('Fecha', 'Dónde / quién', 'Cuenta', 'Detalle', 'Monto') @($ben | ForEach-Object { ,@($_.fecha, $_.proveedor, $_.cuenta, $_.detalle, $_.neto) }) @(4)
$rend = @($todo | Where-Object { $_.sub -eq 'Rendición taller' -and $_.categoria -ne 'Combustible (bencina)' })
Nota $f "Rendiciones mixtas del taller en el mes: $($rend.Count) por $(Plata (Suma $rend 'neto'))."
Hoja 'Bencina' $f @(11, 34, 24, 40, 14)

# ── 7. Sueldos y gastos fijos ──
$f = New-Object System.Collections.ArrayList
Titulo $f "Sueldos — $mesNom" 'CONFIDENCIAL: tiene sueldos por persona. No compartir este archivo.'
$sue = @($sinFactura | Where-Object { $_.categoria -in 'Sueldos y remuneraciones', 'Imposiciones (Previred)' } | Sort-Object fecha)
Sub $f 'Por persona'
Tabla $f @('Persona', 'Pagos', 'Total') @($sue | Group-Object proveedor | ForEach-Object { ,@($_.Name, $_.Count, (Suma $_.Group 'neto')) } | Sort-Object { -$_[2] }) @(1, 2)
Sub $f 'Cada pago'
Tabla $f @('Persona', 'Fecha', 'Concepto', 'Monto') @($sue | ForEach-Object { ,@($_.proveedor, $_.fecha, $(if ($_.detalle) { $_.detalle } else { $_.categoria }), $_.neto) }) @(3)
Hoja 'Sueldos' $f @(34, 11, 40, 14)

# ── Gastos fijos ──
# Lo que cuesta mantener la empresa abierta, y cuánto hay que vender para cubrirlo con el margen del mes.
$f = New-Object System.Collections.ArrayList
$fijos = @($lFijo) + @($lFin | ForEach-Object { [pscustomobject]@{ cat = $(if ($_.cat -eq 'Créditos y deudas (cuotas)') { 'Intereses de créditos' } else { $_.cat }); monto = $_.monto } })
$tFijos = Suma $fijos 'monto'
$tasa = if ($ventaNeta) { $contrib / $ventaNeta } else { 0 }
$equilibrio = if ($tasa -gt 0) { $tFijos / $tasa } else { 0 }
Titulo $f "Gastos fijos — $mesNom" 'Lo que cuesta mantener la empresa abierta, se venda o no. Montos sin IVA; los sueldos son los pagados en el mes.'
Tabla $f @('Concepto', 'Monto', '% del total') @($fijos | Sort-Object monto -Descending | ForEach-Object { ,@($_.cat, $_.monto, (C $(if ($tFijos) { $_.monto / $tFijos } else { 0 }) 4)) }) @(1)
Sub $f '¿Cuánto hay que vender para cubrirlos?'
[void]$f.Add(@((C 'Gastos fijos del mes' 11), (C $tFijos 13)))
[void]$f.Add(@((C 'De cada $100 vendidos, quedan para los fijos' 11), (C ([math]::Round($tasa * 100)) 13)))
[void]$f.Add(@((C 'Venta neta necesaria para cubrirlos' 11), (C ([math]::Round($equilibrio)) 13)))
[void]$f.Add(@((C "Venta neta de $mesNom" 11), (C $ventaNeta 13)))
Nota $f "De cada `$100 que se venden quedan `$$([math]::Round($tasa * 100)) después de materiales, publicidad, ferias, fletes y comisiones. Con eso, cubrir $(Plata $tFijos) de gastos fijos exige vender $(Plata $equilibrio) neto al mes$(if ($ventaNeta -lt $equilibrio) { "; en $mesNom faltaron $(Plata ($equilibrio - $ventaNeta))" } else { '' }). Usa el margen de este mes: una feria o una compra grande de madera lo mueven."
[void]$f.Add(@())
$fij = @($todo | Where-Object { $_.seccion -eq 'fijo' -and $_.categoria -notin 'Sueldos y remuneraciones', 'Imposiciones (Previred)' } | Sort-Object categoria, fecha)
Sub $f 'Detalle (sin sueldos, que están en la hoja Sueldos)'
Tabla $f @('Concepto', 'Fecha', 'Proveedor', 'Detalle', 'Monto') @($fij | ForEach-Object { ,@($_.categoria, $_.fecha, $_.proveedor, $_.detalle, $_.neto) }) @(4)
Hoja 'Gastos fijos' $f @(46, 16, 34, 50, 14)

# ── 8. Marketing y CAC ──
$f = New-Object System.Collections.ArrayList
$cotMes =if ($kpi) { $kpi.conversion_por_mes | Where-Object { $_.mes -eq $tag } | Select-Object -First 1 } else { $null }
Titulo $f "Marketing y costo de adquisición — $mesNom" $(if ($meta) { "Meta: $($meta.fuente)." } else { 'Meta: solo lo facturado (faltan meta-AAAA-MM.json y los pagos de la tarjeta de Mercado Pago).' })
$mk = @(@('Meta (Facebook / Instagram)', $metaReal), @('Google', $google), @('Ferias (arriendo y productos)', $feriaCosto))
Tabla $f @('Canal', 'Gasto') $mk @(1)
Sub $f 'Indicadores'
$nV = $vMes.Count
$ind = @(
  @('Pedidos del mes', $nV, 7), @('Clientes que cotizaron en el mes', $(if ($cotMes) { $cotMes.clientes } else { '' }), 7),
  @('De cotizar a comprar', $(if ($cotMes -and $cotMes.clientes) { $nV / $cotMes.clientes } else { '' }), 4),
  @('CAC: publicidad ÷ pedidos', $(if ($nV) { $ads / $nV } else { 0 }), 2),
  @('Costo por cliente que cotizó', $(if ($cotMes -and $cotMes.clientes) { $ads / $cotMes.clientes } else { '' }), 2),
  @('Publicidad sobre la venta neta', $(if ($ventaNeta) { $ads / $ventaNeta } else { 0 }), 4),
  @('Venta neta por cada $1 en publicidad', $(if ($ads) { $ventaNeta / $ads } else { 0 }), 8),
  @('Meta facturado (Wasabil)', $metaFact, 2)
)
foreach ($i in $ind) { [void]$f.Add(@((C $i[0]), (C $i[1] $i[2]))) }
Hoja 'Marketing y CAC' $f @(42, 16)

# ── 9. Ferias ──
$f = New-Object System.Collections.ArrayList
Titulo $f "Ferias — $mesNom" '¿Valió la pena? Ventas con Point en las fechas de cada feria (ferias.csv) contra sus costos (categoría Ferias).'
# Cada costo va a la feria que lo nombra en ferias.csv (columna Costos: expresión regular que busca en el
# proveedor y en el detalle). Si en el mes hay una sola feria, todos los costos de la categoría Ferias son suyos.
$coFerias = @($todo | Where-Object { $_.categoria -eq 'Ferias' }); $asignados = @()
function EtiquetaCosto($c) {
  if ($c.sub) { return "$($c.sub): $($c.proveedor)" }
  $d = "$($c.detalle)" -replace '\s+x\d+$', ''; if ($d.Length -gt 45) { $d = $d.Substring(0, 45).Trim() + '…' }
  if ($d) { "$d ($($c.proveedor))" } else { "$($c.proveedor)" }
}
foreach ($fe in $ferias) {
  $vs = @($ventasFeria | Where-Object { $_.feria -eq $fe.nombre })
  $co = if ($fe.costos) { @($coFerias | Where-Object { "$($_.proveedor) $($_.detalle)" -match $fe.costos }) } elseif ($ferias.Count -eq 1) { $coFerias } else { @() }
  $asignados += $co
  Sub $f "$($fe.nombre) ($($fe.desde.ToString('dd-MM')) al $($fe.hasta.ToString('dd-MM')))"
  $bruto = Suma $vs 'bruto'; $com = Suma $vs 'comision'
  $res = @(@('Ventas (con IVA)', $bruto), @('− IVA', -($bruto - (Neto $bruto))), @('− Comisión Mercado Pago', -$com))
  foreach ($c in $co) { $res += ,@("− $(EtiquetaCosto $c)", -$c.neto) }
  Tabla $f @('Concepto', 'Monto') $res @(1)
  Nota $f "$($vs.Count) ventas; ticket promedio $(Plata $(if ($vs.Count) { $bruto / $vs.Count } else { 0 }))$(if (-not $co.Count) { '. Sin costos registrados para esta feria' }). No descuenta el costo de los productos de madera propios vendidos ni traslados/colaciones del equipo."
  Tabla $f @('Fecha', 'Venta', 'Comisión') @($vs | ForEach-Object { ,@($_.fecha, $_.bruto, $_.comision) }) @(1, 2)
}
$sinAsignar = @($coFerias | Where-Object { $asignados -notcontains $_ })
if ($sinAsignar.Count) {
  Sub $f 'Costos de ferias sin asignar a una feria'
  Tabla $f @('Proveedor', 'Monto') @($sinAsignar | ForEach-Object { ,@($_.proveedor, $_.neto) }) @(1)
  Nota $f 'Para asignarlos, poner el proveedor o el detalle en la columna Costos de ferias.csv.'
}
if (-not $ferias.Count) { Nota $f 'No hubo ferias este mes (ferias.csv).' }
Hoja 'Ferias' $f @(44, 14, 12)

# ── 10. Cotizador ──
$f = New-Object System.Collections.ArrayList
Titulo $f "Cotizador — $mesNom" $(if ($kpi) { "Datos del Pulso del Cotizador del $($kpi.generado)." } else { 'Falta kpis-cotizador.json.' })
if ($kpi) {
  Sub $f 'Mes a mes'
  Tabla $f @('Mes', 'Clientes que cotizaron', 'Ganados', 'Perdidos', 'En curso', 'Vendido según el panel') @($kpi.conversion_por_mes | ForEach-Object { ,@($_.mes, $_.clientes, $_.ganados, $_.perdidos, $_.en_curso, (C ([double]$_.vendido) 2)) })
  Sub $f 'Embudo de los últimos 14 días'
  $e = $kpi.embudo_14_dias
  Tabla $f @('Visitan', 'Eligen producto', 'Ponen medidas', 'Dejan datos', 'Cotizan') @(,@((C $e.visita 7), (C $e.producto 7), (C $e.medidas 7), (C $e.datos 7), (C $e.cotizacion 7)))
  Sub $f 'Seguimiento'
  $ta = $kpi.toques_atrasados; $ca = $kpi.cartera_abierta
  foreach ($x in @(@('Clientes con toque atrasado', $ta.clientes, 7), @('Monto cotizado de esos clientes', $ta.monto, 2), @('Cartera abierta (clientes)', $ca.clientes, 7), @('Venta probable de la cartera', $ca.venta_probable, 2),
                   @('Horas al primer contacto (mediana)', $kpi.velocidad.mediana_horas, 8), @('Ticket cotizado (mediana)', $kpi.ticket.cotizacion_mediana, 2), @('Ticket vendido (mediana)', $kpi.ticket.venta_mediana, 2))) {
    [void]$f.Add(@((C $x[0]), (C ([double]$x[1]) $x[2]))) }
  [void]$f.Add(@())
  $mp_ = $kpi.motivos_perdida_por_mes | Where-Object { $_.mes -eq $tag } | Select-Object -First 1
  if ($mp_) { Sub $f "Por qué se perdieron ($($mp_.perdidos))"; Tabla $f @('Motivo', 'Clientes') @($mp_.detalle.PSObject.Properties | ForEach-Object { ,@($_.Name, (C ([double]$_.Value) 7)) }) }
  Sub $f 'Productos (últimos 60 días)'
  Tabla $f @('Producto', 'Cotizaciones', 'Ganadas', 'Tasa %', 'Vendido') @($kpi.productos_60_dias | ForEach-Object { ,@($_.producto, (C ([double]$_.cotizaciones) 7), (C ([double]$_.ganadas) 7), (C ([double]$_.tasa) 8), (C ([double]$_.vendido) 2)) })
}
Hoja 'Cotizador' $f @(36, 16, 14, 14, 14, 18)

# ── 11. Facturas recibidas ──
$f = New-Object System.Collections.ArrayList
Titulo $f "Facturas recibidas — $mesNom" 'De la planilla de gastos Wasabil (categorías oficiales). Debajo, los pagos de los bancos que no tienen factura.'
Tabla $f @('Fecha', 'Proveedor', 'RUT', 'Documento', 'Categoría', 'Neto', 'IVA', 'Total', 'Detalle') @($gastos | Sort-Object fecha | ForEach-Object { ,@($_.fecha, $_.proveedor, $_.rut, $_.doc, $_.categoria, $_.neto, $_.iva, $_.total, $_.detalle) }) @(5, 6, 7)
Sub $f 'Resumen por categoría'
Tabla $f @('Categoría', 'Facturas', 'Neto') @($gastos | Group-Object categoria | ForEach-Object { ,@($_.Name, $_.Count, (Suma $_.Group 'neto')) } | Sort-Object { -$_[2] }) @(1, 2)
Sub $f 'Pagos sin factura (bancos)'
$sfGasto = @($sinFactura | Where-Object { $_.seccion } | Sort-Object fecha)
Tabla $f @('Fecha', 'A quién', 'Cuenta', 'Categoría', 'Monto', 'Detalle') @($sfGasto | ForEach-Object { ,@($_.fecha, $_.proveedor, $_.cuenta, $_.categoria, $_.neto, $_.detalle) }) @(4)
Hoja 'Facturas recibidas' $f @(11, 40, 13, 18, 26, 13, 12, 13, 50) 0

# ── 12. Facturas emitidas ──
$f = New-Object System.Collections.ArrayList
Titulo $f "Documentos emitidos — $mesNom" 'Según Wasabil (incluye las boletas de Shopify y Mercado Libre).'
Tabla $f @('Fecha', 'Tipo', 'Folio', 'Cliente', 'RUT', 'Origen', 'Neto', 'IVA', 'Total') @($emit | ForEach-Object { ,@($_.fecha, $_.tipo, $_.folio, $_.cliente, $_.rut, $_.plataforma, $_.neto, $_.iva, $_.total) }) @(6, 7, 8)
Sub $f 'Por tipo'
Tabla $f @('Tipo', 'Cantidad', 'Neto', 'IVA', 'Total') @($emit | Group-Object tipo | ForEach-Object { ,@($_.Name, $_.Count, (Suma $_.Group 'neto'), (Suma $_.Group 'iva'), (Suma $_.Group 'total')) }) @(1, 2, 3, 4)
Sub $f 'Pendientes de emitir según Gestión'
Tabla $f @('N°', 'Cliente', 'Documento', 'Tipo', 'Monto') $pend @(4)
Hoja 'Facturas emitidas' $f @(11, 16, 9, 40, 14, 14, 13, 12, 13) 0

# ── 13. IVA ──
$f = New-Object System.Collections.ArrayList
Titulo $f "IVA — $mesNom" 'Para revisar contra el F29 del contador.'
$iv = @(@('Débito: documentos emitidos (Wasabil)', $debito), @('Débito: ventas de feria con voucher (estimado)', $ivaFeria), @('− Crédito: facturas de compra', -$credito))
Tabla $f @('Concepto', 'Monto') $iv @(1)
Nota $f 'Positivo = IVA a pagar. Negativo = crédito a favor para el mes siguiente. Las facturas de compra que emitimos (Google, Meta, Shopify) retienen el IVA: se paga y se recupera en el mismo F29.'
Nota $f "Crédito según $(if ($sii) { 'el resumen de Wasabil (sii-AAAA-MM.json)' } else { 'la planilla de gastos' }). En la planilla: $(Plata (Suma $gastos 'iva'))."
Hoja 'IVA' $f @(52, 16)

# ── 14. Deudas e inversiones ──
$f = New-Object System.Collections.ArrayList
Titulo $f "Deudas e inversiones — $mesNom" 'El saldo que queda de cada deuda no está en ningún sistema: completarlo a mano para ver la deuda total.'
$CAT_DEUDA = @('Créditos y deudas (cuotas)', 'Préstamos de socios (no es gasto)', 'Pagos de la camioneta', 'Inversión (activo fijo)')
Sub $f 'Pagado en el mes (sale de los bancos y Mercado Pago)'
$di = @($todo | Where-Object { $_.categoria -in $CAT_DEUDA -and $_.fuente -ne 'Factura' } | Sort-Object categoria, fecha | ForEach-Object { ,@($_.categoria, $_.fecha, $_.proveedor, $(if ($_.sub) { $_.sub } else { $_.detalle }), $_.neto, '') })
if ($mpCuotas) { $di += ,@('Créditos y deudas (cuotas)', '', 'Mercado Pago', 'cuota del crédito', $mpCuotas, '') }
Tabla $f @('Tipo', 'Fecha', 'A quién', 'Detalle', 'Monto', 'Saldo que queda') $di @(4)
if ($creditos.Count) {
  Sub $f 'Créditos recibidos en el mes'
  Tabla $f @('Fecha', 'De quién', 'Recibido', 'Pagó el crédito anterior', 'Nota') @($creditos | ForEach-Object { ,@($_.fecha, $_.acreedor, $_.recibido, $_.pagoAnterior, $_.nota) }) @(2, 3)
}
$fd = @($todo | Where-Object { $_.categoria -in $CAT_DEUDA -and $_.fuente -eq 'Factura' } | Sort-Object categoria, fecha)
if ($fd.Count) {
  Sub $f 'Facturas recibidas en el mes (no son pagos)'
  Tabla $f @('Tipo', 'Fecha', 'Proveedor', 'Detalle', 'Neto') @($fd | ForEach-Object { ,@($(if ($_.categoria -eq 'Créditos y deudas (cuotas)') { 'Intereses de créditos (están en el resultado)' } else { $_.categoria }), $_.fecha, $_.proveedor, $_.detalle, $_.neto) })
}
Hoja 'Deudas e inversiones' $f @(30, 11, 34, 30, 14, 16, 16)

# ── Historial ──
$f = New-Object System.Collections.ArrayList
Titulo $f 'Historial mes a mes' 'Se actualiza solo cada vez que se genera el libro de un mes. Montos sin IVA. "parcial" = el mes todavía no terminó o le faltan insumos.'
Tabla $f @('Mes', 'Estado', 'Venta neta', 'Pedidos', 'Ticket promedio', 'Margen bruto', '% margen', 'Gastos fijos', 'Resultado', 'Caja', 'Por cobrar', 'CAC', 'Publicidad', 'Madera') @($histTodo | ForEach-Object {
  ,@($_.Mes, $_.Estado, $_.VentaNeta, (C $_.Pedidos 7), $_.Ticket, $_.MargenBruto, (C $(if ($_.VentaNeta) { $_.MargenBruto / $_.VentaNeta } else { 0 }) 4), $_.GastosFijos, $_.Resultado, $_.Caja, $_.PorCobrar, $_.CAC, $_.Publicidad, $_.Madera) })
Nota $f 'Para un banco o un inversionista: esta hoja y el Resumen. La hoja Sueldos es confidencial, sacarla antes de compartir el archivo.'
Hoja 'Historial' $f @(10, 10, 14, 9, 14, 14, 10, 14, 14, 14, 14, 12, 13, 13)

# Para auditar: $env:LIBRO_DEBUG = 'C:\ruta\movimientos.csv' deja cada gasto con su categoría y sección
if ($env:LIBRO_DEBUG) { $todo | Select-Object fuente, fecha, proveedor, categoria, sub, seccion, neto, detalle | Export-Csv $env:LIBRO_DEBUG -Delimiter ';' -NoTypeInformation -Encoding UTF8 }

# ═════════════════════════════ GUARDAR ═════════════════════════════
# Orden de las hojas: primero lo que más mueve plata.
$ORDEN = @('Resumen', 'Semanas', 'Historial', 'Madera', 'Starken', 'Gastos fijos', 'Caja', 'Ventas', 'Por cobrar y pagar', 'Sueldos', 'Bencina', 'Marketing y CAC', 'Ferias', 'Cotizador', 'Facturas recibidas', 'Facturas emitidas', 'IVA', 'Deudas e inversiones')
$ordenadas = @($hojas | Sort-Object { $i = [array]::IndexOf($ORDEN, $_.nombre); if ($i -lt 0) { 99 } else { $i } })
$hojas.Clear(); foreach ($h in $ordenadas) { [void]$hojas.Add($h) }

New-Item -ItemType Directory -Force $Salida | Out-Null
$ruta = Join-Path $Salida "Libro mensual Casa Zaru $tag.xlsx"
GuardarXlsx $ruta
"Libro: $ruta"
# Tablero HTML al lado del libro (mismo nombre siempre: se abre desde Drive y muestra el último mes generado)
. (Join-Path $PSScriptRoot 'tablero.ps1')
$rutaTab = Join-Path $Salida 'Tablero Casa Zaru.html'
Tablero $rutaTab
"Tablero: $rutaTab"
# Y en PDF: Drive no muestra el HTML como página (ni en el celular), el PDF sí se abre desde el enlace.
$rutaPdf = Join-Path $Salida 'Tablero Casa Zaru.pdf'
if (TableroPdf $rutaTab $rutaPdf) { "Tablero PDF: $rutaPdf" } else { "AVISO: no se pudo generar el PDF del tablero (¿falta Microsoft Edge?)." }
"$mesNom $($iniMes.Year): venta neta $(Plata $ventaNeta) | margen bruto $(Plata $margenBruto) | contribución $(Plata $contrib) | resultado $(Plata $resultado) | caja $(Plata $cajaFin) | avisos $($avisos.Count)"
