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

-- Casa Zaru: canal de venta (P&L) + descuento B2B de Jepe
-- Pegar en Supabase → SQL Editor → Run

alter table cotizaciones
  add column if not exists canal    text,      -- web / cesar / jepe (se llena al marcar Ganada)
  add column if not exists b2b_dcto numeric;   -- % extra Casa Zaru Profesionales (solo cotizaciones de Jepe)

comment on column cotizaciones.canal    is 'Canal de la venta al concretar: web / cesar / jepe (para el P&L)';
comment on column cotizaciones.b2b_dcto is 'Descuento Casa Zaru Profesionales aplicado por Jepe (%), null si no aplica';
