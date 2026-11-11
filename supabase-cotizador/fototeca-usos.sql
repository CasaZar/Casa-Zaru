-- ── CANDADO DE PROYECTO (no borrar) ──────────────────────────────────────
-- Este archivo es del COTIZADOR (cmxqorsyxoltrakxawro). Si se pega en el SQL
-- Editor de otro proyecto, este bloque falla primero y Postgres descarta el
-- resto del script: no se aplica nada.
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
-- Fototeca · usadas en contenido · Cotizador (11-11-2026)
--
-- Cada vez que una foto o video sale en contenido (post, reel, historia,
-- anuncio de Meta, correo) queda una fila: qué pieza, dónde, cuándo, quién y
-- el link si lo hay. Una pieza puede usarse varias veces.
-- Marcan: hola@, Emerge (contenido) y María José (marketing). César solo ve.
-- «Quitar» no borra: pone quitado_at. Cada cambio deja la versión anterior en
-- fototeca_usos_historial.
-- Escritura SOLO por fototeca_marcar_uso() y fototeca_quitar_uso().
-- Idempotente. Rollback al final.
-- ══════════════════════════════════════════════════════════════════════════

create or replace function public.fototeca_marca_usos()
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select lower(coalesce(auth.email(), '')) in ('hola@casazaru.cl', 'emerge.smm@gmail.com', 'mariajose.mgrunen@gmail.com')
$$;

create table if not exists public.fototeca_usos (
  id          bigint generated always as identity primary key,
  item_id     text not null check (item_id ~ '^(M[0-9]{4}|g[0-9a-f]{10})$'),
  canal       text not null check (canal in ('post','reel','historia','anuncio','correo')),
  fecha       date not null default current_date check (fecha between date '2020-01-01' and current_date + 1),
  link        text check (link is null or (link ~ '^https://' and length(link) <= 500)),
  quitado_at  timestamptz,
  created_at  timestamptz not null default now(),
  created_by  text default (auth.jwt() ->> 'email'),
  updated_at  timestamptz not null default now(),
  updated_by  text default (auth.jwt() ->> 'email')
);
-- el mismo uso (pieza + canal + día) no se anota dos veces
create unique index if not exists fototeca_usos_unico
  on public.fototeca_usos (item_id, canal, fecha) where quitado_at is null;
create index if not exists fototeca_usos_item_idx on public.fototeca_usos (item_id);

create table if not exists public.fototeca_usos_historial (
  hid     bigint generated always as identity primary key,
  uso_id  bigint not null,
  op      text not null check (op in ('UPDATE','DELETE')),
  ts      timestamptz not null default now(),
  por     text default (auth.jwt() ->> 'email'),
  antes   jsonb not null
);

create or replace function public.fototeca_usos_hist()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  insert into public.fototeca_usos_historial (uso_id, op, antes) values (old.id, tg_op, to_jsonb(old));
  if tg_op = 'UPDATE' then
    new.updated_at := now();
    new.updated_by := coalesce(auth.jwt() ->> 'email', new.updated_by);
    return new;
  end if;
  return old;
end $$;
drop trigger if exists fototeca_usos_hist on public.fototeca_usos;
create trigger fototeca_usos_hist before update or delete on public.fototeca_usos
  for each row execute function public.fototeca_usos_hist();

alter table public.fototeca_usos enable row level security;
alter table public.fototeca_usos force row level security;
alter table public.fototeca_usos_historial enable row level security;
alter table public.fototeca_usos_historial force row level security;

-- leen los que leen el bucket «fototeca» (también César)
drop policy if exists "lectores fototeca leen usos" on public.fototeca_usos;
create policy "lectores fototeca leen usos" on public.fototeca_usos
  for select to authenticated using (
    lower(auth.email()) in ('hola@casazaru.cl', 'crodriguez.casazaru@gmail.com', 'emerge.smm@gmail.com', 'mariajose.mgrunen@gmail.com')
  );
drop policy if exists "admin lee historial usos" on public.fototeca_usos_historial;
create policy "admin lee historial usos" on public.fototeca_usos_historial
  for select to authenticated using (lower(auth.email()) = 'hola@casazaru.cl');

revoke all on public.fototeca_usos, public.fototeca_usos_historial from anon;
revoke insert, update, delete on public.fototeca_usos, public.fototeca_usos_historial from authenticated;
grant select on public.fototeca_usos, public.fototeca_usos_historial to authenticated;

-- ── escritura ──
-- Marca 1 a 500 piezas como usadas en un canal. Si ya estaba ese uso (misma
-- pieza, canal y día) no hace nada. Devuelve cuántas filas nuevas quedaron.
create or replace function public.fototeca_marcar_uso(p_ids text[], p_canal text, p_fecha date default current_date, p_link text default null)
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare n integer;
begin
  if not public.fototeca_marca_usos() then raise exception 'Esta cuenta no puede marcar usos en la Fototeca'; end if;
  if coalesce(array_length(p_ids, 1), 0) = 0 or array_length(p_ids, 1) > 500 then
    raise exception 'Hay que mandar entre 1 y 500 piezas';
  end if;
  insert into public.fototeca_usos (item_id, canal, fecha, link)
  select distinct unnest(p_ids), p_canal, coalesce(p_fecha, current_date), nullif(trim(p_link), '')
  on conflict (item_id, canal, fecha) where quitado_at is null do nothing;
  get diagnostics n = row_count;
  return n;
end $$;

-- Quita un uso marcado por error (no lo borra).
create or replace function public.fototeca_quitar_uso(p_id bigint)
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare n integer;
begin
  if not public.fototeca_marca_usos() then raise exception 'Esta cuenta no puede marcar usos en la Fototeca'; end if;
  update public.fototeca_usos set quitado_at = now() where id = p_id and quitado_at is null;
  get diagnostics n = row_count;
  return n;
end $$;

revoke all on function public.fototeca_marca_usos() from public, anon;
revoke all on function public.fototeca_marcar_uso(text[], text, date, text) from public, anon;
revoke all on function public.fototeca_quitar_uso(bigint) from public, anon;
grant execute on function public.fototeca_marca_usos() to authenticated;
grant execute on function public.fototeca_marcar_uso(text[], text, date, text) to authenticated;
grant execute on function public.fototeca_quitar_uso(bigint) to authenticated;

-- ── Verificación (2 tablas con RLS forzada y 3 funciones) ──
select relname, relrowsecurity, relforcerowsecurity from pg_class
 where relname in ('fototeca_usos', 'fototeca_usos_historial');
select proname from pg_proc where proname in ('fototeca_marca_usos', 'fototeca_marcar_uso', 'fototeca_quitar_uso');

-- ══ ROLLBACK (no correr salvo que se quiera deshacer todo; se pierde el registro de usos) ══
-- drop function if exists public.fototeca_quitar_uso(bigint);
-- drop function if exists public.fototeca_marcar_uso(text[], text, date, text);
-- drop trigger if exists fototeca_usos_hist on public.fototeca_usos;
-- drop function if exists public.fototeca_usos_hist();
-- drop table if exists public.fototeca_usos_historial;
-- drop table if exists public.fototeca_usos;
-- drop function if exists public.fototeca_marca_usos();
