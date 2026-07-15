-- Casa Zaru: canal de venta (P&L) + descuento B2B de Jepe
-- Pegar en Supabase → SQL Editor → Run

alter table cotizaciones
  add column if not exists canal    text,      -- web / cesar / jepe (se llena al marcar Ganada)
  add column if not exists b2b_dcto numeric;   -- % extra Casa Zaru Profesionales (solo cotizaciones de Jepe)

comment on column cotizaciones.canal    is 'Canal de la venta al concretar: web / cesar / jepe (para el P&L)';
comment on column cotizaciones.b2b_dcto is 'Descuento Casa Zaru Profesionales aplicado por Jepe (%), null si no aplica';
