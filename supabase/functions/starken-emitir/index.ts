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
//     contenido, precioCotizado, documentos: [{ tipo: 'BOLETA'|'FACTURA', numero }] }
//                                                → { envio } con of_numero
//   { accion: 'etiqueta', of, formato? }          → { pdfBase64, paginas, pdfs, tipoSalida, forma }
//     (todas las etiquetas de la OF en un solo PDF; formato '10x10' pide el tamaño 10×10)
//   { accion: 'anular', id, manual? }             → anula la OF en Starken y la marca anulada;
//     con manual:true solo la marca (el admin ya la anuló en Starken PRO)
//
// Despliegue: panel de Gestión → Edge Functions → Via Editor, nombre `starken-emitir`.
// «Verify JWT» PRENDIDO: la Gestión manda el token del usuario (llave anon de formato JWT).
//
// Secretos (los carga el administrador; NUNCA van al repo):
//   STARKEN_RUT, STARKEN_CLAVE         emisión H2H (rutEmpresaEmisora/rutUsuarioEmisor y claveUsuarioEmisor)
//   STARKEN_CTA, STARKEN_CTA_DV         cuenta corriente para emitir (la de la web: 777979-8)
//   STARKEN_CENTRO_COSTO                centro de costo de esa cuenta (lo da el ejecutivo)
//   STARKEN_ETIQUETA_USUARIO, STARKEN_ETIQUETA_CLAVE   autenticación básica de la API de etiqueta
//   STARKEN_PRO_RUN, STARKEN_PRO_RUT_MASTER, STARKEN_PRO_CLAVE
//                                       usuario de Starken PRO Empresa para anular (con DV, sin
//                                       puntos). Starken recomienda un usuario solo para esto.
//   STARKEN_URL_LOGIN, STARKEN_URL_ANULAR   URLs de producción del login y la anulación (la
//                                       documentación solo trae las de QA; las da el ejecutivo)
//   STARKEN_REMITENTE                   JSON: {"dv","nombre","direccion","numero","depto","comuna","email","telefono"}
//   STARKEN_MODO                        'qa' (por defecto) o 'produccion'. En QA la emisión usa
//                                       los datos públicos de ejemplo de la documentación de
//                                       Starken y nunca crea OF reales; etiqueta y anulación usan
//                                       los mismos secretos con sufijo _QA (también públicos en el
//                                       portal, pero tras un login: no van al repo).
// SUPABASE_URL y SUPABASE_ANON_KEY los inyecta Supabase.

// Para juntar en un solo PDF las etiquetas de una OF de varios bultos.
import { PDFDocument } from 'npm:pdf-lib@1.17.1';

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
  login: 'https://apiqa.starkenpro.cl/authentication/auth/login',
  anular: 'https://apiqa.starken.cl/anulacion/apianular/anularOrdenEmpresas',
  rutEmpresa: '76211240', rutUsuario: '10', clave: 'SOPORTE', cta: '19154', ctaDv: 'K', centroCosto: '0',
};
const PRD = {
  emision: 'https://emisionh2h.starken.cl/starkenh2h/servlet/aemisionh2hremrest',
  etiqueta: 'https://apiprd.starken.cl/apiprd/etiqueta/impresionByOrdenFleteDynamic',
  login: secreto('STARKEN_URL_LOGIN'),
  anular: secreto('STARKEN_URL_ANULAR'),
};
// Códigos de tipo de documento de Starken (tabla propia, no la del SII), confirmados por soporte
// de Starken el 03-11-2026: 26 factura, 27 guía de despacho, 28 boleta. El 28 se probó en QA ese
// día (OF de prueba 222795830, codigoError 0). Hasta entonces la boleta iba como 26 (30-10).
// 39 y 99 probados en QA: «no homologado» / «no válido».
const DOC_TIPO: Record<string, string> = { FACTURA: '26', BOLETA: '28' };
// Secreto de producción, o su gemelo _QA en pruebas.
function secretoModo(nombre: string) { return secreto(MODO === 'produccion' ? nombre : nombre + '_QA'); }

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
// Starken guarda el depto del destinatario en 10 caracteres y corta el resto SIN avisar:
// la OF 281309090 (pedido 1607, 04-11-2026) mandó «depto D-202» y quedó «DEPTO D 20».
// Se compacta («depto D-202» → «D-202», «Torre B depto 1504» → «TB D1504») y, si igual
// no cabe, se rechaza antes de emitir para que lo acorte quien emite. Misma regla que
// _stkDeptoCorto() en index.html.
const DEPTO_MAX = 10;
function deptoStarken(s: string) {
  let c = comunaStarken(s).replace(/\s+/g, ' ');
  c = c.replace(/^(DEPARTAMENTO|DEPTO|DPTO|DEPT|DEPA|DEP|DTO)\.?\s*[:#°º-]?\s*/, '');
  c = c.replace(/\b(DEPARTAMENTO|DEPTO|DPTO|DEPT|DEPA|DEP|DTO)\b\.?\s*[:#°º]?\s*/g, 'D');
  c = c.replace(/\bTORRE\s*/g, 'T').replace(/\b(BLOCK|BLOQUE|BLK)\b\.?\s*/g, 'B')
    .replace(/\bOFICINA\s*/g, 'OF').replace(/\bPISO\s*/g, 'P').replace(/\bPARCELA\s*/g, 'PC').replace(/\bLOTE\s*/g, 'L');
  c = c.replace(/\s*(N[°º]|#)\s*/g, ' ').replace(/[,;]/g, ' ').replace(/\s*-\s*/g, '-').replace(/\s+/g, ' ').trim();
  if (c.length > DEPTO_MAX) {
    throw new ErrorPublico('Starken guarda el depto en ' + DEPTO_MAX + ' caracteres y «' + c + '» no cabe: acórtalo (ej. «D-202» o «TB D1504»)', 400);
  }
  return c;
}

// El número de OF. La respuesta documentada (portal, leído 26-10-2026) es
// { codigoError: 0, descripcionError: 'OK', nroOrdenFlete: 2.22607751E8, totalOF, ... }:
// el número viene como decimal en notación científica, por eso se redondea. Si algún día
// cambia el nombre del campo, se busca uno parecido.
function numeroOF(d: any): string {
  if (!d || typeof d !== 'object') return '';
  if (d.nroOrdenFlete != null) {
    const n = Math.round(Number(d.nroOrdenFlete));
    return n > 0 ? String(n) : '';
  }
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
    depto: deptoStarken(texto(d.depto, 40)),
    comuna: exigir(comunaStarken(texto(d.comuna, 60)), 'la comuna'),
  };
  const kilos = Number(b.kilos);
  if (!(kilos > 0 && kilos <= 2000)) throw new ErrorPublico('Kilos inválidos', 400);
  const bultos = Math.round(Number(b.bultos) || 1);
  if (bultos < 1 || bultos > 30) throw new ErrorPublico('Bultos inválidos (1 a 30)', 400);
  const m = b.medidas || {};
  const modo = m.modo === 'reales' ? 'reales' : 'web';
  let largo: number, ancho: number, alto: number;
  // Medidas en cm ENTEROS, como las manda el plugin de la web. El cubo se redondea hacia
  // abajo para que el peso volumétrico nunca pase los kilos declarados y Starken cobre por
  // kilos. (La etiqueta de QA imprime Alto/Ancho/Largo 0 con decimales y con enteros por
  // igual, 26-10-2026: no depende de esto; el peso sí sale.)
  if (modo === 'web') {   // igual que el plugin de la web: un cubo de 2.500 cm³ por kilo
    largo = ancho = alto = Math.max(1, Math.floor(Math.cbrt(kilos * 2500)));
  } else {
    largo = Math.round(Number(m.largo)); ancho = Math.round(Number(m.ancho)); alto = Math.round(Number(m.alto));
    if (![largo, ancho, alto].every((x) => x > 0 && x <= 1000)) throw new ErrorPublico('Medidas inválidas', 400);
  }
  // Starken rechaza la OF sin valor declarado («El Valor Declarado es Obligatorio») y, sobre
  // $50.000, exige adjuntar un documento (boleta o factura): probado en QA el 26-10-2026.
  // Se valida acá para no dejar filas en 'error' por algo que se sabe de antemano.
  const valor = Math.round(Number(b.valorDeclarado) || 0);
  if (!(valor > 0)) throw new ErrorPublico('Falta el valor declarado', 400);
  // Documentos: la OF admite hasta 5 (tipoDocumento1..5). Starken valida el código del tipo
  // (26 = factura, 28 = boleta; 39 «no homologado», 99 «no válido», probado en QA el 26-10).
  // El dueño decidió adjuntar SIEMPRE la boleta o factura del pedido: cobertura por el valor real.
  const docs: { tipo: string; numero: string }[] = [];
  for (const d of Array.isArray(b.documentos) ? b.documentos.slice(0, 5) : []) {
    const tipo = String(d && d.tipo || '').toUpperCase() === 'FACTURA' ? 'FACTURA' : 'BOLETA';
    const numero = texto(d && d.numero, 20).replace(/\D/g, '');
    if (!numero || numero.length > 10) throw new ErrorPublico('Folio de documento inválido (hasta 10 dígitos)', 400);
    const codigo = DOC_TIPO[tipo];
    if (!codigo) throw new ErrorPublico('Starken todavía no nos da el código de ' + tipo.toLowerCase() + ' (pendiente en la función)', 500);
    docs.push({ tipo: codigo, numero });
  }
  if (valor > 50000 && !docs.length) throw new ErrorPublico('Sobre $50.000 Starken exige la boleta o factura emitida', 400);
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
    tipoEncargo1: '29', cantidadEncargo1: String(bultos),   // 29 = el tipo del ejemplo de Starken
    observacion: ('PEDIDO ' + pedido).slice(0, 60),
  };
  for (let i = 1; i <= 5; i++) {
    const d = docs[i - 1];
    solicitud['tipoDocumento' + i] = d ? d.tipo : '';
    solicitud['numeroDocumento' + i] = d ? d.numero : '';
    solicitud['generaEtiquetaDocumento' + i] = d ? 'N' : '';
  }

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
  let resp: any = null; try { resp = JSON.parse(txt); } catch (_e) { /* abajo */ }
  if (!resp || typeof resp !== 'object') resp = { texto: txt.slice(0, 2000) };
  const of = numeroOF(resp);
  // codigoError 0 = emitida. Otro código trae el motivo en descripcionError.
  const sinError = resp.codigoError === undefined || Number(resp.codigoError) === 0;
  const ok = res.ok && sinError && !!of;
  const motivo = texto(resp && (resp.descripcionError || resp.mensajeRespuesta || resp.mensaje || resp.texto) || ('HTTP ' + res.status), 500);
  const upd = await q('envios_starken?id=eq.' + id, {
    method: 'PATCH',
    body: JSON.stringify(ok
      ? { estado: 'emitida', of_numero: of, respuesta: resp }
      : { estado: 'error', respuesta: resp, error: motivo }),
  });
  if (!upd.ok) console.error('update envios_starken', upd.status, upd.t.slice(0, 300));
  if (!ok) throw new ErrorPublico('Starken no emitió la OF: ' + motivo.slice(0, 200), 422);
  return { envio: upd.ok ? upd.d[0] : { id, of_numero: of, estado: 'emitida' }, modo: MODO };
}

// Junta TODOS los PDF en Base64 de la respuesta, vengan sueltos, como texto JSON o en
// campos/arreglos (un PDF en Base64 siempre empieza con «JVBER», que es «%PDF»). Antes se
// quedaba con el primero y una OF de 6 bultos salía con 1 sola etiqueta (OF 281442116, 06-11-2026).
function buscarPdfs(d: any, acc: string[] = []): string[] {
  if (typeof d === 'string') { const s = d.trim().replace(/^"|"$/g, ''); if (/^JVBER/.test(s)) acc.push(s); }
  else if (d && typeof d === 'object') { for (const v of Object.values(d)) buscarPdfs(v, acc); }
  return acc;
}

// Forma de la respuesta de Starken, SIN su contenido (para diagnosticar desde la Gestión):
// tipos, llaves y largos de arreglos y textos.
function forma(d: any, prof = 0): any {
  if (prof > 4) return '…';
  if (typeof d === 'string') return /^JVBER/.test(d.trim().replace(/^"/, '')) ? 'pdf(' + d.length + ')' : 'texto(' + d.length + ')';
  if (Array.isArray(d)) return d.length ? ['arreglo(' + d.length + ')', forma(d[0], prof + 1)] : 'arreglo(0)';
  if (d && typeof d === 'object') { const o: any = {}; for (const [k, v] of Object.entries(d).slice(0, 20)) o[k] = forma(v, prof + 1); return o; }
  return typeof d;
}

function aBase64(u8: Uint8Array): string {
  let bin = ''; for (let i = 0; i < u8.length; i += 0x8000) bin += String.fromCharCode(...u8.subarray(i, i + 0x8000));
  return btoa(bin);
}

// Un PDF que llega solo se entrega tal cual (sin pasar por pdf-lib); solo se cuentan sus páginas.
async function contarPaginas(b64: string): Promise<number> {
  try { return (await PDFDocument.load(Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)))).getPageCount(); } catch (_e) { return 0; }
}

// Une varios PDF (uno por bulto) en uno solo, en el orden en que llegan.
async function unirPdfs(lista: string[]): Promise<{ pdfBase64: string; paginas: number }> {
  const out = await PDFDocument.create();
  for (const b64 of lista) {
    const doc = await PDFDocument.load(Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)));
    for (const p of await out.copyPages(doc, doc.getPageIndices())) out.addPage(p);
  }
  return { pdfBase64: aBase64(await out.save()), paginas: out.getPageCount() };
}

// API REST Etiqueta (diccionario «Diccionario_Entrada_Impresion_OF», leído 06-11-2026): POST
// sin cuerpo, autenticación básica, parámetros ordenFlete y tipoSalida: 1 = Base64 hoja carta,
// 2 = ZPL 10×10, 3 = PDF hoja carta, 5 = PDF 10×10, 6 = Base64 10×10. Por defecto 1 (es el que
// se imprime hoy); b.formato '10x10' pide el 6.
async function etiqueta(b: any) {
  const of = texto(b.of, 20).replace(/\D/g, '');
  if (!of) throw new ErrorPublico('Falta el número de OF', 400);
  const tipoSalida = b.formato === '10x10' ? 6 : 1;
  const user = secretoModo('STARKEN_ETIQUETA_USUARIO'), pass = secretoModo('STARKEN_ETIQUETA_CLAVE');
  if (!user || !pass) throw new ErrorPublico('Faltan las credenciales de la API de etiqueta', 500);
  const url = (MODO === 'produccion' ? PRD.etiqueta : QA.etiqueta) + '?ordenFlete=' + encodeURIComponent(of) + '&tipoSalida=' + tipoSalida;
  const r = await fetch(url, { method: 'POST', headers: { Authorization: 'Basic ' + btoa(user + ':' + pass) }, signal: AbortSignal.timeout(30000) })
    .catch(() => { throw new ErrorPublico('Starken no respondió', 504); });
  if (!r.ok) throw new ErrorPublico('Starken no entregó la etiqueta (HTTP ' + r.status + ')', 502);
  if (/pdf|octet/.test(r.headers.get('content-type') || '')) {   // por si algún día manda el archivo
    const b64 = aBase64(new Uint8Array(await r.arrayBuffer()));
    return { pdfBase64: b64, pdfs: 1, paginas: await contarPaginas(b64), tipoSalida, forma: 'archivo' };
  }
  const t = await r.text();
  let d: any = t; try { d = JSON.parse(t); } catch (_e) { /* Base64 suelto */ }
  const lista = buscarPdfs(d);
  console.log('etiqueta OF', of, 'tipoSalida', tipoSalida, 'pdfs', lista.length, JSON.stringify(forma(d)).slice(0, 500));
  if (!lista.length) { console.error('etiqueta sin PDF:', t.slice(0, 300)); throw new ErrorPublico('Starken respondió sin el PDF de la etiqueta', 502); }
  if (lista.length === 1) return { pdfBase64: lista[0], pdfs: 1, paginas: await contarPaginas(lista[0]), tipoSalida, forma: forma(d) };
  const unido = await unirPdfs(lista);
  return { ...unido, pdfs: lista.length, tipoSalida, forma: forma(d) };
}

// Anulación (portal, leído 26-10-2026): dos pasos. 1) login con un usuario de Starken PRO
// Empresa → token (uno nuevo por cada anulación). 2) POST { numerosOrden: [OF] } → data[]
// con estado 'OK' o 'NO_OK' y el motivo. Solo se anulan OF sin movimientos operativos.
async function anularEnStarken(of: string) {
  const login = MODO === 'produccion' ? PRD.login : QA.login, urlAnular = MODO === 'produccion' ? PRD.anular : QA.anular;
  const run = secretoModo('STARKEN_PRO_RUN'), master = secretoModo('STARKEN_PRO_RUT_MASTER'), clave = secretoModo('STARKEN_PRO_CLAVE');
  if (!login || !urlAnular || !run || !master || !clave) throw new ErrorPublico('Faltan los secretos para anular en Starken', 500);
  const l = await fetch(login, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, signal: AbortSignal.timeout(20000),
    body: JSON.stringify({ application: { code: 'PRO' }, run, rut_master: master, password: clave }),
  }).catch(() => { throw new ErrorPublico('Starken no respondió', 504); });
  const ld = await l.json().catch(() => ({}));
  if (!l.ok || !ld.token) throw new ErrorPublico('Starken rechazó el usuario de anulación (HTTP ' + l.status + ')', 502);
  // La documentación no dice cómo va el token; Bearer es lo estándar (se confirma en QA).
  const a = await fetch(urlAnular, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + ld.token }, signal: AbortSignal.timeout(20000),
    body: JSON.stringify({ numerosOrden: [Number(of)] }),
  }).catch(() => { throw new ErrorPublico('Starken no respondió', 504); });
  const ad = await a.json().catch(() => ({}));
  const fila = Array.isArray(ad.data) ? ad.data.find((x: any) => String(x.numeroOrden) === of) || ad.data[0] : null;
  if (!a.ok || !fila) throw new ErrorPublico('Starken no confirmó la anulación (HTTP ' + a.status + ')', 502);
  if (fila.estado !== 'OK') throw new ErrorPublico('Starken no anuló la OF: ' + texto(fila.mensaje, 200), 422);
  return ad;
}

// Una OF emitida se anula PRIMERO en Starken y recién después se marca acá; si Starken
// dice que no (ya va en camino), la fila sigue emitida. Una fila sin OF (error, o
// 'emitiendo' que el admin ya revisó en Starken PRO) solo se marca. Marcarla anulada
// libera el candado para emitir otra.
// Vía manual (manual:true): el admin la anuló él mismo en Starken PRO y acá solo se marca.
// Existe porque la anulación por API responde 401 (26-10-2026, consultado a Starken) y sin
// ella una OF equivocada dejaba el pedido trabado: etiqueta vieja y candado sin liberar.
async function anular(req: Request, b: any) {
  const id = Math.round(Number(b.id));
  if (!(id > 0)) throw new ErrorPublico('Falta el envío', 400);
  const q = db(req);
  const g = await q('envios_starken?id=eq.' + id + '&select=id,estado,of_numero,respuesta');
  const fila = g.ok && Array.isArray(g.d) ? g.d[0] : null;
  if (!fila) throw new ErrorPublico('No encontré ese envío', 404);
  if (fila.estado === 'anulada') throw new ErrorPublico('Ya estaba anulada', 409);
  const manual = b.manual === true;
  let respuesta = fila.respuesta;
  if (fila.estado === 'emitida' && fila.of_numero) {
    const anulacion = manual
      ? { manual: true, fecha: new Date().toISOString(), nota: 'Anulada en Starken PRO por el administrador; aquí solo se marcó' }
      : await anularEnStarken(String(fila.of_numero));
    respuesta = { ...(respuesta || {}), anulacion };
  }
  const r = await q('envios_starken?id=eq.' + id + '&estado=in.(emitida,error,emitiendo)', {
    method: 'PATCH', body: JSON.stringify({ estado: 'anulada', anulada_at: new Date().toISOString(), respuesta }),
  });
  if (!r.ok || !Array.isArray(r.d) || !r.d.length) throw new ErrorPublico('No pude marcarla anulada aquí: avísale al administrador', 500);
  return { envio: r.d[0], enStarken: fila.estado === 'emitida' && !manual, manual };
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
