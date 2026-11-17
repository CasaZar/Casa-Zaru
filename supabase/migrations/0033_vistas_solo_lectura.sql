-- ── CANDADO DE PROYECTO (no borrar) ──────────────────────────────────────
-- Este archivo es de GESTIÓN (padnttpgzuotxeipjrry). Si se pega en el SQL
-- Editor de otro proyecto, este bloque falla primero y Postgres descarta el
-- resto del script: no se aplica nada.
do $candado$
begin
  if to_regclass('public.gestion_pedidos') is null then
    raise exception 'PROYECTO EQUIVOCADO: este SQL es de GESTIÓN (padnttpgzuotxeipjrry) y aquí no existe gestion_pedidos. No se aplicó nada.';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '0032') then
    raise exception 'FALTA LA 0032 en schema_migrations: revisar el orden antes de seguir. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- 0033 · Vistas de solo lectura (17-11-2026)
--
-- Cierra el P077 (gestion_clientes) con la decisión del usuario del 17-11:
-- la vista SIGUE legible para todo usuario con sesión (el vendedor arma su
-- pestaña Clientes con ella: contacto, dirección, RUT y etiqueta de envío,
-- sin montos; ver loadClientesSeguro en index.html), pero nadie escribe a
-- través de ella. Hoy authenticated tenía INSERT/UPDATE/DELETE, y como la
-- vista corre como su dueño (security_invoker=off) esa escritura podía pasar
-- por encima del RLS solo_admin de gestion_finanzas.
--
-- Lo mismo para todas las vistas de public: ninguna app escribe por una vista
-- (buscado en index.html: sbInsert/sbUpdate/sbDelete van siempre a tablas).
-- Las vistas quedan solo con SELECT para authenticated.
--
-- No cambia ni borra ninguna fila. Idempotente. Rollback al final.
--
-- APLICADA el 17-11-2026 en el SQL Editor de Gestión. Verificación:
-- vistas_escribibles 0, gestion_clientes SELECT true (security_invoker=off,
-- como antes), última 0033. Las 10 vistas quedan solo con SELECT.
-- ══════════════════════════════════════════════════════════════════════════

do $m0033$
declare r record;
begin
  for r in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'public' and c.relkind in ('v','m') loop
    execute format('revoke insert, update, delete on public.%I from authenticated', r.relname);
  end loop;
end
$m0033$;

-- Registro
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('0033', 'vistas_solo_lectura', array[
  'revoke insert, update, delete on <todas las vistas de public> from authenticated;'
])
on conflict (version) do nothing;

-- Verificación: vistas_escribibles = 0, clientes_select = true,
-- clientes_invoker = security_invoker=off, última 0033.
with tv as (
  select c.oid, c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('v','m'))
select
  (select count(*) from tv cross join unnest(array['insert','update','delete']) p
     where has_table_privilege('authenticated', tv.oid, p))                               as vistas_escribibles,
  has_table_privilege('authenticated', 'public.gestion_clientes'::regclass, 'select')     as clientes_select,
  (select array_to_string(reloptions, ',') from pg_class
     where oid = 'public.gestion_clientes'::regclass)                                     as clientes_invoker,
  (select max(version) from supabase_migrations.schema_migrations)                        as ultima_migracion;

-- ── ROLLBACK (no correr junto con lo de arriba) ──────────────────────────
-- Estado leído el 17-11 antes de aplicar:
-- grant insert, update, delete on public.gestion_clientes, public.v_b2b_cuentas,
--   public.v_costo_pedido, public.v_documentos_recibidos_pendientes,
--   public.v_errores_cliente_7d, public.v_facturas, public.v_inventario,
--   public.v_madera_mes, public.v_mayor to authenticated;
-- delete from supabase_migrations.schema_migrations where version = '0033';
