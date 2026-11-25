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
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '0014') then
    raise exception 'FALTA LA 0014: aplicar antes 0014_bandeja_avisos.sql. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- 0015 · COTIZADOR · Prueba del paso de datos a mitad de visitas (25-11-2026)
-- APLICADA el 25-11-2026 (SQL Editor, desde el Chrome del usuario, con su ok: «dale tú»).
-- Verificada por MCP: columna 1, check_variante 1, paso_nuevo 1, interruptor «prueba», registrada 1.
-- La versión B se vio en vivo con ?prod=cubierta&ab=b. El reparto sigue SIN ENCENDER.
--
-- Pedido del dueño («Probar a mitad de visitas», boceto aprobado el 25-11): en 30 días,
-- 447 de 549 personas vieron su precio estimado y se fueron sin dejar datos. El rango
-- que ya se muestra gratis trae dos de los tres precios exactos, así que el premio por
-- dejar el WhatsApp es débil. Se prueba otra versión con la mitad de las visitas:
--   A = como está hoy (rango y «Mira el precio exacto de cada madera»).
--   B = el precio de las tres maderas a la vista y «Recibe tu cotización por WhatsApp».
-- Solo en cubiertas (87 % de los que ven precio) y solo en la entrada pública.
--
-- Cambios:
--   · embudo_eventos.variante: null (todo lo de siempre) o 'A' / 'B'. El navegador la
--     manda solo mientras exista la fila `prueba_datos` y esté activa, así que el front
--     puede publicarse antes de aplicar esto: sin la fila no cambia nada para nadie.
--   · paso nuevo 'datos_foco': la persona tocó el campo de nombre o de WhatsApp. Hoy
--     'datos' se registra recién cuando el formulario pasa la validación, y no se sabe
--     cuántos empiezan a escribir y abandonan.
--   · cotizador_valores['prueba_datos'] = interruptor, igual que `asistente`:
--       apagado → nadie ve la B
--       prueba  → solo quien abre el link con ?ab=b (no cuenta en el embudo)
--       activo  → se reparte: `pct` de cada 100 visitas ve la B
--     Parte en «prueba». Para encenderla, la línea está al final.
-- No toca cotizaciones ni permisos: mismas políticas de embudo_eventos.
--
-- Idempotente. Rollback al final.
-- ══════════════════════════════════════════════════════════════════════════

-- 1) variante
alter table public.embudo_eventos add column if not exists variante text;

do $c$
begin
  if not exists (select 1 from pg_constraint where conname = 'embudo_eventos_variante_chk') then
    alter table public.embudo_eventos
      add constraint embudo_eventos_variante_chk check (variante is null or variante in ('A', 'B'));
  end if;
end
$c$;

-- 2) paso 'datos_foco' (los nueve de antes más el nuevo)
alter table public.embudo_eventos drop constraint if exists embudo_eventos_paso_check;
alter table public.embudo_eventos
  add constraint embudo_eventos_paso_check check (paso = any (array[
    'visita', 'producto', 'medidas', 'datos', 'cotizacion',
    'whatsapp', 'duda', 'muestrario', 'wa_tienda', 'datos_foco']));

-- 3) interruptor, en «prueba»
insert into public.cotizador_valores (clave, valor, updated_at, updated_by)
select 'prueba_datos', '{"estado": "prueba", "pct": 50}'::jsonb, now(), 'migracion 0015'
where not exists (select 1 from public.cotizador_valores where clave = 'prueba_datos');

-- 4) registro
insert into supabase_migrations.schema_migrations (version, name, statements)
select '0015', 'prueba_datos', array['ver supabase-cotizador/migrations/0015_prueba_datos.sql']
where not exists (select 1 from supabase_migrations.schema_migrations where version = '0015');

-- 5) verificación (debe dar: columna 1, check_variante 1, paso_nuevo 1, interruptor «prueba», registrada 1)
select
  (select count(*) from information_schema.columns where table_name = 'embudo_eventos' and column_name = 'variante') as columna,
  (select count(*) from pg_constraint where conname = 'embudo_eventos_variante_chk') as check_variante,
  (select count(*) from pg_constraint where conname = 'embudo_eventos_paso_check' and pg_get_constraintdef(oid) like '%datos_foco%') as paso_nuevo,
  (select valor ->> 'estado' from public.cotizador_valores where clave = 'prueba_datos') as interruptor,
  (select count(*) from supabase_migrations.schema_migrations where version = '0015') as registrada;

-- ── ENCENDER / APAGAR (dato, no esquema; se corre aparte cuando se decida) ──
-- update public.cotizador_valores set valor = '{"estado": "activo", "pct": 50}'::jsonb, updated_at = now(), updated_by = 'dueño' where clave = 'prueba_datos';
-- update public.cotizador_valores set valor = '{"estado": "apagado", "pct": 50}'::jsonb, updated_at = now(), updated_by = 'dueño' where clave = 'prueba_datos';

-- ── ROLLBACK (a mano, solo si hace falta; se pierde qué versión vio cada sesión) ──
-- delete from public.cotizador_valores where clave = 'prueba_datos';
-- delete from public.embudo_eventos where paso = 'datos_foco';
-- alter table public.embudo_eventos drop constraint if exists embudo_eventos_paso_check;
-- alter table public.embudo_eventos add constraint embudo_eventos_paso_check check (paso = any (array['visita','producto','medidas','datos','cotizacion','whatsapp','duda','muestrario','wa_tienda']));
-- alter table public.embudo_eventos drop constraint if exists embudo_eventos_variante_chk;
-- alter table public.embudo_eventos drop column if exists variante;
-- delete from supabase_migrations.schema_migrations where version = '0015';
