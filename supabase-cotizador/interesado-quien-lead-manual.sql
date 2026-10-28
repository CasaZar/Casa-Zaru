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

-- ══════════════════════════════════════════════════════════════
-- Casa Zaru · ★ Interesado: quién la puso y cuándo + leads a mano
-- (28-10-2026)
--
-- 1) interesado_por / interesado_fecha: la ★ «Interesado» (interesado.sql)
--    no decía quién la marcó. Desde la revisión diaria de WhatsApp la pone
--    también Claude, y hay que distinguirla de la de César o Tomás.
--    El panel las escribe junto con la ★ y las pone en null al quitarla.
-- 2) lead_manual: un cliente que ya conversa por WhatsApp pero nunca cotizó
--    en la web (caso posavasos, 27-10). null = cotización normal; si trae
--    texto, es un lead creado a mano y el texto dice quién lo creó
--    ('Claude' = revisión de WhatsApp). El panel lo sigue igual, pero NO lo
--    suma a montos, metas ni conteos, y los scripts del Pulso lo excluyen.
--
-- Idempotente: se puede correr dos veces sin efecto.
-- No toca políticas: las de update de cotizaciones son por fila (RLS) y el
-- grant de la tabla cubre las columnas nuevas. El select del final lo
-- comprueba.
-- Pegar en Supabase (proyecto cmxqorsyxoltrakxawro) → SQL Editor → Run.
-- ══════════════════════════════════════════════════════════════

alter table public.cotizaciones
  add column if not exists interesado_por   text,
  add column if not exists interesado_fecha timestamptz,
  add column if not exists lead_manual      text;

comment on column public.cotizaciones.interesado_por   is 'Quién puso la ★ Interesado (César, Tomás, Claude (revisión WhatsApp)…). null en las marcadas antes del 28-10-2026';
comment on column public.cotizaciones.interesado_fecha is 'Cuándo se puso la ★ Interesado';
comment on column public.cotizaciones.lead_manual      is 'null = cotización normal. Con texto = lead creado a mano sin cotización (Claude = revisión de WhatsApp): no suma a montos, metas ni conteos';

-- un lead manual siempre dice quién lo creó (no vale el texto vacío)
do $chk$
begin
  if not exists (select 1 from pg_constraint
                 where conname = 'cotizaciones_lead_manual_no_vacio'
                   and conrelid = 'public.cotizaciones'::regclass) then
    alter table public.cotizaciones
      add constraint cotizaciones_lead_manual_no_vacio
      check (lead_manual is null or length(btrim(lead_manual)) > 0);
  end if;
end
$chk$;

-- ── Verificación: las tres columnas existen y el panel (authenticated)
--    puede leerlas y actualizarlas. Debe salir 3 filas con true / true.
select c.column_name,
       has_column_privilege('authenticated', 'public.cotizaciones', c.column_name, 'SELECT') as lee,
       has_column_privilege('authenticated', 'public.cotizaciones', c.column_name, 'UPDATE') as actualiza
from information_schema.columns c
where c.table_schema = 'public' and c.table_name = 'cotizaciones'
  and c.column_name in ('interesado_por', 'interesado_fecha', 'lead_manual')
order by c.column_name;

-- ══════════════════════════════════════════════════════════════
-- ROLLBACK (no correr salvo que haya que deshacer). Antes de correrlo,
-- respaldar lo que se pierde:
--   select id, numero, interesado_por, interesado_fecha, lead_manual
--   from public.cotizaciones
--   where interesado_por is not null or lead_manual is not null;
-- Ojo: los leads manuales quedarían como cotizaciones normales y volverían a
-- sumar en montos y conteos; marcarlos eliminada=true antes si se deshace.
--
--   alter table public.cotizaciones drop constraint if exists cotizaciones_lead_manual_no_vacio;
--   alter table public.cotizaciones
--     drop column if exists lead_manual,
--     drop column if exists interesado_fecha,
--     drop column if exists interesado_por;
-- ══════════════════════════════════════════════════════════════
