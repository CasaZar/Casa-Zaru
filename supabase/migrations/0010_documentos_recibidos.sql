-- ══════════════════════════════════════════════════════════════════════════
-- MIGRACIÓN 0010 · DOCUMENTOS RECIBIDOS (staging desde Wasabil)
--
-- PROYECTO SUPABASE: padnttpgzuotxeipjrry (el mismo de index.html y de 0001)
--
-- ── QUÉ RESUELVE ──────────────────────────────────────────────────────────
-- Facturas/boletas/notas que OTROS proveedores le emiten a Casa Zaru (gasto),
-- traídas desde Wasabil vía MCP (`get_documents` + `get_document`), para
-- clasificarlas a mano antes de que pasen a `factura_lineas`/`mayor` (0001):
--
--   Wasabil (recibidos) ──> documentos_recibidos(_lineas) ──> clasificación
--   manual (INVENTARIO/GASTO, misma columna `tipo` que factura_lineas) ──>
--   -- cuando esté maduro, un paso posterior las vuelca a factura_lineas.
--
-- Es TRANSITORIA a propósito, igual que la 0007 lo fue — con la diferencia
-- de fondo que la hizo revertirse en la 0009: la 0007 tomaba documentos que
-- Wasabil EMITE a clientes de Casa Zaru (venta). Esta toma los que Wasabil
-- registra como RECIBIDOS de un proveedor (`received: true` en el documento
-- de Wasabil) — el discriminador es ese booleano, no el código SII: un
-- mismo tipo SII (33, 34, 39, 41…) aparece tanto emitido como recibido, y
-- el tipo 46 (factura de compra) es un caso emitido por Casa Zaru en nombre
-- de un proveedor extranjero (Meta/Google/Shopify) — NO es un documento que
-- llega solo, aunque conceptualmente sea "gasto". Confirmado con datos
-- reales: de 1.593 documentos `trx_type=expense` en Wasabil, 116 tienen
-- `received: false` (son de este tipo) — quedan excluidos siempre.
--
-- Quedan excluidas también, a propósito, las Notas de Crédito (sii_type 61):
-- son devoluciones que restan del gasto, no gasto nuevo — no encajan en el
-- flujo Factura/Boleta → ¿Tiene Glosa? → Inventario/Gasto Fijo. Se filtran
-- en el paso de importación (no hay constraint acá): si más adelante hace
-- falta trazarlas, se agregan aparte con su propio criterio.
--
-- ── GLOSA ─────────────────────────────────────────────────────────────────
-- El campo `description` de cada línea de Wasabil. En el piloto de agosto
-- 2026 (79 documentos, 91 líneas) salió vacío en el 88% de los casos —
-- mayormente porque son boletas emitidas vía SIIApi (issuer_id 19) donde el
-- SII no entrega detalle de línea (`name` queda literal "Detalle no
-- disponible"). `tiene_glosa` trata como vacíos "", null Y "." (apareció un
-- caso real con glosa = "." en una factura de Imperial S.A.) — btrim sin
-- ese caso lo hubiera contado como "con glosa" por error.
--
-- ── MONTOS ────────────────────────────────────────────────────────────────
-- Se usan los campos `sent_*` de Wasabil (sent_nsubtotal/sent_niva/
-- sent_ntotal a nivel documento, sent_subtotal/sent_iva/sent_total a nivel
-- línea) y NO los campos sin `sent_` — estos últimos vienen a veces con
-- fracciones de peso (ej. "iva": 6648.1) por redondeo del cálculo de
-- impuesto por unidad; los `sent_*` ya vienen en pesos enteros, igual que
-- el resto del sistema (ver regla de montos en CLAUDE.md).
--
-- Depende de zaru_rol() (0001), inventario e gasto_categorias (0001).
-- Pegar completo en Supabase → proyecto Gestión → SQL Editor → Run.
-- Es idempotente: se puede correr dos veces sin romper nada.
-- No olvidar registrar la fila en supabase_migrations.schema_migrations
-- (CLAUDE.md — Migraciones) después de aplicarla a mano.
-- ══════════════════════════════════════════════════════════════════════════


-- ── 1. documentos_recibidos ────────────────────────────────────────────────
create table if not exists documentos_recibidos (
  id                    bigint      generated always as identity primary key,
  wasabil_document      bigint      not null unique,
  wasabil_uuid          uuid        not null unique,
  folio                 text        not null,
  sii_document_type_id  smallint    not null,
  sii_tipo_nombre       text,
  proveedor_rut         text,
  proveedor_nombre      text        not null,
  fecha                 date        not null,
  neto                  integer     not null default 0,
  iva                   integer     not null default 0,
  total                 integer     not null default 0,
  -- 'pendiente' hasta que TODAS sus líneas tengan tipo asignado. Se recalcula
  -- desde la app al clasificar, no hay trigger cruzado entre tablas acá.
  estado                text        not null default 'pendiente' check (estado in ('pendiente','clasificado')),
  importado_en          timestamptz not null default now()
);
comment on column documentos_recibidos.wasabil_document is 'Campo `document` de Wasabil (id interno del documento, ej. 20260900007388).';
comment on column documentos_recibidos.neto is 'sent_nsubtotal de Wasabil. Pesos enteros.';
comment on column documentos_recibidos.iva  is 'sent_niva de Wasabil. Pesos enteros.';
comment on column documentos_recibidos.total is 'sent_ntotal de Wasabil. Pesos enteros.';


-- ── 2. documentos_recibidos_lineas ─────────────────────────────────────────
-- Acá se bifurca el diagrama, igual que en factura_lineas (0001): cada línea
-- termina siendo INVENTARIO o GASTO. A diferencia de factura_lineas, `tipo`
-- empieza en NULL — recién se fija al clasificar a mano.
create table if not exists documentos_recibidos_lineas (
  id             bigint   generated always as identity primary key,
  documento_id   bigint   not null references documentos_recibidos(id) on delete cascade,
  linea_n        smallint not null,
  item_nombre    text,
  glosa          text,
  cantidad       numeric(14,3),
  precio_unit    numeric(14,2),
  subtotal       integer  not null default 0,
  iva            integer  not null default 0,
  total          integer  not null default 0,
  codigo         text,
  es_exento      boolean  not null default false,
  -- Rama inventario
  tipo           text     check (tipo in ('INVENTARIO','GASTO')),
  inventario_id  bigint   references inventario(id),
  -- Rama gasto
  categoria_id   smallint references gasto_categorias(id),
  -- Auditoría de quién clasificó
  clasificado_por text,
  clasificado_en  timestamptz,
  unique (documento_id, linea_n),
  -- Mientras tipo es null, no hay más regla. Una vez clasificada, la misma
  -- coherencia que factura_lineas: INVENTARIO tiene ítem+cantidad y no
  -- categoría; GASTO tiene categoría y no ítem.
  constraint linea_transitoria_coherente check (
    tipo is null
    or (tipo = 'INVENTARIO' and inventario_id is not null and cantidad is not null and categoria_id is null)
    or (tipo = 'GASTO'      and categoria_id  is not null and inventario_id is null)
  )
);
comment on column documentos_recibidos_lineas.glosa is 'Campo `description` de Wasabil, tal cual llegó (puede venir vacío o con un simple ".").';

-- tiene_glosa no se guarda a mano: se recalcula sola. Trata como "sin glosa"
-- vacío, null Y el caso real "." (Imperial S.A., agosto 2026).
alter table documentos_recibidos_lineas
  drop column if exists tiene_glosa;
alter table documentos_recibidos_lineas
  add column tiene_glosa boolean
  generated always as (
    glosa is not null and btrim(glosa) <> '' and btrim(glosa) <> '.'
  ) stored;


-- ── 3. Sello automático de quién y cuándo clasificó ────────────────────────
create or replace function _stamp_linea_clasificada()
returns trigger
language plpgsql
as $$
begin
  if (new.tipo is distinct from old.tipo) and new.tipo is not null then
    new.clasificado_en := now();
    new.clasificado_por := coalesce(auth.jwt() ->> 'email', new.clasificado_por);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_linea_clasificada on documentos_recibidos_lineas;
create trigger trg_linea_clasificada
  before update on documentos_recibidos_lineas
  for each row execute function _stamp_linea_clasificada();


-- ── 4. Vista de la cola pendiente ───────────────────────────────────────────
create or replace view v_documentos_recibidos_pendientes with (security_invoker = true) as
select
  l.id as linea_id, l.documento_id, l.linea_n, l.item_nombre, l.glosa, l.tiene_glosa,
  l.cantidad, l.precio_unit, l.subtotal, l.iva, l.total, l.codigo, l.es_exento,
  d.wasabil_document, d.folio, d.fecha, d.proveedor_rut, d.proveedor_nombre,
  d.sii_document_type_id, d.sii_tipo_nombre
from documentos_recibidos_lineas l
join documentos_recibidos d on d.id = l.documento_id
where l.tipo is null
order by d.fecha, d.wasabil_document, l.linea_n;


-- ══════════════════════════════════════════════════════════════════════════
-- SEGURIDAD (RLS) — mismo criterio que facturas/factura_lineas en 0001:
-- solo admin. Son documentos tributarios de proveedores, y Gastos ya está
-- vedado para vendedor/taller en el resto del sistema.
-- ══════════════════════════════════════════════════════════════════════════
do $$
declare t text;
begin
  foreach t in array array['documentos_recibidos','documentos_recibidos_lineas'] loop
    execute format('alter table %I enable row level security', t);
    execute format('alter table %I force  row level security', t);
    execute format('drop policy if exists "solo admin %1$s" on %1$I', t);
    execute format('create policy "solo admin %1$s" on %1$I for all to authenticated using (zaru_rol() = ''admin'') with check (zaru_rol() = ''admin'')', t);
  end loop;
end $$;


-- ══════════════════════════════════════════════════════════════════════════
-- ÍNDICES
-- ══════════════════════════════════════════════════════════════════════════
create index if not exists idx_docrecibidos_estado     on documentos_recibidos (estado);
create index if not exists idx_docrecibidos_fecha      on documentos_recibidos (fecha);
create index if not exists idx_docrecibidos_proveedor  on documentos_recibidos (proveedor_rut);
create index if not exists idx_doclineas_documento     on documentos_recibidos_lineas (documento_id);
create index if not exists idx_doclineas_pendientes    on documentos_recibidos_lineas (tipo) where tipo is null;
create index if not exists idx_doclineas_inventario    on documentos_recibidos_lineas (inventario_id);
