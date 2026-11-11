# Cerebro Zaru - publica el día armado en la pestaña «Mi día» de la Gestión (Edge Function cerebro-dia).
# Uso (desde Bash):
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .claude/cerebro/publicar-dia.ps1 -Dia "G:/Mi unidad/Casa Zaru/Cerebro/dias/2026-11-12.json"
# El secreto se lee de %USERPROFILE%\.casazaru\cerebro-token.txt y nunca se imprime.
# Este archivo no lleva datos ni secretos: el repo es público.
param(
  [Parameter(Mandatory=$true)][string]$Dia,
  [string]$Url = 'https://padnttpgzuotxeipjrry.supabase.co/functions/v1/cerebro-dia',
  [string]$TokenRuta = (Join-Path $env:USERPROFILE '.casazaru\cerebro-token.txt')
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $TokenRuta)) { Write-Output "SIN_TOKEN: falta $TokenRuta"; exit 2 }
$token = (Get-Content -LiteralPath $TokenRuta -Raw).Trim()
$json = Get-Content -LiteralPath $Dia -Raw -Encoding UTF8
$d = $json | ConvertFrom-Json
if (-not $d.fecha) { Write-Output 'SIN_FECHA en el JSON del día'; exit 2 }
# Se arma el cuerpo como texto para no re-serializar (y desordenar) el día.
$cuerpo = '{"fecha":"' + $d.fecha + '","data":' + $json.Trim() + '}'
$bytes = [System.Text.Encoding]::UTF8.GetBytes($cuerpo)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try {
  $r = Invoke-WebRequest -Uri $Url -Method Post -Body $bytes -ContentType 'application/json; charset=utf-8' -Headers @{ 'x-cerebro-token' = $token } -UseBasicParsing
  Write-Output ("OK {0} {1}" -f $r.StatusCode, $r.Content)
} catch {
  $st = $null; try { $st = $_.Exception.Response.StatusCode.value__ } catch {}
  Write-Output ("ERROR {0} {1}" -f $st, $_.Exception.Message); exit 1
}
