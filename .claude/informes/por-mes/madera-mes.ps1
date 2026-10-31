# "Compras madera AAAA por mes.xlsx": Resumen + una hoja por mes a partir del cruce compra a compra ($MADERA_CRUCE).
# Las compras sin factura van marcadas (texto rojo sobre crema) y con subtotal propio por fórmula.
param([int]$Anio = 0)
. "$PSScriptRoot\engine.ps1"
. "$PSScriptRoot\fuentes.ps1"
if (-not (Test-Path $MADERA_CRUCE)) { throw "No está el cruce de madera: $MADERA_CRUCE" }
$out = Join-Path $PL "Compras madera $Anio por mes.xlsx"

$filas = @(Import-Csv $MADERA_CRUCE -Delimiter ';' -Encoding UTF8 | ForEach-Object {
  [pscustomobject]@{ fecha = (FechaDe $_.Fecha); grupo = $_.Grupo; prov = $_.Proveedor; factura = $_.Factura; total = (V $_.Total); neto = (V $_.Neto); pagado = (V $_.Pagado)
    pagos = $_.Pagos; planilla = $_.Planilla; chat = $_.Chat; sinFactura = ($_.Factura -match 'sin factura') }
} | Where-Object { $_.fecha -and $_.fecha.Year -eq $Anio } | Sort-Object fecha)
$HastaMes = HastaMesDe ($filas | ForEach-Object { $_.fecha })
# Los grupos (proveedores) salen del propio cruce, del más grande al más chico
$grupos = @($filas | Group-Object grupo | ForEach-Object { $s = 0; foreach ($x in $_.Group) { $s += $x.total }; [pscustomobject]@{ g = $_.Name; s = $s } } | Sort-Object s -Descending | ForEach-Object { $_.g })

$f = New-Object System.Collections.ArrayList
Titulo $f "Compras de madera $Anio" 'Con IVA. Una hoja por mes; las compras sin factura van marcadas en rojo. Fuentes: cartolas BCI y Banco de Chile, facturas de Wasabil, planillas y el chat de gastos del taller.'
$cols = @('Mes') + $grupos + @('Total', 'Sin factura', 'N° compras', 'N° sin factura')
[void]$f.Add(@($cols | ForEach-Object { C $_ 1 }))
$ini = $f.Count + 1; $nG = $grupos.Count
for ($m = 1; $m -le $HastaMes; $m++) {
  $g = @($filas | Where-Object { $_.fecha.Month -eq $m })
  $fila = New-Object System.Collections.ArrayList; [void]$fila.Add((C $MESES[$m - 1]))
  foreach ($gr in $grupos) { $s = 0; foreach ($x in @($g | Where-Object { $_.grupo -eq $gr })) { $s += $x.total }; [void]$fila.Add((C $s 2)) }
  $r = $f.Count + 1
  [void]$fila.Add((F "SUM(B$($r):$(ColL $nG)$r)" 13))
  $sf = 0; $nsf = 0; foreach ($x in @($g | Where-Object { $_.sinFactura })) { $sf += $x.total; $nsf++ }
  [void]$fila.Add((C $sf 16)); [void]$fila.Add((C $g.Count 7)); [void]$fila.Add((C $nsf 7))
  [void]$f.Add($fila.ToArray())
}
$fin = $f.Count
$tot = @((C 'Total' 9)); for ($i = 1; $i -le $nG + 4; $i++) { $tot += (F "SUM($(ColL $i)$($ini):$(ColL $i)$fin)" $(if ($i -ge $nG + 3) { 9 } else { 3 })) }
[void]$f.Add($tot); [void]$f.Add(@())
Nota $f 'Los proveedores que facturan van por fecha de factura; los que no facturan, por fecha de pago.'
Nota $f '«Sin factura» = pago sin documento tributario (proveedores particulares o pagos hechos a través de alguien del equipo).'
Hoja 'Resumen' $f (@(12) + @($grupos | ForEach-Object { 14 }) + @(13, 13, 10, 12)) 4

$cabMes = 'Fecha', 'Proveedor', 'Factura', 'Total c/IVA', 'Neto', 'Pagado', 'Pago', 'Planilla', 'Chat del taller'
for ($m = 1; $m -le $HastaMes; $m++) {
  $g = @($filas | Where-Object { $_.fecha.Month -eq $m })
  $f = New-Object System.Collections.ArrayList
  Titulo $f "$($MESES[$m - 1]) $Anio" 'Las filas en rojo no tienen factura. «Planilla» vacía = la compra no está en ninguna planilla.'
  [void]$f.Add(@($cabMes | ForEach-Object { C $_ 1 }))
  $ini = $f.Count + 1
  foreach ($x in $g) {
    if ($x.sinFactura) { $t = 10; $p = 16; $fac = 'SIN FACTURA' } else { $t = 14; $p = 2; $fac = $x.factura }
    $neto = if ($x.neto -gt 0) { C $x.neto $p } else { C '' $t }
    [void]$f.Add(@((C $x.fecha.ToString('dd-MM-yyyy') $t), (C $x.prov $t), (C $fac $t), (C $x.total $p), $neto, (C $x.pagado $p), (C $x.pagos $t), (C $(if ($x.planilla) { $x.planilla } else { '—' }) $t), (C $x.chat $t)))
  }
  $fin = $f.Count
  if ($fin -ge $ini) {
    [void]$f.Add(@((C 'Total del mes' 9), (C '' 9), (F "COUNTA(A$($ini):A$fin)" 9), (F "SUM(D$($ini):D$fin)" 3), (F "SUM(E$($ini):E$fin)" 3), (F "SUM(F$($ini):F$fin)" 3), (C '' 9), (C '' 9), (C '' 9)))
    [void]$f.Add(@((C 'Sin factura' 10), (C '' 10), (F "COUNTIF(C$($ini):C$fin,""SIN FACTURA"")" 10), (F "SUMIF(C$($ini):C$fin,""SIN FACTURA"",D$($ini):D$fin)" 16), (C '' 10), (F "SUMIF(C$($ini):C$fin,""SIN FACTURA"",F$($ini):F$fin)" 16), (C '' 10), (C '' 10), (C '' 10)))
  } else { Nota $f 'Sin compras registradas este mes (o el cruce todavía no llega hasta acá).' }
  Hoja (NombreHoja $m) $f @(11, 26, 12, 13, 13, 13, 40, 30, 50) 4
}
Publicar $out
"Compras: $($filas.Count) · sin factura: $(@($filas | Where-Object { $_.sinFactura }).Count) · hasta $($MESES[$HastaMes - 1])"
