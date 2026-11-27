-- ── CANDADO DE PROYECTO (no borrar) ──────────────────────────────────────
-- Este archivo es del COTIZADOR (cmxqorsyxoltrakxawro). Si se pega en el SQL
-- Editor de otro proyecto, este bloque falla primero y Postgres descarta el
-- resto del script: no se aplica nada.
do $candado$
begin
  if to_regclass('public.gestion_pedidos') is not null then
    raise exception 'PROYECTO EQUIVOCADO: este SQL es del COTIZADOR (cmxqorsyxoltrakxawro) y lo estás corriendo en GESTIÓN. No se aplicó nada.';
  end if;
  if to_regclass('public.cotizaciones') is null then
    raise exception 'PROYECTO EQUIVOCADO: este SQL es del COTIZADOR (cmxqorsyxoltrakxawro) y aquí no existe la tabla cotizaciones. No se aplicó nada.';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '0018') then
    raise exception 'FALTA LA 0018: aplicar antes 0018_bandeja_soltar.sql. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- 0019 · COTIZADOR · Campañas: varias activas a la vez (27-11-2026)
--
-- La 0010 dejó un índice único que permitía UNA sola campaña activa. Para el
-- Black Friday (27 al 30-11) tiene que convivir con «Peldaños · ronda 2»
-- (hasta el 05-12). El panel ya pinta un bloque por campaña activa y un
-- cliente sale en una sola. Se quita el índice; la nota sigue siendo única
-- (es lo que une cada campaña con sus resultados) y los demás check siguen.
-- No toca filas. Idempotente. Rollback al final.
-- ══════════════════════════════════════════════════════════════════════════

drop index if exists public.campanas_una_activa;

-- Registro
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('0019', 'campanas_varias_activas', array[
  'drop index campanas_una_activa: puede haber varias campañas activas a la vez (Black Friday + peldaños ronda 2).'
])
on conflict (version) do nothing;

-- Verificación. Debe dar: indice_unico 0 · registrada 1.
select
  (select count(*) from pg_indexes where schemaname = 'public' and indexname = 'campanas_una_activa') as indice_unico,
  (select count(*) from supabase_migrations.schema_migrations where version = '0019')               as registrada;

-- Rollback (NO correr junto con lo de arriba). Antes, dejar UNA sola activa:
--   create unique index if not exists campanas_una_activa
--     on public.campanas ((true)) where estado = 'activa' and deleted_at is null;
--   delete from supabase_migrations.schema_migrations where version = '0019';
