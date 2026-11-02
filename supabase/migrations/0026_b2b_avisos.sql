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

-- ══════════════════════════════════════════════════════════════════════════
-- 0026 · Aviso del programa Cuenta empresa (02-11-2026)
--
-- Registro de a qué empresa se le avisó del programa, cuándo, por dónde y
-- quién. Lo escribe el botón «Avisar por WhatsApp» de la pestaña Empresas
-- (o «Ya se lo dije por otro lado»).
--
-- Una empresa se avisa UNA vez por tipo: lo garantiza el índice único parcial
-- (empresa_id, tipo) sobre los avisos vigentes, no el navegador. Si dos
-- personas tocan el botón a la vez, la segunda recibe 23505.
-- Un aviso no se borra ni se edita: se deshace (anulado_at) y queda la fila,
-- más su versión anterior en b2b_avisos_historial.
--
-- Antes de aplicar: mirar supabase_migrations.schema_migrations; si la 0026
-- ya existe, renumerar. Idempotente.
-- ══════════════════════════════════════════════════════════════════════════

create table if not exists public.b2b_avisos (
  id          bigint generated always as identity primary key,
  client_id   uuid not null unique,                     -- uuid del navegador: el reintento no duplica
  empresa_id  bigint not null references public.b2b_empresas(id),
  tipo        text not null default 'programa' check (tipo ~ '^[a-z_]{3,30}$'),
  canal       text not null check (canal in ('whatsapp','otro')),
  celular     text,
  mensaje     text check (mensaje is null or length(mensaje) <= 4000),
  anulado_at  timestamptz,
  anulado_por text,
  created_at  timestamptz not null default now(),
  created_by  text default (auth.jwt() ->> 'email'),
  updated_at  timestamptz not null default now(),
  updated_by  text default (auth.jwt() ->> 'email'),
  constraint b2b_avisos_anulado check ((anulado_at is null) = (anulado_por is null))
);
comment on table public.b2b_avisos is 'A qué empresa se le avisó del programa Cuenta empresa. Se deshace con anulado_at; nunca se borra.';

create unique index if not exists b2b_avisos_uno_vigente
  on public.b2b_avisos (empresa_id, tipo) where anulado_at is null;

create table if not exists public.b2b_avisos_historial (
  id        bigint generated always as identity primary key,
  aviso_id  bigint not null,
  ts        timestamptz not null default now(),
  por       text default (auth.jwt() ->> 'email'),
  accion    text not null check (accion in ('UPDATE','DELETE')),
  anterior  jsonb not null
);
create index if not exists b2b_avisos_hist_idx on public.b2b_avisos_historial (aviso_id, ts);

-- Lo único que cambia en un aviso es deshacerlo, y deshecho no vuelve.
create or replace function public.b2b_avisos_antes()
returns trigger language plpgsql as $$
begin
  if (new.client_id, new.empresa_id, new.tipo, new.canal, new.celular, new.mensaje)
     is distinct from
     (old.client_id, old.empresa_id, old.tipo, old.canal, old.celular, old.mensaje) then
    raise exception 'Un aviso no se edita: se deshace y se avisa de nuevo';
  end if;
  if old.anulado_at is not null and new.anulado_at is distinct from old.anulado_at then
    raise exception 'Un aviso deshecho no vuelve: avisa de nuevo';
  end if;
  if new.anulado_at is not null and old.anulado_at is null then
    new.anulado_por := coalesce(auth.jwt() ->> 'email', new.anulado_por);
  end if;
  new.updated_at := now();
  new.updated_by := coalesce(auth.jwt() ->> 'email', new.updated_by);
  new.created_at := old.created_at;
  new.created_by := old.created_by;
  return new;
end $$;
drop trigger if exists tr_b2b_avisos_antes on public.b2b_avisos;
create trigger tr_b2b_avisos_antes before update on public.b2b_avisos
  for each row execute function public.b2b_avisos_antes();

create or replace function public.b2b_avisos_historial_guardar()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.b2b_avisos_historial (aviso_id, accion, anterior)
  values (old.id, tg_op, to_jsonb(old));
  return coalesce(new, old);
end $$;
drop trigger if exists tr_b2b_avisos_historial on public.b2b_avisos;
create trigger tr_b2b_avisos_historial after update or delete on public.b2b_avisos
  for each row execute function public.b2b_avisos_historial_guardar();


-- ── RLS ───────────────────────────────────────────────────────────────────
-- Admin y vendedor leen, avisan y deshacen. El taller no ve Empresas.
-- No hay DELETE para nadie.
alter table public.b2b_avisos           enable row level security;
alter table public.b2b_avisos           force  row level security;
alter table public.b2b_avisos_historial enable row level security;
alter table public.b2b_avisos_historial force  row level security;

drop policy if exists b2b_avisos_leer on public.b2b_avisos;
create policy b2b_avisos_leer on public.b2b_avisos
  for select to authenticated using (public.zaru_rol() in ('admin','vendedor'));
drop policy if exists b2b_avisos_crear on public.b2b_avisos;
create policy b2b_avisos_crear on public.b2b_avisos
  for insert to authenticated
  with check (public.zaru_rol() in ('admin','vendedor') and anulado_at is null);
drop policy if exists b2b_avisos_deshacer on public.b2b_avisos;
create policy b2b_avisos_deshacer on public.b2b_avisos
  for update to authenticated
  using (public.zaru_rol() in ('admin','vendedor')) with check (public.zaru_rol() in ('admin','vendedor'));

drop policy if exists b2b_avisos_hist_leer on public.b2b_avisos_historial;
create policy b2b_avisos_hist_leer on public.b2b_avisos_historial
  for select to authenticated using (public.zaru_rol() = 'admin');

grant select, insert, update on public.b2b_avisos to authenticated;
grant select on public.b2b_avisos_historial to authenticated;
revoke all on public.b2b_avisos, public.b2b_avisos_historial from anon;


-- Rollback (los avisos registrados se pierden; respaldarlos antes):
--   drop table public.b2b_avisos_historial; drop table public.b2b_avisos;
--   drop function public.b2b_avisos_historial_guardar(); drop function public.b2b_avisos_antes();

-- Registrar en el panel (Database → Migrations), pegándolo junto con este archivo:
-- insert into supabase_migrations.schema_migrations (version, name, statements)
-- values ('0026', 'b2b_avisos', array[$m0026$ <este archivo> $m0026$]);
