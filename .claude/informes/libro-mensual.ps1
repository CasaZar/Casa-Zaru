# Libro mensual de Casa Zaru (Excel, 14 hojas) — el cierre con números de gerente de finanzas
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
  [string]$Salida = 'G:\Mi unidad\Casa Zaru\Informes Gestion'
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
$resp = Get-ChildItem $dirResp -Filter 'respaldo-gestion-*.json' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $resp) { throw "No hay respaldos en $dirResp" }
$j = [IO.File]::ReadAllText($resp.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json
$prod = @{}; @($j.tablas.gestion_produccion) | ForEach-Object { $prod[$_.num] = $_.data }
$ventasTodas = @(@($j.tablas.gestion_finanzas) | ForEach-Object {
  $d = $_.data; $tipo = if ("$($d.tipo)") { "$($d.tipo)" } else { 'VENTA' }
  $a = (N $d.abono1) + (N $d.abono2) + (N $d.abono3); $tot = N $d.total
  [pscustomobject]@{
    num = $_.num; cliente = ("$($d.nombre) $($d.apellido)").Trim(); apellido = "$($d.apellido)"; tipo = $tipo
    fecha = Fecha $(if ($d.fecha_creacion) { $d.fecha_creacion } else { $d.fecha })
    total = $tot; vp = (N $d.val_prod); envio = (N $d.val_envio); abonado = $a; saldo = $tot - $a
    vendedor = $(if ("$($d.vendedor)") { "$($d.vendedor)" } else { '(sin asignar)' })
    producto = "$($d.producto)"; web = ("$($d.canal_pago)" -match 'SHOPIFY')
    d1 = [bool]$d.doc1_emitida; d2 = [bool]$d.doc2_emitida; ab = @((N $d.abono1), (N $d.abono2), (N $d.abono3)); a1 = (N $d.abono1); a23 = (N $d.abono2) + (N $d.abono3); tipoDoc = $d.doc1_tipo
  }
} | Where-Object { $_.tipo -eq 'VENTA' })
$vMes = @($ventasTodas | Where-Object { EnMes $_.fecha } | Sort-Object fecha)
$vAnt = @($ventasTodas | Where-Object { $_.fecha -and $_.fecha -ge $iniMes.AddMonths(-1) -and $_.fecha -lt $iniMes })

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
$mp = @($mp | ForEach-Object { [pscustomobject]@{ fecha = Fecha $_.fecha; mov = $_.mov; tipo = $_.tipo; monto = (N $_.monto); comision = -(N $_.otros) } })
$mpSaldos = LeerJson (Join-Path $CZ "mp-$tag.json")
if (-not $mp.Count) { Aviso "Falta el movimiento de Mercado Pago de $mesNom (mp-$tag.csv): la caja y las ventas de feria quedan incompletas." }

# ── Ventas de feria (Point de Mercado Pago en las fechas de cada feria) ──
$ferias = @(LeerCsv (Join-Path $PLAN 'ferias.csv') | ForEach-Object { [pscustomobject]@{ nombre = $_.Nombre; desde = Fecha $_.Desde; hasta = Fecha $_.Hasta } } | Where-Object { (EnMes $_.desde) -or (EnMes $_.hasta) })
$ventasFeria = @()
foreach ($f in $ferias) {
  $ventasFeria += @($mp | Where-Object { $_.tipo -eq 'Liberación de dinero' -and $_.fecha -ge $f.desde -and $_.fecha -le $f.hasta -and $_.monto -gt 1000 -and $_.monto -lt 300000 } |
    ForEach-Object { [pscustomobject]@{ feria = $f.nombre; fecha = $_.fecha; bruto = $_.monto; comision = $_.comision } })
}
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
$gastos = @(LeerCsv (Join-Path $PLAN 'Gastos Wasabil 2026.csv') | Where-Object { EnMes (Fecha $_.Fecha) } | ForEach-Object {
  $tot = N $_.Monto; $td = "$($_.'Tipo doc')"
  $neto = if ($td -match 'compra|exenta') { $tot } else { Neto $tot }
  $cat = "$($_.'Categoría')"; $sub = ''
  $r = Clasificar 'planilla' "$($_.RUT)" $tot; if ($r) { $cat = $r.Categoria; $sub = $r.Subcategoria }
  [pscustomobject]@{ fuente = 'Factura'; fecha = Fecha $_.Fecha; proveedor = $_.Proveedor; rut = $_.RUT; doc = "$td $($_.Folio)"; folio = "$($_.Folio)"
    categoria = $cat; sub = $sub; neto = $neto; iva = $(if ($td -match 'compra|exenta') { 0 } else { $tot - $neto }); total = $tot; detalle = "$($_.'Detalle (glosa)')" }
})

# ── Bancos: pagos del mes cruzados con las facturas (cargar-cartolas.ps1 en modo simulación) ──
$tmpBanco = Join-Path $env:TEMP "banco-$tag.csv"
& (Join-Path $PLAN 'cargar-cartolas.ps1') -Desde $iniMes.ToString('yyyy-MM-dd') -Simular -ExportarCsv $tmpBanco *> $null
$banco = @(LeerCsv $tmpBanco | Where-Object { EnMes (Fecha $_.Fecha) } | ForEach-Object {
  $txt = "$($_.Glosa) | $($_.Contraparte) | $($_.Nota)"; $monto = N $_.Monto
  $conFactura = "$($_.Factura)" -match '\[(\d+)\]'; $folio = if ($conFactura) { $matches[1] } else { '' }
  $cat = "$($_.Categoria)"; $sub = ''
  if ("$($_.Factura)" -match 'traspaso') { $cat = 'Traspaso interno (no es gasto)' }
  elseif ($conFactura) { $g = $gastos | Where-Object { $_.folio -eq $folio } | Select-Object -First 1; $cat = if ($g) { $g.categoria } else { '(factura de otro mes)' } }
  elseif (-not $cat) { $r = Clasificar 'banco' $txt $monto; if ($r) { $cat = $r.Categoria; $sub = $r.Subcategoria } else { $cat = 'POR CLASIFICAR' } }
  [pscustomobject]@{ fuente = 'Banco sin factura'; fecha = Fecha $_.Fecha; cuenta = $_.Cuenta; proveedor = $(if ($_.Contraparte) { $_.Contraparte } else { ($_.Glosa -replace '^Pago:\s*', '') })
    rut = $_.RUT; doc = ''; conFactura = $conFactura; categoria = $cat; sub = $sub; neto = $monto; iva = 0; total = $monto; detalle = "$($_.Nota)"; glosa = $_.Glosa }
})
Remove-Item $tmpBanco -ErrorAction SilentlyContinue
$sinFactura = @($banco | Where-Object { -not $_.conFactura -and $_.categoria -ne 'Traspaso interno (no es gasto)' })

# ── Saldos de las cuentas ──
. (Join-Path $PLAN 'lib-xls.ps1')
$caja = @()
$fBci = Get-ChildItem "$env:USERPROFILE\Downloads" -Filter '*Movimientos_Detallado_Cuenta_7175*.xlsx' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($fBci) {
  $rows = @(Read-XlsxRows $fBci.FullName | Select-Object -Skip 1 | Where-Object { $_.Count -gt 10 -and $_[0] -match '^\d' } | ForEach-Object {
    [pscustomobject]@{ fecha = [datetime]::FromOADate([double]::Parse($_[0], $INV)).Date; hora = $_[1]; ing = (N $_[8]); egr = (N $_[9]); saldo = (N $_[10]); rut = "$($_[12])"; nombre = "$($_[11])"; nota = "$($_[17])" } } |
    Where-Object { EnMes $_.fecha })
  if ($rows.Count) {
    $ult = $rows | Sort-Object fecha, hora | Select-Object -Last 1
    $ing = Suma $rows 'ing'; $egr = Suma $rows 'egr'
    $trI = Suma @($rows | Where-Object { $_.rut -match $RUT_PROPIO -and $_.ing -gt 0 }) 'ing'; $trE = Suma @($rows | Where-Object { $_.rut -match $RUT_PROPIO -and $_.egr -gt 0 }) 'egr'
    $caja += [pscustomobject]@{ cuenta = 'BCI 7175 (cuenta principal)'; inicial = $ult.saldo - $ing + $egr; ent = $ing; sal = $egr; final = $ult.saldo; trI = $trI; trE = $trE }
    $bciIngresos = @($rows | Where-Object { $_.ing -gt 0 -and $_.rut -notmatch $RUT_PROPIO })
  }
}
$fBdc = Get-ChildItem "$env:USERPROFILE\Downloads" -Filter 'cartola*.xls' | Sort-Object LastWriteTime -Descending
foreach ($f in $fBdc) {
  try { $raw = @(Read-XlsRows $f.FullName) } catch { continue }
  $rows = @($raw | Where-Object { $_.Count -gt 9 -and "$($_[1])" -match '^\d{2}/\d{2}/\d{4}$' } | ForEach-Object {
    [pscustomobject]@{ fecha = [datetime]::ParseExact($_[1], 'dd/MM/yyyy', $INV); glosa = "$($_[3])"; cargo = (N $_[7]); abono = (N $_[8]); saldo = (N $_[9]) } } | Where-Object { EnMes $_.fecha })
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
$mpSinDetalle = -(Suma @($mp | Where-Object { $_.tipo -in 'Pago', 'Compra' }) 'monto') - (Suma @($mp | Where-Object { $_.tipo -eq 'Devolución de pago' }) 'monto')
$mpCuotas = -(Suma @($mp | Where-Object { $_.tipo -eq 'Pago de cuota' }) 'monto')

# ── Meta, SII, cotizador ──
$meta = LeerJson (Join-Path $CZ "meta-$tag.json")
$sii = LeerJson (Join-Path $CZ "sii-$tag.json")
$kpi = LeerJson (Join-Path $CZ 'kpis-cotizador.json')

# ═════════════════════════════ RESULTADO ═════════════════════════════
$SECCION = @{
  'Madera (proveedores)' = 'costo'; 'Materiales e insumos' = 'costo'; 'Bases de fierro (mesas)' = 'costo'; 'Embalaje' = 'costo'; 'Maquinaria y herramientas' = 'costo'
  'Fletes y logística' = 'venta'; 'Comisiones marketplace' = 'venta'; 'Comisiones bancarias' = 'venta'; 'Publicidad Meta' = 'venta'; 'Publicidad Google' = 'venta'; 'Ferias' = 'venta'
  'Sueldos y remuneraciones' = 'fijo'; 'Imposiciones (Previred)' = 'fijo'; 'Arriendo' = 'fijo'; 'Servicios básicos' = 'fijo'; 'Combustible (bencina)' = 'fijo'
  'Transporte / viajes' = 'fijo'; 'Software y suscripciones' = 'fijo'; 'Gastos administrativos' = 'fijo'; 'Mantención y reparaciones' = 'fijo'
  'Colación y alimentación equipo' = 'fijo'; 'Post venta' = 'fijo'; 'Reforestación' = 'fijo'; 'POR CLASIFICAR' = 'fijo'
}
$todo = @($gastos) + @($sinFactura)
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
$lCosto = PorCat 'costo'; $lVenta = PorCat 'venta'; $lFijo = PorCat 'fijo'; $lFin = PorCat 'fin'
$tCosto = Suma $lCosto 'monto'; $tVenta = Suma $lVenta 'monto'; $tFijo = Suma $lFijo 'monto'; $tFin = Suma $lFin 'monto'
$margenBruto = $ventaNeta - $tCosto; $contrib = $margenBruto - $tVenta; $operac = $contrib - $tFijo; $resultado = $operac - $tFin
$ads = $metaReal + (Suma @($todo | Where-Object { $_.categoria -eq 'Publicidad Google' }) 'neto')
$feriaCosto = Suma @($todo | Where-Object { $_.categoria -eq 'Ferias' }) 'neto'

# ═════════════════════════════ AVISOS ═════════════════════════════
# Boletas repetidas: mismo cliente, mismo monto, mismo día, sin nota de crédito que la anule
$nc = @($emit | Where-Object { $_.tipo -match 'cr.dito' })
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
# Pagos a proveedores sin factura
foreach ($g in @($sinFactura | Where-Object { $_.seccion -eq 'costo' -and $_.sub -ne 'Rendición taller' } | Group-Object proveedor | Where-Object { (Suma $_.Group 'neto') -ge 100000 })) {
  Aviso "$($g.Name): $(Plata (Suma $g.Group 'neto')) pagados en $mesNom sin factura (en $($g.Count) pago$(if ($g.Count -gt 1) { 's' }))." }
$porClas = @($todo | Where-Object { $_.categoria -eq 'POR CLASIFICAR' })
if ($porClas.Count) { Aviso "$($porClas.Count) gastos por $(Plata (Suma $porClas 'neto')) siguen POR CLASIFICAR (ver Facturas recibidas). Clasificarlos en la planilla o en reglas-cierre.csv." }
if ($mpSinDetalle -gt 0) { Aviso "Mercado Pago: $(Plata $mpSinDetalle) en pagos y compras sin detalle del comercio (el estado de cuenta PDF no lo trae). No entran al resultado; bajar el reporte en Excel/CSV con descripción para clasificarlos." }
if ($meta -and $metaReal - $metaFact -gt 1000) { Aviso "Meta: gasto real $(Plata $metaReal) pero solo $(Plata $metaFact) tienen factura de compra. Revisar con el contador las facturas que faltan (IVA no recuperado)." }
if ($ventasFeria.Count) { Aviso "Ventas de feria con Point: $(Plata (Suma $ventasFeria 'bruto')) sin boleta electrónica (el voucher vale como boleta). Su IVA ($(Plata ((Suma $ventasFeria 'bruto') - $vNetaFeria))) no está en el débito de Wasabil: confirmar que entre al F29." }
foreach ($v in $vMes) {
  if (-not $v.web -and $v.total -gt 0 -and [math]::Abs($v.total - $v.vp - $v.envio) -gt 1000) { Aviso "Venta #$($v.num) ($($v.cliente)): total $(Plata $v.total) no cuadra con valor producto $(Plata $v.vp) + envío $(Plata $v.envio). Cambia la comisión de César." }
  if ($v.vendedor -eq '(sin asignar)') { Aviso "Venta #$($v.num) ($($v.cliente)) sin vendedor." }
}

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
Titulo $f "Casa Zaru — Cierre de $mesNom $($iniMes.Year)" "Montos sin IVA. Generado $gen. Fuentes: Gestión, planilla de gastos Wasabil, cartolas BCI y Banco de Chile, Mercado Pago, Wasabil y Meta."
Sub $f 'Los números del mes'
$cajaFin = Suma $caja 'final'
$kp = @(
  @('Venta neta del mes', $ventaNeta, "$($vMes.Count) pedidos + $($ventasML.Count) Mercado Libre + $($ventasFeria.Count) ventas de feria"),
  @('Margen bruto', $margenBruto, 'venta − materiales'),
  @('Resultado del mes', $resultado, 'después de todos los gastos del mes'),
  @('Caja total al cierre', $cajaFin, 'BCI + Banco de Chile + Mercado Pago'),
  @('Costo de adquisición por venta (CAC)', $(if ($vMes.Count) { [math]::Round($ads / $vMes.Count) } else { 0 }), 'Meta + Google ÷ pedidos del mes'),
  @('Madera por m² vendido', $(if ($m2Mes -gt 0) { [math]::Round((Suma @($todo | Where-Object { $_.categoria -eq 'Madera (proveedores)' }) 'neto') / $m2Mes) } else { 0 }), "$($m2Mes.ToString('N1', $cl)) m² vendidos")
)
foreach ($k in $kp) { [void]$f.Add(@((C $k[0] 11), (C $k[1] 13), (C $k[2] 6))) }
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
$a = $f.Count + 1; foreach ($l in $lVenta) { L $l.cat (-$l.monto) $(if ($l.cat -eq 'Publicidad Meta' -and $meta) { 'gasto real (no solo lo facturado)' }) }
$rMC = Total 'Margen de contribución' "B$rMB$(Rango $a)" 'lo que deja cada venta para pagar los gastos fijos'
$a = $f.Count + 1; foreach ($l in $lFijo) { L $l.cat (-$l.monto) $(if ($l.cat -eq 'Sueldos y remuneraciones') { 'pagados en el mes (los sueldos se pagan a mes vencido)' }) }
$rRO = Total 'Resultado operacional' "B$rMC$(Rango $a)"
$a = $f.Count + 1; foreach ($l in $lFin) { L "$($l.cat) — intereses" (-$l.monto) }
if (-not $lFin.Count) { L 'Gastos financieros' 0 }
[void](Total 'Resultado del mes' "B$rRO$(Rango $a)")
[void]$f.Add(@())
Sub $f 'Fuera del resultado (plata que salió, pero no es gasto del mes)'
$fuera = @($todo | Where-Object { -not $_.seccion -and $_.categoria -notmatch 'Publicidad Meta' } | Group-Object categoria | ForEach-Object { ,@((C "   $($_.Name)"), (C (Suma $_.Group 'neto') 2)) })
if ($mpCuotas) { $fuera += ,@((C '   Cuota crédito Mercado Pago'), (C $mpCuotas 2)) }
if ($mpSinDetalle -gt 0) { $fuera += ,@((C '   Pagos con Mercado Pago sin detalle'), (C $mpSinDetalle 2)) }
foreach ($x in $fuera) { [void]$f.Add($x) }
[void]$f.Add(@())
Sub $f "Para revisar antes de cerrar ($($avisos.Count))"
foreach ($t in $avisos) { [void]$f.Add(@(C "• $t" 10)) }
Hoja 'Resumen' $f @(48, 16, 10, 60)

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
Titulo $f "Por cobrar y por pagar — al $($finMes.ToString('dd-MM-yyyy'))" 'Lo que nos deben los clientes y lo que debemos nosotros.'
Sub $f 'Por cobrar (ventas con saldo, sin ventas web)'
Tabla $f @('N°', 'Fecha', 'Cliente', 'Total', 'Abonado', 'Saldo', 'Ojo') @($cobrar | ForEach-Object { ,@("#$($_.num)", $_.fecha, $_.cliente, $_.total, $_.abonado, $_.saldo, $(if ($_.pagadoBanco) { "parece pagado el $($_.pagadoBanco.ToString('dd-MM')) en BCI" })) }) @(3, 4, 5)
Sub $f 'Por pagar'
$pagar = @(,@('Comisión de César del mes', $comCesar, 'se paga con el sueldo del mes siguiente'))
$suel = Suma @($sinFactura | Where-Object { $_.categoria -eq 'Sueldos y remuneraciones' }) 'neto'; $prev = Suma @($sinFactura | Where-Object { $_.categoria -eq 'Imposiciones (Previred)' }) 'neto'
if ($suel) { $pagar += ,@("Sueldos de $mesNom (estimado)", $suel, 'igual a lo pagado este mes; se pagan a inicios del mes siguiente') }
if ($prev) { $pagar += ,@('Previred (estimado)', $prev, 'igual a lo pagado este mes') }
if ($sii) { $s = $sii.ventas; $deb = $s.facturas.iva + $s.boletas.iva + $s.notas_credito.iva; $pagar += ,@('IVA del mes', [math]::Max(0, $deb - $sii.compras.facturas.iva), 'débito − crédito según Wasabil; ver hoja IVA') }
foreach ($m in LeerCsv (Join-Path $PLAN 'por-pagar-manual.csv')) { $pagar += ,@($m.Concepto, (N $m.Monto), $m.Nota) }
Tabla $f @('Concepto', 'Monto', 'Nota') $pagar @(1)
Hoja 'Por cobrar y pagar' $f @(30, 12, 30, 14, 14, 14, 30)

# ── 5. Madera ──
$f = New-Object System.Collections.ArrayList
$mad = @($todo | Where-Object { $_.categoria -eq 'Madera (proveedores)' } | Sort-Object fecha)
$madTot = Suma $mad 'neto'
Titulo $f "Compras de madera — $mesNom" "Neto sin IVA (con factura) o monto pagado (sin factura). $($m2Mes.ToString('N1', $cl)) m² vendidos en el mes → $(Plata $(if ($m2Mes) { $madTot / $m2Mes } else { 0 })) de madera por m²."
Tabla $f @('Fecha', 'Proveedor', 'Especie / detalle', 'Documento', 'Monto', 'Con factura') @($mad | ForEach-Object { ,@($_.fecha, $_.proveedor, $(if ($_.sub) { "$($_.sub) · $($_.detalle)" } else { $_.detalle }), $_.doc, $_.neto, $(if ($_.fuente -eq 'Factura') { 'Sí' } else { 'NO' })) }) @(4)
Sub $f 'Por proveedor'
Tabla $f @('Proveedor', 'Compras', 'Monto', 'Sin factura') @($mad | Group-Object proveedor | ForEach-Object { ,@($_.Name, $_.Count, (Suma $_.Group 'neto'), (Suma @($_.Group | Where-Object { $_.fuente -ne 'Factura' }) 'neto')) } | Sort-Object { -$_[2] }) @(1, 2, 3)
Hoja 'Madera' $f @(11, 40, 50, 18, 14, 11) 0

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
Titulo $f "Sueldos y gastos fijos — $mesNom" 'CONFIDENCIAL: tiene sueldos por persona. No compartir este archivo.'
$sue = @($sinFactura | Where-Object { $_.categoria -in 'Sueldos y remuneraciones', 'Imposiciones (Previred)' } | Sort-Object fecha)
Sub $f 'Sueldos e imposiciones pagados en el mes'
Tabla $f @('Fecha', 'Persona', 'Concepto', 'Monto') @($sue | ForEach-Object { ,@($_.fecha, $_.proveedor, $(if ($_.detalle) { $_.detalle } else { $_.categoria }), $_.neto) }) @(3)
Sub $f 'Por persona'
Tabla $f @('Persona', 'Pagos', 'Total') @($sue | Group-Object proveedor | ForEach-Object { ,@($_.Name, $_.Count, (Suma $_.Group 'neto')) } | Sort-Object { -$_[2] }) @(1, 2)
$fij = @($todo | Where-Object { $_.seccion -eq 'fijo' -and $_.categoria -notin 'Sueldos y remuneraciones', 'Imposiciones (Previred)' } | Sort-Object categoria, fecha)
Sub $f 'Otros gastos fijos'
Tabla $f @('Categoría', 'Fecha', 'Proveedor', 'Detalle', 'Monto') @($fij | ForEach-Object { ,@($_.categoria, $_.fecha, $_.proveedor, $_.detalle, $_.neto) }) @(4)
Hoja 'Sueldos y fijos' $f @(30, 11, 34, 40, 14)

# ── 8. Marketing y CAC ──
$f = New-Object System.Collections.ArrayList
$google = Suma @($todo | Where-Object { $_.categoria -eq 'Publicidad Google' }) 'neto'
$cotMes = if ($kpi) { $kpi.conversion_por_mes | Where-Object { $_.mes -eq $tag } | Select-Object -First 1 } else { $null }
Titulo $f "Marketing y costo de adquisición — $mesNom" $(if ($meta) { "Meta: gasto real del reporte de anuncios ($($meta.fuente))." } else { 'Meta: solo lo facturado (falta meta-AAAA-MM.json con el gasto real).' })
$mk = @(@('Meta (Facebook / Instagram)', $metaReal), @('Google', $google), @('Ferias (arriendo y productos)', $feriaCosto))
Tabla $f @('Canal', 'Gasto') $mk @(1)
Sub $f 'Indicadores'
$nV = $vMes.Count
$ind = @(
  @('Pedidos del mes', $nV, 7), @('Clientes que cotizaron en el mes', $(if ($cotMes) { $cotMes.clientes } else { '' }), 7),
  @('De cotizar a comprar', $(if ($cotMes -and $cotMes.clientes) { $nV / $cotMes.clientes } else { '' }), 4),
  @('CAC: publicidad ÷ pedidos', $(if ($nV) { $ads / $nV } else { 0 }), 2),
  @('CAC con ferias', $(if ($nV) { ($ads + $feriaCosto) / $nV } else { 0 }), 2),
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
foreach ($fe in $ferias) {
  $vs = @($ventasFeria | Where-Object { $_.feria -eq $fe.nombre }); $co = @($todo | Where-Object { $_.categoria -eq 'Ferias' })
  Sub $f "$($fe.nombre) ($($fe.desde.ToString('dd-MM')) al $($fe.hasta.ToString('dd-MM')))"
  $bruto = Suma $vs 'bruto'; $com = Suma $vs 'comision'
  $res = @(@('Ventas (con IVA)', $bruto), @('− IVA', -($bruto - (Neto $bruto))), @('− Comisión Mercado Pago', -$com))
  foreach ($c in $co) { $res += ,@("− $($c.sub): $($c.proveedor)", -$c.neto) }
  Tabla $f @('Concepto', 'Monto') $res @(1)
  Nota $f "$($vs.Count) ventas; ticket promedio $(Plata $(if ($vs.Count) { $bruto / $vs.Count } else { 0 })). No descuenta el costo de los productos de madera propios vendidos ni traslados/colaciones del equipo."
  Tabla $f @('Fecha', 'Venta', 'Comisión') @($vs | ForEach-Object { ,@($_.fecha, $_.bruto, $_.comision) }) @(1, 2)
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
$pend = @()
foreach ($r in ($ventasTodas | Where-Object { -not $_.web -and $_.fecha -and $_.fecha -le $finMes })) {
  if ($r.a1 -gt 0 -and -not $r.d1) { $pend += ,@("#$($r.num)", $r.cliente, 'Doc 1', $r.tipoDoc, $r.a1) }
  if ($r.a23 -gt 0 -and -not $r.d2) { $pend += ,@("#$($r.num)", $r.cliente, 'Doc 2', $r.tipoDoc, $r.a23) }
}
Sub $f 'Pendientes de emitir según Gestión'
Tabla $f @('N°', 'Cliente', 'Documento', 'Tipo', 'Monto') $pend @(4)
Hoja 'Facturas emitidas' $f @(11, 16, 9, 40, 14, 14, 13, 12, 13) 0

# ── 13. IVA ──
$f = New-Object System.Collections.ArrayList
Titulo $f "IVA — $mesNom" 'Para revisar contra el F29 del contador.'
$debito = Suma $emit 'iva'; $credito = if ($sii) { $sii.compras.facturas.iva } else { Suma $gastos 'iva' }
$ivaFeria = (Suma $ventasFeria 'bruto') - $vNetaFeria
$iv = @(@('Débito: documentos emitidos (Wasabil)', $debito), @('Débito: ventas de feria con voucher (estimado)', $ivaFeria), @('− Crédito: facturas de compra', -$credito))
Tabla $f @('Concepto', 'Monto') $iv @(1)
Nota $f 'Positivo = IVA a pagar. Negativo = crédito a favor para el mes siguiente. Las facturas de compra que emitimos (Google, Meta, Shopify) retienen el IVA: se paga y se recupera en el mismo F29.'
Nota $f "Crédito según $(if ($sii) { 'el resumen de Wasabil (sii-AAAA-MM.json)' } else { 'la planilla de gastos' }). En la planilla: $(Plata (Suma $gastos 'iva'))."
Hoja 'IVA' $f @(52, 16)

# ── 14. Deudas e inversiones ──
$f = New-Object System.Collections.ArrayList
Titulo $f "Deudas e inversiones — $mesNom" 'Lo pagado en el mes. El saldo que queda de cada deuda no está en ningún sistema: completarlo a mano para ver la deuda total.'
$di = @($todo | Where-Object { $_.categoria -in 'Inversión (activo fijo)', 'Créditos y deudas (cuotas)', 'Préstamos de socios (no es gasto)' } | Sort-Object categoria, fecha | ForEach-Object { ,@($_.categoria, $_.fecha, $_.proveedor, $(if ($_.sub) { $_.sub } else { $_.detalle }), $_.neto, $_.fuente, '') })
if ($mpCuotas) { $di += ,@('Créditos y deudas (cuotas)', '', 'Mercado Pago', 'cuota crédito', $mpCuotas, 'Mercado Pago', '') }
Tabla $f @('Tipo', 'Fecha', 'A quién', 'Detalle', 'Monto', 'Fuente', 'Saldo que queda') $di @(4)
Hoja 'Deudas e inversiones' $f @(30, 11, 34, 30, 14, 16, 16)

# Para auditar: $env:LIBRO_DEBUG = 'C:\ruta\movimientos.csv' deja cada gasto con su categoría y sección
if ($env:LIBRO_DEBUG) { $todo | Select-Object fuente, fecha, proveedor, categoria, sub, seccion, neto, detalle | Export-Csv $env:LIBRO_DEBUG -Delimiter ';' -NoTypeInformation -Encoding UTF8 }

# ═════════════════════════════ GUARDAR ═════════════════════════════
New-Item -ItemType Directory -Force $Salida | Out-Null
$ruta = Join-Path $Salida "Libro mensual Casa Zaru $tag.xlsx"
GuardarXlsx $ruta
"Libro: $ruta"
"$mesNom $($iniMes.Year): venta neta $(Plata $ventaNeta) | margen bruto $(Plata $margenBruto) | contribución $(Plata $contrib) | resultado $(Plata $resultado) | caja $(Plata $cajaFin) | avisos $($avisos.Count)"
