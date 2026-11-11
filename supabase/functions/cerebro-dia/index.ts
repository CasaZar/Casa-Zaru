// Cerebro Zaru — escribe el día armado en la pestaña «Mi día» — proyecto Gestión (padnttpgzuotxeipjrry).
//
// La corrida de las 07:30 (tarea programada en el PC del dueño) arma el día y lo manda acá.
// Esta función hace UNA sola cosa: upsert de una fila en public.cerebro_dias (migración 0030).
// No lee ni toca ninguna otra tabla. Si el secreto se filtrara, lo peor que se puede hacer es
// reescribir lo que muestra «Mi día»: nada de pedidos, pagos ni clientes.
//
// Llamada: POST JSON { fecha: 'YYYY-MM-DD', data: { ...el día... } }
//          con el encabezado  x-cerebro-token: <CEREBRO_TOKEN>
// Respuesta: { ok: true, fecha, bytes } o { error } con 400/401/405/413/500.
//
// Despliegue: panel de Gestión → Edge Functions → Via Editor, nombre `cerebro-dia`.
// «Verify JWT» APAGADO: la corrida no tiene sesión de usuario; la puerta es el secreto propio.
//
// Secretos (los carga el administrador; NUNCA van al repo):
//   CEREBRO_TOKEN   texto largo al azar. La copia del PC vive en %USERPROFILE%\.casazaru\cerebro-token.txt
// SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY los inyecta Supabase (la llave de servicio nunca sale del servidor).

const MAX_BYTES = 300000;

function json(cuerpo: unknown, status = 200) {
  return new Response(JSON.stringify(cuerpo), { status, headers: { 'Content-Type': 'application/json' } });
}

// Comparación en tiempo constante, para no regalar el secreto letra por letra.
function iguales(a: string, b: string) {
  if (!a || !b || a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'solo POST' }, 405);

  const esperado = (Deno.env.get('CEREBRO_TOKEN') || '').trim();
  if (esperado.length < 32) return json({ error: 'CEREBRO_TOKEN sin configurar' }, 500);
  if (!iguales((req.headers.get('x-cerebro-token') || '').trim(), esperado)) return json({ error: 'no autorizado' }, 401);

  const texto = await req.text();
  if (texto.length > MAX_BYTES) return json({ error: 'demasiado grande' }, 413);
  let cuerpo: { fecha?: string; data?: unknown };
  try { cuerpo = JSON.parse(texto); } catch { return json({ error: 'JSON inválido' }, 400); }

  const fecha = String(cuerpo.fecha || '');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(fecha) || isNaN(Date.parse(fecha + 'T12:00:00Z'))) return json({ error: 'fecha inválida' }, 400);
  const data = cuerpo.data;
  if (!data || typeof data !== 'object' || Array.isArray(data)) return json({ error: 'data debe ser un objeto' }, 400);

  const url = Deno.env.get('SUPABASE_URL');
  const llave = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !llave) return json({ error: 'faltan variables de Supabase' }, 500);

  const r = await fetch(url + '/rest/v1/cerebro_dias?on_conflict=fecha', {
    method: 'POST',
    headers: {
      apikey: llave,
      Authorization: 'Bearer ' + llave,
      'Content-Type': 'application/json',
      Prefer: 'resolution=merge-duplicates,return=minimal',
    },
    body: JSON.stringify({ fecha, data }),
  });
  if (!r.ok) {
    console.error('cerebro-dia upsert', r.status, await r.text());
    return json({ error: 'no se pudo guardar' }, 500);
  }
  return json({ ok: true, fecha, bytes: texto.length });
});
