# Cerebro Zaru - cierra el «Mi día» de una persona del equipo con lo que marcó (17-11-2026).
# Uso (desde Bash):
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .claude/cerebro/cerrar-equipo.ps1 -Fecha 2026-11-17 -Dueno Cote -Marcas <marcas.json>
# marcas.json = el «data» de equipo_marcas de ese día y esa persona, leído TAL CUAL por el MCP del Cotizador
#   ({} si no marcó nada). Forma: { misiones: { <id>: { estado: listo|bloqueada|manana, link, por, ts } }, rutina: { <k>: true } }
# Qué hace con cada misión mostrada ese día:
#   Listo      -> hecho (o vuelve al dueño, si listo-cuando.csv dice al_terminar=vuelve), con el link en «evidencia»
#   Bloqueada  -> esperando hasta fecha + dias_bloqueo, con «Bloqueada dd-mm: <por>» en «evidencia»
#   Mañana o sin marcar -> un salto más
# Deja Cerebro\equipo\<dueño>\ayer.json (lo lee componer-dia.ps1 para tu «Mi día» → Equipo) y suma la rutina a rutina.csv.
# Idempotente (Cerebro\equipo\cierres.txt). Respalda pendientes.csv antes de escribir. Sin datos: el repo es público.
param(
  [Parameter(Mandatory=$true)][string]$Fecha,
  [Parameter(Mandatory=$true)][string]$Dueno,
  [Parameter(Mandatory=$true)][string]$Marcas,
  [string]$Cerebro = 'G:\Mi unidad\Casa Zaru\Cerebro'
)
$ErrorActionPreference = 'Stop'
$cierres = Join-Path $Cerebro 'equipo\cierres.txt'
$clave = "$Fecha $Dueno"
if ((Test-Path -LiteralPath $cierres) -and (Select-String -LiteralPath $cierres -SimpleMatch $clave -Quiet)) { Write-Output "YA_CERRADO $clave"; exit 0 }

$cfg = Get-Content -LiteralPath (Join-Path $Cerebro 'equipo\personas.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$per = @($cfg.personas | Where-Object { $_.dueno -eq $Dueno })[0]
if (-not $per) { Write-Output "SIN_PERSONA $Dueno"; exit 2 }
$diaRuta = Join-Path $Cerebro ("equipo\$Dueno\$Fecha.json")
if (-not (Test-Path -LiteralPath $diaRuta)) { Write-Output "SIN_DIA $clave"; exit 2 }
$dia = Get-Content -LiteralPath $diaRuta -Raw -Encoding UTF8 | ConvertFrom-Json
$m = Get-Content -LiteralPath $Marcas -Raw -Encoding UTF8 | ConvertFrom-Json
$mis = @{}; if ($m -and $m.misiones) { $m.misiones.PSObject.Properties | ForEach-Object { $mis[$_.Name] = $_.Value } }
$vuelve = @{}; $lr = Join-Path $Cerebro 'equipo\listo-cuando.csv'
if (Test-Path -LiteralPath $lr) { Import-Csv -LiteralPath $lr -Encoding UTF8 | ForEach-Object { if ($_.al_terminar -eq 'vuelve') { $vuelve[$_.id] = $true } } }
$dd = $Fecha.Substring(8,2) + '-' + $Fecha.Substring(5,2)
$diasBloq = [int]$per.dias_bloqueo; if ($diasBloq -le 0) { $diasBloq = 3 }
$escSaltos = [int]$per.escalar_saltos; if ($escSaltos -le 0) { $escSaltos = 3 }
$hasta = ([datetime]::ParseExact($Fecha, 'yyyy-MM-dd', $null)).AddDays($diasBloq).ToString('yyyy-MM-dd')
$manana = ([datetime]::ParseExact($Fecha, 'yyyy-MM-dd', $null)).AddDays(1).ToString('yyyy-MM-dd')
function Ev($f, $txt) { if ([string]::IsNullOrWhiteSpace($f.evidencia)) { $f.evidencia = $txt } else { $f.evidencia = ([string]$f.evidencia).TrimEnd() + ' | ' + $txt } }

$pendRuta = Join-Path $Cerebro 'pendientes.csv'
$resp = Join-Path $Cerebro 'respaldos'; if (-not (Test-Path -LiteralPath $resp)) { New-Item -ItemType Directory -Path $resp | Out-Null }
Copy-Item -LiteralPath $pendRuta -Destination (Join-Path $resp ("pendientes-{0}-cierre-equipo.csv" -f (Get-Date -Format 'yyyy-MM-dd-HHmmss')))
$filas = @(Import-Csv -LiteralPath $pendRuta -Encoding UTF8)
$porId = @{}; foreach ($f in $filas) { $porId[$f.id] = $f }

$items = [ordered]@{}; $escalar = @(); $cambios = @(); $listas = 0
$titulos = @{}; foreach ($x in @($dia.data.misiones)) { $titulos[$x.id] = $x.titulo }
foreach ($id in @($dia.mostrados)) {
  $k = $mis[$id]; $est = if ($k) { [string]$k.estado } else { '' }
  if ($est -eq 'listo') { $listas++ }
  $f = $porId[$id]
  if (-not $f) {   # lo fijo del calendario no tiene fila en pendientes.csv: solo se anota
    $items[$id] = $(switch ($est) { 'listo' { 'Listo · con link' } 'bloqueada' { 'Bloqueada: ' + $k.por } default { 'No se hizo' } })
    # Hecho: no vuelve a salir mañana aunque la fecha siga cerca (armar-equipo.ps1 lee este archivo).
    if ($est -eq 'listo') { [IO.File]::AppendAllText((Join-Path $Cerebro "equipo\$Dueno\fijo-hechos.txt"), "$id`r`n", (New-Object System.Text.UTF8Encoding($false))) }
    $cambios += "$id $(if ($est) { $est } else { 'sin marcar' })"; continue
  }
  switch ($est) {
    'listo' {
      Ev $f ("Listo $dd ($Dueno): " + $k.link); $f.ultima_verificacion = $Fecha
      if ($vuelve.ContainsKey($id)) {
        $f.dueno = 'yo'; $f.estado = 'abierto'; $f.saltos = '0'; $f.proxima_revision = $manana
        $items[$id] = 'Listo · vuelve a ti para decidir'
        $escalar += [pscustomobject]@{ id=$id; dueno="yo"; titulo=$f.titulo; porque=("$Dueno lo dejó listo para que decidas: " + $k.link) }
        $cambios += "$id listo, vuelve al dueño"
      } else {
        $f.estado = 'hecho'; $items[$id] = 'Listo · con link'; $cambios += "$id hecho"
      }
    }
    'bloqueada' {
      $f.estado = 'esperando'; $f.proxima_revision = $hasta; Ev $f ("Bloqueada ${dd}: " + $k.por)
      $items[$id] = 'Bloqueada: ' + $k.por; $cambios += "$id bloqueada"
      if ($per.bloqueo_dueno -and ([string]$k.por -match $per.bloqueo_dueno)) {
        $escalar += [pscustomobject]@{ id=$id; dueno=$Dueno; titulo=$f.titulo; porque=("$Dueno está esperando por ti: " + $k.por) }
      }
    }
    default {
      $s = 0; [int]::TryParse([string]$f.saltos, [ref]$s) | Out-Null; $s++; $f.saltos = [string]$s
      $items[$id] = $(if ($est -eq 'manana') { 'Pasó a mañana' } else { 'Sin marcar' }) + " · $s.º salto"
      $cambios += "$id salto $s"
      if ($s -ge $escSaltos) { $escalar += [pscustomobject]@{ id=$id; dueno=$Dueno; titulo=$f.titulo; porque=("$Dueno la ha saltado $s veces: hacerla, pasarla a otra persona o matarla.") } }
    }
  }
}
$filas | Export-Csv -LiteralPath $pendRuta -NoTypeInformation -Encoding UTF8

# Rutina del día
$rut = @($dia.data.rutina); $hechas = 0
if ($m -and $m.rutina) { foreach ($r in $rut) { if ($m.rutina.($r.k)) { $hechas++ } } }
$rr = Join-Path $Cerebro "equipo\$Dueno\rutina.csv"
if (-not (Test-Path -LiteralPath $rr)) { [IO.File]::WriteAllText($rr, "fecha,hechas,total,misiones_listas,misiones`r`n", (New-Object System.Text.UTF8Encoding($false))) }
[IO.File]::AppendAllText($rr, ("{0},{1},{2},{3},{4}`r`n" -f $Fecha, $hechas, $rut.Count, $listas, @($dia.mostrados).Count), (New-Object System.Text.UTF8Encoding($false)))

$ayer = [pscustomobject]@{
  fecha = $Fecha; listas = $listas; total = @($dia.mostrados).Count; rutina = "$hechas/$($rut.Count)"
  items = [pscustomobject]$items; escalar = $escalar
}
[IO.File]::WriteAllText((Join-Path $Cerebro "equipo\$Dueno\ayer.json"), ($ayer | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))

$enc = New-Object System.Text.UTF8Encoding($true)
$lin = "`r`n## $Fecha · día de $Dueno`r`n- " + $(if ($cambios.Count) { $cambios -join '; ' } else { 'Sin misiones.' }) + "`r`n- Rutina $hechas/$($rut.Count)." +
  $(if ($escalar.Count) { "`r`n- Sube a Decidir: " + (($escalar | ForEach-Object { $_.id }) -join ', ') } else { '' }) + "`r`n"
[IO.File]::AppendAllText((Join-Path $Cerebro 'bitacora.md'), $lin, $enc)
[IO.File]::AppendAllText($cierres, "$clave`r`n", (New-Object System.Text.UTF8Encoding($false)))
Write-Output ("CERRADO {0} listas={1}/{2} rutina={3}/{4} escalar={5}" -f $clave, $listas, @($dia.mostrados).Count, $hechas, $rut.Count, (($escalar | ForEach-Object { $_.id }) -join ','))
