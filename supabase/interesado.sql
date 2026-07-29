-- ══════════════════════════════════════════════════════════════
-- Casa Zaru · Marca "Interesado" en el panel de Seguimiento
-- Agrega la columna que guarda la estrella (★) que el vendedor/
-- admin puede prender o apagar en cada tarjeta de cliente, para
-- ubicar rápido a los que están más calientes dentro de la cola.
-- Pegar en Supabase → SQL Editor → Run.
-- ══════════════════════════════════════════════════════════════

alter table cotizaciones add column if not exists interesado boolean default false;
