param([string]$Root='G:\Mi unidad',[string]$Out)
# Inventario de fotos y videos de Casa Zaru en el Drive. Solo lee.
$img='.jpg','.jpeg','.png','.heic','.webp','.gif','.tif','.tiff','.bmp'
$vid='.mp4','.mov','.avi','.mkv','.m4v','.3gp','.webm','.wmv'
$fuera='Respaldo PC|Empanadas|Puerto Octay|Brasa Nativa|Google AI Studio|bocetos|Claude Code - Mar|Guardado desde Chrome|IMPRESIONES|POS BCI|Formulario sin|ADMINISTRACI|Clientes y Ventas'
$all=Get-ChildItem $Root -Recurse -File -ErrorAction SilentlyContinue | ? { ($img+$vid) -contains $_.Extension.ToLower() } | ? { $_.FullName -notmatch $fuera }
$grupos=$all | Group-Object { "$($_.Name.ToLower())|$($_.Length)" }
$rows=New-Object System.Collections.Generic.List[object]; $n=0
foreach($g in $grupos){
  $n++
  # representante: preferir el original (fuera de la Biblioteca de accesos directos)
  $rep = $g.Group | Sort-Object @{e={ if($_.FullName -like '*Biblioteca Multimedia*'){1}else{0} }}, @{e={$_.FullName.Length}} | Select-Object -First 1
  $ext=$rep.Extension.ToLower()
  $rows.Add([pscustomobject]@{
    id=('M{0:D4}' -f $n)
    tipo= if($vid -contains $ext){'video'}else{'foto'}
    nombre=$rep.Name; ext=$ext
    mb=([math]::Round($rep.Length/1MB,2)).ToString([cultureinfo]::InvariantCulture)
    fecha=$rep.LastWriteTime.ToString('yyyy-MM-dd')
    ruta=$rep.FullName.Replace($Root+'\','')
    copias=$g.Count
    otras_rutas=(($g.Group | ? { $_.FullName -ne $rep.FullName } | % { $_.FullName.Replace($Root+'\','') }) -join ' || ')
  })
}
$rows | Export-Csv -Path $Out -NoTypeInformation -Encoding UTF8
"Archivos: $($all.Count)  Únicos: $($rows.Count)  Fotos: $(($rows|?{$_.tipo -eq 'foto'}).Count)  Videos: $(($rows|?{$_.tipo -eq 'video'}).Count)"
$rows | Group-Object ext | Sort-Object Count -Descending | % { "  $($_.Name): $($_.Count)" }
