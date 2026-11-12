# Cerebro Zaru - arma la parte calculada de «Tu día» (solo lectura de fuentes; no escribe en ninguna base).
# Uso (desde Bash, porque la herramienta PowerShell bloquea G:\):
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .claude/cerebro/armar-dia.ps1 -Salida <json> [-Fecha 2026-11-12]
# Lee: G:\Mi unidad\Casa Zaru\Cerebro\{pendientes,areas,calendario}.csv
#      C:\Users\dell\Casa Zaru Planillas\{cuotas-creditos,por-pagar-manual}.csv
#      respaldos (fechas) y git status del repo.
# Escribe: SOLO el JSON de salida. Este archivo no lleva datos: el repo es público.
param(
  [string]$Fecha = (Get-Date -Format 'yyyy-MM-dd'),
  [Parameter(Mandatory=$true)][string]$Salida,
  [string]$Cerebro = 'G:\Mi unidad\Casa Zaru\Cerebro',
  [string]$Planillas = 'C:\Users\dell\Casa Zaru Planillas',
  [string]$Repo = 'C:\Users\dell\Casa Zaru - Claude'
)
$ErrorActionPreference = 'Stop'
$hoy = [datetime]::ParseExact($Fecha, 'yyyy-MM-dd', $null)
$ok = New-Object System.Collections.ArrayList
$fallidas = New-Object System.Collections.ArrayList

function D([string]$s) {
  if ([string]::IsNullOrWhiteSpace($s)) { return $null }
  try { return [datetime]::ParseExact($s.Trim(), 'yyyy-MM-dd', $null) } catch { return $null }
}
function Num($s) {
  if ($null -eq $s) { return $null }
  $t = ([string]$s).Trim()
  if ($t -match '^-?\d+(\.\d+)?$') { return [double]$t }
  return $null
}
function Leer([string]$ruta, [string]$nombre, [string]$sep = ',') {
  try {
    $r = @(Import-Csv -Path $ruta -Delimiter $sep -Encoding UTF8)
    [void]$ok.Add($nombre); return ,$r
  } catch { [void]$fallidas.Add($nombre); return ,@() }
}

$pend = Leer (Join-Path $Cerebro 'pendientes.csv') 'pendientes.csv'
$areas = Leer (Join-Path $Cerebro 'areas.csv') 'areas.csv'
$cal = Leer (Join-Path $Cerebro 'calendario.csv') 'calendario.csv'
$cuotas = Leer (Join-Path $Planillas 'cuotas-creditos.csv') 'cuotas-creditos.csv' ';'
$porPagar = Leer (Join-Path $Planillas 'por-pagar-manual.csv') 'por-pagar-manual.csv' ';'

$abiertos = @($pend | Where-Object { $_.estado -in @('abierto','esperando') })

# ---------- Alarmas: pendientes abiertos que vencen en <= 10 días (o ya vencidos) ----------
$alarmas = @()
foreach ($p in $abiertos) {
  $v = D $p.vence
  if ($null -eq $v) { continue }
  $dd = [int][math]::Floor(($v - $hoy).TotalDays)
  if ($dd -le 10) {
    $alarmas += [pscustomobject]@{ id=$p.id; titulo=$p.titulo; area=$p.area; dueno=$p.dueno; vence=$p.vence; dias=$dd; monto=(Num $p.'impacto_$') }
  }
}
$alarmas = @($alarmas | Sort-Object dias, id)

# ---------- Semáforo por área ----------
$cadDias = @{ 'diaria'=1; 'semanal'=7; 'quincenal'=15; 'mensual'=31 }
$semaforo = @()
foreach ($a in $areas) {
  $mios = @($abiertos | Where-Object { $_.area -eq $a.area })
  $venc = @($mios | Where-Object { $v = D $_.vence; $v -and $v -lt $hoy }).Count
  $pronto = @($mios | Where-Object { $v = D $_.vence; $v -and $v -ge $hoy -and ($v - $hoy).TotalDays -le 3 }).Count
  $cd = $cadDias[$a.cadencia]; if (-not $cd) { $cd = 7 }
  $ult = D $a.ultima_revision
  $atraso = if ($ult) { [int]($hoy - $ult).TotalDays - $cd } else { $null }
  $estado = 'verde'
  if ($venc -gt 0 -or ($null -ne $atraso -and $atraso -gt $cd)) { $estado = 'rojo' }
  elseif ($pronto -gt 0 -or ($mios.Count -gt 0 -and $null -eq $atraso) -or $atraso -gt 0) { $estado = 'amarillo' }
  elseif ($mios.Count -eq 0 -and $null -eq $atraso) { $estado = 'gris' }   # sin pendientes y nunca revisada
  # Los 3 próximos del área: primero los que tienen fecha (los más cercanos), después el resto por id.
  $prox = @($mios | Sort-Object @{e={ $v = D $_.vence; if ($v) { 0 } else { 1 } }}, @{e={ $v = D $_.vence; if ($v) { $v } else { [datetime]::MaxValue } }}, id | Select-Object -First 3 | ForEach-Object {
    $v = D $_.vence
    [pscustomobject]@{ id=$_.id; titulo=$_.titulo; vence=$_.vence; dias=$(if ($v) { [int][math]::Floor(($v - $hoy).TotalDays) } else { $null }) }
  })
  $semaforo += [pscustomobject]@{ grupo=$a.grupo; area=$a.area; nombre=$a.nombre; estado=$estado; abiertos=$mios.Count; vencidos=$venc; vencen_3d=$pronto; cadencia=$a.cadencia; ultima=$a.ultima_revision; atraso_revision=$atraso; prox=$prox }
}

# ---------- Grupos (Vender, Marketing, Hacer, Plata, La base): el peor color de sus áreas ----------
$gruposDef = @(@('vender','Vender'), @('marketing','Marketing'), @('hacer','Hacer'), @('plata','Plata'), @('base','La base'))
$peso = @{ 'rojo'=3; 'amarillo'=2; 'verde'=1; 'gris'=0 }
$grupos = @()
foreach ($g in $gruposDef) {
  $suyas = @($semaforo | Where-Object { $_.grupo -eq $g[0] })
  if (-not $suyas.Count) { continue }
  $peor = ($suyas | Sort-Object @{e={ $peso[$_.estado] }} -Descending | Select-Object -First 1).estado
  $proxV = @($suyas | ForEach-Object { $_.prox } | Where-Object { $null -ne $_.dias -and $_.dias -ge 0 } | Sort-Object dias | Select-Object -First 1)
  $grupos += [pscustomobject]@{ grupo=$g[0]; nombre=$g[1]; estado=$peor;
    abiertos=($suyas | Measure-Object abiertos -Sum).Sum; vencidos=($suyas | Measure-Object vencidos -Sum).Sum;
    areas=$suyas.Count; proximo=$(if ($proxV.Count) { $proxV[0].vence } else { $null }) }
}

# ---------- Calendario: próxima fecha según la regla ----------
function ProximaFecha($c) {
  $r = [string]$c.regla_fecha
  $fijo = D $c.proxima
  switch -regex ($c.frecuencia) {
    'diaria' { return $hoy }
    'semanal' { if ($r -match 'lunes') { $d = $hoy; while ($d.DayOfWeek -ne 'Monday') { $d = $d.AddDays(1) }; return $d } }
    'mensual' {
      if ($r -match '(\d{1,2})') {
        $n = [int]$Matches[1]
        foreach ($k in 0..1) {
          $m = $hoy.AddMonths($k); $ud = [datetime]::DaysInMonth($m.Year, $m.Month)
          $d = Get-Date -Year $m.Year -Month $m.Month -Day ([math]::Min($n,$ud)) -Hour 0 -Minute 0 -Second 0 -Millisecond 0
          if ($r -match 'antes') { $d = $d.AddDays(-1) }
          if ($d -ge $hoy) { return $d.Date }
        }
      }
      if ($r -match 'último|fin de mes') { $ud = [datetime]::DaysInMonth($hoy.Year,$hoy.Month); return (Get-Date -Year $hoy.Year -Month $hoy.Month -Day $ud).Date }
    }
  }
  if ($fijo -and $fijo -ge $hoy) { return $fijo }
  return $null
}
$fijo = @()
foreach ($c in $cal) {
  if ($c.frecuencia -eq 'diaria') { continue }
  $d = ProximaFecha $c
  if ($d -and ($d - $hoy).TotalDays -le 14) {
    $fijo += [pscustomobject]@{ fecha=$d.ToString('yyyy-MM-dd'); obligacion=$c.obligacion; area=$c.area; dueno=$c.dueno; monto=$null }
  }
}
$fijo = @($fijo | Sort-Object fecha)

# ---------- Deudas (fuente de verdad: las planillas del cierre) ----------
function MesesEntre([datetime]$a, [datetime]$b) { return ($b.Year - $a.Year) * 12 + ($b.Month - $a.Month) }
$deudas = @(); $total = 0.0; $v30 = 0.0; $sinSaldo = 0
$limite = $hoy.AddDays(30)
foreach ($q in $cuotas) {
  $cuota = Num $q.Cuota; $dia = [int](Num $q.Dia); $pri = D $q.PrimeraCuota; $ult = D $q.UltimaCuota
  if (-not $cuota -or -not $pri) { continue }
  # Próximo vencimiento >= hoy (día $dia de este mes o del siguiente)
  $prox = $null
  foreach ($k in 0..1) { $m = $hoy.AddMonths($k); $ud=[datetime]::DaysInMonth($m.Year,$m.Month); $d = (Get-Date -Year $m.Year -Month $m.Month -Day ([math]::Min($dia,$ud))).Date; if ($d -ge $hoy -and $d -ge $pri) { $prox = $d; break } }
  if ($ult -and $prox -and $prox -gt $ult) { $prox = $null }
  $saldo = $null; $det = $q.Nota
  if ($ult) {
    $n = (MesesEntre $pri $ult) + 1
    $vencidas = if ($hoy -ge $pri) { [math]::Min($n, (MesesEntre $pri $hoy) + $(if ($hoy.Day -ge $dia) {1} else {0})) } else { 0 }
    $rest = $n - $vencidas
    $saldo = $rest * $cuota; $total += $saldo
    $det = "$rest de $n cuotas por pagar (supone las vencidas pagadas al día)"
  } else { $sinSaldo++ ; $det = 'número de cuotas sin confirmar: saldo sin dato' }
  if ($null -ne $saldo -and $saldo -le 0) { continue }
  if ($prox -and $prox -le $limite) { $v30 += $cuota }
  $deudas += [pscustomobject]@{ acreedor=$q.Acreedor; tipo='cuota'; proximo=$(if($prox){$prox.ToString('yyyy-MM-dd')}else{''}); monto=$cuota; saldo=$saldo; detalle=$det }
}
$montosPP = @()
foreach ($x in $porPagar) {
  $m = Num $x.Monto; if (-not $m) { continue }
  $montosPP += $m
  $vence = $null
  if ($x.Concepto -match 'vence el (\d{1,2})-(\d{1,2})') {
    $mes=[int]$Matches[2]; $an=$hoy.Year; if ($mes -lt $hoy.Month - 6) { $an++ }
    $vence = (Get-Date -Year $an -Month $mes -Day ([int]$Matches[1])).Date
  }
  $total += $m
  if ($vence -and $vence -le $limite) { $v30 += $m }
  $deudas += [pscustomobject]@{ acreedor=($x.Concepto -replace ',\s*vence el.*$',''); tipo='por pagar'; proximo=$(if($vence){$vence.ToString('yyyy-MM-dd')}else{'sin fecha'}); monto=$m; saldo=$m; detalle='' }
}
# Pagos con fecha que viven solo en pendientes.csv («Pagar ...»), sin duplicar montos de por-pagar
foreach ($p in $abiertos) {
  if ($p.titulo -notmatch '^Pagar') { continue }
  $m = Num $p.'impacto_$'; $v = D $p.vence
  if (-not $m -or ($montosPP -contains $m)) { continue }
  $total += $m
  if ($v -and $v -le $limite) { $v30 += $m }
  $deudas += [pscustomobject]@{ acreedor=$p.titulo; tipo='pendiente'; proximo=$p.vence; monto=$m; saldo=$m; detalle=$p.id }
}
$deudas = @($deudas | Sort-Object @{e={ if ($_.proximo -match '^\d{4}') { $_.proximo } else { '9999' } }})

# ---------- Candidatos a «Decidir» y encargos del equipo ----------
$cand = @()
foreach ($p in $abiertos) {
  if ($p.dueno -ne 'yo' -or $p.estado -ne 'abierto') { continue }
  $c = D $p.creado; $esp = if ($c) { [int]($hoy - $c).TotalDays } else { 0 }
  $cand += [pscustomobject]@{ id=$p.id; titulo=$p.titulo; area=$p.area; espera_dias=$esp; saltos=[int](Num $p.saltos); vence=$p.vence }
}
$cand = @($cand | Sort-Object @{e='saltos';Descending=$true}, @{e='espera_dias';Descending=$true} | Select-Object -First 12)
$equipo = @()
# El equipo son los dueños que aparecen en pendientes.csv (todo lo que no es «yo»): sin nombres en el código.
$duenos = @($abiertos | Where-Object { $_.dueno -and $_.dueno -notin @('yo','Claude','externo') } | Group-Object dueno | Sort-Object @{e='Count';Descending=$true} | ForEach-Object { $_.Name })
foreach ($q in $duenos) {
  $its = @($abiertos | Where-Object { $_.dueno -eq $q } | Sort-Object @{e={ if ($_.vence) { $_.vence } else { '9999' } }} | Select-Object -First 6 | ForEach-Object { [pscustomobject]@{ id=$_.id; titulo=$_.titulo; vence=$_.vence } })
  if ($its.Count) { $equipo += [pscustomobject]@{ quien=$q; items=$its } }
}

# ---------- Automatizaciones mudas y trabajo a medias ----------
$salud = @()
function Edad([string]$ruta) { if (Test-Path -LiteralPath $ruta) { return [math]::Round(((Get-Date) - (Get-Item -LiteralPath $ruta).LastWriteTime).TotalHours, 1) } return $null }
$rg = Get-ChildItem -LiteralPath 'G:\Mi unidad\Casa Zaru\Boletas y Facturas - Ventas 2026\Respaldos Gestion' -Filter 'respaldo-gestion-*.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$rc = Get-ChildItem -LiteralPath 'G:\Mi unidad\Casa Zaru\Respaldos Cotizador' -Filter 'respaldo-cotizador-*.zip' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$salud += [pscustomobject]@{ que='Respaldo Gestión'; horas=$(if($rg){[math]::Round(((Get-Date)-$rg.LastWriteTime).TotalHours,1)}else{$null}) }
$salud += [pscustomobject]@{ que='Respaldo Cotizador'; horas=$(if($rc){[math]::Round(((Get-Date)-$rc.LastWriteTime).TotalHours,1)}else{$null}) }
$salud += [pscustomobject]@{ que='Respaldo PC'; horas=(Edad 'G:\Mi unidad\Casa Zaru\Respaldo PC\ultimo-respaldo.txt') }
$logs = Join-Path $env:LOCALAPPDATA 'CasaZaru'
foreach ($l in @('informe-semanal.log','tablero-semanal.log','cierre-mensual.log','respaldo-pc.log')) { $salud += [pscustomobject]@{ que=$l; horas=(Edad (Join-Path $logs $l)) } }
$aud = Get-ChildItem -LiteralPath 'G:\Mi unidad\Casa Zaru\Informes Gestion' -Filter 'auditoria-confiabilidad-*.md' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
$salud += [pscustomobject]@{ que='Auditoría de confiabilidad'; horas=$(if($aud){[math]::Round(((Get-Date)-$aud.LastWriteTime).TotalHours,1)}else{$null}) }
[void]$ok.Add('respaldos y logs')
$git = @()
try { Push-Location $Repo; $git = @(git status --porcelain 2>$null); Pop-Location; [void]$ok.Add('git status') } catch { [void]$fallidas.Add('git status') }

$out = [pscustomobject]@{
  fecha = $Fecha
  calculado = (Get-Date).ToString('o')
  alarmas = $alarmas
  areas = $semaforo
  grupos = $grupos
  fijo = $fijo
  deudas = [pscustomobject]@{ total=[math]::Round($total); vence_30d=[math]::Round($v30); deudas_sin_saldo=$sinSaldo; items=$deudas }
  candidatos_decidir = $cand
  equipo = $equipo
  salud = $salud
  git_sin_commit = $git.Count
  conteos = [pscustomobject]@{ pendientes_abiertos=$abiertos.Count; mas_de_14_dias=@($abiertos | Where-Object { $c = D $_.creado; $c -and ($hoy-$c).TotalDays -gt 14 }).Count }
  fuentes = [pscustomobject]@{ ok=@($ok); fallidas=@($fallidas) }
}
$json = $out | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($Salida, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Output "OK $Salida"
