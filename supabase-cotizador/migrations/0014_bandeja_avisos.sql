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
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '0011') then
    raise exception 'FALTA LA 0011: aplicar antes 0011_bandeja_freno_persona.sql. No se aplicó nada.';
  end if;
  if not exists (select 1 from pg_extension where extname = 'pg_cron')
     or not exists (select 1 from pg_extension where extname = 'pg_net') then
    raise exception 'FALTAN pg_cron / pg_net (migración 0009). No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- 0014 · COTIZADOR · Bandeja: avisos al equipo cuando un cliente escribe (25-11-2026)
--
-- Por qué: el 23-11 Jose respondió en la bandeja y nadie lo vio; su ventana de 24 horas se
-- cerró con el borrador listo. La bandeja no avisaba. Boceto aprobado por el dueño el 25-11
-- (.claude/boceto-bandeja-avisos.html).
--
--   mensajes_push      un dispositivo (navegador) que aceptó recibir notificaciones. Lo escribe SOLO la
--                      función (ruta /push, con la sesión del panel). Sin policies: nadie la lee desde
--                      el navegador.
--   mensajes_avisos    registro de cada aviso que se mandó. Un aviso por (mensaje, tipo): esa pareja
--                      es unique, así que el mismo aviso no sale dos veces aunque la función se llame
--                      dos veces a la vez.
--   mensajes_en_horario()            lunes a viernes 9:00-17:30 y sábado 10:00-14:00, hora de Chile.
--   mensajes_avisos_por_enviar()     qué avisos tocan ahora. Toda la regla vive aquí:
--        nuevo    un cliente escribió y nadie le ha respondido (uno por «espera», no uno por mensaje).
--                 No aplica si su respuesta automática está agendada (chats de prueba).
--        espera   lleva 2 horas sin respuesta. Solo sale dentro del horario: lo que llegó de noche
--                 avisa a las 9:00.
--        cierra   quedan 3 horas o menos para que se cierre la ventana de 24 horas. Sale a cualquier hora.
--   cron bandeja-avisos               cada minuto, y solo si hay algo que avisar, llama a la función
--                                     (ruta /avisos). Igual que /despachar: no recibe datos ni lleva llave,
--                                     y solo puede mandar lo que esta función dice que toca.
--
-- Qué viaja en la notificación: nombre de pila y hasta 90 caracteres del mensaje, cifrado de punta
-- a punta para ese navegador (RFC 8291); el servicio de notificaciones no puede leerlo.
-- Para apagarlo sin tocar la función:  select cron.unschedule('bandeja-avisos');
-- Idempotente. Rollback al final.
--
-- SIN APLICAR.
-- ══════════════════════════════════════════════════════════════════════════

create table if not exists public.mensajes_push (
  id             bigint generated always as identity primary key,
  usuario        text not null check (usuario = lower(usuario) and usuario like '%_@_%'),
  endpoint       text not null check (endpoint like 'https://%' and length(endpoint) <= 1000),
  p256dh         text not null check (length(p256dh) between 80 and 100),
  auth           text not null check (length(auth) between 16 and 40),
  recordatorios  boolean not null default true,
  fuera_horario  boolean not null default false,
  dispositivo    text check (dispositivo is null or length(dispositivo) <= 200),
  fallos         smallint not null default 0 check (fallos >= 0),
  ultimo_ok_at   timestamptz,
  deleted_at     timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  updated_by     text not null default coalesce(auth.jwt() ->> 'email', 'mensajes-webhook'),
  constraint mensajes_push_endpoint_uk unique (endpoint)
);
comment on table public.mensajes_push is
  'Dispositivos que reciben los avisos de la bandeja (web push). Solo la función mensajes-webhook la lee y escribe.';

create table if not exists public.mensajes_avisos (
  id          bigint generated always as identity primary key,
  tipo        text not null check (tipo in ('nuevo', 'espera', 'cierra', 'prueba')),
  chat_id     bigint references public.mensajes_chats (id),
  mensaje_id  bigint references public.mensajes (id),
  usuario     text,
  destinos    smallint not null default 0 check (destinos >= 0),
  entregados  smallint not null default 0 check (entregados >= 0),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  updated_by  text not null default coalesce(auth.jwt() ->> 'email', 'mensajes-webhook'),
  constraint mensajes_avisos_forma check (
    (tipo = 'prueba' and mensaje_id is null and usuario is not null)
    or (tipo <> 'prueba' and mensaje_id is not null and chat_id is not null)),
  constraint mensajes_avisos_uno unique (mensaje_id, tipo)
);
comment on table public.mensajes_avisos is
  'Registro de avisos enviados al equipo. unique (mensaje_id, tipo): el mismo aviso no sale dos veces.';
create index if not exists mensajes_avisos_chat_idx on public.mensajes_avisos (chat_id, created_at);

drop trigger if exists tr_mensajes_push_sellar on public.mensajes_push;
create trigger tr_mensajes_push_sellar before update on public.mensajes_push
  for each row execute function public.mensajes_sellar();
drop trigger if exists tr_mensajes_push_hist on public.mensajes_push;
create trigger tr_mensajes_push_hist after update or delete on public.mensajes_push
  for each row execute function public.mensajes_historial_guardar();
drop trigger if exists tr_mensajes_avisos_sellar on public.mensajes_avisos;
create trigger tr_mensajes_avisos_sellar before update on public.mensajes_avisos
  for each row execute function public.mensajes_sellar();

alter table public.mensajes_push   enable row level security;
alter table public.mensajes_push   force  row level security;
alter table public.mensajes_avisos enable row level security;
alter table public.mensajes_avisos force  row level security;

-- mensajes_push: sin policies a propósito (solo la llave de servicio, desde la función).
-- mensajes_avisos: el equipo de la bandeja puede leer el registro; nadie escribe desde el navegador.
drop policy if exists mensajes_avisos_leer on public.mensajes_avisos;
create policy mensajes_avisos_leer on public.mensajes_avisos
  for select to authenticated using (public.mensajes_puede_leer());

revoke all on public.mensajes_push, public.mensajes_avisos from public, anon, authenticated;
grant select on public.mensajes_avisos to authenticated;
grant select, insert, update on public.mensajes_push, public.mensajes_avisos to service_role;

-- Horario de atención, hora de Chile (turno de César). Los feriados no se consideran.
create or replace function public.mensajes_en_horario(p timestamptz default now())
returns boolean language sql stable set search_path = public as $$
  select case extract(isodow from l)::int
           when 7 then false
           when 6 then l::time >= time '10:00' and l::time < time '14:00'
           else        l::time >= time '09:00' and l::time < time '17:30'
         end
    from (select p at time zone 'America/Santiago' as l) x;
$$;
revoke all on function public.mensajes_en_horario(timestamptz) from public, anon, authenticated;
grant execute on function public.mensajes_en_horario(timestamptz) to service_role;

-- Qué avisos tocan en este momento. p_ahora existe para poder probar la regla con horas simuladas.
create or replace function public.mensajes_avisos_por_enviar(p_ahora timestamptz default now())
returns table (tipo text, chat_id bigint, mensaje_id bigint, nombre text, texto text,
               en_horario boolean, desde timestamptz, cierra_at timestamptz)
language sql stable security definer set search_path = public as $$
  with base as (
    -- chats con la ventana de 24 horas abierta y sin una respuesta automática agendada
    select c.id as chat_id, c.nombre, c.ultimo_entrante_at,
           (select max(m.id) from public.mensajes m
             where m.chat_id = c.id and m.direccion = 'saliente') as ult_saliente
      from public.mensajes_chats c
     where c.deleted_at is null
       and c.estado <> 'cerrado'
       and c.ultimo_entrante_at is not null
       and c.ultimo_entrante_at > p_ahora - interval '24 hours'
       and c.ultimo_entrante_at <= p_ahora
       and not exists (select 1 from public.mensajes_borradores b
                        where b.chat_id = c.id and b.estado = 'pendiente' and b.auto_desde is not null)
  ), espera as (
    -- la «espera»: los mensajes del cliente posteriores a nuestra última respuesta
    select b.*,
           (select min(m.id) from public.mensajes m
             where m.chat_id = b.chat_id and m.autor = 'cliente' and m.id > coalesce(b.ult_saliente, 0)) as primero,
           (select max(m.id) from public.mensajes m
             where m.chat_id = b.chat_id and m.autor = 'cliente' and m.id > coalesce(b.ult_saliente, 0)) as ultimo
      from base b
  ), e as (
    select x.chat_id, x.primero, x.ultimo, x.ultimo_entrante_at,
           coalesce(nullif(split_part(btrim(coalesce(x.nombre, '')), ' ', 1), ''), 'Un cliente') as nombre,
           left(coalesce(nullif(btrim(m2.texto), ''), '[' || coalesce(m2.tipo, 'mensaje') || ']'), 90) as texto,
           m1.enviado_at as desde,
           public.mensajes_en_horario(p_ahora) as en_horario
      from espera x
      join public.mensajes m1 on m1.id = x.primero
      join public.mensajes m2 on m2.id = x.ultimo
  )
  -- nuevo: apenas hay borrador (o pasados 90 segundos, para los mensajes que no generan borrador)
  select 'nuevo'::text, e.chat_id, e.primero, e.nombre, e.texto, e.en_horario, e.desde,
         e.ultimo_entrante_at + interval '24 hours'
    from e
   where (e.desde <= p_ahora - interval '90 seconds'
          or exists (select 1 from public.mensajes_borradores b
                      where b.chat_id = e.chat_id and b.mensaje_id >= e.primero))
     and not exists (select 1 from public.mensajes_avisos a where a.mensaje_id = e.primero and a.tipo = 'nuevo')
  union all
  -- espera: 2 horas sin respuesta, solo dentro del horario
  select 'espera'::text, e.chat_id, e.primero, e.nombre, e.texto, e.en_horario, e.desde,
         e.ultimo_entrante_at + interval '24 hours'
    from e
   where e.en_horario
     and e.desde <= p_ahora - interval '2 hours'
     and not exists (select 1 from public.mensajes_avisos a where a.mensaje_id = e.primero and a.tipo = 'espera')
  union all
  -- cierra: quedan 3 horas o menos de ventana (se cuenta desde el último mensaje del cliente)
  select 'cierra'::text, e.chat_id, e.ultimo, e.nombre, e.texto, e.en_horario, e.desde,
         e.ultimo_entrante_at + interval '24 hours'
    from e
   where e.ultimo_entrante_at + interval '24 hours' - p_ahora <= interval '3 hours'
     and not exists (select 1 from public.mensajes_avisos a where a.mensaje_id = e.ultimo and a.tipo = 'cierra');
$$;
revoke all on function public.mensajes_avisos_por_enviar(timestamptz) from public, anon, authenticated;
grant execute on function public.mensajes_avisos_por_enviar(timestamptz) to service_role;

-- La tarea: cada minuto, y solo si hay algo que avisar, un POST a la función.
do $tarea$
begin
  if exists (select 1 from cron.job where jobname = 'bandeja-avisos') then
    perform cron.unschedule('bandeja-avisos');
  end if;
  perform cron.schedule('bandeja-avisos', '* * * * *', $job$
    select net.http_post(
      url := 'https://cmxqorsyxoltrakxawro.supabase.co/functions/v1/mensajes-webhook/avisos',
      body := '{}'::jsonb,
      headers := '{"Content-Type": "application/json"}'::jsonb,
      timeout_milliseconds := 20000
    )
    where exists (select 1 from public.mensajes_avisos_por_enviar());
  $job$);
end
$tarea$;

-- Registro
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('0014', 'bandeja_avisos', array[
  'create table mensajes_push (dispositivos con notificaciones; RLS + FORCE, sin policies);',
  'create table mensajes_avisos (registro de avisos; unique (mensaje_id, tipo); select para el equipo);',
  'create function mensajes_en_horario(timestamptz), mensajes_avisos_por_enviar(timestamptz);',
  'cron bandeja-avisos: cada minuto, si hay un aviso que toca, POST a mensajes-webhook/avisos.'
])
on conflict (version) do nothing;

-- Verificación. Debe dar: tablas 2 · rls 2 · policies_push 0 · policies_avisos 1 · funciones 2 ·
-- tarea 1 · activa true · anon_lee false · registrada 1.
select
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname in ('mensajes_push', 'mensajes_avisos'))                         as tablas,
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname in ('mensajes_push', 'mensajes_avisos')
      and c.relrowsecurity and c.relforcerowsecurity)                                                          as rls,
  (select count(*) from pg_policies where schemaname = 'public' and tablename = 'mensajes_push')               as policies_push,
  (select count(*) from pg_policies where schemaname = 'public' and tablename = 'mensajes_avisos')             as policies_avisos,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('mensajes_en_horario', 'mensajes_avisos_por_enviar'))         as funciones,
  (select count(*) from cron.job where jobname = 'bandeja-avisos')                                             as tarea,
  (select bool_and(active) from cron.job where jobname = 'bandeja-avisos')                                     as activa,
  (select has_table_privilege('anon', 'public.mensajes_push', 'select')
       or has_table_privilege('authenticated', 'public.mensajes_push', 'select'))                              as anon_lee,
  (select count(*) from supabase_migrations.schema_migrations where version = '0014')                          as registrada;

-- Rollback (NO correr junto con lo de arriba):
--   select cron.unschedule('bandeja-avisos');
--   drop function public.mensajes_avisos_por_enviar(timestamptz);
--   drop function public.mensajes_en_horario(timestamptz);
--   drop table public.mensajes_avisos;
--   drop table public.mensajes_push;     -- antes, respaldar sus filas si hay dispositivos inscritos
--   delete from supabase_migrations.schema_migrations where version = '0014';
