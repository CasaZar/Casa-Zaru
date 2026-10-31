# Exporta cada hoja de un .xlsx a un CSV (;) con columnas alineadas (A,B,C...).
# Uso: export-xlsx.ps1 -Path <xlsx> -OutDir <carpeta>
param([Parameter(Mandatory=$true)][string]$Path, [Parameter(Mandatory=$true)][string]$OutDir)
Add-Type -AssemblyName System.IO.Compression.FileSystem
$inv = [Globalization.CultureInfo]::InvariantCulture

function ColIndex([string]$ref) {
  $letters = ($ref -replace '[0-9]', '')
  $n = 0
  foreach ($ch in $letters.ToCharArray()) { $n = $n * 26 + ([int][char]$ch - 64) }
  return $n - 1
}
function ColName([int]$i) {
  $s = ''; $i = $i + 1
  while ($i -gt 0) { $r = ($i - 1) % 26; $s = [char](65 + $r) + $s; $i = [math]::Floor(($i - 1) / 26) }
  return $s
}
function ReadEntry($zip, [string]$name) {
  $e = $zip.GetEntry($name); if (-not $e) { return $null }
  $sr = New-Object IO.StreamReader($e.Open(), [Text.Encoding]::UTF8)
  $t = $sr.ReadToEnd(); $sr.Close(); return $t
}
function IsDateFormat([int]$id, [string]$code) {
  if (($id -ge 14 -and $id -le 22) -or ($id -ge 45 -and $id -le 47)) { return $true }
  if (-not $code) { return $false }
  $c = $code.ToLower()
  $c = [regex]::Replace($c, '"[^"]*"', '')
  $c = [regex]::Replace($c, '\[[^\]]*\]', '')
  $c = $c -replace '\.', ''
  if ($c -match '[#0]') { return $false }
  return ($c -match '[ymdh]')
}

$zip = [IO.Compression.ZipFile]::OpenRead($Path)
try {
  $wb = [xml](ReadEntry $zip 'xl/workbook.xml')
  $rels = [xml](ReadEntry $zip 'xl/_rels/workbook.xml.rels')
  # shared strings
  $strings = New-Object Collections.Generic.List[string]
  $sst = ReadEntry $zip 'xl/sharedStrings.xml'
  if ($sst) {
    $d = New-Object Xml.XmlDocument; $d.PreserveWhitespace = $true; $d.LoadXml($sst)
    foreach ($si in $d.DocumentElement.ChildNodes) {
      $txt = ''
      foreach ($t in $si.GetElementsByTagName('t')) { if ($t.ParentNode.LocalName -ne 'rPh') { $txt += $t.InnerText } }
      $strings.Add($txt)
    }
  }
  # styles -> date flags per xf index
  $dateXf = @{}
  $st = ReadEntry $zip 'xl/styles.xml'
  if ($st) {
    $sd = [xml]$st
    $fmts = @{}
    if ($sd.styleSheet.numFmts) { foreach ($nf in $sd.styleSheet.numFmts.numFmt) { $fmts[[int]$nf.numFmtId] = [string]$nf.formatCode } }
    $i = 0
    if ($sd.styleSheet.cellXfs) {
      foreach ($xf in $sd.styleSheet.cellXfs.xf) {
        $id = 0; if ($xf.numFmtId) { $id = [int]$xf.numFmtId }
        $code = $null; if ($fmts.ContainsKey($id)) { $code = $fmts[$id] }
        $dateXf[$i] = (IsDateFormat $id $code)
        $i++
      }
    }
  }
  $epoch = [datetime]::new(1899, 12, 30)
  $resumen = New-Object Collections.Generic.List[string]
  $nSheet = 0
  foreach ($s in $wb.workbook.sheets.sheet) {
    $nSheet++
    $rid = $s.GetAttribute('r:id')
    $target = ($rels.Relationships.Relationship | Where-Object { $_.Id -eq $rid }).Target
    $entry = if ($target.StartsWith('/')) { $target.TrimStart('/') } else { 'xl/' + $target }
    $xmlTxt = ReadEntry $zip $entry
    $sd = New-Object Xml.XmlDocument; $sd.PreserveWhitespace = $true; $sd.LoadXml($xmlTxt)
    $rows = @{}
    $maxCol = -1
    foreach ($r in $sd.DocumentElement.GetElementsByTagName('row')) {
      $rn = [int]$r.GetAttribute('r')
      foreach ($c in $r.ChildNodes) {
        if ($c.LocalName -ne 'c') { continue }
        $ref = $c.GetAttribute('r'); if (-not $ref) { continue }
        $ci = ColIndex $ref
        $t = $c.GetAttribute('t'); $sIdx = $c.GetAttribute('s')
        $val = $null
        if ($t -eq 'inlineStr') {
          $val = ''; foreach ($tt in $c.GetElementsByTagName('t')) { $val += $tt.InnerText }
        } else {
          $vn = $null
          foreach ($ch in $c.ChildNodes) { if ($ch.LocalName -eq 'v') { $vn = $ch; break } }
          if ($vn -ne $null) {
            $val = $vn.InnerText
            if ($t -eq 's') { $val = $strings[[int]$val] }
            elseif ($t -eq 'b') { $val = if ($val -eq '1') { 'TRUE' } else { 'FALSE' } }
            elseif ($t -eq 'e') { $val = '#ERR:' + $val }
            elseif ($t -eq 'str') { }
            else {
              # numero
              $isDate = $false
              if ($sIdx -ne '' -and $dateXf.ContainsKey([int]$sIdx)) { $isDate = $dateXf[[int]$sIdx] }
              if ($isDate) {
                $num = [double]::Parse($val, $inv)
                if ($num -gt 0 -and $num -lt 100000) {
                  $dt = $epoch.AddDays($num)
                  if ($num -eq [math]::Floor($num)) { $val = $dt.ToString('yyyy-MM-dd') } else { $val = $dt.ToString('yyyy-MM-dd HH:mm') }
                }
              }
            }
          }
        }
        if ($val -eq $null -or $val -eq '') { continue }
        if (-not $rows.ContainsKey($rn)) { $rows[$rn] = @{} }
        $rows[$rn][$ci] = [string]$val
        if ($ci -gt $maxCol) { $maxCol = $ci }
      }
    }
    $name = $s.name
    $safe = ($name -replace '[\/:*?"<>|]', '_').Trim()
    $out = Join-Path $OutDir ('{0:D2}_{1}.csv' -f $nSheet, $safe)
    $lines = New-Object Collections.Generic.List[string]
    $hdr = @('fila'); for ($k = 0; $k -le $maxCol; $k++) { $hdr += (ColName $k) }
    $lines.Add(($hdr -join ';'))
    $nRows = 0
    foreach ($rn in ($rows.Keys | Sort-Object)) {
      $cells = @([string]$rn)
      for ($k = 0; $k -le $maxCol; $k++) {
        $v = ''
        if ($rows[$rn].ContainsKey($k)) { $v = $rows[$rn][$k] }
        $v = $v -replace '"', '""'
        $v = $v -replace "`r?`n", ' '
        $cells += ('"' + $v + '"')
      }
      $lines.Add(($cells -join ';'))
      $nRows++
    }
    [IO.File]::WriteAllLines($out, $lines, (New-Object Text.UTF8Encoding $true))
    $resumen.Add(('{0}|{1}|{2}|{3}' -f $nSheet, $name, $nRows, ($maxCol + 1)))
  }
  $resumen | ForEach-Object { Write-Output $_ }
} finally { $zip.Dispose() }
