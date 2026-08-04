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
-- ── CORRECCIÓN 2026-07-31 ──
-- La primera versión de este archivo comparaba user_email contra
-- auth.email() directo, y con eso César veía "0 cotizaciones" en
-- su propio panel. La causa real: en VENDEDORES (código), César
-- tiene DOS correos distintos — email (con el que inicia sesión) y
-- srcEmail (el que queda guardado en user_email de cada cotización
-- que entra por su link ?src=k7m2). Corregido: ahora compara contra
-- ambos correos de cada vendedor.
--
-- ── CORRECCIÓN 2026-08-03 ──
-- Clientes de César aparecían también en el panel de Jepe y viceversa.
-- Causa: existen DOS archivos SQL históricos con nombres de policy
-- LIGERAMENTE distintos — "equipo lee cotizaciones" (rls-seguridad.sql,
-- el que se corrió) vs "equipo lee cotizacion" sin la "s" final
-- (seguridad-rls.sql, un borrador anterior). Si alguna vez se corrió
-- también ese borrador, quedó una policy vieja con "using (true)"
-- (acceso total) bajo un nombre que este archivo nunca tocaba —
-- Postgres combina todas las policies de una tabla con OR, así que
-- esa policy vieja por sí sola bastaba para que cualquier cuenta
-- logueada viera TODO, sin importar lo restrictiva que fuera esta.
-- Esta versión borra explícitamente ambas variantes de nombre (con
-- y sin "s") antes de crear las policies correctas, para que no
-- pueda quedar ninguna policy vieja viva por accidente.
--
-- Esta versión compara contra TODOS los correos que el código usa
-- para etiquetar a cada vendedor (ver VENDEDORES en cotizador-clientes.html).
-- Si se agrega un vendedor nuevo o le cambian el email/srcEmail en el
-- código, hay que reflejar el mismo cambio acá.
-- ══════════════════════════════════════════════════════════════

-- ── PASO 1: diagnóstico — ver TODAS las policies activas hoy ──
-- (correr esto primero y mirar el resultado si quieres confirmar
--  la causa antes de aplicar el fix; no es obligatorio, el paso 2
--  limpia igual cualquier nombre viejo que encuentre)
select policyname, cmd, roles, qual, with_check
from pg_policies
where tablename = 'cotizaciones';

-- ── PASO 2: limpieza total de nombres viejos (con y sin "s") ──
drop policy if exists "equipo lee cotizaciones" on cotizaciones;
drop policy if exists "equipo lee cotizacion" on cotizaciones;
drop policy if exists "equipo edita cotizaciones" on cotizaciones;
drop policy if exists "equipo edita cotizacion" on cotizaciones;

-- ── PASO 3: crear las policies correctas ──
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

-- ── PASO 4: verificación — correr de nuevo el select de arriba ──
-- Ahora debería listar SOLO "equipo lee cotizaciones" y "equipo edita
-- cotizaciones" (más "publico inserta cotizacion" y las de insert de
-- equipo) — si aparece cualquier otro nombre parecido con qual = "true",
-- avísame el nombre exacto para borrarlo también.
select policyname, cmd, roles, qual, with_check
from pg_policies
where tablename = 'cotizaciones';

-- ══════════════════════════════════════════════════════════════
-- Después de correr esto: entrar como César y como Jepe y confirmar
-- que cada uno ve SOLO lo suyo (+ los web para César, que no es B2B).
-- ══════════════════════════════════════════════════════════════
