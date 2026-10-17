# Tablero de Casa Zaru: una página HTML simple que se genera junto con el libro mensual.
# Se carga desde libro-mensual.ps1 (dot-source) y usa las variables que ese script ya calculó.
# No depende de internet: sin librerías, sin fuentes externas. Se abre con doble clic desde Drive.
#
# Qué muestra, en este orden: seis números con su variación contra el mes anterior, el semáforo
# (qué está bien y qué falla, con la acción), la venta y el resultado mes a mes, y qué falta para cerrar.

function Tablero($ruta) {
  function Hx($s) { [Security.SecurityElement]::Escape("$s") }
  function Mill($v) { $v = [double]$v; if ([math]::Abs($v) -ge 1000000) { '$' + ($v / 1000000).ToString('N1', $cl) + 'M' } elseif ([math]::Abs($v) -ge 1000) { '$' + ($v / 1000).ToString('N0', $cl) + 'k' } else { '$' + $v.ToString('N0', $cl) } }
  function Delta($actual, $campoAnt, $mejorSiSube = $true) {
    if (-not $ant) { return '<span class="delta muted">sin mes anterior</span>' }
    $a = [double]$ant.$campoAnt; $d = [double]$actual - $a
    if ([math]::Abs($d) -lt 1) { return '<span class="delta muted">igual que el mes anterior</span>' }
    $sube = $d -gt 0; $bien = if ($mejorSiSube) { $sube } else { -not $sube }
    $cls = if ($bien) { 'bien' } else { 'mal' }
    $flecha = if ($sube) { '▲' } else { '▼' }
    "<span class=`"delta $cls`">$flecha $(Mill ([math]::Abs($d))) vs $(Hx $tagAnt)</span>"
  }
  function Tile($titulo, $valor, $delta, $nota) { "<div class=`"tile`"><div class=`"t`">$(Hx $titulo)</div><div class=`"v`">$(Hx $valor)</div>$delta<div class=`"n`">$(Hx $nota)</div></div>" }

  # Barras mes a mes (inline SVG, una serie por gráfico, etiquetas directas)
  function Barras($campo, $titulo, $polaridad) {
    $filas = @($histTodo | Select-Object -Last 8)
    if (-not $filas.Count) { return '' }
    $vals = @($filas | ForEach-Object { [double]$_.$campo })
    $max = ($vals | ForEach-Object { [math]::Abs($_) } | Measure-Object -Maximum).Maximum; if (-not $max) { $max = 1 }
    $w = 640; $h = 220; $padL = 16; $padR = 16; $top = 28; $bottom = 40
    $n = $filas.Count; $slot = ($w - $padL - $padR) / $n; $bw = [math]::Min(72, $slot * 0.62)
    $zona = $h - $top - $bottom
    $cero = if ($polaridad) { $top + $zona / 2 } else { $top + $zona }
    $escala = if ($polaridad) { ($zona / 2) / $max } else { $zona / $max }
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append("<figure class=`"chart`"><figcaption>$(Hx $titulo)</figcaption><svg viewBox=`"0 0 $w $h`" role=`"img`" aria-label=`"$(Hx $titulo)`">")
    [void]$sb.Append("<line x1=`"$padL`" x2=`"$($w - $padR)`" y1=`"$cero`" y2=`"$cero`" class=`"base`"/>")
    for ($i = 0; $i -lt $n; $i++) {
      $v = $vals[$i]; $x = $padL + $slot * $i + ($slot - $bw) / 2
      $alto = [math]::Max(2, [math]::Abs($v) * $escala)
      $y = if ($v -ge 0) { $cero - $alto } else { $cero }
      $cls = if ($polaridad -and $v -lt 0) { 'neg' } else { 'pos' }
      $parcial = if ("$($filas[$i].Estado)" -match 'parcial') { ' parcial' } else { '' }
      $et = Mill $v; $yEt = if ($v -ge 0) { $y - 6 } else { $y + $alto + 14 }
      $mesEt = [datetime]::ParseExact("$($filas[$i].Mes)-01", 'yyyy-MM-dd', $INV).ToString('MMM yy', $cl)
      [void]$sb.Append("<rect class=`"bar $cls$parcial`" x=`"$([math]::Round($x,1))`" y=`"$([math]::Round($y,1))`" width=`"$([math]::Round($bw,1))`" height=`"$([math]::Round($alto,1))`" rx=`"4`"><title>$(Hx $filas[$i].Mes): $(Plata $v)$(if ($parcial) { ' (parcial)' })</title></rect>")
      [void]$sb.Append("<text class=`"val`" x=`"$([math]::Round($x + $bw / 2,1))`" y=`"$([math]::Round($yEt,1))`" text-anchor=`"middle`">$(Hx $et)</text>")
      [void]$sb.Append("<text class=`"mes`" x=`"$([math]::Round($x + $bw / 2,1))`" y=`"$($h - 14)`" text-anchor=`"middle`">$(Hx $mesEt)$(if ($parcial) { '*' })</text>")
    }
    [void]$sb.Append('</svg></figure>')
    $sb.ToString()
  }

  $tiles = (Tile 'Venta neta' (Plata $ventaNeta) (Delta $ventaNeta 'VentaNeta') "$($vMes.Count) pedidos + Mercado Libre + ferias") +
           (Tile 'Resultado del mes' (Plata $resultado) (Delta $resultado 'Resultado') 'después de todos los gastos') +
           (Tile 'Margen bruto' "$([math]::Round($pctMB * 100)) %" (Delta $margenBruto 'MargenBruto') "$(Plata $margenBruto), venta menos materiales") +
           (Tile 'Caja' (Plata $cajaFin) (Delta $cajaFin 'Caja') 'BCI + Banco de Chile + Mercado Pago') +
           (Tile 'Por cobrar' (Plata $porCobrar) (Delta $porCobrar 'PorCobrar' $false) "$($cobrar.Count) pedidos con saldo") +
           (Tile 'Publicidad por pedido' (Plata ([math]::Round($cac))) (Delta $cac 'CAC' $false) "$(Plata $ads) en Meta y Google")
  $luces = ($semaforo | ForEach-Object { "<li class=`"$($_.estado)`"><span class=`"ic`" aria-hidden=`"true`">$($_.icono)</span><div><b>$(Hx $_.nombre)</b> <span class=`"est`">$(Hx $_.estado.ToUpper())</span><div class=`"d`">$(Hx $_.valor). $(Hx $_.accion)</div></div></li>" }) -join ''
  $pendHtml = ($falta | ForEach-Object { "<li>$(Hx $_)</li>" }) -join ''
  $avisosHtml = (@($avisos | Select-Object -First 6) | ForEach-Object { "<li>$(Hx $_)</li>" }) -join ''
  $masAvisos = if ($avisos.Count -gt 6) { "<p class=`"muted`">y $($avisos.Count - 6) avisos más en el libro.</p>" } else { '' }

  $css = @'
:root{--bg:#F1ECE4;--card:#FFFFFF;--ink:#2B2622;--muted:#6B625A;--line:#E3DCCF;--verde:#485B3D;--terracota:#B5652E;--dorado:#D4AC74;--dorado-ink:#5C4512;--bar:#485B3D;--bar-neg:#B5652E}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#1F1C19;--card:#2A2622;--ink:#F1ECE4;--muted:#B8AEA2;--line:#3A342E;--verde:#8FAE7B;--terracota:#D99463;--dorado:#D4AC74;--dorado-ink:#F1ECE4;--bar:#8FAE7B;--bar-neg:#D99463}}
:root[data-theme="dark"]{--bg:#1F1C19;--card:#2A2622;--ink:#F1ECE4;--muted:#B8AEA2;--line:#3A342E;--verde:#8FAE7B;--terracota:#D99463;--dorado:#D4AC74;--dorado-ink:#F1ECE4;--bar:#8FAE7B;--bar-neg:#D99463}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.45 Georgia,"Times New Roman",serif}
main{max-width:1100px;margin:0 auto;padding:24px 16px 48px}
header h1{font-size:28px;margin:0 0 4px}header p{margin:0;color:var(--muted)}
h2{font-size:18px;margin:32px 0 12px;font-weight:600}
.tiles{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}
@media(max-width:800px){.tiles{grid-template-columns:repeat(2,1fr)}}@media(max-width:520px){.tiles{grid-template-columns:1fr}}
.tile{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px}
.tile .t{font-size:13px;color:var(--muted);text-transform:uppercase;letter-spacing:.04em}.tile .v{font-size:28px;font-weight:700;margin:4px 0}
.tile .n,.delta{font-size:13px;color:var(--muted)}.delta{display:block;margin-bottom:4px}.delta.bien{color:var(--verde)}.delta.mal{color:var(--terracota)}
.luces{list-style:none;padding:0;margin:0;display:grid;gap:10px}
.luces li{display:flex;gap:12px;align-items:flex-start;background:var(--card);border:1px solid var(--line);border-radius:12px;padding:12px 14px}
.luces .ic{flex:0 0 32px;height:32px;border-radius:50%;display:grid;place-items:center;font-weight:700;color:#fff}
.luces li.bien .ic{background:var(--verde)}.luces li.ojo .ic{background:var(--dorado);color:var(--dorado-ink)}.luces li.mal .ic{background:var(--terracota)}
.luces .est{font-size:12px;color:var(--muted);margin-left:6px}.luces .d{font-size:14px;color:var(--muted)}
.charts{display:grid;grid-template-columns:1fr 1fr;gap:16px}@media(max-width:800px){.charts{grid-template-columns:1fr}}
.chart{margin:0;background:var(--card);border:1px solid var(--line);border-radius:12px;padding:12px}.chart figcaption{font-size:14px;color:var(--muted);margin-bottom:4px}
svg{width:100%;height:auto;display:block}.bar.pos{fill:var(--bar)}.bar.neg{fill:var(--bar-neg)}.bar.parcial{opacity:.55}.base{stroke:var(--line);stroke-width:1}
.val{font-size:12px;fill:var(--ink);font-family:system-ui,sans-serif}.mes{font-size:12px;fill:var(--muted);font-family:system-ui,sans-serif}
ul.lista{margin:0;padding-left:20px}ul.lista li{margin:6px 0}.muted{color:var(--muted)}footer{margin-top:40px;font-size:13px;color:var(--muted)}
'@

  $html = "<!doctype html><html lang=`"es`"><head><meta charset=`"utf-8`"><meta name=`"viewport`" content=`"width=device-width,initial-scale=1`"><title>Tablero Casa Zaru</title><style>$css</style></head><body><main>" +
    "<header><h1>Casa Zaru · $(Hx $mesNom) $($iniMes.Year)</h1><p>$(Hx $estadoMes). Montos sin IVA. Generado el $(Hx $gen).</p></header>" +
    "<h2>Los números</h2><div class=`"tiles`">$tiles</div>" +
    "<h2>Dónde estamos bien y dónde fallamos</h2><ul class=`"luces`">$luces</ul>" +
    "<h2>Mes a mes</h2><div class=`"charts`">$(Barras 'VentaNeta' 'Venta neta por mes' $false)$(Barras 'Resultado' 'Resultado por mes' $true)</div><p class=`"muted`">* mes parcial o con insumos incompletos.</p>" +
    "<h2>Qué falta para cerrar el mes</h2><ul class=`"lista`">$pendHtml</ul>" +
    $(if ($avisos.Count) { "<h2>Para revisar</h2><ul class=`"lista`">$avisosHtml</ul>$masAvisos" } else { '' }) +
    "<footer>Fuentes: Gestión, planilla de gastos Wasabil, cartolas BCI y Banco de Chile, Mercado Pago, Wasabil y Meta. El detalle está en el libro Excel del mes, en la misma carpeta.</footer>" +
    '</main></body></html>'
  [IO.File]::WriteAllText($ruta, $html, (New-Object Text.UTF8Encoding($true)))
}
