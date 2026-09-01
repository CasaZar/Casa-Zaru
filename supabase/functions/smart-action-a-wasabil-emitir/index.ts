// Supabase Edge Function: wasabil-emitir (desplegada como smart-action-a-wasabil-emitir)
// Puente entre Finanzas (Firebase) y Wasabil. No guarda el documento en sí en
// ninguna tabla de negocio, pero además de reenviar a Wasabil y subirlo a
// Drive, deja una copia del PDF en Supabase Storage y una fila en
// documentos_transitorios (glosa + estado), para el panel "Docs. Wasabil"
// del módulo de Gastos (index.html).
//
// Secrets requeridos además de los ya existentes (WASABIL_API_TOKEN,
// DRIVE_UPLOAD_URL, DRIVE_UPLOAD_SECRET): ninguno nuevo — SUPABASE_URL y
// SUPABASE_SERVICE_ROLE_KEY los inyecta Supabase automáticamente.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const WASABIL_BASE = "https://api.wasabil.com/api";
const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);
const DOCS_BUCKET = "documentos-sii";

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

function sanitizeFilename(name: string): string {
  return name.replace(/[\\/:*?"<>|]/g, "-").replace(/\s+/g, " ").trim();
}

// Wasabil devuelve la URL del PDF/XML con distinto nombre segun el endpoint:
// al crear el documento viene como document_pdf_url, pero al consultar el estado
// (que es lo que pasa siempre despues de emitir) viene como public_pdf_url / pdf_url.
function pdfUrlDe(d: any): string | undefined {
  return d?.document_pdf_url || d?.public_pdf_url || d?.pdf_url || undefined;
}
function xmlUrlDe(d: any): string | undefined {
  return d?.document_xml_url || d?.public_xml_url || d?.xml_url || undefined;
}

function limpiarRut(rutSucio: string): string {
  return String(rutSucio).replace(/[^0-9kK]/g, "").toUpperCase();
}

function rutValido(rutSucio: string): boolean {
  const rut = limpiarRut(rutSucio);
  if (rut.length < 2) return false;
  const cuerpo = rut.slice(0, -1);
  const dv = rut.slice(-1);
  if (!/^\d+$/.test(cuerpo)) return false;
  let suma = 0, multiplo = 2;
  for (let i = cuerpo.length - 1; i >= 0; i--) {
    suma += parseInt(cuerpo[i], 10) * multiplo;
    multiplo = multiplo < 7 ? multiplo + 1 : 2;
  }
  const resto = 11 - (suma % 11);
  const dvEsperado = resto === 11 ? "0" : resto === 10 ? "K" : String(resto);
  return dv === dvEsperado;
}

function formatearRut(rutSucio: string): string {
  const rut = limpiarRut(rutSucio);
  return rut.slice(0, -1) + "-" + rut.slice(-1);
}

// Descarga el PDF UNA sola vez. Antes subirADrive lo bajaba internamente cada
// vez que se la llamaba; ahora Drive y Storage reusan los mismos bytes en vez
// de pegarle dos veces a la misma URL.
async function descargarPdf(pdfUrl: string, token: string): Promise<Uint8Array | null> {
  console.log("PDF: descargando de", pdfUrl);
  const res = await fetch(pdfUrl, { headers: { Authorization: `Bearer ${token}` } });
  if (!res.ok) {
    const t = await res.text();
    console.error("PDF: fallo al descargar", res.status, t.slice(0, 300));
    return null;
  }
  const buf = new Uint8Array(await res.arrayBuffer());
  console.log("PDF: descargado, bytes =", buf.length);
  return buf;
}

async function subirADrive(bytes: Uint8Array, filename: string): Promise<any> {
  try {
    const driveUrl = Deno.env.get("DRIVE_UPLOAD_URL");
    const driveSecret = Deno.env.get("DRIVE_UPLOAD_SECRET");
    if (!driveUrl || !driveSecret) {
      console.error("Drive: faltan DRIVE_UPLOAD_URL o DRIVE_UPLOAD_SECRET");
      return { success: false, error: "Drive no configurado" };
    }
    let binary = "";
    for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
    const pdfBase64 = btoa(binary);

    console.log("Drive: subiendo a Apps Script", driveUrl);
    const upRes = await fetch(driveUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ secret: driveSecret, filename: sanitizeFilename(filename) + ".pdf", pdfBase64 }),
    });
    const text = await upRes.text();
    console.log("Drive: respuesta de Apps Script", upRes.status, text.slice(0, 300));
    try {
      return JSON.parse(text);
    } catch {
      return { success: false, error: "Respuesta inválida de Drive: " + text.slice(0, 200) };
    }
  } catch (err) {
    console.error("Drive: excepción no controlada", String(err));
    return { success: false, error: "Excepción en subida a Drive: " + String(err) };
  }
}

// Copia del PDF en Supabase Storage, para el panel "Docs. Wasabil". Nunca
// revienta la emisión si falla: se loguea y se sigue, igual que subirADrive.
async function subirAStorage(bytes: Uint8Array, path: string): Promise<{ success: boolean; path?: string; error?: string }> {
  try {
    const { error } = await supabase.storage.from(DOCS_BUCKET).upload(path, bytes, {
      contentType: "application/pdf",
      upsert: true,
    });
    if (error) {
      console.error("Storage: fallo al subir", error.message);
      return { success: false, error: error.message };
    }
    return { success: true, path };
  } catch (err) {
    console.error("Storage: excepción no controlada", String(err));
    return { success: false, error: String(err) };
  }
}

// Deja/actualiza la fila en documentos_transitorios. glosa y monto SOLO se
// tocan si esta llamada trae detalle/total: la acción "check" no manda
// ninguno de los dos, y no debe borrar una glosa que alguien ya corrigió a
// mano en el panel, ni pisar el monto con 0.
async function registrarDocumentoTransitorio(params: {
  numStr: string;
  docNum: number | null | undefined;
  tipo: string;
  cliente: string;
  folio: unknown;
  uuid: unknown;
  monto?: unknown;
  detalle?: string;
  storagePath?: string;
  pdfUrl?: string;
}): Promise<void> {
  if (!params.docNum) {
    console.error("documentos_transitorios: falta docNum en el payload, no se registra fila");
    return;
  }
  const row: Record<string, unknown> = {
    num_pedido: String(params.numStr),
    doc_num: params.docNum,
    tipo: params.tipo,
    cliente: params.cliente || null,
    folio: params.folio != null ? String(params.folio) : null,
    uuid: params.uuid != null ? String(params.uuid) : null,
    storage_path: params.storagePath || null,
    pdf_url: params.pdfUrl || null,
  };
  if (params.monto) row.monto = Math.round(Number(params.monto) || 0);
  if (params.detalle) row.glosa = params.detalle;
  const { error } = await supabase
    .from("documentos_transitorios")
    .upsert(row, { onConflict: "num_pedido,doc_num" });
  if (error) console.error("documentos_transitorios: fallo al guardar", error.message);
}

// CAMBIO 28-08: el folio va SIEMPRE en el nombre del archivo.
// Sin él, el segundo documento de un mismo pedido (abono y saldo, o una
// factura re-emitida) repetía el nombre, y la rama de "archivo ya existe"
// del Apps Script escribe como TEXTO: el PDF llegaba corrupto a Drive
// (los "en blanco" del 13 al 28 de agosto). Con folio, cada documento
// tiene nombre propio y esa rama no se ejecuta nunca.
function nombreArchivo(base: string, detalle: unknown, folio: unknown): string {
  const conDetalle = detalle ? `${base} - ${detalle}` : base;
  return folio ? `${conDetalle} - Folio ${folio}` : conDetalle;
}

// Ruta del PDF dentro del bucket documentos-sii: agrupada por pedido, con
// folio en el nombre por la misma razón de arriba — y porque upsert:true ya
// sobrescribe seguro (escribe bytes, no texto), no hace falta más que eso
// para que no colisione entre Doc 1 y Doc 2 del mismo pedido.
function storagePathDe(numStr: string, docNum: number | null | undefined, folio: unknown): string {
  return `${sanitizeFilename(String(numStr))}/doc${docNum ?? "x"}-folio-${folio ?? "pendiente"}.pdf`;
}

async function pollStatus(uuid: string, token: string, maxTries = 8): Promise<any> {
  for (let i = 0; i < maxTries; i++) {
    const res = await fetch(`${WASABIL_BASE}/documents/${uuid}/status`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    const json = await res.json();
    const statusId = json?.data?.status_id;
    if (statusId === 3 || statusId === 4) return json;
    if (i < maxTries - 1) await new Promise((r) => setTimeout(r, 2000));
  }
  return null;
}

Deno.serve(async (req) => {
  try {
    return await handleRequest(req);
  } catch (err) {
    console.error("Excepción no controlada en el handler:", String(err));
    return jsonResponse({ success: false, error: "Excepción no controlada: " + String(err) }, 500);
  }
});

async function handleRequest(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return jsonResponse({ success: false, error: "Método no permitido" }, 405);

  const token = Deno.env.get("WASABIL_API_TOKEN");
  if (!token) return jsonResponse({ success: false, error: "Falta WASABIL_API_TOKEN en los secretos" }, 500);

  let body: any;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ success: false, error: "Body inválido" }, 400);
  }

  const {
    numStr, docNum, docType, total, producto, detalle,
    nombre, apellido, email, rut, razon_social, giro, direccion, comuna, ciudad,
  } = body || {};

  if (body?.action === "check") {
    if (!body.uuid) return jsonResponse({ success: false, error: "Falta uuid" }, 400);
    const nombreCompletoCheck = (razon_social || `${nombre || ""} ${apellido || ""}`).trim();
    const checked = await pollStatus(body.uuid, token, 1);
    const dc = checked?.data;
    if (!dc) return jsonResponse({ success: false, status_id: 2, uuid: body.uuid, error: "Sigue Procesando" });
    let driveCheck: any = null;
    let storageCheck: any = null;
    const pdfCheck = pdfUrlDe(dc);
    if (dc.status_id === 3 && pdfCheck) {
      const baseCheck = docType === "FACTURA" && razon_social
        ? `${numStr}. ${nombreCompletoCheck}. ${razon_social}`
        : `${numStr}. ${nombreCompletoCheck}`;
      // CAMBIO 28-08: folio en el nombre (antes: solo base + detalle)
      const filenameCheck = nombreArchivo(baseCheck, detalle, dc.folio);
      const bytesCheck = await descargarPdf(pdfCheck, token);
      if (bytesCheck) {
        driveCheck = await subirADrive(bytesCheck, filenameCheck);
        storageCheck = await subirAStorage(bytesCheck, storagePathDe(numStr, docNum, dc.folio));
        await registrarDocumentoTransitorio({
          numStr, docNum, tipo: docType, cliente: nombreCompletoCheck,
          folio: dc.folio, uuid: dc.uuid, monto: total, detalle,
          storagePath: storageCheck?.success ? storageCheck.path : undefined,
          pdfUrl: pdfCheck,
        });
      } else {
        driveCheck = { success: false, error: "No se pudo descargar el PDF" };
        storageCheck = { success: false, error: "No se pudo descargar el PDF" };
      }
    }
    return jsonResponse({
      success: dc.status_id === 3,
      status_id: dc.status_id,
      uuid: dc.uuid,
      folio: dc.folio,
      document_pdf_url: pdfCheck,
      document_xml_url: xmlUrlDe(dc),
      display_error: dc.display_error,
      drive: driveCheck,
      storage: storageCheck,
    });
  }

  if (!numStr) return jsonResponse({ success: false, error: "Falta numStr (número de pedido)" }, 400);
  if (!total || Number(total) <= 0) return jsonResponse({ success: false, error: "Falta total o es 0" }, 400);
  if (docType !== "BOLETA" && docType !== "FACTURA") {
    return jsonResponse({ success: false, error: "docType debe ser BOLETA o FACTURA" }, 400);
  }

  const nombreCompleto = (razon_social || `${nombre || ""} ${apellido || ""}`).trim();
  const itemName = String(producto || "Producto").slice(0, 80);

  if ((docType === "FACTURA" || rut) && !rutValido(rut || "")) {
    return jsonResponse({ success: false, error: `El RUT "${rut}" no es válido (revisá el dígito verificador)` }, 400);
  }
  const rutFormateado = rut ? formatearRut(rut) : undefined;

  let wasabilBody: Record<string, unknown>;

  if (docType === "FACTURA") {
    const faltantes = ["giro", "direccion", "comuna", "ciudad"].filter((k) => !body[k]);
    if (!nombreCompleto) faltantes.push("razon_social o nombre");
    if (faltantes.length) {
      return jsonResponse({ success: false, error: `Faltan datos para factura: ${faltantes.join(", ")}` }, 400);
    }
    wasabilBody = {
      sii_document_type_id: 33,
      issue: true,
      currency_symbol: "CLP",
      payment_method: "contado",
      price_includes_iva: true,
      receiver_rut: rutFormateado,
      receiver_name: nombreCompleto,
      receiver_address: direccion,
      receiver_comuna: comuna,
      receiver_city: ciudad,
      receiver_giro: giro,
      receiver_email: email || undefined,
      invoice_reference: String(numStr),
      details: [{ name: itemName, description: detalle || undefined, price: Number(total), quantity: 1 }],
    };
  } else {
    wasabilBody = {
      sii_document_type_id: 39,
      issue: true,
      currency_symbol: "CLP",
      price_includes_iva: true,
      receiver_input: rutFormateado ? "rut" : "none",
      receiver_rut: rutFormateado,
      receiver_name: nombreCompleto || undefined,
      receiver_email: email || undefined,
      details: [{ name: itemName, description: detalle || undefined, price: Number(total), quantity: 1 }],
    };
  }

  console.log("Wasabil: creando documento", JSON.stringify(wasabilBody));
  const createRes = await fetch(`${WASABIL_BASE}/documents`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify(wasabilBody),
  });
  const createText = await createRes.text();
  console.log("Wasabil: respuesta creación", createRes.status, createText.slice(0, 500));
  let createJson: any;
  try {
    createJson = JSON.parse(createText);
  } catch {
    return jsonResponse({ success: false, error: "Wasabil devolvió una respuesta inválida: " + createText.slice(0, 200) }, 400);
  }

  if (!createRes.ok || !createJson?.success) {
    const detalleValidacion = createJson?.validation
      ? Object.entries(createJson.validation).map(([campo, msg]) => `${campo}: ${msg}`).join(" | ")
      : null;
    return jsonResponse({ success: false, error: detalleValidacion || createJson?.error || createJson?.message || "Wasabil rechazó la solicitud", raw: createJson }, 400);
  }

  const uuid = createJson.data.uuid;
  let finalJson = createJson;
  if (createJson.data.status_id === 2) {
    const polled = await pollStatus(uuid, token);
    if (polled) finalJson = polled;
  }

  const d = finalJson.data;
  let drive: any = null;
  let storage: any = null;
  const pdfUrl = pdfUrlDe(d);
  if (d.status_id === 3 && pdfUrl) {
    const baseFilename = docType === "FACTURA" && razon_social
      ? `${numStr}. ${nombreCompleto}. ${razon_social}`
      : `${numStr}. ${nombreCompleto}`;
    // CAMBIO 28-08: folio en el nombre (antes: solo base + detalle)
    const filename = nombreArchivo(baseFilename, detalle, d.folio);
    const bytes = await descargarPdf(pdfUrl, token);
    if (bytes) {
      drive = await subirADrive(bytes, filename);
      storage = await subirAStorage(bytes, storagePathDe(numStr, docNum, d.folio));
      await registrarDocumentoTransitorio({
        numStr, docNum, tipo: docType, cliente: nombreCompleto,
        folio: d.folio, uuid: d.uuid, monto: total, detalle,
        storagePath: storage?.success ? storage.path : undefined,
        pdfUrl,
      });
    } else {
      drive = { success: false, error: "No se pudo descargar el PDF" };
      storage = { success: false, error: "No se pudo descargar el PDF" };
    }
  }

  return jsonResponse({
    success: d.status_id === 3,
    status_id: d.status_id,
    uuid: d.uuid,
    folio: d.folio,
    document_pdf_url: pdfUrl,
    document_xml_url: xmlUrlDe(d),
    display_error: d.display_error,
    drive,
    storage,
  });
}
