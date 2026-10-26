-- ── CANDADO DE PROYECTO (no borrar) ──────────────────────────────────────
-- Este archivo es de GESTIÓN (padnttpgzuotxeipjrry). Si se pega en el SQL
-- Editor de otro proyecto, este bloque falla primero y Postgres descarta el
-- resto del script: no se aplica nada.
do $candado$
begin
  if to_regclass('public.gestion_pedidos') is null then
    raise exception 'PROYECTO EQUIVOCADO: este SQL es de GESTIÓN (padnttpgzuotxeipjrry) y aquí no existe gestion_pedidos. No se aplicó nada.';
  end if;
  if to_regclass('public.b2b_empresas') is null then
    raise exception 'Falta la migración 0019_b2b_cuentas. Correrla primero.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- 0023 · Cuentas empresa: ventana móvil de 12 meses (26-10-2026)
--
-- Antes el acumulado se contaba por ciclos fijos desde `inicio_ciclo` y al
-- cumplirse el año volvía a $0 de golpe, con todo lo comprado en medio. Ahora
-- el acumulado es lo comprado en los ÚLTIMOS 12 MESES contados desde hoy:
-- cada compra deja de contar sola al cumplir un año, el tramo baja de a poco
-- y la regla se explica en una frase. Decisión del dueño, 26-10-2026.
--
-- Cambia solo la vista (y b2b_estado, que la lee). Las tablas quedan igual;
-- `inicio_ciclo` sobrevive como dato histórico pero ya no se usa.
--
-- Columnas nuevas de la vista: `salida_fecha` y `salida_monto` (la compra más
-- antigua de la ventana y cuándo deja de contar). `ciclo_inicio` / `ciclo_fin`
-- se conservan con el mismo nombre para no tocar el JS: ahora son los bordes
-- de la ventana (hace un año → hoy). `dias_ciclo` pasa a ser los días hasta
-- la próxima baja.
--
-- ROLLBACK: volver a crear la vista y b2b_estado con el texto de
-- 0019_b2b_cuentas.sql (sección «Vista» y «Lo que ve el cliente»). Nada más.
-- ══════════════════════════════════════════════════════════════════════════

drop view if exists public.v_b2b_cuentas;

create view public.v_b2b_cuentas with (security_invoker = on) as
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
  public.b2b_tramo(s.acumulado) as tramo_pct,
  greatest(0, 1500000 - s.acumulado)::bigint as falta_2,
  greatest(0, 3000000 - s.acumulado)::bigint as falta_5,
  -- la compra más antigua de la ventana deja de contar al cumplir un año
  (s.mas_antigua + interval '1 year')::date as salida_fecha,
  (select coalesce(sum(k2.monto), 0)::bigint from public.b2b_compras k2
    where k2.empresa_id = e.id and not k2.anulada and k2.fecha = s.mas_antigua) as salida_monto,
  ((s.mas_antigua + interval '1 year')::date - current_date)::int as dias_ciclo
from public.b2b_empresas e
cross join v
join s on s.id = e.id;

grant select on public.v_b2b_cuentas to authenticated;
revoke all on public.v_b2b_cuentas from anon;

-- Ya no se usa: el ciclo no tiene fecha de corte.
drop function if exists public.b2b_ciclo(date, date);
comment on column public.b2b_empresas.inicio_ciclo is 'Histórico (0019). Desde 0023 el acumulado es ventana móvil de 12 meses y esta fecha no se usa.';

create or replace function public.b2b_estado(p_token text)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'razon_social', v.razon_social, 'rut', v.rut, 'contacto', v.contacto,
    'ciclo_inicio', v.ciclo_inicio, 'ciclo_fin', v.ciclo_fin, 'dias_ciclo', v.dias_ciclo,
    'salida_fecha', v.salida_fecha, 'salida_monto', v.salida_monto,
    'acumulado', v.acumulado, 'tramo_pct', v.tramo_pct, 'falta_2', v.falta_2, 'falta_5', v.falta_5,
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

-- Registro en el panel (Database → Migrations). Sin CLI hay que hacerlo a mano:
-- insert into supabase_migrations.schema_migrations (version, name, statements)
-- values ('0023', 'b2b_ventana_movil', array[$mig$ <este archivo> $mig$]);
