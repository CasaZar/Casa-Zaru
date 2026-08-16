-- ══════════════════════════════════════════════════════════════
-- Casa Zaru · SEGUIMIENTO v2 — esquema para las fases 2, 3 y 4
-- (spec "Rediseño del panel de seguimiento v2", 16-08-2026)
--
-- DECISIÓN DE COMPATIBILIDAD (difiere del spec §1.2, a propósito):
--   El spec propone reemplazar el enum de estado por 7 valores nuevos.
--   NO lo hacemos: el estado actual ('enviada'/'ganado'/'perdida') está
--   cableado en el panel, la planilla de seguimiento de Google y la app de
--   Gestión. En su lugar, los estados nuevos se DERIVAN de campos:
--     nueva      = enviada y fecha_primer_contacto es null
--     contactada = enviada y fecha_primer_contacto sin respondio
--     activa     = enviada y respondio = true
--     pausada    = enviada y motivo_pausa con próxima fecha
--     cerrada_sin_respuesta = estado 'cerrada' (valor NUEVO, solo lo escribe
--                             el cierre automático de la fase 7)
--   Mismo modelo mental del spec, cero migración de datos, nada se rompe.
--
-- Pegar en Supabase → proyecto "Cotizador Interno" (cmxqorsyxoltrakxawro)
-- → SQL Editor → Run. Seguro de correr dos veces.
-- ══════════════════════════════════════════════════════════════

-- ── 1. Campos nuevos en cotizaciones (spec §1.1) ──
alter table cotizaciones add column if not exists respondio boolean not null default false;
alter table cotizaciones add column if not exists fecha_primera_respuesta timestamptz;
alter table cotizaciones add column if not exists fecha_primer_contacto timestamptz;
alter table cotizaciones add column if not exists cliente_recurrente boolean not null default false;
alter table cotizaciones add column if not exists telefono_valido boolean;
alter table cotizaciones add column if not exists motivo_pausa text;      -- decision_familiar | esperando_obra | comparando | presupuesto
alter table cotizaciones add column if not exists fecha_agendada date;    -- solo para esperando_obra

-- ── 2. Tabla toques (spec §1.3) ──
-- Una fila por click del botón de WhatsApp. Es la base de las métricas
-- nuevas (toques cumplidos vs meta, minutos por toque, toques por venta).
create table if not exists toques (
  id            bigint generated always as identity primary key,
  cotizacion_id uuid not null references cotizaciones(id),
  tipo          text not null check (tipo in ('p1','p2','p3','p4','cadencia','agendado')),
  ts            timestamptz not null default now(),
  hecho_por     text
);
create index if not exists idx_toques_cotizacion on toques (cotizacion_id);
create index if not exists idx_toques_ts on toques (ts);

alter table toques enable row level security;
alter table toques force row level security;

drop policy if exists "equipo lee toques" on toques;
create policy "equipo lee toques" on toques
  for select to authenticated using (true);

drop policy if exists "equipo registra toques" on toques;
create policy "equipo registra toques" on toques
  for insert to authenticated with check (true);

-- Borrar solo el equipo (para el "deshacer" de 30 segundos del spec §5.1)
drop policy if exists "equipo deshace toques" on toques;
create policy "equipo deshace toques" on toques
  for delete to authenticated using (true);
-- anon: nada. El panel de seguimiento siempre corre con sesión iniciada.

-- ── 3. Config del seguimiento (spec §1.4) — una sola fila ──
create table if not exists config_seguimiento (
  id                        int primary key default 1 check (id = 1),
  corte_monto_prioritario   int not null default 400000,
  techo_prioritarios_activos int not null default 60,
  meta_toques_lunes         int not null default 8,
  meta_toques_normal        int not null default 15,
  meta_toques_sabado        int not null default 0,
  dias_cierre_backlog       int not null default 14,
  dias_cierre_cadencia      int not null default 40,
  updated_at                timestamptz not null default now()
);
insert into config_seguimiento (id) values (1) on conflict (id) do nothing;

alter table config_seguimiento enable row level security;
alter table config_seguimiento force row level security;

drop policy if exists "equipo lee config seguimiento" on config_seguimiento;
create policy "equipo lee config seguimiento" on config_seguimiento
  for select to authenticated using (true);

drop policy if exists "solo admin edita config seguimiento" on config_seguimiento;
create policy "solo admin edita config seguimiento" on config_seguimiento
  for update to authenticated
  using (auth.email() = 'hola@casazaru.cl')
  with check (auth.email() = 'hola@casazaru.cl');

-- ── 4. Verificación (correr después) ──
--   select count(*) from toques;                        → 0
--   select corte_monto_prioritario from config_seguimiento; → 400000
--   select respondio, fecha_primer_contacto from cotizaciones limit 1;  → false, null
