# "Bencina AAAA por mes.xlsx": cada carga de combustible con la cuenta que la pagó; en rojo las que no tienen factura
# (sin factura, el IVA de la bencina no se recupera).
param([int]$Anio = 0)
. "$PSScriptRoot\engine.ps1"
. "$PSScriptRoot\fuentes.ps1"
$out = Join-Path $PL "Bencina $Anio por mes.xlsx"
$EST = '(?i)copec|aramco|shell|petrobras|enex|estacion serv|turno libre|distribuidora de'
$DESDE = $H1_HASTA.AddDays(1)   # lo que no cubre la planilla del semestre se lee de cartolas y tarjetas

$movs = New-Object System.Collections.ArrayList
foreach ($h in ($H1 | Where-Object { $_.cat -eq 'Combustible (bencina)' -and $_.estado -eq 'Gasto real' })) {
  $m = Mov $h.fecha $h.cuenta $h.desc $h.detalle $h.monto 'planilla 1er semestre'
  $m.cruce = $(if ($h.nota) { $h.nota } else { $h.sub }); [void]$movs.Add($m)
}
foreach ($b in ($BDC | Where-Object { $_.fecha -ge $DESDE -and $_.glosa -match $EST })) { [void]$movs.Add((Mov $b.fecha 'Banco de Chile (tarjeta taller)' $b.glosa '' $b.monto 'cartola Banco de Chile')) }
foreach ($b in ($BCI | Where-Object { $_.fecha -ge $DESDE -and $_.comentario -match '(?i)bencina|petr.?leo|combustible' })) { $m = Mov $b.fecha 'BCI (rendición)' $b.nombre $b.comentario $b.monto 'cartola BCI'; $m.cruce = 'rendición: puede mezclar bencina con otras cosas'; [void]$movs.Add($m) }
foreach ($p in ($MP | Where-Object { $_.fecha -ge $DESDE -and $_.nombre -match $EST })) { [void]$movs.Add((Mov $p.fecha 'Tarjeta Mercado Pago' $p.nombre '' $p.monto 'estado de cuenta Mercado Pago')) }
foreach ($v in ($VISA | Where-Object { $_.fecha -ge $DESDE -and $_.glosa -match $EST })) { [void]$movs.Add((Mov $v.fecha 'Visa 8340' $v.glosa '' $v.monto 'export Visa')) }
foreach ($m in $movs) { if ($m.quien -match '(?i)distribuidora de') { $m.cruce = 'Distribuidora De: el 1er semestre la contó como bencina; desde octubre el libro la manda a Otros gastos' } }
$movs = @($movs | Sort-Object fecha)
$fact = @($FACT | Where-Object { $_.cat -match '(?i)bencina|combustible' })
CruzarFacturas $movs $fact 2 10
$HastaMes = HastaMesDe ($movs | ForEach-Object { $_.fecha })

$f = New-Object System.Collections.ArrayList
Titulo $f "Bencina $Anio" 'Cargas de combustible por mes y por cuenta. Primer semestre desde su planilla clasificada; después, desde las cartolas de Banco de Chile y BCI, la tarjeta de Mercado Pago y la Visa. En rojo, cargas sin factura.'
$cols = 'Mes', 'Cargas', 'Total', 'Tarjeta Banco de Chile', 'Tarjeta Mercado Pago', 'Rendiciones BCI', 'Visa', 'Con factura', 'Sin factura', 'N° sin factura', 'IVA no recuperado (aprox.)'
[void]$f.Add(@($cols | ForEach-Object { C $_ 1 }))
$ini = $f.Count + 1
for ($mes = 1; $mes -le $HastaMes; $mes++) {
  $mm = @($movs | Where-Object { $_.fecha.Month -eq $mes })
  $t = 0; $bdc = 0; $mp = 0; $bci = 0; $vi = 0; $con = 0; $sin = 0; $nsin = 0
  foreach ($x in $mm) { $t += $x.monto; if ($x.cuenta -match 'Banco de Chile') { $bdc += $x.monto } elseif ($x.cuenta -match 'Mercado Pago') { $mp += $x.monto } elseif ($x.cuenta -match 'BCI') { $bci += $x.monto } else { $vi += $x.monto }; if ($x.sinFactura) { $sin += $x.monto; $nsin++ } else { $con += $x.monto } }
  $r = $f.Count + 1
  [void]$f.Add(@((C $MESES[$mes - 1]), (C $mm.Count 7), (C $t 13), (C $bdc 2), (C $mp 2), (C $bci 2), (C $vi 2), (C $con 2), (C $sin 16), (C $nsin 7), (F "ROUND(I$r/1.19*0.19,0)" 2)))
}
$fin_ = $f.Count
$tot = @((C 'Total' 9)); for ($i = 1; $i -le 10; $i++) { $tot += (F "SUM($(ColL $i)$($ini):$(ColL $i)$fin_)" $(if ($i -in 1, 9) { 9 } else { 3 })) }
[void]$f.Add($tot); [void]$f.Add(@())
Nota $f 'Los meses sin estado de cuenta de Mercado Pago cargado (~/.casazaru/mp-AAAA-MM.csv) no muestran lo pagado con esa tarjeta.'
Nota $f 'Las rendiciones por BCI son transferencias a gente del equipo cuya glosa dice bencina; pueden mezclar bencina con otras compras.'
Nota $f 'IVA no recuperado = lo pagado sin factura ÷ 1,19 × 0,19. Es lo que se deja de descontar en el F29 por cargar con boleta en vez de factura.'
Hoja 'Resumen' $f @(12, 8, 13, 15, 15, 14, 11, 13, 13, 10, 15) 4

$cab = 'Fecha', 'Cuenta', 'Comercio / quién', 'Glosa', 'Monto', 'Factura', 'Observación'
for ($mes = 1; $mes -le $HastaMes; $mes++) {
  $mm = @($movs | Where-Object { $_.fecha.Month -eq $mes })
  $f = New-Object System.Collections.ArrayList
  Titulo $f "Bencina — $($MESES[$mes - 1]) $Anio" 'Las filas en rojo no tienen factura de compra que calce (mismo monto, ±10 días).'
  [void]$f.Add(@($cab | ForEach-Object { C $_ 1 }))
  $ini = $f.Count + 1
  foreach ($x in $mm) {
    if ($x.sinFactura) { $t = 10; $p = 16; $fac = 'SIN FACTURA' } else { $t = 14; $p = 2; $fac = $x.factura }
    [void]$f.Add(@((C $x.fecha.ToString('dd-MM-yyyy') $t), (C $x.cuenta $t), (C $x.quien $t), (C $x.glosa $t), (C $x.monto $p), (C $fac $t), (C $x.cruce $t)))
  }
  $fin_ = $f.Count
  if ($fin_ -ge $ini) {
    [void]$f.Add(@((C 'Total del mes' 9), (F "COUNTA(A$($ini):A$fin_)" 9), (C '' 9), (C '' 9), (F "SUM(E$($ini):E$fin_)" 3), (C '' 9), (C '' 9)))
    [void]$f.Add(@((C 'Sin factura' 10), (F "COUNTIF(F$($ini):F$fin_,""SIN FACTURA"")" 10), (C '' 10), (C '' 10), (F "SUMIF(F$($ini):F$fin_,""SIN FACTURA"",E$($ini):E$fin_)" 16), (C '' 10), (C '' 10)))
  } else { Nota $f 'Sin cargas registradas este mes.' }
  $fm = @($fact | Where-Object { $_.fecha.Month -eq $mes })
  if ($fm.Count) {
    [void]$f.Add(@()); [void]$f.Add(@(C 'Facturas de combustible del mes (planilla Wasabil)' 15))
    [void]$f.Add(@((C 'Fecha' 1), (C 'Proveedor' 1), (C 'Folio' 1), (C 'Monto' 1), (C 'Cruzada con un pago' 1)))
    foreach ($x in $fm) { $t = if ($x.usada) { 0 } else { 10 }; [void]$f.Add(@((C $x.fecha.ToString('dd-MM-yyyy') $t), (C $x.proveedor $t), (C "$($x.tipo) $($x.folio)" $t), (C $x.monto 2), (C $(if ($x.usada) { 'sí' } else { 'NO: no hay cargo de tarjeta ni rendición que calce' }) $t))) }
  }
  Hoja (NombreHoja $mes) $f @(11, 26, 24, 34, 12, 16, 60) 4
}
Publicar $out
"cargas: $($movs.Count) · sin factura: $(@($movs | Where-Object sinFactura).Count) · facturas: $($fact.Count) (sin cruzar: $(@($fact | Where-Object { -not $_.usada }).Count))"
