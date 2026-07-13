-- Panel de Cotizaciones: seguimiento, ventas y vendedores
-- Pegar completo en Supabase → SQL Editor → Run

-- 1. Columnas nuevas en cotizaciones
alter table cotizaciones
  add column if not exists seg_etapa smallint default 0,
  add column if not exists seg_proxima date,
  add column if not exists seg_historial jsonb default '[]'::jsonb,
  add column if not exists asignado_a text,
  add column if not exists motivo_perdida text,
  add column if not exists monto_cierre numeric;

comment on column cotizaciones.seg_etapa is 'Toques de seguimiento hechos (0-5, cadencia dias 1/3/7/14/30)';
comment on column cotizaciones.seg_proxima is 'Fecha del proximo seguimiento; null = se calcula por cadencia desde fecha_creacion';
comment on column cotizaciones.seg_historial is 'Historial de toques: [{etapa, fecha, nota}]';
comment on column cotizaciones.asignado_a is 'Email del vendedor responsable (para cotizaciones web)';
comment on column cotizaciones.monto_cierre is 'Monto final real de la venta al concretar';

-- 2. Tabla de vendedores
create table if not exists vendedores (
  email  text primary key,
  nombre text not null,
  activo boolean default true,
  creado timestamptz default now()
);

alter table vendedores enable row level security;

-- Cualquier usuario logueado puede leer la lista (para asignaciones y nombres)
drop policy if exists "vendedores select autenticados" on vendedores;
create policy "vendedores select autenticados" on vendedores
  for select to authenticated using (true);

-- Solo el admin agrega o modifica vendedores
drop policy if exists "vendedores insert admin" on vendedores;
create policy "vendedores insert admin" on vendedores
  for insert to authenticated
  with check (auth.email() = 'hola@casazaru.cl');

drop policy if exists "vendedores update admin" on vendedores;
create policy "vendedores update admin" on vendedores
  for update to authenticated
  using (auth.email() = 'hola@casazaru.cl');

-- 3. Primer vendedor: César
insert into vendedores (email, nombre) values ('crodriguez.casazaru@gmail.com', 'César')
  on conflict (email) do nothing;

-- 4. Recordatorio (manual, no SQL):
--    Crear la cuenta de César en Supabase → Authentication → Users → Add user,
--    con el correo crodriguez.casazaru@gmail.com (el mismo de la tabla vendedores).
