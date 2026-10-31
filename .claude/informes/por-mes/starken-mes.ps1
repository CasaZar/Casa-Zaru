# "Starken AAAA por mes.xlsx": cada despacho (OF del portal) con su pedido y el envío cobrado; en rojo las OF que no
# calzan con ningún pedido. Al pie de cada mes, las facturas de Starken y su pago por BCI.
# Los exports del portal y el cruce OF→pedido viven en $STARKEN_DIR (privado) y se actualizan a mano.
param([int]$Anio = 0)
. "$PSScriptRoot\engine.ps1"
. "$PSScriptRoot\fuentes.ps1"
$S = $STARKEN_DIR
$out = Join-Path $PL "Starken $Anio por mes.xlsx"
$CTA = @{ '8' = '777978'; '9' = '777979' }
function Vd($x) { V ("$x" -replace ',', '.') }

# ── OF: unión de las lecturas del portal, la más descriptiva manda ──
$of = @{}
if (Test-Path "$S\portal-ano.csv") { foreach ($r in (Import-Csv "$S\portal-ano.csv" -Delimiter ';')) { $of[$r.of] = [pscustomobject]@{ of = $r.of; fecha = (FechaDe ('20' + $r.fecha)); cuenta = $CTA[$r.cta]; monto = (Vd $r.monto); estado = $r.est; destino = $r.ciudad; dest = $r.dest; entrega = '' } } }
if (Test-Path "$S\starken.csv") { foreach ($r in (Import-Csv "$S\starken.csv")) { $of[$r.of] = [pscustomobject]@{ of = $r.of; fecha = (FechaDe $r.emision); cuenta = $r.cuenta; monto = (Vd $r.monto); estado = $r.estado; destino = $r.destino; dest = $r.dest; entrega = $r.entregado } } }
if (Test-Path "$S\informe.csv") { foreach ($r in (Import-Csv "$S\informe.csv" -Delimiter ';')) { $of[$r.of] = [pscustomobject]@{ of = $r.of; fecha = (FechaDe $r.fecha); cuenta = $CTA[$r.cta]; monto = (Vd $r.valor); estado = $r.estado; destino = $r.destino; dest = $r.destinatario; entrega = $r.entrega } } }
$map = @{}; if (Test-Path "$S\map_ano.csv") { foreach ($r in (Import-Csv "$S\map_ano.csv")) { $map[$r.of] = $r } }
$fin = @{}; if (Test-Path "$S\fin_all.csv") { foreach ($r in (Import-Csv "$S\fin_all.csv" -Encoding UTF8)) { $fin[$r.num] = $r } }

$ofs = @($of.Values | Where-Object { $_.fecha -and $_.fecha.Year -eq $Anio } | Sort-Object fecha, of)
$cobradoYa = @{}
$filas = @(foreach ($o in $ofs) {
  $m = $map[$o.of]; $conf = if ($m) { $m.conf } else { 'sin pedido' }
  $nota = if ($m) { $m.nota } else { '' }
  # Gestión parte en mayo de 2026 (#1447): las OF anteriores no pueden tener pedido, y no es un error.
  if ($conf -eq 'sin pedido' -and ($o.fecha -lt [datetime]::new(2026, 5, 1) -or $nota -match '(?i)antes de gesti')) { $conf = 'antes de Gestión'; $nota = '' }
  $num = if ($m -and $m.num) { $m.num } else { '' }
  $fr = if ($num) { $fin[$num] } else { $null }
  $cobrado = 0
  if ($num -and $fr -and -not $cobradoYa[$num] -and $conf -in 'seguro', 'probable') { $cobrado = V $fr.val_envio; $cobradoYa[$num] = $true }
  [pscustomobject]@{ fecha = $o.fecha; of = $o.of; cuenta = $o.cuenta; destino = $o.destino; dest = $o.dest; estado = $o.estado; monto = $o.monto
    num = $num; cliente = $(if ($fr) { $fr.cliente } else { '' }); cobrado = $cobrado; conf = $conf; nota = $nota; sinPedido = ($conf -in 'sin pedido', 'dudoso') }
})

# ── Facturas de Starken: lista privada (Wasabil) + lo que traiga la planilla de gastos con folio nuevo; pagos por BCI ──
$fact = @()
if (Test-Path "$S\facturas-starken.csv") { $fact += @(Import-Csv "$S\facturas-starken.csv" -Delimiter ';' | ForEach-Object { [pscustomobject]@{ fecha = (FechaDe $_.fecha); folio = "$($_.folio)"; neto = (V $_.neto); total = (V $_.total); pago = '' } }) }
foreach ($x in @($FACT | Where-Object { ($_.rut -replace '[\.\-]', '') -like "$STARKEN_RUT*" -and $fact.folio -notcontains $_.folio })) { $fact += [pscustomobject]@{ fecha = $x.fecha; folio = $x.folio; neto = [math]::Round($x.monto / 1.19); total = $x.monto; pago = '' } }
$fact = @($fact | Where-Object { $_.fecha -and $_.fecha.Year -eq $Anio } | Sort-Object fecha)
$pagos = @($BCI | Where-Object { ($_.rut -replace '[\.\-]', '') -like "$STARKEN_RUT*" } | ForEach-Object { [pscustomobject]@{ fecha = $_.fecha.ToString('yyyy-MM-dd'); monto = $_.monto; nota = $_.comentario; usado = $false } })
foreach ($g in ($fact | Group-Object { $_.fecha.ToString('yyyy-MM') })) {
  $tot = 0; foreach ($x in $g.Group) { $tot += $x.total }
  $pg = $pagos | Where-Object { -not $_.usado -and [math]::Abs($_.monto - $tot) -le 20 } | Select-Object -First 1
  if (-not $pg) { $pg = $pagos | Where-Object { -not $_.usado -and ($n = $_.nota) -and @($g.Group.folio | Where-Object { $n -match $_ }).Count } | Select-Object -First 1 }
  if ($pg) { $pg.usado = $true; foreach ($x in $g.Group) { $x.pago = "pagada el $($pg.fecha) por BCI (" + '$' + $pg.monto.ToString('N0', $CL) + " por las " + $g.Count + " facturas del mes)" } }
  else { foreach ($x in $g.Group) { $x.pago = 'PENDIENTE' } }
}
$HastaMes = HastaMesDe (@($filas | ForEach-Object { $_.fecha }) + @($fact | ForEach-Object { $_.fecha }))

# ── Resumen ──
$f = New-Object System.Collections.ArrayList
Titulo $f "Starken $Anio" 'Despachos (OF) del portal de Starken cruzados con los pedidos de Gestión y el envío cobrado al cliente. Facturas desde Wasabil, pagos desde la cartola BCI. Montos con IVA salvo la columna Neto.'
$cols = 'Mes', 'Despachos', 'Costo OF (portal)', 'Facturado', 'Facturado neto', 'Pago', 'Envío cobrado', 'Diferencia', 'OF sin pedido', '$ sin pedido'
[void]$f.Add(@($cols | ForEach-Object { C $_ 1 }))
$ini = $f.Count + 1
for ($m = 1; $m -le $HastaMes; $m++) {
  $fm = @($filas | Where-Object { $_.fecha.Month -eq $m }); $gm = @($fact | Where-Object { $_.fecha.Month -eq $m })
  $costo = 0; $cob = 0; $sp = 0; $nsp = 0; foreach ($x in $fm) { $costo += $x.monto; $cob += $x.cobrado; if ($x.sinPedido) { $sp += $x.monto; $nsp++ } }
  $ft = 0; $fn = 0; foreach ($x in $gm) { $ft += $x.total; $fn += $x.neto }
  $pago = if ($gm.Count -and $gm[0].pago -ne 'PENDIENTE') { ($gm[0].pago -replace '^pagada el (\S+).*', '$1') } elseif ($gm.Count) { 'PENDIENTE' } else { 'sin factura' }
  $r = $f.Count + 1
  [void]$f.Add(@((C $MESES[$m - 1]), (C $fm.Count 7), (C $costo 2), (C $ft 2), (C $fn 2), (C $pago $(if ($pago -eq 'PENDIENTE') { 10 } else { 0 })), (C $cob 2), (F "G$r-C$r" 2), (C $nsp 7), (C $sp 16)))
}
$fin_ = $f.Count
[void]$f.Add(@((C 'Total' 9), (F "SUM(B$($ini):B$fin_)" 9), (F "SUM(C$($ini):C$fin_)" 3), (F "SUM(D$($ini):D$fin_)" 3), (F "SUM(E$($ini):E$fin_)" 3), (C '' 9), (F "SUM(G$($ini):G$fin_)" 3), (F "SUM(H$($ini):H$fin_)" 3), (F "SUM(I$($ini):I$fin_)" 9), (F "SUM(J$($ini):J$fin_)" 3)))
[void]$f.Add(@())
Nota $f 'Diferencia = envío cobrado al cliente − costo de las OF del mes. Negativa = el flete costó más de lo que se cobró.'
Nota $f 'Las OF salen de los exports del portal de Starken; si un mes aparece con pocas, falta bajar el export. Las facturas y pagos sí están completos.'
Nota $f 'El envío cobrado se cuenta una sola vez por pedido (en su primera OF), aunque el pedido haya salido en varios bultos.'
Hoja 'Resumen' $f @(12, 11, 15, 13, 14, 13, 14, 13, 12, 13) 4

# ── una hoja por mes ──
$cab = 'Fecha', 'OF', 'Cuenta', 'Destino', 'Destinatario', 'Estado', 'Costo OF', 'Pedido', 'Cliente', 'Envío cobrado', 'Diferencia', 'Cruce'
for ($m = 1; $m -le $HastaMes; $m++) {
  $fm = @($filas | Where-Object { $_.fecha.Month -eq $m })
  $f = New-Object System.Collections.ArrayList
  Titulo $f "Starken — $($MESES[$m - 1]) $Anio" 'Las filas en rojo son OF que no calzan con ningún pedido de Gestión. Cruce: seguro / probable / muestrario / interno / devolución / sin pedido.'
  [void]$f.Add(@($cab | ForEach-Object { C $_ 1 }))
  $ini = $f.Count + 1
  foreach ($x in $fm) {
    if ($x.sinPedido) { $t = 10; $p = 16 } else { $t = 14; $p = 2 }
    $cruce = $x.conf + $(if ($x.nota) { ' — ' + $x.nota } else { '' })
    $r = $f.Count + 1
    [void]$f.Add(@((C $x.fecha.ToString('dd-MM-yyyy') $t), (C $x.of $t), (C $x.cuenta $t), (C $x.destino $t), (C $x.dest $t), (C $x.estado $t), (C $x.monto $p), (C $x.num $t), (C $x.cliente $t), (C $x.cobrado $p), (F "J$r-G$r" $p), (C $cruce $t)))
  }
  $fin_ = $f.Count
  if ($fin_ -ge $ini) {
    [void]$f.Add(@((C 'Total del mes' 9), (F "COUNTA(B$($ini):B$fin_)" 9), (C '' 9), (C '' 9), (C '' 9), (C '' 9), (F "SUM(G$($ini):G$fin_)" 3), (C '' 9), (C '' 9), (F "SUM(J$($ini):J$fin_)" 3), (F "SUM(K$($ini):K$fin_)" 3), (C '' 9)))
    [void]$f.Add(@((C 'Sin pedido' 10), (F "COUNTIF(L$($ini):L$fin_,""sin pedido*"")+COUNTIF(L$($ini):L$fin_,""dudoso*"")" 10), (C '' 10), (C '' 10), (C '' 10), (C '' 10), (F "SUMIF(L$($ini):L$fin_,""sin pedido*"",G$($ini):G$fin_)+SUMIF(L$($ini):L$fin_,""dudoso*"",G$($ini):G$fin_)" 16), (C '' 10), (C '' 10), (C '' 10), (C '' 10), (C '' 10)))
  } else { Nota $f 'Sin OF del portal para este mes.' }
  [void]$f.Add(@())
  $gm = @($fact | Where-Object { $_.fecha.Month -eq $m })
  [void]$f.Add(@(C 'Facturas de Starken del mes' 15))
  [void]$f.Add(@((C 'Fecha' 1), (C 'Folio' 1), (C 'Neto' 1), (C 'Total' 1), (C 'Pago' 1)))
  foreach ($x in $gm) { $t = if ($x.pago -eq 'PENDIENTE') { 10 } else { 0 }; [void]$f.Add(@((C $x.fecha.ToString('dd-MM-yyyy') $t), (C $x.folio $t), (C $x.neto 2), (C $x.total 2), (C $x.pago $t))) }
  if (-not $gm.Count) { Nota $f 'Sin factura de Starken con fecha de este mes.' }
  Hoja (NombreHoja $m) $f @(11, 12, 9, 14, 24, 16, 12, 8, 26, 13, 12, 34) 4
}
Publicar $out
"OF: $($filas.Count) · sin pedido: $(@($filas | Where-Object sinPedido).Count) · facturas: $($fact.Count) · pendientes: " + (($fact | Where-Object { $_.pago -eq 'PENDIENTE' } | ForEach-Object { $_.folio }) -join ',')
