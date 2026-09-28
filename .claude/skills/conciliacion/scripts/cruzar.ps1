# Cruza los ingresos (cartola BCI y, si hay, Mercado Pago) contra Finanzas y
# propone a qué pedido corresponde cada uno. PROPONE: la asignación final la
# revisa Claude con las reglas de SKILL.md y la confirma el usuario.
#
# Uso: .\cruzar.ps1 -Bci bci.csv -Finanzas app.csv [-Mp mp.csv] -Salida cruce.csv [-Desde 2026-09-22]
#   mp.csv (opcional): columnas fecha,monto,quien,comentario,tipo
#     tipo = link | web | point | ml | otro   (point y ml se suman aparte, no se cruzan)
param(
  [Parameter(Mandatory=$true)][string]$Bci,
  [Parameter(Mandatory=$true)][string]$Finanzas,
  [string]$Mp,
  [string]$Desde = '1900-01-01',
  [Parameter(Mandatory=$true)][string]$Salida
)
$ErrorActionPreference = 'Stop'
# Flow deposita el 96,204 % de lo cobrado (medido en dos pagos de sep-2026, misma tasa).
$TASA_FLOW = 0.96204

# Cuentas propias / movimientos que NO son ventas. Los nombres de personas van en
# un archivo local fuera del repo (el repo es público): uno por línea, en minúscula.
$EXCLUIR = @('muvale', 'getnet', 'dinero plus', 'transferencia interna')
$archExcluir = Join-Path $env:USERPROFILE '.claude\conciliacion-excluir.txt'
if (Test-Path $archExcluir) { $EXCLUIR += @(Get-Content $archExcluir -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim().ToLowerInvariant() }) }
else { Write-Warning "No existe $archExcluir — las transferencias de cuentas personales propias van a aparecer como posibles ventas." }

function Norm([string]$s) {
  if (-not $s) { return '' }
  $s = $s.ToLowerInvariant().Normalize([Text.NormalizationForm]::FormD)
  (($s.ToCharArray() | Where-Object { [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark' }) -join '') -replace '[^a-z0-9 ]', ' '
}
function Tokens([string]$s) { @((Norm $s) -split '\s+' | Where-Object { $_.Length -ge 4 -and $_ -notin 'spa','ltda','chile','banco','transferencia','pedido','abono','saldo','cuota' }) }
function SoloDig([string]$s) { if ($s) { ($s -replace '[^\dkK]', '').ToUpper() } else { '' } }

$ped = @(Import-Csv $Finanzas | Where-Object { -not $_.tipo -or $_.tipo -eq 'VENTA' })
foreach ($p in $ped) {
  $p | Add-Member tok (Tokens ("$($p.cliente) $($p.razon_social)")) -Force
  $p | Add-Member rutd (SoloDig $p.rut) -Force
}

$ing = @()
Import-Csv $Bci | Where-Object { [int64]$_.ingreso -gt 0 -and $_.fecha -ge $Desde } | ForEach-Object {
  $ing += [pscustomobject]@{ fuente='BCI'; fecha=$_.fecha; monto=[int64]$_.ingreso; quien=$(if($_.nombre){$_.nombre}else{$_.glosa}); rut=$_.rut; comentario=$_.comentario; tipo='' }
}
if ($Mp) {
  Import-Csv $Mp | Where-Object { $_.fecha -ge $Desde } | ForEach-Object {
    $ing += [pscustomobject]@{ fuente='MP'; fecha=$_.fecha; monto=[int64]$_.monto; quien=$_.quien; rut=''; comentario=$_.comentario; tipo=$_.tipo }
  }
}

$out = foreach ($i in $ing) {
  $q = Norm "$($i.quien) $($i.comentario)"
  $clase = 'venta?'
  $bruto = $i.monto
  if ($i.tipo -in 'point','ml') { $clase = $i.tipo }
  elseif (@($EXCLUIR | Where-Object { $q.Contains((Norm $_).Trim()) }).Count) { $clase = 'interno (no es venta)' }
  elseif ($q -match 'flow s a') { $clase = 'pasarela'; $bruto = [int64][math]::Round($i.monto / $TASA_FLOW) }
  # Venti Pay cobra otra comisión, todavía no medida: se cruza solo por monto neto.
  elseif ($q -match 'venti pay') { $clase = 'pasarela (tasa desconocida)' }

  $cands = @()
  if ($clase -like 'venta?' -or $clase -like 'pasarela*') {
    $itok = Tokens "$($i.quien) $($i.comentario)"; $irut = SoloDig $i.rut
    foreach ($p in $ped) {
      $mot = @()
      $tot = [double]$p.total; $a = @([double]$p.a1, [double]$p.a2, [double]$p.a3)
      foreach ($m in @($i.monto, $bruto) | Select-Object -Unique) {
        for ($k = 0; $k -lt 3; $k++) { if ($a[$k] -gt 0 -and [math]::Abs($a[$k] - $m) -le 1) { $mot += "ya marcado en abono$($k+1)" } }
        if ([double]$p.saldo -gt 0 -and [math]::Abs([double]$p.saldo - $m) -le 1) { $mot += 'paga el saldo' }
        if ($tot -gt 0 -and [math]::Abs([math]::Round($tot * 0.7) - $m) -le 1) { $mot += '70% del total' }
        if ($tot -gt 0 -and [math]::Abs([math]::Round($tot * 0.3) - $m) -le 1) { $mot += '30% del total' }
      }
      if ($irut -and $p.rutd -and $irut -eq $p.rutd) { $mot += 'mismo RUT' }
      $comun = @($itok | Where-Object { $p.tok -contains $_ })
      if ($comun.Count -ge 2) { $mot += 'mismo nombre' } elseif ($comun.Count -eq 1) { $mot += "apellido/nombre '$($comun[0])'" }
      if ($mot.Count) {
        $peso = 0
        foreach ($x in $mot) { $peso += $(if ($x -match 'RUT|mismo nombre') { 3 } elseif ($x -match 'marcado|saldo|70|30') { 2 } else { 1 }) }
        $cands += [pscustomobject]@{ num = $p.num; txt = "$($p.num) $($p.cliente): " + (($mot | Select-Object -Unique) -join ', '); peso = $peso }
      }
    }
  }
  $top = @($cands | Sort-Object peso -Descending | Select-Object -First 3)
  [pscustomobject]@{
    fuente = $i.fuente; fecha = $i.fecha; monto = $i.monto; bruto = $(if ($bruto -ne $i.monto) { $bruto } else { '' })
    quien = $i.quien; comentario = $i.comentario; clase = $clase
    candidatos = ($top | ForEach-Object { $_.txt }) -join ' | '
  }
}
$out | Export-Csv -Encoding UTF8 -NoTypeInformation $Salida
$sinCand = @($out | Where-Object { ($_.clase -like 'venta?' -or $_.clase -like 'pasarela*') -and -not $_.candidatos })
"Ingresos: $($out.Count) | internos: $(@($out | ? clase -like 'interno*').Count) | sin candidato: $($sinCand.Count)"
foreach ($t in 'point','ml') {
  $g = @($out | Where-Object clase -eq $t)
  if ($g.Count) { "Total {0}: {1} ventas por {2:N0}" -f $t.ToUpper(), $g.Count, ($g | Measure-Object monto -Sum).Sum }
}
