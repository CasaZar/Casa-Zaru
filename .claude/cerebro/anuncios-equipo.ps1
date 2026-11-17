# Cerebro Zaru - semáforo de anuncios activos de Meta para el «Mi día» de marketing (18-11-2026).
# Uso (desde Bash), los lunes o cuando Cerebro\equipo\anuncios.json tenga más de 7 días:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .claude/cerebro/anuncios-equipo.ps1 -Fecha 2026-11-18 -Entrada <meta-ads.json>
# meta-ads.json = respuesta TAL CUAL de ads_get_ad_entities (cuenta 1393145254729847, level=ad, date_preset=last_7d,
#   effective_status IN [ACTIVE], sort amount_spent_descending, fields id,name,adset_name,amount_spent,results,
#   cost_per_result,frequency). Acepta el objeto entero ({ad_entities:"<json>"}) o el arreglo ya leído.
# Reglas (todas aquí, ningún color se pone a mano):
#   Chats de WhatsApp: verde si el costo por chat <= 1,25 x el promedio de los anuncios de chat; si no, ámbar.
#   Compra web: verde si hubo compras; rojo si gastó >= $30.000 en 7 días sin compras; si no, ámbar.
#   Frecuencia >= 3: un verde baja a ámbar («se está repitiendo»).
# No escribe montos de gasto ni presupuestos: solo el color y el dato que lo explica. Sin datos en el repo.
param(
  [Parameter(Mandatory=$true)][string]$Fecha,
  [Parameter(Mandatory=$true)][string]$Entrada,
  [int]$Max = 8,
  [int]$RojoGasto = 30000,
  [string]$Cerebro = 'G:\Mi unidad\Casa Zaru\Cerebro'
)
$ErrorActionPreference = 'Stop'
function N($v) { $n = 0.0; if ([double]::TryParse(([string]$v), [Globalization.NumberStyles]::Any, [Globalization.CultureInfo]::InvariantCulture, [ref]$n)) { $n } else { $null } }
function Pesos($v) { '$' + ([math]::Round($v)).ToString('N0', [Globalization.CultureInfo]::GetCultureInfo('es-CL')) }

$raw = Get-Content -LiteralPath $Entrada -Raw -Encoding UTF8 | ConvertFrom-Json
if ($raw.ad_entities -is [string]) { $ads = @($raw.ad_entities | ConvertFrom-Json | ForEach-Object { $_ }) }
elseif ($raw.ad_entities) { $ads = @($raw.ad_entities | ForEach-Object { $_ }) }
else { $ads = @($raw | ForEach-Object { $_ }) }   # en PS 5.1 un arreglo JSON llega como un solo objeto

$filas = foreach ($a in $ads) {
  $ind = [string]$a.results.indicator
  $res = $null
  if ($a.results.values) { $res = N (@($a.results.values)[0].value) } elseif ($a.results.value -ne $null) { $res = N $a.results.value }
  [pscustomobject]@{
    nombre = [string]$a.name; conjunto = [string]$a.adset_name
    gasto = [double](N $a.amount_spent.value); res = $res; cpr = (N $a.cost_per_result.value); frec = (N $a.frequency)
    tipo = $(if ($ind -match 'messaging') { 'chat' } elseif ($ind -match 'purchase') { 'web' } else { 'otro' })
  }
}
$filas = @($filas | Sort-Object gasto -Descending)
$chats = @($filas | Where-Object { $_.tipo -eq 'chat' -and $_.res -gt 0 })
$prom = $null; if ($chats.Count) { $prom = ($chats | Measure-Object gasto -Sum).Sum / ($chats | Measure-Object res -Sum).Sum }

$items = foreach ($f in ($filas | Select-Object -First $Max)) {
  $color = 'gris'; $dato = 'sin dato comparable'
  if ($f.tipo -eq 'chat') {
    if ($f.res -gt 0) {
      $c = $f.gasto / $f.res
      $color = $(if ($prom -and $c -le 1.25 * $prom) { 'verde' } else { 'ambar' })
      $dato = ('{0} chats · {1} c/u' -f [int]$f.res, (Pesos $c))
    } else { $color = 'ambar'; $dato = 'sin chats en 7 días' }
  } elseif ($f.tipo -eq 'web') {
    if ($f.res -gt 0) { $color = 'verde'; $dato = ('{0} compras web' -f [int]$f.res) }
    elseif ($f.gasto -ge $RojoGasto) { $color = 'rojo'; $dato = '0 compras web en 7 días' }
    else { $color = 'ambar'; $dato = 'sin compras web todavía' }
  }
  if ($f.frec -ne $null -and $f.frec -ge 3) {
    if ($color -eq 'verde') { $color = 'ambar' }
    $dato += (' · se está repitiendo (frecuencia {0})' -f ([math]::Round($f.frec, 1)).ToString([Globalization.CultureInfo]::GetCultureInfo('es-CL')))
  }
  [pscustomobject]@{ nombre = $f.nombre; conjunto = $f.conjunto; color = $color; dato = $dato }
}
$nota = 'Últimos 7 días, de más a menos gasto. Rojo = gastó más de ' + (Pesos $RojoGasto) + ' sin una compra web. ' +
  'Las compras web son las que ve el píxel: muchas ventas de estos anuncios entran por WhatsApp y no aparecen aquí. ' +
  'Solo para mirar y proponer: pausar o subir lo decide Tomás.'
$out = [pscustomobject]@{ fecha = $Fecha; activos = $filas.Count; items = @($items); nota = $nota }
$dir = Join-Path $Cerebro 'equipo'; if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
[IO.File]::WriteAllText((Join-Path $dir 'anuncios.json'), ($out | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
Write-Output ('OK anuncios={0} activos={1} verde={2} ambar={3} rojo={4}' -f @($items).Count, $filas.Count,
  @($items | Where-Object { $_.color -eq 'verde' }).Count, @($items | Where-Object { $_.color -eq 'ambar' }).Count, @($items | Where-Object { $_.color -eq 'rojo' }).Count)
