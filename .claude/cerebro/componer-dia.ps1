# Cerebro Zaru - junta lo calculado (armar-dia.ps1) con lo que escribe Claude (narrativa) en el JSON del día.
# Uso (desde Bash):
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .claude/cerebro/componer-dia.ps1 -Calc <calc.json> -Narrativa <narrativa.json> -Salida <dia.json>
# narrativa.json: { foco, pulso:{cifras:[...], raro}, decidir:[{id,titulo,porque,espera_dias}], mensajes:{"<dueño>":"..."}, crecer:{...} }
# Las cifras del pulso las pone Claude copiadas TAL CUAL de las consultas de sql/; aquí no se calcula nada nuevo.
param(
  [Parameter(Mandatory=$true)][string]$Calc,
  [Parameter(Mandatory=$true)][string]$Narrativa,
  [Parameter(Mandatory=$true)][string]$Salida,
  [int]$MaxAlarmas = 12,
  # Última revisión de WhatsApp (skill revision-whatsapp, desde 12-11-2026): se copia tal cual en la sección «WhatsApp».
  [string]$WhatsApp = 'G:\Mi unidad\Casa Zaru\Revision WhatsApp\mi-dia-whatsapp.json',
  # Cruce de datos (cruzar-dia.ps1, desde 16-11-2026): se copia tal cual en la sección «Cruce de datos».
  [string]$Cruce = '',
  # «Mi día» del equipo (armar-equipo.ps1 / cerrar-equipo.ps1, desde 17-11-2026).
  [string]$Cerebro = 'G:\Mi unidad\Casa Zaru\Cerebro'
)
$ErrorActionPreference = 'Stop'
$c = Get-Content -LiteralPath $Calc -Raw -Encoding UTF8 | ConvertFrom-Json
$n = Get-Content -LiteralPath $Narrativa -Raw -Encoding UTF8 | ConvertFrom-Json

# Orden: primero lo que vence de hoy a 3 días (no se puede pasar), luego lo vencido, luego el resto.
$al = @($c.alarmas | Sort-Object @{e={ $d=[int]$_.dias; if ($d -ge 0 -and $d -le 3) {0} elseif ($d -lt 0) {1} else {2} }}, @{e={[int]$_.dias}})
$mostrarAl = @($al | Select-Object -First $MaxAlarmas)
# «Mi día» del equipo: quién tiene día propio hoy, qué hizo ayer y qué escala a Decidir.
$propio = @{}; $ayerDe = @{}; $ajenos = @{}; $escalar = @()
$perRuta = Join-Path $Cerebro 'equipo\personas.json'
if (Test-Path -LiteralPath $perRuta) {
  $duenosEq = @((Get-Content -LiteralPath $perRuta -Raw -Encoding UTF8 | ConvertFrom-Json).personas | ForEach-Object { $_.dueno })
  foreach ($q in $duenosEq) {
    $r = Join-Path $Cerebro ("equipo\$q\" + $c.fecha + '.json')
    if (Test-Path -LiteralPath $r) { $propio[$q] = Get-Content -LiteralPath $r -Raw -Encoding UTF8 | ConvertFrom-Json }
    $a = Join-Path $Cerebro "equipo\$q\ayer.json"
    if (Test-Path -LiteralPath $a) {
      $ay = Get-Content -LiteralPath $a -Raw -Encoding UTF8 | ConvertFrom-Json
      if ($ay.fecha -lt $c.fecha) { $ayerDe[$q] = $ay; $escalar += @($ay.escalar | Where-Object { $_ }) }
    }
  }
  # Lo que es de alguien con día propio suma saltos en SU día, no porque el dueño lo vea aquí.
  if ($propio.Count) {
    Import-Csv -LiteralPath (Join-Path $Cerebro 'pendientes.csv') -Encoding UTF8 | Where-Object { $propio.ContainsKey($_.dueno) } | ForEach-Object { $ajenos[$_.id] = $true }
    foreach ($q in $propio.Keys) { @($propio[$q].mostrados) | ForEach-Object { $ajenos[$_] = $true } }
  }
}
$equipo = @()
foreach ($e in @($c.equipo)) {
  $msg = $null
  if ($n.mensajes -and ($n.mensajes.PSObject.Properties.Name -contains $e.quien)) { $msg = $n.mensajes.($e.quien) }
  $pd = $propio[$e.quien]
  if ($pd) {
    # Tiene su propio día: aquí van SUS misiones de hoy, con lo que hizo ayer con cada una.
    $ay = $ayerDe[$e.quien]; $its = @()
    foreach ($x in @($pd.data.misiones)) {
      $det = ''; if ($ay -and $ay.items -and ($ay.items.PSObject.Properties.Name -contains $x.id)) { $det = 'Ayer: ' + $ay.items.($x.id) }
      elseif ($x.vence) { $det = 'vence ' + $x.vence }
      $its += [pscustomobject]@{ id=$x.id; titulo=$x.titulo; detalle=$det }
    }
    # Su nota y las fotos que pidió al taller (18-11-2026): solo para que lo veas; no son pendientes.
    if ($ay -and $ay.nota) { $its = @([pscustomobject]@{ id=('nota:' + $e.quien + ':' + $ay.fecha); titulo=('Nota de ' + $e.quien + ': «' + $ay.nota + '»'); detalle=('escrita el ' + $ay.fecha.Substring(8,2) + '-' + $ay.fecha.Substring(5,2)) }) + $its }
    if ($ay -and $ay.fotos) { foreach ($fo in @($ay.fotos)) { $its += [pscustomobject]@{ id=('fotos:' + $fo.num); titulo=('Fotos pedidas al taller: ' + $fo.num + $(if ($fo.titulo) { ' · ' + $fo.titulo } else { '' })); detalle=('antes de despachar' + $(if ($fo.detalle) { ' · ' + $fo.detalle } else { '' })) } } }
    $res = 'Hoy en su «Mi día»: ' + @($pd.data.misiones).Count + ' misiones, ' + @($pd.data.cola).Count + ' en cola' + $(if (@($pd.data.bloqueadas).Count) { ', ' + @($pd.data.bloqueadas).Count + $(if (@($pd.data.bloqueadas).Count -eq 1) { ' bloqueada' } else { ' bloqueadas' }) } else { '' }) + '.'
    $sm = $pd.data.semana
    if ($sm) { $res += ' Su semana: ' + $sm.listas + ' de ' + $sm.misiones + ' misiones · rutina ' + $sm.rutina + '/' + $sm.rutina_total + $(if ($sm.reels_meta) { ' · reels ' + $sm.reels + '/' + $sm.reels_meta } else { '' }) + '.' }
    if ($ay) { $res = 'Ayer ('+ $ay.fecha.Substring(8,2) + '-' + $ay.fecha.Substring(5,2) + '): ' + $ay.listas + ' de ' + $ay.total + ' listas · rutina ' + $ay.rutina + '. ' + $res }
    $equipo += [pscustomobject]@{ quien=$e.quien; resumen=$res; items=$its; mensaje=$msg }
    continue
  }
  $equipo += [pscustomobject]@{ quien=$e.quien; items=@($e.items | ForEach-Object { [pscustomobject]@{ id=$_.id; titulo=$_.titulo; detalle=$(if($_.vence){'vence ' + $_.vence}else{''}) } }); mensaje=$msg }
}
$decidir = @($n.decidir | Select-Object -First 4)
$yaDec = @($decidir | ForEach-Object { $_.id })
foreach ($x in $escalar) { if ($yaDec -notcontains $x.id) { $decidir += [pscustomobject]@{ id=$x.id; titulo=$x.titulo; porque=$x.porque; espera_dias=$null }; $yaDec += $x.id } }
$mostrados = New-Object System.Collections.ArrayList
$mostrarAl | ForEach-Object { [void]$mostrados.Add($_.id) }
@($decidir) | ForEach-Object { if ($_.id) { [void]$mostrados.Add($_.id) } }
$equipo | ForEach-Object { $_.items | ForEach-Object { [void]$mostrados.Add($_.id) } }
if ($n.crecer -and $n.crecer.id) { [void]$mostrados.Add($n.crecer.id) }

$fuentes = [pscustomobject]@{ ok=@(@($c.fuentes.ok) + @($n.fuentes_ok) | Where-Object { $_ }); fallidas=@(@($c.fuentes.fallidas) + @($n.fuentes_fallidas) | Where-Object { $_ }) }
$dia = [pscustomobject]@{
  fecha = $c.fecha
  generado = (Get-Date).ToString('o')
  foco = $n.foco
  alarmas = $mostrarAl
  alarmas_mas = [math]::Max(0, $al.Count - $mostrarAl.Count)
  pulso = $n.pulso
  decidir = $decidir
  equipo = $equipo
  crecer = $n.crecer
  deudas = $c.deudas
  areas = $c.areas
  grupos = $c.grupos
  fijo = $c.fijo
  salud = $c.salud
  whatsapp = $(if ($WhatsApp -and (Test-Path -LiteralPath $WhatsApp)) { Get-Content -LiteralPath $WhatsApp -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null })
  cruce = $(if ($Cruce -and (Test-Path -LiteralPath $Cruce)) { Get-Content -LiteralPath $Cruce -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null })
  fuentes = $fuentes
  mostrados = @($mostrados | Where-Object { -not $ajenos.ContainsKey($_) -and $_ -notmatch '^(nota|fotos):' } | Select-Object -Unique)
}
$dir = Split-Path -Parent $Salida; if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
[System.IO.File]::WriteAllText($Salida, ($dia | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding($false)))
Write-Output "OK $Salida alarmas=$($mostrarAl.Count)+$($dia.alarmas_mas) mostrados=$($dia.mostrados.Count)"
