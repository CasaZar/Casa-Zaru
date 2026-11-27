# Extrae la capa de texto de un PDF sin herramientas externas (aquí no hay pdftotext ni Python).
# Descomprime los streams FlateDecode que tienen texto (operador Tf) y junta los strings (...) de Tj/TJ.
# Sirve para PDF con fuentes estándar (ej. Wood Handbook 1999). No sirve para PDF escaneados ni con
# fuentes CID: ahí sale basura y hay que buscar otra copia.
# Uso: powershell -File pdf-texto.ps1 -Entrada <archivo.pdf> -Salida <archivo.txt>
param(
  [Parameter(Mandatory)] [string] $Entrada,
  [Parameter(Mandatory)] [string] $Salida
)
$bytes = [IO.File]::ReadAllBytes($Entrada)
$latin = [Text.Encoding]::GetEncoding(28591)
$s = $latin.GetString($bytes)
$sb = New-Object Text.StringBuilder
$idx = 0
while (($m = $s.IndexOf('stream', $idx)) -ge 0) {
  if ($m -ge 3 -and $s.Substring($m - 3, 3) -eq 'end') { $idx = $m + 6; continue }
  $dictIni = [Math]::Max(0, $m - 600)
  $dict = $s.Substring($dictIni, $m - $dictIni)
  $ultimo = $dict.LastIndexOf('<<')
  if ($ultimo -ge 0) { $dict = $dict.Substring($ultimo) }
  $start = $m + 6
  if ($s[$start] -eq "`r") { $start++ }
  if ($s[$start] -eq "`n") { $start++ }
  $end = $s.IndexOf('endstream', $start)
  if ($end -lt 0) { break }
  $idx = $end + 9
  if ($dict -match 'Image|DCT|CCITT|FontFile|Length1|/XObject') { continue }
  $txt = $null
  if ($dict -match 'FlateDecode') {
    try {
      $ms = New-Object IO.MemoryStream($bytes, ($start + 2), ($end - $start - 2))
      $ds = New-Object IO.Compression.DeflateStream($ms, [IO.Compression.CompressionMode]::Decompress)
      $txt = (New-Object IO.StreamReader($ds, $latin)).ReadToEnd()
    } catch { continue }
  } else { $txt = $s.Substring($start, $end - $start) }
  if ($txt -notmatch '\bTf\b') { continue }
  foreach ($t in [regex]::Matches($txt, '\((?:\\.|[^\\)])*\)|T\*|\bT[dD]\b|\bET\b')) {
    $v = $t.Value
    if ($v.StartsWith('(')) {
      $v = $v.Substring(1, $v.Length - 2)
      $v = [regex]::Replace($v, '\\([0-7]{1,3})', { param($x) [string][char][Convert]::ToInt32($x.Groups[1].Value, 8) })
      $v = $v -replace '\\(.)', '$1'
      [void]$sb.Append($v)
    } else { [void]$sb.Append(' ') }
  }
  [void]$sb.Append("`n")
}
[IO.File]::WriteAllText($Salida, $sb.ToString())
"{0} caracteres -> {1}" -f $sb.Length, $Salida
