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

-- Casa Zaru: de qué anuncio o sitio llegó cada cotización (04-10-2026)
-- Pegar en Supabase → SQL Editor → Run
--
-- Lo llena el cotizador público al guardar (origenCapturar → saveQuote):
--   utm_source, utm_medium, utm_campaign, utm_content, utm_term,
--   gclid / gbraid / wbraid (Google), fbclid (Meta), src, prod,
--   ref (sitio desde el que llegó), fecha, y "anterior" = último clic en un
--   anuncio de los 90 días previos cuando la visita de hoy llegó sin anuncio.
-- Null en cotizaciones de vendedores y en todo lo anterior a esta fecha.
--
-- El front no depende de esto: si la columna falta, guarda la cotización sin
-- origen. Pero hasta correr este archivo no se registra nada.

alter table cotizaciones
  add column if not exists origen jsonb;

comment on column cotizaciones.origen is 'De dónde llegó el cliente (UTMs, gclid/fbclid, sitio de referencia); null si la creó un vendedor';
