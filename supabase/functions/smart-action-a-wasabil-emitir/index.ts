// Supabase Edge Function: wasabil-emitir
// Puente entre Finanzas (Firebase) y Wasabil. No guarda nada, solo reenvía y espera la respuesta del SII.

const WASABIL_BASE = "https://api.wasabil.com/api";
const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

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

async function subirADrive(pdfUrl: string, token: string, filename: string): Promise<any> {
  try {
    const driveUrl = Deno.env.get("DRIVE_UPLOAD_URL");
    const driveSecret = Deno.env.get("DRIVE_UPLOAD_SECRET");
    if (!driveUrl || !driveSecret) {
      console.error("Drive: faltan DRIVE_UPLOAD_URL o DRIVE_UPLOAD_SECRET");
      return { success: false, error: "Drive no configurado" };
    }

    console.log("Drive: descargando PDF de", pdfUrl);
    const pdfRes = await fetch(pdfUrl, { headers: { Authorization: `Bearer ${token}` } });
    if (!pdfRes.ok) {
      const t = await pdfRes.text();
      console.error("Drive: fallo al descargar PDF", pdfRes.status, t.slice(0, 300));
      return { success: false, error: `No se pudo descargar el PDF (${pdfRes.status})` };
    }
    const buf = new Uint8Array(await pdfRes.arrayBuffer());
    console.log("Drive: PDF descargado, bytes =", buf.length);
    let binary = "";
    for (let i = 0; i < buf.length; i++) binary += String.fromCharCode(buf[i]);
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
    numStr, docType, total, producto, detalle,
    nombre, apellido, email, rut, razon_social, giro, direccion, comuna, ciudad,
  } = body || {};

  if (body?.action === "check") {
    if (!body.uuid) return jsonResponse({ success: false, error: "Falta uuid" }, 400);
    const nombreCompletoCheck = (razon_social || `${nombre || ""} ${apellido || ""}`).trim();
    const checked = await pollStatus(body.uuid, token, 1);
    const dc = checked?.data;
    if (!dc) return jsonResponse({ success: false, status_id: 2, uuid: body.uuid, error: "Sigue Procesando" });
    let driveCheck: any = null;
    const pdfCheck = pdfUrlDe(dc);
    if (dc.status_id === 3 && pdfCheck) {
      const baseCheck = docType === "FACTURA" && razon_social
        ? `${numStr}. ${nombreCompletoCheck}. ${razon_social}`
        : `${numStr}. ${nombreCompletoCheck}`;
      // CAMBIO 28-08: folio en el nombre (antes: solo base + detalle)
      const filenameCheck = nombreArchivo(baseCheck, detalle, dc.folio);
      driveCheck = await subirADrive(pdfCheck, token, filenameCheck);
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
  const pdfUrl = pdfUrlDe(d);
  if (d.status_id === 3 && pdfUrl) {
    const baseFilename = docType === "FACTURA" && razon_social
      ? `${numStr}. ${nombreCompleto}. ${razon_social}`
      : `${numStr}. ${nombreCompleto}`;
    // CAMBIO 28-08: folio en el nombre (antes: solo base + detalle)
    const filename = nombreArchivo(baseFilename, detalle, d.folio);
    drive = await subirADrive(pdfUrl, token, filename);
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
  });
}
