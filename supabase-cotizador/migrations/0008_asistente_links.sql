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
  if to_regclass('public.mensajes_envios') is null
     or not exists (select 1 from supabase_migrations.schema_migrations where version = '0007') then
    raise exception 'FALTA LA 0007: aplicar antes 0007_bandeja_borrador_enviado.sql. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- 0008 · COTIZADOR · Links de cotización del asistente (19-11-2026)
--
-- El asistente de la bandeja pide las medidas en el chat y manda el cotizador
-- con ellas ya puestas:  casazaru.cl/cotizador?prod=<producto>&c=<codigo>&src=asistente
-- El precio lo sigue calculando SOLO el cotizador. Acá queda el registro para
-- medir: qué link se armó, si se mandó, si se abrió y si terminó en cotización.
--
--   mensajes_links                una fila por link armado (código, chat, producto, medidas).
--   asistente_link_abrir(codigo)  la llama el cotizador público al abrir el link: devuelve
--                                 las medidas y el nombre (NUNCA el teléfono) y anota la apertura.
--   trigger en mensajes_envios    cuando un envío sale, el link que iba en el texto queda «enviado».
--   trigger en cotizaciones       la cotización que llega con origen.c = código queda amarrada al
--                                 link y al chat, y toma el WhatsApp del chat si venía sin contacto.
--                                 Si algo falla ahí dentro, la cotización se guarda igual.
--   asistente_resumen(dias)       los números para la pantalla de mensajes.
--
-- Idempotente. Rollback al final.
--
-- APLICADA el 19-11-2026 en el SQL Editor del Cotizador (con ok del dueño).
-- Verificación: tabla 1, rls_force true, funciones 4, trg_envios 5, trg_cotiz 1, anon_abre true,
-- anon_tabla false, última 0008. Reglas probadas con supabase-cotizador/prueba-0008-reglas.sql: 9 de 9.
-- ══════════════════════════════════════════════════════════════════════════

create table if not exists public.mensajes_links (
  id                  bigint generated always as identity primary key,
  codigo              text not null unique check (codigo ~ '^[a-z0-9]{10,24}$'),
  chat_id             bigint not null references public.mensajes_chats(id),
  borrador_id         bigint references public.mensajes_borradores(id),
  producto            text not null check (producto in ('cubierta', 'repisa', 'peldano', 'puertas', 'mesa')),
  datos               jsonb not null check (jsonb_typeof(datos) = 'object'),
  listo               boolean not null default false,   -- true: abre directo en la cotización; false: falta elegir modelo
  enviado_at          timestamptz,
  abierto_at          timestamptz,
  ultima_apertura_at  timestamptz,
  aperturas           integer not null default 0 check (aperturas >= 0),
  cotizo_at           timestamptz,
  cotizaciones        integer not null default 0 check (cotizaciones >= 0),
  cotizacion_numero   text,
  cotizacion_link     text,
  deleted_at          timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  updated_by          text not null default coalesce(auth.jwt() ->> 'email', 'mensajes-webhook')
);
create index if not exists mensajes_links_chat_idx on public.mensajes_links (chat_id, created_at);

drop trigger if exists tr_mensajes_links_sellar on public.mensajes_links;
create trigger tr_mensajes_links_sellar before update on public.mensajes_links
  for each row execute function public.mensajes_sellar();
drop trigger if exists tr_mensajes_links_hist on public.mensajes_links;
create trigger tr_mensajes_links_hist after update or delete on public.mensajes_links
  for each row execute function public.mensajes_historial_guardar();

alter table public.mensajes_links enable row level security;
alter table public.mensajes_links force  row level security;
drop policy if exists mensajes_links_leer on public.mensajes_links;
create policy mensajes_links_leer on public.mensajes_links
  for select to authenticated using (public.mensajes_puede_leer());
revoke all on public.mensajes_links from anon, authenticated;
grant select on public.mensajes_links to authenticated;

-- ── El cotizador público abre un link ─────────────────────────────────────
-- Devuelve solo lo necesario para rellenar el formulario. El teléfono no sale
-- de la base: lo pone el trigger de cotizaciones al guardar.
create or replace function public.asistente_link_abrir(p_codigo text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v public.mensajes_links;
  v_nombre text;
begin
  if p_codigo is null or p_codigo !~ '^[a-z0-9]{10,24}$' then return null; end if;
  select * into v from public.mensajes_links
   where codigo = p_codigo and deleted_at is null and created_at > now() - interval '60 days'
   for update;
  if not found then return null; end if;
  update public.mensajes_links
     set aperturas = aperturas + 1,
         abierto_at = coalesce(abierto_at, now()),
         ultima_apertura_at = now()
   where id = v.id;
  select nullif(btrim(left(coalesce(c.nombre, ''), 60)), '') into v_nombre
    from public.mensajes_chats c where c.id = v.chat_id;
  return jsonb_build_object(
    'd', v.datos,
    'listo', v.listo,
    'n', v_nombre,
    's', substring(coalesce(v.cotizacion_link, '') from '[?&]s=([A-Za-z0-9_-]+)')
  );
end $$;
revoke all on function public.asistente_link_abrir(text) from public;
grant execute on function public.asistente_link_abrir(text) to anon, authenticated;

-- ── Un envío salió: el link que iba en el texto queda «enviado» ───────────
create or replace function public.mensajes_envio_marca_link()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.estado = 'enviado' and old.estado is distinct from 'enviado' then
    update public.mensajes_links l
       set enviado_at = now()
     where l.chat_id = new.chat_id and l.enviado_at is null and l.deleted_at is null
       and position('c=' || l.codigo in new.texto) > 0;
  end if;
  return new;
end $$;
revoke all on function public.mensajes_envio_marca_link() from public, anon, authenticated;
drop trigger if exists tr_mensajes_envios_link on public.mensajes_envios;
create trigger tr_mensajes_envios_link after update on public.mensajes_envios
  for each row execute function public.mensajes_envio_marca_link();

-- ── Una cotización llegó desde un link del asistente ──────────────────────
-- BEFORE INSERT en cotizaciones. Todo va dentro de un bloque que traga
-- cualquier error: una falla acá NUNCA puede impedir que se guarde la cotización.
create or replace function public.asistente_cotizacion_amarra()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_cod text;
  v public.mensajes_links;
  v_tel text;
begin
  begin
    v_cod := new.origen ->> 'c';
    if v_cod is null or v_cod !~ '^[a-z0-9]{10,24}$' then return new; end if;
    select * into v from public.mensajes_links where codigo = v_cod and deleted_at is null for update;
    if not found then return new; end if;
    select regexp_replace(coalesce(c.telefono, ''), '\D', '', 'g') into v_tel
      from public.mensajes_chats c where c.id = v.chat_id;
    if coalesce(btrim(new.contacto), '') = '' and length(coalesce(v_tel, '')) >= 8 then
      new.contacto := '+' || v_tel;
    end if;
    new.origen := new.origen || jsonb_build_object('src', 'asistente', 'chat', v.chat_id);
    update public.mensajes_links
       set cotizaciones = cotizaciones + 1,
           cotizo_at = coalesce(cotizo_at, now()),
           cotizacion_numero = coalesce(cotizacion_numero, new.numero),
           cotizacion_link = coalesce(cotizacion_link, new.link)
     where id = v.id;
  exception when others then
    null;
  end;
  return new;
end $$;
revoke all on function public.asistente_cotizacion_amarra() from public, anon, authenticated;
drop trigger if exists tr_cotizaciones_asistente on public.cotizaciones;
create trigger tr_cotizaciones_asistente before insert on public.cotizaciones
  for each row when (new.origen ? 'c') execute function public.asistente_cotizacion_amarra();

-- ── Los números para la pantalla de mensajes ──────────────────────────────
create or replace function public.asistente_resumen(p_dias integer default 30)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_desde timestamptz := now() - make_interval(days => greatest(1, least(coalesce(p_dias, 30), 365)));
begin
  if not public.mensajes_puede_leer() then
    raise exception 'sin acceso' using errcode = '42501';
  end if;
  return (
    with base as (
      select l.producto, l.enviado_at, l.abierto_at, l.cotizo_at,
             (select q.estado from public.cotizaciones q
               where q.numero = l.cotizacion_numero and not coalesce(q.eliminada, false) limit 1) as estado
        from public.mensajes_links l
       where l.deleted_at is null and l.created_at >= v_desde
    ), por as (
      select producto,
             count(*)                                   as armados,
             count(*) filter (where enviado_at is not null) as enviados,
             count(*) filter (where abierto_at is not null) as abiertos,
             count(*) filter (where cotizo_at is not null)  as cotizaron,
             count(*) filter (where estado = 'ganado')      as ventas
        from base group by producto
    )
    select jsonb_build_object(
      'dias', greatest(1, least(coalesce(p_dias, 30), 365)),
      'armados',   coalesce(sum(armados), 0),
      'enviados',  coalesce(sum(enviados), 0),
      'abiertos',  coalesce(sum(abiertos), 0),
      'cotizaron', coalesce(sum(cotizaron), 0),
      'ventas',    coalesce(sum(ventas), 0),
      'por_producto', coalesce(jsonb_agg(to_jsonb(por) order by por.enviados desc, por.producto), '[]'::jsonb)
    ) from por
  );
end $$;
revoke all on function public.asistente_resumen(integer) from public, anon;
grant execute on function public.asistente_resumen(integer) to authenticated;

-- Registro
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('0008', 'asistente_links', array[
  'create table mensajes_links (links de cotización que arma el asistente; RLS + FORCE, solo lectura para el equipo);',
  'function asistente_link_abrir(text): el cotizador público lee las medidas del link y anota la apertura (sin teléfono);',
  'trigger tr_mensajes_envios_link: el link que va en un envío queda enviado;',
  'trigger tr_cotizaciones_asistente (before insert, when origen ? c): amarra la cotización al link y al chat; nunca bloquea;',
  'function asistente_resumen(integer): armados, enviados, abiertos, cotizaron y ventas por producto.'
])
on conflict (version) do nothing;

-- Verificación. Debe dar: tabla 1 · rls_force true · funciones 4 · trg_envios 5 · trg_cotiz 1 · anon_abre true · anon_tabla false · ultima 0008.
select
  (select count(*) from information_schema.tables where table_schema = 'public' and table_name = 'mensajes_links')            as tabla,
  (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.mensajes_links'::regclass)                 as rls_force,
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
     and proname in ('asistente_link_abrir', 'mensajes_envio_marca_link', 'asistente_cotizacion_amarra', 'asistente_resumen')) as funciones,
  (select count(*) from pg_trigger where tgrelid = 'public.mensajes_envios'::regclass and not tgisinternal)                   as trg_envios,
  (select count(*) from pg_trigger where tgrelid = 'public.cotizaciones'::regclass and not tgisinternal)                      as trg_cotiz,
  has_function_privilege('anon', 'public.asistente_link_abrir(text)', 'execute')                                              as anon_abre,
  has_table_privilege('anon', 'public.mensajes_links', 'select')                                                              as anon_tabla,
  (select max(version) from supabase_migrations.schema_migrations)                                                            as ultima;

-- Rollback (NO correr junto con lo de arriba):
--   drop trigger tr_cotizaciones_asistente on public.cotizaciones;
--   drop trigger tr_mensajes_envios_link on public.mensajes_envios;
--   drop function public.asistente_cotizacion_amarra(); drop function public.mensajes_envio_marca_link();
--   drop function public.asistente_link_abrir(text);    drop function public.asistente_resumen(integer);
--   drop table public.mensajes_links;   -- antes: respaldo de sus filas
--   delete from supabase_migrations.schema_migrations where version = '0008';
