// Envíos Starken desde la Gestión — proyecto Gestión (padnttpgzuotxeipjrry).
//
// Botón «Enviar con Starken» de Producción, SOLO admin (decisión del dueño, 20-10-2026).
// Crea la orden de flete (OF) en Starken, la anota en public.envios_starken (migración
// 0022) y entrega la etiqueta para imprimir. Una OF es dinero y no se modifica una vez
// creada: antes de llamar a Starken se inserta la fila en 'emitiendo', y el índice único
// de la tabla impide una segunda OF viva para el mismo pedido (doble clic, dos pestañas).
//
// Acciones (POST JSON, con la sesión del usuario en Authorization):
//   { accion: 'destinos' }                       → comunas de Starken (vía starken-tarifa)
//   { accion: 'cotizar', destino, kilos | bultos } → precio, igual que el cotizador
//   { accion: 'emitir', pedido, destinatario, bultos, kilos, medidas, valorDeclarado,
//     contenido, precioCotizado }               → { envio } con of_numero
//   { accion: 'etiqueta', of }                    → { pdfBase64 }
//   { accion: 'anular', id }                      → marca la OF anulada (ver nota en la función)
//
// Despliegue: panel de Gestión → Edge Functions → Via Editor, nombre `starken-emitir`.
// «Verify JWT» PRENDIDO: la Gestión manda el token del usuario (llave anon de formato JWT).
//
// Secretos (los carga el administrador; NUNCA van al repo):
//   STARKEN_RUT, STARKEN_CLAVE         emisión H2H (rutEmpresaEmisora/rutUsuarioEmisor y claveUsuarioEmisor)
//   STARKEN_CTA, STARKEN_CTA_DV         cuenta corriente para emitir (la de la web: 777979-8)
//   STARKEN_CENTRO_COSTO                centro de costo de esa cuenta (lo da el ejecutivo)
//   STARKEN_ETIQUETA_USUARIO, STARKEN_ETIQUETA_CLAVE   autenticación básica de la API de etiqueta
//   STARKEN_REMITENTE                   JSON: {"dv","nombre","direccion","numero","depto","comuna","email","telefono"}
//   STARKEN_MODO                        'qa' (por defecto) o 'produccion'. En QA usa los datos
//                                       públicos de ejemplo de la documentación de Starken y
//                                       nunca crea OF reales.
// SUPABASE_URL y SUPABASE_ANON_KEY los inyecta Supabase.

class ErrorPublico extends Error {
  status: number;
  constructor(msg: string, status: number) { super(msg); this.status = status; }
}

function secreto(nombre: string) { return (Deno.env.get(nombre) || '').trim(); }

const MODO = secreto('STARKEN_MODO') === 'produccion' ? 'produccion' : 'qa';

// Ambiente de pruebas: los valores de ejemplo que publica Starken en developers.starken.cl
// (no son de Casa Zaru ni secretos). Con ellos se puede probar todo sin OF reales.
const QA = {
  emision: 'https://emisionh2h-qa.starken.cl/starkenh2h/servlet/aemisionh2hremrest',
  etiqueta: 'https://apiqa.starken.cl/apiqa/etiqueta/impresionByOrdenFleteDynamic',
  rutEmpresa: '76211240', rutUsuario: '10', clave: 'SOPORTE', cta: '19154', ctaDv: 'K', centroCosto: '0',
};
const PRD = {
  emision: 'https://emisionh2h.starken.cl/starkenh2h/servlet/aemisionh2hremrest',
  etiqueta: 'https://apiprd.starken.cl/apiprd/etiqueta/impresionByOrdenFleteDynamic',
};

// La cotización la hace la función del Cotizador (ya probada y con sus credenciales):
// así hay un solo lugar que calcula el precio, el mismo que vio el cliente.
const TARIFA_URL = 'https://cmxqorsyxoltrakxawro.supabase.co/functions/v1/starken-tarifa';

const ORIGENES = ['https://casazar.github.io'];
function cors(req: Request) {
  const o = req.headers.get('origin') || '';
  const ok = ORIGENES.includes(o) || /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(o);
  return {
    'Access-Control-Allow-Origin': ok ? o : ORIGENES[0],
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  };
}

// ── Base de datos con el token del usuario: la RLS (es_admin) decide ────────
function db(req: Request) {
  const url = Deno.env.get('SUPABASE_URL')!, anon = Deno.env.get('SUPABASE_ANON_KEY')!;
  const auth = req.headers.get('Authorization') || '';
  return async (ruta: string, init: RequestInit = {}) => {
    const r = await fetch(url + '/rest/v1/' + ruta, {
      ...init,
      headers: { apikey: anon, Authorization: auth, 'Content-Type': 'application/json', Prefer: 'return=representation', ...(init.headers || {}) },
    });
    const t = await r.text();
    let d: any = null; try { d = JSON.parse(t); } catch (_e) { /* vacío */ }
    return { ok: r.ok, status: r.status, d, t };
  };
}

// Solo un admin con sesión: la RLS de gestion_finanzas solo le devuelve filas a él.
async function exigirAdmin(req: Request) {
  const r = await db(req)('gestion_finanzas?select=num&limit=1');
  if (!r.ok || !Array.isArray(r.d) || !r.d.length) throw new ErrorPublico('Solo el administrador puede enviar con Starken', 403);
}

async function tarifa(cuerpo: any) {
  const r = await fetch(TARIFA_URL, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(cuerpo), signal: AbortSignal.timeout(20000) })
    .catch(() => { throw new ErrorPublico('Starken no respondió', 504); });
  const d = await r.json().catch(() => ({}));
  if (!r.ok) throw new ErrorPublico(d.error || 'No se pudo cotizar', r.status);
  return d;
}

function texto(v: any, max: number) { return String(v == null ? '' : v).trim().slice(0, max); }
function exigir(v: string, nombre: string) { if (!v) throw new ErrorPublico('Falta ' + nombre, 400); return v; }
function rutPartes(rut: string) {
  const l = rut.replace(/[^0-9kK]/g, '').toUpperCase();
  return l.length >= 2 ? { cuerpo: l.slice(0, -1), dv: l.slice(-1) } : { cuerpo: '', dv: '' };
}
// Starken escribe las comunas sin tildes ni ñ (NUNOA, PENALOLEN).
function comunaStarken(c: string) { return c.toUpperCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/Ñ/g, 'N').trim(); }

// Busca el número de OF en la respuesta de Starken, se llame como se llame el campo.
function numeroOF(d: any): string {
  if (!d || typeof d !== 'object') return '';
  for (const [k, v] of Object.entries(d)) {
    if (/orden.?flete|numero.?of|^of$|nro.?of/i.test(k) && v != null && String(v).trim() && !/[a-z]{4}/i.test(String(v))) return String(v).trim();
  }
  for (const v of Object.values(d)) { if (v && typeof v === 'object') { const n = numeroOF(v); if (n) return n; } }
  return '';
}

async function emitir(req: Request, b: any) {
  const q = db(req);
  const pedido = exigir(texto(b.pedido, 20), 'el pedido');
  const d = b.destinatario || {};
  const dest = {
    nombre: exigir(texto(d.nombre, 60), 'el nombre del destinatario'),
    apellidos: texto(d.apellidos, 80),
    rut: texto(d.rut, 15),
    telefono: exigir(texto(d.telefono, 20), 'el teléfono del destinatario'),
    email: texto(d.email, 80),
    calle: exigir(texto(d.calle, 120), 'la calle'),
    numero: exigir(texto(d.numero, 20), 'el número de la dirección'),
    depto: texto(d.depto, 40),
    comuna: exigir(comunaStarken(texto(d.comuna, 60)), 'la comuna'),
  };
  const kilos = Number(b.kilos);
  if (!(kilos > 0 && kilos <= 2000)) throw new ErrorPublico('Kilos inválidos', 400);
  const bultos = Math.round(Number(b.bultos) || 1);
  if (bultos < 1 || bultos > 30) throw new ErrorPublico('Bultos inválidos (1 a 30)', 400);
  const m = b.medidas || {};
  const modo = m.modo === 'reales' ? 'reales' : 'web';
  let largo: number, ancho: number, alto: number;
  if (modo === 'web') {   // igual que el plugin de la web: un cubo de 2.500 cm³ por kilo
    largo = ancho = alto = Math.round(Math.cbrt(kilos * 2500) * 10) / 10;
  } else {
    largo = Number(m.largo); ancho = Number(m.ancho); alto = Number(m.alto);
    if (![largo, ancho, alto].every((x) => x > 0 && x <= 1000)) throw new ErrorPublico('Medidas inválidas', 400);
  }
  const valor = Math.max(0, Math.round(Number(b.valorDeclarado) || 0));
  const contenido = texto(b.contenido, 60) || 'MUEBLE DE MADERA';

  const cred = MODO === 'produccion'
    ? { rutEmpresa: secreto('STARKEN_RUT'), rutUsuario: secreto('STARKEN_RUT'), clave: secreto('STARKEN_CLAVE'),
        cta: secreto('STARKEN_CTA'), ctaDv: secreto('STARKEN_CTA_DV'), centroCosto: secreto('STARKEN_CENTRO_COSTO') }
    : QA;
  if (!cred.rutEmpresa || !cred.clave || !cred.cta || !cred.ctaDv || cred.centroCosto === '') {
    throw new ErrorPublico('Faltan secretos de emisión (cuenta corriente o centro de costo)', 500);
  }
  let rem: any = {};
  try { rem = JSON.parse(secreto('STARKEN_REMITENTE') || '{}'); } catch (_e) { /* abajo */ }
  if (MODO === 'produccion' && (!rem.direccion || !rem.numero || !rem.telefono)) {
    throw new ErrorPublico('Falta el secreto STARKEN_REMITENTE (dirección y teléfono del taller)', 500);
  }

  const solicitud: any = {
    rutRemitente: MODO === 'produccion' ? secreto('STARKEN_RUT') : QA.rutEmpresa,
    dvRemitente: MODO === 'produccion' ? texto(rem.dv, 1) : 'K',
    nombreRazonSocialRemitente: texto(rem.nombre, 60) || 'MUVALE DISENO SPA',
    apellidoPaternoRemitente: '.', apellidoMaternoRemitente: '.',
    direccionRemitente: texto(rem.direccion, 120) || 'BERNARDO OHIGGINS',
    numeracionDireccionRemitente: texto(rem.numero, 20) || '152',
    departamentoRemitente: texto(rem.depto, 40),
    emailRemitente: texto(rem.email, 80) || 'hola@casazaru.cl',
    telefonoRemitente: texto(rem.telefono, 20) || '+56 9 1234 5678',
    comunaRemitente: comunaStarken(texto(rem.comuna, 60) || (MODO === 'produccion' ? 'VILLARRICA' : 'COLINA')),
    rutDestinatario: rutPartes(dest.rut).cuerpo, dvRutDestinatario: rutPartes(dest.rut).dv,
    nombreRazonSocialDestinatario: dest.nombre,
    apellidoPaternoDestinatario: dest.apellidos.split(/\s+/)[0] || '.',
    apellidoMaternoDestinatario: dest.apellidos.split(/\s+/).slice(1).join(' ') || '.',
    direccionDestinatario: dest.calle, numeracionDireccionDestinatario: dest.numero,
    departamentoDireccionDestinatario: dest.depto, comunaDestino: dest.comuna,
    telefonoDestinatario: dest.telefono, emailDestinatario: dest.email,
    nombreContactoDestinatario: (dest.nombre + ' ' + dest.apellidos).trim(),
    tipoEntrega: 2,                       // domicilio
    tipoPago: '2',                        // cuenta corriente
    numeroCtaCte: cred.cta, dvNumeroCtaCte: cred.ctaDv, centroCostoCtaCte: cred.centroCosto,
    valorDeclarado: String(valor), contenido,
    kilosTotal: String(Math.round(kilos * 100) / 100),
    alto: String(alto), ancho: String(ancho), largo: String(largo),
    tipoServicio: '0',
    tipoDocumento1: '', numeroDocumento1: '', generaEtiquetaDocumento1: '',
    tipoEncargo1: '29', cantidadEncargo1: String(bultos),   // 29 = el tipo del ejemplo de Starken
    observacion: ('PEDIDO ' + pedido).slice(0, 60),
  };

  // 1) CANDADO: la fila se crea ANTES de llamar a Starken.
  const fila = {
    pedido, estado: 'emitiendo',
    destinatario: dest, bultos, kilos,
    medidas: { largo, ancho, alto, modo },
    valor_declarado: valor,
    precio_cotizado: Number(b.precioCotizado) > 0 ? Math.round(Number(b.precioCotizado)) : null,
    cuenta: MODO === 'produccion' ? cred.cta + '-' + cred.ctaDv : 'QA',
    solicitud,   // sin credenciales: van solo en el envío a Starken
  };
  const ins = await q('envios_starken', { method: 'POST', body: JSON.stringify(fila) });
  if (!ins.ok) {
    if (ins.status === 409 || /envios_starken_una_activa/.test(ins.t)) throw new ErrorPublico('Este pedido ya tiene una OF emitida o emitiéndose', 409);
    console.error('insert envios_starken', ins.status, ins.t.slice(0, 300));
    throw new ErrorPublico('No se pudo registrar el envío (¿falta aplicar la migración 0022?)', 500);
  }
  const id = ins.d[0].id;

  // 2) Starken
  const cuerpo = { ...solicitud, rutEmpresaEmisora: cred.rutEmpresa, rutUsuarioEmisor: cred.rutUsuario, claveUsuarioEmisor: cred.clave };
  let res: Response, txt = '';
  try {
    res = await fetch(MODO === 'produccion' ? PRD.emision : QA.emision, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(cuerpo), signal: AbortSignal.timeout(30000),
    });
    txt = await res.text();
  } catch (_e) {
    // No se sabe si Starken alcanzó a crear la OF: la fila queda en 'emitiendo' (bloquea
    // reintentos) hasta que el admin revise en Starken PRO y la marque como error.
    throw new ErrorPublico('Starken no respondió. NO reintentes: revisa en Starken PRO si la OF se creó', 504);
  }
  let resp: any = null; try { resp = JSON.parse(txt); } catch (_e) { resp = { texto: txt.slice(0, 2000) }; }
  const of = numeroOF(resp);
  const ok = res.ok && !!of;
  const upd = await q('envios_starken?id=eq.' + id, {
    method: 'PATCH',
    body: JSON.stringify(ok
      ? { estado: 'emitida', of_numero: of, respuesta: resp }
      : { estado: 'error', respuesta: resp, error: texto(resp && (resp.mensajeRespuesta || resp.mensaje || resp.texto) || ('HTTP ' + res.status), 500) }),
  });
  if (!upd.ok) console.error('update envios_starken', upd.status, upd.t.slice(0, 300));
  if (!ok) throw new ErrorPublico('Starken no emitió la OF: ' + texto(resp && (resp.mensajeRespuesta || resp.mensaje || resp.texto), 200), 422);
  return { envio: upd.ok ? upd.d[0] : { id, of_numero: of, estado: 'emitida' }, modo: MODO };
}

// PENDIENTE confirmar con la documentación de la API REST Etiqueta: nombres de los
// parámetros (N° de OF y formato) y cómo viene el PDF. Se deja con los nombres más
// probables; la prueba en QA lo confirma antes de pasar a producción.
async function etiqueta(b: any) {
  const of = texto(b.of, 20).replace(/\D/g, '');
  if (!of) throw new ErrorPublico('Falta el número de OF', 400);
  const user = MODO === 'produccion' ? secreto('STARKEN_ETIQUETA_USUARIO') : secreto('STARKEN_ETIQUETA_USUARIO_QA');
  const pass = MODO === 'produccion' ? secreto('STARKEN_ETIQUETA_CLAVE') : secreto('STARKEN_ETIQUETA_CLAVE_QA');
  if (!user || !pass) throw new ErrorPublico('Faltan las credenciales de la API de etiqueta', 500);
  const url = (MODO === 'produccion' ? PRD.etiqueta : QA.etiqueta) + '?ordenFlete=' + encodeURIComponent(of) + '&tipoSalida=1';
  const r = await fetch(url, { method: 'POST', headers: { Authorization: 'Basic ' + btoa(user + ':' + pass) }, signal: AbortSignal.timeout(30000) })
    .catch(() => { throw new ErrorPublico('Starken no respondió', 504); });
  const tipo = r.headers.get('content-type') || '';
  if (!r.ok) throw new ErrorPublico('Starken no entregó la etiqueta (HTTP ' + r.status + ')', 502);
  if (/pdf|octet/.test(tipo)) {
    const buf = new Uint8Array(await r.arrayBuffer());
    let bin = ''; for (let i = 0; i < buf.length; i++) bin += String.fromCharCode(buf[i]);
    return { pdfBase64: btoa(bin) };
  }
  const d = await r.json().catch(() => null);
  const b64 = d && (d.pdf || d.etiqueta || d.base64 || d.archivo || (d.data && (d.data.pdf || d.data.base64)));
  if (!b64) throw new ErrorPublico('Starken respondió sin el PDF de la etiqueta', 502);
  return { pdfBase64: String(b64) };
}

// Anular: por ahora SOLO marca la fila (estado 'anulada'). La anulación en Starken
// (WS AnularOrdenEmpresa) se conecta cuando se lea su documentación; mientras, la OF se
// anula también en Starken PRO. La fila anulada libera el candado para emitir otra.
async function anular(req: Request, b: any) {
  const id = Math.round(Number(b.id));
  if (!(id > 0)) throw new ErrorPublico('Falta el envío', 400);
  const r = await db(req)('envios_starken?id=eq.' + id + '&estado=in.(emitida,error,emitiendo)', {
    method: 'PATCH', body: JSON.stringify({ estado: 'anulada', anulada_at: new Date().toISOString() }),
  });
  if (!r.ok || !Array.isArray(r.d) || !r.d.length) throw new ErrorPublico('No se pudo anular (¿ya estaba anulada?)', 409);
  return { envio: r.d[0] };
}

Deno.serve(async (req) => {
  const h = cors(req);
  if (req.method === 'OPTIONS') return new Response('ok', { headers: h });
  const json = (o: any, s: number) => new Response(JSON.stringify(o), { status: s, headers: { ...h, 'Content-Type': 'application/json' } });
  try {
    if (req.method !== 'POST') throw new ErrorPublico('Usar POST', 405);
    let b: any; try { b = await req.json(); } catch (_e) { throw new ErrorPublico('El cuerpo debe ser JSON', 400); }
    await exigirAdmin(req);
    if (b.accion === 'destinos') return json({ ...(await tarifa({ accion: 'destinos' })), modo: MODO }, 200);
    if (b.accion === 'cotizar') {
      const t = await tarifa(b.bultos ? { accion: 'tarifa', destino: b.destino, bultos: b.bultos } : { accion: 'tarifa', destino: b.destino, kilos: b.kilos });
      return json({ ...t, modo: MODO }, 200);
    }
    if (b.accion === 'emitir') return json(await emitir(req, b), 200);
    if (b.accion === 'etiqueta') return json(await etiqueta(b), 200);
    if (b.accion === 'anular') return json(await anular(req, b), 200);
    throw new ErrorPublico('Acción desconocida', 400);
  } catch (e) {
    if (e instanceof ErrorPublico) return json({ error: e.message, modo: MODO }, e.status);
    console.error('starken-emitir:', e);
    return json({ error: 'Error interno' }, 500);
  }
});
