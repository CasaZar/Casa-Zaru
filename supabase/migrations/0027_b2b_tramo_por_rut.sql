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
-- 0027 · Tramo de la cuenta empresa por RUT, para el cotizador (03-11-2026)
--
-- El vendedor escribe el RUT en «Extras» del cotizador y el precio sale con
-- el descuento de la cuenta. El cotizador vive en otro proyecto y no tiene
-- sesión de Gestión, así que pregunta con la llave pública a esta función.
--
-- Devuelve SOLO razón social y tramo (0, 2 o 5): nunca montos, compras,
-- contacto ni token. Quien sepa un RUT puede ver si es cuenta y su tramo;
-- se aceptó así el 03-11-2026 (el tramo no dice cuánto compró).
-- El tramo sale de v_b2b_cuentas: la fórmula sigue viviendo en un solo lugar.
--
-- Antes de aplicar: mirar supabase_migrations.schema_migrations; si la 0027
-- ya existe, renumerar. Idempotente.
-- ══════════════════════════════════════════════════════════════════════════

create or replace function public.b2b_tramo_rut(p_rut text)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('razon_social', v.razon_social, 'tramo_pct', v.tramo_pct)
  from public.v_b2b_cuentas v
  where v.rut = public.b2b_norm_rut(p_rut) and v.activa
  limit 1
$$;
comment on function public.b2b_tramo_rut(text) is 'Cotizador: razón social y tramo (0/2/5) de una cuenta empresa activa por RUT. Nada más.';
revoke all on function public.b2b_tramo_rut(text) from public;
grant execute on function public.b2b_tramo_rut(text) to anon, authenticated;


-- Rollback: drop function public.b2b_tramo_rut(text);

-- Registrar en el panel (Database → Migrations), pegándolo junto con este archivo:
-- insert into supabase_migrations.schema_migrations (version, name, statements)
-- values ('0027', 'b2b_tramo_por_rut', array[$m0027$ <este archivo> $m0027$]);
