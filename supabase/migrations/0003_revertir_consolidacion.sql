-- ══════════════════════════════════════════════════════════════════════════
-- MIGRACIÓN 0003 · REVERTIR LA CONSOLIDACIÓN DE casa-zaru-gastos
--
-- PROYECTO SUPABASE: padnttpgzuotxeipjrry (el de la Gestión)
--
-- La 0002 y la carga de datos que la acompañó fueron un desvío: metieron la
-- app de gastos dentro de este módulo, que es una cosa aparte —el circuito
-- factura → bodega → costo del pedido, para sacar el margen real—. Se deshace.
--
-- casa-zaru-gastos NO se tocó en ningún momento: su Firebase solo se leyó.
-- Sigue funcionando con todos sus datos.
--
-- Qué borra:
--   · los 36 movimientos importados al mayor (marcados en la nota)
--   · los 55 proveedores y 12 ítems de bodega que vinieron de esa app
--   · la tabla deudas y su vista, creadas por la 0002
--
-- Después de correr esto, las tablas de la 0001 quedan vacías, que es como
-- estaban recién creadas. Los catálogos (unidades, gasto_categorias) se
-- conservan: son del diseño original, no de la consolidación.
--
-- Pegar en Supabase → SQL Editor → Run. Es idempotente.
-- ══════════════════════════════════════════════════════════════════════════

-- ── 1. Movimientos importados ─────────────────────────────────────────────
-- Se identifican por la marca que se les puso al migrarlos, no por un rango
-- de fechas ni por el id: así no se lleva por delante nada cargado a mano.
delete from mayor where nota like '%[migrado de casa-zaru-gastos]';

-- ── 2. Bodega y proveedores ───────────────────────────────────────────────
-- Estas dos tablas nacieron vacías con la 0001 y todo lo que tienen vino de
-- la app de gastos. Se borra solo lo que no dejó rastro en otra tabla: si
-- algún ítem o proveedor ya quedó referenciado por una factura o un
-- movimiento cargado de verdad, la FK lo protege y la fila se conserva.
delete from inventario i
 where not exists (select 1 from factura_lineas l where l.inventario_id = i.id)
   and not exists (select 1 from mayor m        where m.inventario_id = i.id);

delete from proveedores p
 where not exists (select 1 from facturas f where f.proveedor_id = p.id);

-- ── 3. Deudas ─────────────────────────────────────────────────────────────
-- Creadas por la 0002 solo para absorber esa app. Fuera.
drop view  if exists v_deudas;
drop table if exists deudas;
