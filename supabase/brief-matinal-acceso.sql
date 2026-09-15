-- ── CANDADO DE PROYECTO (no borrar) ──────────────────────────────────────
-- Este archivo es de GESTIÓN (padnttpgzuotxeipjrry). Si se pega en el SQL
-- Editor de otro proyecto, este bloque falla primero y Postgres descarta el
-- resto del script: no se aplica nada.
do $candado$
begin
  if to_regclass('public.gestion_pedidos') is null then
    raise exception 'PROYECTO EQUIVOCADO: este SQL es de GESTIÓN (padnttpgzuotxeipjrry) y aquí no existe gestion_pedidos. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════
-- Casa Zaru · Acceso acotado para el brief matinal — mitad GESTIÓN
--
-- Este archivo era uno solo con dos bloques para dos proyectos distintos
-- (15-09-2026 se partió): correrlo entero en cualquiera de los dos fallaba a
-- medias. La otra mitad, la del Cotizador, está en
-- supabase-cotizador/brief-matinal-acceso.sql.
--
-- El brief matinal corre como agente en la nube sin sesión: solo tiene la API
-- key pública (anon), que por RLS no puede leer las tablas. Se exponen
-- funciones angostas (SECURITY DEFINER) con los campos mínimos; nada de
-- Finanzas, Costos ni datos de pago.
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
