-- ============================================================
-- SEGURIDAD: activar RLS en Supabase (Casa Zaru)
-- NO ejecutar hasta que:
--   1) existan las cuentas de Supabase Auth (César + admin), y
--   2) el panel tenga el login desplegado.
-- Ejecutar en Supabase → SQL Editor → Run.
-- ============================================================

-- 1) COTIZACIONES: el público SOLO puede insertar. Leer/editar = equipo logueado.
alter table cotizaciones enable row level security;

drop policy if exists "publico inserta cotizacion" on cotizaciones;
create policy "publico inserta cotizacion" on cotizaciones
  for insert to anon with check (true);

drop policy if exists "equipo lee cotizacion" on cotizaciones;
create policy "equipo lee cotizacion" on cotizaciones
  for select to authenticated using (true);

drop policy if exists "equipo edita cotizacion" on cotizaciones;
create policy "equipo edita cotizacion" on cotizaciones
  for update to authenticated using (true) with check (true);

drop policy if exists "equipo inserta cotizacion" on cotizaciones;
create policy "equipo inserta cotizacion" on cotizaciones
  for insert to authenticated with check (true);

-- 2) QUOTE_LINKS: el público crea el link, pero NO puede leer la tabla completa.
--    La lectura del link compartido va por una función que devuelve solo ese token.
alter table quote_links enable row level security;

drop policy if exists "publico crea link" on quote_links;
create policy "publico crea link" on quote_links
  for insert to anon with check (true);

create or replace function get_quote_link(tok text)
returns jsonb language sql security definer set search_path = public
as $$ select data from quote_links where token = tok limit 1 $$;

grant execute on function get_quote_link(text) to anon, authenticated;

-- ============================================================
-- Después de correr esto, la clave pública (anon) YA NO puede leer
-- la lista de clientes. El panel funciona solo con login.
-- ============================================================
