// Puente cotizador -> Shopify. Recibe la misma forma de datos que getShareData()
// en cotizador-clientes.html + { tier, extras, pesoKg, detalle }. Recalcula el
// precio con su propia copia de la tabla de precios (nunca confía en un precio
// que venga del navegador) y crea un Draft Order en Shopify con ese precio.
//
// Secrets requeridos (Supabase Edge Functions -> Manage secrets):
//   SHOPIFY_STORE_DOMAIN  ej. "casazaru.myshopify.com"
//   SHOPIFY_ADMIN_TOKEN   token de una Custom App con scope write_draft_orders
//
// SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY los inyecta Supabase automaticamente.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const ALLOWED_ORIGIN = 'https://cotizador.casazaru.cl';
const SHOPIFY_API_VERSION = '2026-04';

const corsHeaders = {
  'Access-Control-Allow-Origin': ALLOWED_ORIGIN,
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// ---- Misma tabla de precios que cotizador-clientes.html (PR) ----
//
// ⚠ FUENTE ÚNICA: si tocas PR en cotizador-clientes.html (~línea 570) TIENES
// que copiar el cambio acá. Esta tabla ya se desincronizó una vez: nació como
// copia del cotizador de julio y quedó con las puertas entre 16% y 35% más
// baratas (granero alto 263.250 contra 362.145). Como esta función es la que
// cobra de verdad en Shopify, esa diferencia se le cobraba al cliente.
// Sincronizada el 9 ago 2026.
//
// ⚠ IVA: TODOS estos precios son con IVA incluido, igual que el cotizador.
// Antes de encender el botón "Comprar ahora" hay que configurar Shopify con
// "prices include tax", o el cliente pagará un 19% de más.
const PR: Record<string, any> = {
  cubierta: { alto: 362145, medio: 333184, bajo: 241890 },
  repisa: { alto: 315066, medio: 289870, bajo: 210444 },
  peldano: { alto: 362145, medio: 333184, bajo: 241890 },
  granero: { bajo: { m2: 241890, fijo: 50000 }, medio: { m2: 333184, fijo: 50000 }, alto: { m2: 362145, fijo: 50000 } },
  maciza: { alto: { m2: 362145, fijo: 80000 }, medio: { m2: 333184, fijo: 80000 }, bajo: { m2: 241890, fijo: 80000 } },
  vidrios: { alto: { m2: 362145, fijo: 80000 }, medio: { m2: 333184, fijo: 80000 }, bajo: { m2: 241890, fijo: 80000 } },
  revestimiento: { coihue: 89900, cipres: 82900 },
};
const WOOD: Record<string, string> = { alto: 'Coihue / Raulí / Lenga', medio: 'Castaño / Ciprés / Mañío', bajo: 'Pino Oregón' };
const PNAME: Record<string, string> = {
  cubierta: 'Cubiertas', repisa: 'Repisa / Cubierta 2cm', peldano: 'Peldaños',
  granero: 'Puerta Granero', maciza: 'Puerta Madera', vidrios: 'Puerta con Vidrios',
  revestimiento: 'Revestimiento',
};
// Misma tabla que EXTRAS en cotizador-clientes.html
const EXTRAS: Record<string, { precio: number; unit: string }> = {
  tenido: { precio: 10000, unit: 'm2' },
  perf_enc: { precio: 14900, unit: 'cu' },
  perf_red: { precio: 5000, unit: 'cu' },
  union45: { precio: 24900, unit: 'cu' },
};

function extrasTotal(extras: Record<string, any> | undefined, m2: number) {
  if (!extras) return 0;
  var total = 0;
  for (var id in EXTRAS) {
    var e = EXTRAS[id];
    var v = extras[id];
    if (!v) continue;
    total += e.unit === 'm2' ? e.precio * m2 : e.precio * (parseInt(v) || 0);
  }
  return total;
}

function calcular(data: any) {
  var p = data.p;
  if (['cubierta', 'repisa', 'peldano'].includes(p)) {
    var sumM2 = 0;
    (data.rows || []).forEach((r: any) => { sumM2 += (r.lg / 100) * (r.an / 100) * (r.ca || 1); });
    var tier = ['bajo', 'medio', 'alto'].includes(data.tier) ? data.tier : 'alto';
    var total = sumM2 * PR[p][tier] + extrasTotal(data.extras, sumM2);
    return {
      total: total,
      grams: Math.round(sumM2 * 30) * 1000,
      titulo: PNAME[p] + ' — ' + WOOD[tier] + ' (' + sumM2.toFixed(2) + ' m²)',
      detalle: sumM2.toFixed(2) + ' m²',
      madera: WOOD[tier],
    };
  }
  if (['granero', 'maciza', 'vidrios'].includes(p)) {
    var filas = (data.rows || []).map((r: any) => ({ lg: r.lg, an: r.an, ca: r.ca || 1, m2: (r.lg / 100) * (r.an / 100) }));
    var tier2 = ['bajo', 'medio', 'alto'].includes(data.tier) ? data.tier : 'alto';
    var extraTipo = (p === 'granero' || p === 'vidrios') ? (data.vt || '') : '';
    var sumNeto = 0, sumPesoM2 = 0;
    filas.forEach((f: any) => {
      var extraIva = extraTipo ? f.m2 * 40000 * 1.19 : 0;
      sumNeto += (f.m2 * PR[p][tier2].m2 + PR[p][tier2].fijo) * f.ca + extraIva * f.ca;
      sumPesoM2 += f.m2 * f.ca;
    });
    var marco = data.marco || [];
    var mcM2 = 0;
    marco.forEach((m: any) => { mcM2 += (m.ml || 0) * ((m.an || 0) / 100); });
    if (mcM2 > 0) sumNeto += mcM2 * PR.cubierta[tier2];
    return {
      total: sumNeto,
      grams: Math.round(sumPesoM2 * 30) * 1000,
      titulo: PNAME[p] + ' — ' + WOOD[tier2] + ' (' + filas.length + ' u.)',
      detalle: filas.length + ' u.',
      madera: WOOD[tier2],
    };
  }
  if (p === 'revestimiento') {
    var m2r = data.m2 || 0;
    var tier3 = data.tier === 'alto' ? 'alto' : 'bajo';
    var precioM2 = tier3 === 'alto' ? PR.revestimiento.coihue : PR.revestimiento.cipres;
    return {
      total: m2r * precioM2,
      grams: Math.round(m2r * 10) * 1000,
      titulo: 'Revestimiento — ' + (tier3 === 'alto' ? 'Coihue' : 'Ciprés') + ' (' + m2r.toFixed(2) + ' m²)',
      detalle: m2r.toFixed(2) + ' m²',
      madera: tier3 === 'alto' ? 'Coihue' : 'Ciprés',
    };
  }
  throw new Error('Producto no reconocido: ' + p);
}

async function quoteExiste(supabase: any, numero: string) {
  for (var intento = 0; intento < 2; intento++) {
    var { data } = await supabase.from('cotizaciones').select('numero').eq('numero', numero).limit(1);
    if (data && data.length) return true;
    if (intento === 0) await new Promise((r) => setTimeout(r, 400));
  }
  return false;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    var body = await req.json();
    if (!body.qnum) return json({ error: 'Falta número de cotización' }, 400);

    var supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    var existe = await quoteExiste(supabase, body.qnum);
    if (!existe) return json({ error: 'Cotización no encontrada' }, 404);

    var calc = calcular(body);
    if (!(calc.total > 0)) return json({ error: 'No se pudo calcular el precio' }, 400);

    var storeDomain = Deno.env.get('SHOPIFY_STORE_DOMAIN');
    var token = Deno.env.get('SHOPIFY_ADMIN_TOKEN');
    if (!storeDomain || !token) return json({ error: 'Tienda no configurada' }, 500);

    var shopifyRes = await fetch('https://' + storeDomain + '/admin/api/' + SHOPIFY_API_VERSION + '/draft_orders.json', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Shopify-Access-Token': token },
      body: JSON.stringify({
        draft_order: {
          line_items: [{
            title: calc.titulo,
            price: calc.total.toFixed(2),
            quantity: 1,
            grams: calc.grams,
            taxable: true,
            properties: [
              { name: 'Cotización', value: body.qnum },
              { name: 'Madera', value: calc.madera },
              { name: 'Detalle', value: calc.detalle },
            ],
          }],
          note: 'Cotización ' + body.qnum + ' generada desde cotizador.casazaru.cl',
          tags: 'cotizador-web',
        },
      }),
    });

    var shopifyOut = await shopifyRes.json();
    if (!shopifyRes.ok) {
      console.error('Shopify error:', shopifyOut);
      return json({ error: 'Error al crear el pedido en Shopify' }, 502);
    }

    return json({ invoice_url: shopifyOut.draft_order.invoice_url }, 200);
  } catch (e) {
    console.error('create-draft-order:', e);
    return json({ error: 'Error interno' }, 500);
  }
});

function json(obj: any, status: number) {
  return new Response(JSON.stringify(obj), { status: status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
}
