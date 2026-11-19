// Bandeja de mensajes — proyecto COTIZADOR (cmxqorsyxoltrakxawro). Migración supabase-cotizador 0004.
//
// Recibe los mensajes del WhatsApp de la bandeja (+56 9 9305 1122, el número que dejó ManyChat) y de
// Instagram por las APIs OFICIALES de Meta (webhook) y los guarda en mensajes_chats / mensajes. Por
// cada mensaje entrante de texto le pide a Claude un borrador y lo deja en mensajes_borradores.
// ETAPA 1: esta función NO ENVÍA NADA a ningún cliente.
// App de Meta: «Casa Zaru Bandeja» (1678367953790415), negocio Casa Zaru. Ver .claude/bandeja-mensajes.md.
//
// Rutas:
//   GET  /mensajes-webhook                verificación de Meta (hub.challenge)
//   POST /mensajes-webhook                avisos de Meta, firmados con X-Hub-Signature-256
//   POST /mensajes-webhook/conocimiento   la revisión del 5558 sube ejemplos y la guía
//   POST /mensajes-webhook/suscribir      engancha la app a la cuenta de WhatsApp (se corre una vez)
//                                         y devuelve qué apps reciben sus mensajes
//   (las dos últimas piden el encabezado x-conocimiento-token)
//
// Despliegue: panel del Cotizador → Edge Functions → Via Editor, nombre `mensajes-webhook`,
// un solo archivo (index.ts). «Verify JWT» APAGADO: Meta no trae sesión;
// la puerta es la firma de Meta y, en las rutas propias, el secreto propio.
//
// Secretos (los carga el administrador en el panel; NUNCA van al repo):
//   META_APP_SECRET        «Clave secreta de la app» de Meta, para validar la firma
//   META_VERIFY_TOKEN      texto al azar que se escribe también en la config del webhook de Meta
//   WA_PHONE_NUMBER_ID     1190938267435299 (el 1122; solo ese número entra). No es secreto.
//   WA_BUSINESS_ACCOUNT_ID 1323717016492821 (cuenta «Casa Zaru - Manychat»). No es secreto.
//   WA_TOKEN               token permanente de un usuario del sistema con whatsapp_business_messaging
//                          y whatsapp_business_management sobre esa cuenta. Hoy solo lo usa /suscribir.
//   IG_ACCOUNT_ID          id de la cuenta de Instagram de Casa Zaru (cuando se conecte Instagram)
//   CONOCIMIENTO_TOKEN     texto largo al azar; la copia del PC vive en %USERPROFILE%\.casazaru\
//   ANTHROPIC_API_KEY      opcional: sin ella se guardan los mensajes pero no hay borradores
//   MODELO                 opcional, por defecto claude-sonnet-4-6 (CLAUDE.md)
// SUPABASE_URL y la llave de servicio los inyecta Supabase.

// Instrucciones para los borradores de la bandeja. Salen de la memoria de reglas de la casa
// (estilo de mensajes, madera noble, pedir comuna y plano, condiciones de venta).
// Si una regla cambia, se cambia AQUÍ y se vuelve a desplegar la función.

const SISTEMA = `Eres el asistente que redacta borradores de respuesta para Casa Zaru, taller de muebles de madera noble en Villarrica, Chile. Un humano revisa cada borrador antes de enviarlo. Escribes como César, el vendedor.

ESTILO
- Español de Chile, cálido y directo. Párrafos cortos separados por una línea en blanco.
- En el PRIMER mensaje nuestro del chat: «Hola <nombre>, cómo estás? Te escribe César de Casa Zaru.» En los siguientes, sin presentarse otra vez.
- Nunca uses ¡ ni ¿ de apertura; solo los de cierre (? !). Nunca escribas «al tiro». Sin emojis.
- Di siempre «madera noble». NUNCA «nativa» ni «nativo».

QUÉ HACEMOS Y CÓMO
- Mesas, cubiertas, peldaños, puertas y muebles a medida en madera noble (castaño, coihue, raulí, lenga). Roble SOLO si el cliente lo menciona.
- Peldaños: hacemos solo los peldaños de madera, llegan vitrificados y listos para instalar. La estructura de fierro la hace un maestro herrero de su zona.
- Despachamos a todo Chile (el envío se cotiza aparte) o retiro en el taller de Villarrica. No enviamos fuera de Chile.
- La instalación no está incluida. Plazo de fabricación: 7 a 15 días hábiles.

PARA COTIZAR
- No preguntes qué madera quiere ni cuántas sillas por lado.
- Pide la medida (si falta), la comuna de destino y «mándame un plano o boceto si tienes» (en peldaños: «foto, plano o dibujo»). En Instagram pide además un WhatsApp o correo.

PRECIOS
- NUNCA inventes un monto. Si la respuesta necesita un precio, escribe exactamente [PRECIO: <qué producto y medida>] y el humano lo completa desde el Manual.

CUÁNDO NO RESPONDER SOLO
- Reclamos, problemas con un pedido ya comprado, pagos, cambios de un pedido, insultos, o algo que no entiendas: marca "necesita_humano": true y deja un borrador corto y amable que solo acuse recibo.
- Si el cliente dijo que no le interesa, el borrador solo agradece y se despide; no insistas.

FORMATO DE SALIDA
Responde SOLO un objeto JSON, sin texto alrededor:
{"texto": "<el mensaje>", "necesita_humano": <true|false>, "motivo": "<una línea: por qué necesita humano, o vacío>"}`;

const MAX_BYTES = 1_000_000;

function json(cuerpo: unknown, status = 200) {
  return new Response(JSON.stringify(cuerpo), { status, headers: { 'Content-Type': 'application/json' } });
}

function llaveServicio(): string {
  try {
    const k = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') ?? '{}');
    if (typeof k.default === 'string' && k.default) return k.default;
  } catch (_e) { /* sigue con la antigua */ }
  return Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
}

function iguales(a: string, b: string) {
  if (!a || !b || a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

async function hex(algo: 'SHA-256', datos: string) {
  const h = await crypto.subtle.digest(algo, new TextEncoder().encode(datos));
  return [...new Uint8Array(h)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

async function firmaValida(cuerpo: string, firma: string, secreto: string) {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secreto),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(cuerpo));
  const esperado = 'sha256=' + [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, '0')).join('');
  return iguales(firma, esperado);
}

// ── PostgREST con la llave de servicio ─────────────────────────────────────
const BASE = (Deno.env.get('SUPABASE_URL') ?? '') + '/rest/v1/';
async function db(ruta: string, init: RequestInit & { prefer?: string } = {}) {
  const llave = llaveServicio();
  const r = await fetch(BASE + ruta, {
    ...init,
    headers: {
      apikey: llave, Authorization: 'Bearer ' + llave, 'Content-Type': 'application/json',
      ...(init.prefer ? { Prefer: init.prefer } : {}),
    },
  });
  const t = await r.text();
  if (!r.ok) throw new Error(`db ${init.method ?? 'GET'} ${ruta.split('?')[0]} ${r.status}: ${t.slice(0, 300)}`);
  return t ? JSON.parse(t) : null;
}

type Canal = 'whatsapp' | 'instagram';
type Autor = 'cliente' | 'externo';
interface Entrada {
  canal: Canal; contacto: string; nombre?: string; telefono?: string;
  metaId: string; autor: Autor; tipo: string; texto: string | null; ts: Date;
  origen?: unknown; payload: unknown;
}

// Una hora inválida no puede botar el guardado (Meta reintentaría para siempre): se usa la de llegada.
function fecha(ms: number): Date {
  const d = new Date(ms);
  return isNaN(d.getTime()) ? new Date() : d;
}

// ── Leer el aviso de Meta ─────────────────────────────────────────────────
function leerAviso(cuerpo: any): Entrada[] {
  const out: Entrada[] = [];
  const waId = Deno.env.get('WA_PHONE_NUMBER_ID') ?? '';
  const igId = Deno.env.get('IG_ACCOUNT_ID') ?? '';

  if (cuerpo?.object === 'whatsapp_business_account') {
    for (const e of cuerpo.entry ?? []) for (const c of e.changes ?? []) {
      const v = c.value ?? {};
      if (!waId || v.metadata?.phone_number_id !== waId) continue;       // solo el número de la bandeja
      if (c.field === 'messages') {
        const nombres: Record<string, string> = {};
        for (const k of v.contacts ?? []) nombres[k.wa_id] = k.profile?.name;
        for (const m of v.messages ?? []) out.push({
          canal: 'whatsapp', contacto: m.from, nombre: nombres[m.from], telefono: m.from,
          metaId: m.id, autor: 'cliente', tipo: m.type ?? 'text',
          texto: m.text?.body ?? m.button?.text ?? m.interactive?.button_reply?.title ?? m.image?.caption ?? null,
          ts: fecha(Number(m.timestamp) * 1000), origen: m.referral, payload: m,
        });
      } else if (c.field === 'smb_message_echoes') {
        // Coexistencia: lo que se escribe desde la app del celular llega como eco = alguien entró a mano.
        for (const m of v.message_echoes ?? []) out.push({
          canal: 'whatsapp', contacto: m.to, telefono: m.to, metaId: m.id, autor: 'externo',
          tipo: m.type ?? 'text', texto: m.text?.body ?? null,
          ts: fecha(Number(m.timestamp) * 1000), payload: m,
        });
      }
    }
  } else if (cuerpo?.object === 'instagram' && igId) {            // Instagram solo si está configurado
    for (const e of cuerpo.entry ?? []) for (const m of e.messaging ?? []) {
      if (!m.message?.mid || m.message?.is_deleted) continue;
      const eco = !!m.message.is_echo;
      const cliente = eco ? m.recipient?.id : m.sender?.id;
      if (!cliente || cliente === igId) continue;
      out.push({
        canal: 'instagram', contacto: cliente, metaId: m.message.mid,
        // Un eco que NO salió de la bandeja = alguien escribió desde la app. Los que salen de la
        // bandeja ya están guardados con el mismo mid y el insert los ignora.
        autor: eco ? 'externo' : 'cliente', tipo: m.message.attachments ? 'adjunto' : 'text',
        texto: m.message.text ?? null, ts: fecha(Number(m.timestamp)),
        origen: m.message.referral ?? m.referral, payload: m,
      });
    }
  }
  return out;
}

// ── Guardar ───────────────────────────────────────────────────────────────
async function chatId(x: Entrada): Promise<number> {
  const fila: Record<string, unknown> = { canal: x.canal, contacto_id: x.contacto };
  if (x.telefono) fila.telefono = x.telefono;
  await db('mensajes_chats?on_conflict=canal,contacto_id', {
    method: 'POST', body: JSON.stringify(fila), prefer: 'resolution=ignore-duplicates,return=minimal',
  });
  const [c] = await db(`mensajes_chats?select=id,nombre,origen&canal=eq.${x.canal}&contacto_id=eq.${encodeURIComponent(x.contacto)}`);
  // Nombre y anuncio de origen: solo si faltan (no pisar).
  const cambios: Record<string, unknown> = {};
  if (!c.nombre && x.nombre) cambios.nombre = x.nombre;
  if (!c.origen && x.origen) cambios.origen = x.origen;
  if (Object.keys(cambios).length) await db(`mensajes_chats?id=eq.${c.id}`, { method: 'PATCH', body: JSON.stringify(cambios) });
  return c.id;
}

async function guardar(x: Entrada): Promise<{ chat: number; id: number } | null> {
  const chat = await chatId(x);
  const r = await db('mensajes?on_conflict=meta_id', {
    method: 'POST', prefer: 'resolution=ignore-duplicates,return=representation',
    body: JSON.stringify({
      chat_id: chat, meta_id: x.metaId, direccion: x.autor === 'cliente' ? 'entrante' : 'saliente',
      autor: x.autor, tipo: x.tipo, texto: x.texto, payload: x.payload, enviado_at: x.ts.toISOString(),
    }),
  });
  return r?.length ? { chat, id: r[0].id } : null;   // null = Meta lo reintentó, ya estaba
}

// ── Borrador ──────────────────────────────────────────────────────────────
const PROHIBIDO = [/nativ[ao]s?\b/i, /al tiro/i, /^[\s]*[¡¿]/m];

async function contexto(): Promise<string> {
  const [guia] = await db('mensajes_guia?select=texto&order=id.desc&limit=1');
  const ej = await db('mensajes_ejemplos?select=intencion,cliente,respuesta,propuesta,calidad,por_que,fuente'
    + '&activo=is.true&calidad=in.(modelo,evitar)&order=fecha.desc&limit=40');
  const modelos = ej.filter((e: any) => e.calidad === 'modelo').slice(0, 25);
  const evitar = ej.filter((e: any) => e.calidad === 'evitar').slice(0, 8);
  let s = '';
  if (guia?.texto) s += '\n\nGUÍA DE RESPUESTAS (aprendida de los chats reales del 5558):\n' + guia.texto;
  if (modelos.length) s += '\n\nRESPUESTAS MODELO (copia el tono y el siguiente paso, no los datos del cliente):\n'
    + modelos.map((e: any) => `- [${e.intencion}] Cliente: ${e.cliente}\n  Respuesta: ${e.respuesta}`).join('\n');
  if (evitar.length) s += '\n\nERRORES A EVITAR:\n'
    + evitar.map((e: any) => `- [${e.intencion}] ${e.respuesta}\n  Por qué no: ${e.por_que ?? ''}`).join('\n');
  return s;
}

async function redactar(chat: number, mensajeId: number) {
  const llave = Deno.env.get('ANTHROPIC_API_KEY');
  if (!llave) return;
  const [c] = await db(`mensajes_chats?select=canal,nombre,tomado_por,toques_sin_respuesta,origen&id=eq.${chat}`);
  const hist = await db(`mensajes?select=autor,texto,enviado_at&chat_id=eq.${chat}&order=enviado_at.desc&limit=30`);
  hist.reverse();
  const conv = hist.map((m: any) => `${m.autor === 'cliente' ? 'CLIENTE' : 'CASA ZARU'}: ${m.texto ?? '[adjunto]'}`).join('\n');
  const anuncio = (c.origen as any)?.headline ?? (c.origen as any)?.ad_title ?? '';
  const modelo = Deno.env.get('MODELO') || 'claude-sonnet-4-6';

  const r = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: { 'x-api-key': llave, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
    body: JSON.stringify({
      model: modelo, max_tokens: 800,
      system: SISTEMA + await contexto(),
      messages: [{ role: 'user', content:
        `Canal: ${c.canal === 'whatsapp' ? 'WhatsApp' : 'Instagram'}`
        + (anuncio ? `\nAnuncio de origen: ${anuncio}` : '')
        + (c.nombre ? `\nNombre del cliente: ${c.nombre}` : '')
        + (c.tomado_por ? '\nEste chat lo lleva César: el borrador es una sugerencia para él.' : '')
        + `\n\nConversación (lo último abajo):\n${conv}\n\nRedacta la próxima respuesta de Casa Zaru.` }],
    }),
  });
  if (!r.ok) throw new Error('anthropic ' + r.status + ': ' + (await r.text()).slice(0, 200));
  const out = await r.json();
  const crudo = (out.content ?? []).map((b: any) => b.text ?? '').join('').trim();
  let res: { texto?: string; necesita_humano?: boolean; motivo?: string };
  try { res = JSON.parse(crudo.slice(crudo.indexOf('{'), crudo.lastIndexOf('}') + 1)); }
  catch { res = { texto: crudo, necesita_humano: true, motivo: 'la respuesta no vino en JSON' }; }
  const texto = String(res.texto ?? '').trim();
  if (!texto) return;

  // Las reglas se revisan en código, no se le cree al modelo.
  const revision = {
    cesar_no_entro: !c.tomado_por,
    toques_sin_respuesta: c.toques_sin_respuesta,
    toques_ok: c.toques_sin_respuesta < 2,
    sin_palabras_prohibidas: !PROHIBIDO.some((re) => re.test(texto)),
    falta_precio: /\[PRECIO:/.test(texto),
    necesita_humano: !!res.necesita_humano,
    motivo: res.motivo ?? '',
  };

  // Si el cliente mandó varios mensajes seguidos, solo vale el borrador del último.
  await db(`mensajes_borradores?chat_id=eq.${chat}&estado=eq.pendiente`, {
    method: 'PATCH', body: JSON.stringify({ estado: 'caducado' }),
  });
  await db('mensajes_borradores?on_conflict=mensaje_id', {
    method: 'POST', prefer: 'resolution=ignore-duplicates,return=minimal',
    body: JSON.stringify({ chat_id: chat, mensaje_id: mensajeId, texto, revision, modelo }),
  });
}

// ── /conocimiento: la revisión del 5558 sube corpus y guía ────────────────
// La puerta de las rutas propias: null si el secreto calza, o la respuesta de rechazo.
function puertaPropia(req: Request): Response | null {
  const esperado = (Deno.env.get('CONOCIMIENTO_TOKEN') || '').trim();
  if (esperado.length < 32) return json({ error: 'CONOCIMIENTO_TOKEN sin configurar' }, 500);
  if (!iguales((req.headers.get('x-conocimiento-token') || '').trim(), esperado)) return json({ error: 'no autorizado' }, 401);
  return null;
}

// ── /suscribir: la app de Meta empieza a recibir los mensajes de la cuenta de WhatsApp ──
// Se corre UNA vez después de cargar WA_TOKEN. No envía nada a ningún cliente. Repetirlo no daña.
// Devuelve además la lista de apps suscritas: si aparece una que no es «Casa Zaru Bandeja»
// (p. ej. la de ManyChat), esa app todavía recibe los mensajes y hay que sacarla.
async function suscribir(req: Request) {
  const no = puertaPropia(req);
  if (no) return no;
  const token = (Deno.env.get('WA_TOKEN') ?? '').trim();
  const waba = (Deno.env.get('WA_BUSINESS_ACCOUNT_ID') ?? '').trim();
  if (!token || !/^\d{6,20}$/.test(waba)) return json({ error: 'WA_TOKEN o WA_BUSINESS_ACCOUNT_ID sin configurar' }, 500);
  const u = `https://graph.facebook.com/v25.0/${waba}/subscribed_apps`;
  const h = { Authorization: 'Bearer ' + token };
  const alta = await fetch(u, { method: 'POST', headers: h });
  const altaCuerpo = await alta.json().catch(() => null);
  const lista = await fetch(u, { headers: h });
  const listaCuerpo = await lista.json().catch(() => null);
  return json({
    ok: alta.ok && altaCuerpo?.success === true,
    alta: { status: alta.status, respuesta: altaCuerpo },
    suscritas: (listaCuerpo?.data ?? []).map((a: any) => ({
      id: a.whatsapp_business_api_data?.id, nombre: a.whatsapp_business_api_data?.name,
    })),
    lista_status: lista.status,
  }, alta.ok ? 200 : 502);
}

const RESULTADOS = ['compró', 'siguió', 'silencio', 'perdido', 'pendiente'];

async function conocimiento(req: Request) {
  const no = puertaPropia(req);
  if (no) return no;
  const t = await req.text();
  if (t.length > MAX_BYTES) return json({ error: 'demasiado grande' }, 413);
  let b: { ejemplos?: any[]; guia?: string };
  try { b = JSON.parse(t); } catch { return json({ error: 'JSON inválido' }, 400); }

  const filas = [];
  for (const e of b.ejemplos ?? []) {
    if (!e?.cliente || !e?.respuesta || !e?.intencion || !/^\d{4}-\d{2}-\d{2}$/.test(e.fecha ?? '')) continue;
    if (!['modelo', 'ok', 'evitar'].includes(e.calidad)) continue;
    filas.push({
      clave: await hex('SHA-256', [e.fecha, e.cliente, e.respuesta].join('|')),
      fuente: '5558', fecha: e.fecha, intencion: String(e.intencion).slice(0, 40),
      producto: e.producto ?? null, cliente: String(e.cliente).slice(0, 2000),
      respuesta: String(e.respuesta).slice(0, 4000), calidad: e.calidad,
      // Un valor fuera de la lista haría que la base rechace el lote entero: se guarda vacío.
      resultado_7d: RESULTADOS.includes(e.resultado_7d) ? e.resultado_7d : null,
      por_que: e.por_que ? String(e.por_que).slice(0, 500) : null,
    });
  }
  // merge-duplicates: si la revisión reevalúa una línea (resultado_7d, calidad), se actualiza.
  if (filas.length) await db('mensajes_ejemplos?on_conflict=clave', {
    method: 'POST', prefer: 'resolution=merge-duplicates,return=minimal', body: JSON.stringify(filas),
  });
  let guia = false;
  if (typeof b.guia === 'string' && b.guia.trim().length >= 50) {
    const [ult] = await db('mensajes_guia?select=texto&order=id.desc&limit=1');
    if (ult?.texto !== b.guia) {
      await db('mensajes_guia', { method: 'POST', prefer: 'return=minimal', body: JSON.stringify({ texto: b.guia }) });
      guia = true;
    }
  }
  return json({ ok: true, ejemplos: filas.length, guia_nueva: guia });
}

// ── Entrada ───────────────────────────────────────────────────────────────
Deno.serve(async (req) => {
  const url = new URL(req.url);

  if (req.method === 'GET') {
    const ok = url.searchParams.get('hub.mode') === 'subscribe'
      && iguales(url.searchParams.get('hub.verify_token') ?? '', Deno.env.get('META_VERIFY_TOKEN') ?? '');
    return ok ? new Response(url.searchParams.get('hub.challenge') ?? '', { status: 200 }) : json({ error: 'no' }, 403);
  }
  if (req.method !== 'POST') return json({ error: 'solo GET/POST' }, 405);
  if (url.pathname.endsWith('/conocimiento') || url.pathname.endsWith('/suscribir')) {
    try {
      return await (url.pathname.endsWith('/suscribir') ? suscribir(req) : conocimiento(req));
    } catch (e) { console.error('ruta propia', url.pathname, String(e)); return json({ error: 'falló; ver registros de la función' }, 500); }
  }

  const secreto = Deno.env.get('META_APP_SECRET') ?? '';
  if (!secreto) return json({ error: 'META_APP_SECRET sin configurar' }, 500);
  const texto = await req.text();
  if (texto.length > MAX_BYTES) return json({ error: 'demasiado grande' }, 413);
  if (!(await firmaValida(texto, req.headers.get('x-hub-signature-256') ?? '', secreto))) return json({ error: 'firma' }, 401);

  let cuerpo: unknown;
  try { cuerpo = JSON.parse(texto); } catch { return json({ error: 'JSON inválido' }, 400); }

  // Guardar es lo urgente (Meta reintenta si no hay 200). El borrador va después, en segundo plano.
  // Si uno falla se sigue con los demás y al final se responde 500: Meta reenvía el aviso completo
  // y los ya guardados se ignoran por meta_id, sin duplicar ni perder su borrador.
  const nuevos: { chat: number; id: number }[] = [];
  let fallos = 0;
  for (const x of leerAviso(cuerpo)) {
    try {
      const g = await guardar(x);
      if (g && x.autor === 'cliente' && x.texto) nuevos.push(g);
    } catch (e) { fallos++; console.error('guardar', x.canal, x.metaId, String(e)); }
  }
  const trabajo = (async () => {
    for (const n of nuevos) {
      try { await redactar(n.chat, n.id); } catch (e) { console.error('borrador', n.chat, String(e)); }
    }
  })();
  // @ts-ignore EdgeRuntime existe en Supabase
  if (typeof EdgeRuntime !== 'undefined') EdgeRuntime.waitUntil(trabajo); else await trabajo;
  return fallos ? json({ error: 'guardar', fallos, guardados: nuevos.length }, 500)
                : json({ ok: true, guardados: nuevos.length });
});
