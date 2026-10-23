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
-- 0020 · Prueba de restauración (23-10-2026)
--
-- «Un respaldo que nunca se restauró no existe» (CLAUDE.md, contrato de
-- confiabilidad). Esta migración crea lo mínimo para ensayar la restauración
-- todos los meses sin CLI ni psql: cuatro funciones RPC que el script
-- .claude/skills/auditoria/scripts/restaurar-prueba.ps1 llama por PostgREST.
--
--   restore_test_preparar()        borra y recrea el esquema restore_test con
--                                  una copia VACÍA de cada tabla de public
--                                  (misma forma, sin identity ni FK).
--   restore_test_cargar(t, filas)  inserta un lote del JSON del respaldo en
--                                  restore_test.<t>. Si un valor no calza con
--                                  el tipo de la columna, Postgres lo rechaza:
--                                  eso ES la prueba.
--   restore_test_resumen()         filas y suma de cada columna numérica por
--                                  tabla restaurada, para comparar con el archivo.
--   restore_test_limpiar()         borra el esquema. El ensayo no deja rastro.
--
-- El esquema restore_test NO está expuesto por PostgREST (solo public), así
-- que nadie lo lee por la API. Solo el admin (es_admin()) puede llamar las
-- funciones. Idempotente: se puede volver a correr.
-- ══════════════════════════════════════════════════════════════════════════

create or replace function public.restore_test_preparar()
returns text[] language plpgsql security definer set search_path = public, pg_temp as $$
declare t record; creadas text[] := '{}';
begin
  if not es_admin() then raise exception 'restore_test: solo admin'; end if;
  execute 'drop schema if exists restore_test cascade';
  execute 'create schema restore_test';
  for t in select tablename from pg_tables where schemaname = 'public' order by 1 loop
    -- LIKE sin INCLUDING IDENTITY: el id llega explícito desde el respaldo.
    execute format('create table restore_test.%I (like public.%I including defaults)', t.tablename, t.tablename);
    creadas := creadas || t.tablename;
  end loop;
  return creadas;
end $$;

create or replace function public.restore_test_cargar(tabla text, filas jsonb)
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare n integer;
begin
  if not es_admin() then raise exception 'restore_test: solo admin'; end if;
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
  if not es_admin() then raise exception 'restore_test: solo admin'; end if;
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
  if not es_admin() then raise exception 'restore_test: solo admin'; end if;
  execute 'drop schema if exists restore_test cascade';
end $$;

-- Solo usuarios con sesión; dentro, es_admin() filtra al vendedor.
revoke execute on function public.restore_test_preparar()           from public, anon;
revoke execute on function public.restore_test_cargar(text, jsonb)  from public, anon;
revoke execute on function public.restore_test_resumen()            from public, anon;
revoke execute on function public.restore_test_limpiar()            from public, anon;
grant  execute on function public.restore_test_preparar()           to authenticated;
grant  execute on function public.restore_test_cargar(text, jsonb)  to authenticated;
grant  execute on function public.restore_test_resumen()            to authenticated;
grant  execute on function public.restore_test_limpiar()            to authenticated;

-- Rollback: drop function public.restore_test_preparar(), public.restore_test_cargar(text, jsonb),
--           public.restore_test_resumen(), public.restore_test_limpiar(); drop schema if exists restore_test cascade;

-- Registrar en el panel (Database → Migrations), pegándolo junto con este archivo:
-- insert into supabase_migrations.schema_migrations (version, name, statements)
-- values ('0020', 'restore_test', array[$mig$ <este archivo> $mig$]);
