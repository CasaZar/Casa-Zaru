# Cerebro Zaru - junta lo calculado (armar-dia.ps1) con lo que escribe Claude (narrativa) en el JSON del día.
# Uso (desde Bash):
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .claude/cerebro/componer-dia.ps1 -Calc <calc.json> -Narrativa <narrativa.json> -Salida <dia.json>
# narrativa.json: { foco, pulso:{cifras:[...], raro}, decidir:[{id,titulo,porque,espera_dias}], mensajes:{"<dueño>":"..."}, crecer:{...} }
# Las cifras del pulso las pone Claude copiadas TAL CUAL de las consultas de sql/; aquí no se calcula nada nuevo.
param(
  [Parameter(Mandatory=$true)][string]$Calc,
  [Parameter(Mandatory=$true)][string]$Narrativa,
  [Parameter(Mandatory=$true)][string]$Salida,
  [int]$MaxAlarmas = 12
)
$ErrorActionPreference = 'Stop'
$c = Get-Content -LiteralPath $Calc -Raw -Encoding UTF8 | ConvertFrom-Json
$n = Get-Content -LiteralPath $Narrativa -Raw -Encoding UTF8 | ConvertFrom-Json

# Orden: primero lo que vence de hoy a 3 días (no se puede pasar), luego lo vencido, luego el resto.
$al = @($c.alarmas | Sort-Object @{e={ $d=[int]$_.dias; if ($d -ge 0 -and $d -le 3) {0} elseif ($d -lt 0) {1} else {2} }}, @{e={[int]$_.dias}})
$mostrarAl = @($al | Select-Object -First $MaxAlarmas)
$equipo = @()
foreach ($e in @($c.equipo)) {
  $msg = $null
  if ($n.mensajes -and ($n.mensajes.PSObject.Properties.Name -contains $e.quien)) { $msg = $n.mensajes.($e.quien) }
  $equipo += [pscustomobject]@{ quien=$e.quien; items=@($e.items | ForEach-Object { [pscustomobject]@{ id=$_.id; titulo=$_.titulo; detalle=$(if($_.vence){'vence ' + $_.vence}else{''}) } }); mensaje=$msg }
}
$mostrados = New-Object System.Collections.ArrayList
$mostrarAl | ForEach-Object { [void]$mostrados.Add($_.id) }
@($n.decidir) | ForEach-Object { if ($_.id) { [void]$mostrados.Add($_.id) } }
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
  decidir = @($n.decidir | Select-Object -First 4)
  equipo = $equipo
  crecer = $n.crecer
  deudas = $c.deudas
  areas = $c.areas
  grupos = $c.grupos
  fijo = $c.fijo
  salud = $c.salud
  fuentes = $fuentes
  mostrados = @($mostrados | Select-Object -Unique)
}
$dir = Split-Path -Parent $Salida; if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
[System.IO.File]::WriteAllText($Salida, ($dia | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding($false)))
Write-Output "OK $Salida alarmas=$($mostrarAl.Count)+$($dia.alarmas_mas) mostrados=$($dia.mostrados.Count)"
