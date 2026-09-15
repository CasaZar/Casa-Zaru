-- ── CANDADO DE PROYECTO (no borrar) ──────────────────────────────────────
-- Este archivo es del COTIZADOR (cmxqorsyxoltrakxawro). Si se pega en el SQL
-- Editor de otro proyecto, este bloque falla primero y Postgres descarta el
-- resto del script: no se aplica nada. Hace falta porque el proyecto de
-- Gestión TIENE tablas "cotizaciones" y "quote_links" (restos vacíos de junio)
-- y un alter sobre ellas pasaría ahí sin ningún error.
do $candado$
begin
  if to_regclass('public.gestion_pedidos') is not null then
    raise exception 'PROYECTO EQUIVOCADO: este SQL es del COTIZADOR (cmxqorsyxoltrakxawro) y lo estás corriendo en GESTIÓN. No se aplicó nada.';
  end if;
  if to_regclass('public.cotizaciones') is null then
    raise exception 'PROYECTO EQUIVOCADO: este SQL es del COTIZADOR (cmxqorsyxoltrakxawro) y aquí no existe la tabla cotizaciones. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════
-- Casa Zaru · Acceso acotado para el brief matinal — mitad COTIZADOR
--
-- Este archivo era uno solo con dos bloques para dos proyectos distintos
-- (15-09-2026 se partió): correrlo entero en cualquiera de los dos fallaba a
-- medias. La otra mitad, la de Gestión, está en
-- supabase/brief-matinal-acceso.sql.
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
