param([string]$Csv,[string]$Out,[string]$Hoja='Clasificación',[string]$ColLink='link',[hashtable]$Anchos=@{})
# CSV -> XLSX mínimo (sin Excel ni Python): encabezado congelado, autofiltro, links clicables y números como número.
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$rows=Import-Csv $Csv; $cols=@($rows[0].PSObject.Properties.Name)
function Col([int]$i){ $s=''; $i++; while($i -gt 0){ $m=($i-1)%26; $s=[char](65+$m)+$s; $i=[math]::Floor(($i-1)/26) }; $s }
function X([string]$t){ [Security.SecurityElement]::Escape($t) -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]','' }
$num=@('calidad','duracion_s','mb','otras_ubicaciones')
$sb=New-Object Text.StringBuilder
[void]$sb.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">')
[void]$sb.Append('<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols>')
for($c=0;$c -lt $cols.Count;$c++){ $w= if($Anchos[$cols[$c]]){$Anchos[$cols[$c]]}else{14}; [void]$sb.Append("<col min=`"$($c+1)`" max=`"$($c+1)`" width=`"$w`" customWidth=`"1`"/>") }
[void]$sb.Append('</cols><sheetData><row r="1">')
for($c=0;$c -lt $cols.Count;$c++){ [void]$sb.Append("<c r=`"$(Col $c)1`" t=`"inlineStr`" s=`"1`"><is><t>$(X $cols[$c])</t></is></c>") }
[void]$sb.Append('</row>')
$r=1
foreach($row in $rows){ $r++; [void]$sb.Append("<row r=`"$r`">")
  for($c=0;$c -lt $cols.Count;$c++){ $n=$cols[$c]; $v=[string]$row.$n; if($v -eq ''){ continue }; $ref="$(Col $c)$r"
    if($n -eq $ColLink){ [void]$sb.Append("<c r=`"$ref`" t=`"str`" s=`"2`"><f>HYPERLINK(&quot;$(X $v)&quot;,&quot;Abrir&quot;)</f><v>Abrir</v></c>") }
    elseif($num -contains $n -and $v -match '^-?\d+(\.\d+)?$'){ [void]$sb.Append("<c r=`"$ref`"><v>$v</v></c>") }
    else{ [void]$sb.Append("<c r=`"$ref`" t=`"inlineStr`"><is><t xml:space=`"preserve`">$(X $v)</t></is></c>") } }
  [void]$sb.Append('</row>') }
[void]$sb.Append("</sheetData><autoFilter ref=`"A1:$(Col ($cols.Count-1))$r`"/></worksheet>")
$files=@{
 '[Content_Types].xml'='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>'
 '_rels/.rels'='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'
 'xl/workbook.xml'="<?xml version=`"1.0`" encoding=`"UTF-8`" standalone=`"yes`"?><workbook xmlns=`"http://schemas.openxmlformats.org/spreadsheetml/2006/main`" xmlns:r=`"http://schemas.openxmlformats.org/officeDocument/2006/relationships`"><sheets><sheet name=`"$(X $Hoja)`" sheetId=`"1`" r:id=`"rId1`"/></sheets><definedNames><definedName name=`"_xlnm._FilterDatabase`" localSheetId=`"0`" hidden=`"1`">'$(X $Hoja)'!`$A`$1:`$$(Col ($cols.Count-1))`$$r</definedName></definedNames></workbook>"
 'xl/_rels/workbook.xml.rels'='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>'
 'xl/styles.xml'='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="3"><font><sz val="10"/><name val="Arial"/></font><font><b/><sz val="10"/><color rgb="FFFFFFFF"/><name val="Arial"/></font><font><u/><sz val="10"/><color rgb="FF485B3D"/><name val="Arial"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF485B3D"/></patternFill></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf/></cellStyleXfs><cellXfs count="3"><xf/><xf fontId="1" fillId="2" applyFont="1" applyFill="1"/><xf fontId="2" applyFont="1"/></cellXfs></styleSheet>'
 'xl/worksheets/sheet1.xml'=$sb.ToString() }
if(Test-Path $Out){ Remove-Item $Out -Confirm:$false }
$zip=[IO.Compression.ZipFile]::Open($Out,'Create'); $enc=[Text.UTF8Encoding]::new($false)
foreach($k in $files.Keys){ $e=$zip.CreateEntry($k); $s=$e.Open(); $b=$enc.GetBytes($files[$k]); $s.Write($b,0,$b.Length); $s.Close() }
$zip.Dispose(); "xlsx: $Out  filas: $($rows.Count)"
