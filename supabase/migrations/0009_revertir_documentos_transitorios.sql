-- ══════════════════════════════════════════════════════════════════════════
-- MIGRACIÓN 0009 · REVERTIR documentos_transitorios (malentendido)
--
-- PROYECTO SUPABASE: padnttpgzuotxeipjrry
--
-- ── QUÉ RESUELVE ──────────────────────────────────────────────────────────
-- La 0007 armó documentos_transitorios + el bucket documentos-sii asumiendo
-- que los documentos de Wasabil eran facturas/boletas RECIBIDAS por Casa
-- Zaru (gasto). Son al revés: Wasabil EMITE documentos de Casa Zaru hacia el
-- cliente (receiver_rut/receiver_name en el body, invoice_reference contra
-- el propio pedido) — es venta/ingreso, no gasto. El módulo que el negocio
-- necesita es uno de facturas de PROVEEDOR recibidas, que es un concepto
-- distinto (y probablemente ya cubierto por la tabla `facturas` de 0001, o
-- por un futuro feed de Wasabil que todavía no existe).
--
-- Esta migración da de baja la tabla y su vista. El bucket documentos-sii
-- (vacío — nunca llegó a escribirse un PDF real) NO se borra acá: Supabase
-- bloquea el DELETE directo sobre storage.buckets por SQL ("Direct deletion
-- from storage tables is not allowed. Use the Storage API instead."). Queda
-- vacío y sin política de escritura (se saca la policy más abajo); borrarlo
-- del todo es un paso manual de 10 segundos en el dashboard → Storage →
-- documentos-sii → Delete bucket.
--
-- Lo que NO se toca: las foreign keys de la 0008 hacia gestion_usuarios en
-- gestion_borrados.borrado_por y pedido_centro_costo.asignado_por — esas no
-- tienen nada que ver con este malentendido, siguen siendo correctas. La
-- tercera FK de la 0008 (documentos_transitorios.corregido_por) desaparece
-- sola al borrar la tabla.
--
-- 0007 y 0008 se dejan como archivos (registro histórico de lo que se
-- corrió), igual que se hizo con la 0004 — no se reescribe el pasado, se
-- revierte hacia adelante.
--
-- Pegar completo en Supabase → proyecto Gestión → SQL Editor → Run.
-- Idempotente.
-- ══════════════════════════════════════════════════════════════════════════

drop view if exists v_documentos_sin_glosa;
drop table if exists documentos_transitorios;

-- Sin política de por medio, nadie (salvo service_role) puede escribir en el
-- bucket aunque siga existiendo hasta que se borre a mano.
drop policy if exists "admin gestiona documentos-sii" on storage.objects;
