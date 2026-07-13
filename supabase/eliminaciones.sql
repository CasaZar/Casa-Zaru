-- Casa Zaru: borrado suave de cotizaciones (con motivo y responsable)
-- Pegar en Supabase → SQL Editor → Run

alter table cotizaciones
  add column if not exists eliminada  boolean default false,
  add column if not exists elim_motivo text,
  add column if not exists elim_por    text,
  add column if not exists elim_fecha  timestamptz;

comment on column cotizaciones.eliminada  is 'true = archivada/eliminada (no se muestra en el panel normal)';
comment on column cotizaciones.elim_motivo is 'Motivo que indicó quien la eliminó';
comment on column cotizaciones.elim_por    is 'Nombre del vendedor/admin que la eliminó';
comment on column cotizaciones.elim_fecha  is 'Cuándo se eliminó';
