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
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- Prueba de restauración del Cotizador (23-10-2026)
--
-- Misma idea que supabase/migrations/0020_restore_test.sql en Gestión: cuatro
-- funciones RPC para cargar el zip del respaldo diario en un esquema aparte
-- (restore_test) y comparar filas y sumas contra el archivo. Las llama
-- .claude/skills/auditoria/scripts/restaurar-prueba.ps1 -Proyecto cotizador
-- con la llave secreta local (service_role). Ningún otro rol puede ejecutarlas.
-- restore_test no está expuesto por PostgREST. Idempotente.
-- ══════════════════════════════════════════════════════════════════════════

create or replace function public.restore_test_preparar()
returns text[] language plpgsql security definer set search_path = public, pg_temp as $$
declare t record; creadas text[] := '{}';
begin
  execute 'drop schema if exists restore_test cascade';
  execute 'create schema restore_test';
  for t in select tablename from pg_tables where schemaname = 'public' order by 1 loop
    execute format('create table restore_test.%I (like public.%I including defaults)', t.tablename, t.tablename);
    creadas := creadas || t.tablename;
  end loop;
  return creadas;
end $$;

create or replace function public.restore_test_cargar(tabla text, filas jsonb)
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare n integer;
begin
  if to_regclass(format('restore_test.%I', tabla)) is null then
    raise exception 'restore_test.% no existe: correr restore_test_preparar() primero', tabla;
  end if;
  execute format('insert into restore_test.%I select * from jsonb_populate_recordset(null::restore_test.%I, $1)', tabla, tabla)
    using filas;
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.restore_test_resumen()
returns table (tabla text, filas bigint, sumas jsonb)
language plpgsql security definer set search_path = public, pg_temp as $$
declare t record; c record; n bigint; s jsonb; v numeric;
begin
  for t in select tablename from pg_tables where schemaname = 'restore_test' order by 1 loop
    execute format('select count(*) from restore_test.%I', t.tablename) into n;
    s := '{}'::jsonb;
    for c in
      select column_name from information_schema.columns
      where table_schema = 'restore_test' and table_name = t.tablename
        and data_type in ('smallint','integer','bigint','numeric','real','double precision')
      order by ordinal_position
    loop
      execute format('select coalesce(sum(%I), 0) from restore_test.%I', c.column_name, t.tablename) into v;
      s := s || jsonb_build_object(c.column_name, v);
    end loop;
    tabla := t.tablename; filas := n; sumas := s;
    return next;
  end loop;
end $$;

create or replace function public.restore_test_limpiar()
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  execute 'drop schema if exists restore_test cascade';
end $$;

-- Solo la llave secreta (service_role). Ni la pública ni una sesión del panel.
revoke execute on function public.restore_test_preparar()           from public, anon, authenticated;
revoke execute on function public.restore_test_cargar(text, jsonb)  from public, anon, authenticated;
revoke execute on function public.restore_test_resumen()            from public, anon, authenticated;
revoke execute on function public.restore_test_limpiar()            from public, anon, authenticated;
grant  execute on function public.restore_test_preparar()           to service_role;
grant  execute on function public.restore_test_cargar(text, jsonb)  to service_role;
grant  execute on function public.restore_test_resumen()            to service_role;
grant  execute on function public.restore_test_limpiar()            to service_role;

-- Rollback: drop function public.restore_test_preparar(), public.restore_test_cargar(text, jsonb),
--           public.restore_test_resumen(), public.restore_test_limpiar(); drop schema if exists restore_test cascade;
