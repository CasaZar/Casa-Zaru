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
-- 0021 · Registro de errores del cliente (23-10-2026)
--
-- Contrato de confiabilidad: «los errores del cliente (window.onerror) se
-- registran en una tabla y se revisan en /auditoria». La app de Gestión
-- (index.html) manda acá cada error no capturado del navegador: mensaje,
-- stack, URL, navegador y quién estaba conectado.
--
--   errores_cliente            una fila por error. Escribe cualquier usuario
--                              con sesión; lee y borra solo el admin. La llave
--                              pública no tiene nada (como en todo gestion_*).
--   v_errores_cliente_7d       lo que mira la auditoría: últimos 7 días
--                              agrupados por mensaje.
--   errores_cliente_limpiar()  borra lo de más de 90 días. Si pg_cron está,
--                              corre los lunes 04:15 UTC.
--
-- El respaldo diario (gestion-respaldo-v2) descubre la tabla solo, así que
-- /auditoria lee los errores desde el JSON de Drive sin llave admin.
-- Idempotente.
-- ══════════════════════════════════════════════════════════════════════════

create table if not exists public.errores_cliente (
  id       bigint generated always as identity primary key,
  ts       timestamptz not null default now(),
  app      text not null check (length(app) between 1 and 20),       -- 'gestion', 'copiloto', 'prueba'…
  usuario  text default (auth.jwt() ->> 'email'),
  mensaje  text not null check (length(mensaje) between 1 and 2000),
  stack    text check (length(stack) <= 8000),
  url      text check (length(url) <= 500),
  ua       text check (length(ua) <= 300),
  version  text check (length(version) <= 40),
  extra    jsonb
);
create index if not exists errores_cliente_ts_idx on public.errores_cliente (ts desc);

alter table public.errores_cliente enable row level security;
alter table public.errores_cliente force row level security;

drop policy if exists errores_cliente_escribir on public.errores_cliente;
create policy errores_cliente_escribir on public.errores_cliente
  for insert to authenticated with check (es_usuario());
drop policy if exists errores_cliente_leer on public.errores_cliente;
create policy errores_cliente_leer on public.errores_cliente
  for select to authenticated using (es_admin());
drop policy if exists errores_cliente_borrar on public.errores_cliente;
create policy errores_cliente_borrar on public.errores_cliente
  for delete to authenticated using (es_admin());

grant insert, select, delete on public.errores_cliente to authenticated;
revoke all on public.errores_cliente from anon;

create or replace view public.v_errores_cliente_7d with (security_invoker = on) as
select app, left(mensaje, 160) as mensaje, count(*)::int as veces,
       max(ts) as ultimo, min(ts) as primero,
       count(distinct usuario)::int as usuarios
from public.errores_cliente
where ts >= now() - interval '7 days'
group by app, left(mensaje, 160)
order by veces desc, ultimo desc;
grant select on public.v_errores_cliente_7d to authenticated;
revoke all on public.v_errores_cliente_7d from anon;

create or replace function public.errores_cliente_limpiar()
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare n integer;
begin
  delete from public.errores_cliente where ts < now() - interval '90 days';
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.errores_cliente_limpiar() from public, anon, authenticated;

do $$
begin
  if to_regnamespace('cron') is not null then
    perform cron.schedule('errores-cliente-limpiar', '15 4 * * 1', 'select public.errores_cliente_limpiar()');
  end if;
end $$;

-- Rollback: drop view public.v_errores_cliente_7d; drop function public.errores_cliente_limpiar();
--           drop table public.errores_cliente; select cron.unschedule('errores-cliente-limpiar');

-- Registrar en el panel (Database → Migrations), pegándolo junto con este archivo:
-- insert into supabase_migrations.schema_migrations (version, name, statements)
-- values ('0021', 'errores_cliente', array[$m0021$ <este archivo> $m0021$]);
