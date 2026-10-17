// Envío Starken para el cotizador — proyecto Cotizador (cmxqorsyxoltrakxawro).
//
// Le pregunta el precio del despacho a la API de Cotización de Starken sin que las
// credenciales lleguen al navegador: el cotizador es público y su código se ve.
// Solo COTIZA: no crea envíos ni órdenes de flete.
//
// Doc de Starken: developers.starken.cl/cotizaTusEnvios (hay que iniciar sesión).
// Medidas en cm, peso en kg, costoTotal con IVA incluido.
//
// Despliegue (no hay CLI en el PC): panel de Supabase del Cotizador → Edge Functions →
// Deploy a new function → Via Editor, nombre `starken-tarifa`, pegar este archivo.
// Apagar «Verify JWT»: el cotizador usa la llave publicable nueva (sb_publishable_…),
// que no es un JWT, y con la verificación prendida toda llamada da 401.
//
// Secretos (Edge Functions → Secrets). Los carga el administrador; NUNCA van al repo:
//   STARKEN_RUT     rut de la empresa, sin dígito verificador (cabecera `rut`)
//   STARKEN_CLAVE   clave de producción de la API (cabecera `Clave`)
//   STARKEN_CTA     opcional: cuenta corriente sin DV, para cotizar con la tarifa convenida
//   STARKEN_CTA_DV  obligatorio si hay STARKEN_CTA
// Sin cuenta corriente se cotiza con rutCliente = STARKEN_RUT.
// Opcionales: STARKEN_BASE (otra URL base, ej. la de QA), STARKEN_ORIGEN (código de ciudad,
// 103 = Villarrica) y STARKEN_ORIGEN_NOMBRE (nombre que debe tener ese código en Starken).
//
// Llamadas (POST, JSON):
//   { accion: 'destinos' }
//     → { ciudades: [{ codigo, nombre, region, comunas: ['…'] }] }
//   { accion: 'tarifa', destino: <codigoCiudad>, bultos: [{ largo, ancho, alto, kilos }] }
//     → { origen, destino, conCuentaCorriente, bulto: { largo, ancho, alto, kilos },
//         tarifas: [{ entrega, servicio, total, dias }] }   (tarifas vacío = sin cobertura)
// Errores: { error } con 400 (datos), 422 (Starken rechazó la consulta), 429 (límite por IP),
// 500 (configuración), 502/504 (Starken caído).

class ErrorPublico extends Error {
  status: number;
  constructor(msg: string, status: number) { super(msg); this.status = status; }
}

function secreto(nombre: string) {
  // trim: un espacio o salto de línea pegado en el panel haría inválida la cabecera HTTP.
  return (Deno.env.get(nombre) || '').trim();
}

const BASE = (secreto('STARKEN_BASE') || 'https://restservices.starken.cl/apiprd/starkenservices/rest/').replace(/\/?$/, '/');
const ORIGEN = Number(secreto('STARKEN_ORIGEN') || 103);
const ORIGEN_NOMBRE = (secreto('STARKEN_ORIGEN_NOMBRE') || 'VILLARRICA').toUpperCase();

const ORIGENES_PERMITIDOS = [
  'https://cotizador.casazaru.cl',
  'http://localhost:5550', // perfil «Cotizador» de .claude/launch.json
  'http://127.0.0.1:5550',
];

function cors(req: Request) {
  const origen = req.headers.get('origin') || '';
  return {
    'Access-Control-Allow-Origin': ORIGENES_PERMITIDOS.includes(origen) ? origen : ORIGENES_PERMITIDOS[0],
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  };
}

// Límite por IP (en memoria, por instancia). La función es pública y habla con Starken con
// nuestras credenciales: esto frena un bucle del navegador o un bot; no es un muro.
const LIMITE_POR_MINUTO = 40;
const golpes = new Map<string, number[]>();
function limitar(req: Request) {
  const ip = (req.headers.get('x-forwarded-for') || '').split(',')[0].trim() || 'sin-ip';
  const ahora = Date.now();
  const lista = (golpes.get(ip) || []).filter((t) => ahora - t < 60000);
  if (lista.length >= LIMITE_POR_MINUTO) throw new ErrorPublico('Demasiadas consultas, espera un minuto', 429);
  lista.push(ahora);
  golpes.set(ip, lista);
  if (golpes.size > 5000) golpes.clear(); // que el mapa no crezca sin tope
}

function cabecerasStarken() {
  const rut = secreto('STARKEN_RUT');
  const clave = secreto('STARKEN_CLAVE');
  if (!rut || !clave) throw new ErrorPublico('Faltan los secretos STARKEN_RUT / STARKEN_CLAVE', 500);
  // Deno manda los nombres de cabecera en minúscula (rut, clave); HTTP no distingue mayúsculas.
  return { 'Content-Type': 'application/json', 'rut': rut, 'Clave': clave };
}

async function llamarStarken(servicio: string, init: RequestInit) {
  const res = await fetch(BASE + servicio, { ...init, signal: AbortSignal.timeout(15000) })
    .catch(() => { throw new ErrorPublico('Starken no respondió', 504); });
  const texto = await res.text();
  let datos: any = null;
  try { datos = JSON.parse(texto); } catch (_e) { /* no era JSON */ }
  if (!res.ok || !datos) {
    console.error('starken ' + servicio + ' HTTP ' + res.status + ': ' + texto.slice(0, 300));
    const msg = (res.status === 401 || res.status === 403)
      ? 'Starken rechazó las credenciales'
      : 'Error de Starken (HTTP ' + res.status + ')';
    throw new ErrorPublico(msg, 502);
  }
  if (datos.codigoRespuesta !== undefined && Number(datos.codigoRespuesta) !== 1) {
    throw new ErrorPublico('Starken: ' + (datos.mensajeRespuesta || 'código ' + datos.codigoRespuesta), 422);
  }
  return datos;
}

// Las listas de ciudades casi no cambian: se guardan 12 h mientras viva la instancia.
const DOCE_HORAS = 12 * 60 * 60 * 1000;
const cacheCiudades = new Map<string, { cuando: number; ciudades: any[] }>();
async function ciudades(servicio: 'listarCiudadesOrigen' | 'listarCiudadesDestino') {
  const c = cacheCiudades.get(servicio);
  if (c && Date.now() - c.cuando < DOCE_HORAS) return c.ciudades;
  const datos = await llamarStarken(servicio, { method: 'GET', headers: cabecerasStarken() });
  // La lista viene en listaCiudadesOrigen o listaCiudadesDestino según el servicio.
  const clave = Object.keys(datos).find((k) => k.indexOf('listaCiudades') === 0);
  const lista: any[] = clave && Array.isArray(datos[clave]) ? datos[clave] : [];
  if (!lista.length) throw new ErrorPublico('Starken devolvió la lista de ciudades vacía', 502);
  const salida = lista.map((x) => ({
    codigo: x.codigoCiudad,
    nombre: x.nombreCiudad,
    region: x.codigoRegion,
    comunas: (x.listaComunas || []).map((m: any) => m.nombreComuna),
  }));
  cacheCiudades.set(servicio, { cuando: Date.now(), ciudades: salida });
  return salida;
}

// Candado: que el código de origen sea de verdad Villarrica en la lista de Starken (el 103 se
// vio en QA; producción podría numerar distinto). Si no calza, mejor fallar que cotizar en
// silencio desde otra ciudad. Si la lista no se pudo leer, no bloquea: decide consultarTarifas.
let origenVerificado = false;
async function verificarOrigen() {
  if (origenVerificado) return;
  let lista: any[];
  try { lista = await ciudades('listarCiudadesOrigen'); }
  catch (e) { console.error('no se pudo verificar el origen:', (e as Error).message); return; }
  const ciudad = lista.find((x) => Number(x.codigo) === ORIGEN);
  if (!ciudad || String(ciudad.nombre).toUpperCase().indexOf(ORIGEN_NOMBRE) < 0) {
    throw new ErrorPublico('El código de origen ' + ORIGEN + ' no es ' + ORIGEN_NOMBRE + ' en Starken', 500);
  }
  origenVerificado = true;
}

function numeroPositivo(v: any, max: number, nombre: string) {
  const n = Number(v);
  if (!isFinite(n) || n <= 0 || n > max) throw new ErrorPublico('Valor inválido en ' + nombre, 400);
  return n;
}

// Starken recibe UN bulto por consulta. Para varios (doc «Tarifa Multibultos»): se suman los
// kilos, se suma una de las medidas y de las otras dos se toma la mayor. Como despachamos
// piezas planas, cada bulto se ordena de mayor a menor medida y se suma la menor (el grosor),
// que es como van apiladas; largo y ancho quedan en el máximo.
function juntarBultos(bultos: any[]) {
  if (!Array.isArray(bultos) || bultos.length < 1 || bultos.length > 30) {
    throw new ErrorPublico('Se necesitan entre 1 y 30 bultos', 400);
  }
  let largo = 0, ancho = 0, alto = 0, kilos = 0;
  bultos.forEach((b, i) => {
    const medidas = [
      numeroPositivo(b.largo, 1000, 'largo del bulto ' + (i + 1)),
      numeroPositivo(b.ancho, 1000, 'ancho del bulto ' + (i + 1)),
      numeroPositivo(b.alto, 1000, 'alto del bulto ' + (i + 1)),
    ].sort((a, z) => z - a);
    largo = Math.max(largo, medidas[0]);
    ancho = Math.max(ancho, medidas[1]);
    alto += medidas[2];
    kilos += numeroPositivo(b.kilos, 2000, 'kilos del bulto ' + (i + 1));
  });
  const r2 = (x: number) => Math.round(x * 100) / 100;
  return { largo: r2(largo), ancho: r2(ancho), alto: r2(alto), kilos: r2(kilos) };
}

async function tarifa(body: any) {
  const destino = Number(body.destino);
  if (!Number.isInteger(destino) || destino <= 0) throw new ErrorPublico('Falta la ciudad de destino', 400);
  const bulto = juntarBultos(body.bultos);

  const cta = secreto('STARKEN_CTA');
  const ctaDv = secreto('STARKEN_CTA_DV');
  if (cta && !ctaDv) throw new ErrorPublico('Falta el secreto STARKEN_CTA_DV', 500);
  await verificarOrigen();

  const pedido = {
    codigoCiudadOrigen: ORIGEN,
    codigoCiudadDestino: destino,
    codigoAgenciaOrigen: 0,
    codigoAgenciaDestino: 0,
    alto: bulto.alto,
    ancho: bulto.ancho,
    largo: bulto.largo,
    kilos: bulto.kilos,
    // Cuenta corriente o rut de cliente, nunca los dos (diccionario de entrada de Starken).
    cuentaCorriente: cta,
    cuentaCorrienteDV: cta ? ctaDv : '',
    rutCliente: cta ? '' : secreto('STARKEN_RUT'),
  };
  const datos = await llamarStarken('consultarTarifas', {
    method: 'POST',
    headers: cabecerasStarken(),
    body: JSON.stringify(pedido),
  });
  const tarifas = (datos.listaTarifas || []).map((t: any) => ({
    entrega: t.tipoEntrega ? t.tipoEntrega.descripcionTipoEntrega : '',
    servicio: t.tipoServicio ? t.tipoServicio.descripcionTipoServicio : '',
    total: Math.round(Number(t.costoTotal) || 0),
    dias: t.diasEntrega,
  }));
  return { origen: ORIGEN, destino, conCuentaCorriente: !!cta, bulto, tarifas };
}

Deno.serve(async (req) => {
  const h = cors(req);
  if (req.method === 'OPTIONS') return new Response('ok', { headers: h });
  const json = (obj: any, status: number) =>
    new Response(JSON.stringify(obj), { status, headers: { ...h, 'Content-Type': 'application/json' } });

  try {
    if (req.method !== 'POST') throw new ErrorPublico('Usar POST', 405);
    limitar(req);
    let body: any;
    try { body = await req.json(); } catch (_e) { throw new ErrorPublico('El cuerpo debe ser JSON', 400); }

    if (body.accion === 'destinos') return json({ ciudades: await ciudades('listarCiudadesDestino') }, 200);
    if (body.accion === 'tarifa') return json(await tarifa(body), 200);
    throw new ErrorPublico('Acción desconocida (usar destinos o tarifa)', 400);
  } catch (e) {
    if (e instanceof ErrorPublico) return json({ error: e.message }, e.status);
    console.error('starken-tarifa:', e);
    return json({ error: 'Error interno' }, 500);
  }
});
