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
-- 0030 · Cerebro Zaru: pestaña «Mi día» (11-11-2026)
--
-- La pantalla diaria del dueño (antes una página aparte) pasa a ser una
-- pestaña de la Gestión, solo admin. Tiene sueldos, deudas y RR. HH.: nadie
-- más que el admin la lee, y anon no toca nada.
--
--   cerebro_dias    el día armado (JSON). Lo escribe SOLO la Edge Function
--                   `cerebro-dia` con la llave de servicio, que la corrida de
--                   las 07:30 llama con un secreto propio. Ningún rol de la
--                   app puede escribirla.
--   cerebro_marcas  lo que el dueño marca en la pestaña: hechos, decisiones
--                   (hacer/delegar/matar), notas y encargos a Claude. Lo
--                   escribe el admin con su sesión. La corrida de las 07:30 la
--                   LEE con el MCP de solo lectura.
--   cerebro_historial  versión anterior de cada fila que cambia o se borra.
--
-- Una fila por fecha en cada tabla (primary key). Idempotente.
-- Antes de aplicar: mirar supabase_migrations.schema_migrations; si la 0030
-- ya existe, renumerar.
-- ══════════════════════════════════════════════════════════════════════════

create table if not exists public.cerebro_dias (
  fecha      date primary key,
  data       jsonb not null check (jsonb_typeof(data) = 'object' and length(data::text) <= 300000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by text not null default coalesce(auth.jwt() ->> 'email', 'cerebro-dia')
);
comment on table public.cerebro_dias is 'Cerebro Zaru: el día armado para la pestaña «Mi día» (0030). Lo escribe solo la Edge Function cerebro-dia; lo lee el admin.';

create table if not exists public.cerebro_marcas (
  fecha      date primary key,
  data       jsonb not null default '{}'::jsonb
             check (jsonb_typeof(data) = 'object' and length(data::text) <= 100000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by text not null default coalesce(auth.jwt() ->> 'email', 'sin-sesion')
);
comment on table public.cerebro_marcas is 'Cerebro Zaru: lo que el dueño marca en «Mi día» (hechos, decisiones, notas, encargos a Claude) (0030).';

create table if not exists public.cerebro_historial (
  id       bigint generated always as identity primary key,
  tabla    text not null check (tabla in ('cerebro_dias','cerebro_marcas')),
  fecha    date not null,
  ts       timestamptz not null default now(),
  por      text default coalesce(auth.jwt() ->> 'email', 'cerebro-dia'),
  accion   text not null check (accion in ('UPDATE','DELETE')),
  anterior jsonb not null
);
create index if not exists cerebro_hist_idx on public.cerebro_historial (tabla, fecha, ts);

-- Sellos: updated_at/updated_by los pone la base, no el navegador.
create or replace function public.cerebro_sellar()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  new.updated_by := coalesce(auth.jwt() ->> 'email', case when tg_table_name = 'cerebro_dias' then 'cerebro-dia' else 'sin-sesion' end);
  if tg_op = 'UPDATE' then new.created_at := old.created_at; end if;
  return new;
end $$;

create or replace function public.cerebro_historial_guardar()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.cerebro_historial (tabla, fecha, accion, anterior)
  values (tg_table_name, old.fecha, tg_op, to_jsonb(old));
  return coalesce(new, old);
end $$;
revoke all on function public.cerebro_historial_guardar() from public, anon, authenticated;

drop trigger if exists tr_cerebro_dias_sellar on public.cerebro_dias;
create trigger tr_cerebro_dias_sellar before insert or update on public.cerebro_dias
  for each row execute function public.cerebro_sellar();
drop trigger if exists tr_cerebro_dias_hist on public.cerebro_dias;
create trigger tr_cerebro_dias_hist after update or delete on public.cerebro_dias
  for each row execute function public.cerebro_historial_guardar();

drop trigger if exists tr_cerebro_marcas_sellar on public.cerebro_marcas;
create trigger tr_cerebro_marcas_sellar before insert or update on public.cerebro_marcas
  for each row execute function public.cerebro_sellar();
drop trigger if exists tr_cerebro_marcas_hist on public.cerebro_marcas;
create trigger tr_cerebro_marcas_hist after update or delete on public.cerebro_marcas
  for each row execute function public.cerebro_historial_guardar();


-- ── RLS ───────────────────────────────────────────────────────────────────
-- cerebro_dias: el admin solo lee. La escritura llega por la llave de servicio
--   (Edge Function), que se salta el RLS; ningún rol de la app escribe.
-- cerebro_marcas: el admin lee, crea y cambia. Nadie borra.
-- cerebro_historial: el admin lee. Lo escribe solo el trigger.
alter table public.cerebro_dias      enable row level security;
alter table public.cerebro_dias      force  row level security;
alter table public.cerebro_marcas    enable row level security;
alter table public.cerebro_marcas    force  row level security;
alter table public.cerebro_historial enable row level security;
alter table public.cerebro_historial force  row level security;

drop policy if exists cerebro_dias_leer on public.cerebro_dias;
create policy cerebro_dias_leer on public.cerebro_dias
  for select to authenticated using (public.zaru_rol() = 'admin');

drop policy if exists cerebro_marcas_leer on public.cerebro_marcas;
create policy cerebro_marcas_leer on public.cerebro_marcas
  for select to authenticated using (public.zaru_rol() = 'admin');
drop policy if exists cerebro_marcas_crear on public.cerebro_marcas;
create policy cerebro_marcas_crear on public.cerebro_marcas
  for insert to authenticated with check (public.zaru_rol() = 'admin');
drop policy if exists cerebro_marcas_cambiar on public.cerebro_marcas;
create policy cerebro_marcas_cambiar on public.cerebro_marcas
  for update to authenticated
  using (public.zaru_rol() = 'admin') with check (public.zaru_rol() = 'admin');

drop policy if exists cerebro_hist_leer on public.cerebro_historial;
create policy cerebro_hist_leer on public.cerebro_historial
  for select to authenticated using (public.zaru_rol() = 'admin');

revoke all on public.cerebro_dias, public.cerebro_marcas, public.cerebro_historial from anon, authenticated;
grant select on public.cerebro_dias to authenticated;
grant select, insert, update on public.cerebro_marcas to authenticated;
grant select on public.cerebro_historial to authenticated;


-- Rollback (lo marcado se pierde; respaldar antes con
--   select * from public.cerebro_marcas; select * from public.cerebro_dias;):
--   drop table public.cerebro_historial; drop table public.cerebro_marcas; drop table public.cerebro_dias;
--   drop function public.cerebro_historial_guardar(); drop function public.cerebro_sellar();

-- Registrar en el panel (Database → Migrations), pegándolo junto con este archivo:
-- insert into supabase_migrations.schema_migrations (version, name, statements)
-- values ('0030', 'cerebro_mi_dia', array[$m0030$ <este archivo> $m0030$]);
