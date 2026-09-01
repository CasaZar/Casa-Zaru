-- ══════════════════════════════════════════════════════════════════════════
-- MIGRACIÓN 0007 · DOCUMENTOS TRANSITORIOS (Wasabil → Storage + glosa)
--
-- PROYECTO SUPABASE: padnttpgzuotxeipjrry (el mismo de index.html y de 0001)
--
-- ── QUÉ RESUELVE ──────────────────────────────────────────────────────────
-- Hoy la Edge Function smart-action-a-wasabil-emitir emite la boleta/factura
-- en Wasabil, descarga el PDF y lo sube a Drive vía Apps Script (ver
-- supabase/functions/smart-action-a-wasabil-emitir.FIX.md). Esta migración
-- agrega el destino Supabase-nativo de esa misma emisión:
--
--   Emitir en Wasabil ──> sube el PDF a Storage (bucket documentos-sii)
--                     └─> inserta una fila acá con la glosa (r.detalle)
--
-- Es TRANSITORIA a propósito: no reemplaza doc1_pdf_url/doc2_pdf_url dentro
-- de gestion_finanzas (eso sigue siendo la fuente de verdad de "¿está
-- emitido?"). Esta tabla es el panel de trabajo para un problema puntual:
-- muchas boletas/facturas salen con el campo "detalle" vacío (el prompt de
-- prepararDocumento/emitirFinDoc en index.html permite guardar con glosa en
-- blanco) y hay que ubicarlas y corregirlas. glosa_estado se recalcula solo
-- — no hay que mantenerlo a mano — y la corrección de la glosa se hace ACÁ
-- mismo (columna editable), no en Wasabil.
--
-- Alcance: solo hacia adelante. No trae el historial ya emitido.
--
-- Depende de zaru_rol(), creada en 0001 (ya aplicada). Pegar completo en
-- Supabase → proyecto Gestión → SQL Editor → Run. Idempotente.
-- ══════════════════════════════════════════════════════════════════════════


-- ── 1. Bucket de Storage ───────────────────────────────────────────────────
-- Privado: el document_pdf_url de Wasabil ya es público sin auth (por diseño
-- de Wasabil), pero la copia que vive en Supabase no tiene por qué serlo —
-- son documentos con RUT y dirección del cliente. Se sirve con URL firmada.
insert into storage.buckets (id, name, public)
values ('documentos-sii', 'documentos-sii', false)
on conflict (id) do nothing;


-- ── 2. documentos_transitorios ─────────────────────────────────────────────
create table if not exists documentos_transitorios (
  id             bigint      generated always as identity primary key,
  num_pedido     text        not null,
  doc_num        smallint    not null check (doc_num in (1,2)),
  tipo           text        not null check (tipo in ('BOLETA','FACTURA')),
  cliente        text,
  folio          text,
  uuid           text,
  monto          integer     not null default 0,
  -- La glosa es el mismo texto que hoy viaja como `detalle` en el payload a
  -- Wasabil ("Abono", "Saldo final"...). Acá queda editable para corregirla
  -- sin tener que volver a emitir nada.
  glosa          text,
  storage_path   text,       -- ruta del PDF en el bucket documentos-sii
  pdf_url        text,       -- document_pdf_url original de Wasabil, de respaldo
  corregido_por  text,
  corregido_en   timestamptz,
  creado_en      timestamptz not null default now(),
  -- Reemisión del mismo doc (abono/saldo) del mismo pedido = mismo lugar, no
  -- fila nueva. La Edge Function hace upsert con esta llave.
  unique (num_pedido, doc_num)
);
comment on column documentos_transitorios.doc_num is '1 = Doc 1 / Abono, 2 = Doc 2 / Saldo — igual que doc1_*/doc2_* en gestion_finanzas.';
comment on column documentos_transitorios.monto    is 'Pesos, entero — igual que el resto de montos del sistema.';
comment on column documentos_transitorios.glosa    is 'Fuente de verdad de la glosa PARA ESTA TABLA. No se sincroniza de vuelta a Wasabil.';

-- glosa_estado no es columna guardada a mano: se recalcula sola, así nunca
-- queda desincronizada de lo que hay en `glosa`.
alter table documentos_transitorios
  drop column if exists glosa_estado;
alter table documentos_transitorios
  add column glosa_estado text
  generated always as (
    case when glosa is not null and btrim(glosa) <> '' then 'con_glosa' else 'sin_glosa' end
  ) stored;


-- ── 3. Sello automático de quién y cuándo corrigió la glosa ────────────────
create or replace function _stamp_glosa_corregida()
returns trigger
language plpgsql
as $$
begin
  if (new.glosa is distinct from old.glosa)
     and new.glosa is not null and btrim(new.glosa) <> '' then
    new.corregido_en := now();
    new.corregido_por := coalesce(auth.jwt() ->> 'email', new.corregido_por);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_glosa_corregida on documentos_transitorios;
create trigger trg_glosa_corregida
  before update on documentos_transitorios
  for each row execute function _stamp_glosa_corregida();


-- ── 4. Vista de la cola pendiente ───────────────────────────────────────────
-- Lo que muestra el panel de "por corregir": solo lo que falta.
create or replace view v_documentos_sin_glosa with (security_invoker = true) as
select id, num_pedido, doc_num, tipo, cliente, folio, monto, storage_path, pdf_url, creado_en
from documentos_transitorios
where glosa_estado = 'sin_glosa'
order by creado_en;


-- ══════════════════════════════════════════════════════════════════════════
-- SEGURIDAD (RLS) — mismo criterio que facturas/mayor en 0001: solo admin.
-- Son documentos tributarios con datos del cliente; vendedor/taller no
-- tienen Finanzas habilitada en el resto del sistema tampoco.
-- ══════════════════════════════════════════════════════════════════════════
alter table documentos_transitorios enable row level security;
alter table documentos_transitorios force  row level security;

drop policy if exists "solo admin documentos_transitorios" on documentos_transitorios;
create policy "solo admin documentos_transitorios" on documentos_transitorios
  for all to authenticated
  using (zaru_rol() = 'admin')
  with check (zaru_rol() = 'admin');

-- Storage: mismo criterio para los PDFs del bucket.
drop policy if exists "admin gestiona documentos-sii" on storage.objects;
create policy "admin gestiona documentos-sii" on storage.objects
  for all to authenticated
  using (bucket_id = 'documentos-sii' and zaru_rol() = 'admin')
  with check (bucket_id = 'documentos-sii' and zaru_rol() = 'admin');


-- ══════════════════════════════════════════════════════════════════════════
-- ÍNDICES
-- ══════════════════════════════════════════════════════════════════════════
create index if not exists idx_doctrans_estado  on documentos_transitorios (glosa_estado);
create index if not exists idx_doctrans_pedido  on documentos_transitorios (num_pedido);
