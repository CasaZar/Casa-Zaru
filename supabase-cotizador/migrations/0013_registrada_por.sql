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
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '0012') then
    raise exception 'FALTA LA 0012: aplicar antes 0012_whatsapp_canales.sql. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- 0013 · COTIZADOR · Cotizaciones registradas por el asistente (Claude) (24-11-2026)
--
-- Pedido del dueño: las cotizaciones que registra Claude al revisar WhatsApp e
-- Instagram se guardan con la cuenta hola@, la misma por la que entran las del link
-- de César, y no se podían separar. Boceto aprobado el 24-11 («Sí, constrúyelo»).
--
-- Cambios:
--   · cotizaciones.registrada_por: null (todas las de siempre) o 'claude'. El valor es
--     'claude' y no 'asistente' para no confundirlo con el asistente de la bandeja
--     (0008, links ?src=asistente), que es otra cosa. En pantalla dice «asistente».
--   · Solo la cuenta hola@ puede marcarla. Un insert público (anon) o de otro usuario
--     que traiga registrada_por la pierde en silencio (la cotización se guarda igual),
--     y nadie más puede cambiarla después.
--   · Se marcan las 6 que Claude ya registró: CL-1126-258, 270, 271, 272, 273 y 275.
-- No cambia de quién es la cotización: user_email sigue siendo hola@ y el panel se la
-- sigue dando a César para el seguimiento. Mismas políticas de lectura y escritura.
--
-- Idempotente. Rollback al final.
-- ══════════════════════════════════════════════════════════════════════════

-- 1) columna
alter table public.cotizaciones add column if not exists registrada_por text;

do $c$
begin
  if not exists (select 1 from pg_constraint where conname = 'cotizaciones_registrada_por_chk') then
    alter table public.cotizaciones
      add constraint cotizaciones_registrada_por_chk check (registrada_por is null or registrada_por = 'claude');
  end if;
end
$c$;

-- 2) candado: solo hola@ la pone (o el dueño de la base, que es quien corre las migraciones)
create or replace function public.cotizaciones_registrada_por_guardia()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if coalesce(auth.jwt() ->> 'email', '') = 'hola@casazaru.cl'
     or current_user in ('postgres', 'supabase_admin') then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.registrada_por := null;
  else
    new.registrada_por := old.registrada_por;
  end if;
  return new;
end $$;

drop trigger if exists tr_cotizaciones_registrada_por on public.cotizaciones;
create trigger tr_cotizaciones_registrada_por
  before insert or update of registrada_por on public.cotizaciones
  for each row execute function public.cotizaciones_registrada_por_guardia();

-- 3) las que Claude ya registró
update public.cotizaciones
   set registrada_por = 'claude'
 where numero in ('N° CL-1126-258', 'N° CL-1126-270', 'N° CL-1126-271',
                  'N° CL-1126-272', 'N° CL-1126-273', 'N° CL-1126-275')
   and registrada_por is distinct from 'claude';

-- 4) registro
insert into supabase_migrations.schema_migrations (version, name, statements)
select '0013', 'registrada_por', array['ver supabase-cotizador/migrations/0013_registrada_por.sql']
where not exists (select 1 from supabase_migrations.schema_migrations where version = '0013');

-- 5) verificación (debe dar: columna 1, check 1, trigger 1, marcadas 6, registrada 1)
select
  (select count(*) from information_schema.columns where table_name = 'cotizaciones' and column_name = 'registrada_por') as columna,
  (select count(*) from pg_constraint where conname = 'cotizaciones_registrada_por_chk') as check_valor,
  (select count(*) from pg_trigger where tgname = 'tr_cotizaciones_registrada_por') as trigger_guardia,
  (select count(*) from public.cotizaciones where registrada_por = 'claude') as marcadas,
  (select count(*) from supabase_migrations.schema_migrations where version = '0013') as registrada;

-- ── ROLLBACK (a mano, solo si hace falta; se pierde la marca de las cotizaciones) ──
-- drop trigger if exists tr_cotizaciones_registrada_por on public.cotizaciones;
-- drop function if exists public.cotizaciones_registrada_por_guardia();
-- alter table public.cotizaciones drop constraint if exists cotizaciones_registrada_por_chk;
-- alter table public.cotizaciones drop column if exists registrada_por;
-- delete from supabase_migrations.schema_migrations where version = '0013';
