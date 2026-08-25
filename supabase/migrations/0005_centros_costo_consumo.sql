-- ══════════════════════════════════════════════════════════════════════════
-- MIGRACIÓN 0005 · CENTROS DE COSTO Y CONSUMO DEL TALLER
--
-- PROYECTO SUPABASE: padnttpgzuotxeipjrry (el de la Gestión)
--
-- Cierra la caja del medio del diagrama:
--
--   Factura ─┬─> Inventario ──> [EL TALLER CONSUME] ──┐
--            │                    ← esto              ├──> Libro Mayor
--            └─> Gastos directos ─────────────────────┘
--
-- Hasta ahora la compra de un insumo quedaba como activo en bodega y nunca se
-- convertía en costo de un pedido. El síntoma: las dos cifras del mayor
-- ("gasto real" y "costo del período") daban siempre el mismo número.
--
-- Se agrega además una dimensión que no existía: el CENTRO DE COSTO. Cada
-- pedido se asigna a uno y el consumo se descarga por línea contra él, para
-- poder sacar el margen por pedido en detalle y agrupar por tipo de producto
-- y especie de madera.
--
-- Pegar en Supabase → SQL Editor → Run. Es idempotente.
-- ══════════════════════════════════════════════════════════════════════════


-- ── 1. centros_costo ──────────────────────────────────────────────────────
-- Catálogo fijo y administrable. Los códigos son de 12 caracteres EXACTOS:
-- es la convención que ya se usa fuera del sistema (MaderCoihu26, CasaZaru2026)
-- y se hace cumplir acá para que no entren variantes de otro largo.
--
--   MADER   = producto de madera pura
--   MIXTO   = producto que lleva fierro
--   GENERAL = el cajón para lo que no calza en una especie
create table if not exists centros_costo (
  id      smallint generated always as identity primary key,
  codigo  text     not null unique check (char_length(codigo) = 12),
  nombre  text     not null,
  tipo    text     not null check (tipo in ('MADER','MIXTO','GENERAL')),
  especie text,
  activo  boolean  not null default true,
  orden   smallint not null default 0,
  creado_en timestamptz not null default now()
);

comment on table  centros_costo is 'CECOs. El código va en 12 caracteres exactos por convención de la empresa.';
comment on column centros_costo.especie is 'Especie de madera que representa, para sugerir el CECO solo desde Producción. Null en los GENERAL.';
comment on column centros_costo.activo  is 'false = no se ofrece para consumos nuevos, pero los movimientos viejos lo conservan.';

-- Los 15 iniciales. "Orego" cubre OREGÓN y PINO OREGÓN; Laurel queda fuera a
-- propósito y sus pedidos caen en CasaZaru2026.
insert into centros_costo (codigo, nombre, tipo, especie, orden) values
  ('MaderOrego26','Madera Oregón',  'MADER','OREGÓN',  1),
  ('MaderCasta26','Madera Castaño', 'MADER','CASTAÑO', 2),
  ('MaderCipré26','Madera Ciprés',  'MADER','CIPRÉS',  3),
  ('MaderMañío26','Madera Mañío',   'MADER','MAÑÍO',   4),
  ('MaderRaulí26','Madera Raulí',   'MADER','RAULÍ',   5),
  ('MaderLenga26','Madera Lenga',   'MADER','LENGA',   6),
  ('MaderCoihu26','Madera Coihue',  'MADER','COIHUE',  7),
  ('MixtoOrego26','Mixto Oregón',   'MIXTO','OREGÓN',  11),
  ('MixtoCasta26','Mixto Castaño',  'MIXTO','CASTAÑO', 12),
  ('MixtoCipré26','Mixto Ciprés',   'MIXTO','CIPRÉS',  13),
  ('MixtoMañío26','Mixto Mañío',    'MIXTO','MAÑÍO',   14),
  ('MixtoRaulí26','Mixto Raulí',    'MIXTO','RAULÍ',   15),
  ('MixtoLenga26','Mixto Lenga',    'MIXTO','LENGA',   16),
  ('MixtoCoihu26','Mixto Coihue',   'MIXTO','COIHUE',  17),
  ('CasaZaru2026','Casa Zaru general','GENERAL', null, 90)
on conflict (codigo) do nothing;


-- ── 2. pedido_centro_costo ────────────────────────────────────────────────
-- El CECO asignado a cada pedido. Vive acá y no dentro de gestion_costos
-- porque esa tabla es solo_admin y el taller, que es quien consume, no puede
-- ni leerla. gestion_produccion sí lo deja leer (policy usuarios_leer sobre
-- es_usuario(), que incluye al rol taller).
create table if not exists pedido_centro_costo (
  pedido_num      text     primary key,
  centro_costo_id smallint not null references centros_costo(id),
  asignado_por    text,
  asignado_en     timestamptz not null default now()
);

comment on column pedido_centro_costo.pedido_num is 'numStr, el mismo del resto del sistema. En gestion_produccion vive en el campo "pedido".';


-- ── 3. mayor: la columna del centro de costo ──────────────────────────────
alter table mayor add column if not exists centro_costo_id smallint references centros_costo(id);

-- Misma idea que cantidad_con_unidad: un consumo sin centro de costo no sirve
-- para nada — no se puede sacar margen con él — así que la base no lo acepta.
-- Los otros grupos (GASTO, COMPRA, AJUSTE) pueden no tenerlo.
do $$
begin
  alter table mayor add constraint consumo_con_ceco
    check (grupo <> 'CONSUMO' or centro_costo_id is not null);
exception when duplicate_object then null;
end $$;

create index if not exists idx_mayor_ceco on mayor (centro_costo_id) where centro_costo_id is not null;


-- ── 4. v_mayor con el CECO ────────────────────────────────────────────────
-- Se borra y se recrea en vez de "create or replace": Postgres solo deja
-- AGREGAR columnas al final de una vista existente, y acá las del centro de
-- costo van junto a las demás para que la vista se lea en orden.
drop view if exists v_mayor;
create view v_mayor with (security_invoker = true) as
select
  m.id, m.fecha, m.mes, m.mes_n, m.numero_doc, m.descripcion,
  m.cantidad, m.unidad_id, u.clave as unidad,
  m.producto, m.madera,
  m.inventario_id, i.sku, i.descripcion as item,
  m.categoria_id, c.nombre as categoria, c.destino,
  m.centro_costo_id, cc.codigo as ceco, cc.nombre as ceco_nombre, cc.tipo as ceco_tipo,
  m.monto, m.grupo, m.origen_tipo, m.factura_linea_id, m.pedido_num, m.nota,
  case when c.destino = 'excluida' then 'Excluido' else 'Gasto real' end as estado,
  -- Gasto real = plata que salió, incluida la compra de materiales.
  case when c.destino = 'excluida' then 0 else m.monto end as gasto_real,
  -- Costo del período = devengado. La compra de bodega vale 0 hasta que el
  -- taller la consume; el consumo sí cuenta aunque la plata haya salido antes.
  case when c.destino = 'excluida' or m.grupo = 'COMPRA' then 0 else m.monto end as costo_periodo
from mayor m
join gasto_categorias c on c.id = m.categoria_id
left join unidades      u  on u.id  = m.unidad_id
left join inventario    i  on i.id  = m.inventario_id
left join centros_costo cc on cc.id = m.centro_costo_id;

-- Margen por pedido, que era la finalidad de todo esto. El costo sale del
-- consumo real; la venta la pone la app desde gestion_finanzas, que el taller
-- no puede leer, así que acá solo va el costo.
create or replace view v_costo_pedido with (security_invoker = true) as
select
  m.pedido_num,
  cc.codigo as ceco,
  cc.nombre as ceco_nombre,
  min(m.fecha) as primer_consumo,
  count(*)     as lineas,
  sum(m.monto) as costo_materiales
from mayor m
join centros_costo cc on cc.id = m.centro_costo_id
where m.grupo = 'CONSUMO' and m.pedido_num is not null
group by m.pedido_num, cc.codigo, cc.nombre;


-- ══════════════════════════════════════════════════════════════════════════
-- SEGURIDAD
-- El taller ESCRIBE consumos pero NO LEE el mayor: ahí están los sueldos de
-- todo el equipo. La restricción es del servidor, no de la pantalla.
-- ══════════════════════════════════════════════════════════════════════════

alter table centros_costo enable row level security;
alter table centros_costo force  row level security;

drop policy if exists "equipo lee centros_costo" on centros_costo;
create policy "equipo lee centros_costo" on centros_costo
  for select to authenticated using (zaru_rol() in ('admin','taller'));

drop policy if exists "admin escribe centros_costo" on centros_costo;
create policy "admin escribe centros_costo" on centros_costo
  for all to authenticated using (zaru_rol() = 'admin') with check (zaru_rol() = 'admin');


alter table pedido_centro_costo enable row level security;
alter table pedido_centro_costo force  row level security;

-- El taller sí escribe acá: asignar el CECO es parte de consumir.
drop policy if exists "admin y taller pedido_ceco" on pedido_centro_costo;
create policy "admin y taller pedido_ceco" on pedido_centro_costo
  for all to authenticated
  using (zaru_rol() in ('admin','taller')) with check (zaru_rol() in ('admin','taller'));


-- El taller puede INSERTAR en el mayor, y solo consumos. No hay policy de
-- SELECT para él, así que no lee ni una fila: ni sueldos, ni gastos, ni las
-- compras. El with check es lo que impide que se cuele un GASTO disfrazado.
drop policy if exists "taller inserta consumos" on mayor;
create policy "taller inserta consumos" on mayor
  for insert to authenticated
  with check (
    zaru_rol() = 'taller'
    and grupo = 'CONSUMO'
    and centro_costo_id is not null
    and pedido_num is not null
  );


-- ── 5. Nota sobre PostgREST ───────────────────────────────────────────────
-- Como el taller no tiene SELECT sobre mayor, sus INSERT tienen que mandarse
-- con "Prefer: return=minimal". Con return=representation PostgREST intenta
-- leer la fila recién escrita y falla con 401. En el HTML eso lo resuelve
-- sbInsertMudo().
