# Crea (una sola vez) un texto al azar para la bandeja de mensajes y lo deja en el portapapeles.
# Nunca lo muestra en pantalla. Si ya existe, NO lo cambia: solo lo vuelve a copiar.
# Uso:  powershell -ExecutionPolicy Bypass -File .claude\bandeja-llave.ps1 -Nombre conocimiento-token
#       powershell -ExecutionPolicy Bypass -File .claude\bandeja-llave.ps1 -Nombre meta-verify-token
# Los archivos quedan en %USERPROFILE%\.casazaru\ (fuera del repo). Solo ASCII en este archivo.
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('conocimiento-token', 'meta-verify-token')]
  [string]$Nombre
)

$dir = Join-Path $env:USERPROFILE '.casazaru'
New-Item -ItemType Directory -Force $dir | Out-Null
$ruta = Join-Path $dir "$Nombre.txt"

if (-not (Test-Path $ruta)) {
  $b = New-Object byte[] 36
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
  $nuevo = [Convert]::ToBase64String($b) -replace '[+/=]', 'x'
  [IO.File]::WriteAllText($ruta, $nuevo)
  $que = 'creada'
} else {
  $que = 'ya existia, no se cambio'
}

$t = [IO.File]::ReadAllText($ruta).Trim()
Set-Clipboard -Value $t
Write-Output "Llave $Nombre ($que): copiada al portapapeles, $($t.Length) caracteres. Pegala con Ctrl+V en Supabase."
