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
-- base de datos.
--
-- ── CORRECCIÓN 2026-07-31 ──
-- La primera versión de este archivo comparaba user_email contra
-- auth.email() directo, y con eso César veía "0 cotizaciones" en
-- su propio panel (el 31 de julio, pero el problema NO era la
-- fecha). La causa real: en el array VENDEDORES del código, César
-- tiene DOS correos distintos —
--   email:    'crodriguez.casazaru@gmail.com'  (con el que inicia sesión)
--   srcEmail: 'hola@casazaru.cl'                (el que queda guardado
--                                                 en user_email de CADA
--                                                 cotización que entra
--                                                 por su link ?src=k7m2)
-- El SELECT filtraba por auth.email() = user_email, así que ninguna
-- cotización de César (todas con user_email = 'hola@casazaru.cl')
-- calzaba con su sesión (auth.email() = 'crodriguez.casazaru@gmail.com').
-- Las cotizaciones "Registrar venta" desde el panel sí quedan con
-- user_email = su email de login, así que esas SÍ se veían — por
-- eso el error no era "cero total", sino "cero en su cola normal".
--
-- Esta versión compara contra TODOS los correos que el código usa
-- para etiquetar a cada vendedor (ver VENDEDORES en cotizador-clientes.html).
-- Si se agrega un vendedor nuevo o le cambian el email/srcEmail en el
-- código, hay que reflejar el mismo cambio acá.
-- ══════════════════════════════════════════════════════════════

drop policy if exists "equipo lee cotizaciones" on cotizaciones;
create policy "equipo lee cotizaciones" on cotizaciones
  for select to authenticated using (
    auth.email() = 'hola@casazaru.cl'                    -- admin: ve todo
    or asignado_a = auth.email()                          -- fila asignada directo a esta cuenta
    or (                                                   -- César: propias (por login o por srcEmail) + web
      auth.email() = 'crodriguez.casazaru@gmail.com'
      and (
        user_email = 'crodriguez.casazaru@gmail.com'
        or user_email = 'hola@casazaru.cl'
        or (user_email is null and asignado_a is null)
      )
    )
    or (                                                   -- Jepe (B2B): solo su propio canal, sin los web
      auth.email() = 'jeperomanosorio@gmail.com'
      and user_email = 'jeperomanosorio@gmail.com'
    )
  );

drop policy if exists "equipo edita cotizaciones" on cotizaciones;
create policy "equipo edita cotizaciones" on cotizaciones
  for update to authenticated using (
    auth.email() = 'hola@casazaru.cl'
    or asignado_a = auth.email()
    or (
      auth.email() = 'crodriguez.casazaru@gmail.com'
      and (
        user_email = 'crodriguez.casazaru@gmail.com'
        or user_email = 'hola@casazaru.cl'
        or (user_email is null and asignado_a is null)
      )
    )
    or (
      auth.email() = 'jeperomanosorio@gmail.com'
      and user_email = 'jeperomanosorio@gmail.com'
    )
  ) with check (
    auth.email() = 'hola@casazaru.cl'
    or asignado_a = auth.email()
    or (
      auth.email() = 'crodriguez.casazaru@gmail.com'
      and (
        user_email = 'crodriguez.casazaru@gmail.com'
        or user_email = 'hola@casazaru.cl'
        or (user_email is null and asignado_a is null)
      )
    )
    or (
      auth.email() = 'jeperomanosorio@gmail.com'
      and user_email = 'jeperomanosorio@gmail.com'
    )
  );

-- ══════════════════════════════════════════════════════════════
-- Después de correr esto: entrar como César (panel?panel=cesar)
-- y confirmar que "Mis cotizaciones" ya NO da 0 — debería mostrar
-- lo mismo que mostraba antes de correr rls-por-vendedor.sql la
-- primera vez. Probar también como Jepe.
-- ══════════════════════════════════════════════════════════════
