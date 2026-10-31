# Fuentes compartidas de las planillas "por mes" (madera, Starken, sueldos, bencina, publicidad).
# Nada privado vive acá: nombres, RUT y rutas de datos van en `Casa Zaru Planillas\por-mes\config.ps1` (fuera del repo).
#
#   $Anio      año que se arma (por defecto el del mes pasado)
#   $HastaMes  último mes con hoja: el mayor con datos, sin pasar del mes en curso
#
# Cartolas: se unen TODAS las de Descargas (BCI 7175 y Banco de Chile de Muvale) sin repetir movimientos, y se guardan en
# un caché en %LOCALAPPDATA%\CasaZaru\por-mes que se rehace cuando aparece una cartola más nueva.
$INV = [Globalization.CultureInfo]::InvariantCulture
$CL = [Globalization.CultureInfo]::GetCultureInfo('es-CL')
$PL = 'C:\Users\dell\Casa Zaru Planillas'; $CZ = "$env:USERPROFILE\.casazaru"
$PRIV = Join-Path $PL 'por-mes'
$CACHE = Join-Path $env:LOCALAPPDATA 'CasaZaru\por-mes'; New-Item -ItemType Directory -Force $CACHE | Out-Null
$DRIVE = 'G:\Mi unidad\Casa Zaru\Finanzas'
if (-not $Anio) { $Anio = (Get-Date).AddMonths(-1).Year }
. (Join-Path $PL 'lib-xls.ps1')
. (Join-Path $PRIV 'config.ps1')
$MESES = 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
$A0 = [datetime]::new($Anio, 1, 1); $A1 = $A0.AddYears(1)
function HastaMesDe($fechas) {
  $tope = if ((Get-Date).Year -eq $Anio) { (Get-Date).Month } else { 12 }
  $m = 1; foreach ($f in $fechas) { if ($f -and $f.Year -eq $Anio -and $f.Month -gt $m) { $m = $f.Month } }
  [math]::Min($m, $tope)
}
function NombreHoja($mes) { '{0:00} {1}' -f $mes, $MESES[$mes - 1].Substring(0, 3) }

function V($x) { $s = "$x".Trim() -replace '[^\d\.\-]', ''; if ($s -eq '' -or $s -eq '-') { 0 } else { [double]::Parse($s, $INV) } }
function FechaDe($s) {
  if ($s -match '^(\d{4})-(\d{2})-(\d{2})') { return [datetime]::new([int]$matches[1], [int]$matches[2], [int]$matches[3]) }
  if ($s -match '^(\d{1,2})[-/](\d{1,2})[-/](\d{4})') { return [datetime]::new([int]$matches[3], [int]$matches[2], [int]$matches[1]) }
  $null
}
function Mov($fecha, $cuenta, $quien, $glosa, $monto, $fuente) { [pscustomobject]@{ fecha = $fecha; cuenta = $cuenta; quien = "$quien"; glosa = "$glosa"; monto = [double]$monto; fuente = $fuente; factura = ''; cruce = ''; sinFactura = $true } }

# ── BCI 7175: unión de todos los exports "Movimientos_Detallado" ──
function CacheVigente($cache, $archivos) {
  if (-not (Test-Path $cache) -or -not $archivos.Count) { return $false }
  $c = (Get-Item $cache).LastWriteTime; -not @($archivos | Where-Object { $_.LastWriteTime -gt $c }).Count
}
$bciArch = @(Get-ChildItem "$env:USERPROFILE\Downloads" -Filter '*Movimientos_Detallado_Cuenta_7175*.xlsx')
$bciCache = Join-Path $CACHE 'bci-todo.csv'
if (-not (CacheVigente $bciCache $bciArch)) {
  $vistos = @{}; $filas = New-Object System.Collections.ArrayList
  foreach ($f in ($bciArch | Sort-Object LastWriteTime)) {
    foreach ($r in @(Read-XlsxRows $f.FullName | Select-Object -Skip 1)) {
      if ($r.Count -lt 12 -or "$($r[0])" -notmatch '^\d') { continue }
      $fe = [datetime]::FromOADate([double]::Parse($r[0], $INV)).Date
      $k = "$($fe.ToString('yyyy-MM-dd'))|$($r[1])|$($r[7])|$($r[8])|$($r[9])|$($r[11])"
      if ($vistos[$k]) { continue }; $vistos[$k] = 1
      [void]$filas.Add([pscustomobject]@{ fecha = $fe.ToString('yyyy-MM-dd'); hora = "$($r[1])"; glosa = "$($r[7])"; ingreso = "$($r[8])"; egreso = "$($r[9])"; nombre = "$($r[11])"; rut = "$($r[12])"; banco = "$($r[15])"; comentario = $(if ($r.Count -gt 17) { "$($r[17])" } else { '' }) })
    }
  }
  $filas | Sort-Object fecha, hora | Export-Csv $bciCache -NoTypeInformation -Encoding UTF8 -Delimiter ';'
}
$BCI = @(Import-Csv $bciCache -Delimiter ';' -Encoding UTF8 | Where-Object { (V $_.egreso) -gt 0 } | ForEach-Object {
  [pscustomobject]@{ fecha = (FechaDe $_.fecha); nombre = $_.nombre; rut = $_.rut; glosa = $_.glosa; comentario = $_.comentario; monto = (V $_.egreso) } } | Where-Object { $_.fecha -ge $A0 -and $_.fecha -lt $A1 })

# ── Banco de Chile (tarjeta del taller): unión de las "cartola (N).xls" de Muvale ──
$bdcArch = @(Get-ChildItem "$env:USERPROFILE\Downloads" -Filter 'cartola*.xls')
$bdcCache = Join-Path $CACHE 'bdc-todo.csv'
if (-not (CacheVigente $bdcCache $bdcArch)) {
  $vistos = @{}; $filas = New-Object System.Collections.ArrayList
  foreach ($f in ($bdcArch | Sort-Object LastWriteTime)) {
    $b = [IO.File]::ReadAllBytes($f.FullName)
    if ($b.Length -lt 8 -or (($b[0..7] | ForEach-Object { $_.ToString('x2') }) -join '') -ne 'd0cf11e0a1b11ae1') { continue }
    if ([Text.Encoding]::GetEncoding(28591).GetString($b) -notmatch '77\.157\.082-8') { continue }
    try { $raw = @(Read-XlsRows $f.FullName) } catch { continue }
    foreach ($r in $raw) {
      if ($r.Count -le 9 -or "$($r[1])" -notmatch '^\d{2}/\d{2}/\d{4}$') { continue }
      $fe = [datetime]::ParseExact($r[1], 'dd/MM/yyyy', $INV); $k = "$($fe.ToString('yyyy-MM-dd'))|$($r[3])|$($r[7])|$($r[8])|$($r[9])"
      if ($vistos[$k]) { continue }; $vistos[$k] = 1
      [void]$filas.Add([pscustomobject]@{ fecha = $fe.ToString('yyyy-MM-dd'); glosa = "$($r[3])"; cargo = "$($r[7])"; abono = "$($r[8])"; saldo = "$($r[9])" })
    }
  }
  $filas | Sort-Object fecha | Export-Csv $bdcCache -NoTypeInformation -Encoding UTF8 -Delimiter ';'
}
$BDC = @(Import-Csv $bdcCache -Delimiter ';' -Encoding UTF8 | Where-Object { (V $_.cargo) -gt 0 } | ForEach-Object {
  [pscustomobject]@{ fecha = (FechaDe $_.fecha); glosa = ($_.glosa -replace '^Pago:\s*', ''); monto = (V $_.cargo) } } | Where-Object { $_.fecha -ge $A0 -and $_.fecha -lt $A1 })

# ── Planilla del 1er semestre (ya clasificada; hoja Movimientos) ──
$h1Path = Join-Path $PL "Gastos 1er Semestre $Anio Clasificado.xlsx"
$H1 = if (Test-Path $h1Path) { @(Read-XlsxRows $h1Path | Select-Object -Skip 1 | Where-Object { $_.Count -ge 10 -and "$($_[1])" -match '^\d{4}-' } | ForEach-Object {
  [pscustomobject]@{ fecha = (FechaDe $_[1]); cuenta = "$($_[2])"; desc = "$($_[3])"; detalle = "$($_[4])"; cat = "$($_[5])"; sub = "$($_[6])"; monto = (V $_[7]); estado = "$($_[8])"; real = (V $_[9]); nota = "$($_[10])" } }) } else { @() }
$H1_HASTA = if ($H1.Count) { ($H1 | ForEach-Object { $_.fecha } | Measure-Object -Maximum).Maximum } else { $A0.AddDays(-1) }

# ── Tarjeta de Mercado Pago: cargos de los estados de cuenta, con el nombre del comercio si está en las capturas ──
$mpNombres = @(); $mpn = Join-Path $CZ 'mp-nombres.csv'
if (Test-Path $mpn) { $mpNombres = @(Import-Csv $mpn -Delimiter ';' -Encoding UTF8 | ForEach-Object { [pscustomobject]@{ fecha = (FechaDe $_.Fecha); monto = (V $_.Monto); nombre = "$($_.Nombre)" } }) }
$MP = @()
foreach ($n in (Get-ChildItem $CZ -Filter "mp-$Anio-??.csv")) {
  $MP += @(Import-Csv $n.FullName -Delimiter ';' -Encoding UTF8 | Where-Object { $_.mov -eq 'Cargo' -and $_.tipo -in 'Pago', 'Compra' } | ForEach-Object {
    $f = FechaDe $_.fecha; $m = [math]::Abs((V $_.monto))
    $nom = $mpNombres | Where-Object { $_.fecha -eq $f -and [math]::Abs($_.monto - $m) -le 1 } | Select-Object -First 1
    [pscustomobject]@{ fecha = $f; monto = $m; nombre = $(if ($nom) { $nom.nombre } else { '' }); id = $_.id } })
}
$hastaMP = if ($MP.Count) { ($MP | ForEach-Object { $_.fecha } | Measure-Object -Maximum).Maximum } else { $A0.AddDays(-1) }
$MP += @($mpNombres | Where-Object { $_.fecha -gt $hastaMP -and $_.fecha -lt $A1 } | ForEach-Object { [pscustomobject]@{ fecha = $_.fecha; monto = $_.monto; nombre = $_.nombre; id = 'captura' } })

# ── Visa Empresa 8340 (export MovimientosNoFacturados.xls) ──
$VISA = @()
foreach ($n in (Get-ChildItem "$env:USERPROFILE\Downloads" -Filter 'Movimientos*Facturados*.xls' -ErrorAction SilentlyContinue)) {
  $VISA += @(Read-XlsRows $n.FullName | Where-Object { $_.Count -ge 10 -and "$($_[1])" -match '^\d{2}/\d{2}/\d{4}$' } | ForEach-Object {
    [pscustomobject]@{ fecha = (FechaDe $_[1]); glosa = "$($_[4])"; monto = (V $_[10]) } })
}
$vv = @{}; $VISA = @($VISA | Where-Object { $_.fecha -ge $A0 -and $_.fecha -lt $A1 -and $_.monto -gt 0 } | Where-Object { $k = "$($_.fecha.ToString('yyyyMMdd'))|$($_.glosa)|$($_.monto)"; if ($vv[$k]) { $false } else { $vv[$k] = 1; $true } })

# ── Facturas de compra (planilla Gastos Wasabil: Monto con IVA) ──
$FACT = @(Import-Csv (Join-Path $PL "Gastos Wasabil $Anio.csv") -Delimiter ';' -Encoding UTF8 | ForEach-Object {
  [pscustomobject]@{ fecha = (FechaDe $_.Fecha); proveedor = $_.Proveedor; rut = $_.RUT; tipo = $_.'Tipo doc'; folio = "$($_.Folio)"; cat = $_.'Categoría'; monto = (V $_.Monto); glosa = $_.'Detalle (glosa)'; usada = $false } } | Where-Object { $_.fecha -and $_.fecha.Year -eq $Anio })

# Cruza cada movimiento con una factura: mismo monto (±tol) y fecha a ≤ $dias días. Una factura justifica un solo pago.
function CruzarFacturas($movs, $facturas, $tol = 2, $dias = 15) {
  foreach ($m in ($movs | Sort-Object fecha)) {
    $f = $facturas | Where-Object { -not $_.usada -and [math]::Abs($_.monto - $m.monto) -le $tol -and [math]::Abs(($_.fecha - $m.fecha).Days) -le $dias } | Sort-Object { [math]::Abs(($_.fecha - $m.fecha).Days) } | Select-Object -First 1
    if ($f) { $f.usada = $true; $m.factura = "$($f.tipo) $($f.folio)"; $m.sinFactura = $false }
  }
}
# Guarda el libro en Planillas y deja una copia en Drive/Finanzas
function Publicar($ruta) {
  GuardarXlsx $ruta
  if (Test-Path $DRIVE) { Copy-Item $ruta $DRIVE -Force }
  "$ruta  $((Get-Item $ruta).Length) bytes, $($hojas.Count) hojas"
}
