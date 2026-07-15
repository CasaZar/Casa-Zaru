-- ══════════════════════════════════════════════════════════════
-- Casa Zaru · SEGURIDAD RLS (paso 3/3)
-- Bloquea que la clave pública lea/edite/borre datos de clientes.
-- El cotizador público solo puede INSERTAR cotizaciones y crear links.
-- El equipo (logueado) lee y edita. Los links compartidos y la
-- numeración funcionan por funciones seguras, sin abrir la tabla.
-- Pegar completo en Supabase → SQL Editor → Run.
-- ══════════════════════════════════════════════════════════════

-- ── 1. cotizaciones ──
alter table cotizaciones enable row level security;

drop policy if exists "publico inserta cotizacion" on cotizaciones;
create policy "publico inserta cotizacion" on cotizaciones
  for insert to anon with check (true);

drop policy if exists "equipo lee cotizaciones" on cotizaciones;
create policy "equipo lee cotizaciones" on cotizaciones
  for select to authenticated using (true);

drop policy if exists "equipo edita cotizaciones" on cotizaciones;
create policy "equipo edita cotizaciones" on cotizaciones
  for update to authenticated using (true) with check (true);

drop policy if exists "equipo inserta cotizaciones" on cotizaciones;
create policy "equipo inserta cotizaciones" on cotizaciones
  for insert to authenticated with check (true);

-- ── 2. quote_links (links compartidos con el cliente) ──
alter table quote_links enable row level security;

drop policy if exists "publico crea link" on quote_links;
create policy "publico crea link" on quote_links
  for insert to anon with check (true);
-- (sin SELECT para anon: la lectura va por función get_quote_link)

-- ── 3. Función: leer un link compartido por su token (sin abrir la tabla) ──
create or replace function get_quote_link(tok text)
returns jsonb
language sql
security definer
set search_path = public
as $$ select data from quote_links where token = tok limit 1 $$;
grant execute on function get_quote_link(text) to anon;

-- ── 4. Función: siguiente número de cotización (sin que el público lea la tabla) ──
create or replace function next_quote_number(k text)
returns text
language sql
security definer
set search_path = public
as $$
  select 'N° CL-' || k || '-' || lpad(
    (coalesce(max((regexp_replace(numero, '^.*-', ''))::int), 0) + 1)::text, 3, '0')
  from cotizaciones
  where numero like 'N° CL-' || k || '-%'
    and regexp_replace(numero, '^.*-', '') ~ '^[0-9]+$'
$$;
grant execute on function next_quote_number(text) to anon;
