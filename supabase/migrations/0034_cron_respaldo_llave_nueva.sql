-- ── CANDADO DE PROYECTO (no borrar) ──────────────────────────────────────
-- Este archivo es de GESTIÓN (padnttpgzuotxeipjrry). Si se pega en el SQL
-- Editor de otro proyecto, este bloque falla primero y Postgres descarta el
-- resto del script: no se aplica nada.
do $candado$
begin
  if to_regclass('public.gestion_pedidos') is null then
    raise exception 'PROYECTO EQUIVOCADO: este SQL es de GESTIÓN (padnttpgzuotxeipjrry) y aquí no existe gestion_pedidos. No se aplicó nada.';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '0033') then
    raise exception 'FALTA LA 0033 en schema_migrations: revisar el orden antes de seguir. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- 0034 · El cron del respaldo deja de usar la llave anon antigua (17-11-2026)
--
-- Parte de P069: la service_role de Gestión se filtró por chat el 09-08 y la
-- única forma de anularla es apagar las llaves antiguas de formato JWT
-- (Settings → API Keys → «Disable JWT-based API keys»). Los dos crons del
-- respaldo (gestion-respaldo-diario y gestion-respaldo-tarde) llaman a la
-- función con «Authorization: Bearer <anon antigua>»; con las llaves antiguas
-- apagadas, esa llamada se rechazaría y el respaldo dejaría de correr.
--
-- Cambio: ese header se reemplaza por «apikey: sb_publishable_…» (la llave
-- pública nueva, que ya está en index.html). La puerta de la función sigue
-- siendo el secreto del cuerpo, que NO se toca.
--
-- ANTES DE CORRER ESTO: en el panel, Edge Functions → gestion-respaldo-v2 →
-- apagar «Verify JWT» (la llave nueva no es un JWT). Si no, el respaldo de la
-- noche falla con 401. Después: probar con una corrida manual (abajo).
--
-- Respaldo: los comandos actuales (traen el secreto) se copian a
-- respaldos.cron_job_0034, en un esquema sin acceso por la API.
-- No cambia ninguna fila de negocio. Idempotente. Rollback al final.
-- ══════════════════════════════════════════════════════════════════════════

create schema if not exists respaldos;
revoke all on schema respaldos from public, anon, authenticated;

create table if not exists respaldos.cron_job_0034 as
  select jobid, jobname, command, now() as copiado from cron.job
  where jobname in ('gestion-respaldo-diario', 'gestion-respaldo-tarde');
revoke all on respaldos.cron_job_0034 from public, anon, authenticated;

do $m0034$
declare r record;
begin
  for r in select jobid, command from cron.job
           where jobname in ('gestion-respaldo-diario', 'gestion-respaldo-tarde')
             and command ~ '"Authorization"\s*:\s*"Bearer eyJ' loop
    perform cron.alter_job(r.jobid, command := regexp_replace(r.command,
      '"Authorization"\s*:\s*"Bearer eyJ[A-Za-z0-9_.-]+"',
      '"apikey":"sb_publishable_XeCtx06OFHQ3LsYxYk5NTA_kkWHlJHG"'));
  end loop;
end
$m0034$;

-- Registro
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('0034', 'cron_respaldo_llave_nueva', array[
  'cron gestion-respaldo-*: header Authorization Bearer <anon JWT> -> apikey sb_publishable (respaldo en respaldos.cron_job_0034)'
])
on conflict (version) do nothing;

-- Verificación: con_jwt = 0, con_llave_nueva = 2, respaldados = 2, última 0034.
select
  (select count(*) from cron.job where jobname like 'gestion-respaldo-%' and command ~ 'eyJ')            as con_jwt,
  (select count(*) from cron.job where jobname like 'gestion-respaldo-%' and command ~ 'sb_publishable_') as con_llave_nueva,
  (select count(*) from respaldos.cron_job_0034)                                                       as respaldados,
  (select max(version) from supabase_migrations.schema_migrations)                                     as ultima_migracion;

-- Prueba manual (correr aparte, DESPUÉS de lo de arriba): dispara el respaldo
-- con el comando ya cambiado. A los ~2 minutos tiene que aparecer el JSON de hoy
-- en Drive (Respaldos Gestion) con hora nueva.
--   do $p$ declare c text; begin
--     select command into c from cron.job where jobname = 'gestion-respaldo-tarde';
--     execute c;
--   end $p$;

-- ── ROLLBACK (no correr junto con lo de arriba) ──────────────────────────
-- Devuelve los comandos exactos de antes desde el respaldo:
-- do $r$ declare r record; begin
--   for r in select jobid, command from respaldos.cron_job_0034 loop
--     perform cron.alter_job(r.jobid, command := r.command);
--   end loop;
-- end $r$;
-- delete from supabase_migrations.schema_migrations where version = '0034';
-- (Y volver a prender «Verify JWT» en gestion-respaldo-v2 si se quiere.)
