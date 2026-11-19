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
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '0003') then
    raise exception 'FALTA LA 0003: aplicar antes 0003_equipo_mi_dia.sql. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- 0004 · COTIZADOR · Bandeja de mensajes: WhatsApp (+56 9 9305 1122) + Instagram (18-11-2026)
--
-- Etapa 1 del boceto .claude/boceto-bandeja-mensajes.html (aprobado 18-11).
-- Los mensajes llegan por las APIs OFICIALES de Meta a la Edge Function
-- `mensajes-webhook`, que escribe aquí con la llave de servicio. Claude deja
-- un borrador por mensaje entrante; en la etapa 1 NADA se envía.
--
--   mensajes_chats        un chat por (canal, contacto). Estado y dueño.
--   mensajes              cada mensaje, entrante o saliente. meta_id único =
--                         el webhook es idempotente (Meta reintenta).
--   mensajes_borradores   lo que propone Claude, y qué se hizo con él.
--   mensajes_ejemplos     respuestas modelo / a evitar que alimentan los borradores.
--   mensajes_guia         la guía de respuestas por intención (manda la última fila).
--   mensajes_historial    versión anterior de toda fila que cambia o se borra.
--
-- El número de la bandeja es el +56 9 9305 1122 (el que dejó ManyChat), que no
-- está en ningún celular: se contesta desde la bandeja. Un chat se «toma» con
-- tomado_por (botón «Tomar chat», etapa 2) o, si algún día el número convive
-- con la app del celular, con un saliente de autor 'externo'.
--
-- Regla del usuario (18-11): «una vez que entra a contestar César o yo, no
-- respondas más esa conversación». Vive AQUÍ, no en el JS:
--   · un saliente con autor 'externo' (escrito desde el celular o la app, no
--     desde la bandeja) marca el chat como tomado, para siempre;
--   · en un chat tomado Claude SIGUE sugiriendo (pedido del usuario, 18-11:
--     «que se pueda seguir semiautomático, sugerirle los mensajes a César»),
--     pero el borrador queda marcado para='cesar' y solo lo ve él;
--   · la base rechaza todo mensaje AUTOMÁTICO en un chat tomado, y todo envío
--     desde la bandeja sin nombre de quién lo aprobó.
--
-- No toca ninguna tabla existente. Idempotente. Rollback al final.
--
-- APLICADA el 18-11-2026 en el SQL Editor del Cotizador (con ok del dueño).
-- Verificación: tablas 6, con_rls_force 6, policies 6, triggers 14, anon_algo 0,
-- auth_escribe 0, service_inserta 6, última 0004; confirmado aparte por el MCP.
-- Reglas probadas con supabase-cotizador/prueba-0004-reglas.sql: 11 de 11, y
-- las seis tablas quedaron vacías después de la prueba.
-- ══════════════════════════════════════════════════════════════════════════

create table if not exists public.mensajes_chats (
  id              bigint generated always as identity primary key,
  canal           text not null check (canal in ('whatsapp','instagram')),
  contacto_id     text not null check (length(contacto_id) between 3 and 64),   -- wa_id o IGSID
  nombre          text,
  telefono        text,
  estado          text not null default 'por_aprobar'
                  check (estado in ('por_aprobar','esperando','de_cesar','cerrado')),
  tomado_por      text,                         -- 'cesar' / correo; null = la bandeja lo lleva
  tomado_at       timestamptz,
  origen          jsonb,                        -- referral del anuncio (ad id, titular)
  ultimo_entrante_at timestamptz,               -- ventana de 24 h
  toques_sin_respuesta smallint not null default 0 check (toques_sin_respuesta between 0 and 50),
  deleted_at      timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  updated_by      text not null default coalesce(auth.jwt() ->> 'email', 'mensajes-webhook'),
  unique (canal, contacto_id),
  check (estado <> 'de_cesar' or tomado_por is not null),
  check (tomado_por is null or estado in ('de_cesar','cerrado'))
);

create table if not exists public.mensajes (
  id          bigint generated always as identity primary key,
  chat_id     bigint not null references public.mensajes_chats(id),
  meta_id     text not null unique,             -- wamid / mid de Meta
  direccion   text not null check (direccion in ('entrante','saliente')),
  autor       text not null check (autor in ('cliente','bandeja','externo','automatico')),
  tipo        text not null default 'text',
  texto       text check (length(texto) <= 8000),
  payload     jsonb not null,                   -- lo que mandó Meta, tal cual
  enviado_at  timestamptz not null,
  enviado_por text,                             -- quién aprobó (solo autor 'bandeja')
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  updated_by  text not null default coalesce(auth.jwt() ->> 'email', 'mensajes-webhook'),
  check ((direccion = 'entrante') = (autor = 'cliente')),
  check (autor <> 'bandeja' or enviado_por is not null)
);
create index if not exists mensajes_chat_idx on public.mensajes (chat_id, enviado_at);

create table if not exists public.mensajes_borradores (
  id           bigint generated always as identity primary key,
  chat_id      bigint not null references public.mensajes_chats(id),
  mensaje_id   bigint not null references public.mensajes(id),   -- el entrante que responde
  texto        text not null check (length(texto) between 1 and 4000),
  revision     jsonb not null default '{}'::jsonb,                -- reglas revisadas
  modelo       text not null,
  para         text not null default 'bandeja' check (para in ('bandeja','cesar')),  -- lo fija el trigger
  estado      text not null default 'pendiente'
               check (estado in ('pendiente','enviado','editado_enviado','descartado','caducado')),
  texto_final  text check (length(texto_final) <= 4000),
  aprobado_por text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  updated_by   text not null default coalesce(auth.jwt() ->> 'email', 'mensajes-webhook'),
  unique (mensaje_id),                                            -- un borrador por mensaje
  check (estado not in ('enviado','editado_enviado') or aprobado_por is not null)  -- nada sale sin nombre
);
create index if not exists mensajes_borr_chat_idx on public.mensajes_borradores (chat_id, estado);

create table if not exists public.mensajes_historial (
  id        bigint generated always as identity primary key,
  tabla     text not null,
  fila_id   bigint not null,
  accion    text not null,
  anterior  jsonb not null,
  ts        timestamptz not null default now(),
  por       text not null default coalesce(auth.jwt() ->> 'email', 'mensajes-webhook')
);
create index if not exists mensajes_hist_idx on public.mensajes_historial (tabla, fila_id, ts);

-- ── Lo que se aprende (pedido del usuario, 18-11) ─────────────────────────
-- La revisión diaria del 5558 (skill revision-whatsapp) ya arma en Drive el
-- corpus anonimizado (corpus-respuestas.jsonl) y la guía (guia-respuestas.md).
-- Esa corrida los sube aquí por la Edge Function (ruta /conocimiento, con su
-- propio secreto) y los borradores de la bandeja los usan como ejemplos.
-- Además entran como ejemplo los borradores que un humano EDITÓ antes
-- de enviar (lo que Claude propuso vs. lo que salió) y las respuestas de César.
create table if not exists public.mensajes_ejemplos (
  id            bigint generated always as identity primary key,
  clave         text not null unique,           -- hash de fecha+cliente+respuesta: subir dos veces no duplica
  fuente        text not null check (fuente in ('5558','bandeja_editado','bandeja_cesar')),
  fecha         date not null,
  intencion     text not null,
  producto      text,
  cliente       text not null check (length(cliente) <= 2000),     -- ANONIMIZADO
  respuesta     text not null check (length(respuesta) <= 4000),
  propuesta     text check (length(propuesta) <= 4000),           -- solo bandeja_editado: lo que propuso Claude
  calidad       text not null check (calidad in ('modelo','ok','evitar')),
  resultado_7d  text check (resultado_7d in ('compró','siguió','silencio','perdido','pendiente')),
  por_que       text,
  activo        boolean not null default true,  -- apagar un ejemplo malo sin borrarlo
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  updated_by    text not null default coalesce(auth.jwt() ->> 'email', 'mensajes-webhook')
);
create index if not exists mensajes_ej_idx on public.mensajes_ejemplos (activo, calidad, fecha desc);

-- La guía por intención (guia-respuestas.md). Una fila por versión; manda la última.
create table if not exists public.mensajes_guia (
  id          bigint generated always as identity primary key,
  texto       text not null check (length(texto) between 50 and 60000),
  fuente      text not null default 'revision-whatsapp',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  updated_by  text not null default coalesce(auth.jwt() ->> 'email', 'mensajes-webhook')
);

-- ── Sellos e historial ───────────────────────────────────────────────────
create or replace function public.mensajes_sellar()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  new.updated_by := coalesce(auth.jwt() ->> 'email', 'mensajes-webhook');
  return new;
end $$;

create or replace function public.mensajes_historial_guardar()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.mensajes_historial (tabla, fila_id, accion, anterior)
  values (tg_table_name, old.id, lower(tg_op), to_jsonb(old));
  return coalesce(new, old);
end $$;
revoke all on function public.mensajes_historial_guardar() from public, anon, authenticated;

-- ── La regla de César, en la base ───────────────────────────────────────
-- Un saliente que no salió de la bandeja = alguien entró a mano: el chat es suyo.
create or replace function public.mensajes_tomar_chat()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.autor = 'externo' then
    update public.mensajes_chats
       set estado = 'de_cesar', tomado_por = coalesce(tomado_por, 'cesar'), tomado_at = coalesce(tomado_at, new.enviado_at)
     where id = new.chat_id and tomado_por is null;
    update public.mensajes_borradores set estado = 'caducado'
     where chat_id = new.chat_id and estado = 'pendiente';
  elsif new.autor = 'cliente' then
    update public.mensajes_chats
       set ultimo_entrante_at = greatest(coalesce(ultimo_entrante_at, new.enviado_at), new.enviado_at),
           toques_sin_respuesta = 0,
           estado = case when tomado_por is null then 'por_aprobar' else estado end
     where id = new.chat_id;
  else -- bandeja / automatico
    update public.mensajes_chats
       set toques_sin_respuesta = toques_sin_respuesta + 1,
           estado = case when tomado_por is null then 'esperando' else estado end
     where id = new.chat_id;
  end if;
  return new;
end $$;
revoke all on function public.mensajes_tomar_chat() from public, anon, authenticated;

-- En un chat tomado el borrador es una SUGERENCIA para César (para='cesar'),
-- lo decida quien lo decida en el código. Y nunca sale nada automático ahí.
create or replace function public.mensajes_borrador_permitido()
returns trigger language plpgsql as $$
begin
  if exists (select 1 from public.mensajes_chats where id = new.chat_id and tomado_por is not null) then
    new.para := 'cesar';
  else
    new.para := 'bandeja';
  end if;
  return new;
end $$;

create or replace function public.mensajes_sin_auto_en_tomado()
returns trigger language plpgsql as $$
begin
  if new.autor = 'automatico'
     and exists (select 1 from public.mensajes_chats where id = new.chat_id and tomado_por is not null) then
    raise exception 'CHAT TOMADO: en un chat de César no sale nada automático.';
  end if;
  return new;
end $$;

-- Un chat tomado no se «destoma» solo.

create or replace function public.mensajes_chat_no_destomar()
returns trigger language plpgsql as $$
begin
  if old.tomado_por is not null and new.tomado_por is null then
    raise exception 'Un chat tomado no vuelve a la bandeja.';
  end if;
  return new;
end $$;

drop trigger if exists tr_mensajes_chats_sellar on public.mensajes_chats;
create trigger tr_mensajes_chats_sellar before update on public.mensajes_chats
  for each row execute function public.mensajes_sellar();
drop trigger if exists tr_mensajes_chats_destomar on public.mensajes_chats;
create trigger tr_mensajes_chats_destomar before update on public.mensajes_chats
  for each row execute function public.mensajes_chat_no_destomar();
drop trigger if exists tr_mensajes_chats_hist on public.mensajes_chats;
create trigger tr_mensajes_chats_hist after update or delete on public.mensajes_chats
  for each row execute function public.mensajes_historial_guardar();

drop trigger if exists tr_mensajes_sin_auto on public.mensajes;
create trigger tr_mensajes_sin_auto before insert on public.mensajes
  for each row execute function public.mensajes_sin_auto_en_tomado();
drop trigger if exists tr_mensajes_tomar on public.mensajes;
create trigger tr_mensajes_tomar after insert on public.mensajes
  for each row execute function public.mensajes_tomar_chat();
drop trigger if exists tr_mensajes_sellar on public.mensajes;
create trigger tr_mensajes_sellar before update on public.mensajes
  for each row execute function public.mensajes_sellar();
drop trigger if exists tr_mensajes_hist on public.mensajes;
create trigger tr_mensajes_hist after update or delete on public.mensajes
  for each row execute function public.mensajes_historial_guardar();

drop trigger if exists tr_mensajes_borr_permitido on public.mensajes_borradores;
create trigger tr_mensajes_borr_permitido before insert on public.mensajes_borradores
  for each row execute function public.mensajes_borrador_permitido();
drop trigger if exists tr_mensajes_borr_sellar on public.mensajes_borradores;
create trigger tr_mensajes_borr_sellar before update on public.mensajes_borradores
  for each row execute function public.mensajes_sellar();
drop trigger if exists tr_mensajes_borr_hist on public.mensajes_borradores;
create trigger tr_mensajes_borr_hist after update or delete on public.mensajes_borradores
  for each row execute function public.mensajes_historial_guardar();

drop trigger if exists tr_mensajes_ej_sellar on public.mensajes_ejemplos;
create trigger tr_mensajes_ej_sellar before update on public.mensajes_ejemplos
  for each row execute function public.mensajes_sellar();
drop trigger if exists tr_mensajes_ej_hist on public.mensajes_ejemplos;
create trigger tr_mensajes_ej_hist after update or delete on public.mensajes_ejemplos
  for each row execute function public.mensajes_historial_guardar();
drop trigger if exists tr_mensajes_guia_sellar on public.mensajes_guia;
create trigger tr_mensajes_guia_sellar before update on public.mensajes_guia
  for each row execute function public.mensajes_sellar();
drop trigger if exists tr_mensajes_guia_hist on public.mensajes_guia;
create trigger tr_mensajes_guia_hist after update or delete on public.mensajes_guia
  for each row execute function public.mensajes_historial_guardar();

-- ── RLS ─────────────────────────────────────────────────────────────────
-- Etapa 1: el dueño y los vendedores ACTIVOS solo LEEN (la bandeja vive en el
-- panel de seguimiento, donde trabaja César). Marketing no: son datos personales
-- y no los necesita (por eso no se usa es_equipo_panel()). Escribe únicamente la
-- Edge Function con la llave de servicio.
create or replace function public.mensajes_puede_leer()
returns boolean language sql stable security definer set search_path = public as $$
  select lower(coalesce(auth.email(), '')) = 'hola@casazaru.cl'
      or exists (select 1 from public.vendedores v where lower(v.email) = lower(auth.email()) and v.activo);
$$;
revoke all on function public.mensajes_puede_leer() from public, anon;
grant execute on function public.mensajes_puede_leer() to authenticated;

alter table public.mensajes_chats      enable row level security;
alter table public.mensajes_chats      force  row level security;
alter table public.mensajes            enable row level security;
alter table public.mensajes            force  row level security;
alter table public.mensajes_borradores enable row level security;
alter table public.mensajes_borradores force  row level security;
alter table public.mensajes_historial  enable row level security;
alter table public.mensajes_historial  force  row level security;

drop policy if exists mensajes_chats_leer on public.mensajes_chats;
create policy mensajes_chats_leer on public.mensajes_chats
  for select to authenticated using (public.mensajes_puede_leer());
drop policy if exists mensajes_leer on public.mensajes;
create policy mensajes_leer on public.mensajes
  for select to authenticated using (public.mensajes_puede_leer());
drop policy if exists mensajes_borr_leer on public.mensajes_borradores;
create policy mensajes_borr_leer on public.mensajes_borradores
  for select to authenticated using (public.mensajes_puede_leer());
drop policy if exists mensajes_hist_leer on public.mensajes_historial;
create policy mensajes_hist_leer on public.mensajes_historial
  for select to authenticated using (public.mensajes_puede_leer());

alter table public.mensajes_ejemplos   enable row level security;
alter table public.mensajes_ejemplos   force  row level security;
alter table public.mensajes_guia       enable row level security;
alter table public.mensajes_guia       force  row level security;
drop policy if exists mensajes_ej_leer on public.mensajes_ejemplos;
create policy mensajes_ej_leer on public.mensajes_ejemplos
  for select to authenticated using (public.mensajes_puede_leer());
drop policy if exists mensajes_guia_leer on public.mensajes_guia;
create policy mensajes_guia_leer on public.mensajes_guia
  for select to authenticated using (public.mensajes_puede_leer());

revoke all on public.mensajes_chats, public.mensajes, public.mensajes_borradores, public.mensajes_historial,
              public.mensajes_ejemplos, public.mensajes_guia
  from anon, authenticated;
grant select on public.mensajes_chats, public.mensajes, public.mensajes_borradores, public.mensajes_historial,
               public.mensajes_ejemplos, public.mensajes_guia
  to authenticated;

-- Registro
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('0004', 'bandeja_mensajes', array[
  'create table mensajes_chats, mensajes, mensajes_borradores, mensajes_historial, mensajes_ejemplos, mensajes_guia (ver supabase-cotizador/migrations/0004_bandeja_mensajes.sql);',
  'triggers: sellar, historial, tomar_chat, borrador_permitido, sin_auto_en_tomado, chat_no_destomar;',
  'RLS + FORCE en las seis; select para authenticated solo si mensajes_puede_leer() (dueño o vendedor activo); anon sin permisos.'
])
on conflict (version) do nothing;

-- Verificación. Debe dar: tablas 6 · con_rls_force 6 · policies 6 · triggers 14 ·
-- anon_algo 0 · auth_escribe 0 · service_inserta 6 · ultima 0004.
with t as (
  select c.oid, c.relname, c.relrowsecurity, c.relforcerowsecurity
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r' and c.relname like 'mensajes%')
select
  (select count(*) from t)                                                           as tablas,
  (select count(*) from t where relrowsecurity and relforcerowsecurity)              as con_rls_force,
  (select count(*) from pg_policies where schemaname = 'public' and tablename like 'mensajes%') as policies,
  (select count(*) from pg_trigger g join t on t.oid = g.tgrelid where not g.tgisinternal)      as triggers,
  (select count(*) from t cross join unnest(array['select','insert','update','delete','truncate']) p
    where has_table_privilege('anon', t.oid, p))                                     as anon_algo,
  (select count(*) from t cross join unnest(array['insert','update','delete','truncate']) p
    where has_table_privilege('authenticated', t.oid, p))                            as auth_escribe,
  (select count(*) from t where has_table_privilege('service_role', t.oid, 'insert')) as service_inserta,
  (select max(version) from supabase_migrations.schema_migrations)                   as ultima;

-- Rollback (NO correr junto con lo de arriba; respaldar antes: select * de las seis tablas):
--   drop table public.mensajes_guia; drop table public.mensajes_ejemplos;
--   drop table public.mensajes_historial; drop table public.mensajes_borradores;
--   drop table public.mensajes; drop table public.mensajes_chats;
--   drop function public.mensajes_sellar(); drop function public.mensajes_historial_guardar();
--   drop function public.mensajes_tomar_chat(); drop function public.mensajes_borrador_permitido();
--   drop function public.mensajes_chat_no_destomar(); drop function public.mensajes_sin_auto_en_tomado();
--   drop function public.mensajes_puede_leer();
--   delete from supabase_migrations.schema_migrations where version = '0004';
