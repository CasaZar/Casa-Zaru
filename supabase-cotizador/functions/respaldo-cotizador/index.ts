// ══════════════════════════════════════════════════════════════════════════
// respaldo-cotizador — respaldo diario de TODO el proyecto del Cotizador a Drive
//
// Proyecto: cmxqorsyxoltrakxawro («ZARU · Cotizador (público y panel)»). Lo
// llaman los crons `respaldo-cotizador-diario` (06:00 UTC = 03:00 en Chile) y
// `respaldo-cotizador-tarde` (21:00 UTC) con un POST que trae { secret } en el
// cuerpo; ver `supabase-cotizador/respaldo-diario.sql`. Deja
// `respaldo-cotizador-AAAA-MM-DD.zip` (un JSON adentro, mismo formato que el
// script local) en la subcarpeta «Respaldos Cotizador» de la carpeta de Drive
// que maneja el Apps Script de las boletas.
//
// POR QUÉ EXISTE (26-10-2026): hasta ahora el respaldo del Cotizador era una
// tarea de Windows en el PC de la oficina (`.casazaru\respaldo-cotizador.ps1`).
// Del 23 al 25-10 no corrió: el PC despertaba sin red, el script fallaba y el
// domingo ni despertó. Un respaldo que depende de que un computador esté
// prendido no es un respaldo. Esta función corre en Supabase, igual que
// `gestion-respaldo-v2` en Gestión, de la que copia el diseño:
//   - las tablas se DESCUBREN leyendo la descripción de la API (una tabla nueva
//     entra sola al día siguiente, sin tocar este archivo);
//   - se pagina de a 1000 ordenando por la llave primaria (sin orden fijo una
//     fila puede repetirse o saltarse entre páginas);
//   - si `cotizaciones`, `toques` o `cotizador_valores` vienen vacías se ABORTA:
//     un respaldo vacío con la fecha de hoy pisaría uno bueno.
// El zip se arma acá (fflate) para que `/auditoria` y `restaurar-prueba.ps1`
// sigan leyendo el mismo formato que dejaba el script local.
//
// Despliegue (no hay CLI en el PC): panel del Cotizador → Edge Functions →
// Deploy a new function → Via Editor, nombre `respaldo-cotizador`, pegar este
// archivo. Apagar «Verify JWT»: el cron no manda JWT, lo que autoriza es el
// secreto del cuerpo. Verificar el código pegado por sha1 antes de Deploy.
//
// Secretos (Edge Functions → Secrets). NUNCA van al repo, que es público:
//   RESPALDO_SECRET      el que manda el cron (el mismo que se guarda en Vault)
//   DRIVE_UPLOAD_URL     URL /exec del Apps Script de las boletas (el mismo de Gestión)
//   DRIVE_UPLOAD_SECRET  secreto compartido de ese Apps Script (el mismo de Gestión)
// SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY los inyecta Supabase solo.
//
// Retención: el Apps Script deja solo los últimos 30 archivos en «Respaldos
// Gestion». Para que haga lo mismo acá hay que cambiarle una línea:
//   if (body.carpeta === 'Respaldos Gestion')      →  if (/^Respaldos /.test(body.carpeta))
// Mientras no se cambie, los zips se acumulan (~750 KB/día), nada se pierde.
// ══════════════════════════════════════════════════════════════════════════

import { strToU8, zipSync } from "npm:fflate@0.8.2";

const SB_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SB_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

// Si alguna viene vacía algo está muy mal (una migración que borró datos, una
// llave sin permisos). Se aborta en vez de guardar.
const PRINCIPALES = ["cotizaciones", "toques", "cotizador_valores"];

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

// Todo lo que expone la API, con su llave primaria (PostgREST la marca con
// <pk/> en la descripción de la columna).
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

// btoa solo acepta latin-1 y bytes: se pasa por tramos porque fromCharCode con
// millones de bytes de una vez revienta la pila.
function bytesABase64(bytes: Uint8Array): string {
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
    // Fecha de Chile en el nombre: a las 03:00 coincide con UTC, pero así una
    // corrida manual de noche no queda con la fecha del día siguiente.
    const fecha = new Date().toLocaleDateString("en-CA", { timeZone: "America/Santiago" });
    const base = `respaldo-cotizador-${fecha}`;
    const zip = zipSync({ [`${base}.json`]: strToU8(documento) }, { level: 6 });

    const subida = await fetch(driveUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        secret: driveSecret,
        filename: `${base}.zip`,
        pdfBase64: bytesABase64(zip),   // el Apps Script usa ese nombre de campo para cualquier archivo
        mimeType: "application/zip",
        carpeta: "Respaldos Cotizador",
      }),
    });
    const texto = await subida.text();
    let drive: { success?: boolean; error?: string; fileId?: string };
    try { drive = JSON.parse(texto); } catch { drive = { success: false, error: texto.slice(0, 200) }; }

    const ok = !!drive.success;
    console.log("Respaldo", ok ? "OK" : "FALLÓ", `${base}.zip`, `${lista.length} tablas`, `${documento.length} bytes json`, `${zip.length} bytes zip`, avisos);
    return responder(
      { success: ok, archivo: `${base}.zip`, tablas: lista.length, bytesJson: documento.length, bytesZip: zip.length, resumen, avisos, drive },
      ok ? 200 : 502,
    );
  } catch (err) {
    console.error("Respaldo: excepción", String(err));
    return responder({ success: false, error: String(err) }, 500);
  }
});
