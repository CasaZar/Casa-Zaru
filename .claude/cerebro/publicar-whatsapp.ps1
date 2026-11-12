# Cerebro Zaru - pone la última revisión de WhatsApp en la sección «WhatsApp» de «Mi día» (12-11-2026).
# La revisión (skill revision-whatsapp) deja su JSON en Revision WhatsApp\mi-dia-whatsapp.json. Este script lo
# mete en el día más reciente de Cerebro\dias\ y lo vuelve a publicar con publicar-dia.ps1 (misma Edge Function,
# mismo secreto). El día armado a las 07:30 no se toca salvo la clave «whatsapp»; componer-dia.ps1 la copia
# también, así que la sección no se pierde cuando se arma el día siguiente.
# Uso (desde Bash):
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .claude/cerebro/publicar-whatsapp.ps1
# Este archivo no lleva datos ni secretos: el repo es público.
param(
  [string]$WhatsApp = 'G:\Mi unidad\Casa Zaru\Revision WhatsApp\mi-dia-whatsapp.json',
  [string]$Dias = 'G:\Mi unidad\Casa Zaru\Cerebro\dias'
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
if (-not (Test-Path -LiteralPath $WhatsApp)) { Write-Output "SIN_REVISION: falta $WhatsApp"; exit 2 }
$wa = [System.IO.File]::ReadAllText($WhatsApp, $utf8) | ConvertFrom-Json
$ultimo = Get-ChildItem -LiteralPath $Dias -Filter '????-??-??.json' | Sort-Object Name -Descending | Select-Object -First 1
if (-not $ultimo) { Write-Output "SIN_DIA: no hay ningún día armado en $Dias"; exit 2 }
$dia = [System.IO.File]::ReadAllText($ultimo.FullName, $utf8) | ConvertFrom-Json
if ($dia.PSObject.Properties.Name -contains 'whatsapp') { $dia.whatsapp = $wa } else { $dia | Add-Member -NotePropertyName whatsapp -NotePropertyValue $wa }
[System.IO.File]::WriteAllText($ultimo.FullName, ($dia | ConvertTo-Json -Depth 12), $utf8)
& (Join-Path $PSScriptRoot 'publicar-dia.ps1') -Dia $ultimo.FullName
