# Cerebro Zaru - arma el «Mi día» de cada persona del equipo que tiene día propio (17-11-2026).
# Uso (desde Bash), DESPUÉS de armar-dia.ps1 y ANTES de componer-dia.ps1:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .claude/cerebro/armar-equipo.ps1 -Fecha 2026-11-17 -Calc <calc.json> [-Pulso <marketing.json>] [-Contenido <contenido.json>]
# Además (18-11-2026): «Para contenido» (sql/gestion-contenido-semana.sql), anuncios activos (Cerebro\equipo\anuncios.json,
# de anuncios-equipo.ps1) y «su semana» (rutina.csv). Contenido y anuncios solo si personas.json los activa para esa persona.
# Personas: Cerebro\equipo\personas.json (Drive). Definición de «listo»: Cerebro\equipo\listo-cuando.csv.
# Escribe Cerebro\equipo\<dueño>\<fecha>.json = { correo, fecha, mostrados, data } (lo que se publica va en data).
# Solo lee pendientes.csv: no escribe nada fuera de Cerebro\equipo\. Este archivo no lleva datos: el repo es público.
param(
  [Parameter(Mandatory=$true)][string]$Fecha,
  [string]$Calc = '',
  # Resultado TAL CUAL de sql/cotizador-marketing.sql: [{o, ayer, semana}]
  [string]$Pulso = '',
  [string]$WhatsApp = 'G:\Mi unidad\Casa Zaru\Revision WhatsApp\mi-dia-whatsapp.json',
  # Resultado TAL CUAL de sql/gestion-contenido-semana.sql (18-11-2026): lo que sale del taller esta semana.
  [string]$Contenido = '',
  [string]$Cerebro = 'G:\Mi unidad\Casa Zaru\Cerebro'
)
$ErrorActionPreference = 'Stop'
$hoy = [datetime]::ParseExact($Fecha, 'yyyy-MM-dd', $null)
function Leer($p) { Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json }
function Num($v) { $n = 0.0; if ([double]::TryParse(([string]$v), [Globalization.NumberStyles]::Any, [Globalization.CultureInfo]::InvariantCulture, [ref]$n)) { $n } else { 0 } }
function Dias($iso) { if (-not $iso) { return $null }; try { [int]([datetime]::ParseExact(([string]$iso).Substring(0,10), 'yyyy-MM-dd', $null) - $hoy).TotalDays } catch { $null } }

$cfg = Leer (Join-Path $Cerebro 'equipo\personas.json')
$pend = @(Import-Csv -LiteralPath (Join-Path $Cerebro 'pendientes.csv') -Encoding UTF8)
$areas = @{}; Import-Csv -LiteralPath (Join-Path $Cerebro 'areas.csv') -Encoding UTF8 | ForEach-Object { $areas[$_.area] = $_.nombre }
$listo = @{}; $lcRuta = Join-Path $Cerebro 'equipo\listo-cuando.csv'
if (Test-Path -LiteralPath $lcRuta) { Import-Csv -LiteralPath $lcRuta -Encoding UTF8 | ForEach-Object { $listo[$_.id] = $_.listo_cuando } }
$c = $null; if ($Calc -and (Test-Path -LiteralPath $Calc)) { $c = Leer $Calc }
$wa = $null; if ($WhatsApp -and (Test-Path -LiteralPath $WhatsApp)) { $wa = Leer $WhatsApp }
$pu = $null; if ($Pulso -and (Test-Path -LiteralPath $Pulso)) { $pu = @(Leer $Pulso | ForEach-Object { $_ }) }  # en PS 5.1 un arreglo JSON llega como un solo objeto

# «Para contenido» (18-11-2026): una fila por pedido, solo producto, medidas, madera y comuna.
$ti = [Globalization.CultureInfo]::GetCultureInfo('es-CL').TextInfo
function Lindo($s) { $t = ([string]$s).Trim(); if (-not $t) { return '' }; $ti.ToTitleCase($t.ToLower()) }
$paraCont = @()
if ($Contenido -and (Test-Path -LiteralPath $Contenido)) {
  $lin = @(Leer $Contenido | ForEach-Object { $_ })
  foreach ($g in ($lin | Group-Object num)) {
    $ls = @($g.Group)
    $prods = foreach ($pg in ($ls | Group-Object { (([string]$_.producto) -split ' — ')[0].Trim() })) {
      $cant = ($pg.Group | ForEach-Object { Num $_.cantidad } | Measure-Object -Sum).Sum
      $med = ''; if ($pg.Count -eq 1 -and $pg.Group[0].largo -and $pg.Group[0].ancho) { $med = ' ' + $pg.Group[0].largo + ' × ' + $pg.Group[0].ancho }
      $pg.Name + $med + $(if ($cant -gt 1) { ' (' + $cant.ToString([Globalization.CultureInfo]::GetCultureInfo('es-CL')) + ')' } else { '' })
    }
    $mad = (@($ls | ForEach-Object { Lindo $_.madera } | Where-Object { $_ } | Select-Object -Unique)) -join ' y '
    $com = @($ls | ForEach-Object { [string]$_.comuna } | Where-Object { $_ } | Select-Object -First 1)
    $paraCont += [pscustomobject]@{ num=[string]$g.Name; titulo=(@($prods) -join ' + '); detalle=((@($mad) + $com | Where-Object { $_ }) -join ' · ') }
  }
}
# Anuncios activos (anuncios-equipo.ps1, los lunes): se muestran si tienen 7 días o menos.
$anuncios = $null; $anRuta = Join-Path $Cerebro 'equipo\anuncios.json'
if (Test-Path -LiteralPath $anRuta) { $an = Leer $anRuta; $da = Dias $an.fecha; if ($da -ne $null -and $da -le 0 -and $da -ge -7) { $anuncios = $an } }
# Carruseles listos en Canva (26-11-2026, skill /carrusel): Cerebro\equipo\carruseles.json, uno por carrusel
# {dueno, titulo, detalle, link, estado}. Se muestran mientras estado no sea «publicado».
$carruseles = @(); $caRuta = Join-Path $Cerebro 'equipo\carruseles.json'
if (Test-Path -LiteralPath $caRuta) { $carruseles = @((Leer $caRuta).items | Where-Object { $_.estado -ne 'publicado' }) }

foreach ($p in @($cfg.personas)) {
  $max = [int]$p.max_misiones; if ($max -le 0) { $max = 3 }
  $maxCola = [int]$p.max_cola; if ($maxCola -le 0) { $maxCola = 8 }
  $mias = @($pend | Where-Object { $_.dueno -eq $p.dueno })

  # Bloqueadas: «esperando» hasta su próxima revisión; cumplida la fecha, vuelven a la fila.
  $bloq = @(); $abiertas = @()
  foreach ($f in $mias) {
    if ($f.estado -eq 'abierto') { $abiertas += $f; continue }
    if ($f.estado -ne 'esperando') { continue }
    $dr = Dias $f.proxima_revision
    if ($dr -ne $null -and $dr -le 0) { $abiertas += $f; continue }
    $por = ''; $m = [regex]::Matches([string]$f.evidencia, 'Bloqueada \d\d-\d\d: ([^|]+)'); if ($m.Count) { $por = $m[$m.Count-1].Groups[1].Value.Trim() }
    $bloq += [pscustomobject]@{ id=$f.id; titulo=$f.titulo; por=$por }
  }

  # Orden: lo que vence primero; sin vencimiento, lo de más impacto y más saltos; al final lo más antiguo.
  $orden = @($abiertas | Sort-Object `
    @{e={ if ($_.vence) { 0 } else { 1 } }}, @{e={ [string]$_.vence }}, `
    @{e={ Num $_.'impacto_$' }; Descending=$true}, @{e={ Num $_.saltos }; Descending=$true}, @{e={ [string]$_.creado }})

  # Lo fijo de la persona que toca hoy o mañana entra como misión (va primero).
  $fijoP = @(); if ($c -and $c.fijo) { $fijoP = @($c.fijo | Where-Object { $_.dueno -eq $p.dueno }) }
  $misiones = New-Object System.Collections.ArrayList
  $fh = Join-Path $Cerebro ('equipo\' + $p.dueno + '\fijo-hechos.txt')
  $fijoHecho = @(); if (Test-Path -LiteralPath $fh) { $fijoHecho = @(Get-Content -LiteralPath $fh -Encoding UTF8 | ForEach-Object { $_.Trim() }) }
  foreach ($x in ($fijoP | Where-Object { (Dias $_.fecha) -ne $null -and (Dias $_.fecha) -le 1 -and (Dias $_.fecha) -ge 0 })) {
    if ($misiones.Count -ge $max) { break }
    if ($fijoHecho -contains ('fijo:' + $x.area + ':' + $x.fecha)) { continue }
    [void]$misiones.Add([pscustomobject]@{ id=('fijo:' + $x.area + ':' + $x.fecha); area=$x.area; area_nombre=$areas[$x.area]; titulo=$x.obligacion;
      listo_cuando='está hecho y pegas el link donde se ve.'; vence=$x.fecha; dias=(Dias $x.fecha); saltos=0 })
  }
  foreach ($f in $orden) {
    if ($misiones.Count -ge $max) { break }
    [void]$misiones.Add([pscustomobject]@{ id=$f.id; area=$f.area; area_nombre=$areas[$f.area]; titulo=$f.titulo;
      listo_cuando=$(if ($listo.ContainsKey($f.id)) { $listo[$f.id] } else { 'pegas el link donde se ve hecho.' });
      vence=$f.vence; dias=(Dias $f.vence); saltos=[int](Num $f.saltos) })
  }
  $ids = @($misiones | ForEach-Object { $_.id })
  $cola = @($orden | Where-Object { $ids -notcontains $_.id } | Select-Object -First $maxCola | ForEach-Object { [pscustomobject]@{ id=$_.id; titulo=$_.titulo } })

  $dow = [int]$hoy.DayOfWeek
  $rutina = @($p.rutina | Where-Object { -not $_.dias -or (@($_.dias) -contains $dow) } | ForEach-Object { [pscustomobject]@{ k=$_.k; label=$_.label; cuando=$_.cuando } })

  $pulsoDia = $null
  if ($p.pulso_marketing) {
    $cif = @()
    if ($pu) {
      $v = @{}; foreach ($r in $pu) { $v[[string]$r.o] = $r }
      foreach ($par in @(@('meta','desde Meta'), @('google','desde Google'), @('web','por la web, sin anuncio'), @('sin_origen','sin origen registrado'))) {
        $r = $v[$par[0]]
        $cif += [pscustomobject]@{ label=$par[1]; valor=$(if ($r) { [int]$r.ayer } else { 0 }); comp=('7 días: ' + $(if ($r) { [int]$r.semana } else { 0 })) }
      }
    }
    if ($wa -and $wa.conteos -and ($wa.conteos.nuevas -ne $null)) {
      $cif += [pscustomobject]@{ label='chats nuevos de WhatsApp'; valor=[int]$wa.conteos.nuevas; comp=[string]$wa.conteos.dia }
    }
    if ($cif.Count) { $pulsoDia = [pscustomobject]@{ titulo='Pulso de marketing · cotizaciones de ayer'; cifras=$cif;
      nota=$(if ($pu) { '«Sin origen» = la cotización no trae de dónde vino. Sale de la base del cotizador.' } else { 'Cotizaciones por origen: sin dato hoy.' }) } }
  }

  # Ideas para redes: solo si la revisión de WhatsApp es de los últimos 2 días.
  $ideas = @()
  if ($wa -and $wa.ideas -and $wa.revision) {
    $rev = [datetime]::Parse(([string]$wa.revision).Substring(0,10))
    if (($hoy - $rev).TotalDays -le 2) { $ideas = @($wa.ideas | Select-Object -First 4) }
  }
  $fijo = @($fijoP | Where-Object { (Dias $_.fecha) -ge 0 } | Select-Object -First 6 | ForEach-Object { [pscustomobject]@{ fecha=$_.fecha; obligacion=$_.obligacion } })

  # Su semana (18-11-2026): de lunes a ayer, desde rutina.csv (lo escribe cerrar-equipo.ps1). Nada se estima.
  $semana = $null
  $lunes = $hoy.AddDays(-(([int]$hoy.DayOfWeek + 6) % 7)).ToString('yyyy-MM-dd')
  $rr = Join-Path $Cerebro ('equipo\' + $p.dueno + '\rutina.csv')
  if (Test-Path -LiteralPath $rr) {
    $sem = @(Import-Csv -LiteralPath $rr -Encoding UTF8 | Where-Object { $_.fecha -ge $lunes -and $_.fecha -lt $Fecha })
    if ($sem.Count) {
      $metaReels = 0; foreach ($r in @($p.rutina | Where-Object { $_.k -match 'reel' })) { $metaReels += $(if ($r.dias) { @($r.dias).Count } else { 6 }) }
      $semana = [pscustomobject]@{ desde = $lunes; dias = $sem.Count
        listas = [int]($sem | ForEach-Object { Num $_.misiones_listas } | Measure-Object -Sum).Sum
        misiones = [int]($sem | ForEach-Object { Num $_.misiones } | Measure-Object -Sum).Sum
        rutina = [int]($sem | ForEach-Object { Num $_.hechas } | Measure-Object -Sum).Sum
        rutina_total = [int]($sem | ForEach-Object { Num $_.total } | Measure-Object -Sum).Sum
        reels = [int]($sem | ForEach-Object { Num $_.reels } | Measure-Object -Sum).Sum; reels_meta = $metaReels }
    }
  }

  $data = [pscustomobject]@{
    fecha = $Fecha; nombre = $p.nombre; generado = (Get-Date).ToString('o')
    misiones = @($misiones); cola = $cola; bloqueadas = $bloq; rutina = $rutina
    pulso = $pulsoDia; ideas = $ideas; fijo = $fijo; semana = $semana
    contenido = $(if ($p.contenido) { @($paraCont) } else { @() })
    anuncios = $(if ($p.anuncios) { $anuncios } else { $null })
    carruseles = @($carruseles | Where-Object { $_.dueno -eq $p.dueno } | ForEach-Object { [pscustomobject]@{ titulo=$_.titulo; detalle=$_.detalle; link=$_.link } })
  }
  $dir = Join-Path $Cerebro ('equipo\' + $p.dueno); if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  $sal = Join-Path $dir "$Fecha.json"
  $obj = [pscustomobject]@{ correo = ([string]$p.correo).ToLower(); fecha = $Fecha; mostrados = $ids; data = $data }
  [System.IO.File]::WriteAllText($sal, ($obj | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
  Write-Output ("OK {0} misiones={1} cola={2} bloqueadas={3} rutina={4} pulso={5} contenido={6} anuncios={7} semana={8}" -f $p.dueno, $misiones.Count, $cola.Count, $bloq.Count, $rutina.Count, [bool]$pulsoDia, @($data.contenido).Count, $(if ($data.anuncios) { @($data.anuncios.items).Count } else { 0 }), [bool]$semana)
}
