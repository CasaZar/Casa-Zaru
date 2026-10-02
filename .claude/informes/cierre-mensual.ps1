# Cierre mensual de Gestión (PDF) — Casa Zaru
#
# Lee el último respaldo diario de Gestión (Drive, 03:00) y arma el cierre de un
# mes calendario: cuánto se vendió, cuánto queda de eso para la empresa, cuánto
# falta cobrar, la comisión de César a pagar, documentos emitidos y pendientes, y
# una lista de cosas a corregir antes de dar el mes por cerrado.
# Todo número sale de acá, nunca escrito a mano.
#
# El repo es PÚBLICO: este script no lleva datos de clientes. Los datos solo
# viven en el respaldo y en el PDF, que queda en Drive.
#
# Uso:  .\cierre-mensual.ps1                  (mes anterior)
#       .\cierre-mensual.ps1 -Mes 2026-09     (un mes en particular)
param(
  [string]$Mes,
  [string]$Salida = 'G:\Mi unidad\Casa Zaru\Informes Gestion'
)
$ErrorActionPreference = 'Stop'
$cl = [Globalization.CultureInfo]'es-CL'
$MESES = @('ENERO','FEBRERO','MARZO','ABRIL','MAYO','JUNIO','JULIO','AGOSTO','SEPTIEMBRE','OCTUBRE','NOVIEMBRE','DICIEMBRE')
$TRAMOS = @(@(0, 0.02), @(15000000, 0.025), @(25000000, 0.035))   # comisión César sobre val_prod del mes
$IVA = 0.19

# ── Fechas ────────────────────────────────────────────────────────────────
$iniMes = if ($Mes) { [datetime]::ParseExact("$Mes-01", 'yyyy-MM-dd', $null) } else { (Get-Date -Day 1).Date.AddMonths(-1) }
$finMes = $iniMes.AddMonths(1).AddDays(-1)
$iniAnt = $iniMes.AddMonths(-1); $finAnt = $iniMes.AddDays(-1)
function NomMes($d) { $n = $MESES[$d.Month - 1]; $n.Substring(0,1) + $n.Substring(1).ToLower() }
$mesNom = NomMes $iniMes; $mesAntNom = NomMes $iniAnt

# ── Datos ─────────────────────────────────────────────────────────────────
$dirResp = 'G:\Mi unidad\Casa Zaru\Boletas y Facturas - Ventas 2026\Respaldos Gestion'
$resp = Get-ChildItem $dirResp -Filter 'respaldo-gestion-*.json' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $resp) { throw "No hay respaldos en $dirResp" }
$j = [IO.File]::ReadAllText($resp.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json

function N($x) { if ($x -eq $null -or "$x" -eq '') { 0 } else { [double]("$x" -replace '[^\d\.-]', '') } }
function Fecha($s) {            # acepta 5/9/2026, 05-09-2026 y 2026-09-05
  if ("$s" -match '^(\d{4})-(\d{1,2})-(\d{1,2})') { $y = $matches[1]; $m = $matches[2]; $d = $matches[3] }
  elseif ("$s" -match '^(\d{1,2})[/-](\d{1,2})[/-](\d{4})') { $d = $matches[1]; $m = $matches[2]; $y = $matches[3] }
  else { return $null }
  try { return (Get-Date -Year ([int]$y) -Month ([int]$m) -Day ([int]$d)).Date } catch { return $null }
}
function Plata($v) { '$' + ([double]$v).ToString('N0', $cl) }
function E($s) { [Net.WebUtility]::HtmlEncode("$s") }
function Suma($lista, $campo) { $s = (@($lista) | Measure-Object $campo -Sum).Sum; if ($s) { $s } else { 0 } }
function EnMes($lista, $a, $b) { @($lista | Where-Object { $_.fecha -and $_.fecha -ge $a -and $_.fecha -le $b }) }
function Pct($a, $b) { if ($b -gt 0) { [math]::Round(100 * ($a - $b) / $b) } else { $null } }
function Delta($a, $b) {
  $p = Pct $a $b; if ($p -eq $null) { return '<span class="d">—</span>' }
  $c = if ($p -ge 0) { 'up' } else { 'down' }; $s = if ($p -ge 0) { '▲' } else { '▼' }
  "<span class=""d $c"">$s $([math]::Abs($p))%</span>"
}
function Categoria($p) {
  $t = "$p".ToLower()
  if ($t -match 'puerta') { 'Puertas' } elseif ($t -match 'mesa') { 'Mesas' } elseif ($t -match 'vanitorio|ba[ñn]o') { 'Vanitorios' }
  elseif ($t -match 'cocina') { 'Cubiertas de cocina' } elseif ($t -match 'escritorio') { 'Escritorios' } elseif ($t -match 'repisa') { 'Repisas' }
  elseif ($t -match 'cubierta|mes[oó]n|tablero') { 'Cubiertas' } else { 'Otros' }
}

$todos = @($j.tablas.gestion_finanzas) | ForEach-Object {
  $d = $_.data
  $tipo = if ("$($d.tipo)") { "$($d.tipo)" } else { 'VENTA' }
  $a = (N $d.abono1) + (N $d.abono2) + (N $d.abono3); $tot = N $d.total
  [pscustomobject]@{
    num = $_.num; cliente = ("$($d.nombre) $($d.apellido)").Trim(); tipo = $tipo
    fecha = Fecha $(if ($d.fecha_creacion) { $d.fecha_creacion } else { $d.fecha })
    total = $tot; vp = (N $d.val_prod); envio = (N $d.val_envio); abonado = $a; saldo = $tot - $a
    plataformas = (N $d.costo_plataformas)
    vendedor = $(if ("$($d.vendedor)") { "$($d.vendedor)" } else { '(sin asignar)' })
    producto = "$($d.producto)"; web = ("$($d.canal_pago)" -match 'SHOPIFY')
    pago = $(if ("$($d.canal_pago)") { "$($d.canal_pago)" } else { "$($d.medio_pago)" })
    d1 = [bool]$d.doc1_emitida; d2 = [bool]$d.doc2_emitida; a1 = (N $d.abono1); a23 = (N $d.abono2) + (N $d.abono3)
    tipoDoc = $d.doc1_tipo
  }
}
$ventasTodas = @($todos | Where-Object { $_.tipo -eq 'VENTA' })
$vMes = EnMes $ventasTodas $iniMes $finMes | Sort-Object { [int]("$($_.num)" -replace '\D', '0') }
$vAnt = EnMes $ventasTodas $iniAnt $finAnt
$noVenta = EnMes @($todos | Where-Object { $_.tipo -ne 'VENTA' }) $iniMes $finMes

# ── Números del mes ───────────────────────────────────────────────────────
$tot = Suma $vMes 'total'; $totAnt = Suma $vAnt 'total'
$vp = Suma $vMes 'vp'; $envios = Suma $vMes 'envio'; $plat = Suma $vMes 'plataformas'
$neto = [math]::Round($tot / (1 + $IVA)); $ivaDeb = $tot - $neto
$abon = Suma $vMes 'abonado'; $saldoMes = Suma @($vMes | Where-Object { $_.saldo -gt 1000 -and -not $_.web }) 'saldo'
$ticket = if ($vMes.Count) { $tot / $vMes.Count } else { 0 }

# Comisión César: liquidación del mes
$vCesar = @($vMes | Where-Object { $_.vendedor -match 'sar' })
$vpCesar = Suma $vCesar 'vp'
$tramo = $TRAMOS[0]; foreach ($t in $TRAMOS) { if ($vpCesar -ge $t[0]) { $tramo = $t } }
# Igual que la planilla de liquidación: el tramo se elige con el valor producto,
# pero el % se aplica sobre el valor producto SIN IVA (redondeado por venta).
$sinIvaCesar = 0; foreach ($v in $vCesar) { $sinIvaCesar += [math]::Round($v.vp / (1 + $IVA)) }
$comCesar = [math]::Round($sinIvaCesar * $tramo[1])

# Lo que queda: venta neta de IVA, menos envío (se le paga al transporte), plataformas y comisión
$envNeto = [math]::Round($envios / (1 + $IVA))
$queda = $neto - $envNeto - $plat - $comCesar

# Cobranza al cierre (todas las ventas, no solo las del mes; Shopify cobra el total)
$cobrar = @($ventasTodas | Where-Object { $_.saldo -gt 1000 -and -not $_.web -and $_.fecha -le $finMes } | Sort-Object fecha)
$totCobrar = Suma $cobrar 'saldo'

# Documentos emitidos en el mes (registro de emisiones de la app)
$docsMes = @($j.tablas.gestion_documentos | Where-Object { $f = Fecha $_.fecha; $f -and $f -ge $iniMes -and $f -le $finMes })
$docsVig = @($docsMes | Where-Object { -not $_.anulada }); $docsAnul = @($docsMes | Where-Object { $_.anulada })
$porTipoDoc = @($docsVig | Group-Object tipo | ForEach-Object { [pscustomobject]@{ k=$_.Name; n=$_.Count; m=(Suma $_.Group 'monto') } })
$pendDocs = @()
foreach ($r in ($ventasTodas | Where-Object { -not $_.web -and $_.fecha -le $finMes })) {
  if ($r.a1 -gt 0 -and -not $r.d1) { $pendDocs += [pscustomobject]@{ num=$r.num; cliente=$r.cliente; doc='Doc 1'; tipo=$r.tipoDoc; monto=$r.a1 } }
  if ($r.a23 -gt 0 -and -not $r.d2) { $pendDocs += [pscustomobject]@{ num=$r.num; cliente=$r.cliente; doc='Doc 2'; tipo=$r.tipoDoc; monto=$r.a23 } }
}

# Compras del mes (facturas recibidas importadas desde Wasabil)
$compras = @($j.tablas.documentos_recibidos | Where-Object { $f = Fecha $_.fecha; $f -and $f -ge $iniMes -and $f -le $finMes })
$compNeto = Suma $compras 'neto'; $compIva = Suma $compras 'iva'

# Antes de cerrar: datos que faltan y cambian los números
$revisar = @()
foreach ($v in $vMes) {
  if ($v.vendedor -eq '(sin asignar)') { $revisar += ,@("#$($v.num)", (E $v.cliente), 'Sin vendedor: no entra a la comisión') }
  if ($v.vp -le 0 -and $v.total -gt 0) { $revisar += ,@("#$($v.num)", (E $v.cliente), 'Sin valor producto (val_prod)') }
  if ($v.total -gt 0 -and [math]::Abs($v.total - $v.vp - $v.envio) -gt 1000 -and -not $v.web) { $revisar += ,@("#$($v.num)", (E $v.cliente), "Total $(Plata $v.total) no cuadra con valor producto $(Plata $v.vp) + envío $(Plata $v.envio): diferencia $(Plata ($v.total - $v.vp - $v.envio))") }
  if ($v.total -le 0) { $revisar += ,@("#$($v.num)", (E $v.cliente), 'Venta con total $0') }
  if ($v.web -and $v.plataformas -le 0) { $revisar += ,@("#$($v.num)", (E $v.cliente), 'Venta web sin costo de plataforma') }
}

# ── HTML ──────────────────────────────────────────────────────────────────
function Tabla($cols, $filas, $clase = '') {
  $h = "<table class=""$clase""><thead><tr>" + (($cols | ForEach-Object { "<th>$_</th>" }) -join '') + '</tr></thead><tbody>'
  if (-not $filas -or @($filas).Count -eq 0) { return $h + "<tr><td colspan=""$($cols.Count)"" class=""vacio"">Sin registros</td></tr></tbody></table>" }
  $h + ((@($filas) | ForEach-Object { '<tr>' + (($_ | ForEach-Object { "<td>$_</td>" }) -join '') + '</tr>' }) -join '') + '</tbody></table>'
}
function Grupo($lista, $fn, $titulo) {
  $g = @($lista | ForEach-Object { [pscustomobject]@{ k=(& $fn $_); total=$_.total } } | Group-Object k |
    ForEach-Object { [pscustomobject]@{ k=$_.Name; n=$_.Count; m=(Suma $_.Group 'total') } } | Sort-Object m -Descending)
  Tabla @($titulo, 'Ventas', 'Monto', '%') ($g | ForEach-Object { ,@((E $_.k), $_.n, (Plata $_.m), $(if ($tot) { [math]::Round(100 * $_.m / $tot).ToString() + '%' } else { '' })) })
}

$tVentas = $vMes | Sort-Object fecha | ForEach-Object {
  ,@("#$($_.num)", $_.fecha.ToString('dd\/MM'), (E $_.cliente), (E $_.producto), (E $_.vendedor), (Plata $_.total), (Plata $_.vp), $(if ($_.web) { 'web' } elseif ($_.saldo -gt 1000) { "<b class=""rojo"">$(Plata $_.saldo)</b>" } else { '✓' }))
}
$tCesar = $vCesar | Sort-Object fecha | ForEach-Object { ,@("#$($_.num)", $_.fecha.ToString('dd\/MM'), (E $_.cliente), (Plata $_.vp)) }
$tCobrar = $cobrar | ForEach-Object { ,@("#$($_.num)", $_.fecha.ToString('dd\/MM'), (E $_.cliente), (Plata $_.total), (Plata $_.abonado), "<b>$(Plata $_.saldo)</b>") }
$tPend = $pendDocs | ForEach-Object { ,@("#$($_.num)", (E $_.cliente), $_.doc, (E $_.tipo), (Plata $_.monto)) }
$tTipoDoc = $porTipoDoc | ForEach-Object { ,@((E $_.k), $_.n, (Plata $_.m)) }
$tAnul = $docsAnul | ForEach-Object { ,@("#$($_.num)", (E $_.tipo), "folio $(E $_.folio)", (Plata $_.monto)) }
$sig = $TRAMOS | Where-Object { $_[0] -gt $vpCesar } | Select-Object -First 1
$faltaTramo = if ($sig) { "Le faltaron $(Plata ($sig[0] - $vpCesar)) para el tramo de $([math]::Round($sig[1]*100,1).ToString($cl))%." } else { 'Quedó en el tramo máximo.' }
$pctTramo = [math]::Round($tramo[1] * 100, 1).ToString($cl)

$resumen = @(
  ,@('Venta total del mes (con IVA)', "<b>$(Plata $tot)</b>", "$($vMes.Count) ventas")
  ,@('− IVA de las ventas (19%)', (Plata $ivaDeb), 'se paga al SII; se descuenta el IVA de las compras')
  ,@('= Venta neta', "<b>$(Plata $neto)</b>", '')
  ,@('− Envíos cobrados al cliente (neto)', (Plata $envNeto), 'plata que pasa al transporte')
  ,@('− Comisiones Shopify / Mercado Pago', (Plata $plat), 'descontadas de lo depositado')
  ,@("− Comisión César ($pctTramo%)", (Plata $comCesar), 'a pagar')
  ,@('= Queda para madera, taller, sueldos y utilidad', "<b>$(Plata $queda)</b>", 'antes de costos de fabricación')
)
$siiPath = Join-Path $env:USERPROFILE ".casazaru\sii-$($iniMes.ToString('yyyy-MM')).json"
$comprasHtml = if (Test-Path $siiPath) {
  # Totales del mes según el SII (Wasabil), guardados fuera del repo
  $sii = [IO.File]::ReadAllText($siiPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
  $sv = $sii.ventas; $sc = $sii.compras
  $netoDoc = $sv.facturas.neto + $sv.boletas.neto + $sv.notas_credito.neto; $deb = $sv.facturas.iva + $sv.boletas.iva + $sv.notas_credito.iva
  $cred = $sc.facturas.iva; $netoComp = $sc.facturas.neto + $sc.exentas.neto; $saldoIva = $deb - $cred
  $filas = @(
    ,@("Ventas documentadas ($($sv.facturas.n) facturas, $($sv.boletas.n) boletas, $($sv.notas_credito.n) notas de crédito)", (Plata $netoDoc), (Plata $deb))
    ,@("Compras ($($sc.facturas.n) facturas + $($sc.exentas.n) exenta)", (Plata $netoComp), (Plata $cred))
    ,@($(if ($saldoIva -ge 0) { '<b>IVA a pagar</b>' } else { '<b>Sin IVA a pagar: queda crédito a favor</b>' }), '', "<b>$(Plata ([math]::Abs($saldoIva)))</b>")
  )
  (Tabla @('Según el SII (Wasabil)', 'Neto', 'IVA') $filas) +
  "<div class=""sub"">Lo documentado no calza con lo vendido: las boletas siguen a los pagos (incluye abonos de ventas de meses anteriores y las de Shopify). Facturas de compra emitidas por nosotros: $($sc.facturas_de_compra.n), IVA retenido $(Plata $sc.facturas_de_compra.iva_retenido) (se paga y se recupera, neutro). Confirmar contra el F29 del contador. Fuente: $(E $sii.fuente).</div>"
} elseif ($compras.Count) {
  "<div class=""nota"">Facturas de compra del mes: <b>$($compras.Count)</b> por <b>$(Plata $compNeto)</b> neto + $(Plata $compIva) de IVA (crédito fiscal). IVA estimado a pagar: <b>$(Plata ([math]::Max(0, $ivaDeb - $compIva)))</b> (débito $(Plata $ivaDeb) − crédito $(Plata $compIva)). Confirmar contra el F29.</div>"
} else {
  "<div class=""nota"">⚠ No hay facturas de compra de $mesNom en Gestión (Recibidos). Sin ellas no se puede calcular el IVA a pagar ni el gasto del mes desde acá.</div>"
}

$html = @"
<!doctype html><html lang="es"><head><meta charset="utf-8"><title>Cierre $mesNom $($iniMes.Year)</title><style>
@page { size: A4; margin: 14mm 12mm; }
* { box-sizing: border-box; }
body { font-family: 'Segoe UI', Arial, sans-serif; color: #2B2118; font-size: 10.5pt; margin: 0; }
h1 { font-size: 20pt; margin: 0; color: #5C3D20; }
h2 { font-size: 12.5pt; color: #7B5B3A; border-bottom: 2px solid #E8DFD5; padding-bottom: 4px; margin: 20px 0 8px; break-after: avoid; }
.sub { color: #8A7960; font-size: 9pt; margin-top: 2px; }
.kpis { display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px; margin-top: 14px; }
.kpi { background: #F7F2EC; border-radius: 8px; padding: 10px 12px; }
.kpi .l { font-size: 8pt; text-transform: uppercase; letter-spacing: .05em; color: #8A7960; }
.kpi .v { font-size: 15pt; font-weight: 700; color: #5C3D20; margin-top: 2px; }
.d { font-size: 8.5pt; font-weight: 600; color: #8A7960; } .up { color: #2E7D32; } .down { color: #B4342A; }
table { width: 100%; border-collapse: collapse; font-size: 9pt; }
th { text-align: left; background: #F2ECE4; color: #6B5840; font-weight: 600; padding: 5px 6px; font-size: 8.5pt; }
td { padding: 4px 6px; border-bottom: 1px solid #EFE8DF; } tr { break-inside: avoid; }
table.res td { font-size: 10pt; padding: 6px 8px; } table.res td:nth-child(2) { text-align: right; white-space: nowrap; width: 130px; }
table.res td:nth-child(3) { color: #8A7960; font-size: 8.5pt; }
.vacio { color: #9A8B7C; text-align: center; font-style: italic; }
.dos { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; }
.nota { background: #FDF6E8; border-left: 3px solid #C9902A; padding: 8px 10px; font-size: 9pt; margin: 6px 0; }
.rojo { color: #B4342A; }
.pie { margin-top: 22px; font-size: 8pt; color: #9A8B7C; border-top: 1px solid #E8DFD5; padding-top: 6px; }
</style></head><body>
<h1>🪵 Casa Zaru — Cierre de $mesNom $($iniMes.Year)</h1>
<div class="sub">Ventas por fecha de venta, solo tipo venta (sin muestrarios ni devoluciones) · generado $((Get-Date).ToString('dd\/MM\/yyyy HH:mm'))</div>

<div class="kpis">
  <div class="kpi"><div class="l">Vendido en $mesNom</div><div class="v">$(Plata $tot)</div>$(Delta $tot $totAnt) <span class="d">vs $mesAntNom ($(Plata $totAnt))</span></div>
  <div class="kpi"><div class="l">N° de ventas</div><div class="v">$($vMes.Count)</div><span class="d">$($mesAntNom): $($vAnt.Count)</span></div>
  <div class="kpi"><div class="l">Ticket promedio</div><div class="v">$(Plata $ticket)</div></div>
  <div class="kpi"><div class="l">Falta cobrar del mes</div><div class="v">$(Plata $saldoMes)</div><span class="d">cobrado: $(Plata $abon)</span></div>
</div>

<h2>El mes en una tabla</h2>
$(Tabla @('Concepto','Monto','') $resumen 'res')

<h2>IVA y compras del mes</h2>
$comprasHtml

<h2>Comisión de César · $mesNom (a pagar)</h2>
<div class="nota">Valor producto vendido por César: <b>$(Plata $vpCesar)</b> en $($vCesar.Count) ventas → tramo <b>$pctTramo%</b>, aplicado sobre el valor sin IVA ($(Plata $sinIvaCesar)) → <b>comisión $(Plata $comCesar)</b>. $faltaTramo</div>
$(Tabla @('N°','Fecha','Cliente','Valor producto') $tCesar)

<h2>Antes de cerrar: revisar ($($revisar.Count))</h2>
<div class="sub" style="margin-bottom:6px">Datos que faltan en Gestión y cambian los números de arriba. Corregir en la app y volver a generar el cierre (toma el respaldo de las 03:00).</div>
$(Tabla @('N°','Cliente','Qué falta') $revisar)

<h2>Ventas de $mesNom ($($vMes.Count))</h2>
$(Tabla @('N°','Fecha','Cliente','Producto','Vendedor','Total','Val. producto','Saldo') $tVentas)
$(if ($noVenta.Count) { "<div class=""sub"">No cuentan como venta: $($noVenta.Count) registros ($((@($noVenta | Group-Object tipo | ForEach-Object { "$($_.Count) $($_.Name.ToLower())" })) -join ', ')).</div>" })

<h2>De dónde vino la venta</h2>
<div class="dos"><div>$(Grupo $vMes { param($x) $x.vendedor } 'Vendedor')</div><div>$(Grupo $vMes { param($x) Categoria $x.producto } 'Producto')</div></div>
<div style="margin-top:10px">$(Grupo $vMes { param($x) $(if ($x.pago) { $x.pago } else { '(sin dato)' }) } 'Forma de pago')</div>

<h2>Documentos tributarios</h2>
<div class="dos"><div>
  <b>Emitidos desde la app en $mesNom</b>
  $(Tabla @('Tipo','Cantidad','Monto') $tTipoDoc)
  $(if ($docsAnul.Count) { "<div class=""sub"" style=""margin-top:6px"">Anulados con nota de crédito: $($docsAnul.Count)</div>" + (Tabla @('N°','Tipo','Folio','Monto') $tAnul) })
  <div class="sub">Las boletas que emite Shopify no pasan por este registro.</div>
</div><div>
  <b>Pendientes de emitir al cierre ($($pendDocs.Count))</b>
  $(Tabla @('N°','Cliente','Doc','Tipo','Monto') $tPend)
</div></div>

<h2>Por cobrar al cierre del mes ($(Plata $totCobrar) en $($cobrar.Count))</h2>
<div class="sub" style="margin-bottom:6px">Todas las ventas hasta el $($finMes.ToString('dd\/MM')) con saldo, no solo las del mes. Sin ventas web (Shopify cobra el total).</div>
$(Tabla @('N°','Fecha','Cliente','Total','Abonado','Saldo') $tCobrar)

<div class="pie">Fuente: $(E $resp.Name) (respaldo de Gestión del $($resp.LastWriteTime.ToString('dd\/MM\/yyyy HH:mm'))). Lo marcado en la app después de esa hora no aparece. IVA calculado como 19/119 del total. "Queda" no descuenta madera, taller ni sueldos: el costeo por pedido todavía no está cargado.</div>
</body></html>
"@

# ── PDF ───────────────────────────────────────────────────────────────────
New-Item -ItemType Directory -Force $Salida | Out-Null
$tag = $iniMes.ToString('yyyy-MM')
$tmp = Join-Path $env:TEMP "cierre-gestion-$tag.html"
[IO.File]::WriteAllText($tmp, $html, (New-Object Text.UTF8Encoding($true)))
$pdf = Join-Path $Salida "Cierre mensual Casa Zaru $tag.pdf"
$edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $edge) { throw 'No encontré Microsoft Edge para generar el PDF.' }
$uri = ([Uri]$tmp).AbsoluteUri
$p = Start-Process -FilePath $edge -ArgumentList @('--headless=new', '--disable-gpu', '--no-pdf-header-footer', "--print-to-pdf=`"$pdf`"", $uri) -Wait -PassThru -WindowStyle Hidden
if (-not (Test-Path $pdf)) { throw "Edge no generó el PDF (código $($p.ExitCode))." }
if (-not $env:CIERRE_DEJAR_HTML) { Remove-Item $tmp -ErrorAction SilentlyContinue }
"PDF: $pdf"
"$mesNom $($iniMes.Year): $($vMes.Count) ventas por $(Plata $tot) (neto $(Plata $neto)) | vs $mesAntNom $(Plata $totAnt) | queda $(Plata $queda) | comision Cesar $(Plata $comCesar) ($pctTramo%) | por cobrar $(Plata $totCobrar) | docs pendientes $($pendDocs.Count) | compras $($compras.Count) | revisar $($revisar.Count)"
