-- ══════════════════════════════════════════════════════════════════
-- EMBUDO: paso "medidas" (el cliente puso medidas y vio el precio estimado)
--
-- Proyecto: cmxqorsyxoltrakxawro («ZARU · Cotizador»). NO es la Gestión.
-- Correr en el SQL Editor de ese proyecto. Idempotente.
--
-- Separa a los que se van SIN escribir medidas de los que ven el precio
-- estimado y se van sin dejar sus datos. Mientras no corra, el cotizador
-- intenta registrar el paso y la base lo rechaza en silencio: no rompe nada,
-- solo no se mide.
-- ══════════════════════════════════════════════════════════════════

alter table public.embudo_eventos
  drop constraint if exists embudo_eventos_paso_check;

alter table public.embudo_eventos
  add constraint embudo_eventos_paso_check
  check (paso in ('visita','producto','medidas','datos','cotizacion'));
