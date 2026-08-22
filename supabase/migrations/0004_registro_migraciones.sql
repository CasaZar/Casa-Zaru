-- ══════════════════════════════════════════════════════════════════════════
-- MIGRACIÓN 0004 · REGISTRO DE MIGRACIONES APLICADAS
--
-- PROYECTO SUPABASE: padnttpgzuotxeipjrry (el de la Gestión)
--
-- Las migraciones se pegan a mano en el SQL Editor y nada deja constancia de
-- cuáles se corrieron. Hoy la base coincide con el código, pero eso se
-- verificó a ojo: no hay forma de saberlo sin ir tabla por tabla.
--
-- El día que alguien corra una dos veces, se salte una, o aplique algo desde
-- otro lado, el síntoma va a ser la app rota y nadie va a saber qué falta.
-- Esta tabla convierte esa pregunta en un SELECT.
--
-- Pegar en Supabase → SQL Editor → Run. Es idempotente: correrla de nuevo no
-- duplica ni pisa nada.
-- ══════════════════════════════════════════════════════════════════════════

create table if not exists migraciones (
  nombre      text primary key,
  aplicada_at timestamptz not null default now(),
  notas       text
);

comment on table migraciones is
  'Qué migraciones se corrieron en esta base. Cada archivo nuevo de supabase/migrations/ debe terminar insertando su propia fila acá.';

-- ── Se registra lo que YA está aplicado ───────────────────────────────────
-- Verificado el 2026-08-22 contra la base: las 7 tablas y las 3 vistas de la
-- 0001 existen y responden; la tabla deudas de la 0002 no existe (o sea que
-- la 0003 corrió); mayor, proveedores, inventario y facturas están en 0 filas
-- y los catálogos conservan sus 9 unidades y 25 categorías.
insert into migraciones (nombre, notas) values
  ('0001_gastos_inventario',    'Circuito factura → bodega → costo del pedido. 7 tablas + 3 vistas.'),
  ('0002_deudas',               'Consolidación de casa-zaru-gastos. REVERTIDA por la 0003.'),
  ('0003_revertir_consolidacion','Deshace la 0002: borra los datos importados y la tabla deudas. Los catálogos se conservan.'),
  ('0004_registro_migraciones', 'Esta tabla.')
on conflict (nombre) do nothing;

-- ── Cómo se usa de ahora en adelante ──────────────────────────────────────
-- Toda migración nueva termina con su propia línea, por ejemplo:
--
--   insert into migraciones (nombre, notas)
--   values ('0005_lo_que_sea', 'Qué hace y por qué')
--   on conflict (nombre) do nothing;
--
-- Y antes de correr cualquier cosa, para saber en qué estado está la base:
--
--   select nombre, aplicada_at from migraciones order by nombre;
