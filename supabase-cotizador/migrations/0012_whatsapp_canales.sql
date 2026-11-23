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
  if to_regclass('public.whatsapp_revisiones') is null then
    raise exception 'FALTA whatsapp-al-dia-historial.sql (whatsapp_revisiones). No se aplicó nada.';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '0011') then
    raise exception 'FALTA LA 0011: aplicar antes 0011_bandeja_freno_persona.sql. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- 0012 · COTIZADOR · «WhatsApp al día» por canal: 5558, 0141 e Instagram (23-11-2026)
-- APLICADA el 23-11-2026 (SQL Editor, desde el Chrome del usuario, a su pedido). Verificada por MCP:
-- 4 columnas, 99 filas quedaron en 5558, wa_cargar de 5 argumentos, unique (canal, chat_id).
--
-- Pedido del dueño: lo que la revisión encuentra sin responder en el 0141 (número de
-- los anuncios) y en Instagram le aparece a César en el panel con el mensaje sugerido
-- listo, igual que el 5558. Boceto aprobado el 23-11 («Sí, constrúyelo»).
--
-- Cambios:
--   · whatsapp_pendientes.canal ('5558' | '0141' | 'instagram'), default '5558': todo
--     lo que existe queda como 5558, que es lo que era.
--   · chat_id ya no es único solo: es único POR CANAL (un mismo número puede escribir
--     al 5558 y al 0141 y son dos conversaciones).
--   · enlace: para Instagram, el link del hilo en Meta Business Suite (no hay número).
--   · cotizacion / cotizacion_link: la cotización que se hizo para ese chat (N° CL y
--     link corto), para que César la vea en la fila.
--   · whatsapp_revisiones.canal: cada carga dice de qué canal fue.
--   · wa_cargar(..., p_canal): la carga de un canal SOLO cierra pendientes de ese canal,
--     y el freno y la «revisión más nueva» se miden dentro del canal. Antes, cargar el
--     0141 habría cerrado todo lo del 5558.
--   · wa_historial trae el canal.
-- No cambia quién lee ni quién escribe (mismas políticas: admin y César leen; solo
-- wa_cargar y wa_marcar escriben). wa_marcar no cambia.
--
-- Idempotente. Rollback al final.
-- ══════════════════════════════════════════════════════════════════════════

-- 1) columnas nuevas
alter table public.whatsapp_pendientes
  add column if not exists canal text not null default '5558',
  add column if not exists enlace text,
  add column if not exists cotizacion text,
  add column if not exists cotizacion_link text;

do $c$
begin
  if not exists (select 1 from pg_constraint where conname = 'whatsapp_pendientes_canal_check') then
    alter table public.whatsapp_pendientes add constraint whatsapp_pendientes_canal_check
      check (canal in ('5558','0141','instagram'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'whatsapp_pendientes_enlace_check') then
    alter table public.whatsapp_pendientes add constraint whatsapp_pendientes_enlace_check
      check (enlace is null or (length(enlace) <= 500 and enlace ~ '^https://(business\.facebook\.com|www\.instagram\.com|web\.whatsapp\.com)/'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'whatsapp_pendientes_cotizacion_check') then
    alter table public.whatsapp_pendientes add constraint whatsapp_pendientes_cotizacion_check
      check (cotizacion is null or length(cotizacion) <= 30);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'whatsapp_pendientes_cotizacion_link_check') then
    alter table public.whatsapp_pendientes add constraint whatsapp_pendientes_cotizacion_link_check
      check (cotizacion_link is null or cotizacion_link ~ '^https://www\.casazaru\.cl/cotizador\?s=[A-Za-z0-9]{3,20}$');
  end if;
  -- chat_id único por canal (antes, único a secas)
  if exists (select 1 from pg_constraint where conname = 'whatsapp_pendientes_chat_id_key') then
    alter table public.whatsapp_pendientes drop constraint whatsapp_pendientes_chat_id_key;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'whatsapp_pendientes_canal_chat_key') then
    alter table public.whatsapp_pendientes add constraint whatsapp_pendientes_canal_chat_key unique (canal, chat_id);
  end if;
end
$c$;

alter table public.whatsapp_revisiones
  add column if not exists canal text not null default '5558';
do $c$
begin
  if not exists (select 1 from pg_constraint where conname = 'whatsapp_revisiones_canal_check') then
    alter table public.whatsapp_revisiones add constraint whatsapp_revisiones_canal_check
      check (canal in ('5558','0141','instagram'));
  end if;
end
$c$;

-- 2) wa_cargar por canal (reemplaza la de 4 argumentos)
drop function if exists public.wa_cargar(timestamptz, jsonb, timestamptz, boolean);

create or replace function public.wa_cargar(
  p_revision timestamptz, p_filas jsonb,
  p_desde timestamptz default null, p_forzar boolean default false,
  p_canal text default '5558')
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  f jsonb; n_nuevos int := 0; n_act int := 0; n_resp int := 0; n_cerr int := 0;
  ids text[] := '{}'; r public.whatsapp_pendientes;
  n_pend int; n_a_cerrar int; nombres text; ult timestamptz; lista jsonb;
begin
  if coalesce(auth.email(), '') <> 'hola@casazaru.cl' then
    raise exception 'Solo el admin carga la revisión de WhatsApp';
  end if;
  if p_canal is null or p_canal not in ('5558','0141','instagram') then
    raise exception 'Canal inválido: %', p_canal;
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

  select max(revision_at) into ult from public.whatsapp_revisiones where canal = p_canal;
  if ult is not null and p_revision < ult then
    raise exception 'Ya hay una revisión más nueva cargada para el % (%). No se aplicó nada.', p_canal, ult;
  end if;

  select coalesce(array_agg(e ->> 'chat_id'), '{}') into ids
  from jsonb_array_elements(p_filas) e;

  -- freno: ¿cuántos pendientes DE ESTE CANAL cerraría esta carga?
  select count(*) into n_pend from public.whatsapp_pendientes
  where canal = p_canal and estado = 'pendiente' and deleted_at is null;
  select count(*), string_agg(cliente, ', ' order by prioridad)
    into n_a_cerrar, nombres
  from public.whatsapp_pendientes
  where canal = p_canal and estado = 'pendiente' and deleted_at is null
    and revision_at < p_revision and not (chat_id = any(ids));
  if not p_forzar and n_a_cerrar > 3 and n_a_cerrar * 2 > n_pend then
    raise exception 'FRENO: esta carga cerraría % de % pendientes del % (%). Si la revisión fue completa y esos chats de verdad se respondieron, repetirla con p_forzar => true. No se aplicó nada.',
      n_a_cerrar, n_pend, p_canal, nombres;
  end if;

  for f in select * from jsonb_array_elements(p_filas) loop
    select * into r from public.whatsapp_pendientes
     where canal = p_canal and chat_id = f ->> 'chat_id';
    if not found then
      insert into public.whatsapp_pendientes
        (canal, chat_id, cliente, telefono, tipo, prioridad, espera_desde, contexto, cita,
         mensaje, monto, pedido, enlace, cotizacion, cotizacion_link, revision_at)
      values
        (p_canal, f ->> 'chat_id', f ->> 'cliente', nullif(f ->> 'telefono', ''), f ->> 'tipo',
         coalesce((f ->> 'prioridad')::smallint, 50), (f ->> 'espera_desde')::timestamptz,
         f ->> 'contexto', f ->> 'cita', f ->> 'mensaje', (f ->> 'monto')::integer,
         f ->> 'pedido', nullif(f ->> 'enlace', ''), nullif(f ->> 'cotizacion', ''),
         nullif(f ->> 'cotizacion_link', ''), p_revision);
      n_nuevos := n_nuevos + 1;
    elsif r.estado in ('respondido','no_corresponde') and r.resuelto_at >= p_revision then
      n_resp := n_resp + 1;          -- César lo cerró después de la revisión: manda él
    else
      update public.whatsapp_pendientes set
        cliente = f ->> 'cliente', telefono = nullif(f ->> 'telefono', ''), tipo = f ->> 'tipo',
        prioridad = coalesce((f ->> 'prioridad')::smallint, 50),
        espera_desde = (f ->> 'espera_desde')::timestamptz, contexto = f ->> 'contexto',
        cita = f ->> 'cita', mensaje = f ->> 'mensaje', monto = (f ->> 'monto')::integer,
        pedido = f ->> 'pedido', enlace = nullif(f ->> 'enlace', ''),
        cotizacion = nullif(f ->> 'cotizacion', ''), cotizacion_link = nullif(f ->> 'cotizacion_link', ''),
        revision_at = p_revision, estado = 'pendiente',
        resuelto_at = null, resuelto_por = null, deleted_at = null
      where id = r.id;
      n_act := n_act + 1;
    end if;
  end loop;

  with c as (
    update public.whatsapp_pendientes set
      estado = 'cerrado', resuelto_at = now(), resuelto_por = 'revision'
    where canal = p_canal and estado = 'pendiente' and deleted_at is null
      and revision_at < p_revision and not (chat_id = any(ids))
    returning cliente
  )
  select count(*), coalesce(jsonb_agg(cliente), '[]') into n_cerr, lista from c;

  insert into public.whatsapp_revisiones
    (canal, revision_at, desde, chats, nuevos, actualizados, ya_resueltos, cerrados, forzada)
  values (p_canal, p_revision, p_desde, jsonb_array_length(p_filas), n_nuevos, n_act, n_resp, n_cerr,
          p_forzar and n_a_cerrar > 3 and n_a_cerrar * 2 > n_pend);

  return jsonb_build_object('canal', p_canal, 'nuevos', n_nuevos, 'actualizados', n_act,
                            'ya_resueltos', n_resp, 'cerrados', n_cerr,
                            'cerrados_quienes', lista);
end $$;

-- 3) wa_historial con el canal (misma firma)
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
               'id', c.fila_id, 'canal', coalesce(c.v ->> 'canal', p.canal),
               'cliente', c.v ->> 'cliente', 'tipo', c.v ->> 'tipo',
               'estado', c.v ->> 'estado', 'resuelto_at', c.cuando,
               'resuelto_por', c.v ->> 'resuelto_por', 'contexto', c.v ->> 'contexto',
               'monto', c.v -> 'monto', 'pedido', c.v ->> 'pedido',
               'espera_desde', c.v ->> 'espera_desde',
               'vigente', (p.estado = c.v ->> 'estado' and p.resuelto_at = c.cuando))
             order by c.cuando desc)
      from cierres c join public.whatsapp_pendientes p on p.id = c.fila_id), '[]'::jsonb),
    'revisiones', coalesce((
      select jsonb_agg(jsonb_build_object(
               'canal', r.canal, 'revision_at', r.revision_at, 'desde', r.desde, 'chats', r.chats,
               'nuevos', r.nuevos, 'actualizados', r.actualizados,
               'ya_resueltos', r.ya_resueltos, 'cerrados', r.cerrados,
               'forzada', r.forzada, 'nota', r.nota)
             order by r.revision_at desc)
      from public.whatsapp_revisiones r where r.revision_at >= d0), '[]'::jsonb)
  ) into res;
  return res;
end $$;

revoke all on function public.wa_cargar(timestamptz, jsonb, timestamptz, boolean, text) from public, anon;
revoke all on function public.wa_historial(integer) from public, anon;
grant execute on function public.wa_cargar(timestamptz, jsonb, timestamptz, boolean, text) to authenticated;
grant execute on function public.wa_historial(integer) to authenticated;

-- 4) registro
insert into supabase_migrations.schema_migrations (version, name, statements)
select '0012', 'whatsapp_canales', array['ver supabase-cotizador/migrations/0012_whatsapp_canales.sql']
where not exists (select 1 from supabase_migrations.schema_migrations where version = '0012');

-- 5) verificación (debe dar: 3 columnas nuevas, canal 5558 en todas las filas actuales,
--    wa_cargar con 5 argumentos, unique (canal, chat_id))
select
  (select count(*) from information_schema.columns where table_name = 'whatsapp_pendientes'
     and column_name in ('canal','enlace','cotizacion','cotizacion_link')) as columnas_nuevas,
  (select count(*) from public.whatsapp_pendientes where canal <> '5558') as filas_no_5558,
  (select string_agg(p.oid::regprocedure::text, ' | ') from pg_proc p where p.proname = 'wa_cargar') as wa_cargar,
  (select count(*) from pg_constraint where conname = 'whatsapp_pendientes_canal_chat_key') as unico_por_canal,
  (select count(*) from supabase_migrations.schema_migrations where version = '0012') as registrada;

-- ── ROLLBACK (a mano, solo si hace falta; borra el canal de las filas) ──
-- Antes: confirmar que no hay filas de 0141/instagram que importen (quedarían como 5558).
-- drop function if exists public.wa_cargar(timestamptz, jsonb, timestamptz, boolean, text);
-- (volver a correr el bloque wa_cargar de whatsapp-al-dia-historial.sql)
-- alter table public.whatsapp_pendientes drop constraint if exists whatsapp_pendientes_canal_chat_key;
-- alter table public.whatsapp_pendientes add constraint whatsapp_pendientes_chat_id_key unique (chat_id);
-- alter table public.whatsapp_pendientes drop column if exists canal, drop column if exists enlace,
--   drop column if exists cotizacion, drop column if exists cotizacion_link;
-- alter table public.whatsapp_revisiones drop column if exists canal;
-- delete from supabase_migrations.schema_migrations where version = '0012';
