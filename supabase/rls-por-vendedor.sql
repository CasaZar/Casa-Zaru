-- ══════════════════════════════════════════════════════════════
-- Casa Zaru · RLS por vendedor (blindaje fila a fila)
--
-- Hasta ahora cualquier cuenta autenticada (admin, César, Jepe)
-- podía leer/editar TODA la tabla cotizaciones llamando directo
-- a la API de Supabase (policies "equipo lee/edita cotizaciones"
-- de supabase/rls-seguridad.sql usaban using (true)). El filtro
-- "cada vendedor ve solo lo suyo" vivía SOLO en el JS del panel
-- (loadDash), que no protege nada si alguien salta el panel y
-- pega directo a la REST API con sus credenciales.
--
-- Esto reemplaza esas dos políticas por unas que reflejan la
-- misma regla de ownerCode/isWeb del código, pero a nivel de
-- base de datos:
--   - admin (hola@casazaru.cl) ve y edita todo.
--   - un vendedor ve/edita sus propias filas (user_email o
--     asignado_a = su correo).
--   - además ve/edita las filas "web" (sin dueño) SALVO que sea
--     un vendedor B2B (Jepe) — los B2B solo ven su propio canal.
--
-- Si se agrega un vendedor B2B nuevo (igual que se agrega en el
-- array VENDEDORES del código), sumar su correo a la lista de
-- exclusión de abajo.
--
-- Requiere haber corrido antes supabase/rls-seguridad.sql.
-- Pegar en Supabase → SQL Editor → Run.
-- ══════════════════════════════════════════════════════════════

drop policy if exists "equipo lee cotizaciones" on cotizaciones;
create policy "equipo lee cotizaciones" on cotizaciones
  for select to authenticated using (
    auth.email() = 'hola@casazaru.cl'
    or user_email = auth.email()
    or asignado_a = auth.email()
    or (
      user_email is null and asignado_a is null
      and auth.email() not in ('jeperomanosorio@gmail.com')
    )
  );

drop policy if exists "equipo edita cotizaciones" on cotizaciones;
create policy "equipo edita cotizaciones" on cotizaciones
  for update to authenticated using (
    auth.email() = 'hola@casazaru.cl'
    or user_email = auth.email()
    or asignado_a = auth.email()
    or (
      user_email is null and asignado_a is null
      and auth.email() not in ('jeperomanosorio@gmail.com')
    )
  ) with check (
    auth.email() = 'hola@casazaru.cl'
    or user_email = auth.email()
    or asignado_a = auth.email()
    or (
      user_email is null and asignado_a is null
      and auth.email() not in ('jeperomanosorio@gmail.com')
    )
  );

-- ══════════════════════════════════════════════════════════════
-- Después de correr esto: probar login como César y como Jepe
-- y confirmar que cada uno sigue viendo sus propios leads (y
-- César también los web) tal como antes. Si a alguno le falta
-- data que antes veía, es señal de que hay filas con
-- user_email/asignado_a en un formato distinto al esperado.
-- ══════════════════════════════════════════════════════════════
