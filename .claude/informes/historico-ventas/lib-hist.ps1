# Libreria del historico de ventas: numeros, normalizacion, fechas, CSV y escritor xlsx (copiado del libro mensual).
$INV = [Globalization.CultureInfo]::InvariantCulture

function Norm([string]$s) {
  if ($null -eq $s) { return '' }
  $d = $s.Normalize([Text.NormalizationForm]::FormD)
  $sb = New-Object Text.StringBuilder
  foreach ($ch in $d.ToCharArray()) { if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) } }
  return (($sb.ToString().ToUpperInvariant()) -replace '[^A-Z0-9]', '')
}
function Limpio([string]$s) { if ($null -eq $s) { return '' } return (($s -replace '\s+', ' ').Trim()) }
function Num($s) {
  if ($null -eq $s) { return $null }
  $t = "$s".Trim()
  if ($t -eq '' -or $t -eq '.' -or $t -eq '-' -or $t -eq 'p' -or $t -eq 'P') { return $null }
  if ($t -match '^-?\d+(\.\d+)?$') { return [double]::Parse($t, $INV) }
  if ($t -match '^-?\d+(\.\d+)?[Ee][+-]?\d+$') { return [double]::Parse($t, $INV) }
  if ($t -match '^\$?\s*-?[\d\.\s]+\.?\s*$') { $dg = $t -replace '[^\d-]', ''; if ($dg -match '^-?\d+$') { return [double]$dg } }
  if ($t -match '^\$?\s*-?[\d,]+(\.\d+)?$') { return [double]::Parse(($t -replace '[\$,\s]', ''), $INV) }
  return $null
}
function Entero($v) { if ($null -eq $v) { return $null } return [math]::Round([double]$v) }
function Lunes([datetime]$d) { return $d.Date.AddDays(-(([int]$d.DayOfWeek + 6) % 7)) }
function FechaDe($s) {
  if ($null -eq $s) { return $null }
  $t = "$s".Trim()
  if ($t -match '^(\d{4})-(\d{2})-(\d{2})') { try { return (Get-Date -Year ([int]$matches[1]) -Month ([int]$matches[2]) -Day ([int]$matches[3])).Date } catch { return $null } }
  if ($t -match '^(\d{1,2})\s*[-/]\s*(\d{1,2})\s*[-/]\s*(\d{2,4})$') {
    $y = [int]$matches[3]; if ($y -lt 100) { $y += 2000 }
    try { return (Get-Date -Year $y -Month ([int]$matches[2]) -Day ([int]$matches[1])).Date } catch { return $null }
  }
  return $null
}
$MESES3 = @{ ENE = 1; FEB = 2; MAR = 3; ABR = 4; MAY = 5; JUN = 6; JUL = 7; AGO = 8; SEP = 9; OCT = 10; NOV = 11; DIC = 12 }
function MesDeTexto([string]$tok) { $n = Norm $tok; if ($n.Length -lt 3) { return 0 }; $k = $n.Substring(0, 3); if ($MESES3.ContainsKey($k)) { return $MESES3[$k] } return 0 }
function LeerHoja($path) { return @(Import-Csv -LiteralPath $path -Delimiter ';' -Encoding UTF8) }
function Celda($row, [string]$col) { if (-not $col) { return $null }; $p = $row.PSObject.Properties[$col]; if ($p) { return $p.Value } return $null }
function ColIdx([string]$col) { $n = 0; foreach ($ch in $col.ToCharArray()) { $n = $n * 26 + ([int][char]$ch - 64) }; return $n }
function ColDeIdx([int]$n) { $s = ''; while ($n -gt 0) { $r = [int](($n - 1) % 26); $s = [string][char](65 + $r) + $s; $n = [int][math]::Floor(($n - 1) / 26) }; return $s }
function ColSig([string]$col) { return (ColDeIdx ((ColIdx $col) + 1)) }
function GuardarCsv($filas, $path) {
  if (@($filas).Count -eq 0) { [IO.File]::WriteAllText($path, '', (New-Object Text.UTF8Encoding $true)); return }
  $tmp = @($filas) | ConvertTo-Csv -Delimiter ';' -NoTypeInformation
  [IO.File]::WriteAllLines($path, $tmp, (New-Object Text.UTF8Encoding $true))
}

# ===== Escritor xlsx (mismas funciones que .claude/informes/libro-mensual.ps1) =====
function X($s) { [Security.SecurityElement]::Escape("$s") }
function ColL($i) { $s = ''; $i = [int]$i + 1; while ($i -gt 0) { $m = [int](($i - 1) % 26); $s = "$([char](65 + $m))$s"; $i = [int][math]::Floor(($i - 1) / 26) }; $s }
# Estilos: 0 normal 1 encabezado 2 pesos 3 pesos total 4 % 5 titulo 6 nota 7 entero 8 decimal 9 texto total 10 aviso 11 negrita 12 % total 13 pesos negrita 14 texto ajustado 15 subtitulo
function C($v, $s = $null) { @{ v = $v; s = $s } }
function F($f, $s = 2) { @{ f = $f; s = $s } }
$script:hojas = New-Object System.Collections.ArrayList
function Hoja($nombre, $filas, $anchos, $congelar = 0) { [void]$script:hojas.Add(@{ nombre = $nombre; filas = $filas; anchos = $anchos; congelar = $congelar }) }
function CeldaXml($ref, $c) {
  if ($c -eq $null) { return '' }
  if ($c -isnot [hashtable]) { $c = @{ v = $c } }
  $s = $c.s; $v = $c.v
  if ($c.f) { return "<c r=""$ref"" s=""$(if ($s -ne $null) { $s } else { 2 })""><f>$(X $c.f)</f></c>" }
  if ($v -eq $null -or "$v" -eq '') { if ($s) { return "<c r=""$ref"" s=""$s""/>" } else { return '' } }
  if ($v -is [int] -or $v -is [long] -or $v -is [double] -or $v -is [decimal]) {
    if ($s -eq $null) { $s = if ($v -is [int] -or $v -is [long]) { 7 } else { 2 } }
    return "<c r=""$ref"" s=""$s""><v>$(([double]$v).ToString('R', $INV))</v></c>"
  }
  if ($v -is [datetime]) { $v = $v.ToString('dd-MM-yyyy') }
  if ($s -eq $null) { $s = 0 }
  "<c r=""$ref"" s=""$s"" t=""inlineStr""><is><t xml:space=""preserve"">$(X $v)</t></is></c>"
}
function HojaXml($h) {
  $sb = New-Object Text.StringBuilder
  [void]$sb.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">')
  [void]$sb.Append('<sheetViews><sheetView workbookViewId="0" showGridLines="0">')
  if ($h.congelar) { [void]$sb.Append("<pane ySplit=""$($h.congelar)"" topLeftCell=""A$($h.congelar + 1)"" activePane=""bottomLeft"" state=""frozen""/>") }
  [void]$sb.Append('</sheetView></sheetViews><cols>')
  for ($i = 0; $i -lt $h.anchos.Count; $i++) { [void]$sb.Append("<col min=""$($i+1)"" max=""$($i+1)"" width=""$($h.anchos[$i])"" customWidth=""1""/>") }
  [void]$sb.Append('</cols><sheetData>')
  $r = 0
  foreach ($fila in $h.filas) {
    $r++; [void]$sb.Append("<row r=""$r"">")
    $cI = 0; foreach ($c in @($fila)) { [void]$sb.Append((CeldaXml "$(ColL $cI)$r" $c)); $cI++ }
    [void]$sb.Append('</row>')
  }
  [void]$sb.Append('</sheetData><pageMargins left="0.5" right="0.5" top="0.6" bottom="0.6" header="0.3" footer="0.3"/><pageSetup orientation="landscape" fitToWidth="1" fitToHeight="0"/></worksheet>')
  $sb.ToString()
}
function GuardarXlsx($ruta) {
  $hojas = $script:hojas
  $tmp = Join-Path $env:TEMP ("libro-" + [guid]::NewGuid()); New-Item -ItemType Directory $tmp | Out-Null
  New-Item -ItemType Directory "$tmp\_rels", "$tmp\xl", "$tmp\xl\_rels", "$tmp\xl\worksheets" | Out-Null
  $u = New-Object Text.UTF8Encoding($false)
  $ct = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
  $wbS = ''; $wbR = ''
  for ($i = 0; $i -lt $hojas.Count; $i++) {
    $n = $i + 1
    [IO.File]::WriteAllText("$tmp\xl\worksheets\sheet$n.xml", (HojaXml $hojas[$i]), $u)
    $ct += "<Override PartName=""/xl/worksheets/sheet$n.xml"" ContentType=""application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml""/>"
    $wbS += "<sheet name=""$(X $hojas[$i].nombre)"" sheetId=""$n"" r:id=""rId$n""/>"
    $wbR += "<Relationship Id=""rId$n"" Type=""http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"" Target=""worksheets/sheet$n.xml""/>"
  }
  $ct += '</Types>'
  [IO.File]::WriteAllText("$tmp\[Content_Types].xml", $ct, $u)
  [IO.File]::WriteAllText("$tmp\_rels\.rels", '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>', $u)
  [IO.File]::WriteAllText("$tmp\xl\workbook.xml", "<?xml version=""1.0"" encoding=""UTF-8"" standalone=""yes""?><workbook xmlns=""http://schemas.openxmlformats.org/spreadsheetml/2006/main"" xmlns:r=""http://schemas.openxmlformats.org/officeDocument/2006/relationships""><sheets>$wbS</sheets><calcPr calcId=""191029"" fullCalcOnLoad=""1""/></workbook>", $u)
  $n = $hojas.Count + 1
  [IO.File]::WriteAllText("$tmp\xl\_rels\workbook.xml.rels", "<?xml version=""1.0"" encoding=""UTF-8"" standalone=""yes""?><Relationships xmlns=""http://schemas.openxmlformats.org/package/2006/relationships"">$wbR<Relationship Id=""rId$n"" Type=""http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles"" Target=""styles.xml""/></Relationships>", $u)
  $st = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<numFmts count="3"><numFmt numFmtId="164" formatCode="&quot;$&quot;#,##0;[Red]-&quot;$&quot;#,##0"/><numFmt numFmtId="165" formatCode="0.0%"/><numFmt numFmtId="166" formatCode="#,##0.00"/></numFmts>
<fonts count="7"><font><sz val="10"/><name val="Arial"/></font><font><b/><sz val="10"/><name val="Arial"/></font><font><b/><sz val="15"/><color rgb="FF5C3D20"/><name val="Arial"/></font><font><i/><sz val="9"/><color rgb="FF8A7960"/><name val="Arial"/></font><font><b/><sz val="10"/><color rgb="FFFFFFFF"/><name val="Arial"/></font><font><sz val="10"/><color rgb="FF8A3B12"/><name val="Arial"/></font><font><b/><sz val="11"/><color rgb="FF7B5B3A"/><name val="Arial"/></font></fonts>
<fills count="6"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFF2ECE4"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFF7F2EC"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FF5C3D20"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFFDF6E8"/></patternFill></fill></fills>
<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left/><right/><top style="thin"><color rgb="FFB8A890"/></top><bottom/><diagonal/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="16">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>
<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="164" fontId="1" fillId="3" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1"/>
<xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>
<xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment wrapText="1" vertical="top"/></xf>
<xf numFmtId="3" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="166" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="0" fontId="1" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/>
<xf numFmtId="0" fontId="5" fillId="5" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment wrapText="1" vertical="top"/></xf>
<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
<xf numFmtId="165" fontId="1" fillId="3" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1"/>
<xf numFmtId="164" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/>
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment wrapText="1" vertical="top"/></xf>
<xf numFmtId="0" fontId="6" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>
'@
  [IO.File]::WriteAllText("$tmp\xl\styles.xml", $st, $u)
  if (Test-Path -LiteralPath $ruta) { Remove-Item -LiteralPath $ruta }
  Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
  $zip = [IO.Compression.ZipFile]::Open($ruta, 'Create')
  try {
    foreach ($a in Get-ChildItem -LiteralPath $tmp -Recurse -File) {
      $nombre = $a.FullName.Substring($tmp.Length + 1).Replace('\', '/')
      [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $a.FullName, $nombre)
    }
  } finally { $zip.Dispose() }
  Remove-Item -LiteralPath $tmp -Recurse
}
function Tabla([System.Collections.ArrayList]$filas, $cols, $datos, $sumar = @()) {
  [void]$filas.Add(@($cols | ForEach-Object { C $_ 1 }))
  $ini = $filas.Count + 1
  foreach ($d in $datos) { [void]$filas.Add(@($d)) }
  $fin = $filas.Count
  if ($sumar.Count) {
    $tot = for ($i = 0; $i -lt $cols.Count; $i++) {
      if ($i -eq 0) { C 'Total' 9 } elseif ($sumar -contains $i) { if ($fin -ge $ini) { F "SUM($(ColL $i)$($ini):$(ColL $i)$fin)" 3 } else { C 0 3 } } else { C '' 9 }
    }
    [void]$filas.Add(@($tot))
  }
  [void]$filas.Add(@())
}
function Titulo([System.Collections.ArrayList]$filas, $t, $sub) { [void]$filas.Add(@(C $t 5)); if ($sub) { [void]$filas.Add(@(C $sub 6)) }; [void]$filas.Add(@()) }
function Sub([System.Collections.ArrayList]$filas, $t) { [void]$filas.Add(@(C $t 15)) }
function Nota([System.Collections.ArrayList]$filas, $t) { [void]$filas.Add(@(C $t 6)) }
