-- ── CANDADO DE PROYECTO (no borrar) ──────────────────────────────────────
-- Este archivo es de GESTIÓN (padnttpgzuotxeipjrry). Si se pega en el SQL
-- Editor de otro proyecto, este bloque falla primero y Postgres descarta el
-- resto del script: no se aplica nada.
do $candado$
begin
  if to_regclass('public.gestion_pedidos') is null then
    raise exception 'PROYECTO EQUIVOCADO: este SQL es de GESTIÓN (padnttpgzuotxeipjrry) y aquí no existe gestion_pedidos. No se aplicó nada.';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '0031') then
    raise exception 'FALTA LA 0031 en schema_migrations: revisar el orden antes de seguir. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- 0032 · FORCE, permisos de más y restos muertos (17-11-2026)
--
-- Los amarillos de seguridad de la auditoría del 16-11 en Gestión. Solo
-- permisos: no cambia ni borra ninguna fila.
--
-- 1) FORCE RLS en las 11 tablas que no lo tenían: gestion_pedidos,
--    gestion_produccion, gestion_finanzas, gestion_costos, gestion_pixel,
--    gestion_historial, gestion_borrados, gestion_usuarios, cotizaciones,
--    cotizacion_lineas y quote_links. No cambia nada para las funciones
--    SECURITY DEFINER ni para las Edge Functions: el dueño (postgres) y
--    service_role tienen bypassrls (verificado el 17-11).
--
-- 2) La llave pública (anon) sin NINGÚN permiso sobre tablas ni vistas de
--    public. Tenía SELECT/INSERT/UPDATE/DELETE/TRUNCATE en 15 tablas y 5
--    vistas de gastos, postventa y documentos (RLS devolvía vacío, pero el
--    permiso no debía existir; TRUNCATE además ignora RLS). La Gestión usa la
--    llave pública solo para llamar funciones (B2B por token, ficha de venta
--    del Cotizador, chequeos de rol): esas no se tocan. Todo lo demás entra
--    con sesión iniciada.
--
-- 3) authenticated sin TRUNCATE, REFERENCES ni TRIGGER en ninguna tabla o
--    vista (ninguna app los usa; PostgREST ni los expone).
--
-- 4) Restos muertos de antes de separar los proyectos (junio 2026):
--    cotizaciones (0 filas), cotizacion_lineas (0) y quote_links (35).
--    quote_links se LEÍA con la llave pública (policy «anon read
--    non-expired»): eran 35 cotizaciones de junio con datos de clientes.
--    Se borran sus 6 policies y se les quita todo permiso a anon y
--    authenticated. Las filas se quedan (nada se borra sin respaldo y ok);
--    siguen en el respaldo diario y legibles por SQL. Nada las usa: buscado en
--    index.html y en el resto del repo (las referencias son del Cotizador,
--    que es otro proyecto).
--
-- 5) respaldo_produccion_20261113 (111 filas, copia de seguridad del 13-11):
--    se queda donde está pero sin permisos para anon ni authenticated, + FORCE.
--
-- NO entra (va aparte): la vista gestion_clientes (P077, decisión pendiente),
-- los respaldos mensuales y los datos de integridad (filas Firebase, emisiones
-- sin historial): esos cambian datos y piden su propio ok.
--
-- Idempotente: se puede correr dos veces sin error. Rollback al final.
--
-- APLICADA el 17-11-2026 en el SQL Editor de Gestión. Verificación: sin_force 0,
-- anon_relaciones 0, auth_truncate 0, policies_muertas 0, auth_muertas 0,
-- quote_links 35 filas, respaldo 111, gestion_pedidos 174, última 0032. Probado
-- con la llave pública: quote_links, facturas, gestion_pedidos, v_mayor y el
-- respaldo dan 401; es_admin, zaru_rol, b2b_norm_rut, b2b_tramo_rut,
-- b2b_estado y estado_ventas_cotizador responden 200. Antes de aplicar se
-- revisó que toda función pública que lee tablas sea SECURITY DEFINER (lo son).
-- ══════════════════════════════════════════════════════════════════════════

-- 1) FORCE
alter table public.gestion_pedidos    force row level security;
alter table public.gestion_produccion force row level security;
alter table public.gestion_finanzas   force row level security;
alter table public.gestion_costos     force row level security;
alter table public.gestion_pixel      force row level security;
alter table public.gestion_historial  force row level security;
alter table public.gestion_borrados   force row level security;
alter table public.gestion_usuarios   force row level security;
alter table public.cotizaciones       force row level security;
alter table public.cotizacion_lineas  force row level security;
alter table public.quote_links        force row level security;
alter table public.respaldo_produccion_20261113 force row level security;

-- 2) y 3) permisos, recorriendo todas las tablas y vistas de public
do $m0032$
declare r record;
begin
  for r in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'public' and c.relkind in ('r','v','m','p') loop
    execute format('revoke all on public.%I from anon', r.relname);
    execute format('revoke truncate, references, trigger on public.%I from authenticated', r.relname);
  end loop;
end
$m0032$;

-- 4) restos muertos: fuera policies y permisos
drop policy if exists "anon insert lineas"    on public.cotizacion_lineas;
drop policy if exists "auth full lineas"      on public.cotizacion_lineas;
drop policy if exists "anon insert"           on public.cotizaciones;
drop policy if exists "auth full"             on public.cotizaciones;
drop policy if exists "anon insert"           on public.quote_links;
drop policy if exists "anon read non-expired" on public.quote_links;
revoke all on public.cotizaciones, public.cotizacion_lineas, public.quote_links from anon, authenticated;

-- 5) copia del 13-11
revoke all on public.respaldo_produccion_20261113 from anon, authenticated;

-- Registro
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('0032', 'force_permisos_restos', array[
  'alter table ... force row level security en gestion_pedidos, gestion_produccion, gestion_finanzas, gestion_costos, gestion_pixel, gestion_historial, gestion_borrados, gestion_usuarios, cotizaciones, cotizacion_lineas, quote_links, respaldo_produccion_20261113;',
  'revoke all on <todas las tablas y vistas de public> from anon; revoke truncate, references, trigger on <todas> from authenticated;',
  'drop policy x6 en cotizaciones, cotizacion_lineas, quote_links; revoke all on esas 3 from anon, authenticated;',
  'revoke all on public.respaldo_produccion_20261113 from anon, authenticated;'
])
on conflict (version) do nothing;

-- Verificación: sin_force = 0, anon_relaciones = 0, auth_truncate = 0,
-- policies_muertas = 0, auth_muertas = 0, filas_quote_links = 35,
-- filas_respaldo = 111 y migraciones termina en 0032.
with tp as (
  select c.oid, c.relname, c.relkind, c.relforcerowsecurity from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r','v','m','p'))
select
  (select count(*) from tp where relkind = 'r' and not relforcerowsecurity)                      as sin_force,
  (select count(*) from tp cross join unnest(array['select','insert','update','delete','truncate']) p
     where has_table_privilege('anon', tp.oid, p))                                              as anon_relaciones,
  (select count(*) from tp where has_table_privilege('authenticated', tp.oid, 'truncate'))       as auth_truncate,
  (select count(*) from pg_policies where schemaname = 'public'
     and tablename in ('cotizaciones','cotizacion_lineas','quote_links'))                        as policies_muertas,
  (select count(*) from tp cross join unnest(array['select','insert','update','delete']) p
     where tp.relname in ('cotizaciones','cotizacion_lineas','quote_links','respaldo_produccion_20261113')
       and has_table_privilege('authenticated', tp.oid, p))                                      as auth_muertas,
  (select count(*) from public.quote_links)                                                      as filas_quote_links,
  (select count(*) from public.respaldo_produccion_20261113)                                     as filas_respaldo,
  (select max(version) from supabase_migrations.schema_migrations)                               as ultima_migracion;

-- ── ROLLBACK (no correr junto con lo de arriba) ──────────────────────────
-- Estado anterior leído el 17-11 antes de aplicar:
-- alter table public.<cada una de las 12 de arriba> no force row level security;
-- grant all on public.centros_costo, public.documentos_recibidos,
--   public.documentos_recibidos_lineas, public.factura_lineas, public.facturas,
--   public.gasto_categorias, public.gestion_documentos, public.inventario,
--   public.mayor, public.pedido_centro_costo, public.postventa, public.proveedores,
--   public.respaldo_produccion_20261113, public.unidades, public.v_costo_pedido,
--   public.v_documentos_recibidos_pendientes, public.v_facturas,
--   public.v_inventario, public.v_mayor to anon;
-- grant insert on public.cotizaciones, public.cotizacion_lineas to anon;
-- grant insert, select on public.quote_links to anon;
-- grant all on public.cotizaciones, public.cotizacion_lineas, public.quote_links,
--   public.respaldo_produccion_20261113 to authenticated;
-- grant truncate, references, trigger on all tables in schema public to authenticated;
-- create policy "anon insert lineas" on public.cotizacion_lineas for insert to anon with check (true);
-- create policy "auth full lineas" on public.cotizacion_lineas for all to authenticated using (true);
-- create policy "anon insert" on public.cotizaciones for insert to anon with check (true);
-- create policy "auth full" on public.cotizaciones for all to authenticated using (true);
-- create policy "anon insert" on public.quote_links for insert to anon with check (true);
-- create policy "anon read non-expired" on public.quote_links for select to anon using (expires_at > now());
-- delete from supabase_migrations.schema_migrations where version = '0032';
