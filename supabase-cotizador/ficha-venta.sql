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

-- Casa Zaru: ficha de venta del panel (09-11-2026, etapa 1 de conectar
-- Cotizador → Gestión). Pegar en Supabase → SQL Editor → Run.
--
-- «Ganada» ahora arma una ficha desde la cotización (productos, madera, pago,
-- envío, documento), se le manda al cliente por WhatsApp y, cuando confirma,
-- la cotización queda ganada. La ficha entera vive en esta columna:
--   estado      borrador | enviada | confirmada
--   items, tier, madera, lista, pago, envio{tipo,comuna,cod,kg,monto},
--   doc{tipo,rut,razon}, direccion, abono_pct (70 | 100),
--   calc{productos,envio,total,abono,saldo,pct_transf}  ← lo calcula el panel
--   hist[{t,que,por}]  ← cada paso, con fecha y quién
-- Null en todo lo anterior y en las ganadas «sin ficha».
--
-- No crea tabla ni toca filas existentes: solo agrega la columna y dos checks.
-- Es idempotente (se puede correr dos veces).
--
-- Rollback (borra las fichas guardadas: respaldar antes con
--   select id, ficha_venta from cotizaciones where ficha_venta is not null;):
--   alter table cotizaciones drop constraint if exists ficha_venta_estado_ok;
--   alter table cotizaciones drop column if exists ficha_venta;

alter table cotizaciones
  add column if not exists ficha_venta jsonb;

comment on column cotizaciones.ficha_venta is
  'Ficha de venta del panel (09-11-2026): borrador → enviada al cliente → confirmada. Ver supabase-cotizador/ficha-venta.sql';

-- La base rechaza una ficha mal formada aunque el navegador la mande.
do $chk$
begin
  if not exists (select 1 from pg_constraint where conname = 'ficha_venta_estado_ok') then
    alter table cotizaciones add constraint ficha_venta_estado_ok check (
      ficha_venta is null or (
        jsonb_typeof(ficha_venta) = 'object'
        and ficha_venta->>'estado' in ('borrador','enviada','confirmada')
      )
    );
  end if;
end
$chk$;

-- Verificación: debe devolver una fila con data_type = jsonb
select column_name, data_type from information_schema.columns
 where table_schema = 'public' and table_name = 'cotizaciones' and column_name = 'ficha_venta';
