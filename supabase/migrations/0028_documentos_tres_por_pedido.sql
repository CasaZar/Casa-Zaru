-- ── CANDADO DE PROYECTO (no borrar) ──────────────────────────────────────
-- Este archivo es de GESTIÓN (padnttpgzuotxeipjrry). Si se pega en el SQL
-- Editor de otro proyecto, este bloque falla primero y Postgres descarta el
-- resto del script: no se aplica nada.
do $candado$
begin
  if to_regclass('public.gestion_pedidos') is null then
    raise exception 'PROYECTO EQUIVOCADO: este SQL es de GESTIÓN (padnttpgzuotxeipjrry) y aquí no existe gestion_pedidos. No se aplicó nada.';
  end if;
  if to_regclass('public.gestion_documentos') is null then
    raise exception 'Falta la migración 0012 (gestion_documentos). Correrla primero.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- 0028 · Hasta tres documentos por pedido, uno por abono (09-11-2026)
--
-- Antes: doc 1 = abono 1 y doc 2 = abono 2 + abono 3. Cuando un cliente
-- pagaba en tres transferencias (un abono para reservar, el resto del 70 % y
-- el saldo), una de ellas quedaba esperando boleta. Ahora cada abono tiene
-- su documento: doc N = abono N.
--
-- Solo cambia el check de doc_num. El candado (índice único num + doc_num
-- donde no está anulada) no cambia y cubre el doc 3 igual que los otros.
-- Idempotente: si ya admite el 3, no hace nada.
-- ══════════════════════════════════════════════════════════════════════════

alter table public.gestion_documentos drop constraint if exists gestion_documentos_doc_num_check;
alter table public.gestion_documentos add constraint gestion_documentos_doc_num_check
  check (doc_num in (1, 2, 3));
comment on column public.gestion_documentos.doc_num is
  '1, 2 o 3: el documento de cada abono (doc N = abono N). Igual que docN_* en gestion_finanzas.';


-- Rollback (solo si ningún pedido tiene doc 3):
--   alter table public.gestion_documentos drop constraint gestion_documentos_doc_num_check;
--   alter table public.gestion_documentos add constraint gestion_documentos_doc_num_check check (doc_num in (1, 2));

-- Registrar en el panel (Database → Migrations), pegándolo junto con este archivo:
-- insert into supabase_migrations.schema_migrations (version, name, statements)
-- values ('0028', 'documentos_tres_por_pedido', array[$m0028$ <este archivo> $m0028$]);
