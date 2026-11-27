# Cerebro Zaru - gastos POR CLASIFICAR del libro mensual <-> pendientes de «Mi día» <-> reglas-cierre.csv
# Uso (desde Bash, en la corrida de las 07:30, DESPUÉS de cerrar-dia.ps1 y ANTES de armar-dia.ps1):
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .claude/cerebro/clasificar-sync.ps1 -Fecha 2026-11-28
#
# libro-mensual.ps1 deja en Cerebro\por-clasificar.csv lo que quedó POR CLASIFICAR, con una respuesta propuesta.
# Este script:
#   1. Cierra el ciclo de lo que el usuario ya marcó en «Mi día»:
#        hecho  + propuesta -> agrega la regla a reglas-cierre.csv (estado "regla": no vuelve a preguntarse)
#        hecho  sin propuesta, o matado -> estado "revisar": Claude lee la nota dictada y escribe la regla a mano
#   2. Cierra solo el pendiente de lo que se resolvió por otro lado (llegó la factura, regla nueva): "resuelto".
#   3. Vuelve pendiente (área caja, vence hoy) cada fila "nuevo".
# Respalda pendientes.csv y reglas-cierre.csv antes de escribir. Idempotente. Este archivo no lleva datos (repo público).
param(
  [Parameter(Mandatory = $true)][string]$Fecha,
  [string]$Cerebro = 'G:\Mi unidad\Casa Zaru\Cerebro',
  [string]$Reglas = 'C:\Users\dell\Casa Zaru Planillas\reglas-cierre.csv'
)
$ErrorActionPreference = 'Stop'
$fPC = Join-Path $Cerebro 'por-clasificar.csv'
$fPend = Join-Path $Cerebro 'pendientes.csv'
if (-not (Test-Path -LiteralPath $fPC)) { Write-Output 'CLASIF sin archivo (el libro no ha dejado nada por clasificar)'; exit 0 }
$cl = [Globalization.CultureInfo]'es-CL'
$filas = @(Import-Csv -LiteralPath $fPC -Delimiter ';' -Encoding UTF8)
$pend = @(Import-Csv -LiteralPath $fPend -Encoding UTF8)
$pPorId = @{}; foreach ($p in $pend) { $pPorId[$p.id] = $p }
$stamp = Get-Date -Format 'yyyy-MM-dd-HHmmss'
$resp = Join-Path $Cerebro 'respaldos'; if (-not (Test-Path -LiteralPath $resp)) { New-Item -ItemType Directory -Path $resp | Out-Null }
$cReglas = 0; $cRevisar = 0; $cNuevos = 0; $cResueltos = 0; $tocoPend = $false; $nuevasReglas = @()

foreach ($f in $filas) {
  $p = if ($f.pendiente) { $pPorId[$f.pendiente] } else { $null }
  if ($f.estado -eq 'pendiente' -and $p) {
    if ($p.estado -eq 'hecho') {
      if ($f.propuesta) {
        $coment = "$($f.proveedor) ($($f.fecha)): aceptado en «Mi día» $Fecha ($($f.id))" -replace ';', ','
        $nuevasReglas += "$($f.fuente);$($f.patron);;$($f.propuesta);$($f.sub);$coment"
        $f.estado = 'regla'; $cReglas++
      } else { $f.estado = 'revisar'; $cRevisar++ }
    } elseif ($p.estado -in 'matado', 'delegado') { $f.estado = 'revisar'; $cRevisar++ }
  }
  elseif ($f.estado -eq 'resuelto' -and $p -and $p.estado -in 'abierto', 'esperando') {
    $p.estado = 'hecho'; $p.ultima_verificacion = $Fecha; $p.evidencia = "$($p.evidencia) | se resolvió solo (regla o factura) $Fecha"
    $tocoPend = $true; $cResueltos++
  }
}

# Nuevos -> pendientes (siguiente P###)
$max = 0; foreach ($p in $pend) { if ($p.id -match '^P(\d+)$') { $max = [math]::Max($max, [int]$matches[1]) } }
$nuevosPend = @()
foreach ($f in @($filas | Where-Object { $_.estado -eq 'nuevo' })) {
  $max++; $id = 'P{0:000}' -f $max
  $plata = '$' + ([double]$f.monto).ToString('N0', $cl)
  $fe = try { ([datetime]::ParseExact($f.fecha, 'yyyy-MM-dd', $null)).ToString('dd-MM') } catch { $f.fecha }
  $prop = if ($f.propuesta) { "propongo $($f.propuesta)$(if ($f.sub) { " · $($f.sub)" }). Marca hecho si está bien" } else { "¿qué es? Dicta en notas «$($f.id): categoría»" }
  $nuevosPend += [pscustomobject][ordered]@{
    id = $id; area = 'caja'; titulo = "Clasificar pago: $($f.proveedor) $plata ($fe, $($f.cuenta)) → $prop"; dueno = 'yo'
    origen = "por-clasificar.csv $($f.id)"; creado = $Fecha; vence = $Fecha; proxima_revision = $Fecha; estado = 'abierto'; saltos = '0'
    'impacto_$' = "$($f.monto)"; evidencia = "$($f.detalle)" ; ultima_verificacion = $Fecha }
  $f.estado = 'pendiente'; $f.pendiente = $id; $cNuevos++
}

if ($nuevasReglas.Count) {
  Copy-Item -LiteralPath $Reglas -Destination (Join-Path $resp "reglas-cierre-$stamp.csv")
  $txt = [IO.File]::ReadAllText($Reglas); $sep = if ($txt.EndsWith("`n")) { '' } else { "`r`n" }
  [IO.File]::AppendAllText($Reglas, $sep + ($nuevasReglas -join "`r`n") + "`r`n", (New-Object Text.UTF8Encoding $false))   # el BOM queda al inicio
}
if ($nuevosPend.Count -or $tocoPend) {
  Copy-Item -LiteralPath $fPend -Destination (Join-Path $resp "pendientes-$stamp.csv")
  @($pend) + @($nuevosPend) | Export-Csv -LiteralPath $fPend -NoTypeInformation -Encoding UTF8
}
if ($cReglas -or $cRevisar -or $cNuevos) {
  Copy-Item -LiteralPath $fPC -Destination (Join-Path $resp "por-clasificar-$stamp.csv")
  $filas | Export-Csv -LiteralPath $fPC -Delimiter ';' -NoTypeInformation -Encoding UTF8
}
$rev = @($filas | Where-Object { $_.estado -eq 'revisar' } | ForEach-Object { "$($_.id) $($_.pendiente)" })
Write-Output ("CLASIF nuevos={0} reglas={1} resueltos={2} revisar={3} {4}" -f $cNuevos, $cReglas, $cResueltos, $rev.Count, ($rev -join ', '))
