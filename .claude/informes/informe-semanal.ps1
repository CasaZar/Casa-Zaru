# Informe semanal de Gestión (PDF) — Casa Zaru
#
# Lee el último respaldo diario de Gestión (Drive, 03:00), calcula ventas,
# cobranza, documentos, producción y avisos, arma un HTML y lo imprime a PDF
# con Edge. Todo número sale de acá, nunca escrito a mano.
#
# El repo es PÚBLICO: este script no lleva datos de clientes. Los datos solo
# viven en el respaldo y en el PDF, que queda en Drive.
#
# Uso:  .\informe-semanal.ps1                 (semana pasada, lunes a domingo)
#       .\informe-semanal.ps1 -Lunes 2026-09-28   (informe como si hoy fuera ese lunes)
param(
  [string]$Lunes,
  [string]$Salida = 'G:\Mi unidad\Casa Zaru\Informes Gestion'
)
$ErrorActionPreference = 'Stop'
$cl = [Globalization.CultureInfo]'es-CL'
$MESES = @('ENERO','FEBRERO','MARZO','ABRIL','MAYO','JUNIO','JULIO','AGOSTO','SEPTIEMBRE','OCTUBRE','NOVIEMBRE','DICIEMBRE')
$CAPACIDAD_M2 = 15
$TRAMOS = @(@(0, 0.02), @(15000000, 0.025), @(25000000, 0.035))   # comisión César sobre val_prod del mes

# ── Fechas ────────────────────────────────────────────────────────────────
$hoy = if ($Lunes) { [datetime]::ParseExact($Lunes, 'yyyy-MM-dd', $null) } else { (Get-Date).Date }
$dow = [int]$hoy.DayOfWeek; $lunesActual = $hoy.AddDays(-(($dow + 6) % 7))
$ini = $lunesActual.AddDays(-7); $fin = $lunesActual.AddDays(-1)           # semana informada
$iniAnt = $ini.AddDays(-7); $finAnt = $ini.AddDays(-1)
$iniMes = (Get-Date -Year $fin.Year -Month $fin.Month -Day 1).Date   # .Date: sin la hora, o se pierden las ventas del día 1
$iniMesAnt = $iniMes.AddMonths(-1); $finMesAnt = $iniMesAnt.AddDays($fin.Day - 1)
if ($finMesAnt.Month -ne $iniMesAnt.Month) { $finMesAnt = $iniMes.AddDays(-1) }

# ── Datos ─────────────────────────────────────────────────────────────────
$dirResp = 'G:\Mi unidad\Casa Zaru\Boletas y Facturas - Ventas 2026\Respaldos Gestion'
$resp = Get-ChildItem $dirResp -Filter 'respaldo-gestion-*.json' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $resp) { throw "No hay respaldos en $dirResp" }
$j = [IO.File]::ReadAllText($resp.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json
$prod = @{}; @($j.tablas.gestion_produccion) | ForEach-Object { $prod[$_.num] = $_.data }
$seg = @{};  @($j.tablas.gestion_pedidos)    | ForEach-Object { $seg[$_.num] = $_.data }

function N($x) { if ($x -eq $null -or "$x" -eq '') { 0 } else { [double]("$x" -replace '[^\d\.-]', '') } }
function Fecha($s) {
  if (-not $s) { return $null }
  $p = "$s".Split('/'); if ($p.Count -ne 3) { return $null }
  try { return Get-Date -Year ([int]$p[2]) -Month ([int]$p[1]) -Day ([int]$p[0]) -Hour 0 -Minute 0 -Second 0 } catch { return $null }
}
function SemanaAFecha($sem) {   # "SEMANA 14 SEPTIEMBRE" -> lunes de fabricación
  if ("$sem" -match '(\d{1,2})\s+([A-Z]+)') {
    $m = [array]::IndexOf($MESES, $matches[2].ToUpper()) + 1
    if ($m -gt 0) { return (Get-Date -Year $fin.Year -Month $m -Day ([int]$matches[1])).Date }
  }
  return $null
}
function Envio($o) {            # día de despacho: el cargado, o el lunes siguiente a la semana
  if ($o.dia_envio) { return [datetime]::ParseExact($o.dia_envio, 'yyyy-MM-dd', $null) }
  $s = SemanaAFecha $o.envio; if ($s) { return $s.AddDays(7) }; return $null
}
function Plata($v) { '$' + ([double]$v).ToString('N0', $cl) }
function E($s) { [Net.WebUtility]::HtmlEncode("$s") }
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

$fin_ = @($j.tablas.gestion_finanzas) | ForEach-Object {
  $d = $_.data; $f = Fecha ($(if ($d.fecha_creacion) { $d.fecha_creacion } else { $d.fecha }))
  $tipo = if ("$($d.tipo)") { "$($d.tipo)" } else { 'VENTA' }
  $a = (N $d.abono1) + (N $d.abono2) + (N $d.abono3); $tot = N $d.total
  $p = $prod[$_.num]
  [pscustomobject]@{
    num = $_.num; cliente = ("$($d.nombre) $($d.apellido)").Trim(); fecha = $f; tipo = $tipo
    total = $tot; vp = (N $d.val_prod); abonado = $a; saldo = $tot - $a
    vendedor = $(if ("$($d.vendedor)") { "$($d.vendedor)" } else { '(sin asignar)' })
    como = $(if ("$($d.como)") { "$($d.como)" } else { '(sin dato)' })
    pago = $(if ("$($d.canal_pago)") { "$($d.canal_pago)" } else { "$($d.medio_pago)" })
    producto = $d.producto; web = ("$($d.canal_pago)" -match 'SHOPIFY')
    d1 = [bool]$d.doc1_emitida; d2 = [bool]$d.doc2_emitida; a1 = (N $d.abono1); a23 = (N $d.abono2) + (N $d.abono3)
    tipoDoc = $d.doc1_tipo; envio = $(if ($p) { Envio $p } else { $null }); semana = $(if ($p) { $p.envio } else { $d.semana })
  }
}
$ventas = @($fin_ | Where-Object { $_.tipo -eq 'VENTA' -and $_.fecha })
function EnRango($lista, $a, $b) { @($lista | Where-Object { $_.fecha -ge $a -and $_.fecha -le $b }) }
function Suma($lista, $campo) { $s = ($lista | Measure-Object $campo -Sum).Sum; if ($s) { $s } else { 0 } }

$vSem = EnRango $ventas $ini $fin;       $vAnt = EnRango $ventas $iniAnt $finAnt
$vMes = EnRango $ventas $iniMes $fin;    $vMesAnt = EnRango $ventas $iniMesAnt $finMesAnt

# Últimas 8 semanas para el gráfico
$serie = for ($k = 7; $k -ge 0; $k--) {
  $a = $ini.AddDays(-7 * $k); $b = $a.AddDays(6); $l = EnRango $ventas $a $b
  [pscustomobject]@{ desde = $a; monto = (Suma $l 'total'); n = $l.Count }
}

# Comisión César (base val_prod del mes)
$vpCesar = Suma @($vMes | Where-Object { $_.vendedor -match 'sar' }) 'vp'
$tramo = $TRAMOS[0]; foreach ($t in $TRAMOS) { if ($vpCesar -ge $t[0]) { $tramo = $t } }
$sig = $TRAMOS | Where-Object { $_[0] -gt $vpCesar } | Select-Object -First 1

# Cobranza y documentos
$cobrar = @($fin_ | Where-Object { $_.tipo -eq 'VENTA' -and $_.saldo -gt 1000 -and -not $_.web } | Sort-Object { if ($_.envio) { $_.envio } else { [datetime]::MaxValue } })
$docs = @()
foreach ($r in ($fin_ | Where-Object { $_.tipo -eq 'VENTA' -and -not $_.web })) {
  if ($r.a1 -gt 0 -and -not $r.d1) { $docs += [pscustomobject]@{ num=$r.num; cliente=$r.cliente; doc='Doc 1'; tipo=$r.tipoDoc; monto=$r.a1 } }
  # El doc 2 cubre todo lo pagado después del abono 1: si todavía debe, se emite al completar.
  if ($r.a23 -gt 0 -and -not $r.d2) { $docs += [pscustomobject]@{ num=$r.num; cliente=$r.cliente; doc=$(if ($r.saldo -gt 1000) { 'Doc 2 · pago parcial, esperar el resto' } else { 'Doc 2' }); tipo=$r.tipoDoc; monto=$r.a23 } }
}

# Producción: lo que se fabrica esta semana y lo que se despacha esta semana
$fabrica = @(); $despacha = @()
foreach ($kv in $prod.GetEnumerator()) {
  $o = $kv.Value; $s = SemanaAFecha $o.envio; $e = Envio $o
  $f = $fin_ | Where-Object { $_.num -eq $kv.Key } | Select-Object -First 1
  if ($f -and $f.tipo -ne 'VENTA') { continue }
  if ($s -and $s -eq $lunesActual) {
    foreach ($l in @($o.lineas)) {
      $m2 = (N $l.largo) / 100 * (N $l.ancho) / 100 * [math]::Max(1, (N $l.cantidad))
      $fabrica += [pscustomobject]@{ num=$kv.Key; madera=$(if ($l.madera) { "$($l.madera)".ToUpper() } else { '(sin madera)' }); m2=$m2 }
    }
  }
  if ($e -and $e -ge $lunesActual -and $e -le $lunesActual.AddDays(6)) {
    $despacha += [pscustomobject]@{ num=$kv.Key; cliente=("$($o.comprador) $($o.apellido)").Trim(); dia=$e; saldo=$(if ($f) { $f.saldo } else { 0 }); diaCargado=[bool]$o.dia_envio }
  }
}
$m2Semana = Suma $fabrica 'm2'

# Avisos atrasados (mismas ventanas que el tablero "Hoy hay que avisar")
$AV = @(@('aviso_sem','Aviso semana previa',-5),@('aviso_lun','Confirmar día',-2),@('aviso_dia','Sale mañana',-1),@('comprobante','Comprobante',1))
$atrasos = @{}; foreach ($a in $AV) { $atrasos[$a[1]] = @() }
foreach ($kv in $seg.GetEnumerator()) {
  $o = $kv.Value; $f = $fin_ | Where-Object { $_.num -eq $kv.Key } | Select-Object -First 1
  if (-not $f -or $f.tipo -ne 'VENTA') { continue }
  $e = Envio ([pscustomobject]@{ dia_envio=$o.dia_envio; envio=$o.semana }); if (-not $e) { continue }
  $dRel = ($hoy - $e).TotalDays
  foreach ($a in $AV) {
    $hecho = $o.checks -and $o.checks.($a[0]); $motivo = $o.excusas -and $o.excusas.($a[0])
    if (-not $hecho -and -not $motivo -and $dRel -gt $a[2] -and $dRel -le $a[2] + 30) { $atrasos[$a[1]] += $kv.Key }
  }
}

# ── Cotizador vs ventas reales ────────────────────────────────────────────
# Lee los KPI del Pulso del Cotizador (kpis-cotizador.json) y su foto cruda,
# y cruza cada venta real de Gestión con las cotizaciones del mismo teléfono,
# correo o monto de cierre. Solo lectura: no toca ninguno de los dos proyectos.
$cz = $null
$kpiPath = Join-Path $env:USERPROFILE '.casazaru\kpis-cotizador.json'
if (Test-Path $kpiPath) {
  $k = [IO.File]::ReadAllText($kpiPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
  $cotPath = Join-Path $k.foto 'cotizaciones.json'
  if (Test-Path $cotPath) {
    # En PS 5.1 ConvertFrom-Json entrega el arreglo como UN objeto: se guarda primero y recién ahí se filtra.
    $cotRaw = [IO.File]::ReadAllText($cotPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $cot = @($cotRaw | Where-Object { -not $_.eliminada })
    function Tel($s) { $d = ("$s" -replace '\D', ''); if ($d.Length -ge 8) { $d.Substring($d.Length - 8) } else { '' } }
    function Mail($s) { if ("$s" -match '[\w\.\-+]+@[\w\-]+\.[\w\.\-]+') { $matches[0].ToLower() } else { '' } }
    $idx = @{}
    foreach ($c in $cot) {
      $fc = ([datetime]$c.fecha_creacion).Date
      $item = [pscustomobject]@{ f=$fc; estado=$c.estado; cliente=$c.cliente; cierre=(N $c.monto_cierre); numero=$c.numero; contacto=$c.contacto }
      $claves = @((Tel $c.contacto), (Mail $c.contacto)); if ($item.cierre -gt 0) { $claves += 'm' + [math]::Round($item.cierre) }
      foreach ($key in $claves | Where-Object { $_ }) { if (-not $idx[$key]) { $idx[$key] = @() }; $idx[$key] += $item }
    }
    $finRaw = @{}; @($j.tablas.gestion_finanzas) | ForEach-Object { $finRaw[$_.num] = $_.data }
    function Cruce($v) {
      $d = $finRaw[$v.num]; $m = @()
      foreach ($key in @((Tel $d.celular), (Mail $d.email), ('m' + [math]::Round($v.total))) | Where-Object { $_ -and $_ -ne 'm0' }) { $m += @($idx[$key]) }
      @($m | Where-Object { $_ -and $_.f -le $v.fecha.AddDays(3) -and $_.f -ge $v.fecha.AddDays(-180) } | Sort-Object f)
    }
    $czMeses = foreach ($q in 2, 1, 0) {   # ojo: no llamarla $meses, PowerShell no distingue mayúsculas y pisaría $MESES
      $a = $iniMes.AddMonths(-$q); $b = if ($q -eq 0) { $fin } else { $a.AddMonths(1).AddDays(-1) }
      $vs = EnRango $ventas $a $b
      # @(): con un solo resultado PS 5.1 entrega un objeto suelto, sin .Count
      $x = foreach ($v in $vs) { $m = @(Cruce $v); [pscustomobject]@{ v=$v; cotizo=($m.Count -gt 0); ganado=(@($m | Where-Object estado -eq 'ganado').Count -gt 0); dias=$(if ($m.Count) { ($v.fecha - $m[0].f).Days } else { $null }) } }
      $conC = @($x | Where-Object cotizo); $dd = @($conC | ForEach-Object dias | Sort-Object)
      $km = $k.conversion_por_mes | Where-Object { $_.mes -eq $a.ToString('yyyy-MM') } | Select-Object -First 1
      [pscustomobject]@{ mes=$a; ventas=$vs.Count; monto=(Suma $vs 'total'); conCot=$conC.Count; marcadas=@($conC | Where-Object ganado).Count
        mediana=$(if ($dd.Count) { $dd[[math]::Floor(($dd.Count - 1) / 2)] } else { $null }); detalle=$x
        cotClientes=$(if ($km) { $km.clientes } else { $null }); cotGanados=$(if ($km) { $km.ganados } else { $null }); cotVendido=$(if ($km) { $km.vendido } else { $null }) }
    }
    $mesAct = $czMeses[-1]
    # Ganadas en el cotizador este mes que no tienen venta en Gestión (ni por teléfono, correo ni monto).
    # También por nombre y apellido: muchas ventas se cargan con otro teléfono o
    # con un monto distinto al cotizado (se agregó envío, se ajustó una medida).
    function NomTok($s) { @(("$s".ToLower().Normalize([Text.NormalizationForm]::FormD) -replace '[̀-ͯ]', '' -replace '[^a-z ]', ' ').Split(' ') | Where-Object { $_.Length -ge 3 }) }
    $claveVenta = @{}; $nombresVenta = @()
    foreach ($v in $ventas) {
      $d = $finRaw[$v.num]; $nombresVenta += ,(NomTok $v.cliente)
      foreach ($key in @((Tel $d.celular), (Mail $d.email), ('m' + [math]::Round($v.total)))) { if ($key -and $key -ne 'm0') { $claveVenta[$key] = 1 } }
    }
    function TieneVenta($c) {
      $t = Tel $c.contacto; $ml = Mail $c.contacto; $mm = 'm' + [math]::Round((N $c.monto_cierre))
      if (($t -and $claveVenta[$t]) -or ($ml -and $claveVenta[$ml]) -or ($mm -ne 'm0' -and $claveVenta[$mm])) { return $true }
      $tk = NomTok $c.cliente
      if ($tk.Count -ge 2) { foreach ($nv in $nombresVenta) { if (@($tk | Where-Object { $nv -contains $_ }).Count -ge 2) { return $true } } }
      return $false
    }
    # Solo las del mes, una por cliente (el panel repite al mismo cliente en varias cotizaciones), sin cierres simbólicos.
    $fantasmas = @($cot | Where-Object { $_.estado -eq 'ganado' -and (N $_.monto_cierre) -ge 1000 -and
        ([datetime]$(if ($_.fecha_concretada) { $_.fecha_concretada } else { $_.fecha_creacion })).Date -ge $iniMes } |
      Where-Object { -not (TieneVenta $_) } | Group-Object { $k2 = (Tel $_.contacto); if ($k2) { $k2 } else { "$($_.cliente)" } } |
      ForEach-Object { $_.Group | Sort-Object { N $_.monto_cierre } -Descending | Select-Object -First 1 })
    # Embudo de 14 días del Pulso + ventas reales de esos mismos 14 días que cotizaron
    $v14 = EnRango $ventas $fin.AddDays(-13) $fin
    $v14c = @($v14 | Where-Object { @(Cruce $_).Count -gt 0 })
    $vMed = @($vMes | ForEach-Object total | Sort-Object); $ventaMed = if ($vMed.Count) { $vMed[[math]::Floor(($vMed.Count - 1) / 2)] } else { 0 }
    $cz = [pscustomobject]@{ k=$k; meses=$czMeses; mesAct=$mesAct; fantasmas=$fantasmas; v14=$v14.Count; v14c=$v14c.Count; ventaMed=$ventaMed
      edad=((Get-Date) - [datetime]::ParseExact($k.generado, 'yyyy-MM-dd HH:mm', $null)).TotalDays }
  }
}

# ── HTML ──────────────────────────────────────────────────────────────────
function Tabla($cols, $filas) {
  $h = '<table><thead><tr>' + (($cols | ForEach-Object { "<th>$_</th>" }) -join '') + '</tr></thead><tbody>'
  if (-not $filas -or @($filas).Count -eq 0) { return $h + "<tr><td colspan=""$($cols.Count)"" class=""vacio"">Sin registros</td></tr></tbody></table>" }
  $h + ((@($filas) | ForEach-Object { '<tr>' + (($_ | ForEach-Object { "<td>$_</td>" }) -join '') + '</tr>' }) -join '') + '</tbody></table>'
}
function Agrupar($lista, $campo) {
  @($lista | Group-Object $campo | ForEach-Object { [pscustomobject]@{ k=$_.Name; n=$_.Count; m=(Suma $_.Group 'total') } } | Sort-Object m -Descending)
}

$max = ($serie | Measure-Object monto -Maximum).Maximum; if (-not $max) { $max = 1 }
$barras = ($serie | ForEach-Object {
  $h = [math]::Round(120 * $_.monto / $max); $x = 20 + 60 * [array]::IndexOf(@($serie), $_)
  $cls = if ($_.desde -eq $ini) { 'bar act' } else { 'bar' }
  "<rect class=""$cls"" x=""$x"" y=""$(140 - $h)"" width=""40"" height=""$h"" rx=""4""/>" +
  "<text x=""$($x + 20)"" y=""$(134 - $h)"" class=""bv"">$([math]::Round($_.monto / 1000000, 1).ToString($cl))M</text>" +
  "<text x=""$($x + 20)"" y=""158"" class=""bl"">$($_.desde.ToString('dd/MM'))</text>"
}) -join ''

$porVend = Agrupar $vMes 'vendedor'; $porComo = Agrupar $vMes 'como'; $porPago = Agrupar $vMes 'pago'
$porCat = @($vMes | ForEach-Object { [pscustomobject]@{ cat=(Categoria $_.producto); total=$_.total } } | Group-Object cat |
  ForEach-Object { [pscustomobject]@{ k=$_.Name; n=$_.Count; m=(Suma $_.Group 'total') } } | Sort-Object m -Descending)
$porMadera = @($fabrica | Group-Object madera | ForEach-Object { [pscustomobject]@{ k=$_.Name; m2=(Suma $_.Group 'm2'); n=@($_.Group.num | Select-Object -Unique).Count } } | Sort-Object m2 -Descending)
$ocup = [math]::Round(100 * $m2Semana / $CAPACIDAD_M2)

$tSemana = $vSem | Sort-Object fecha | ForEach-Object { ,@("#$($_.num)", "<span style=""white-space:nowrap"">$($_.fecha.ToString('dd/MM'))</span>", (E $_.cliente), (E $_.producto), (E $_.vendedor), (Plata $_.total), (Plata $_.abonado), $(if ($_.saldo -gt 0) { Plata $_.saldo } else { '✓' })) }
$totCobrar = Suma $cobrar 'saldo'
$tCobrar = $cobrar | ForEach-Object {
  $est = if ($_.envio -and $_.envio -lt $hoy) { '<b class="rojo">despachado</b>' } elseif ($_.envio) { 'despacha ' + $_.envio.ToString('dd/MM') } else { '—' }
  ,@("#$($_.num)", (E $_.cliente), (Plata $_.total), (Plata $_.abonado), "<b>$(Plata $_.saldo)</b>", $est)
}
$tDocs = $docs | ForEach-Object { ,@("#$($_.num)", (E $_.cliente), $_.doc, (E $_.tipo), (Plata $_.monto)) }
$tDesp = $despacha | Sort-Object dia | ForEach-Object { ,@("#$($_.num)", (E $_.cliente), $(if ($_.diaCargado) { $_.dia.ToString('ddd dd/MM', $cl) } else { 'semana del ' + $_.dia.ToString('dd/MM') }), $(if ($_.saldo -gt 1000) { "<b class=""rojo"">debe $(Plata $_.saldo)</b>" } else { 'pagado' })) }
$tMadera = $porMadera | ForEach-Object { ,@((E $_.k), $_.n, ($_.m2.ToString('N2', $cl) + ' m²')) }
function TablaGrupo($g, $titulo) { Tabla @($titulo, 'Ventas', 'Monto', '%') ($g | ForEach-Object { $tm = Suma $vMes 'total'; ,@((E $_.k), $_.n, (Plata $_.m), $(if ($tm) { [math]::Round(100 * $_.m / $tm).ToString() + '%' } else { '' })) }) }
$tAvisos = $AV | ForEach-Object { $l = $atrasos[$_[1]]; ,@($_[1], @($l).Count, ((@($l) | Sort-Object | ForEach-Object { "#$_" }) -join ', ')) }

# Página "Cotizador vs ventas reales" (solo si están los datos del Pulso)
$czHtml = ''
if ($cz) {
  $ma = $cz.mesAct; $pc = if ($ma.ventas) { [math]::Round(100 * $ma.conCot / $ma.ventas) } else { 0 }
  $viejo = if ($cz.edad -gt 2) { "<div class=""nota"">⚠ Los datos del cotizador son del $(E $cz.k.generado): hace $([math]::Floor($cz.edad)) días. El Pulso se actualiza los lunes 09:00.</div>" } else { '' }
  $tMeses = $cz.meses | ForEach-Object {
    $n = $MESES[$_.mes.Month - 1]; $n = $n.Substring(0,1) + $n.Substring(1).ToLower()
    ,@($n, $(if ($_.cotClientes -ne $null) { $_.cotClientes } else { '—' }), $(if ($_.cotGanados -ne $null) { $_.cotGanados } else { '—' }), $(if ($_.cotVendido -ne $null) { Plata $_.cotVendido } else { '—' }),
       "<b>$($_.ventas)</b>", "<b>$(Plata $_.monto)</b>", $(if ($_.ventas) { "$($_.conCot) ($([math]::Round(100 * $_.conCot / $_.ventas))%)" } else { '—' }), "$($_.marcadas) de $($_.conCot)", $(if ($_.mediana -ne $null) { "$($_.mediana) días" } else { '—' }))
  }
  $sinCot = @($ma.detalle | Where-Object { -not $_.cotizo } | ForEach-Object { ,@("#$($_.v.num)", (E $_.v.cliente), (Plata $_.v.total), $(if ($_.v.web) { 'venta web' } else { 'no se encontró cotización' })) })
  $sinMarca = @($ma.detalle | Where-Object { $_.cotizo -and -not $_.ganado } | ForEach-Object { ,@("#$($_.v.num)", (E $_.v.cliente), (Plata $_.v.total), "$($_.dias) días desde que cotizó") })
  $tFant = @($cz.fantasmas | ForEach-Object { ,@((E $_.numero), (E $_.cliente), (Plata (N $_.monto_cierre)), ([datetime]$_.fecha_creacion).ToString('dd/MM')) })
  $e = $cz.k.embudo_14_dias
  $ta = $cz.k.toques_atrasados
  $czHtml = @"
<h2 style="break-before: page">Cotizador vs ventas reales</h2>
<div class="sub">Cruza el Pulso del Cotizador con las ventas de Gestión por teléfono, correo o monto de cierre (hasta 180 días antes de la venta). Datos del cotizador: $(E $cz.k.generado).</div>
$viejo
<div class="kpis">
  <div class="kpi"><div class="l">Ventas del mes que cotizaron</div><div class="v">$($ma.conCot) de $($ma.ventas)</div><span class="d">$pc% pasó por el cotizador</span></div>
  <div class="kpi"><div class="l">Marcadas "ganada" en el panel</div><div class="v">$($ma.marcadas) de $($ma.conCot)</div><span class="d">el resto hay que marcarlas</span></div>
  <div class="kpi"><div class="l">Cotización → venta</div><div class="v">$(if ($ma.mediana -ne $null) { "$($ma.mediana) días" } else { '—' })</div><span class="d">mediana, con la fecha real de venta</span></div>
  <div class="kpi"><div class="l">Ticket</div><div class="v">$(Plata $cz.ventaMed)</div><span class="d">venta real (mediana) vs cotizado $(Plata $cz.k.ticket.cotizacion_mediana)</span></div>
</div>
<h2>Mes a mes: lo que dice el cotizador y lo que se vendió</h2>
$(Tabla @('Mes','Cotizaron (clientes)','Ganadas en panel','Vendido según panel','Ventas reales','Monto real','Con cotización previa','Marcadas ganada','Cotización → venta') $tMeses)
<h2>Embudo de los últimos 14 días, hasta la venta real</h2>
$(Tabla @('Visitan','Eligen producto','Ponen medidas','Dejan datos','Cotizaciones','Ventas reales','Ventas que cotizaron') @(,@($e.visita, $e.producto, $e.medidas, $e.datos, $e.cotizacion, $cz.v14, $cz.v14c)))
<div class="nota">Seguimiento pendiente según el Pulso: <b>$($ta.clientes) clientes</b> con toque atrasado por <b>$(Plata $ta.monto)</b> cotizados (César: $($ta.por_dueno.cesar.n); web: $($ta.por_dueno.web.n)). Cartera abierta: $($cz.k.cartera_abierta.clientes) clientes.</div>
<div class="dos"><div>
<h2>Ganadas en el panel sin venta en Gestión ($($tFant.Count))</h2>
<div class="sub">Probablemente ventas que falta cargar.</div>
$(Tabla @('Cotización','Cliente','Cierre','Cotizó') $tFant)
</div><div>
<h2>Vendidas sin marcar "ganada" ($($sinMarca.Count))</h2>
<div class="sub">Cotizaron y compraron, pero el panel no lo sabe.</div>
$(Tabla @('N°','Cliente','Venta','') $sinMarca)
</div></div>
<h2>Ventas del mes que no pasaron por el cotizador ($($sinCot.Count))</h2>
$(Tabla @('N°','Cliente','Venta','Motivo') $sinCot)
"@
}

$totSem = Suma $vSem 'total'; $totAnt = Suma $vAnt 'total'; $totMes = Suma $vMes 'total'; $totMesAnt = Suma $vMesAnt 'total'
$ticket = if ($vSem.Count) { $totSem / $vSem.Count } else { 0 }
$titulo = "Informe semanal · $($ini.ToString('dd MMM', $cl)) al $($fin.ToString('dd MMM yyyy', $cl))"
$mesNom = $MESES[$fin.Month - 1].Substring(0,1) + $MESES[$fin.Month - 1].Substring(1).ToLower()
$faltaTramo = if ($sig) { "Faltan <b>$(Plata ($sig[0] - $vpCesar))</b> para el tramo de $([math]::Round($sig[1]*100,1).ToString($cl))%." } else { 'Está en el tramo máximo.' }

$html = @"
<!doctype html><html lang="es"><head><meta charset="utf-8"><title>$(E $titulo)</title><style>
@page { size: A4; margin: 14mm 12mm; }
* { box-sizing: border-box; }
body { font-family: 'Segoe UI', Arial, sans-serif; color: #2B2118; font-size: 10.5pt; margin: 0; }
h1 { font-size: 19pt; margin: 0; color: #5C3D20; }
h2 { font-size: 12.5pt; color: #7B5B3A; border-bottom: 2px solid #E8DFD5; padding-bottom: 4px; margin: 20px 0 8px; break-after: avoid; }
.sub { color: #8A7960; font-size: 9pt; margin-top: 2px; }
.kpis { display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px; margin-top: 14px; }
.kpi { background: #F7F2EC; border-radius: 8px; padding: 10px 12px; }
.kpi .l { font-size: 8pt; text-transform: uppercase; letter-spacing: .05em; color: #8A7960; }
.kpi .v { font-size: 15pt; font-weight: 700; color: #5C3D20; margin-top: 2px; }
.d { font-size: 8.5pt; font-weight: 600; color: #8A7960; } .up { color: #2E7D32; } .down { color: #B4342A; }
table { width: 100%; border-collapse: collapse; font-size: 9pt; break-inside: auto; }
th { text-align: left; background: #F2ECE4; color: #6B5840; font-weight: 600; padding: 5px 6px; font-size: 8.5pt; }
td { padding: 4px 6px; border-bottom: 1px solid #EFE8DF; } tr { break-inside: avoid; }
td:nth-last-child(-n+3) { white-space: nowrap; }
.vacio { color: #9A8B7C; text-align: center; font-style: italic; }
.dos { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; }
.nota { background: #FDF6E8; border-left: 3px solid #C9902A; padding: 8px 10px; font-size: 9pt; margin: 6px 0; }
.rojo { color: #B4342A; } svg .bar { fill: #D9C4A5; } svg .bar.act { fill: #7B5B3A; }
svg .bv { font-size: 9px; text-anchor: middle; fill: #5C3D20; font-weight: 600; } svg .bl { font-size: 9px; text-anchor: middle; fill: #8A7960; }
.pie { margin-top: 22px; font-size: 8pt; color: #9A8B7C; border-top: 1px solid #E8DFD5; padding-top: 6px; }
.barra { height: 10px; background: #EFE8DF; border-radius: 5px; overflow: hidden; margin: 4px 0 2px; }
.barra > div { height: 100%; background: $(if ($ocup -gt 100) { '#B4342A' } else { '#2E7D32' }); }
</style></head><body>
<h1>🪵 Casa Zaru — $(E $titulo)</h1>
<div class="sub">Ventas por fecha de venta (solo tipo venta: sin muestrarios ni devoluciones) · generado $((Get-Date).ToString('dd/MM/yyyy HH:mm'))</div>

<div class="kpis">
  <div class="kpi"><div class="l">Ventas de la semana</div><div class="v">$(Plata $totSem)</div>$(Delta $totSem $totAnt) <span class="d">vs semana anterior ($(Plata $totAnt))</span></div>
  <div class="kpi"><div class="l">N° de ventas</div><div class="v">$($vSem.Count)</div><span class="d">semana anterior: $($vAnt.Count)</span></div>
  <div class="kpi"><div class="l">Ticket promedio</div><div class="v">$(Plata $ticket)</div></div>
  <div class="kpi"><div class="l">$mesNom al $($fin.Day)</div><div class="v">$(Plata $totMes)</div>$(Delta $totMes $totMesAnt) <span class="d">vs mismo período mes anterior</span></div>
</div>

<h2>Ventas de las últimas 8 semanas</h2>
<svg width="500" height="165" viewBox="0 0 500 165">$barras</svg>

<h2>Ventas de la semana ($($vSem.Count))</h2>
$(Tabla @('N°','Fecha','Cliente','Producto','Vendedor','Total','Abonado','Saldo') $tSemana)

<h2>Comisión de César · $mesNom</h2>
<div class="nota">Valor producto vendido por César en el mes: <b>$(Plata $vpCesar)</b> → tramo <b>$([math]::Round($tramo[1]*100,1).ToString($cl))%</b>, comisión estimada <b>$(Plata ($vpCesar * $tramo[1]))</b>. $faltaTramo Es un avance, no la liquidación.</div>

<h2>${mesNom}: de dónde vienen las ventas</h2>
<div class="dos"><div>$(TablaGrupo $porVend 'Vendedor')</div><div>$(TablaGrupo $porCat 'Producto')</div></div>
<div class="dos" style="margin-top:10px"><div>$(TablaGrupo $porComo '¿Cómo nos conoció?')</div><div>$(TablaGrupo $porPago 'Forma de pago')</div></div>

<h2>Cobranza: saldos por cobrar ($(Plata $totCobrar) en $($cobrar.Count))</h2>
<div class="sub" style="margin-bottom:6px">Sin ventas web (Shopify cobra el total). "Despachado" = ya salió y todavía debe.</div>
$(Tabla @('N°','Cliente','Total','Abonado','Saldo','Despacho') $tCobrar)

<h2>Boletas y facturas por emitir ($($docs.Count))</h2>
$(Tabla @('N°','Cliente','Documento','Tipo','Monto') $tDocs)

<h2>Esta semana en el taller</h2>
<div class="dos"><div>
  <b>Se fabrica (semana del $($lunesActual.ToString('dd/MM')))</b>
  <div class="barra"><div style="width:$([math]::Min(100,$ocup))%"></div></div>
  <div class="sub">$($m2Semana.ToString('N2', $cl)) m² de $CAPACIDAD_M2 m² de capacidad ($ocup%)</div>
  $(Tabla @('Madera','Pedidos','m²') $tMadera)
</div><div>
  <b>Se despacha esta semana ($($despacha.Count))</b>
  $(Tabla @('N°','Cliente','Día','Pago') $tDesp)
</div></div>

<h2>Avisos al cliente atrasados</h2>
$(Tabla @('Aviso','Pedidos','Cuáles') $tAvisos)
$czHtml

<div class="pie">Fuente: $(E $resp.Name) (respaldo de Gestión del $($resp.LastWriteTime.ToString('dd/MM/yyyy HH:mm'))). Lo marcado en la app después de esa hora no aparece. Semanas de producción nombradas por su lunes; el despacho va la semana siguiente.</div>
</body></html>
"@

# ── PDF ───────────────────────────────────────────────────────────────────
New-Item -ItemType Directory -Force $Salida | Out-Null
$tmp = Join-Path $env:TEMP "informe-gestion-$($lunesActual.ToString('yyyy-MM-dd')).html"
[IO.File]::WriteAllText($tmp, $html, (New-Object Text.UTF8Encoding($true)))
$pdf = Join-Path $Salida "Informe semanal Casa Zaru $($lunesActual.ToString('yyyy-MM-dd')).pdf"
$edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $edge) { throw 'No encontré Microsoft Edge para generar el PDF.' }
$uri = ([Uri]$tmp).AbsoluteUri
$p = Start-Process -FilePath $edge -ArgumentList @('--headless=new', '--disable-gpu', '--no-pdf-header-footer', "--print-to-pdf=`"$pdf`"", $uri) -Wait -PassThru -WindowStyle Hidden
if (-not (Test-Path $pdf)) { throw "Edge no generó el PDF (código $($p.ExitCode))." }
Remove-Item $tmp -ErrorAction SilentlyContinue
"PDF: $pdf"
"Semana $($ini.ToString('dd/MM')) a $($fin.ToString('dd/MM')): $($vSem.Count) ventas por $(Plata $totSem) | mes $(Plata $totMes) | cobrar $(Plata $totCobrar) | docs $($docs.Count)"
