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
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- Registro de errores del cliente · Cotizador (23-10-2026)
--
-- Misma idea que supabase/migrations/0021_errores_cliente.sql en Gestión. Acá
-- el cotizador público corre con la llave pública, así que anon PUEDE insertar
-- (solo insertar: ni leer ni borrar). Los límites de largo acotan el abuso y
-- el cliente manda como mucho 20 errores por carga, sin repetir mensaje.
-- Nadie lee por la API salvo la llave secreta; /auditoria lo lee desde el zip
-- del respaldo diario, que descubre la tabla solo. Idempotente.
-- ══════════════════════════════════════════════════════════════════════════

create table if not exists public.errores_cliente (
  id       bigint generated always as identity primary key,
  ts       timestamptz not null default now(),
  app      text not null check (app in ('cotizador','panel','cuenta','prueba')),
  usuario  text default (auth.jwt() ->> 'email'),
  mensaje  text not null check (length(mensaje) between 1 and 2000),
  stack    text check (length(stack) <= 8000),
  url      text check (length(url) <= 500),
  ua       text check (length(ua) <= 300),
  version  text check (length(version) <= 40),
  extra    jsonb check (extra is null or pg_column_size(extra) <= 4000)
);
create index if not exists errores_cliente_ts_idx on public.errores_cliente (ts desc);

alter table public.errores_cliente enable row level security;
alter table public.errores_cliente force row level security;

drop policy if exists errores_cliente_publico_escribe on public.errores_cliente;
create policy errores_cliente_publico_escribe on public.errores_cliente
  for insert to anon, authenticated with check (true);
-- Sin policy de select/update/delete: ni anon ni el equipo leen por la API.

grant insert on public.errores_cliente to anon, authenticated;
revoke select, update, delete on public.errores_cliente from anon, authenticated;

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

-- Rollback: drop function public.errores_cliente_limpiar(); drop table public.errores_cliente;
--           select cron.unschedule('errores-cliente-limpiar');
