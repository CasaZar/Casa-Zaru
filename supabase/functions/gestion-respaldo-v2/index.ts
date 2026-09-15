// ══════════════════════════════════════════════════════════════════════════
// gestion-respaldo — respaldo diario de TODO el proyecto de Gestión a Drive
//
// Proyecto: padnttpgzuotxeipjrry («ZARU · Gestión»). Lo llama el cron
// `gestion-respaldo-diario` (06:00 UTC = 03:00 en Chile) con un POST que trae
// { secret } en el cuerpo. Deja `respaldo-gestion-AAAA-MM-DD.json` en la carpeta
// «Respaldos Gestion» de Drive, a través del mismo Apps Script de las boletas,
// que se queda con los últimos 30.
//
// POR QUÉ SE REESCRIBIÓ (15-09-2026): la versión anterior respaldaba una lista
// FIJA de 8 tablas gestion_*. Todo lo que se creó después quedó afuera sin que
// nadie lo notara: gestion_documentos, el módulo de gastos entero (facturas,
// mayor, inventario...), Recibidos, centros de costo y las cotizaciones. En el
// plan Free de Supabase no hay respaldos propios, así que esas tablas no tenían
// ninguna copia. Ahora las tablas se DESCUBREN en cada corrida leyendo la
// descripción de la API: una tabla nueva entra sola al respaldo del día
// siguiente, sin tocar este archivo.
//
// Además, la versión anterior se publicó por API sin guardar el fuente: el
// panel ya no puede mostrarla ("Failed to retrieve function bundle"). Por eso
// esta vive en el repo.
//
// Secretos que usa: RESPALDO_SECRET (el que manda el cron), DRIVE_UPLOAD_URL y
// DRIVE_UPLOAD_SECRET (los mismos del Apps Script de las boletas).
// SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY los inyecta Supabase solo.
// ══════════════════════════════════════════════════════════════════════════

const SB_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SB_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

// Si alguna de estas viene vacía algo está muy mal (una migración que borró
// datos, una llave sin permisos). Se aborta en vez de guardar: un respaldo vacío
// con la fecha de hoy empuja fuera de la retención a uno bueno.
const PRINCIPALES = ["gestion_pedidos", "gestion_produccion", "gestion_finanzas"];

// PostgREST entrega de a 1000 filas.
const PAGINA = 1000;

function responder(cuerpo: unknown, status = 200): Response {
  return new Response(JSON.stringify(cuerpo), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function cabeceras(extra: Record<string, string> = {}): Record<string, string> {
  return { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`, ...extra };
}

// Todo lo que expone la API, con su llave primaria. La llave hace falta para
// paginar ordenado: sin orden fijo, una fila puede repetirse o saltarse entre
// páginas y el respaldo quedaría incompleto sin que nada lo avise.
async function descubrirTablas(): Promise<{ nombre: string; pk: string[] }[]> {
  const r = await fetch(`${SB_URL}/rest/v1/`, {
    headers: cabeceras({ Accept: "application/openapi+json" }),
  });
  if (!r.ok) throw new Error(`No se pudo leer la descripción de la API (${r.status})`);
  const api = await r.json();
  const defs = (api?.definitions ?? {}) as Record<string, { properties?: Record<string, { description?: string }> }>;
  return Object.entries(defs)
    .map(([nombre, def]) => ({
      nombre,
      pk: Object.entries(def.properties ?? {})
        .filter(([, p]) => String(p.description ?? "").includes("<pk/>"))
        .map(([columna]) => columna),
    }))
    .sort((a, b) => a.nombre.localeCompare(b.nombre));
}

async function volcarTabla(t: { nombre: string; pk: string[] }): Promise<{ filas: unknown[]; total: number }> {
  const orden = t.pk.length ? "&order=" + t.pk.map((c) => `${c}.asc`).join(",") : "";
  const filas: unknown[] = [];
  let total = -1;
  for (let offset = 0; total < 0 || offset < total; offset += PAGINA) {
    const r = await fetch(
      `${SB_URL}/rest/v1/${encodeURIComponent(t.nombre)}?select=*&limit=${PAGINA}&offset=${offset}${orden}`,
      { headers: cabeceras({ Prefer: "count=exact" }) },
    );
    if (!r.ok) throw new Error(`${t.nombre}: ${r.status} ${(await r.text()).slice(0, 200)}`);
    if (total < 0) total = Number((r.headers.get("Content-Range") ?? "*/0").split("/")[1]) || 0;
    const pagina = await r.json();
    if (!Array.isArray(pagina)) throw new Error(`${t.nombre}: respuesta inesperada`);
    filas.push(...pagina);
    if (pagina.length === 0) break;
  }
  return { filas, total: Math.max(total, 0) };
}

// btoa solo acepta latin-1: se codifica a UTF-8 primero, o las tildes y las ñ
// de nombres y glosas romperían la subida. Por tramos, porque pasar millones de
// bytes de una vez a fromCharCode revienta la pila.
function aBase64(texto: string): string {
  const bytes = new TextEncoder().encode(texto);
  let binario = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binario += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(binario);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return responder({ success: false, error: "Método no permitido" }, 405);

  let body: { secret?: string } = {};
  try { body = await req.json(); } catch { /* sin cuerpo: cae en el control de abajo */ }
  const esperado = Deno.env.get("RESPALDO_SECRET");
  if (!esperado || body.secret !== esperado) return responder({ success: false, error: "No autorizado" }, 401);

  const driveUrl = Deno.env.get("DRIVE_UPLOAD_URL");
  const driveSecret = Deno.env.get("DRIVE_UPLOAD_SECRET");
  if (!SB_URL || !SB_KEY || !driveUrl || !driveSecret) {
    return responder({ success: false, error: "Faltan secretos de la función" }, 500);
  }

  try {
    const lista = await descubrirTablas();
    const tablas: Record<string, unknown[]> = {};
    const resumen: Record<string, number> = {};
    const avisos: string[] = [];

    for (const t of lista) {
      const { filas, total } = await volcarTabla(t);
      tablas[t.nombre] = filas;
      resumen[t.nombre] = filas.length;
      if (filas.length !== total) avisos.push(`${t.nombre}: trajo ${filas.length} de ${total}`);
    }

    for (const p of PRINCIPALES) {
      if (!(resumen[p] > 0)) {
        console.error("Respaldo abortado:", p, "vino vacía o no existe", resumen);
        return responder({ success: false, error: `Abortado: ${p} vino vacía o no existe`, resumen }, 500);
      }
    }

    const documento = JSON.stringify({ generado: new Date().toISOString(), origen: SB_URL, tablas });
    // La fecha del nombre es la de Chile: a las 03:00 coincide con UTC, pero así
    // una corrida manual de noche no queda con la fecha del día siguiente.
    const fecha = new Date().toLocaleDateString("en-CA", { timeZone: "America/Santiago" });
    const archivo = `respaldo-gestion-${fecha}.json`;

    const subida = await fetch(driveUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        secret: driveSecret,
        filename: archivo,
        pdfBase64: aBase64(documento),   // el Apps Script usa ese nombre de campo para cualquier archivo
        mimeType: "application/json",
        carpeta: "Respaldos Gestion",
      }),
    });
    const texto = await subida.text();
    let drive: { success?: boolean; error?: string; fileId?: string };
    try { drive = JSON.parse(texto); } catch { drive = { success: false, error: texto.slice(0, 200) }; }

    const ok = !!drive.success;
    console.log("Respaldo", ok ? "OK" : "FALLÓ", archivo, `${lista.length} tablas`, `${documento.length} bytes`, avisos);
    return responder(
      { success: ok, archivo, tablas: lista.length, bytes: documento.length, resumen, avisos, drive },
      ok ? 200 : 502,
    );
  } catch (err) {
    console.error("Respaldo: excepción", String(err));
    return responder({ success: false, error: String(err) }, 500);
  }
});
