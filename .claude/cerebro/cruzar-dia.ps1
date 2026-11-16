# Cerebro Zaru - cruce de datos del dia (seccion «Cruce de datos» de Mi dia).
# Etapa 1 (16-11-2026): cotizaciones GANADAS en el Cotizador que no tienen pedido en la Gestion.
# Etapa 2 (16-11-2026): pagos que entraron al banco (avisos del correo + cartola) contra los abonos de Finanzas.
# Uso (desde Bash):
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .claude/cerebro/cruzar-dia.ps1 -Fecha 2026-11-16 `
#     -Cotizador <scratchpad>/cruce-cotizador.json -Gestion <scratchpad>/cruce-gestion.json `
#     -Marcas <scratchpad>/marcas-<dia anterior>.json -Salida <scratchpad>/cruce-<hoy>.json
# -Cotizador y -Gestion son los resultados de sql/cotizador-cruce.sql y sql/gestion-cruce.sql, guardados tal cual.
# -Marcas (opcional, se puede repetir separando con coma): lo que el usuario descarto en la pestaña pasa a
#   cruce-descartes.csv y no vuelve a salir.
# Solo lee las fuentes; escribe la salida y cruce-descartes.csv (en Drive). Sin datos ni secretos: el repo es publico.
param(
  [Parameter(Mandatory=$true)][string]$Fecha,
  [Parameter(Mandatory=$true)][string]$Cotizador,
  [Parameter(Mandatory=$true)][string]$Gestion,
  [Parameter(Mandatory=$true)][string]$Salida,
  [string[]]$Marcas = @(),
  [string]$Descartes = 'G:\Mi unidad\Casa Zaru\Cerebro\cruce-descartes.csv',
  # Etapa 2 (16-11-2026): pagos que entraron al banco contra los abonos de Finanzas.
  # -PagosNuevos: JSON con los avisos de transferencia RECIBIDA leidos del correo:
  #     [{ "fecha":"2026-11-13", "hora":"10:41", "monto":1037434, "pagador":"...", "rut":"76731998-3", "comentario":"...", "banco":"BCI" }]
  # -Cartola: CSV de leer-cartola-bci.ps1 (skill conciliacion), cuando hay una cartola nueva en Descargas.
  # Los dos se suman al libro de pagos (en Drive), que es lo que se cruza: ultimos -DiasPagos dias.
  [string]$PagosNuevos = '',
  [string]$Cartola = '',
  [string]$Pagos = 'G:\Mi unidad\Casa Zaru\Cerebro\pagos.csv',
  [string]$Estado = 'G:\Mi unidad\Casa Zaru\Cerebro\pagos-estado.json',
  [string]$Excluir = (Join-Path $env:USERPROFILE '.claude\conciliacion-excluir.txt'),
  [int]$DiasPagos = 21
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Leer-Filas([string]$ruta) {
  $j = Get-Content -LiteralPath $ruta -Raw -Encoding UTF8 | ConvertFrom-Json
  # Acepta el arreglo directo o la fila de la consulta: [{ "cruce": [...] }]
  $j = @($j)
  if ($j.Count -eq 1 -and $j[0].PSObject.Properties.Name -contains 'cruce') { return @($j[0].cruce) }
  return $j
}
function Sin-Tildes([string]$s) {
  if (-not $s) { return '' }
  $n = $s.ToLowerInvariant().Normalize([Text.NormalizationForm]::FormD)
  $sb = New-Object System.Text.StringBuilder
  foreach ($ch in $n.ToCharArray()) { if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne 'NonSpacingMark') { [void]$sb.Append($ch) } }
  return $sb.ToString()
}
function Fono8([string]$s) { $d = ($s -replace '\D', ''); if ($d.Length -ge 8) { return $d.Substring($d.Length - 8) } return '' }
function Palabras([string]$s) { return @((Sin-Tildes $s) -split '[^a-z]+' | Where-Object { $_.Length -ge 3 }) }
function Mismo-Nombre($a, $b) {
  # Un solo nombre en comun no alcanza: primer nombre igual y ademas otro apellido en comun.
  if ($a.Count -lt 2 -or $b.Count -lt 2) { return $false }
  if ($a[0] -ne $b[0]) { return $false }
  foreach ($x in $a[1..($a.Count - 1)]) { if ($b[1..($b.Count - 1)] -contains $x) { return $true } }
  return $false
}
function Plata($n) { return '$' + ([math]::Round([double]$n)).ToString('N0', [Globalization.CultureInfo]::GetCultureInfo('es-CL')) }
function Corta([string]$iso) { if ($iso -match '^(\d{4})-(\d{2})-(\d{2})') { return "$($Matches[3])-$($Matches[2])" } return $iso }

$cot = Leer-Filas $Cotizador
$ped = Leer-Filas $Gestion

# 1. Descartes: lo que el usuario marco «No es venta» en la pestaña queda para siempre en el CSV.
$desc = @{}
if (Test-Path -LiteralPath $Descartes) { Import-Csv -LiteralPath $Descartes -Encoding UTF8 | ForEach-Object { $desc[$_.id] = $_ } }
$nuevos = 0
foreach ($m in $Marcas) {
  if (-not $m -or -not (Test-Path -LiteralPath $m)) { continue }
  $mj = Get-Content -LiteralPath $m -Raw -Encoding UTF8 | ConvertFrom-Json
  if (-not $mj -or -not $mj.cruce) { continue }
  foreach ($p in $mj.cruce.PSObject.Properties) {
    if ($p.Value.accion -eq 'descartar' -and -not $desc.ContainsKey($p.Name)) {
      $desc[$p.Name] = [pscustomobject]@{ id = $p.Name; fecha = $Fecha; motivo = [string]$p.Value.motivo }
      $nuevos++
    }
  }
}
if ($nuevos -gt 0) {
  $lin = New-Object System.Collections.ArrayList
  [void]$lin.Add('id,fecha,motivo')
  foreach ($d in ($desc.Values | Sort-Object fecha, id)) { [void]$lin.Add(('"{0}","{1}","{2}"' -f $d.id, $d.fecha, (([string]$d.motivo) -replace '"', '""'))) }
  [System.IO.File]::WriteAllText($Descartes, ($lin -join "`r`n") + "`r`n", (New-Object System.Text.UTF8Encoding($true)))
}

# 2. Cada ganada busca UN pedido del mismo cliente (telefono, o nombre y apellido), el de monto mas parecido.
#    Un pedido justifica una sola cotizacion: un cliente con dos ganadas y un pedido deja una sin pedido.
function Dia([string]$s) { if ($s -and $s.Length -ge 10) { return [datetime]::ParseExact($s.Substring(0, 10), 'yyyy-MM-dd', $null) } return $null }
$Cots = @($cot | ForEach-Object { [pscustomobject]@{ c = $_; f8 = (Fono8 ([string]$_.contacto)); pal = (Palabras ([string]$_.cliente)); creada = (Dia ([string]$_.creada)); monto = [double]$_.monto; pedido = $null } })
$Peds = @($ped | Where-Object { -not $_.tipo -or $_.tipo -eq 'VENTA' } | ForEach-Object { [pscustomobject]@{ p = $_; f8 = (Fono8 ([string]$_.celular)); pal = (Palabras ("$($_.nombre) $($_.apellido)")); fecha = (Dia ([string]$_.fecha)); usado = $false } })
function Mismo-Cliente($a, $b) { return ($a.f8 -and $a.f8 -eq $b.f8) -or (Mismo-Nombre $a.pal $b.pal) }

# Pares posibles: mismo cliente y pedido no anterior a la cotizacion (salvo que el monto calce casi exacto:
# un pedido que se amplio despues conserva su fecha original). Se asignan del monto mas parecido al menos.
$pares = New-Object System.Collections.ArrayList
foreach ($x in $Cots) {
  foreach ($y in $Peds) {
    if (-not (Mismo-Cliente $x $y)) { continue }
    $dif = [math]::Min([math]::Abs($x.monto - [double]$y.p.val_prod), [math]::Abs($x.monto - [double]$y.p.total))
    $despues = (-not $x.creada) -or (-not $y.fecha) -or ($y.fecha -ge $x.creada.AddDays(-3))
    if ($despues -or $dif -le ($x.monto * 0.01)) { [void]$pares.Add([pscustomobject]@{ x = $x; y = $y; dif = $dif }) }
  }
}
foreach ($par in ($pares | Sort-Object dif)) {
  if ($par.x.pedido -or $par.y.usado) { continue }
  $par.x.pedido = $par.y; $par.y.usado = $true
}

$sinPedido = New-Object System.Collections.ArrayList
$calzan = 0
foreach ($x in $Cots) {
  if ($x.pedido) { $calzan++; continue }
  # Cotizacion repetida: otra ganada del mismo cliente por el mismo monto ya tiene su pedido.
  $repetida = @($Cots | Where-Object { $_.pedido -and $_.monto -eq $x.monto -and (Mismo-Cliente $_ $x) }).Count -gt 0
  # Absorbida: el cliente tiene un pedido de esa fecha o posterior por un monto igual o mayor (se amplio la compra).
  $absorbida = @($Peds | Where-Object { (Mismo-Cliente $x $_) -and [double]$_.p.total -ge $x.monto -and ((-not $x.creada) -or (-not $_.fecha) -or ($_.fecha -ge $x.creada.AddDays(-3))) }).Count -gt 0
  if ($repetida -or $absorbida) { $calzan++; continue }
  $c = $x.c
  $num = ([string]$c.numero) -replace '^N°\s*', ''
  $id = 'cot:' + $num
  if ($desc.ContainsKey($id)) { continue }
  [void]$sinPedido.Add([pscustomobject]@{
    id = $id
    tono = 'rojo'
    titulo = [string]$c.cliente
    monto = $c.monto
    lineas = @("Ganada el $(Corta ([string]$c.concretada)) · cotización $num" + $(if ($c.producto) { " · $($c.producto)" } else { '' }))
    acciones = @('cargar', 'descartar')
    cot = [pscustomobject]@{ numero = $num; cliente = [string]$c.cliente; contacto = [string]$c.contacto; monto = $c.monto; producto = [string]$c.producto; concretada = [string]$c.concretada; link = [string]$c.link; canal = [string]$c.canal }
  })
}

# 3. Pagos (etapa 2). El libro de pagos junta los avisos del correo y la cartola; cada pago entra una vez.
function RutLimpio([string]$s) { return (($s -replace '[^0-9kK]', '').ToLowerInvariant()) }
function Comparten($a, $b) {
  # Cuantas palabras tienen en comun; el banco corta los nombres («Espin» = Espinoza): vale el prefijo de 5 o mas letras.
  $n = 0
  foreach ($x in $a) { foreach ($y in $b) {
    if ($x -eq $y -or ($x.Length -ge 5 -and $y.StartsWith($x)) -or ($y.Length -ge 5 -and $x.StartsWith($y))) { $n++; break }
  } }
  return $n
}
$libro = New-Object System.Collections.ArrayList
$claves = @{}
function Sumar-Pago($fecha, $hora, $monto, $pagador, $rut, $comentario, $banco, $fuente) {
  $m = [double]$monto; if ($m -le 0 -or -not $fecha) { return $false }
  $f = ([string]$fecha).Substring(0, 10)
  $clave = "$f|$([math]::Round($m))"   # mismo dia y mismo monto = el mismo pago visto por el correo y por la cartola
  if ($claves.ContainsKey($clave)) { return $false }
  $claves[$clave] = $true
  [void]$libro.Add([pscustomobject]@{ fecha = $f; hora = [string]$hora; monto = [math]::Round($m); pagador = ([string]$pagador).Trim(); rut = [string]$rut; comentario = ([string]$comentario).Trim(); banco = [string]$banco; fuente = [string]$fuente })
  return $true
}
$hayPagos = $false
if (Test-Path -LiteralPath $Pagos) { $hayPagos = $true; Import-Csv -LiteralPath $Pagos -Encoding UTF8 | ForEach-Object { [void](Sumar-Pago $_.fecha $_.hora $_.monto $_.pagador $_.rut $_.comentario $_.banco $_.fuente) } }
$est = [pscustomobject]@{ correo = $null; cartola_hasta = $null; cartola_leida = $null }
if (Test-Path -LiteralPath $Estado) { $e0 = Get-Content -LiteralPath $Estado -Raw -Encoding UTF8 | ConvertFrom-Json; foreach ($k in 'correo', 'cartola_hasta', 'cartola_leida') { if ($e0.PSObject.Properties.Name -contains $k) { $est.$k = $e0.$k } } }
$pagosNuevosN = 0
if ($PagosNuevos -and (Test-Path -LiteralPath $PagosNuevos)) {
  $hayPagos = $true
  $pn = Get-Content -LiteralPath $PagosNuevos -Raw -Encoding UTF8 | ConvertFrom-Json   # en PS 5.1 el arreglo sale entero: se desarma al asignarlo
  foreach ($x in @($pn)) { if ($x -and (Sumar-Pago $x.fecha $x.hora $x.monto $x.pagador $x.rut $x.comentario $x.banco 'correo')) { $pagosNuevosN++ } }
  $est.correo = (Get-Date).ToString('o')
}
if ($Cartola -and (Test-Path -LiteralPath $Cartola)) {
  $hayPagos = $true
  $filasC = @(Import-Csv -LiteralPath $Cartola -Encoding UTF8)
  foreach ($x in $filasC) { if ([double]$x.ingreso -gt 0 -and (Sumar-Pago $x.fecha $x.hora $x.ingreso $x.nombre $x.rut $x.comentario $x.banco 'cartola')) { $pagosNuevosN++ } }
  $hasta = ($filasC | ForEach-Object { $_.fecha } | Sort-Object | Select-Object -Last 1)
  if ($hasta) { $est.cartola_hasta = $hasta; $est.cartola_leida = (Get-Date).ToString('o') }
}
if ($hayPagos -and ($pagosNuevosN -gt 0 -or -not (Test-Path -LiteralPath $Pagos))) {
  $lp = New-Object System.Collections.ArrayList
  [void]$lp.Add('fecha,hora,monto,pagador,rut,comentario,banco,fuente')
  foreach ($x in ($libro | Sort-Object fecha, hora)) { [void]$lp.Add((@($x.fecha, $x.hora, $x.monto, $x.pagador, $x.rut, $x.comentario, $x.banco, $x.fuente) | ForEach-Object { '"' + (([string]$_) -replace '"', '""') + '"' }) -join ',') }
  [System.IO.File]::WriteAllText($Pagos, ($lp -join "`r`n") + "`r`n", (New-Object System.Text.UTF8Encoding($true)))
}
if ($hayPagos) { [System.IO.File]::WriteAllText($Estado, ($est | ConvertTo-Json), $utf8) }

$sinMarcar = New-Object System.Collections.ArrayList
$pagoSinPedido = New-Object System.Collections.ArrayList
$sinDueno = New-Object System.Collections.ArrayList
$pagosOk = 0; $pagosVistos = 0
if ($hayPagos) {
  # Plata propia que no es venta: la otra cuenta de la empresa y los nombres del archivo local de exclusiones.
  $propios = @('77157082')
  $nomPropios = @()
  if (Test-Path -LiteralPath $Excluir) { $nomPropios = @(Get-Content -LiteralPath $Excluir -Encoding UTF8 | Where-Object { $_ -and $_.Trim() -and -not $_.Trim().StartsWith('#') } | ForEach-Object { ,(Palabras $_) }) }
  $hoyD = Dia $Fecha
  $PF = @($ped | Where-Object { -not $_.tipo -or $_.tipo -eq 'VENTA' } | ForEach-Object {
    $ab = New-Object System.Collections.ArrayList
    foreach ($k in 'a1', 'a2', 'a3') { if ([double]$_.$k -gt 0) { [void]$ab.Add([double]$_.$k) } }
    [pscustomobject]@{ p = $_; rut = (RutLimpio ([string]$_.rut)); pal = (Palabras ("$($_.nombre) $($_.apellido)")); razon = (Palabras ([string]$_.razon)); libres = $ab; saldo = ([double]$_.total - [double]$_.a1 - [double]$_.a2 - [double]$_.a3) }
  })
  $porVer = New-Object System.Collections.ArrayList
  foreach ($g in ($libro | Sort-Object fecha, hora)) {
    $fd = Dia $g.fecha
    if ($hoyD -and $fd -and ($hoyD - $fd).TotalDays -gt $DiasPagos) { continue }
    $rl = RutLimpio $g.rut
    $pg = Palabras $g.pagador
    if ($rl -and ($propios | Where-Object { $rl.StartsWith($_) })) { continue }
    if (@($nomPropios | Where-Object { $_.Count -and (Comparten $_ $pg) -ge [math]::Min(2, $_.Count) }).Count) { continue }
    $pagosVistos++
    $suyos = @($PF | Where-Object { ($rl -and $_.rut -and $_.rut -eq $rl) -or ((Comparten $pg $_.pal) -ge 2) -or ($_.razon.Count -ge 2 -and (Comparten $pg $_.razon) -ge 2) })
    [void]$porVer.Add([pscustomobject]@{ g = $g; rl = $rl; pal = $pg; suyos = $suyos; ok = $false })
  }
  # a) el pago es un abono ya marcado (mismo monto) en un pedido de ese cliente
  foreach ($v in $porVer) {
    foreach ($s in $v.suyos) { $i = $s.libres.IndexOf([double]$v.g.monto); if ($i -ge 0) { $s.libres.RemoveAt($i); $v.ok = $true; $pagosOk++; break } }
  }
  # b) pago partido: varios pagos del mismo pagador suman un abono marcado
  foreach ($grp in ($porVer | Where-Object { -not $_.ok -and $_.suyos.Count } | Group-Object { if ($_.rl) { $_.rl } else { $_.g.pagador } })) {
    $suma = 0; foreach ($v in $grp.Group) { $suma += [double]$v.g.monto }
    foreach ($s in $grp.Group[0].suyos) { $i = $s.libres.IndexOf([double]$suma); if ($i -ge 0 -and $grp.Count -gt 1) { $s.libres.RemoveAt($i); foreach ($v in $grp.Group) { $v.ok = $true; $pagosOk++ }; break } }
  }
  foreach ($v in ($porVer | Where-Object { -not $_.ok })) {
    $g = $v.g
    $llave = if ($v.rl) { $v.rl } else { ($v.pal -join '-') }
    $id = "pago:$($g.fecha):$($g.monto):$llave"
    if ($desc.ContainsKey($id)) { continue }
    $base = "$($g.banco) · $(Corta $g.fecha)" + $(if ($g.comentario -and $g.comentario -ne 'Sin mensaje') { " · «$($g.comentario)»" } else { '' })
    # c) cliente con saldo: falta marcar el abono. Si el pago es mucho mayor que el saldo, no es de ese pedido.
    $conSaldo = @($v.suyos | Where-Object { $_.saldo -gt 0 -and [double]$g.monto -le ($_.saldo * 2) } | Sort-Object { [math]::Abs($_.saldo - [double]$g.monto) })
    if ($conSaldo.Count) {
      $s = $conSaldo[0]; $dif = [double]$g.monto - $s.saldo
      $nota = if ($dif -eq 0) { 'Calza con el saldo del pedido.' } elseif ($dif -gt 0) { "El saldo era $(Plata $s.saldo): pagó $(Plata $dif) de más." } else { "Quedaría un saldo de $(Plata (-$dif))." }
      [void]$sinMarcar.Add([pscustomobject]@{
        id = $id; tono = 'ambar'; titulo = "$($s.p.num) · $($s.p.nombre) $($s.p.apellido)".Trim(); monto = $g.monto
        lineas = @($base, $nota); acciones = @('marcar', 'descartar'); botones = [pscustomobject]@{ descartar = 'No es de este pedido' }
        pago = [pscustomobject]@{ num = [string]$s.p.num; monto = $g.monto; fecha = $g.fecha; pagador = $g.pagador; banco = $g.banco }
      })
      continue
    }
    # d) sin pedido que lo explique: ¿calza con una venta del Cotizador que no tiene pedido?
    $cz = $null
    foreach ($x in $Cots) {
      if ($x.pedido) { continue }
      $m70 = [math]::Round($x.monto * 0.7)
      # Paga una empresa por el cliente: el pagador ya tiene un pedido anterior a nombre de la persona que cotizó.
      $porSuCliente = @($v.suyos | Where-Object { ($x.f8 -and (Fono8 ([string]$_.p.celular)) -eq $x.f8) -or (Mismo-Nombre $x.pal $_.pal) }).Count -gt 0
      if ($porSuCliente -or (Comparten $v.pal $x.pal) -ge 2 -or [math]::Abs([double]$g.monto - $m70) -le 1 -or [double]$g.monto -eq $x.monto) { $cz = $x; break }
    }
    if ($cz) {
      $c = $cz.c; $num = ([string]$c.numero) -replace '^N°\s*', ''
      [void]$pagoSinPedido.Add([pscustomobject]@{
        id = $id; tono = 'rojo'; titulo = $g.pagador; monto = $g.monto
        lineas = @($base, "Calza con la cotización $num de $($c.cliente) por $(Plata $cz.monto).")
        acciones = @('cargar', 'descartar')
        cot = [pscustomobject]@{ numero = $num; cliente = [string]$c.cliente; contacto = [string]$c.contacto; monto = $c.monto; producto = [string]$c.producto; concretada = [string]$c.concretada; link = [string]$c.link; canal = [string]$c.canal; abono1 = $g.monto }
      })
      continue
    }
    $pista = if ($v.suyos.Count) { "Es cliente del pedido $($v.suyos[0].p.num), que no tiene un saldo que calce." } else { 'No calza con ningún pedido ni con una venta del Cotizador.' }
    [void]$sinDueno.Add([pscustomobject]@{ id = $id; tono = 'ambar'; titulo = $g.pagador; monto = $g.monto; lineas = @($base, $pista); acciones = @('descartar'); botones = [pscustomobject]@{ descartar = 'Ya sé qué es' } })
  }
}

$grupos = New-Object System.Collections.ArrayList
if ($pagoSinPedido.Count) { [void]$grupos.Add([pscustomobject]@{ k = 'pago_sin_pedido'; titulo = 'Pagó y no hay pedido'; items = $pagoSinPedido.ToArray() }) }
# Una venta que ya salio arriba por su pago no se repite abajo.
$yaArriba = @($pagoSinPedido | ForEach-Object { 'cot:' + $_.cot.numero })
$sp = @($sinPedido | Where-Object { $yaArriba -notcontains $_.id })
if ($sp.Count) { [void]$grupos.Add([pscustomobject]@{ k = 'sin_pedido'; titulo = 'Vendida en el Cotizador y sin pedido'; items = $sp }) }
if ($sinMarcar.Count) { [void]$grupos.Add([pscustomobject]@{ k = 'pago_sin_marcar'; titulo = 'Pago sin marcar en Finanzas'; items = $sinMarcar.ToArray() }) }
if ($sinDueno.Count) { [void]$grupos.Add([pscustomobject]@{ k = 'pago_sin_dueno'; titulo = 'Plata que entró y no sé de quién es'; items = $sinDueno.ToArray() }) }
$total = 0; foreach ($i in $sp) { $total += [double]$i.monto }
$txtCalzan = "Calzan: $calzan de $(@($cot).Count) ventas del Cotizador de los últimos 30 días tienen su pedido"
if ($hayPagos) { $txtCalzan += " y $pagosOk de $pagosVistos pagos de los últimos $DiasPagos días tienen su abono marcado" }
$fuentes = New-Object System.Collections.ArrayList
[void]$fuentes.Add([pscustomobject]@{ nombre = 'Cotizador y Gestión'; cuando = (Get-Date).ToString('o'); viejo = $false })
if ($hayPagos) {
  $vc = $true; if ($est.correo) { $vc = ((Get-Date) - [datetime]$est.correo).TotalHours -gt 36 }
  [void]$fuentes.Add([pscustomobject]@{ nombre = 'Banco · avisos por correo'; cuando = $(if ($est.correo) { [string]$est.correo } else { 'nunca' }); viejo = $vc })
  $vk = $true; $ck = 'nunca'
  if ($est.cartola_hasta) { $ck = 'hasta el ' + (Corta ([string]$est.cartola_hasta)); $vk = ((Dia $Fecha) - (Dia ([string]$est.cartola_hasta))).TotalDays -gt 7 }
  [void]$fuentes.Add([pscustomobject]@{ nombre = 'Banco · cartola completa'; cuando = $ck; viejo = $vk })
}
$res = [pscustomobject]@{
  generado = (Get-Date).ToString('o')
  etapa = $(if ($hayPagos) { 2 } else { 1 })
  grupos = $grupos.ToArray()
  calzan = $txtCalzan + '.'
  fuentes = $fuentes.ToArray()
}
$dir = Split-Path -Parent $Salida; if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
[System.IO.File]::WriteAllText($Salida, ($res | ConvertTo-Json -Depth 10), $utf8)
$tp = 0; foreach ($i in $pagoSinPedido) { $tp += [double]$i.monto }
$tm = 0; foreach ($i in $sinMarcar) { $tm += [double]$i.monto }
Write-Output "OK $Salida sin_pedido=$(@($sp).Count) por=$(Plata $total) calzan=$calzan de=$(@($cot).Count) descartes_nuevos=$nuevos | pagos: vistos=$pagosVistos ok=$pagosOk pago_sin_pedido=$($pagoSinPedido.Count) por=$(Plata $tp) sin_marcar=$($sinMarcar.Count) por=$(Plata $tm) sin_dueno=$($sinDueno.Count) nuevos_en_libro=$pagosNuevosN"
