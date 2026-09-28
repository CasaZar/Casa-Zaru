# Saca Finanzas (+ semana de Producción) del respaldo diario de Gestión en Drive
# y deja un CSV con una fila por pedido. El respaldo corre a las 03:00: lo que
# se marcó después NO está acá. Para el estado en vivo, ver SKILL.md (lectura
# desde la sesión del usuario en Chrome).
#
# Uso: .\leer-finanzas-respaldo.ps1 -Salida app.csv [-Respaldo ruta.json]
param(
  [string]$Respaldo,
  [Parameter(Mandatory=$true)][string]$Salida
)
$ErrorActionPreference = 'Stop'
$dir = 'G:\Mi unidad\Casa Zaru\Boletas y Facturas - Ventas 2026\Respaldos Gestion'
if (-not $Respaldo) {
  $f = Get-ChildItem $dir -Filter 'respaldo-gestion-*.json' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $f) { throw "No hay respaldos en $dir" }
  $Respaldo = $f.FullName
}
$j = [IO.File]::ReadAllText($Respaldo, [Text.Encoding]::UTF8) | ConvertFrom-Json
$prod = @{}; @($j.tablas.gestion_produccion) | ForEach-Object { $prod[$_.num] = $_.data }
$n = { param($x) if ($x -eq $null -or "$x" -eq '') { 0 } else { [double]("$x" -replace '[^\d\.-]', '') } }
$rows = @($j.tablas.gestion_finanzas) | ForEach-Object {
  $d = $_.data; $p = $prod[$_.num]
  $tot = & $n $d.total; $a1 = & $n $d.abono1; $a2 = & $n $d.abono2; $a3 = & $n $d.abono3
  [pscustomobject]@{
    num = $_.num; cliente = ("$($d.nombre) $($d.apellido)").Trim(); razon_social = $d.razon_social; rut = $d.rut
    tipo = $d.tipo; canal = $d.canal_pago; total = $tot; a1 = $a1; a2 = $a2; a3 = $a3; saldo = $tot - $a1 - $a2 - $a3
    val_envio = & $n $d.val_envio
    doc_tipo = $d.doc1_tipo
    d1 = $(if ($d.doc1_emitida) { "$($d.doc1_num)" } elseif ($d.doc1_procesando) { 'PROC' } else { '' })
    d1_monto = $d.doc1_monto
    d2 = $(if ($d.doc2_emitida) { "$($d.doc2_num)" } elseif ($d.doc2_procesando) { 'PROC' } else { '' })
    d2_monto = $d.doc2_monto
    semana = $p.envio; estado = $p.estado
  }
}
$rows | Sort-Object { [int]($_.num -replace '\D', '0') } | Export-Csv -Encoding UTF8 -NoTypeInformation $Salida
"Respaldo: $Respaldo ($((Get-Item $Respaldo).LastWriteTime))"
"Pedidos en Finanzas: $($rows.Count)"
