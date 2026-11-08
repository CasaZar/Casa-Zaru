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
  if to_regclass('public.whatsapp_pendientes') is null then
    raise exception 'Falta whatsapp-al-dia.sql: córrelo primero. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- «WhatsApp al día» · historial y freno (08-11-2026)
--
-- Tres cosas, a pedido del usuario («me da miedo que se vayan pasando cosas»):
-- 1) whatsapp_revisiones: una fila por cada carga de la revisión, con desde
--    cuándo cubrió. Así se ve si un día quedó sin revisar (hueco entre una
--    revisión y la siguiente). Solo la escribe wa_cargar; nadie la edita ni
--    la borra (no hay permiso de update/delete para nadie): es el registro.
-- 2) Freno en wa_cargar: si una carga cerraría más de la mitad de lo pendiente
--    (y más de 3 chats), no aplica NADA y dice cuáles serían. Así una revisión
--    a medias no hace desaparecer chats que siguen esperando. Para pasar el
--    freno hay que decirlo explícito (p_forzar => true) después de comprobar
--    que esos chats de verdad se respondieron. Tampoco acepta una revisión
--    más vieja que la última cargada.
-- 3) wa_historial(p_dias): lo que se cerró en los últimos días (quién y
--    cuándo, incluido «lo cerró la revisión») más la lista de revisiones.
--    Lo arma de la tabla y de whatsapp_pendientes_historial, que ya guardaba
--    cada versión anterior. Lo leen solo el admin y César.
-- Idempotente. Rollback al final.
-- ══════════════════════════════════════════════════════════════════════════

create table if not exists public.whatsapp_revisiones (
  id           bigint generated always as identity primary key,
  revision_at  timestamptz not null,
  desde        timestamptz,
  chats        integer not null check (chats >= 0),
  nuevos       integer not null default 0,
  actualizados integer not null default 0,
  ya_resueltos integer not null default 0,
  cerrados     integer not null default 0,
  forzada      boolean not null default false,
  nota         text check (length(nota) <= 300),
  check (desde is null or desde <= revision_at),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  updated_by   text default (auth.jwt() ->> 'email')
);
create index if not exists whatsapp_revisiones_rev_idx on public.whatsapp_revisiones (revision_at desc);

alter table public.whatsapp_revisiones enable row level security;
alter table public.whatsapp_revisiones force row level security;
drop policy if exists "5558 lee revisiones" on public.whatsapp_revisiones;
create policy "5558 lee revisiones" on public.whatsapp_revisiones
  for select to authenticated using (
    auth.email() in ('hola@casazaru.cl', 'crodriguez.casazaru@gmail.com')
  );
revoke all on public.whatsapp_revisiones from anon, authenticated;
grant select on public.whatsapp_revisiones to authenticated;

-- la primera carga (08-11 15:15) fue antes de que existiera esta tabla:
-- se anota con lo que dejó en whatsapp_pendientes (13 chats nuevos, tabla vacía)
insert into public.whatsapp_revisiones
  (revision_at, desde, chats, nuevos, actualizados, ya_resueltos, cerrados, nota)
select '2026-11-08 18:15:00+00', null, 13, 13, 0, 0, 0,
       'Primera carga; se anotó después, al crear el registro de revisiones'
where not exists (select 1 from public.whatsapp_revisiones where revision_at = '2026-11-08 18:15:00+00')
  and (select count(*) from public.whatsapp_pendientes where revision_at = '2026-11-08 18:15:00+00') > 0;

-- ── wa_cargar con freno y registro ──
-- La firma cambia (agrega p_desde y p_forzar): se borra la vieja para que una
-- llamada con dos argumentos no quede ambigua entre las dos.
drop function if exists public.wa_cargar(timestamptz, jsonb);

create or replace function public.wa_cargar(
  p_revision timestamptz, p_filas jsonb,
  p_desde timestamptz default null, p_forzar boolean default false)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  f jsonb; n_nuevos int := 0; n_act int := 0; n_resp int := 0; n_cerr int := 0;
  ids text[] := '{}'; r public.whatsapp_pendientes;
  n_pend int; n_a_cerrar int; nombres text; ult timestamptz; lista jsonb;
begin
  if coalesce(auth.email(), '') <> 'hola@casazaru.cl' then
    raise exception 'Solo el admin carga la revisión de WhatsApp';
  end if;
  if p_revision is null or p_revision > now() + interval '5 minutes' then
    raise exception 'Hora de revisión inválida';
  end if;
  if p_desde is not null and p_desde > p_revision then
    raise exception 'p_desde no puede ser después de la hora de la revisión';
  end if;
  if jsonb_typeof(p_filas) <> 'array' or jsonb_array_length(p_filas) > 200 then
    raise exception 'p_filas debe ser una lista de hasta 200 chats';
  end if;

  select max(revision_at) into ult from public.whatsapp_revisiones;
  if ult is not null and p_revision < ult then
    raise exception 'Ya hay una revisión más nueva cargada (%). No se aplicó nada.', ult;
  end if;

  select coalesce(array_agg(e ->> 'chat_id'), '{}') into ids
  from jsonb_array_elements(p_filas) e;

  -- freno: ¿cuántos pendientes cerraría esta carga?
  select count(*) into n_pend from public.whatsapp_pendientes
  where estado = 'pendiente' and deleted_at is null;
  select count(*), string_agg(cliente, ', ' order by prioridad)
    into n_a_cerrar, nombres
  from public.whatsapp_pendientes
  where estado = 'pendiente' and deleted_at is null
    and revision_at < p_revision and not (chat_id = any(ids));
  if not p_forzar and n_a_cerrar > 3 and n_a_cerrar * 2 > n_pend then
    raise exception 'FRENO: esta carga cerraría % de % pendientes (%). Si la revisión fue completa y esos chats de verdad se respondieron, repetirla con p_forzar => true. No se aplicó nada.',
      n_a_cerrar, n_pend, nombres;
  end if;

  for f in select * from jsonb_array_elements(p_filas) loop
    select * into r from public.whatsapp_pendientes where chat_id = f ->> 'chat_id';
    if not found then
      insert into public.whatsapp_pendientes
        (chat_id, cliente, telefono, tipo, prioridad, espera_desde, contexto, cita,
         mensaje, monto, pedido, revision_at)
      values
        (f ->> 'chat_id', f ->> 'cliente', nullif(f ->> 'telefono', ''), f ->> 'tipo',
         coalesce((f ->> 'prioridad')::smallint, 50), (f ->> 'espera_desde')::timestamptz,
         f ->> 'contexto', f ->> 'cita', f ->> 'mensaje', (f ->> 'monto')::integer,
         f ->> 'pedido', p_revision);
      n_nuevos := n_nuevos + 1;
    elsif r.estado in ('respondido','no_corresponde') and r.resuelto_at >= p_revision then
      n_resp := n_resp + 1;          -- César lo cerró después de la revisión: manda él
    else
      update public.whatsapp_pendientes set
        cliente = f ->> 'cliente', telefono = nullif(f ->> 'telefono', ''), tipo = f ->> 'tipo',
        prioridad = coalesce((f ->> 'prioridad')::smallint, 50),
        espera_desde = (f ->> 'espera_desde')::timestamptz, contexto = f ->> 'contexto',
        cita = f ->> 'cita', mensaje = f ->> 'mensaje', monto = (f ->> 'monto')::integer,
        pedido = f ->> 'pedido', revision_at = p_revision, estado = 'pendiente',
        resuelto_at = null, resuelto_por = null, deleted_at = null
      where id = r.id;
      n_act := n_act + 1;
    end if;
  end loop;

  with c as (
    update public.whatsapp_pendientes set
      estado = 'cerrado', resuelto_at = now(), resuelto_por = 'revision'
    where estado = 'pendiente' and deleted_at is null
      and revision_at < p_revision and not (chat_id = any(ids))
    returning cliente
  )
  select count(*), coalesce(jsonb_agg(cliente), '[]') into n_cerr, lista from c;

  insert into public.whatsapp_revisiones
    (revision_at, desde, chats, nuevos, actualizados, ya_resueltos, cerrados, forzada)
  values (p_revision, p_desde, jsonb_array_length(p_filas), n_nuevos, n_act, n_resp, n_cerr,
          p_forzar and n_a_cerrar > 3 and n_a_cerrar * 2 > n_pend);

  return jsonb_build_object('nuevos', n_nuevos, 'actualizados', n_act,
                            'ya_resueltos', n_resp, 'cerrados', n_cerr,
                            'cerrados_quienes', lista);
end $$;

-- ── wa_historial: lo cerrado en los últimos p_dias + las revisiones ──
-- Cada cierre sale de una versión de la fila (la actual o una guardada en el
-- historial). «vigente» = false si después volvió a la lista (Deshacer o una
-- revisión que lo vio abierto otra vez).
create or replace function public.wa_historial(p_dias integer default 30)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare d0 timestamptz; res jsonb;
begin
  if coalesce(auth.email(), '') not in ('hola@casazaru.cl', 'crodriguez.casazaru@gmail.com') then
    raise exception 'Sin acceso';
  end if;
  d0 := now() - make_interval(days => least(greatest(coalesce(p_dias, 30), 1), 120));

  with versiones as (
    select p.id as fila_id, to_jsonb(p) as v, 1 as actual
    from public.whatsapp_pendientes p where p.deleted_at is null
    union all
    select h.fila_id, h.antes, 0 from public.whatsapp_pendientes_historial h
  ), cierres as (
    select distinct on (fila_id, (v ->> 'resuelto_at')::timestamptz)
           fila_id, v, (v ->> 'resuelto_at')::timestamptz as cuando
    from versiones
    where v ->> 'estado' in ('respondido','no_corresponde','cerrado')
      and v ->> 'resuelto_at' is not null
      and (v ->> 'resuelto_at')::timestamptz >= d0
    order by fila_id, (v ->> 'resuelto_at')::timestamptz, actual desc
  )
  select jsonb_build_object(
    'cierres', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', c.fila_id, 'cliente', c.v ->> 'cliente', 'tipo', c.v ->> 'tipo',
               'estado', c.v ->> 'estado', 'resuelto_at', c.cuando,
               'resuelto_por', c.v ->> 'resuelto_por', 'contexto', c.v ->> 'contexto',
               'monto', c.v -> 'monto', 'pedido', c.v ->> 'pedido',
               'espera_desde', c.v ->> 'espera_desde',
               'vigente', (p.estado = c.v ->> 'estado' and p.resuelto_at = c.cuando))
             order by c.cuando desc)
      from cierres c join public.whatsapp_pendientes p on p.id = c.fila_id), '[]'::jsonb),
    'revisiones', coalesce((
      select jsonb_agg(jsonb_build_object(
               'revision_at', r.revision_at, 'desde', r.desde, 'chats', r.chats,
               'nuevos', r.nuevos, 'actualizados', r.actualizados,
               'ya_resueltos', r.ya_resueltos, 'cerrados', r.cerrados,
               'forzada', r.forzada, 'nota', r.nota)
             order by r.revision_at desc)
      from public.whatsapp_revisiones r where r.revision_at >= d0), '[]'::jsonb)
  ) into res;
  return res;
end $$;

revoke all on function public.wa_cargar(timestamptz, jsonb, timestamptz, boolean) from public, anon;
revoke all on function public.wa_historial(integer) from public, anon;
grant execute on function public.wa_cargar(timestamptz, jsonb, timestamptz, boolean) to authenticated;
grant execute on function public.wa_historial(integer) to authenticated;

-- ── Verificación (debe dar 1 tabla con RLS forzado, 3 funciones y 1 revisión) ──
select c.relname, c.relrowsecurity as rls, c.relforcerowsecurity as forzado
from pg_class c where c.relname = 'whatsapp_revisiones';
select p.oid::regprocedure as funcion from pg_proc p
where p.proname in ('wa_cargar','wa_marcar','wa_historial');
select revision_at, chats, nuevos, cerrados, nota from public.whatsapp_revisiones;

-- ══ ROLLBACK (no correr salvo que se quiera deshacer esto; deja wa_cargar como antes) ══
-- drop function if exists public.wa_historial(integer);
-- drop function if exists public.wa_cargar(timestamptz, jsonb, timestamptz, boolean);
-- (volver a correr la sección «wa_cargar» de whatsapp-al-dia.sql)
-- drop table if exists public.whatsapp_revisiones;
