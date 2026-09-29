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
-- Casa Zaru · LA COTIZACIÓN COMPARTIDA LLEVA SU FECHA ORIGINAL
--
-- Una cotización es una promesa con fecha. Hasta ahora el link compartido se
-- volvía a calcular al abrirlo: mostraba la fecha de HOY y renovaba solo sus
-- 10 días de validez, así que nunca vencía. La de Hugo Alonso, hecha el 15 de
-- septiembre, al abrirla el 29 decía "29 de septiembre".
--
-- Los links NUEVOS ya se guardan con su fecha adentro (campo `f` del JSON).
-- Los links VIEJOS no la tienen, pero la tabla sí: `created_at`. Esta función
-- se la agrega al vuelo como `_f`, así los que ya están enviados también
-- muestran su fecha real sin tocar ni una fila.
--
-- Solo reemplaza la función; no cambia tablas, políticas ni datos.
-- ══════════════════════════════════════════════════════════════

create or replace function get_quote_link(tok text)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select data || jsonb_build_object('_f', created_at)
  from quote_links
  where token = tok
  limit 1
$$;

grant execute on function get_quote_link(text) to anon;

-- Comprobación: debe traer `_f` con la fecha de creación del link.
-- select get_quote_link('yfjpee') -> '_f';
