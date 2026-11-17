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

-- ══════════════════════════════════════════════════════════════════
-- EMBUDO: paso "wa_tienda" (17-11-2026). Alguien tocó un botón de WhatsApp
-- (el 5558) en casazaru.cl. Lo registra el snippet cz-origen del tema de
-- Shopify, con canal 'tienda' y la fuente del anuncio si vino de uno.
--
-- Para qué: el mensaje prellenado lleva un código de origen, (GB), (GS), (G)
-- o (M), y el cliente lo puede borrar. Con este registro el cruce de «Mi día»
-- igual puede emparejar un chat nuevo con el clic de anuncio de un minuto
-- antes. Además cuenta cuántos de cada anuncio llegan a escribir.
-- No guarda datos personales: sesión al azar, página, fuente y campaña.
--
-- Paso aparte (no 'whatsapp') a propósito: 'whatsapp' es el botón de la
-- cotización y lo cuentan el análisis y el Pulso del cotizador; mezclarlos
-- inflaría ese embudo.
--
-- Proyecto: cmxqorsyxoltrakxawro («ZARU · Cotizador»). Idempotente.
-- Mientras no corra, la base rechaza el insert en silencio: el link de
-- WhatsApp y su código funcionan igual, solo no queda el registro.
--
-- Rollback (vuelve a la lista anterior sin borrar nada: NOT VALID deja las
-- filas 'wa_tienda' que ya existan y solo rechaza las nuevas):
--   alter table public.embudo_eventos drop constraint if exists embudo_eventos_paso_check;
--   alter table public.embudo_eventos add constraint embudo_eventos_paso_check
--     check (paso in ('visita','producto','medidas','datos','cotizacion',
--                     'whatsapp','duda','muestrario')) not valid;
-- ══════════════════════════════════════════════════════════════════

alter table public.embudo_eventos
  drop constraint if exists embudo_eventos_paso_check;

alter table public.embudo_eventos
  add constraint embudo_eventos_paso_check
  check (paso in ('visita','producto','medidas','datos','cotizacion',
                  'whatsapp','duda','muestrario','wa_tienda'));

-- Verificación: debe aparecer 'wa_tienda' en la definición.
select pg_get_constraintdef(oid)
from pg_constraint
where conrelid = 'public.embudo_eventos'::regclass
  and conname = 'embudo_eventos_paso_check';
