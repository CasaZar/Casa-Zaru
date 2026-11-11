# marketing-json.ps1 · arma marketing.json para la pestaña «Marketing» del panel (11-11-2026)
#
# Lee de Drive (Revision WhatsApp): temas-marketing.md, contenido-rrss.md, reglas-marketing.md
# y el análisis del lunes más reciente (las 10 preguntas). Para cada ficha con una línea
# «**Fototeca:** <búsqueda>» elige las 4 mejores fotos del índice de la Fototeca.
# El resultado NO va al repo (es público): queda en -Salida y se sube al bucket privado
# «marketing» del Cotizador desde el panel (sesión admin). Ver la skill revision-whatsapp.
#
#   powershell -ExecutionPolicy Bypass -File .claude\scripts\marketing-json.ps1 [-Salida <ruta>] [-Buscar "<q>"]
#
# -Buscar solo cuenta cuántas fotos trae una búsqueda (para elegir la de una ficha).
param(
  [string]$RW = 'G:\Mi unidad\Casa Zaru\Revision WhatsApp',
  [string]$Datos = 'G:\Mi unidad\Casa Zaru\Biblioteca\Clasificacion 2026-11\fototeca-datos.json',
  [string]$Salida = (Join-Path $env:TEMP 'marketing.json'),
  [string]$Buscar = ''
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object Text.UTF8Encoding($false)
function Leer($p) { [IO.File]::ReadAllText($p, $utf8) }
function Norm([string]$s) {
  if (-not $s) { return '' }
  $s = $s.ToLowerInvariant().Normalize([Text.NormalizationForm]::FormD)
  return [regex]::Replace($s, '\p{Mn}', '')
}

# ── índice de la Fototeca: texto normalizado por pieza (como filtrar() de fototeca.html) ──
Add-Type -AssemblyName System.Web.Extensions
$jss = New-Object Web.Script.Serialization.JavaScriptSerializer
$jss.MaxJsonLength = 100MB
$fot = $jss.DeserializeObject((Leer $Datos))
$piezas = New-Object Collections.Generic.List[object]
foreach ($d in $fot['items']) {
  if ($d['uso'] -eq 'descartar') { continue }
  if ("$($d['ia'])" -match '^s') { continue }          # sin piezas marcadas IA
  $et = if ($d['etiquetas']) { ($d['etiquetas'] -join ' ') } else { '' }
  $txt = Norm ((@($d['id'], $d['producto'], $d['madera'], $d['tipo'], $d['etapa'], $d['ambiente'], $d['forma'], $d['uso'], $d['descripcion'], $d['gancho'], $d['que_pasa'], $et, $d['anio']) | ForEach-Object { "$_" }) -join ' ')
  $piezas.Add(@{ d = $d; t = $txt; c = [int]("0" + $d['calidad']) })
}
function Fotos([string]$q, [int]$n) {
  $toks = (Norm $q).Split(' ', [StringSplitOptions]::RemoveEmptyEntries)
  $r = New-Object Collections.Generic.List[object]
  foreach ($p in $piezas) {
    $ok = $true
    foreach ($t in $toks) { if ($p.t.IndexOf($t) -lt 0) { $ok = $false; break } }
    if ($ok) { $r.Add($p) }
  }
  $orden = @($r | Sort-Object { -$_.c }, { if ($_.d['personas']) { 1 } else { 0 } })
  return @{ total = $r.Count; top = @($orden | Select-Object -First $n) }
}
if ($Buscar) { $x = Fotos $Buscar 4; "«$Buscar»: $($x.total) piezas"; $x.top | ForEach-Object { "  $($_.d['id']) c$($_.c) $($_.d['descripcion'])" }; return }

# ── fichas de temas-marketing.md ──
$tm = Leer (Join-Path $RW 'temas-marketing.md')
$fichas = @(); $candidatos = @()
$bloques = [regex]::Split($tm, '(?m)^### ')
foreach ($b in $bloques | Select-Object -Skip 1) {
  $lineas = $b -split "`r?`n"
  $cab = $lineas[0]
  $m = [regex]::Match($cab, '^(\d+)\s*·\s*(.+?)\s*—\s*(\S+)\s*(\S*)')
  if (-not $m.Success) { continue }
  $campos = @{}; $k = $null
  foreach ($l in $lineas | Select-Object -Skip 1) {
    if ($l -match '^## ') { break }
    $mm = [regex]::Match($l, '^\*\*(.+?):\*\*\s*(.*)$')
    if ($mm.Success) { $k = $mm.Groups[1].Value; $campos[$k] = $mm.Groups[2].Value }
    elseif ($k -and $l.Trim()) { $campos[$k] += ' ' + $l.Trim() }
  }
  $ev = "$($campos['Evidencia'])"
  $cita = ''; $mc = [regex]::Match($ev, 'Cita:\s*«(.+?)»')
  if ($mc.Success) { $cita = $mc.Groups[1].Value; $ev = $ev.Substring(0, $mc.Index).Trim() }
  $estado = "$($campos['Estado'])"
  $falta = ''; $mf = [regex]::Match($estado, 'Falta:\s*(.+)$')
  if ($mf.Success) { $falta = $mf.Groups[1].Value.Trim() }
  $est = ([regex]::Match($estado, '^\s*([a-záéíóú]+)')).Groups[1].Value
  if (-not $est) { $est = $m.Groups[3].Value }
  $q = "$($campos['Fototeca'])".Trim()
  $foto = $null
  if ($q) {
    $x = Fotos $q 4
    $foto = @{ q = $q; total = $x.total; fotos = @($x.top | ForEach-Object { @{ id = $_.d['id']; s = $_.d['s']; x = $_.d['x']; y = $_.d['y']; d = "$($_.d['descripcion'])" } }) }
  }
  $fichas += [ordered]@{
    n = [int]$m.Groups[1].Value; titulo = $m.Groups[2].Value.Trim(); estado = $est.ToLower(); fecha = $m.Groups[4].Value
    evidencia = $ev; cita = $cita; correo = "$($campos['Correo'])"; redes = "$($campos['Redes'])"
    anuncio = "$($campos['Anuncio Meta'])"; falta = $falta; fototeca = $foto
  }
}
$mcand = [regex]::Match($tm, '(?ms)^## Candidatos.*?$(.*?)(?=^## |\z)')
if ($mcand.Success) {
  foreach ($l in [regex]::Matches($mcand.Groups[1].Value, '(?ms)^- (.+?)(?=^- |\z)')) {
    $t = ($l.Groups[1].Value -replace '\s+', ' ').Trim()
    $mt = [regex]::Match($t, '^(\d\d-\d\d)\s*·\s*(.+)$')
    if ($mt.Success) { $candidatos += [ordered]@{ fecha = $mt.Groups[1].Value; texto = $mt.Groups[2].Value } } else { $candidatos += [ordered]@{ fecha = ''; texto = $t } }
  }
}

# ── ideas para redes (tabla de contenido-rrss.md) ──
$ideas = @()
foreach ($l in (Leer (Join-Path $RW 'contenido-rrss.md')) -split "`r?`n") {
  if ($l -notmatch '^\|' -or $l -match '^\|\s*Idea\s*\|' -or $l -match '^\|\s*-') { continue }
  $c = $l.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() }
  if ($c.Count -lt 5) { continue }
  $ideas += [ordered]@{ idea = $c[0]; gancho = $c[1].Trim('«', '»'); formato = $c[2]; fuente = $c[3]; permiso = $c[4] }
}

# ── 10 preguntas del análisis del lunes más reciente (sin la columna de casos: trae nombres) ──
$preguntas = @(); $analisis = ''
$al = Get-ChildItem $RW -Filter 'analisis-lunes-*.md' | Sort-Object Name -Descending | Select-Object -First 1
if ($al) {
  $analisis = $al.BaseName -replace 'analisis-lunes-', ''
  $sec = [regex]::Match((Leer $al.FullName), '(?ms)^## Las 10 preguntas.*?$(.*?)(?=^## |\z)').Groups[1].Value
  foreach ($l in $sec -split "`r?`n") {
    $mp = [regex]::Match($l, '^\|\s*(\d+)\s*\|\s*(.+?)\s*\|.*\|\s*(.+?)\s*\|\s*$')
    if ($mp.Success) { $preguntas += [ordered]@{ n = [int]$mp.Groups[1].Value; pregunta = $mp.Groups[2].Value; modelo = -not ($mp.Groups[3].Value -match 'hueco') } }
  }
}

# ── reglas ──
$reglas = @(); $g = $null
foreach ($l in (Leer (Join-Path $RW 'reglas-marketing.md')) -split "`r?`n") {
  if ($l -match '^## (.+)$') { $g = [ordered]@{ titulo = $Matches[1].Trim(); items = @() }; $reglas += $g; continue }
  if ($g -and $l -match '^- (.+)$') { $g.items += $Matches[1].Trim() }
}

$fecha = ([regex]::Match($tm, 'propuesto (\d\d-\d\d)')).Groups[1].Value
$out = [ordered]@{
  generado = (Get-Date -Format 'yyyy-MM-dd HH:mm'); analisis = $analisis
  fototeca = @{ celda = $fot['meta']['celda']; cols = $fot['meta']['cols']; filas = $fot['meta']['filas'] }
  fichas = $fichas; candidatos = $candidatos; ideas = $ideas; preguntas = $preguntas; reglas = $reglas
}
[IO.File]::WriteAllText($Salida, ($out | ConvertTo-Json -Depth 10 -Compress), $utf8)
"marketing.json: $($fichas.Count) fichas, $($candidatos.Count) candidatos, $($ideas.Count) ideas, $($preguntas.Count) preguntas, $($reglas.Count) grupos de reglas → $Salida"
$fichas | ForEach-Object { "  ficha $($_.n) «$($_.titulo)»: " + $(if ($_.fototeca) { "$($_.fototeca.total) fotos para «$($_.fototeca.q)»" } else { 'sin búsqueda de Fototeca' }) }
