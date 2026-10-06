-- ── CANDADO DE PROYECTO (no borrar) ──────────────────────────────────────
-- Este archivo es de GESTIÓN (padnttpgzuotxeipjrry). Si se pega en el SQL
-- Editor de otro proyecto, este bloque falla primero y Postgres descarta el
-- resto del script: no se aplica nada.
do $candado$
begin
  if to_regclass('public.gestion_pedidos') is null then
    raise exception 'PROYECTO EQUIVOCADO: este SQL es de GESTIÓN (padnttpgzuotxeipjrry) y aquí no existe gestion_pedidos. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════
-- Casa Zaru · Segundo respaldo del día (en la tarde)
--
-- El respaldo diario (cron `gestion-respaldo-diario`, 06:00 UTC = 03:00 en
-- Chile) deja `respaldo-gestion-AAAA-MM-DD.json` en Drive. Lo que se corrige en
-- el día recién aparece en el respaldo de la madrugada siguiente, y lo que se
-- pierde entre medio no tiene copia.
--
-- Este job llama a la MISMA función con el MISMO comando, a las 21:00 UTC
-- (18:00 en Chile en horario de verano, 17:00 en invierno). Como el nombre del
-- archivo lleva solo la fecha, el Apps Script reemplaza el de la madrugada de
-- ese día (el anterior queda en la papelera de Drive): sigue habiendo un
-- archivo por día, la retención de 30 sigue cubriendo 30 días y los scripts que
-- leen el respaldo no cambian.
--
-- El comando se COPIA del job existente para no escribir el secreto en este
-- archivo (el repo es público). Correrlo de nuevo no duplica nada: cron.schedule
-- con un nombre que ya existe actualiza ese job.
-- ══════════════════════════════════════════════════════════════

do $$
declare
  cmd text;
begin
  select command into cmd from cron.job where jobname = 'gestion-respaldo-diario';
  if cmd is null then
    raise exception 'No existe el job gestion-respaldo-diario: no se creó nada.';
  end if;

  perform cron.schedule('gestion-respaldo-tarde', '0 21 * * *', cmd);

  -- Además, un respaldo ahora mismo, para no esperar a la tarde ni a la madrugada.
  execute cmd;
end
$$;

-- Verificación (sin mostrar el comando, que lleva el secreto).
select jobid, jobname, schedule, active
from cron.job
where jobname like 'gestion-respaldo%'
order by jobid;
