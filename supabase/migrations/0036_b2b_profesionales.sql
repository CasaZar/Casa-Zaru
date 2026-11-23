-- ── CANDADO DE PROYECTO (no borrar) ──────────────────────────────────────
-- Este archivo es de GESTIÓN (padnttpgzuotxeipjrry). Si se pega en el SQL
-- Editor de otro proyecto, este bloque falla primero y Postgres descarta el
-- resto del script: no se aplica nada.
do $candado$
begin
  if to_regclass('public.gestion_pedidos') is null then
    raise exception 'PROYECTO EQUIVOCADO: este SQL es de GESTIÓN (padnttpgzuotxeipjrry) y aquí no existe gestion_pedidos. No se aplicó nada.';
  end if;
  if to_regclass('public.v_b2b_cuentas') is null then
    raise exception 'Falta la migración 0019/0023 (v_b2b_cuentas). Correrla primero.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- 0036 · Cuentas de profesionales: parten en el primer tramo (23-11-2026)
--
-- Decisión del dueño, 23-11-2026: todo profesional (arquitecto, diseñador)
-- tiene su Cuenta Casa Zaru en el primer tramo desde la primera compra
-- (2 % → «7 % con transferencia»), sin esperar los $1.500.000. Sube al 5 %
-- (10 % con transferencia) igual que cualquier cuenta, sobre $3.000.000.
--
-- Una marca `profesional` en b2b_empresas. La vista calcula el tramo con
-- greatest(tramo por monto, 2 si es profesional), así b2b_tramo_rut (el
-- cotizador aplica el descuento solo) y b2b_estado (la página del cliente)
-- la siguen sin cambiar su código: la fórmula vive en un solo lugar.
-- Para un profesional, falta_2 = 0 (ya está en ese tramo).
--
-- La vista se reemplaza con CREATE OR REPLACE agregando `profesional` AL
-- FINAL (Postgres lo permite) para no romper a quien la lea.
--
-- Antes de aplicar: mirar supabase_migrations.schema_migrations; si la 0036
-- ya existe, renumerar. Idempotente.
--
-- ROLLBACK:
--   drop view public.v_b2b_cuentas;  -- y recrearla con el texto de 0023
--   (b2b_estado y b2b_tramo_rut son SQL sin dependencia registrada: siguen)
--   alter table public.b2b_empresas drop column profesional;
--   y recrear b2b_estado con el texto de 0023.
-- ══════════════════════════════════════════════════════════════════════════

alter table public.b2b_empresas
  add column if not exists profesional boolean not null default false;
comment on column public.b2b_empresas.profesional is
  'Arquitecto/diseñador: la cuenta parte en el tramo 2 % aunque no tenga compras (0036, 23-11-2026).';

create or replace view public.v_b2b_cuentas with (security_invoker = on) as
with v as (
  select (current_date - interval '1 year' + interval '1 day')::date as desde,
         current_date as hasta
), s as (
  select e.id,
    coalesce(sum(k.monto) filter (where not k.anulada and k.fecha >= v.desde), 0)::bigint as acumulado,
    coalesce(sum(k.monto) filter (where not k.anulada), 0)::bigint               as total_historico,
    count(*) filter (where not k.anulada and k.tipo = 'FACTURA')::int             as n_facturas,
    max(k.fecha) filter (where not k.anulada and k.tipo = 'FACTURA')              as ultima_compra,
    min(k.fecha) filter (where not k.anulada and k.fecha >= v.desde and k.monto > 0) as mas_antigua
  from public.b2b_empresas e
  cross join v
  left join public.b2b_compras k on k.empresa_id = e.id
  group by e.id
)
select e.id, e.rut, e.razon_social, e.contacto, e.celular, e.email, e.giro, e.comuna,
  e.inicio_ciclo, e.token, e.activa, e.notas, e.creado, e.creado_por,
  v.desde as ciclo_inicio, v.hasta as ciclo_fin,
  s.acumulado, s.total_historico, s.n_facturas, s.ultima_compra,
  -- profesional: nunca menos que el primer tramo
  greatest(public.b2b_tramo(s.acumulado), case when e.profesional then 2 else 0 end) as tramo_pct,
  case when e.profesional then 0 else greatest(0, 1500000 - s.acumulado) end::bigint as falta_2,
  greatest(0, 3000000 - s.acumulado)::bigint as falta_5,
  (s.mas_antigua + interval '1 year')::date as salida_fecha,
  (select coalesce(sum(k2.monto), 0)::bigint from public.b2b_compras k2
    where k2.empresa_id = e.id and not k2.anulada and k2.fecha = s.mas_antigua) as salida_monto,
  ((s.mas_antigua + interval '1 year')::date - current_date)::int as dias_ciclo,
  e.profesional
from public.b2b_empresas e
cross join v
join s on s.id = e.id;

grant select on public.v_b2b_cuentas to authenticated;
revoke all on public.v_b2b_cuentas from anon;

-- La página del cliente también sabe si es cuenta de profesional (para el texto).
create or replace function public.b2b_estado(p_token text)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'razon_social', v.razon_social, 'rut', v.rut, 'contacto', v.contacto,
    'ciclo_inicio', v.ciclo_inicio, 'ciclo_fin', v.ciclo_fin, 'dias_ciclo', v.dias_ciclo,
    'salida_fecha', v.salida_fecha, 'salida_monto', v.salida_monto,
    'acumulado', v.acumulado, 'tramo_pct', v.tramo_pct, 'falta_2', v.falta_2, 'falta_5', v.falta_5,
    'profesional', v.profesional,
    'compras', coalesce((
      select jsonb_agg(jsonb_build_object('fecha', k.fecha, 'detalle', k.detalle, 'folio', k.folio, 'monto', k.monto, 'tipo', k.tipo) order by k.fecha desc)
      from public.b2b_compras k
      where k.empresa_id = v.id and not k.anulada and k.fecha between v.ciclo_inicio and v.ciclo_fin), '[]'::jsonb)
  )
  from public.v_b2b_cuentas v
  where v.token = p_token and v.activa and length(p_token) >= 16
  limit 1
$$;
revoke all on function public.b2b_estado(text) from public;
grant execute on function public.b2b_estado(text) to anon, authenticated;

-- Registrar en el panel (Database → Migrations), pegándolo junto con este archivo:
-- insert into supabase_migrations.schema_migrations (version, name, statements)
-- values ('0036', 'b2b_profesionales', array[$m0036$ <este archivo> $m0036$]);
