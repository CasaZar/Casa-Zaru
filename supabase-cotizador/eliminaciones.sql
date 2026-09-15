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

-- Casa Zaru: borrado suave de cotizaciones (con motivo y responsable)
-- Pegar en Supabase → SQL Editor → Run

alter table cotizaciones
  add column if not exists eliminada  boolean default false,
  add column if not exists elim_motivo text,
  add column if not exists elim_por    text,
  add column if not exists elim_fecha  timestamptz;

comment on column cotizaciones.eliminada  is 'true = archivada/eliminada (no se muestra en el panel normal)';
comment on column cotizaciones.elim_motivo is 'Motivo que indicó quien la eliminó';
comment on column cotizaciones.elim_por    is 'Nombre del vendedor/admin que la eliminó';
comment on column cotizaciones.elim_fecha  is 'Cuándo se eliminó';
