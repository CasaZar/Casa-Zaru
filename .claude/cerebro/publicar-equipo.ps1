# Cerebro Zaru - publica el «Mi día» de cada persona del equipo en el proyecto COTIZADOR (17-11-2026).
# Uso (desde Bash):
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .claude/cerebro/publicar-equipo.ps1 -Fecha 2026-11-17
# Lee Cerebro\equipo\<dueño>\<fecha>.json (lo deja armar-equipo.ps1) y llama la función
# equipo_publicar_dia() (migración 0003 del Cotizador) con la llave de %USERPROFILE%\.casazaru\equipo-token.txt.
# La llave nunca se imprime. Este archivo no lleva datos ni secretos: el repo es público.
param(
  [Parameter(Mandatory=$true)][string]$Fecha,
  [string]$Cerebro = 'G:\Mi unidad\Casa Zaru\Cerebro',
  [string]$Url = 'https://cmxqorsyxoltrakxawro.supabase.co/rest/v1/rpc/equipo_publicar_dia',
  # Llave pública (publishable) del Cotizador: es la misma que va en el HTML del sitio.
  [string]$Publica = 'sb_publishable_Z4Bu9BnRkjiKmuCUzUGz0Q_hwxOc-Go',
  [string]$TokenRuta = (Join-Path $env:USERPROFILE '.casazaru\equipo-token.txt')
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $TokenRuta)) { Write-Output "SIN_TOKEN: falta $TokenRuta"; exit 2 }
$token = (Get-Content -LiteralPath $TokenRuta -Raw).Trim()
$cfg = Get-Content -LiteralPath (Join-Path $Cerebro 'equipo\personas.json') -Raw -Encoding UTF8 | ConvertFrom-Json
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$mal = 0
foreach ($p in @($cfg.personas)) {
  $ruta = Join-Path $Cerebro ('equipo\' + $p.dueno + "\$Fecha.json")
  if (-not (Test-Path -LiteralPath $ruta)) { Write-Output "SIN_DIA $($p.dueno) $Fecha"; $mal++; continue }
  $txt = Get-Content -LiteralPath $ruta -Raw -Encoding UTF8
  $d = $txt | ConvertFrom-Json
  # El día ya viene ordenado por armar-equipo.ps1; se manda compacto.
  $dataTxt = ($d.data | ConvertTo-Json -Depth 8 -Compress)
  $cuerpo = '{"p_llave":' + (ConvertTo-Json $token) + ',"p_correo":' + (ConvertTo-Json ([string]$d.correo)) + ',"p_fecha":"' + $Fecha + '","p_data":' + $dataTxt + '}'
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($cuerpo)
  try {
    $r = Invoke-WebRequest -Uri $Url -Method Post -Body $bytes -ContentType 'application/json; charset=utf-8' `
      -Headers @{ apikey = $Publica } -UseBasicParsing
    Write-Output ("OK {0} {1} {2}" -f $p.dueno, $r.StatusCode, $r.Content)
  } catch {
    $st = $null; try { $st = $_.Exception.Response.StatusCode.value__ } catch {}
    Write-Output ("ERROR {0} {1} {2}" -f $p.dueno, $st, $_.Exception.Message); $mal++
  }
}
if ($mal) { exit 1 }
