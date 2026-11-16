-- Cerebro Zaru · Cruce de datos, lado GESTIÓN (padnttpgzuotxeipjrry). Solo lectura.
-- Correr con mcp__supabase-gestion__execute_sql. Nunca en el proyecto del Cotizador.
-- Devuelve UNA fila con las ventas de los últimos 60 días y las que tienen saldo, con sus abonos y RUT
-- (sin muestrarios ni devoluciones): es la entrada -Gestion de .claude/cerebro/cruzar-dia.ps1.
-- Para los pedidos de los últimos 30 días trae además `det` (direcciones, documento y piezas): es lo que
-- la etapa 3 compara contra lo conversado por WhatsApp.
-- El resultado se guarda tal cual en el scratchpad (trae nombres, teléfonos y direcciones: nunca al repo).
with hoy as (select (now() at time zone 'America/Santiago')::date d),
f as (
  select num, data d,
         data->>'nombre'   as nombre,
         data->>'apellido' as apellido,
         data->>'celular'  as celular,
         coalesce(nullif(data->>'tipo', ''), 'VENTA') as tipo,
         data->>'canal_pago' as canal_pago,
         coalesce(nullif(data->>'total', '')::numeric, 0)    as total,
         coalesce(nullif(data->>'val_prod', '')::numeric, 0) as val_prod,
         coalesce(nullif(data->>'abono1', '')::numeric, 0) as a1,
         coalesce(nullif(data->>'abono2', '')::numeric, 0) as a2,
         coalesce(nullif(data->>'abono3', '')::numeric, 0) as a3,
         data->>'rut' as rut,
         data->>'razon_social' as razon,
         case when data->>'fecha' ~ '^\d{1,2}/\d{1,2}/\d{4}$' then to_date(data->>'fecha', 'DD/MM/YYYY') end as fecha
  from gestion_finanzas
),
g as (
  select f.num, f.nombre, f.apellido, f.celular, f.tipo, f.canal_pago, f.total, f.val_prod, f.a1, f.a2, f.a3,
         f.rut, f.razon, f.fecha,
         case when f.fecha >= hoy.d - 30 then jsonb_build_object(
           'direccion', f.d->>'direccion', 'comuna', f.d->>'comuna', 'ciudad', f.d->>'ciudad',
           'giro', f.d->>'giro', 'doc_tipo', f.d->>'doc1_tipo',
           'fact_direccion', f.d->>'fact_direccion', 'fact_comuna', f.d->>'fact_comuna',
           'val_envio', coalesce(nullif(f.d->>'val_envio', '')::numeric, 0),
           'doc_emitido', coalesce((f.d->>'doc1_emitida')::boolean, false) or coalesce((f.d->>'doc2_emitida')::boolean, false)
                          or coalesce((f.d->>'doc3_emitida')::boolean, false),
           'lineas', (select coalesce(jsonb_agg(jsonb_build_object('madera', l->>'madera', 'largo', l->>'largo',
                                                                     'ancho', l->>'ancho', 'cantidad', l->>'cantidad')), '[]'::jsonb)
                      from gestion_produccion p, jsonb_array_elements(case when jsonb_typeof(p.data->'lineas') = 'array' then p.data->'lineas' else '[]'::jsonb end) l
                      where p.num = f.num)
         ) end as det
  from f, hoy
  where f.tipo = 'VENTA'
    and (f.fecha >= hoy.d - 60                -- ventas recientes
         or f.total - f.a1 - f.a2 - f.a3 > 0) -- o cualquier pedido con saldo (etapa 2: pagos)
)
select coalesce(jsonb_agg(g order by g.num), '[]'::jsonb) as cruce from g;
