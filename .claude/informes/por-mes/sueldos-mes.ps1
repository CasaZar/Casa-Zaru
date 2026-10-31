# "Sueldos AAAA por mes.xlsx": lo pagado por BCI al equipo ($EQUIPO, privado) y a Previred, mes a mes.
# En rojo los pagos a gente del equipo cuya glosa NO dice sueldo (hay que decidir si es sueldo o gasto).
# Los pagos al equipo que claramente son otra cosa (madera, bencina, cuotas, Google…) van en "Otros pagos al equipo".
param([int]$Anio = 0)
. "$PSScriptRoot\engine.ps1"
. "$PSScriptRoot\fuentes.ps1"
$out = Join-Path $PL "Sueldos $Anio por mes.xlsx"
# La cartola pierde las tildes ("Das trabajados", "Prstamo"): los patrones aceptan la letra faltante.
$SUELDO = '(?i)sueldo|suelos|quincena|quncena|aguinaldo|horas|hrs|finiquito|anticipo|adelanto|bono|d.?as|mes anterior|comisi|faltante|restante|^(enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre)\b'
$OTRO = '(?i)madera|casta|laurel|fierro|bencina|google|canva|capcut|cuota|esperan|garantia|scotiabank|deuda|pr.?stamo|devoluci|traspaso|gastos|compra|cencosud|ensambl|env.o|envos|flete|peaje|petr|vitrific|insumo|corchetera|chilenidad|mdf|arreglos|inscripci|tarjeta'

$pagos = New-Object System.Collections.ArrayList; $otros = New-Object System.Collections.ArrayList
foreach ($r in $BCI) {
  if ($r.nombre -match '(?i)previred' -or $r.glosa -match '(?i)previred') {
    [void]$pagos.Add([pscustomobject]@{ fecha = $r.fecha; quien = 'Previred (imposiciones)'; monto = $r.monto; glosa = $r.comentario; tipo = 'Imposiciones'; revisar = $false }); continue
  }
  if (-not $EQUIPO.Contains($r.rut)) { continue }
  $q = $EQUIPO[$r.rut]; $c = "$($r.comentario)".Trim()
  if ($c -match $SUELDO) { [void]$pagos.Add([pscustomobject]@{ fecha = $r.fecha; quien = $q; monto = $r.monto; glosa = $c; tipo = 'Sueldo'; revisar = $false }) }
  elseif ($c -match $OTRO) { [void]$otros.Add([pscustomobject]@{ fecha = $r.fecha; quien = $q; monto = $r.monto; glosa = $c }) }
  else { [void]$pagos.Add([pscustomobject]@{ fecha = $r.fecha; quien = $q; monto = $r.monto; glosa = $(if ($c) { $c } else { '(sin mensaje)' }); tipo = 'SIN GLOSA DE SUELDO'; revisar = $true }) }
}
$pagos = @($pagos | Sort-Object fecha, quien)
$personas = @($EQUIPO.Values)
$HastaMes = HastaMesDe ($pagos | ForEach-Object { $_.fecha })

$f = New-Object System.Collections.ArrayList
Titulo $f "Sueldos $Anio" 'CONFIDENCIAL: sueldos por persona. Lo pagado por BCI cada mes (los sueldos se pagan a mes vencido: lo de enero es el sueldo de diciembre). En rojo, pagos al equipo sin glosa de sueldo.'
$cols = @('Mes') + $personas + @('Previred', 'Total', 'Sin glosa', 'N° sin glosa')
[void]$f.Add(@($cols | ForEach-Object { C $_ 1 }))
$ini = $f.Count + 1; $nP = $personas.Count
for ($m = 1; $m -le $HastaMes; $m++) {
  $pm = @($pagos | Where-Object { $_.fecha.Month -eq $m })
  $fila = New-Object System.Collections.ArrayList; [void]$fila.Add((C $MESES[$m - 1]))
  foreach ($p in $personas) { $s = 0; foreach ($x in @($pm | Where-Object { $_.quien -eq $p })) { $s += $x.monto }; [void]$fila.Add((C $s 2)) }
  $prev = 0; foreach ($x in @($pm | Where-Object { $_.tipo -eq 'Imposiciones' })) { $prev += $x.monto }
  $sg = 0; $nsg = 0; foreach ($x in @($pm | Where-Object revisar)) { $sg += $x.monto; $nsg++ }
  $r = $f.Count + 1
  [void]$fila.Add((C $prev 2)); [void]$fila.Add((F "SUM(B$($r):$(ColL ($nP + 1))$r)" 13)); [void]$fila.Add((C $sg 16)); [void]$fila.Add((C $nsg 7))
  [void]$f.Add($fila.ToArray())
}
$fin_ = $f.Count
$tot = @((C 'Total' 9)); for ($i = 1; $i -le $nP + 4; $i++) { $tot += (F "SUM($(ColL $i)$($ini):$(ColL $i)$fin_)" $(if ($i -eq $nP + 4) { 9 } else { 3 })) }
[void]$f.Add($tot); [void]$f.Add(@())
Nota $f $SUELDOS_NOTA
Hoja 'Resumen' $f (@(12) + @($personas | ForEach-Object { 13 }) + @(13, 14, 13, 10)) 4

$cab = 'Fecha', 'Quién', 'Monto', 'Glosa de la transferencia', 'Tipo'
for ($m = 1; $m -le $HastaMes; $m++) {
  $pm = @($pagos | Where-Object { $_.fecha.Month -eq $m })
  $f = New-Object System.Collections.ArrayList
  Titulo $f "Sueldos — $($MESES[$m - 1]) $Anio" 'Pagos por BCI a gente del equipo y a Previred. Las filas en rojo tienen una glosa que no dice sueldo: decidir si es sueldo o gasto.'
  [void]$f.Add(@($cab | ForEach-Object { C $_ 1 }))
  $ini = $f.Count + 1
  foreach ($x in $pm) {
    if ($x.revisar) { $t = 10; $p = 16 } else { $t = 14; $p = 2 }
    [void]$f.Add(@((C $x.fecha.ToString('dd-MM-yyyy') $t), (C $x.quien $t), (C $x.monto $p), (C $x.glosa $t), (C $x.tipo $t)))
  }
  $fin_ = $f.Count
  if ($fin_ -ge $ini) {
    [void]$f.Add(@((C 'Total del mes' 9), (F "COUNTA(B$($ini):B$fin_)" 9), (F "SUM(C$($ini):C$fin_)" 3), (C '' 9), (C '' 9)))
    [void]$f.Add(@((C 'Sin glosa de sueldo' 10), (F "COUNTIF(E$($ini):E$fin_,""SIN GLOSA*"")" 10), (F "SUMIF(E$($ini):E$fin_,""SIN GLOSA*"",C$($ini):C$fin_)" 16), (C '' 10), (C '' 10)))
    [void]$f.Add(@()); [void]$f.Add(@(C 'Por persona' 15)); [void]$f.Add(@((C 'Quién' 1), (C 'Pagos' 1), (C 'Total' 1)))
    foreach ($p in @($personas) + @('Previred (imposiciones)')) {
      if (-not @($pm | Where-Object { $_.quien -eq $p }).Count) { continue }
      $r = $f.Count + 1
      [void]$f.Add(@((C $p), (F "COUNTIF(B$($ini):B$fin_,A$r)" 7), (F "SUMIF(B$($ini):B$fin_,A$r,C$($ini):C$fin_)" 2)))
    }
  } else { Nota $f 'Sin pagos este mes (o la cartola todavía no llega hasta acá).' }
  Hoja (NombreHoja $m) $f @(12, 24, 13, 48, 22) 4
}

$f = New-Object System.Collections.ArrayList
Titulo $f "Otros pagos al equipo $Anio" 'Transferencias a gente del equipo cuya glosa dice otra cosa (madera, bencina, cuotas de crédito, Google, Canva…). No son sueldo; se listan para que no se pierdan.'
[void]$f.Add(@((C 'Fecha' 1), (C 'Quién' 1), (C 'Monto' 1), (C 'Glosa' 1)))
$ini = $f.Count + 1
foreach ($x in @($otros | Sort-Object fecha)) { [void]$f.Add(@((C $x.fecha.ToString('dd-MM-yyyy') 14), (C $x.quien 14), (C $x.monto 2), (C $x.glosa 14))) }
$fin_ = $f.Count
[void]$f.Add(@((C 'Total' 9), (F "COUNTA(B$($ini):B$fin_)" 9), (F "SUM(C$($ini):C$fin_)" 3), (C '' 9)))
Hoja 'Otros pagos al equipo' $f @(12, 24, 13, 48) 4

Publicar $out
"pagos: $($pagos.Count) · sin glosa: $(@($pagos | Where-Object revisar).Count) · otros: $($otros.Count)"
