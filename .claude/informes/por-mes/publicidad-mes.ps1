# "Publicidad AAAA por mes.xlsx": cada cobro de Meta y Google con la cuenta que lo pagó; en rojo los cobros de Meta sin
# factura de compra. Google se paga con la tarjeta de una persona y se le reembolsa por BCI cada dos meses, así que sus
# facturas se comparan por mes y no cobro a cobro.
param([int]$Anio = 0)
. "$PSScriptRoot\engine.ps1"
. "$PSScriptRoot\fuentes.ps1"
$out = Join-Path $PL "Publicidad $Anio por mes.xlsx"
$DESDE = $H1_HASTA.AddDays(1)

$movs = New-Object System.Collections.ArrayList
foreach ($h in ($H1 | Where-Object { $_.cat -in 'Publicidad Meta', 'Publicidad Google' -and $_.estado -eq 'Gasto real' })) {
  $m = Mov $h.fecha $h.cuenta $h.desc $h.detalle $h.monto 'planilla 1er semestre'
  $m | Add-Member canal $(if ($h.cat -match 'Meta') { 'Meta' } else { 'Google' }); [void]$movs.Add($m)
}
foreach ($p in ($MP | Where-Object { $_.fecha -ge $DESDE -and $_.nombre -match '(?i)facebook|meta' })) { $m = Mov $p.fecha 'Tarjeta Mercado Pago' $p.nombre '' $p.monto 'estado de cuenta Mercado Pago'; $m | Add-Member canal 'Meta'; [void]$movs.Add($m) }
foreach ($v in ($VISA | Where-Object { $_.fecha -ge $DESDE })) {
  if ($v.glosa -match '(?i)FACEBK') { $m = Mov $v.fecha 'Visa 8340' 'Facebook' $v.glosa $v.monto 'export Visa'; $m | Add-Member canal 'Meta'; [void]$movs.Add($m) }
  elseif ($v.glosa -match '(?i)GOOGLE ADS') { $m = Mov $v.fecha 'Visa 8340' 'Google Ads' $v.glosa $v.monto 'export Visa'; $m | Add-Member canal 'Google'; [void]$movs.Add($m) }
}
foreach ($b in ($BCI | Where-Object { $_.fecha -ge $DESDE -and $_.nombre -match "(?i)$GOOGLE_PAGADOR" -and $_.comentario -match '(?i)google' })) { $m = Mov $b.fecha "BCI (reembolso a $GOOGLE_PAGADOR_NOMBRE)" $b.nombre $b.comentario $b.monto 'cartola BCI'; $m | Add-Member canal 'Google'; [void]$movs.Add($m) }
$movs = @($movs | Sort-Object fecha)

# Facturas de compra de Meta y Google: la lista bajada de Wasabil ($WASABIL_PUB) más lo que la planilla de gastos traiga con folio nuevo
$wp = @()
if (Test-Path $WASABIL_PUB) { $wp = @(Import-Csv $WASABIL_PUB -Delimiter ';' | ForEach-Object { [pscustomobject]@{ fecha = (FechaDe $_.fecha); proveedor = $(if ($_.canal -eq 'Meta') { 'Meta Platforms (Facebook Ads)' } else { 'Google LLC' }); tipo = 'Factura de compra'; folio = "$($_.folio)"; cat = "Publicidad $($_.canal)"; monto = (V $_.total); usada = $false } } | Where-Object { $_.fecha.Year -eq $Anio }) }
foreach ($x in @($FACT | Where-Object { $_.cat -in 'Publicidad Meta', 'Publicidad Google' -and $wp.folio -notcontains $_.folio })) { $wp += $x }
$factMeta = @($wp | Where-Object { $_.cat -eq 'Publicidad Meta' } | Sort-Object fecha); $factGoogle = @($wp | Where-Object { $_.cat -eq 'Publicidad Google' } | Sort-Object fecha)
CruzarFacturas @($movs | Where-Object { $_.canal -eq 'Meta' }) $factMeta 2 20
foreach ($m in $movs) { if ($m.canal -eq 'Google') { $m.sinFactura = $false; $m.cruce = 'Google: la factura es mensual y el reembolso junta dos meses; ver la tabla de facturas' } }

$mpSinNombre = @($MP | Where-Object { -not $_.nombre -and $_.monto -ge 20000 })
$HastaMes = HastaMesDe (@($movs | ForEach-Object { $_.fecha }) + @($wp | ForEach-Object { $_.fecha }))

$f = New-Object System.Collections.ArrayList
Titulo $f "Publicidad $Anio" 'Meta y Google por mes, según la cuenta que pagó (con IVA) y las facturas de compra que llegaron a Wasabil. En rojo, cobros de Meta sin factura.'
$cols = 'Mes', 'Meta pagado', 'Meta facturado', 'Meta sin factura', 'N° sin factura', 'Google pagado', 'Google facturado', 'Total pagado', 'Tarjeta MP sin nombre'
[void]$f.Add(@($cols | ForEach-Object { C $_ 1 }))
$ini = $f.Count + 1
for ($mes = 1; $mes -le $HastaMes; $mes++) {
  $mm = @($movs | Where-Object { $_.fecha.Month -eq $mes })
  $mp = 0; $gp = 0; $ms = 0; $nms = 0; foreach ($x in $mm) { if ($x.canal -eq 'Meta') { $mp += $x.monto; if ($x.sinFactura) { $ms += $x.monto; $nms++ } } else { $gp += $x.monto } }
  $mf = 0; foreach ($x in @($factMeta | Where-Object { $_.fecha.Month -eq $mes })) { $mf += $x.monto }
  $gf = 0; foreach ($x in @($factGoogle | Where-Object { $_.fecha.Month -eq $mes })) { $gf += $x.monto }
  $sn = 0; foreach ($x in @($mpSinNombre | Where-Object { $_.fecha.Month -eq $mes })) { $sn += $x.monto }
  $r = $f.Count + 1
  [void]$f.Add(@((C $MESES[$mes - 1]), (C $mp 2), (C $mf 2), (C $ms 16), (C $nms 7), (C $gp 2), (C $gf 2), (F "B$r+F$r" 13), (C $sn $(if ($sn) { 16 } else { 2 }))))
}
$fin_ = $f.Count
$tot = @((C 'Total' 9)); for ($i = 1; $i -le 8; $i++) { $tot += (F "SUM($(ColL $i)$($ini):$(ColL $i)$fin_)" $(if ($i -eq 4) { 9 } else { 3 })) }
[void]$f.Add($tot); [void]$f.Add(@())
Nota $f 'Meta factura cada cobro, así que «Meta facturado» es la mejor cifra del gasto pagado. «Meta pagado» sale más bajo cuando a la tarjeta de Mercado Pago le faltan el estado de cuenta del mes o los nombres de comercio de las capturas (columna «Tarjeta MP sin nombre»).'
Nota $f 'Google se paga con tarjeta personal y se reembolsa por BCI cada dos meses (desde el 19-10-2026 cobra a la Visa 8340). Lo facturado por Google llega por mes a Wasabil.'
Hoja 'Resumen' $f @(12, 13, 13, 13, 10, 13, 13, 13, 14) 4

$cab = 'Fecha', 'Canal', 'Cuenta', 'Comercio / quién', 'Glosa', 'Monto', 'Factura', 'Observación'
for ($mes = 1; $mes -le $HastaMes; $mes++) {
  $mm = @($movs | Where-Object { $_.fecha.Month -eq $mes })
  $f = New-Object System.Collections.ArrayList
  Titulo $f "Publicidad — $($MESES[$mes - 1]) $Anio" 'En rojo, cobros de Meta sin factura de compra que calce (mismo monto, ±20 días). Google no se marca: su factura es mensual.'
  [void]$f.Add(@($cab | ForEach-Object { C $_ 1 }))
  $ini = $f.Count + 1
  foreach ($x in $mm) {
    if ($x.sinFactura) { $t = 10; $p = 16; $fac = 'SIN FACTURA' } else { $t = 14; $p = 2; $fac = $x.factura }
    [void]$f.Add(@((C $x.fecha.ToString('dd-MM-yyyy') $t), (C $x.canal $t), (C $x.cuenta $t), (C $x.quien $t), (C $x.glosa $t), (C $x.monto $p), (C $fac $t), (C $x.cruce $t)))
  }
  $fin_ = $f.Count
  if ($fin_ -ge $ini) {
    [void]$f.Add(@((C 'Total del mes' 9), (F "COUNTA(A$($ini):A$fin_)" 9), (C '' 9), (C '' 9), (C '' 9), (F "SUM(F$($ini):F$fin_)" 3), (C '' 9), (C '' 9)))
    [void]$f.Add(@((C 'Meta' 11), (C '' 11), (C '' 11), (C '' 11), (C '' 11), (F "SUMIF(B$($ini):B$fin_,""Meta"",F$($ini):F$fin_)" 13), (C '' 11), (C '' 11)))
    [void]$f.Add(@((C 'Google' 11), (C '' 11), (C '' 11), (C '' 11), (C '' 11), (F "SUMIF(B$($ini):B$fin_,""Google"",F$($ini):F$fin_)" 13), (C '' 11), (C '' 11)))
    [void]$f.Add(@((C 'Sin factura' 10), (F "COUNTIF(G$($ini):G$fin_,""SIN FACTURA"")" 10), (C '' 10), (C '' 10), (C '' 10), (F "SUMIF(G$($ini):G$fin_,""SIN FACTURA"",F$($ini):F$fin_)" 16), (C '' 10), (C '' 10)))
  } else { Nota $f 'Sin cobros identificados este mes.' }
  $fm = @(($factMeta + $factGoogle) | Where-Object { $_.fecha.Month -eq $mes } | Sort-Object fecha)
  if ($fm.Count) {
    [void]$f.Add(@()); [void]$f.Add(@(C 'Facturas de compra del mes (Wasabil)' 15))
    [void]$f.Add(@((C 'Fecha' 1), (C 'Proveedor' 1), (C 'Folio' 1), (C 'Monto' 1), (C 'Cruzada con un cobro' 1)))
    foreach ($x in $fm) { $g = $x.cat -match 'Google'; $t = if ($x.usada -or $g) { 0 } else { 10 }; [void]$f.Add(@((C $x.fecha.ToString('dd-MM-yyyy') $t), (C $x.proveedor $t), (C "$($x.tipo) $($x.folio)" $t), (C $x.monto 2), (C $(if ($g) { 'Google: factura mensual' } elseif ($x.usada) { 'sí' } else { 'NO: no hay cobro de tarjeta identificado que calce' }) $t))) }
  }
  $sn = @($mpSinNombre | Where-Object { $_.fecha.Month -eq $mes })
  if ($sn.Count) { $s = 0; foreach ($x in $sn) { $s += $x.monto }; [void]$f.Add(@()); Nota $f ("Tarjeta de Mercado Pago: $($sn.Count) pagos de `$20.000 o más sin nombre de comercio, " + '$' + $s.ToString('N0', $CL) + ' en total. Parte puede ser Meta: faltan las capturas de la actividad para saberlo.') }
  Hoja (NombreHoja $mes) $f @(11, 8, 24, 20, 30, 12, 20, 60) 4
}
Publicar $out
"cobros: $($movs.Count) · Meta sin factura: $(@($movs | Where-Object { $_.canal -eq 'Meta' -and $_.sinFactura }).Count) · facturas Meta $($factMeta.Count) (sin cruzar $(@($factMeta | Where-Object { -not $_.usada }).Count)) · Google $($factGoogle.Count)"
