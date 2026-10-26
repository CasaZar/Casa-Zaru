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

-- ══════════════════════════════════════════════════════════════════════════
-- Casa Zaru · Respaldo diario del Cotizador desde Supabase (26-10-2026)
--
-- Dos crons llaman a la Edge Function `respaldo-cotizador` (ver
-- supabase-cotizador/functions/respaldo-cotizador/index.ts), que vuelca todas
-- las tablas a un zip en Drive («Respaldos Cotizador»):
--   respaldo-cotizador-diario   06:00 UTC = 03:00 en Chile
--   respaldo-cotizador-tarde    21:00 UTC = 18:00 (verano) / 17:00 (invierno)
-- El nombre del archivo lleva solo la fecha, así que el de la tarde reemplaza
-- al de la madrugada: un archivo por día.
--
-- Reemplaza la tarea de Windows del PC de la oficina, que dejó tres días sin
-- respaldo (23 al 25-10) porque el PC despertaba sin red o no despertaba.
--
-- EL SECRETO NO VA EN ESTE ARCHIVO (el repo es público). Antes de correrlo:
--   1. Reemplazar <<PEGAR_RESPALDO_SECRET>> por el mismo valor que se cargó
--      como RESPALDO_SECRET en Edge Functions → Secrets. Si se corre con el
--      marcador puesto, el bloque falla a propósito y no cambia nada.
--   2. El valor queda en Vault (`respaldo_cotizador_secret`); el comando del
--      cron lo lee de ahí en cada corrida, así `cron.job` tampoco lo muestra.
--
-- Idempotente: cron.schedule con un nombre que ya existe actualiza ese job, y
-- el secreto de Vault se actualiza si ya estaba.
--
-- En `net._http_response` las corridas pueden salir "Timeout of 5000 ms": es
-- NORMAL (igual que en Gestión), la función sigue y sube el archivo. Se
-- verifica por la hora del zip en Drive o por el campo `generado` del JSON.
--
-- Rollback:
--   select cron.unschedule('respaldo-cotizador-diario');
--   select cron.unschedule('respaldo-cotizador-tarde');
--   delete from vault.secrets where name = 'respaldo_cotizador_secret';
-- ══════════════════════════════════════════════════════════════════════════

create extension if not exists pg_cron;
create extension if not exists pg_net;

do $$
declare
  secreto text := '<<PEGAR_RESPALDO_SECRET>>';
  id_secreto uuid;
  cmd text;
begin
  if secreto like '<<%' or length(secreto) < 16 then
    raise exception 'Falta reemplazar <<PEGAR_RESPALDO_SECRET>> por el secreto real (el mismo RESPALDO_SECRET de la función). No se aplicó nada.';
  end if;

  select id into id_secreto from vault.secrets where name = 'respaldo_cotizador_secret';
  if id_secreto is null then
    perform vault.create_secret(secreto, 'respaldo_cotizador_secret',
      'Secreto que el cron manda a la Edge Function respaldo-cotizador');
  else
    perform vault.update_secret(id_secreto, secreto);
  end if;

  cmd := $cmd$
    select net.http_post(
      url     := 'https://cmxqorsyxoltrakxawro.supabase.co/functions/v1/respaldo-cotizador',
      headers := '{"Content-Type": "application/json"}'::jsonb,
      body    := jsonb_build_object('secret',
                   (select decrypted_secret from vault.decrypted_secrets where name = 'respaldo_cotizador_secret')),
      timeout_milliseconds := 5000)
  $cmd$;

  perform cron.schedule('respaldo-cotizador-diario', '0 6 * * *',  cmd);
  perform cron.schedule('respaldo-cotizador-tarde',  '0 21 * * *', cmd);

  -- Un respaldo ahora mismo, para no esperar a la tarde.
  execute cmd;
end
$$;

-- Verificación (el comando no muestra el secreto: lo lee de Vault).
select jobid, jobname, schedule, active
from cron.job
where jobname like 'respaldo-cotizador%'
order by jobid;
