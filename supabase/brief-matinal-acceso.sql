-- ══════════════════════════════════════════════════════════════
-- Casa Zaru · Acceso acotado para el brief matinal automático
--
-- Problema: el brief matinal corre como un agente en la nube sin sesión
-- de usuario — solo tiene la API key pública (anon), la misma que ya
-- viaja en el navegador. Las tablas de GESTIÓN y de Cotizaciones exigen
-- sesión autenticada (RLS), así que el anon key NO puede leerlas directo
-- (correcto y deseado — no lo cambiamos). En vez de eso, exponemos dos
-- funciones muy angostas (SECURITY DEFINER) que devuelven SOLO los
-- campos mínimos que el brief necesita — nada de Finanzas, Costos, ni
-- datos de pago.
--
-- Hay que correr DOS bloques en DOS proyectos Supabase distintos:
--   • BLOQUE A → proyecto GESTIÓN (el que usa index.html)
--   • BLOQUE B → proyecto Cotizador Interno (el que usa
--     cotizador-clientes.html — atención al nombre cruzado, ver
--     CLAUDE.md / memoria del proyecto)
-- ══════════════════════════════════════════════════════════════


-- ══════════════════════════════════════════════════════════════
-- BLOQUE A — proyecto GESTIÓN
-- ══════════════════════════════════════════════════════════════

-- ── PASO A1: diagnóstico — columnas reales de gestion_ventas ──
-- Ya existe una VISTA "gestion_ventas" (creada en la migración del 2 ago
-- 2026) que cruza finanzas+producción con la fecha ya normalizada — mejor
-- base que adivinar claves sueltas del jsonb. Corre esto primero:
select column_name, data_type
from information_schema.columns
where table_name = 'gestion_ventas'
order by ordinal_position;

-- si por algún motivo gestion_ventas no sirve (no tiene canal, o no tiene
-- valor de producto separado del total), como respaldo mira las claves
-- del jsonb crudo con esto:
select jsonb_object_keys(data) as clave, count(*)
from gestion_produccion group by 1 order by 2 desc;
select jsonb_object_keys(data) as clave, count(*)
from gestion_pedidos group by 1 order by 2 desc;
select jsonb_object_keys(data) as clave, count(*)
from gestion_finanzas group by 1 order by 2 desc;

-- pégame el resultado (sobre todo el de gestion_ventas) y completo la
-- función financiera de cierre semanal (PASO A3, más abajo, pendiente).

-- ── PASO A2: función angosta — pedidos sin semana de producción ──
-- Solo expone num + nombre/apellido. Nada de plata, nada de teléfono.
create or replace function public.brief_pedidos_sin_semana()
returns table(num text, cliente text)
language sql
security definer
set search_path = public
as $$
  select g.num,
         nullif(trim(coalesce(g.data->>'nombre','') || ' ' || coalesce(g.data->>'apellido','')), '')
  from gestion_produccion g
  where coalesce(trim(g.data->>'semana'), '') = '';
$$;

grant execute on function public.brief_pedidos_sin_semana() to anon;

-- ── verificación A2: correr como anon (con la apikey pública) debería
-- devolver filas, no un error de permiso. Pruébalo con:
--   curl "$SB_URL/rest/v1/rpc/brief_pedidos_sin_semana" \
--     -H "apikey: $SB_ANON" -H "Authorization: Bearer $SB_ANON"

-- ── PASO A3: PENDIENTE — venta del mes por canal WhatsApp (val_prod) ──
-- No la escribo todavía: necesito los nombres reales de PASO A1 antes
-- de tocar un cálculo que alimenta la comisión de un vendedor. Cuando
-- me pases el resultado, esta función queda así (placeholder, NO correr
-- todavía — reemplazar los nombres de clave entre <> primero):
--
-- create or replace function public.brief_venta_mes_whatsapp()
-- returns table(mes_total numeric, mes_cantidad int)
-- language sql security definer set search_path = public as $$
--   select coalesce(sum((f.data->>'<CLAVE_VAL_PROD>')::numeric), 0),
--          count(*)
--   from gestion_finanzas f
--   join gestion_pedidos p on p.num = f.num
--   where p.data->>'<CLAVE_CANAL>' = 'whatsapp'
--     and date_trunc('month', (p.data->>'<CLAVE_FECHA>')::timestamptz)
--         = date_trunc('month', now());
-- $$;
-- grant execute on function public.brief_venta_mes_whatsapp() to anon;


-- ══════════════════════════════════════════════════════════════
-- BLOQUE B — proyecto Cotizador Interno (cotizador-clientes.html)
-- ══════════════════════════════════════════════════════════════

-- cotizaciones es una tabla relacional normal (no jsonb), columnas
-- confirmadas por el código del panel: id, cliente, estado, total_alto,
-- fecha_creacion, eliminada.

-- ── PASO B1: función angosta — radar de seguimientos ──
-- Solo expone lo mínimo para que el brief calcule antigüedad y detecte
-- ballenas (monto alto): cliente, total_alto, fecha_creacion. Nada de
-- teléfono, email, ni historial de conversación.
create or replace function public.brief_seguimientos_radar()
returns table(cliente text, total_alto numeric, fecha_creacion timestamptz)
language sql
security definer
set search_path = public
as $$
  select c.cliente, c.total_alto, c.fecha_creacion
  from cotizaciones c
  where coalesce(c.eliminada, false) = false
    and coalesce(c.estado, 'enviada') = 'enviada'
  order by c.fecha_creacion asc;
$$;

grant execute on function public.brief_seguimientos_radar() to anon;

-- ── verificación B1 ──
--   curl "$SB_URL/rest/v1/rpc/brief_seguimientos_radar" \
--     -H "apikey: $SB_ANON" -H "Authorization: Bearer $SB_ANON"

-- ══════════════════════════════════════════════════════════════
-- Después de correr A2 y B1 (y confirmar que devuelven filas con el
-- anon key), avísame para actualizar la rutina del brief matinal para
-- que llame a estas funciones en vez de a las tablas directo.
-- ══════════════════════════════════════════════════════════════
