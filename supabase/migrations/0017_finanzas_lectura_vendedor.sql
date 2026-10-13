-- ── CANDADO DE PROYECTO (no borrar) ──────────────────────────────────────
-- Este archivo es de GESTIÓN (padnttpgzuotxeipjrry). Si se pega en el SQL
-- Editor de otro proyecto, este bloque falla primero y Postgres descarta el
-- resto del script: no se aplica nada.
do $candado$
begin
  if to_regclass('public.gestion_pedidos') is null then
    raise exception 'PROYECTO EQUIVOCADO: este SQL es de GESTIÓN (padnttpgzuotxeipjrry) y aquí no existe gestion_pedidos. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- 0017 · Finanzas en SOLO LECTURA para el rol vendedor (13-10-2026)
--
-- Pedido del dueño: que César pueda ver Finanzas para saber qué pagos están
-- pendientes, sin poder modificar nada.
--
-- Hasta hoy gestion_finanzas era solo_admin para todo. Acá se agrega UNA
-- política nueva, únicamente de SELECT, para quien tenga rol 'vendedor' en
-- gestion_usuarios. No se toca la política existente ni se agrega ninguna de
-- insert / update / delete: el vendedor sigue sin poder escribir aunque fuerce
-- la pantalla, porque para escribir no hay política que lo deje pasar.
--
-- El taller NO entra: sigue sin ver Finanzas.
-- Costos y Pixel tampoco se abren: siguen solo_admin.
--
-- Para deshacerlo:  drop policy finanzas_leer_vendedor on public.gestion_finanzas;
-- Idempotente.
-- ══════════════════════════════════════════════════════════════════════════

-- security definer: gestion_usuarios tiene su propio RLS, y la política no
-- puede depender de que el vendedor pueda leer esa tabla entera.
create or replace function public.es_vendedor()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.gestion_usuarios u
     where lower(u.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
       and u.rol = 'vendedor'
  );
$$;

revoke all on function public.es_vendedor() from public;
grant execute on function public.es_vendedor() to authenticated;

drop policy if exists finanzas_leer_vendedor on public.gestion_finanzas;
create policy finanzas_leer_vendedor on public.gestion_finanzas
  for select to authenticated using (public.es_vendedor());

grant select on public.gestion_finanzas to authenticated;
