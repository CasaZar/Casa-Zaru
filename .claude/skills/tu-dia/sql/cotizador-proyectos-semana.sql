-- Cerebro Zaru · Proyectos de la SEMANA desde el COTIZADOR (cmxqorsyxoltrakxawro). Solo lectura.
-- Correr con mcp__supabase-cotizador__execute_sql. Nunca en el proyecto de la Gestión.
-- Es el número 4 de los lunes del plan comercial: proyectos de $1,5 M o más contactados, con
-- propuesta enviada y ganados en la semana. Misma regla que el panel (medidorSemana, 17-11-2026):
--   · proyecto = cliente (teléfono, correo o nombre) con alguna cotización de $1,5 M o más;
--   · contactados = entradas de seg_historial con via 'llamada' (de la cadencia o de «Lo contacté»)
--     + las de «Lo contacté» con via 'contacto' (WhatsApp, correo, visita);
--   · propuestas = notas «Propuesta formal enviada»; ganados = estado ganado con fecha_concretada
--     en la semana y monto de $1,5 M o más.
-- La semana va de lunes a domingo (hora de Chile) y se nombra por el lunes. Cambiar el desfase
-- (0 = esta semana, -7 = la anterior) en la CTE «sem».
-- No trae nombres ni teléfonos: solo conteos y montos.
with sem as (
  select date_trunc('week', (now() at time zone 'America/Santiago'))::date + 0 as lunes
),
c as (
  select id, estado, coalesce(total_alto, 0) monto, monto_cierre, fecha_concretada, seg_historial,
         coalesce(origen ->> 'medida_rara', '') <> '' rara,
         case
           when length(regexp_replace(coalesce(contacto, ''), '\D', '', 'g')) >= 8 then 't' || right(regexp_replace(contacto, '\D', '', 'g'), 8)
           when position('@' in coalesce(contacto, '')) > 0 then 'e' || lower(trim(contacto))
           when trim(coalesce(cliente, '')) <> '' then 'n' || lower(regexp_replace(trim(cliente), '\s+', ' ', 'g'))
           else 'q' || id::text
         end cli
  from cotizaciones
  where coalesce(eliminada, false) = false and coalesce(motivo_perdida, '') not like 'Prueba%'
),
grandes as (select distinct cli from c where monto >= 1500000 and not rara),
h as (
  select e.value ->> 'via' via, e.value ->> 'nota' nota, e.value ->> 'resp' resp, left(e.value ->> 'fecha', 10) fecha
  from c
  join grandes g on g.cli = c.cli
  cross join lateral jsonb_array_elements(case when jsonb_typeof(c.seg_historial) = 'array' then c.seg_historial else '[]'::jsonb end) e
)
select
  (select lunes from sem)                                                                                 as semana_del_lunes,
  (select count(*) from h, sem where h.fecha >= sem.lunes::text and h.fecha < (sem.lunes + 7)::text
     and (h.via = 'llamada' or (h.nota = 'Contacto de proyecto' and h.via = 'contacto')))               as contactados,
  (select count(*) from h, sem where h.fecha >= sem.lunes::text and h.fecha < (sem.lunes + 7)::text
     and h.nota = 'Contacto de proyecto' and h.resp = 'nada')                                           as no_contestaron,
  (select count(*) from h, sem where h.fecha >= sem.lunes::text and h.fecha < (sem.lunes + 7)::text
     and h.nota = 'Propuesta formal enviada')                                                           as propuestas,
  (select count(*) from c, sem where c.estado = 'ganado' and coalesce(c.monto_cierre, c.monto) >= 1500000
     and (c.fecha_concretada at time zone 'America/Santiago')::date >= sem.lunes
     and (c.fecha_concretada at time zone 'America/Santiago')::date < sem.lunes + 7)                    as ganados,
  (select round(coalesce(sum(coalesce(c.monto_cierre, c.monto)), 0)) from c, sem where c.estado = 'ganado'
     and coalesce(c.monto_cierre, c.monto) >= 1500000
     and (c.fecha_concretada at time zone 'America/Santiago')::date >= sem.lunes
     and (c.fecha_concretada at time zone 'America/Santiago')::date < sem.lunes + 7)                    as ganados_monto;
