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
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '0002') then
    raise exception 'FALTA LA 0002: aplicar antes 0002_force_permisos_whoami.sql. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- 0003_equipo_mi_dia · COTIZADOR · 17-11-2026
--
-- «Mi día» para alguien del equipo (la primera: marketing), en la página
-- mi-dia.html del sitio del Cotizador. Es una versión recortada del «Mi día»
-- del dueño (que vive en la Gestión y tiene plata, impuestos y RR. HH.): aquí
-- solo viaja lo que esa persona tiene que hacer.
--
--   equipo_dias      el día armado de cada persona (JSON), una fila por
--                    (correo, fecha). Lo escribe SOLO equipo_publicar_dia(),
--                    que la corrida de las 07:30 llama con una llave propia.
--                    Lo lee la persona dueña de la fila y el admin.
--   equipo_marcas    lo que la persona marca: Listo (con link), Bloqueada (por
--                    quién), Mañana, y la rutina. Lo escribe la persona con su
--                    sesión; lo lee ella y el admin. La corrida de las 07:30 lo
--                    LEE por el MCP de solo lectura. Nadie borra.
--   equipo_historial versión anterior de cada fila que cambia o se borra.
--   equipo_llave     el hash (sha256) de la llave de publicación. Sin permisos
--                    para nadie: solo la lee la función. La llave no está en el
--                    repo: el hash se carga aparte, en el SQL Editor.
--
-- Idempotente. Rollback al final.
-- ══════════════════════════════════════════════════════════════════════════

create table if not exists public.equipo_dias (
  correo     text not null check (correo = lower(correo) and correo like '%@%'),
  fecha      date not null,
  data       jsonb not null check (jsonb_typeof(data) = 'object' and length(data::text) <= 200000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by text not null default 'equipo-publicar',
  primary key (correo, fecha)
);
comment on table public.equipo_dias is '«Mi día» del equipo (0003): el día armado por persona. Lo escribe solo equipo_publicar_dia(); lo leen la persona y el admin.';

create table if not exists public.equipo_marcas (
  correo     text not null check (correo = lower(correo) and correo like '%@%'),
  fecha      date not null,
  data       jsonb not null default '{}'::jsonb
             check (jsonb_typeof(data) = 'object' and length(data::text) <= 50000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by text not null default coalesce(auth.jwt() ->> 'email', 'sin-sesion'),
  primary key (correo, fecha)
);
comment on table public.equipo_marcas is '«Mi día» del equipo (0003): lo que la persona marca (misiones y rutina). Lo escribe la persona; lo leen ella y el admin.';

create table if not exists public.equipo_historial (
  id       bigint generated always as identity primary key,
  tabla    text not null check (tabla in ('equipo_dias','equipo_marcas')),
  correo   text not null,
  fecha    date not null,
  ts       timestamptz not null default now(),
  por      text default coalesce(auth.jwt() ->> 'email', 'equipo-publicar'),
  accion   text not null check (accion in ('UPDATE','DELETE')),
  anterior jsonb not null
);
create index if not exists equipo_hist_idx on public.equipo_historial (tabla, correo, fecha, ts);

create table if not exists public.equipo_llave (
  id   int primary key default 1 check (id = 1),
  hash text not null check (hash ~ '^[0-9a-f]{64}$'),
  updated_at timestamptz not null default now()
);
comment on table public.equipo_llave is 'Hash sha256 de la llave con que la corrida publica equipo_dias (0003). Sin permisos: solo la lee equipo_publicar_dia().';

-- Sellos: updated_at/updated_by los pone la base, no el navegador.
create or replace function public.equipo_sellar()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  new.updated_by := coalesce(auth.jwt() ->> 'email', case when tg_table_name = 'equipo_dias' then 'equipo-publicar' else 'sin-sesion' end);
  if tg_op = 'UPDATE' then new.created_at := old.created_at; end if;
  return new;
end $$;

create or replace function public.equipo_historial_guardar()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.equipo_historial (tabla, correo, fecha, accion, anterior)
  values (tg_table_name, old.correo, old.fecha, tg_op, to_jsonb(old));
  return coalesce(new, old);
end $$;
revoke all on function public.equipo_historial_guardar() from public, anon, authenticated;

drop trigger if exists tr_equipo_dias_sellar on public.equipo_dias;
create trigger tr_equipo_dias_sellar before insert or update on public.equipo_dias
  for each row execute function public.equipo_sellar();
drop trigger if exists tr_equipo_dias_hist on public.equipo_dias;
create trigger tr_equipo_dias_hist after update or delete on public.equipo_dias
  for each row execute function public.equipo_historial_guardar();

drop trigger if exists tr_equipo_marcas_sellar on public.equipo_marcas;
create trigger tr_equipo_marcas_sellar before insert or update on public.equipo_marcas
  for each row execute function public.equipo_sellar();
drop trigger if exists tr_equipo_marcas_hist on public.equipo_marcas;
create trigger tr_equipo_marcas_hist after update or delete on public.equipo_marcas
  for each row execute function public.equipo_historial_guardar();

-- Publicar el día: la corrida de las 07:30 llama esta función con la llave.
-- Sin llave correcta no escribe nada. Una persona = un correo del equipo.
create or replace function public.equipo_publicar_dia(p_llave text, p_correo text, p_fecha date, p_data jsonb)
returns text language plpgsql security definer set search_path = public as $$
declare h text;
begin
  select hash into h from public.equipo_llave where id = 1;
  if h is null or p_llave is null or length(p_llave) < 32
     or encode(extensions.digest(p_llave, 'sha256'), 'hex') <> h then
    raise exception 'llave inválida' using errcode = '42501';
  end if;
  insert into public.equipo_dias (correo, fecha, data)
  values (lower(p_correo), p_fecha, p_data)
  on conflict (correo, fecha) do update set data = excluded.data;
  return 'ok ' || lower(p_correo) || ' ' || p_fecha;
end $$;
revoke all on function public.equipo_publicar_dia(text, text, date, jsonb) from public;
grant execute on function public.equipo_publicar_dia(text, text, date, jsonb) to anon;


-- ── RLS ───────────────────────────────────────────────────────────────────
alter table public.equipo_dias      enable row level security;
alter table public.equipo_dias      force  row level security;
alter table public.equipo_marcas    enable row level security;
alter table public.equipo_marcas    force  row level security;
alter table public.equipo_historial enable row level security;
alter table public.equipo_historial force  row level security;
alter table public.equipo_llave     enable row level security;
alter table public.equipo_llave     force  row level security;

drop policy if exists equipo_dias_leer on public.equipo_dias;
create policy equipo_dias_leer on public.equipo_dias
  for select to authenticated
  using (correo = lower(auth.email()) or lower(auth.email()) = 'hola@casazaru.cl');

drop policy if exists equipo_marcas_leer on public.equipo_marcas;
create policy equipo_marcas_leer on public.equipo_marcas
  for select to authenticated
  using (correo = lower(auth.email()) or lower(auth.email()) = 'hola@casazaru.cl');
-- Solo marca la dueña de la fila, y solo en un día que se le publicó.
drop policy if exists equipo_marcas_crear on public.equipo_marcas;
create policy equipo_marcas_crear on public.equipo_marcas
  for insert to authenticated
  with check (correo = lower(auth.email())
              and exists (select 1 from public.equipo_dias d where d.correo = equipo_marcas.correo and d.fecha = equipo_marcas.fecha));
drop policy if exists equipo_marcas_cambiar on public.equipo_marcas;
create policy equipo_marcas_cambiar on public.equipo_marcas
  for update to authenticated
  using (correo = lower(auth.email())) with check (correo = lower(auth.email()));

drop policy if exists equipo_hist_leer on public.equipo_historial;
create policy equipo_hist_leer on public.equipo_historial
  for select to authenticated using (lower(auth.email()) = 'hola@casazaru.cl');
-- equipo_llave: sin policies a propósito.

revoke all on public.equipo_dias, public.equipo_marcas, public.equipo_historial, public.equipo_llave from anon, authenticated;
grant select on public.equipo_dias to authenticated;
grant select, insert, update on public.equipo_marcas to authenticated;
grant select on public.equipo_historial to authenticated;


-- Rollback (lo marcado se pierde; respaldar antes con
--   select * from public.equipo_marcas; select * from public.equipo_dias;):
--   drop function public.equipo_publicar_dia(text, text, date, jsonb);
--   drop table public.equipo_historial; drop table public.equipo_marcas;
--   drop table public.equipo_dias; drop table public.equipo_llave;
--   drop function public.equipo_historial_guardar(); drop function public.equipo_sellar();
--   delete from supabase_migrations.schema_migrations where version = '0003';

-- Registrar en el panel (Database → Migrations), pegándolo junto con este archivo:
-- insert into supabase_migrations.schema_migrations (version, name, statements)
-- values ('0003', 'equipo_mi_dia', array[$m0003$ <este archivo> $m0003$]);
