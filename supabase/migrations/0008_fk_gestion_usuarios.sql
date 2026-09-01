-- ══════════════════════════════════════════════════════════════════════════
-- MIGRACIÓN 0008 · FOREIGN KEYS HACIA gestion_usuarios
--
-- PROYECTO SUPABASE: padnttpgzuotxeipjrry (el mismo de index.html y de 0001)
--
-- ── QUÉ RESUELVE ──────────────────────────────────────────────────────────
-- gestion_usuarios.email es primary key pero nada en la base la referencia
-- con una FK real — por eso aparece aislada en el diagrama del dashboard.
-- Tres columnas guardan "quién hizo esto" como texto libre sin que la base
-- lo valide: borrado_por, asignado_por, corregido_por. Esta migración las
-- convierte en foreign keys de verdad.
--
-- OJO — lo que a propósito NO se toca: gestion_ventas.email y
-- gestion_clientes.email se llaman igual pero son el correo del CLIENTE, no
-- de alguien del equipo. Enlazarlas a gestion_usuarios sería un error de
-- modelo, no una corrección.
--
-- ON DELETE SET NULL a propósito: si algún día se borra un usuario, el
-- registro histórico de "quién lo hizo" no debe desaparecer ni bloquear el
-- borrado (mismo criterio que mayor.pedido_num en 0001).
--
-- Verificado antes de escribir esto: gestion_borrados.borrado_por tiene 5
-- filas, todas 'hola@casazaru.cl' (coincide); pedido_centro_costo y
-- documentos_transitorios están vacías. Ningún dato existente viola la FK.
--
-- Pegar completo en Supabase → proyecto Gestión → SQL Editor → Run, o vía
-- CLI (db query --linked --file). Idempotente.
-- ══════════════════════════════════════════════════════════════════════════

alter table gestion_borrados
  drop constraint if exists fk_gestion_borrados_borrado_por,
  add constraint fk_gestion_borrados_borrado_por
    foreign key (borrado_por) references gestion_usuarios(email) on delete set null;

alter table pedido_centro_costo
  drop constraint if exists fk_pedido_centro_costo_asignado_por,
  add constraint fk_pedido_centro_costo_asignado_por
    foreign key (asignado_por) references gestion_usuarios(email) on delete set null;

alter table documentos_transitorios
  drop constraint if exists fk_documentos_transitorios_corregido_por,
  add constraint fk_documentos_transitorios_corregido_por
    foreign key (corregido_por) references gestion_usuarios(email) on delete set null;
