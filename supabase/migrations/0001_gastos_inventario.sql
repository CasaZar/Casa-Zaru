-- ══════════════════════════════════════════════════════════════════════════
-- MIGRACIÓN 0001 · GASTOS, INVENTARIO Y LIBRO MAYOR
--
-- PROYECTO SUPABASE: padnttpgzuotxeipjrry (el que usa index.html)
--   Ojo: en el panel se llama «Cotizador clientes», pero es donde viven las
--   tablas gestion_*. El otro proyecto (cmxqorsyxoltrakxawro,
--   «cotizador-interno») es el del manual de valores del cotizador.
--
-- Primera migración versionada. Van en supabase/migrations/ con el formato
-- <NNNN>_<nombre>.sql, correlativas desde 0001. Los ceros a la izquierda no
-- son adorno: la versión se guarda como TEXTO, así que sin relleno la 10
-- quedaría ordenada entre la 1 y la 2.
--
-- El registro de qué se aplicó lo lleva Supabase en
-- supabase_migrations.schema_migrations (Database → Migrations en el panel).
-- No hay que llevar una tabla de migraciones propia.
--
-- ── QUÉ RESUELVE ──────────────────────────────────────────────────────────
--
--   Factura ─┬─> Inventario (insumos) ──> Taller consume ──┐
--            │                                             ├──> Libro Mayor
--            └─> Gastos directos (sueldos, luz, bencina) ──┘
--
-- La diferencia entre las dos ramas es CUÁNDO la plata se vuelve gasto. Un
-- sueldo es gasto el día que se paga. Una tineta de vitrificado no: es un
-- activo hasta que el taller la usa en un pedido. Por eso los insumos pasan
-- por bodega antes de llegar al mayor.
--
-- ── POR QUÉ ESTAS TABLAS NO SON COMO LAS gestion_* ────────────────────────
-- Las cinco tablas viejas (gestion_pedidos, gestion_produccion, …) guardan
-- `num text` + `data jsonb`: un blob por registro. Sirve para pedidos, donde
-- todo cuelga del número de pedido y no hay relaciones entre entidades.
-- Acá no alcanza: un movimiento del mayor tiene que apuntar a la línea de la
-- factura que lo originó, esa línea a un ítem de bodega, y ese ítem a su
-- unidad de medida. Dentro de un jsonb esos vínculos son texto que nadie
-- valida — y en datos contables, un vínculo roto es plata que no cuadra.
-- Por eso: id numérico secuencial en todas, y llaves foráneas de verdad.
--
-- ── PRECISIÓN ─────────────────────────────────────────────────────────────
-- Las cantidades son numeric(14,3), no enteros ni float binario: media
-- pulgada de Coihue son $14.000 y hay insumos que se consumen de a 0,002 por
-- m². numeric es exacto — con double precision, 0,1 + 0,2 no da 0,3 y la
-- valorización de bodega se va desviando de a centavos.
-- Los valores unitarios van a numeric(14,2) (un litro de sellador sale
-- $3.982,46) y los montos en pesos son integer.
--
-- ── IVA ───────────────────────────────────────────────────────────────────
-- Todo lo que entra al mayor y a bodega va SIN IVA: el IVA de compra es
-- crédito fiscal. La factura guarda neto, iva y total por separado.
--
-- Pegar completo en Supabase → proyecto Gestión → SQL Editor → Run.
-- Es idempotente: se puede correr dos veces sin romper nada.
-- ══════════════════════════════════════════════════════════════════════════


-- ── 1. Helper: el rol del usuario logueado ────────────────────────────────
-- Se lee de gestion_usuarios, la misma tabla que ya usa cargarPermisos() en
-- el HTML. security definer para que las policies puedan consultarla sin
-- que el usuario tenga permiso de leer esa tabla entera.
create or replace function zaru_rol()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select rol from gestion_usuarios
  where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  limit 1
$$;
grant execute on function zaru_rol() to authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- TABLAS DE REFERENCIA
-- ══════════════════════════════════════════════════════════════════════════

-- ── 2. unidades ───────────────────────────────────────────────────────────
-- Una cantidad sin unidad no significa nada: "2" puede ser 2 tinetas o 2
-- litros, y entre esas dos hay un factor 3,7. Que la unidad sea una FK y no
-- un texto libre es lo que impide que aparezcan "lt", "LT", "litro" y "Lt"
-- como cuatro unidades distintas.
create table if not exists unidades (
  id        smallint generated always as identity primary key,
  clave     text     not null unique,
  nombre    text     not null,
  plural    text     not null,
  decimales smallint not null default 3 check (decimales between 0 and 4)
);
comment on column unidades.decimales is 'Con cuántos decimales se muestra esta unidad en pantalla y en el export.';

insert into unidades (clave, nombre, plural, decimales) values
  ('un',    'unidad',         'unidades',     3),
  ('mt',    'metro',          'metros',       3),
  ('m2',    'metro cuadrado', 'm²',           3),
  ('lt',    'litro',          'litros',       3),
  ('gl',    'galón',          'galones',      3),
  ('kg',    'kilo',           'kilos',        3),
  ('pulg',  'pulgada',        'pulgadas',     2),
  ('hh',    'hora hombre',    'horas hombre', 2),
  ('pedido','por pedido',     'por pedido',   0)
on conflict (clave) do nothing;


-- ── 3. gasto_categorias ───────────────────────────────────────────────────
-- Son exactamente las 25 de la planilla que ya recibe el contador, no un plan
-- de cuentas nuevo. Lo único que se agrega es `destino`, que es la decisión
-- de fondo del módulo:
--   inventario → pasa por bodega, se vuelve gasto al consumirse
--   gasto      → va derecho al mayor
--   excluida   → no es gasto (traspasos entre cuentas propias, reembolsos)
--   pendiente  → todavía no se sabe; hay que clasificarla antes de cerrar el mes
create table if not exists gasto_categorias (
  id      smallint generated always as identity primary key,
  nombre  text     not null unique,
  destino text     not null check (destino in ('inventario','gasto','excluida','pendiente')),
  orden   smallint not null default 0,
  activa  boolean  not null default true
);

insert into gasto_categorias (nombre, destino, orden) values
  -- Pasan por inventario (34% del gasto: $40M en el primer semestre 2026)
  ('Materiales e insumos',             'inventario',  1),
  ('Madera (proveedores)',             'inventario',  2),
  ('Embalaje',                         'inventario',  3),
  -- Gasto directo
  ('Sueldos y remuneraciones',         'gasto',      10),
  ('Imposiciones (Previred)',          'gasto',      11),
  ('Impuestos (SII)',                  'gasto',      12),
  ('Arriendo',                         'gasto',      13),
  ('Servicios básicos',                'gasto',      14),
  ('Combustible (bencina)',            'gasto',      15),
  ('Transporte / viajes',              'gasto',      16),
  ('Colación y alimentación equipo',   'gasto',      17),
  ('Publicidad Meta',                  'gasto',      18),
  ('Publicidad Google',                'gasto',      19),
  ('Software y suscripciones',         'gasto',      20),
  ('Fletes y logística',               'gasto',      21),
  ('Mantención y reparaciones',        'gasto',      22),
  ('Maquinaria y herramientas',        'gasto',      23),
  ('Comisiones bancarias',             'gasto',      24),
  ('Créditos y deudas (cuotas)',       'gasto',      25),
  ('Gastos administrativos',           'gasto',      26),
  ('Post venta',                       'gasto',      27),
  -- No son gasto: la columna "Estado" de la planilla las excluye del total
  ('Traspaso interno (no es gasto)',      'excluida', 40),
  ('Préstamos socios (no es gasto)',      'excluida', 41),
  ('Anulado / reembolsado (no es gasto)', 'excluida', 42),
  -- Cola de pendientes
  ('POR CLASIFICAR',                   'pendiente',  90)
on conflict (nombre) do nothing;


-- ── 4. proveedores ────────────────────────────────────────────────────────
-- El RUT es la identidad real del proveedor: "Maderas Voipir", "MADERAS
-- VOIPIR VILLARRICA" y "Voipir" son el mismo. Se guarda normalizado (solo
-- dígitos y el dígito verificador) para que la unicidad funcione de verdad.
-- Es nullable porque hay boletas de honorarios y compras sin RUT a la vista;
-- Postgres permite varios NULL en un unique.
create table if not exists proveedores (
  id        bigint generated always as identity primary key,
  rut       text unique,
  nombre    text not null,
  creado_en timestamptz not null default now()
);
comment on column proveedores.rut is 'Normalizado: sin puntos ni guion, en minúscula la k. Ej: 761234567 / 12345678k';


-- ══════════════════════════════════════════════════════════════════════════
-- TABLAS DEL CIRCUITO
-- ══════════════════════════════════════════════════════════════════════════

-- ── 5. inventario ─────────────────────────────────────────────────────────
-- El stock se lleva SIEMPRE en la unidad del ítem (lt, mt, m2, un, pulg…),
-- nunca en envases: la conversión envase → unidad de stock la hace la app al
-- cargar la factura, y acá llega ya convertida.
create table if not exists inventario (
  id                    bigint   generated always as identity primary key,
  sku                   text     not null unique,
  descripcion           text     not null,
  categoria             text,
  unidad_id             smallint not null references unidades(id),
  stock                 numeric(14,3) not null default 0,
  costo_prom            numeric(14,2) not null default 0,
  ultimo_costo          numeric(14,2) not null default 0,
  ultima_compra         date,
  envase_default        numeric(14,3) not null default 1 check (envase_default > 0),
  unidad_compra_default text,
  item_k                text,
  especie               text,
  minimo                numeric(14,3) not null default 0,
  actualizado_en        timestamptz   not null default now()
);
comment on column inventario.item_k  is 'Clave del ítem en INVENTARIO_ITEMS del HTML: es el puente con el costo estándar por m².';
comment on column inventario.especie is 'Solo para madera (COIHUE, RAULÍ…). Define el factor pulgadas/m² al descontar consumo.';
comment on column inventario.stock   is 'Puede quedar NEGATIVO a propósito: significa que se consumió algo que nunca se cargó. Es una alerta, no un error.';


-- ── 6. facturas ───────────────────────────────────────────────────────────
create table if not exists facturas (
  id           bigint   generated always as identity primary key,
  proveedor_id bigint   not null references proveedores(id),
  numero_doc   text     not null,
  tipo         text     not null default 'FACTURA' check (tipo in ('FACTURA','BOLETA','NC')),
  fecha        date     not null,
  mes          text     not null,
  mes_n        smallint not null check (mes_n between 1 and 12),
  neto         integer  not null default 0,
  iva          integer  not null default 0,
  total        integer  not null default 0,
  estado_pago  text     not null default 'pendiente' check (estado_pago in ('pendiente','pagada')),
  origen       text     not null default 'manual'    check (origen in ('manual','foto','excel')),
  procesada    boolean  not null default false,
  iva_incluido boolean  not null default false,
  creado_en    timestamptz not null default now(),
  -- El mismo proveedor no puede emitir dos veces el mismo folio. Esto es lo
  -- que hace que reimportar el Excel diario no duplique nada, sin depender
  -- de que la app se acuerde de chequearlo.
  unique (proveedor_id, numero_doc)
);
comment on column facturas.mes          is 'Mes contable. Se guarda porque no siempre sale de la fecha: en la planilla hay documentos del 31-dic cargados como ENERO.';
comment on column facturas.procesada    is 'true = ya impactó bodega y libro mayor.';
comment on column facturas.iva_incluido is 'true solo en el histórico migrado del Excel, donde los montos venían con IVA.';


-- ── 7. factura_lineas ─────────────────────────────────────────────────────
-- Acá se bifurca el diagrama: cada línea es INVENTARIO (entra a bodega) o
-- GASTO (va derecho al mayor).
create table if not exists factura_lineas (
  id            bigint   generated always as identity primary key,
  factura_id    bigint   not null references facturas(id) on delete cascade,
  linea_n       smallint not null,
  tipo          text     not null check (tipo in ('INVENTARIO','GASTO')),
  descripcion   text,
  -- Rama inventario
  inventario_id bigint   references inventario(id),
  cant_envases  numeric(14,3),
  unidad_compra text,
  contenido     numeric(14,3),
  cantidad      numeric(14,3),
  unidad_id     smallint references unidades(id),
  unit_neto     numeric(14,2),
  producto      text,
  madera        text,
  -- Rama gasto
  categoria_id  smallint references gasto_categorias(id),
  -- Ambas
  total_neto    integer  not null default 0,
  nota          text,
  unique (factura_id, linea_n),
  -- La regla de fondo, puesta donde no se puede saltar: una línea de bodega
  -- tiene ítem, cantidad Y unidad; una de gasto tiene categoría. No existe
  -- la línea a medias, ni la cantidad sin unidad, ni la que es las dos cosas.
  constraint linea_coherente check (
    (tipo = 'INVENTARIO'
      and inventario_id is not null
      and cantidad      is not null
      and unidad_id     is not null
      and categoria_id  is null)
    or
    (tipo = 'GASTO'
      and categoria_id  is not null
      and inventario_id is null
      and cantidad      is null)
  )
);


-- ── 8. mayor ──────────────────────────────────────────────────────────────
-- El libro. Un movimiento por fila, con las columnas de la planilla del
-- contador (menos Cuenta y Detalle, más N° documento y Unidad).
-- `estado` y `gasto_real` NO son columnas: son fórmulas, y viven en la vista
-- v_mayor de más abajo. Guardar el resultado de una fórmula es pedir que
-- algún día no calce con la fórmula.
create table if not exists mayor (
  id               bigint   generated always as identity primary key,
  fecha            date     not null,
  mes              text     not null,
  mes_n            smallint not null check (mes_n between 1 and 12),
  numero_doc       text,
  descripcion      text     not null,
  cantidad         numeric(14,3),
  unidad_id        smallint references unidades(id),
  producto         text,
  madera           text,
  inventario_id    bigint   references inventario(id),
  categoria_id     smallint not null references gasto_categorias(id),
  monto            integer  not null default 0,
  -- COMPRA = entrada de bodega: salió de la caja pero todavía no es costo.
  -- CONSUMO = el taller la usó en un pedido; ahí sí se vuelve costo.
  grupo            text not null default 'GASTO' check (grupo in ('GASTO','COMPRA','CONSUMO','AJUSTE')),
  origen_tipo      text not null default 'manual' check (origen_tipo in ('manual','factura','consumo','ajuste')),
  factura_linea_id bigint references factura_lineas(id) on delete set null,
  pedido_num       text,
  nota             text,
  creado_en        timestamptz not null default now(),
  -- La regla de CLAUDE.md, hecha cumplir por la base: ninguna cantidad
  -- existe sin su unidad al lado.
  constraint cantidad_con_unidad check (cantidad is null or unidad_id is not null)
);
comment on column mayor.pedido_num is 'N° de pedido (gestion_produccion.num) en los movimientos de consumo. Sin FK a propósito: borrar un pedido viejo no tiene por qué bloquearse por un asiento contable.';
comment on column mayor.monto      is 'Neto, sin IVA. El IVA de compra es crédito fiscal.';


-- ══════════════════════════════════════════════════════════════════════════
-- VISTAS
-- Las fórmulas de la planilla viven acá y en un solo lugar, así el panel, el
-- export y cualquier consulta directa dan siempre el mismo número.
-- security_invoker = las vistas respetan el RLS del usuario que consulta; sin
-- esto correrían con los permisos del dueño y filtrarían datos.
-- ══════════════════════════════════════════════════════════════════════════

create or replace view v_mayor with (security_invoker = true) as
select
  m.id, m.fecha, m.mes, m.mes_n, m.numero_doc, m.descripcion,
  m.cantidad, m.unidad_id, u.clave as unidad,
  m.producto, m.madera,
  m.inventario_id, i.sku, i.descripcion as item,
  m.categoria_id, c.nombre as categoria, c.destino,
  m.monto, m.grupo, m.origen_tipo, m.factura_linea_id, m.pedido_num, m.nota,
  case when c.destino = 'excluida' then 'Excluido' else 'Gasto real' end as estado,
  -- Gasto real = plata que salió, incluida la compra de materiales.
  -- Es la cifra que ya conoce el contador.
  case when c.destino = 'excluida' then 0 else m.monto end as gasto_real,
  -- Costo del período = devengado: la compra de bodega vale 0 hasta que el
  -- taller la consume. Es la que da margen real por pedido.
  case when c.destino = 'excluida' or m.grupo = 'COMPRA' then 0 else m.monto end as costo_periodo
from mayor m
join gasto_categorias c on c.id = m.categoria_id
left join unidades   u on u.id = m.unidad_id
left join inventario i on i.id = m.inventario_id;

create or replace view v_facturas with (security_invoker = true) as
select
  f.*, p.nombre as proveedor, p.rut,
  (select count(*) from factura_lineas l where l.factura_id = f.id) as n_lineas,
  (select count(*) from factura_lineas l where l.factura_id = f.id and l.tipo = 'INVENTARIO') as n_inventario
from facturas f
join proveedores p on p.id = f.proveedor_id;

create or replace view v_inventario with (security_invoker = true) as
select
  i.*, u.clave as unidad, u.decimales,
  round(i.stock * i.costo_prom) as valorizado
from inventario i
join unidades u on u.id = i.unidad_id;


-- ══════════════════════════════════════════════════════════════════════════
-- SEGURIDAD (RLS)
--   admin  → todo
--   taller → lee referencias, lee y edita inventario (recibe mercadería y
--            hace la toma física). No ve facturas ni mayor.
--   resto  → nada
-- ══════════════════════════════════════════════════════════════════════════

-- Referencias: las lee cualquiera del equipo (son catálogos, no datos
-- sensibles); escribirlas es solo del admin.
do $$
declare t text;
begin
  foreach t in array array['unidades','gasto_categorias','proveedores'] loop
    execute format('alter table %I enable row level security', t);
    execute format('alter table %I force  row level security', t);
    execute format('drop policy if exists "equipo lee %1$s" on %1$I', t);
    execute format('create policy "equipo lee %1$s" on %1$I for select to authenticated using (zaru_rol() in (''admin'',''taller''))', t);
    execute format('drop policy if exists "admin escribe %1$s" on %1$I', t);
    execute format('create policy "admin escribe %1$s" on %1$I for all to authenticated using (zaru_rol() = ''admin'') with check (zaru_rol() = ''admin'')', t);
  end loop;
end $$;

-- Proveedores: el admin los crea al cargar facturas. (Cubierto por la policy
-- "admin escribe proveedores" del bloque de arriba.)

-- Inventario: la única tabla que el taller también escribe.
alter table inventario enable row level security;
alter table inventario force  row level security;

drop policy if exists "admin y taller leen inventario" on inventario;
create policy "admin y taller leen inventario" on inventario
  for select to authenticated using (zaru_rol() in ('admin','taller'));

drop policy if exists "admin y taller crean inventario" on inventario;
create policy "admin y taller crean inventario" on inventario
  for insert to authenticated with check (zaru_rol() in ('admin','taller'));

drop policy if exists "admin y taller editan inventario" on inventario;
create policy "admin y taller editan inventario" on inventario
  for update to authenticated using (zaru_rol() in ('admin','taller'))
  with check (zaru_rol() in ('admin','taller'));

-- Borrar un SKU es solo del admin: el taller ajusta cantidades, no elimina
-- ítems del catálogo.
drop policy if exists "admin borra inventario" on inventario;
create policy "admin borra inventario" on inventario
  for delete to authenticated using (zaru_rol() = 'admin');

-- Facturas, líneas y mayor: solo admin.
do $$
declare t text;
begin
  foreach t in array array['facturas','factura_lineas','mayor'] loop
    execute format('alter table %I enable row level security', t);
    execute format('alter table %I force  row level security', t);
    execute format('drop policy if exists "solo admin %1$s" on %1$I', t);
    execute format('create policy "solo admin %1$s" on %1$I for all to authenticated using (zaru_rol() = ''admin'') with check (zaru_rol() = ''admin'')', t);
  end loop;
end $$;


-- ══════════════════════════════════════════════════════════════════════════
-- ÍNDICES
-- El mayor crece ~1.000 filas por semestre y siempre se filtra por mes o
-- categoría; las líneas siempre se traen por factura.
-- ══════════════════════════════════════════════════════════════════════════
create index if not exists idx_mayor_mes        on mayor (mes);
create index if not exists idx_mayor_fecha      on mayor (fecha);
create index if not exists idx_mayor_categoria  on mayor (categoria_id);
create index if not exists idx_mayor_pedido     on mayor (pedido_num) where pedido_num is not null;
create index if not exists idx_mayor_inventario on mayor (inventario_id);
create index if not exists idx_lineas_factura   on factura_lineas (factura_id);
create index if not exists idx_lineas_inv       on factura_lineas (inventario_id);
create index if not exists idx_facturas_mes     on facturas (mes);
create index if not exists idx_facturas_prov    on facturas (proveedor_id);


-- ══════════════════════════════════════════════════════════════════════════
-- ROL 'taller'
-- gestion_usuarios ya existe con la columna rol ('admin' | 'vendedor').
-- Para habilitar a alguien del taller, después de invitarlo por correo:
--   update gestion_usuarios set rol = 'taller' where email = 'jefe.taller@…';
-- Si la columna tiene un CHECK que solo acepta admin/vendedor, hay que
-- ampliarlo. Esto no falla si el constraint no existe.
-- ══════════════════════════════════════════════════════════════════════════
do $$
begin
  alter table gestion_usuarios drop constraint if exists gestion_usuarios_rol_check;
  alter table gestion_usuarios add constraint gestion_usuarios_rol_check
    check (rol in ('admin','vendedor','taller'));
exception when others then
  raise notice 'No se pudo ajustar el check de rol (%). Revisalo a mano si hace falta.', sqlerrm;
end $$;
