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
-- Registro de migraciones del Cotizador (17-11-2026)
--
-- El Cotizador nunca tuvo supabase_migrations.schema_migrations (no se usó
-- la CLI). Se crea la MISMA tabla que crea Supabase —la que muestra
-- Database → Migrations en el panel—, no una propia, y se anota la línea
-- base 0001_estado_actual como aplicada: su esquema ya existía, por eso la
-- 0001 no se ejecuta (su candado lo impide en este proyecto).
--
-- Desde aquí, cada migración nueva de supabase-cotizador/migrations/ termina
-- con su propio insert en esta tabla (ver supabase/migrations/README.md).
-- Idempotente: se puede correr dos veces sin error.
-- APLICADO el 17-11-2026 en el SQL Editor del Cotizador: devuelve 0001
-- estado_actual; RLS activo; anon sin acceso. Ese día también se probó el
-- candado de la 0001 en producción: aborta con «LÍNEA BASE YA APLICADA».
-- ══════════════════════════════════════════════════════════════════════════

create schema if not exists supabase_migrations;

create table if not exists supabase_migrations.schema_migrations (
  version    text primary key,
  statements text[],
  name       text
);
-- RLS sin FORCE: el esquema no está expuesto por la API (anon no tiene ni
-- usage), y sin FORCE el dueño (el panel, Database → Migrations) la sigue leyendo.
alter table supabase_migrations.schema_migrations enable row level security;

insert into supabase_migrations.schema_migrations (version, name, statements)
values ('0001', 'estado_actual', array[
  '-- Línea base: supabase-cotizador/migrations/0001_estado_actual.sql. '
  || 'Registrada el 17-11-2026 sin ejecutar: el esquema ya existía en producción '
  || '(18 tablas, 21 funciones, 3 triggers, 41+5 policies; md5 verificado).'
])
on conflict (version) do nothing;

-- Verificación: debe listar una sola fila, 0001 estado_actual.
select version, name from supabase_migrations.schema_migrations order by version;

-- ── ROLLBACK (no correr junto con lo de arriba)
-- delete from supabase_migrations.schema_migrations where version = '0001';
-- drop table if exists supabase_migrations.schema_migrations;  -- solo si quedó vacía
-- drop schema if exists supabase_migrations;
