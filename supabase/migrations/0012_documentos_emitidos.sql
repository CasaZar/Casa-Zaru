-- ══════════════════════════════════════════════════════════════════
-- DOCUMENTOS EMITIDOS — una fila por boleta/factura enviada al SII
--
-- Proyecto: padnttpgzuotxeipjrry («ZARU · Gestión»). NO es el Cotizador.
--
-- Resuelve tres cosas con la misma pieza:
--
--   1. El vendedor ve las boletas de sus clientes sin entrar a Finanzas.
--      `gestion_finanzas` es solo_admin y va a seguir siéndolo: acá viven
--      sólo folio, monto y link al PDF, nada de márgenes ni comisiones.
--   2. El registro de emisiones que hoy no existe. `gestion_historial`
--      guarda checks y avisos; ninguna emisión al SII quedaba anotada,
--      y por eso no se pudo reconstruir quién sobrescribió el pedido 1527.
--   3. El candado contra la doble emisión (boletas 7245/7260 y 7246/7261,
--      02-09-2026). El índice único de abajo lo hace imposible desde la
--      base, sin depender de que el navegador tenga cargado finRecords.
--
-- ORDEN DE USO, IMPORTANTE: la fila se inserta ANTES de llamar a Wasabil,
-- no después. Insertar es tomar el candado; si otro intento corre en
-- paralelo o alguien reaprieta el botón, el insert falla y la emisión ni
-- siquiera se intenta. Recién con el folio de vuelta se hace el update.
-- Insertar después dejaría el folio ya quemado en el SII.
-- ══════════════════════════════════════════════════════════════════

create table if not exists public.gestion_documentos (
  id         bigint generated always as identity primary key,
  num        text     not null,                                  -- pedido (numStr)
  doc_num    smallint not null check (doc_num in (1, 2)),         -- 1 = abono, 2 = saldo
  tipo       text     not null check (tipo in ('BOLETA','FACTURA')),
  detalle    text,                                               -- glosa: "Abono", "Saldo final"

  -- Identidad del cliente, copiada al emitir. Se guarda acá a propósito y
  -- no por join: el historial por cliente tiene que sobrevivir a que el
  -- pedido cambie de nombre o de RUT más adelante.
  cliente    text,
  rut        text,
  email      text,

  -- Lo que devuelve Wasabil. Nulos mientras el documento está en cola.
  folio      text,
  uuid       text,
  monto      integer,                                            -- total con IVA, en pesos
  fecha      date,
  pdf_url    text,

  -- Anulación por nota de crédito.
  anulada    boolean not null default false,
  nc_folio   text,
  nc_motivo  text,

  creado     timestamptz not null default now(),
  creado_por text default auth.email()
);

-- ── El candado ────────────────────────────────────────────────────
-- Un pedido no puede tener dos veces el mismo documento vivo. Es parcial
-- a propósito: al anular con nota de crédito la fila queda `anulada` y
-- libera el cupo, que es justamente lo que hay que poder hacer cuando se
-- emitió mal y se reemite.
create unique index if not exists gestion_documentos_pedido_doc_idx
  on public.gestion_documentos (num, doc_num)
  where not anulada;

create index if not exists gestion_documentos_rut_idx   on public.gestion_documentos (rut);
create index if not exists gestion_documentos_email_idx on public.gestion_documentos (lower(email));
create index if not exists gestion_documentos_num_idx   on public.gestion_documentos (num);
create index if not exists gestion_documentos_fecha_idx on public.gestion_documentos (fecha desc);

-- ── Permisos ──────────────────────────────────────────────────────
alter table public.gestion_documentos enable row level security;
alter table public.gestion_documentos force row level security;

-- Lee cualquier usuario del equipo (decisión explícita: César ve todas,
-- no sólo las de sus pedidos).
drop policy if exists documentos_leer on public.gestion_documentos;
create policy documentos_leer on public.gestion_documentos
  for select to authenticated using (es_usuario());

-- Escribe sólo admin: las filas las crea el circuito de emisión.
drop policy if exists documentos_crear on public.gestion_documentos;
create policy documentos_crear on public.gestion_documentos
  for insert to authenticated with check (es_admin());

drop policy if exists documentos_editar on public.gestion_documentos;
create policy documentos_editar on public.gestion_documentos
  for update to authenticated using (es_admin()) with check (es_admin());

drop policy if exists documentos_borrar on public.gestion_documentos;
create policy documentos_borrar on public.gestion_documentos
  for delete to authenticated using (es_admin());

grant select on public.gestion_documentos to authenticated;
grant insert, update, delete on public.gestion_documentos to authenticated;
