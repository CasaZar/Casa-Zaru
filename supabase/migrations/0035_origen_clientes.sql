-- ── CANDADO DE PROYECTO (no borrar) ──────────────────────────────────────
-- Este archivo es de GESTIÓN (padnttpgzuotxeipjrry). Si se pega en el SQL
-- Editor de otro proyecto, este bloque falla primero y Postgres descarta el
-- resto del script: no se aplica nada.
do $candado$
begin
  if to_regclass('public.gestion_pedidos') is null then
    raise exception 'PROYECTO EQUIVOCADO: este SQL es de GESTIÓN (padnttpgzuotxeipjrry) y aquí no existe gestion_pedidos. No se aplicó nada.';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '0034') then
    raise exception 'FALTA LA 0034 en schema_migrations: revisar el orden antes de seguir. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- 0035 · De dónde llegan los clientes (18-11-2026)
--
-- Boceto aprobado el 18-11: .claude/boceto-origen-clientes.html.
--
-- Cada 10 minutos la Gestión le pide al Cotizador las cotizaciones nuevas
-- (función origenes_para_gestion de la 0005 del Cotizador) y guarda una fila
-- por cotización en origen_eventos, con el canal YA CLASIFICADO acá en SQL
-- (origen_clasificar). Con eso:
--   · al cargar una venta, la Gestión busca el teléfono y propone el origen;
--   · el informe cuenta leads por canal y por anuncio.
--
-- El secreto que abre la puerta del Cotizador se genera acá, vive solo en la
-- bóveda (vault) y nunca sale de la base. Al Cotizador se le pasa su HUELLA
-- (sha256), que se muestra al final de este script.
--
-- ORDEN:
--   1) Correr este archivo en Gestión. Copiar la huella que muestra al final.
--   2) Pegar esa huella en supabase-cotizador/migrations/0005_origen_para_gestion.sql
--      (donde dice PEGAR_HUELLA) y correrlo en el Cotizador.
--   3) A los 10-20 minutos origen_sync.ultimo_ok_at tiene hora y origen_eventos
--      se empieza a llenar (de a 500 cotizaciones por vuelta, desde junio).
--
-- Solo lectura sobre el Cotizador. No toca gestion_finanzas ni ninguna fila de
-- negocio existente. Idempotente. Rollback al final.
-- ══════════════════════════════════════════════════════════════════════════

-- ── 1. El secreto, en la bóveda ─────────────────────────────────────────
do $m0035s$
begin
  if not exists (select 1 from vault.secrets where name = 'cotizador_origen') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'cotizador_origen',
      'Abre origenes_para_gestion() del Cotizador (0035). Su huella sha256 está en privado.llaves_externas del Cotizador.');
  end if;
end
$m0035s$;


-- ── 2. Clasificar un origen ─────────────────────────────────────────────
-- Recibe las marcas que guardó el Cotizador (utm, gclid, ref…) y devuelve
-- {canal, codigo, ubicacion, campana, anuncio}. Los nombres de canal son los
-- de la lista fija de index.html (CANALES_ANUNCIO / CANALES_SIN_ANUNCIO).
-- Ojo: Instagram le agrega fbclid a TODO link que sale de la app (también el
-- de la bio), así que fbclid solo NO prueba un anuncio. Lo que lo prueba es
-- utm_medium con la ubicación (Instagram_Stories, Facebook_Marketplace…), que
-- Meta pone desde que se cargaron los parámetros de URL.
create or replace function public.origen_clasificar(o jsonb)
returns jsonb language plpgsql immutable as $$
declare
  src  text := lower(coalesce(o->>'utm_source', ''));
  med  text := coalesce(o->>'utm_medium', '');
  cont text := coalesce(o->>'utm_content', '');
  ref  text := lower(coalesce(o->>'ref', ''));
  camp text := nullif(o->>'utm_campaign', '');
  gcid text := coalesce(o->>'gad_campaignid', '');
  ubi  text;
begin
  if o is null or o = '{}'::jsonb then return null; end if;

  if (o->>'profesional') = 'true' then
    return jsonb_build_object('canal', 'Referido', 'ubicacion', 'Profesional');
  end if;

  if (o->>'gclid') = 'true' or (o->>'gbraid') = 'true' or gcid <> ''
     or (src ~ 'google' and lower(med) ~ '(cpc|ppc|paid|ads)') then
    return jsonb_strip_nulls(jsonb_build_object('canal', 'Google anuncio',
      'codigo', case gcid when '23374012785' then 'GB' when '24179981440' then 'GS' else 'G' end,
      'ubicacion', case gcid when '23374012785' then 'Búsqueda' when '24179981440' then 'Shopping' end,
      'campana', camp, 'anuncio', nullif(o->>'utm_term', '')));
  end if;

  if src in ('fb', 'ig', 'facebook', 'instagram', 'meta', 'an', 'msg', 'th') then
    if cont = 'link_in_bio' or lower(med) in ('social', 'organic', 'bio', '') then
      return jsonb_strip_nulls(jsonb_build_object('canal', 'Instagram',
        'ubicacion', case when cont = 'link_in_bio' then 'Link de la bio' end));
    end if;
    ubi := case med
      when 'Instagram_Stories'      then 'Historia IG'
      when 'Instagram_Reels'        then 'Reel IG'
      when 'Instagram_Feed'         then 'Feed IG'
      when 'Instagram_Explore'      then 'Explorar IG'
      when 'Instagram_Profile_Feed' then 'Perfil IG'
      when 'Facebook_Stories'       then 'Historia FB'
      when 'Facebook_Mobile_Reels'  then 'Reel FB'
      when 'Facebook_Reels'         then 'Reel FB'
      when 'Facebook_Mobile_Feed'   then 'Feed FB'
      when 'Facebook_Desktop_Feed'  then 'Feed FB'
      when 'Facebook_Marketplace'   then 'Marketplace FB'
      when 'Facebook_Right_Column'  then 'Columna FB'
      when 'Messenger_Inbox'        then 'Messenger'
      else case when lower(med) ~ '^paid' then null else nullif(replace(med, '_', ' '), '') end end;
    return jsonb_strip_nulls(jsonb_build_object('canal', 'Meta anuncio', 'ubicacion', ubi,
      'campana', camp, 'anuncio', nullif(cont, '')));
  end if;

  if src ~ '(klaviyo|email|mail|newsletter)' or lower(med) ~ 'email' then
    return jsonb_strip_nulls(jsonb_build_object('canal', 'Correo', 'campana', camp));
  end if;

  if src ~ 'google' or ref ~ '(^|\.)google\.' then
    return jsonb_build_object('canal', 'Google orgánico / Maps');
  end if;

  if ref ~ 'manychat' then
    return jsonb_build_object('canal', 'Many Chat');
  end if;

  if ref ~ 'instagram' then
    return jsonb_build_object('canal', 'Instagram');
  end if;

  if ref ~ 'casazaru' then
    return jsonb_build_object('canal', 'Web');
  end if;

  return null;
end $$;
comment on function public.origen_clasificar(jsonb) is 'Marcas de origen del Cotizador → canal de la lista fija de la Gestión (0035). Única fuente de esta regla.';


-- ── 3. Una fila por contacto con su origen ──────────────────────────────
create table if not exists public.origen_eventos (
  id              bigint generated always as identity primary key,
  ref             text not null unique check (length(ref) between 3 and 80),
  tel8            text not null check (tel8 ~ '^\d{8}$'),
  fecha           timestamptz not null,
  fuente          text not null check (fuente in ('cotizacion', 'mensaje', 'manual')),
  canal           text check (canal is null or length(canal) <= 60),
  codigo          text check (codigo is null or codigo in ('GB', 'GS', 'G')),
  ubicacion       text check (ubicacion is null or length(ubicacion) <= 60),
  campana         text check (campana is null or length(campana) <= 200),
  anuncio         text check (anuncio is null or length(anuncio) <= 200),
  cotizacion_num  text check (cotizacion_num is null or length(cotizacion_num) <= 40),
  producto        text check (producto is null or length(producto) <= 80),
  total           integer check (total is null or total >= 0),
  vendedor        text check (vendedor is null or length(vendedor) <= 80),
  eliminada       boolean not null default false,
  crudo           jsonb check (crudo is null or length(crudo::text) <= 4000),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  updated_by      text default coalesce(auth.jwt() ->> 'email', current_user)
);
create index if not exists origen_eventos_tel_idx on public.origen_eventos (tel8, fecha);
create index if not exists origen_eventos_fecha_idx on public.origen_eventos (fecha);
comment on table public.origen_eventos is 'Contactos con su origen, por teléfono (0035). Hoy: una fila por cotización, traída del Cotizador por cron. Mañana: mensajes del 0141 e Instagram (fuente=mensaje).';

create table if not exists public.origen_eventos_historial (
  id         bigint generated always as identity primary key,
  evento_id  bigint not null,
  ts         timestamptz not null default now(),
  por        text default coalesce(auth.jwt() ->> 'email', current_user),
  accion     text not null check (accion in ('UPDATE', 'DELETE')),
  anterior   jsonb not null
);
create index if not exists origen_hist_idx on public.origen_eventos_historial (evento_id, ts);

create or replace function public.origen_eventos_antes()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  new.updated_by := coalesce(auth.jwt() ->> 'email', current_user);
  new.created_at := old.created_at;
  return new;
end $$;
drop trigger if exists tr_origen_eventos_antes on public.origen_eventos;
create trigger tr_origen_eventos_antes before update on public.origen_eventos
  for each row execute function public.origen_eventos_antes();

create or replace function public.origen_eventos_historial_guardar()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.origen_eventos_historial (evento_id, accion, anterior)
  values (old.id, tg_op, to_jsonb(old));
  return coalesce(new, old);
end $$;
drop trigger if exists tr_origen_eventos_historial on public.origen_eventos;
create trigger tr_origen_eventos_historial after update or delete on public.origen_eventos
  for each row execute function public.origen_eventos_historial_guardar();


-- ── 4. Estado de la sincronización (una sola fila) ──────────────────────
create table if not exists public.origen_sync (
  id             smallint primary key default 1 check (id = 1),
  pedido_id      bigint,
  pedido_at      timestamptz,
  desde          timestamptz,
  siguiente      timestamptz,
  ultimo_ok_at   timestamptz,
  filas_ultima   integer,
  ultimo_error   text check (ultimo_error is null or length(ultimo_error) <= 500),
  updated_at     timestamptz not null default now()
);
insert into public.origen_sync (id) values (1) on conflict (id) do nothing;


-- ── 5. Pedir y procesar (pg_net es asíncrono: se pide en una vuelta y se
--       lee la respuesta en la siguiente) ─────────────────────────────────
create or replace function public.origen_sync_pedir()
returns bigint language plpgsql security definer set search_path = public, extensions as $$
declare
  v_secreto text;
  v_desde   timestamptz;
  v_id      bigint;
begin
  select decrypted_secret into v_secreto from vault.decrypted_secrets where name = 'cotizador_origen';
  if v_secreto is null then raise exception 'falta el secreto cotizador_origen en vault'; end if;
  select coalesce(siguiente, '2026-06-01'::timestamptz) into v_desde from public.origen_sync where id = 1;
  v_id := net.http_post(
    url     := 'https://cmxqorsyxoltrakxawro.supabase.co/rest/v1/rpc/origenes_para_gestion',
    body    := jsonb_build_object('p_secreto', v_secreto, 'p_desde', v_desde),
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'apikey', 'sb_publishable_Z4Bu9BnRkjiKmuCUzUGz0Q_hwxOc-Go'),
    timeout_milliseconds := 20000);
  update public.origen_sync set pedido_id = v_id, pedido_at = now(), desde = v_desde, updated_at = now() where id = 1;
  return v_id;
end $$;

create or replace function public.origen_sync_procesar()
returns text language plpgsql security definer set search_path = public, extensions as $$
declare
  s       public.origen_sync%rowtype;
  r       record;
  datos   jsonb;
  x       jsonb;
  c       jsonb;
  n       integer := 0;
  maxf    timestamptz;
begin
  select * into s from public.origen_sync where id = 1;
  if s.pedido_id is null then return 'sin pedido'; end if;
  select status_code, content, error_msg into r from net._http_response where id = s.pedido_id;
  if not found then
    -- La respuesta no llegó todavía, o pg_net ya la limpió (guarda 6 h).
    if s.pedido_at < now() - interval '30 minutes' then
      update public.origen_sync set pedido_id = null, ultimo_error = 'sin respuesta del Cotizador', updated_at = now() where id = 1;
    end if;
    return 'esperando';
  end if;
  if r.status_code is distinct from 200 then
    update public.origen_sync set pedido_id = null,
      ultimo_error = left(coalesce(r.status_code::text, '?') || ' ' || coalesce(r.error_msg, r.content, ''), 500), updated_at = now()
     where id = 1;
    return 'error';
  end if;
  datos := r.content::jsonb;
  for x in select * from jsonb_array_elements(datos) loop
    continue when coalesce(x->>'tel8', '') !~ '^\d{8}$';
    c := public.origen_clasificar(x->'origen');
    insert into public.origen_eventos as e
      (ref, tel8, fecha, fuente, canal, codigo, ubicacion, campana, anuncio, cotizacion_num, producto, total, vendedor, eliminada, crudo)
    values ('cot:' || (x->>'id'), x->>'tel8', (x->>'fecha')::timestamptz, 'cotizacion',
            c->>'canal', c->>'codigo', left(c->>'ubicacion', 60), left(c->>'campana', 200), left(c->>'anuncio', 200),
            left(x->>'numero', 40), left(x->>'producto', 80), nullif(x->>'total', '')::numeric::integer,
            left(x->>'vendedor', 80), coalesce((x->>'eliminada')::boolean, false), x->'origen')
    on conflict (ref) do update set
      tel8 = excluded.tel8, fecha = excluded.fecha, canal = excluded.canal, codigo = excluded.codigo,
      ubicacion = excluded.ubicacion, campana = excluded.campana, anuncio = excluded.anuncio,
      cotizacion_num = excluded.cotizacion_num, producto = excluded.producto, total = excluded.total,
      vendedor = excluded.vendedor, eliminada = excluded.eliminada, crudo = excluded.crudo
    where (e.tel8, e.fecha, e.canal, e.codigo, e.ubicacion, e.campana, e.anuncio, e.cotizacion_num, e.producto, e.total, e.vendedor, e.eliminada, e.crudo)
      is distinct from (excluded.tel8, excluded.fecha, excluded.canal, excluded.codigo, excluded.ubicacion, excluded.campana, excluded.anuncio,
                        excluded.cotizacion_num, excluded.producto, excluded.total, excluded.vendedor, excluded.eliminada, excluded.crudo);
    n := n + 1;
  end loop;
  select max((v->>'fecha')::timestamptz) into maxf from jsonb_array_elements(datos) v;
  -- Página llena (500): la próxima sigue justo desde la última. Si no, se
  -- vuelve a mirar 2 días hacia atrás para recoger cambios recientes.
  update public.origen_sync set
    pedido_id = null, ultimo_ok_at = now(), filas_ultima = jsonb_array_length(datos), ultimo_error = null,
    siguiente = case when jsonb_array_length(datos) >= 500 then maxf
                     else greatest(coalesce(s.siguiente, '2026-06-01'::timestamptz),
                                   coalesce((select max(fecha) from public.origen_eventos where fuente = 'cotizacion'), '2026-06-01'::timestamptz) - interval '2 days') end,
    updated_at = now()
   where id = 1;
  return n || ' filas';
end $$;

revoke all on function public.origen_sync_pedir()    from public, anon, authenticated;
revoke all on function public.origen_sync_procesar() from public, anon, authenticated;

do $m0035c$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'origen-cotizador';
  perform cron.schedule('origen-cotizador', '*/10 * * * *',
    'select public.origen_sync_procesar(); select public.origen_sync_pedir();');
end
$m0035c$;


-- ── 6. Vistas para la pantalla ──────────────────────────────────────────
-- Por teléfono: el primer contacto (cualquiera) y el primer contacto CON canal.
create or replace view public.v_origen_contacto with (security_invoker = true) as
with ev as (
  select * from public.origen_eventos where not eliminada
)
select t.tel8,
       min(ev.fecha)                                  as primer_contacto,
       count(*) filter (where ev.fuente = 'cotizacion') as cotizaciones,
       (select to_jsonb(p) from (select e.fecha, e.fuente, e.canal, e.codigo, e.ubicacion, e.campana, e.anuncio, e.cotizacion_num, e.producto, e.vendedor
                                   from ev e where e.tel8 = t.tel8 order by e.fecha limit 1) p)                         as primero,
       (select to_jsonb(p) from (select e.fecha, e.fuente, e.canal, e.codigo, e.ubicacion, e.campana, e.anuncio, e.cotizacion_num, e.producto, e.vendedor
                                   from ev e where e.tel8 = t.tel8 and e.canal is not null order by e.fecha limit 1) p) as primero_con_canal
  from (select distinct tel8 from ev) t
  join ev on ev.tel8 = t.tel8
 group by t.tel8;

-- Leads por mes y canal del PRIMER contacto (para el informe; evita el tope
-- de 1000 filas de PostgREST). Sin canal = «Sin rastro».
create or replace view public.v_origen_leads_mes with (security_invoker = true) as
with primero as (
  select distinct on (tel8) tel8, fecha, canal, ubicacion, anuncio
    from public.origen_eventos where not eliminada
   order by tel8, fecha
)
select to_char(fecha at time zone 'America/Santiago', 'YYYY-MM') as mes,
       coalesce(canal, 'Sin rastro')                              as canal,
       ubicacion, anuncio,
       count(*)::integer                                          as leads
  from primero
 group by 1, 2, 3, 4;


-- ── 7. Permisos: solo el admin lee; nadie escribe desde la API ──────────
alter table public.origen_eventos           enable row level security;
alter table public.origen_eventos           force  row level security;
alter table public.origen_eventos_historial enable row level security;
alter table public.origen_eventos_historial force  row level security;
alter table public.origen_sync              enable row level security;
alter table public.origen_sync              force  row level security;

drop policy if exists origen_ev_leer on public.origen_eventos;
create policy origen_ev_leer on public.origen_eventos
  for select to authenticated using (public.zaru_rol() = 'admin');
drop policy if exists origen_hist_leer on public.origen_eventos_historial;
create policy origen_hist_leer on public.origen_eventos_historial
  for select to authenticated using (public.zaru_rol() = 'admin');
drop policy if exists origen_sync_leer on public.origen_sync;
create policy origen_sync_leer on public.origen_sync
  for select to authenticated using (public.zaru_rol() = 'admin');

revoke all on public.origen_eventos, public.origen_eventos_historial, public.origen_sync,
              public.v_origen_contacto, public.v_origen_leads_mes from anon, authenticated;
grant select on public.origen_eventos, public.origen_sync, public.v_origen_contacto, public.v_origen_leads_mes to authenticated;
grant select on public.origen_eventos_historial to authenticated;


-- ── Registro ─────────────────────────────────────────────────────────────
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('0035', 'origen_clientes', array[
  'vault cotizador_origen; origen_clasificar(jsonb); origen_eventos (+historial); origen_sync; cron origen-cotizador */10; v_origen_contacto; v_origen_leads_mes'
])
on conflict (version) do nothing;


-- ── Verificación + LA HUELLA PARA EL COTIZADOR ──────────────────────────
-- huella: copiarla tal cual en la 0005 del Cotizador (PEGAR_HUELLA).
-- prueba_meta debe decir Meta anuncio / Historia IG; prueba_bio, Instagram.
select
  (select encode(extensions.digest(decrypted_secret, 'sha256'), 'hex') from vault.decrypted_secrets where name = 'cotizador_origen') as huella,
  (select count(*) from cron.job where jobname = 'origen-cotizador')                                                                  as cron_ok,
  public.origen_clasificar('{"utm_source":"ig","utm_medium":"Instagram_Stories","utm_content":"VIDEO_X","utm_campaign":"TOFU"}')      as prueba_meta,
  public.origen_clasificar('{"utm_source":"ig","utm_medium":"social","utm_content":"link_in_bio","fbclid":true}')                    as prueba_bio,
  (select max(version) from supabase_migrations.schema_migrations)                                                                    as ultima_migracion;


-- ── ROLLBACK (no correr junto con lo de arriba) ──────────────────────────
-- Los eventos se reconstruyen solos desde el Cotizador; no hay dato de negocio único acá.
--   select cron.unschedule('origen-cotizador');
--   drop view if exists public.v_origen_leads_mes; drop view if exists public.v_origen_contacto;
--   drop function if exists public.origen_sync_procesar(); drop function if exists public.origen_sync_pedir();
--   drop table if exists public.origen_sync; drop table if exists public.origen_eventos_historial; drop table if exists public.origen_eventos;
--   drop function if exists public.origen_eventos_historial_guardar(); drop function if exists public.origen_eventos_antes();
--   drop function if exists public.origen_clasificar(jsonb);
--   delete from vault.secrets where name = 'cotizador_origen';
--   delete from supabase_migrations.schema_migrations where version = '0035';
