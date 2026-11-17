-- ── CANDADO DE PROYECTO (no borrar) ──────────────────────────────────────
-- Este archivo es del COTIZADOR (cmxqorsyxoltrakxawro). Si se pega en el SQL
-- Editor de otro proyecto, este bloque falla primero y Postgres descarta el
-- resto del script: no se aplica nada. Hace falta porque el proyecto de
-- Gestión TIENE tablas "cotizaciones" y "quote_links" (restos vacíos de junio)
-- y un alter sobre ellas pasaría ahí sin ningún error.
do $candado$
begin
  if to_regclass('public.gestion_pedidos') is not null then
    raise exception 'PROYECTO EQUIVOCADO: este SQL es del COTIZADOR (cmxqorsyxoltrakxawro) y lo estás corriendo en GESTIÓN. No se aplicó nada.';
  end if;
  if to_regclass('public.cotizaciones') is null then
    raise exception 'PROYECTO EQUIVOCADO: este SQL es del COTIZADOR (cmxqorsyxoltrakxawro) y aquí no existe la tabla cotizaciones. No se aplicó nada.';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '0001') then
    raise exception 'FALTA LA 0001: correr antes registro-migraciones.sql. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- 0002_force_permisos_whoami · COTIZADOR · 17-11-2026
--
-- Las tres cosas que la línea base 0001 copió tal cual y había que corregir:
--
-- 1) FORCE RLS en cotizacion_lineas y vendedores (las dos únicas sin FORCE).
--    No cambia nada para las funciones SECURITY DEFINER: su dueño, postgres,
--    tiene bypassrls (verificado el 17-11), así que next_quote_number,
--    guardar_lineas y es_equipo_panel siguen viendo todo.
--
-- 2) Permisos que sobraban (el default de Supabase da todo a todos):
--    a) TRUNCATE, REFERENCES y TRIGGER fuera para anon y authenticated en
--       todas las tablas. TRUNCATE ignora RLS; ninguna app los usa (PostgREST
--       ni siquiera los expone).
--    b) anon: fuera UPDATE y DELETE en todas las tablas. Ninguna policy le
--       permite editar ni borrar, así que hoy ya no podía; ahora la base lo
--       rechaza antes de llegar a RLS.
--    c) anon: fuera SELECT e INSERT en config_seguimiento, toques y
--       vendedores; fuera SELECT en embudo_eventos; fuera INSERT en
--       cotizador_valores. Sin policy para anon y sin uso público en el código
--       (revisado: index.html, cotizador-clientes.html, propuesta.html,
--       cuenta.html, fototeca.html y cz-origen.liquid, que inserta en el
--       embudo con return=minimal).
--    Se DEJAN a anon a propósito: SELECT en cotizaciones, cotizacion_lineas y
--    quote_links (el cotizador público los lee como plan B si falla la
--    función; RLS devuelve vacío), y lo que sí usa: INSERT en cotizaciones,
--    cotizacion_lineas, quote_links, embudo_eventos y errores_cliente, y
--    SELECT en cotizador_valores. authenticated conserva SELECT/INSERT/
--    UPDATE/DELETE donde los tenía: lo filtra RLS.
--
-- 3) whoami(): función de depuración que cualquiera podía ejecutar y que
--    nadie usa (buscado en ambos repos). Se borra.
--
-- Idempotente: se puede correr dos veces sin error. El rollback va al final.
--
-- APLICADA el 17-11-2026 en el SQL Editor del Cotizador. Verificación: FORCE en
-- las 18 tablas, whoami 0, anon sin TRUNCATE/UPDATE/DELETE, authenticated sin
-- TRUNCATE, migraciones 0001,0002. Probado con la llave pública: lee
-- cotizador_valores, next_quote_number y get_quote_link responden 200; toques,
-- vendedores y PATCH a cotizaciones dan 401; whoami 404.
-- (Primer intento: la verificación usaba format('public.%I', tablename) y
-- Postgres la evaluó sobre tablas de auth → error y rollback completo, no se
-- aplicó nada. Se cambió a has_table_privilege por oid.)
-- ══════════════════════════════════════════════════════════════════════════

-- 1) FORCE
alter table public.cotizacion_lineas force row level security;
alter table public.vendedores        force row level security;

-- 2a) TRUNCATE / REFERENCES / TRIGGER fuera, en todas las tablas de public
do $m0002$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('revoke truncate, references, trigger on public.%I from anon, authenticated', t);
    -- 2b) anon nunca edita ni borra
    execute format('revoke update, delete on public.%I from anon', t);
  end loop;
end
$m0002$;

-- 2c) anon sin lectura/escritura donde no tiene policy ni uso
revoke select, insert on public.config_seguimiento from anon;
revoke select, insert on public.toques             from anon;
revoke select, insert on public.vendedores         from anon;
revoke select         on public.embudo_eventos     from anon;
revoke insert         on public.cotizador_valores  from anon;

-- 3) whoami()
drop function if exists public.whoami();

-- Registro
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('0002', 'force_permisos_whoami', array[
  'alter table public.cotizacion_lineas force row level security; alter table public.vendedores force row level security;',
  'revoke truncate, references, trigger on <todas las tablas de public> from anon, authenticated; revoke update, delete on <todas> from anon;',
  'revoke select, insert on config_seguimiento, toques, vendedores from anon; revoke select on embudo_eventos from anon; revoke insert on cotizador_valores from anon;',
  'drop function if exists public.whoami();'
])
on conflict (version) do nothing;

-- Verificación: force_lineas = force_vendedores = true, whoami = 0,
-- anon_truncate = 0, anon_edita = 0, auth_truncate = 0, y la lista de lo
-- que le queda a anon debe ser exactamente:
--   cotizacion_lineas: insert,select · cotizaciones: insert,select ·
--   cotizador_valores: select · embudo_eventos: insert ·
--   errores_cliente: insert · quote_links: insert,select
with tp as (
  select c.oid, c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r')
select
  (select relforcerowsecurity from pg_class where oid = 'public.cotizacion_lineas'::regclass) as force_lineas,
  (select relforcerowsecurity from pg_class where oid = 'public.vendedores'::regclass)        as force_vendedores,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'whoami')                                     as whoami,
  (select count(*) from tp where has_table_privilege('anon', tp.oid, 'truncate'))            as anon_truncate,
  (select count(*) from tp where has_table_privilege('anon', tp.oid, 'update')
                              or has_table_privilege('anon', tp.oid, 'delete'))              as anon_edita,
  (select count(*) from tp where has_table_privilege('authenticated', tp.oid, 'truncate'))   as auth_truncate,
  (select string_agg(relname || ': ' || privs, ' · ' order by relname) from (
     select tp.relname, string_agg(p, ',' order by p) as privs
     from tp cross join unnest(array['select','insert']) p
     where has_table_privilege('anon', tp.oid, p)
     group by tp.relname) s)                                                                  as anon_queda,
  (select string_agg(version, ',' order by version) from supabase_migrations.schema_migrations) as migraciones;
-- ── ROLLBACK (no correr junto con lo de arriba) ──────────────────────────
-- Deja todo como en la 0001 (estado del 17-11 antes de esta migración).
-- alter table public.cotizacion_lineas no force row level security;
-- alter table public.vendedores        no force row level security;
-- grant delete, insert, references, select, trigger, truncate, update on
--   public.config_seguimiento, public.cotizacion_lineas, public.cotizaciones,
--   public.cotizador_valores, public.embudo_eventos, public.quote_links,
--   public.toques, public.vendedores to anon, authenticated;
-- grant insert, references, trigger, truncate on public.errores_cliente to anon, authenticated;
-- grant references, trigger, truncate on public.fototeca_ediciones,
--   public.fototeca_ediciones_historial, public.fototeca_usos,
--   public.fototeca_usos_historial, public.whatsapp_pendientes to authenticated;
-- create or replace function public.whoami() returns text language sql
--   as $function$ select current_user::text $function$;
-- grant execute on function public.whoami() to public;
-- delete from supabase_migrations.schema_migrations where version = '0002';
