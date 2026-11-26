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
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '0015') then
    raise exception 'FALTA LA 0015: aplicar antes 0015_prueba_datos.sql. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- 0016 · COTIZADOR · Paso «modelo» en el embudo (26-11-2026)
-- SIN APLICAR.
--
-- En puertas, 125 sesiones entraron y 36 vieron un precio (14-09 al 25-11-2026),
-- pero no se sabe si la gente se va sin elegir modelo o después de elegirlo:
-- el paso «producto» se registra al abrir la pantalla y «medidas» recién cuando
-- hay precio. El front público (26-11-2026) ya manda paso = 'modelo' al tocar
-- un modelo de puerta; mientras esto no se aplique, el check rechaza ese evento
-- y el navegador lo ignora (no afecta al resto del embudo).
--
-- Cambio: se agrega 'modelo' a embudo_eventos_paso_check. Nada más.
-- Idempotente. Rollback al final.
-- ══════════════════════════════════════════════════════════════════════════

alter table public.embudo_eventos drop constraint if exists embudo_eventos_paso_check;
alter table public.embudo_eventos
  add constraint embudo_eventos_paso_check check (paso = any (array[
    'visita', 'producto', 'medidas', 'datos', 'cotizacion',
    'whatsapp', 'duda', 'muestrario', 'wa_tienda', 'datos_foco', 'modelo']));

insert into supabase_migrations.schema_migrations (version, name, statements)
select '0016', 'embudo_paso_modelo', array['ver supabase-cotizador/migrations/0016_embudo_paso_modelo.sql']
where not exists (select 1 from supabase_migrations.schema_migrations where version = '0016');

-- verificación (debe dar: paso_nuevo 1, registrada 1)
select
  (select count(*) from pg_constraint where conname = 'embudo_eventos_paso_check' and pg_get_constraintdef(oid) like '%modelo%') as paso_nuevo,
  (select count(*) from supabase_migrations.schema_migrations where version = '0016') as registrada;

-- ── ROLLBACK (a mano, solo si hace falta; se pierden los eventos «modelo») ──
-- delete from public.embudo_eventos where paso = 'modelo';
-- alter table public.embudo_eventos drop constraint if exists embudo_eventos_paso_check;
-- alter table public.embudo_eventos add constraint embudo_eventos_paso_check check (paso = any (array['visita','producto','medidas','datos','cotizacion','whatsapp','duda','muestrario','wa_tienda','datos_foco']));
-- delete from supabase_migrations.schema_migrations where version = '0016';
