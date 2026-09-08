-- ══════════════════════════════════════════════════════════════════════════
-- MIGRACIÓN 0016 · RECLASIFICACIÓN DE LÍNEAS EN RECIBIDOS
--
-- PROYECTO SUPABASE: padnttpgzuotxeipjrry (el mismo de 0001 y 0010)
--
-- ── QUÉ RESUELVE ──────────────────────────────────────────────────────────
-- En documentos_recibidos_lineas (0010), el 88% de las líneas del piloto de
-- agosto 2026 llegaron sin glosa ni nombre de ítem (boletas emitidas vía
-- SIIApi, donde el SII no entrega detalle de línea). Hoy no hay forma de
-- corregir esos datos desde la app: el filtro "Solo sin Ítem/Glosa" las
-- encuentra, pero no las arregla.
--
-- Además falta unidad_id: sin ella, `cantidad` es un número sin significado,
-- contra la regla del proyecto de que ninguna cantidad existe sin su unidad
-- al lado (ver `cantidad_con_unidad` en mayor, 0001).
--
-- Este script agrega lo que le falta a la tabla para soportar una acción de
-- "Reclasificar" por línea: unidad, un snapshot de lo que trajo Wasabil
-- (para no perder el dato original de un documento tributario), y el sello
-- de quién/cuándo corrigió. NO agrega la clasificación INVENTARIO/GASTO —
-- eso queda para una etapa posterior, a propósito (ver 0010).
--
-- Depende de documentos_recibidos_lineas, documentos_recibidos y unidades
-- (0010, 0001).
-- Pegar completo en Supabase → proyecto Gestión → SQL Editor → Run, o
-- `supabase db push`. Es idempotente: se puede correr dos veces sin romper
-- nada.
-- ══════════════════════════════════════════════════════════════════════════


-- ── 1. Unidad de medida ────────────────────────────────────────────────────
alter table documentos_recibidos_lineas
  add column if not exists unidad_id smallint references unidades(id);


-- ── 2. Snapshot inmutable de lo que trajo Wasabil ──────────────────────────
-- Se llenan solas al insertar (trigger de abajo) y no se tocan nunca más:
-- son "lo que decía el documento", para comparar contra lo corregido.
alter table documentos_recibidos_lineas
  add column if not exists item_nombre_original text,
  add column if not exists glosa_original        text,
  add column if not exists cantidad_original     numeric(14,3),
  add column if not exists precio_unit_original  numeric(14,2);

comment on column documentos_recibidos_lineas.item_nombre_original is 'Snapshot de item_nombre tal como llegó de Wasabil. Nunca se edita.';
comment on column documentos_recibidos_lineas.glosa_original        is 'Snapshot de glosa tal como llegó de Wasabil. Nunca se edita.';
comment on column documentos_recibidos_lineas.cantidad_original     is 'Snapshot de cantidad tal como llegó de Wasabil. Nunca se edita.';
comment on column documentos_recibidos_lineas.precio_unit_original  is 'Snapshot de precio_unit tal como llegó de Wasabil. Nunca se edita.';

-- Backfill de las filas que ya existen (piloto de agosto + relleno de
-- septiembre): a esa fecha nadie había corregido nada todavía, así que el
-- valor actual ES el original. Guardia para que correr esto dos veces no
-- pise un original ya capturado.
update documentos_recibidos_lineas
set item_nombre_original = item_nombre,
    glosa_original        = glosa,
    cantidad_original     = cantidad,
    precio_unit_original  = precio_unit
where item_nombre_original is null
  and glosa_original is null
  and cantidad_original is null
  and precio_unit_original is null;

-- De acá en adelante, cualquier fila nueva importada desde Wasabil se
-- congela sola al insertarse: la app no tiene que acordarse de duplicarlo.
create or replace function _snapshot_linea_original()
returns trigger
language plpgsql
as $$
begin
  new.item_nombre_original := new.item_nombre;
  new.glosa_original        := new.glosa;
  new.cantidad_original     := new.cantidad;
  new.precio_unit_original  := new.precio_unit;
  return new;
end;
$$;

drop trigger if exists trg_linea_snapshot_original on documentos_recibidos_lineas;
create trigger trg_linea_snapshot_original
  before insert on documentos_recibidos_lineas
  for each row execute function _snapshot_linea_original();


-- ── 3. Sello de quién y cuándo reclasificó ─────────────────────────────────
-- Aparte de clasificado_por/clasificado_en (0010), que solo se dispara
-- cuando cambia `tipo`. Este cubre los cuatro campos que toca la
-- reclasificación: glosa, cantidad, unidad y precio.
alter table documentos_recibidos_lineas
  add column if not exists editado_por text,
  add column if not exists editado_en  timestamptz;

create or replace function _stamp_linea_editada()
returns trigger
language plpgsql
as $$
begin
  if (new.glosa       is distinct from old.glosa)
  or (new.cantidad    is distinct from old.cantidad)
  or (new.unidad_id   is distinct from old.unidad_id)
  or (new.precio_unit is distinct from old.precio_unit) then
    new.editado_en := now();
    new.editado_por := coalesce(auth.jwt() ->> 'email', new.editado_por);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_linea_editada on documentos_recibidos_lineas;
create trigger trg_linea_editada
  before update on documentos_recibidos_lineas
  for each row execute function _stamp_linea_editada();


-- ── 4. Cantidad con unidad ──────────────────────────────────────────────────
-- Mismo criterio que mayor.cantidad_con_unidad (0001). NOT VALID porque las
-- filas del piloto de agosto ya tienen cantidad sin unidad y no hay forma de
-- adivinarla sin arriesgar el dato: queda exigida para todo lo nuevo desde
-- ahora; se valida más adelante cuando la cola esté limpia con
--   alter table documentos_recibidos_lineas validate constraint cantidad_con_unidad;
alter table documentos_recibidos_lineas
  drop constraint if exists cantidad_con_unidad;
alter table documentos_recibidos_lineas
  add constraint cantidad_con_unidad
  check (cantidad is null or unidad_id is not null)
  not valid;


-- ── 5. Vista de la cola pendiente ───────────────────────────────────────────
-- Se agrega unidad, el sello de edición y el snapshot original, al final de
-- las columnas que ya existían: `create or replace view` no permite insertar
-- columnas en medio del orden existente, solo agregar al final.
create or replace view v_documentos_recibidos_pendientes with (security_invoker = true) as
select
  l.id as linea_id, l.documento_id, l.linea_n, l.item_nombre, l.glosa, l.tiene_glosa,
  l.cantidad, l.precio_unit, l.subtotal, l.iva, l.total, l.codigo, l.es_exento,
  d.wasabil_document, d.folio, d.fecha, d.proveedor_rut, d.proveedor_nombre,
  d.sii_document_type_id, d.sii_tipo_nombre,
  l.unidad_id, u.clave as unidad,
  l.item_nombre_original, l.glosa_original, l.cantidad_original, l.precio_unit_original,
  l.editado_por, l.editado_en
from documentos_recibidos_lineas l
left join unidades u on u.id = l.unidad_id
join documentos_recibidos d on d.id = l.documento_id
where l.tipo is null
order by d.fecha, d.wasabil_document, l.linea_n;


-- ── 6. Índice ────────────────────────────────────────────────────────────────
create index if not exists idx_doclineas_editada
  on documentos_recibidos_lineas (editado_en) where editado_en is not null;
