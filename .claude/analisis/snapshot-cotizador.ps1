# ══════════════════════════════════════════════════════════════
# Casa Zaru · Snapshot semanal del Cotizador
#
# Baja los datos del proyecto Cotizador y deja un resumen agregado listo
# para analizar. Corre solo (tarea de Windows, lunes 08:00) y NO manda nada
# a ninguna parte: escribe archivos locales.
#
# La llave secreta vive FUERA de este repo (el repo es publico), en
# C:\Users\dell\.casazaru\config.ps1 — ver instrucciones ahi.
# En el sistema nuevo de Supabase es una "secret key" (sb_secret_...); en los
# proyectos antiguos era la service_role. Sirven las dos.
#
# Salida: C:\Users\dell\.casazaru\snapshots\AAAA-MM-DD\resumen.json
#         (+ crudo\*.json por si hay que mirar el detalle)
# ══════════════════════════════════════════════════════════════

$ErrorActionPreference = 'Stop'
$INV = [Globalization.CultureInfo]::InvariantCulture

$CFG = "C:\Users\dell\.casazaru\config.ps1"
if (-not (Test-Path $CFG)) { throw "Falta $CFG. Crealo con la URL y la llave secreta." }
. $CFG
if (-not $SB_URL -or -not $SB_KEY -or $SB_KEY -match '^PEGA') {
  throw "Falta pegar la llave secreta en $CFG (Project Settings > API Keys > Secret keys, la que empieza con sb_secret_)."
}
if ($SB_KEY -like 'sb_publishable_*') {
  throw "Esa es la llave PUBLICA. No puede leer cotizaciones y devolveria listas vacias sin avisar. Usa la de Secret keys (sb_secret_...)."
}

$H = @{ apikey = $SB_KEY; Authorization = "Bearer $SB_KEY" }

# PostgREST devuelve 1000 filas por defecto: hay que paginar o se pierde data
# Se pagina con limit/offset y NO con el encabezado Range: PowerShell 5.1
# considera Range un encabezado protegido y tira "se debe modificar con la
# propiedad o metodo adecuados" si se pasa por -Headers.
# El order=id es necesario para que la paginacion sea estable entre paginas.
function Get-Tabla([string]$tabla, [string]$select = '*') {
  $todo = @(); $desde = 0; $paso = 1000
  while ($true) {
    $url = "$SB_URL/rest/v1/$tabla" + "?select=$select&order=id&limit=$paso&offset=$desde"
    # -UserAgent explicito: PowerShell manda por defecto uno que empieza con
    # "Mozilla/5.0" y Supabase lo toma por un navegador, rechazando la llave
    # secreta con "Forbidden use of secret API key in browser".
    #
    # OJO con las dos lineas de abajo: Invoke-RestMethod emite el arreglo JSON
    # como UN SOLO objeto, no fila por fila. Escribir @(Invoke-RestMethod ...)
    # lo envuelve en vez de expandirlo y quedan "1 fila" con las 1000 adentro.
    # Hay que capturarlo en una variable primero y recien ahi normalizar.
    $resp = Invoke-RestMethod -Uri $url -Headers $H -Method Get -UserAgent 'CasaZaru-Analisis/1.0'
    $r = @($resp)
    if ($r.Count -eq 0) { break }
    $todo += $r
    if ($r.Count -lt $paso) { break }
    $desde += $paso
  }
  # la coma es a proposito: sin ella PowerShell desenvuelve el arreglo de una
  # sola fila y .Count queda vacio, y el resumen sale con conteos en blanco
  return ,([object[]]$todo)
}

function AFecha($s) {
  if (-not $s) { return $null }
  try { return [datetime]::Parse($s, $INV, [Globalization.DateTimeStyles]::RoundtripKind) } catch { return $null }
}
function Mediana($nums) {
  $a = @($nums | Where-Object { $_ -ne $null } | Sort-Object)
  if ($a.Count -eq 0) { return $null }
  if ($a.Count % 2) { return [math]::Round($a[[int](($a.Count - 1) / 2)], 1) }
  return [math]::Round((($a[$a.Count / 2 - 1] + $a[$a.Count / 2]) / 2), 1)
}
function Percentil($nums, $p) {
  $a = @($nums | Where-Object { $_ -ne $null } | Sort-Object)
  if ($a.Count -eq 0) { return $null }
  $i = [int][math]::Ceiling($a.Count * $p) - 1
  if ($i -lt 0) { $i = 0 }; if ($i -ge $a.Count) { $i = $a.Count - 1 }
  return [math]::Round($a[$i], 1)
}

Write-Host "Bajando datos..."
$cot = Get-Tabla 'cotizaciones'
$lin = Get-Tabla 'cotizacion_lineas'
$toq = Get-Tabla 'toques'
Write-Host "  cotizaciones: $($cot.Count)  lineas: $($lin.Count)  toques: $($toq.Count)"

$vivas = @($cot | Where-Object { -not $_.eliminada })

# ── ventanas de tiempo ──
$ahora = Get-Date
$sem1 = $ahora.AddDays(-7)     # semana que cierra
$sem2 = $ahora.AddDays(-14)    # la anterior, para comparar

foreach ($c in $vivas) { $c | Add-Member -NotePropertyName _f -NotePropertyValue (AFecha $c.fecha_creacion) -Force }
$estaSem = @($vivas | Where-Object { $_._f -and $_._f -ge $sem1 })
$semPrev = @($vivas | Where-Object { $_._f -and $_._f -ge $sem2 -and $_._f -lt $sem1 })

function ResumenProducto($set) {
  $set | Group-Object producto | ForEach-Object {
    $bajos = @($_.Group | ForEach-Object { [double]$_.total_bajo })
    [pscustomobject]@{
      producto = $_.Name
      n        = $_.Count
      monto_bajo_total = [int]($bajos | Measure-Object -Sum).Sum
      ticket_promedio  = [int]($bajos | Measure-Object -Average).Average
    }
  } | Sort-Object n -Descending
}

# ── lineas: que medidas y que modelos se piden ──
$porId = @{}
foreach ($c in $vivas) { $porId[[string]$c.id] = $c }
$linSem = @($lin | Where-Object {
  $c = $porId[[string]$_.cotizacion_id]; $c -and $c._f -and $c._f -ge $sem1
})

$medidas = $linSem | Where-Object { $_.largo_cm -and $_.ancho_cm } | ForEach-Object {
  $c = $porId[[string]$_.cotizacion_id]
  [pscustomobject]@{ producto = $c.producto; medida = "$([int]$_.largo_cm) x $([int]$_.ancho_cm)" }
} | Group-Object producto, medida | ForEach-Object {
  [pscustomobject]@{ producto = $_.Group[0].producto; medida = $_.Group[0].medida; veces = $_.Count }
} | Sort-Object veces -Descending | Select-Object -First 25

$modelos = $linSem | Where-Object { $_.modelo } | Group-Object modelo |
  ForEach-Object { [pscustomobject]@{ modelo = $_.Name; veces = $_.Count } } |
  Sort-Object veces -Descending | Select-Object -First 20

# ── seguimiento: cuanto se demora el primer toque ──
$primerToque = @{}
foreach ($t in $toq) {
  $k = [string]$t.cotizacion_id; $ts = AFecha $t.ts
  if (-not $ts) { continue }
  if (-not $primerToque.ContainsKey($k) -or $ts -lt $primerToque[$k]) { $primerToque[$k] = $ts }
}
$nToques = @{}
foreach ($t in $toq) { $k = [string]$t.cotizacion_id; $nToques[$k] = [int]$nToques[$k] + 1 }

$horasPrimer = @()
foreach ($c in $vivas) {
  if (-not $c._f) { continue }
  $k = [string]$c.id
  if ($primerToque.ContainsKey($k) -and $c._f -ge $sem1) {
    $horasPrimer += [math]::Round(($primerToque[$k] - $c._f).TotalHours, 1)
  }
}

# ── SIN TOCAR: se cuenta por CLIENTE, no por cotización ──
# Un cliente que pidió 3 cotizaciones y recibió un toque en una sola ESTÁ
# siendo atendido. Contando por cotización las otras 2 aparecían como
# abandonadas y el total salía inflado más del doble (507 "cotizaciones" cuando
# eran 235 clientes). El panel agrupa por cliente: este número tiene que poder
# compararse con lo que muestra el panel.
function ClaveCliente($c) {
  if ($c.contacto) { return ($c.contacto -replace '\s|\+|-', '').ToLower() }
  return ('n:' + $c.cliente).ToLower()
}
$abiertas = @($vivas | Where-Object { -not $_.estado -or $_.estado -eq 'enviada' })
$sinTocar = @($abiertas | Group-Object { ClaveCliente $_ } | ForEach-Object {
  if ($_.Group | Where-Object { $primerToque.ContainsKey([string]$_.id) }) { return }   # ya lo tocaron
  $ult = ($_.Group | Where-Object { $_._f } | Sort-Object _f -Descending)[0]
  if (-not $ult) { return }
  [pscustomobject]@{
    cliente      = $ult.cliente
    cotizaciones = $_.Count
    # monto = suma de TODAS sus cotizaciones abiertas. Exagera cuando el cliente
    # coticé la misma pieza varias veces probando medidas, que es lo normal.
    # monto_max = la cotización individual más grande, mejor proxy de la venta.
    monto        = [int](($_.Group | Measure-Object total_bajo -Sum).Sum)
    monto_max    = [int](($_.Group | Measure-Object total_bajo -Maximum).Maximum)
    dias         = [int]($ahora - $ult._f).TotalDays
    producto     = $ult.producto
    vendedor     = $ult.user_email
    ultimo_numero = $ult.numero
  }
} | Sort-Object monto -Descending)

# por antigüedad, para saber cuánto es cola de hoy y cuánto es backlog viejo
$tramos = @(
  @{ n = '0 a 2 dias'; min = 0; max = 2 }, @{ n = '3 a 7 dias'; min = 3; max = 7 },
  @{ n = '8 a 21 dias'; min = 8; max = 21 }, @{ n = 'mas de 21 dias'; min = 22; max = 999999 })
$sinTocarPorEdad = $tramos | ForEach-Object {
  $s = @($sinTocar | Where-Object { $_.dias -ge $_.min -and $_.dias -le $_.max })
  $t = $_
  $s = @($sinTocar | Where-Object { $_.dias -ge $t.min -and $_.dias -le $t.max })
  [pscustomobject]@{ tramo = $t.n; clientes = $s.Count; monto = [int](($s | Measure-Object monto -Sum).Sum) }
}

$porVendedor = $toq | Where-Object { (AFecha $_.ts) -ge $sem1 } | Group-Object hecho_por |
  ForEach-Object { [pscustomobject]@{ vendedor = $(if ($_.Name) { $_.Name } else { '(sin registrar)' }); toques = $_.Count } } |
  Sort-Object toques -Descending

$resumen = [pscustomobject]@{
  generado           = $ahora.ToString('yyyy-MM-dd HH:mm')
  ventana            = @{ semana_desde = $sem1.ToString('yyyy-MM-dd'); semana_hasta = $ahora.ToString('yyyy-MM-dd') }
  totales            = @{ cotizaciones_historicas = $vivas.Count; lineas_guardadas = $lin.Count; toques_historicos = $toq.Count }
  semana             = @{ n = $estaSem.Count; por_producto = @(ResumenProducto $estaSem) }
  semana_anterior    = @{ n = $semPrev.Count; por_producto = @(ResumenProducto $semPrev) }
  medidas_top        = @($medidas)
  modelos_top        = @($modelos)
  vidrio             = @($estaSem | Where-Object { $_.vidrio_tipo } | Group-Object vidrio_tipo | ForEach-Object { [pscustomobject]@{ tipo = $_.Name; veces = $_.Count } })
  canal              = @($estaSem | Group-Object canal | ForEach-Object { [pscustomobject]@{ canal = $(if ($_.Name) { $_.Name } else { '(directo)' }); veces = $_.Count } })
  estados            = @($vivas | Group-Object estado | ForEach-Object { [pscustomobject]@{ estado = $(if ($_.Name) { $_.Name } else { '(sin estado)' }); n = $_.Count } })
  primer_toque_horas = @{ mediana = (Mediana $horasPrimer); p90 = (Percentil $horasPrimer 0.9); muestra = $horasPrimer.Count }
  sin_tocar          = @{
    unidad      = 'CLIENTES, no cotizaciones — comparable con el panel'
    clientes    = $sinTocar.Count
    monto_total = [int](($sinTocar | Measure-Object monto -Sum).Sum)
    por_edad    = @($sinTocarPorEdad)
    top         = @($sinTocar | Select-Object -First 15)
  }
  toques_por_vendedor = @($porVendedor)
}

$dir = "C:\Users\dell\.casazaru\snapshots\" + $ahora.ToString('yyyy-MM-dd')
New-Item -ItemType Directory -Force -Path "$dir\crudo" | Out-Null

# UTF-8 SIN BOM: Out-File -Encoding utf8 en PS 5.1 escribe BOM y los parsers
# de JSON estrictos se atoran con esos tres bytes al inicio
$sinBom = New-Object System.Text.UTF8Encoding($false)
function Escribir($ruta, $texto) { [IO.File]::WriteAllText($ruta, $texto, $sinBom) }

Escribir "$dir\resumen.json"            ($resumen | ConvertTo-Json -Depth 8)
Escribir "$dir\crudo\cotizaciones.json" ($cot | ConvertTo-Json -Depth 5)
Escribir "$dir\crudo\lineas.json"       ($lin | ConvertTo-Json -Depth 5)
Escribir "$dir\crudo\toques.json"       ($toq | ConvertTo-Json -Depth 5)

# puntero al ultimo, para que la skill sepa cual leer sin adivinar fecha
Escribir "C:\Users\dell\.casazaru\snapshots\ultimo.txt" $dir

Write-Host "Listo -> $dir\resumen.json"
