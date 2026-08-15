-- ══════════════════════════════════════════════════════════════
-- Casa Zaru · MANUAL DE VALORES DEL COTIZADOR
--
-- Una sola tabla clave→valor (jsonb) donde viven los precios y parámetros
-- del cotizador: $/m² por producto, multiplicadores de 8 cm, reborde,
-- $/pulgada por especie, bases de mesa por tramo, y los generales
-- (HH, IVA, margen, comisión).
--
-- El cotizador trae estos valores GRABADOS EN EL CÓDIGO como respaldo:
-- si esta tabla no existe o no responde, funciona igual que siempre.
-- Cuando existe, lo que diga la tabla MANDA sobre el código, y por eso
-- editar un valor en la pestaña "Manual" del panel cambia el precio al
-- instante, sin tocar el código ni hacer deploy.
--
-- Seguridad:
--   · Leer: cualquiera (los precios son públicos: están en el HTML).
--   · Escribir: SOLO la cuenta admin (hola@casazaru.cl), server-side.
--     Un vendedor logueado NO puede cambiar precios ni por API directa.
--
-- Pegar completo en Supabase → proyecto "Cotizador Interno"
-- (cmxqorsyxoltrakxawro) → SQL Editor → Run.
-- ══════════════════════════════════════════════════════════════

create table if not exists cotizador_valores (
  clave       text primary key,
  valor       jsonb not null,
  updated_at  timestamptz not null default now(),
  updated_by  text
);

alter table cotizador_valores enable row level security;
alter table cotizador_valores force row level security;

drop policy if exists "todos leen valores" on cotizador_valores;
create policy "todos leen valores" on cotizador_valores
  for select to anon, authenticated using (true);

drop policy if exists "solo admin escribe valores" on cotizador_valores;
create policy "solo admin escribe valores" on cotizador_valores
  for insert to authenticated
  with check (auth.email() = 'hola@casazaru.cl');

drop policy if exists "solo admin actualiza valores" on cotizador_valores;
create policy "solo admin actualiza valores" on cotizador_valores
  for update to authenticated
  using (auth.email() = 'hola@casazaru.cl')
  with check (auth.email() = 'hola@casazaru.cl');

-- Sin DELETE para nadie: un valor se corrige, no se borra.

-- ── Verificación (correr después) ──
--   select count(*) from cotizador_valores;   → 0 filas (se llenan desde el panel)
-- La pestaña "Manual" del panel admin detecta la tabla y deja de mostrar el aviso.
