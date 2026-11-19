// Revisión de cobros de Starken (skill revision-starken). Se pega en javascript_tool, en una pestaña
// de www.starkenpro.cl con sesión abierta, después de reemplazar __MAPA__ y __DESDE__.
//   __MAPA__  = {"<OF>":{"p":<precio_cotizado>,"n":"<pedido>"}, ...}  (envios_starken emitidas, de la Gestión)
//   __DESDE__ = 'AAAA-MM-DD' (60 días atrás: cubre dos ciclos de factura)
// Devuelve SOLO los avisos (JSON corto). Nunca devuelve ni imprime el token de la sesión.
const MAPA = __MAPA__;
const DESDE = '__DESDE__';
const TOL = 1000;   // misma tolerancia que la ventana de emisión (STK_TOL)
let salida = '';
let tok = null;
for (const k of Object.keys(localStorage)) {
  const v = localStorage.getItem(k);
  if (/^eyJ/.test(v || '')) { tok = v; break; }
  try { const o = JSON.parse(v); if (o && typeof o === 'object') { for (const kk in o) { if (typeof o[kk] === 'string' && /^eyJ/.test(o[kk])) { tok = o[kk]; break; } } } } catch (_) {}
  if (tok) break;
}
if (!tok) salida = 'SIN SESION: pedir al usuario que entre a Starken PRO';
else {
  const hoy = new Date().toISOString().slice(0, 10);
  const r = await fetch('https://apiprod.starkenpro.cl/mystarken/reporte?cuentas=777978,777979&fechaEmisionDesde=' + DESDE + '&fechaEmisionHasta=' + hoy, { headers: { Authorization: 'Bearer ' + tok } });
  if (!r.ok) salida = 'HTTP ' + r.status + ' (sesión vencida: pedir que vuelva a entrar)';
  else {
    const arr = await r.json();
    const items = [];
    for (const a of arr) {
      const of = String(a.orden), est = String(a.estado || '').trim(), v = Number(a.valor_of) || 0;
      if (/ANULAD/i.test(est) || !v) continue;
      const base = { of, emision: String(a['emisión'] || '').slice(0, 10), cuenta: String(a.cuenta), destinatario: String(a.destinatario || '').trim(),
        pedido: MAPA[of] ? MAPA[of].n : '', ahora: v, peso: Number(a.peso_kg) || 0, vol: Number(a.kilos_vol) || 0, estado: est };
      if (/PROBLEMA|SINIESTR|EXTRAV|PERDID|ROBO/i.test(est)) items.push({ ...base, tipo: 'perdido', antes: MAPA[of] ? MAPA[of].p : null });
      else if (MAPA[of] && MAPA[of].p && v - MAPA[of].p > TOL) items.push({ ...base, tipo: 'remidio', antes: MAPA[of].p });
      else if (!MAPA[of] && base.vol > base.peso * 1.2) items.push({ ...base, tipo: 'volumen', antes: null });
    }
    salida = JSON.stringify({ revisado: new Date().toISOString(), desde: DESDE, revisadas: arr.length, items });
  }
}
salida;
