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
//   STARKEN_CTA_DV  opcional: DV de esa cuenta
// Sin cuenta corriente se cotiza con rutCliente = STARKEN_RUT.
//
// Llamadas (POST, JSON):
//   { accion: 'destinos' }
//     → { ciudades: [{ codigo, nombre, region, comunas: ['…'] }] }
//   { accion: 'tarifa', destino: <codigoCiudad>, bultos: [{ largo, ancho, alto, kilos }] }
//     → { origen, destino, bulto: { largo, ancho, alto, kilos }, tarifas: [{ entrega, servicio, total, dias }] }

const BASE = Deno.env.get('STARKEN_BASE') || 'https://restservices.starken.cl/apiprd/starkenservices/rest/';
const ORIGEN = Number(Deno.env.get('STARKEN_ORIGEN') || 103); // 103 = Villarrica

const ORIGENES_PERMITIDOS = [
  'https://cotizador.casazaru.cl',
  'http://localhost:5550', // perfil «Cotizador» de .claude/launch.json
  'http://127.0.0.1:5550',
];

// La lista de ciudades casi no cambia: se guarda mientras viva la instancia.
const DOCE_HORAS = 12 * 60 * 60 * 1000;
let cacheDestinos: { cuando: number; ciudades: any[] } | null = null;

function cors(req: Request) {
  const origen = req.headers.get('origin') || '';
  return {
    'Access-Control-Allow-Origin': ORIGENES_PERMITIDOS.includes(origen) ? origen : ORIGENES_PERMITIDOS[0],
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  };
}

function cabecerasStarken() {
  const rut = Deno.env.get('STARKEN_RUT');
  const clave = Deno.env.get('STARKEN_CLAVE');
  if (!rut || !clave) throw new ErrorPublico('Faltan los secretos STARKEN_RUT / STARKEN_CLAVE', 500);
  return { 'Content-Type': 'application/json', 'rut': rut, 'Clave': clave };
}

class ErrorPublico extends Error {
  status: number;
  constructor(msg: string, status: number) { super(msg); this.status = status; }
}

async function llamarStarken(servicio: string, init: RequestInit) {
  let res: Response;
  try {
    res = await fetch(BASE + servicio, { ...init, signal: AbortSignal.timeout(15000) });
  } catch (_e) {
    throw new ErrorPublico('Starken no respondió', 504);
  }
  const texto = await res.text();
  let datos: any = null;
  try { datos = JSON.parse(texto); } catch (_e) { /* respuesta no JSON */ }
  if (!res.ok || !datos) {
    console.error('starken ' + servicio + ' HTTP ' + res.status + ': ' + texto.slice(0, 300));
    throw new ErrorPublico(res.status === 401 || res.status === 403 ? 'Starken rechazó las credenciales' : 'Error de Starken (HTTP ' + res.status + ')', 502);
  }
  if (datos.codigoRespuesta !== undefined && datos.codigoRespuesta !== 1) {
    throw new ErrorPublico('Starken: ' + (datos.mensajeRespuesta || 'código ' + datos.codigoRespuesta), 422);
  }
  return datos;
}

async function destinos() {
  if (cacheDestinos && Date.now() - cacheDestinos.cuando < DOCE_HORAS) return cacheDestinos.ciudades;
  const datos = await llamarStarken('listarCiudadesDestino', { method: 'GET', headers: cabecerasStarken() });
  // La respuesta trae la lista en listaCiudadesDestino (en origen se llama listaCiudadesOrigen).
  const clave = Object.keys(datos).find((k) => k.indexOf('listaCiudades') === 0);
  const lista: any[] = clave ? datos[clave] : [];
  const ciudades = lista.map((c) => ({
    codigo: c.codigoCiudad,
    nombre: c.nombreCiudad,
    region: c.codigoRegion,
    comunas: (c.listaComunas || []).map((m: any) => m.nombreComuna),
  }));
  cacheDestinos = { cuando: Date.now(), ciudades };
  return ciudades;
}

function numeroPositivo(v: any, max: number, nombre: string) {
  const n = Number(v);
  if (!isFinite(n) || n <= 0 || n > max) throw new ErrorPublico('Valor inválido en ' + nombre, 400);
  return n;
}

// Starken recibe UN bulto por consulta. Para varios (doc «Tarifa Multibultos»): se suman los
// kilos, se suma una de las medidas y de las otras dos se toma la mayor. Como despachamos
// piezas planas, cada bulto se ordena de mayor a menor medida y se suma el alto (el grosor),
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

  const cta = Deno.env.get('STARKEN_CTA') || '';
  const ctaDv = Deno.env.get('STARKEN_CTA_DV') || '';
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
    rutCliente: cta ? '' : (Deno.env.get('STARKEN_RUT') || ''),
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
    let body: any;
    try { body = await req.json(); } catch (_e) { throw new ErrorPublico('El cuerpo debe ser JSON', 400); }

    if (body.accion === 'destinos') return json({ ciudades: await destinos() }, 200);
    if (body.accion === 'tarifa') return json(await tarifa(body), 200);
    throw new ErrorPublico('Acción desconocida (usar destinos o tarifa)', 400);
  } catch (e) {
    if (e instanceof ErrorPublico) return json({ error: e.message }, e.status);
    console.error('starken-tarifa:', e);
    return json({ error: 'Error interno' }, 500);
  }
});
