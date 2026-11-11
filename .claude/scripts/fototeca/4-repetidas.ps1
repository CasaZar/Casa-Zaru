param(
  [string]$Lista="$env:LOCALAPPDATA\CasaZaru\fototeca\lista-pc.csv",
  [string]$Mini="$env:LOCALAPPDATA\CasaZaru\fototeca\mini",
  [string]$Fototeca="$env:LOCALAPPDATA\CasaZaru\fototeca\huellas-fototeca.csv",
  [int]$Umbral=4,
  [int]$UmbralFototeca=3,
  [string]$Out="$env:LOCALAPPDATA\CasaZaru\fototeca\repetidas.csv"
)
# Saca las repetidas por parecido visual (dHash 64 bits sobre el cuadrado central de la miniatura):
#  - contra la Fototeca publicada (h1/h2 de las celdas de los sprites)
#  - entre ellas: de cada grupo queda la de mayor resolución (y, a igualdad, la más pesada).
# Escribe repetidas.csv: id,repite_a,distancia,motivo. No borra nada.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
. "$PSScriptRoot\dhash.ps1"
Add-Type -TypeDefinition @'
public static class Hm {
  public static int D(ulong a, ulong b){ ulong x=a^b; int c=0; while(x!=0){ x&=x-1; c++; } return c; }
  // devuelve [indice, distancia] del más cercano en arr (o -1)
  public static int[] Min(ulong h, ulong[] arr, int hasta){ int bi=-1, bd=99; for(int i=0;i<hasta;i++){ int d=D(h,arr[i]); if(d<bd){bd=d;bi=i;} } return new int[]{bi,bd}; }
}
'@
function U($hex){ [Convert]::ToUInt64($hex,16) }
$fid=New-Object System.Collections.Generic.List[string]; $fh=New-Object System.Collections.Generic.List[uint64]
foreach($r in Import-Csv $Fototeca){ $fid.Add($r.id); $fh.Add((U $r.h1)); $fid.Add($r.id); $fh.Add((U $r.h2)) }
$fArr=$fh.ToArray()
$log=@{}; Import-Csv "$Mini\_log.csv" | %{ $log[$_.id]=$_ }
$filas=@(Import-Csv $Lista | ?{ $log[$_.id].estado -eq 'ok' })
# huellas de las nuevas
$nuevas=foreach($r in $filas){
  $files= if($r.tipo -eq 'foto'){ @("$Mini\$($r.id).jpg") } else { @(Get-ChildItem $Mini -Filter "$($r.id)_*.jpg" | Sort-Object Name | % FullName) }
  $hs=foreach($f in $files){ $im=[System.Drawing.Image]::FromFile($f); try{ U (DHash $im (Cuadrado $im 1.0)) } finally { $im.Dispose() } }
  $L=$log[$r.id]; [pscustomobject]@{ id=$r.id; tipo=$r.tipo; hs=@($hs); px=[long]("0"+$L.ancho)*[long]("0"+$L.alto); bytes=[long]$r.bytes }
}
"huellas nuevas: $(@($nuevas).Count)"
$sal=New-Object System.Collections.Generic.List[string]; $sal.Add('id,repite_a,distancia,motivo')
# 1) contra la Fototeca (para videos basta que un cuadro coincida)
$quedan=New-Object System.Collections.Generic.List[object]
foreach($n in $nuevas){ $best=@(-1,99); foreach($h in $n.hs){ $m=[Hm]::Min($h,$fArr,$fArr.Length); if($m[1] -lt $best[1]){ $best=$m } }
  if($best[1] -le $UmbralFototeca){ $sal.Add("$($n.id),$($fid[$best[0]]),$($best[1]),ya en la Fototeca") } else { $quedan.Add($n) } }
# 2) entre ellas: de mejor a peor resolución; cada una se compara con las que ya quedaron
$orden=@($quedan | Sort-Object @{e='px';Descending=$true},@{e='bytes';Descending=$true})
$kid=New-Object System.Collections.Generic.List[string]; $kh=New-Object System.Collections.Generic.List[uint64]
foreach($n in $orden){ $arr=$kh.ToArray(); $best=@(-1,99)
  if($arr.Length){ foreach($h in $n.hs){ $m=[Hm]::Min($h,$arr,$arr.Length); if($m[1] -lt $best[1]){ $best=$m } } }
  if($best[1] -le $Umbral){ $sal.Add("$($n.id),$($kid[$best[0]]),$($best[1]),repetida en el PC") }
  else { foreach($h in $n.hs){ $kid.Add($n.id); $kh.Add($h) } } }
[IO.File]::WriteAllLines($Out,$sal,[Text.UTF8Encoding]::new($false))
$rep=@(Import-Csv $Out)
"repetidas: $($rep.Count)  (ya en la Fototeca: $(@($rep|?{$_.motivo -like 'ya*'}).Count), entre ellas: $(@($rep|?{$_.motivo -like 'rep*'}).Count))  quedan: $(@($nuevas).Count-$rep.Count)"
$rep | Group-Object distancia | Sort-Object {[int]$_.Name} | %{ "  distancia $($_.Name): $($_.Count)" }
