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
-- EMBUDO: paso "whatsapp" (el cliente tocó "Quiero esta cubierta" en su
-- cotización y se le abrió WhatsApp con el mensaje armado). 06-10-2026.
--
-- Proyecto: cmxqorsyxoltrakxawro («ZARU · Cotizador»). NO es la Gestión.
-- Correr en el SQL Editor de ese proyecto. Idempotente.
--
-- Es el objetivo de la cotización y hasta ahora no se medía: sin este paso no
-- se sabe si mover el botón bajo los precios (revisión UX del 06-10) sirvió.
-- Mientras no corra, el cotizador intenta registrarlo y la base lo rechaza en
-- silencio: no rompe nada, solo no se mide.
-- ══════════════════════════════════════════════════════════════════

alter table public.embudo_eventos
  drop constraint if exists embudo_eventos_paso_check;

alter table public.embudo_eventos
  add constraint embudo_eventos_paso_check
  check (paso in ('visita','producto','medidas','datos','cotizacion','whatsapp'));
