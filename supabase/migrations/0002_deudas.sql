-- ══════════════════════════════════════════════════════════════════════════
-- MIGRACIÓN 0002 · DEUDAS Y CRÉDITOS
--
-- PROYECTO SUPABASE: padnttpgzuotxeipjrry (el de la Gestión)
--
-- Parte de la consolidación de casa-zaru-gastos dentro de la Gestión. De los
-- seis nodos que tenía en Firebase, cinco ya tienen lugar acá:
--
--   proveedores    → tabla proveedores      (migración 0001)
--   registros      → facturas + lineas      (migración 0001)
--   inventario     → tabla inventario       (migración 0001)
--   config.margen  → se elimina: el margen deja de ser un número que se ajusta
--                    a mano y pasa a salir del consumo real por pedido
--   deudas         → esta migración
--
-- Una deuda es el CONTRATO (el crédito con su cuota mensual). Cada cuota que
-- se paga es una fila del mayor con categoría "Créditos y deudas (cuotas)",
-- que ya existe. Por eso acá no hay tabla de cuotas: el mayor ya es el libro
-- de lo que se pagó, y duplicarlo sería tener dos verdades sobre lo mismo.
--
-- Pegar en Supabase → SQL Editor → Run. Es idempotente.
-- ══════════════════════════════════════════════════════════════════════════

create table if not exists deudas (
  id             bigint generated always as identity primary key,
  nombre         text    not null,
  acreedor_id    bigint  references proveedores(id),
  total          integer not null default 0,
  cuota          integer not null default 0,
  saldo_actual   integer not null default 0,
  meses_restantes smallint,
  fecha_inicio   date,
  activa         boolean not null default true,
  notas          text,
  creado_en      timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  -- Un saldo mayor que el total es un error de tipeo, no un caso de negocio.
  constraint saldo_coherente check (saldo_actual >= 0 and saldo_actual <= total)
);

comment on table  deudas is 'Créditos y deudas con cuota mensual. Cada cuota pagada es una fila del mayor, no una fila acá.';
comment on column deudas.acreedor_id  is 'Opcional: solo si el acreedor también es un proveedor con RUT.';
comment on column deudas.saldo_actual is 'Lo que falta por pagar. Se descuenta al registrar la cuota en el mayor.';
comment on column deudas.activa       is 'false = pagada o dada de baja; se conserva para el historial.';

-- Vista con lo derivado, misma idea que v_mayor: las fórmulas viven en SQL.
create or replace view v_deudas with (security_invoker = true) as
select
  d.*,
  p.nombre as acreedor,
  d.total - d.saldo_actual as pagado,
  case when d.total > 0
       then round(((d.total - d.saldo_actual)::numeric / d.total) * 100, 1)
       else 0 end as avance_pct,
  -- Cuántas cuotas quedan según el saldo, para contrastar con lo que se
  -- declaró a mano: si no calzan, alguna cuota no se registró.
  case when d.cuota > 0 then ceil(d.saldo_actual::numeric / d.cuota) else null end as cuotas_por_saldo
from deudas d
left join proveedores p on p.id = d.acreedor_id;

-- ── Seguridad ─────────────────────────────────────────────────────────────
-- Solo admin: son los compromisos financieros de la empresa.
alter table deudas enable row level security;
alter table deudas force  row level security;

drop policy if exists "solo admin deudas" on deudas;
create policy "solo admin deudas" on deudas
  for all to authenticated
  using (zaru_rol() = 'admin') with check (zaru_rol() = 'admin');

create index if not exists idx_deudas_activa on deudas (activa) where activa;
