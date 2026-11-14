-- Cerebro Zaru · Proyectos desde el COTIZADOR (cmxqorsyxoltrakxawro). Solo lectura.
-- Correr con mcp__supabase-cotizador__execute_sql. Nunca en el proyecto de la Gestión.
-- «Proyecto» = cliente con $1,5 M o más en cotizaciones abiertas, con la misma regla que la
-- pestaña Proyectos del panel (renderProyectos): se agrupa por teléfono (o correo, o nombre),
-- manda la cotización más reciente, el monto es el mayor entre las abiertas y «vivo» es el que
-- tiene hasta 30 días (el panel redondea los días: por eso 30 días y 12 horas). Verificado el
-- 14-11-2026 contra el panel: 22 vivos y 54 antiguos en los dos lados.
-- No trae nombres ni teléfonos: solo conteos y montos.
with c as (
  select id, estado, fecha_creacion, coalesce(total_alto, 0) monto, coalesce(interesado, false) interesado,
         (coalesce(seg_etapa, 0) > 0 or fecha_primer_contacto is not null or coalesce(respondio, false)) contactada,
         coalesce(respondio, false) respondio,
         coalesce(origen ->> 'medida_rara', '') <> '' rara,
         case
           when length(regexp_replace(coalesce(contacto, ''), '\D', '', 'g')) >= 8 then 't' || right(regexp_replace(contacto, '\D', '', 'g'), 8)
           when position('@' in coalesce(contacto, '')) > 0 then 'e' || lower(trim(contacto))
           when trim(coalesce(cliente, '')) <> '' then 'n' || lower(regexp_replace(trim(cliente), '\s+', ' ', 'g'))
           else 'q' || id::text
         end cli
  from cotizaciones
  where coalesce(eliminada, false) = false
),
ult as (select distinct on (cli) cli, estado ultimo_estado, fecha_creacion ultima_fecha from c order by cli, fecha_creacion desc),
toque as (select cotizacion_id, max(ts) ts from toques group by 1),
p as (
  select c.cli,
         max(c.monto) filter (where c.estado = 'enviada' and not c.rara) valor,
         case when max(u.ultimo_estado) = 'enviada' then max(u.ultima_fecha)
              else max(c.fecha_creacion) filter (where c.estado = 'enviada' and c.interesado) end fecha_lead,
         min(c.fecha_creacion) filter (where c.estado = 'enviada' and c.monto >= 1500000 and not c.rara) primera_grande,
         bool_or(c.contactada) contactada,
         bool_or(c.respondio) respondio,
         greatest(max(t.ts), max(c.fecha_creacion)) ultimo_movimiento
  from c
  join ult u on u.cli = c.cli
  left join toque t on t.cotizacion_id = c.id
  where u.ultimo_estado = 'enviada' or exists (select 1 from c c2 where c2.cli = c.cli and c2.estado = 'enviada' and c2.interesado)
  group by c.cli
),
proy as (select * from p where valor >= 1500000)
select
  count(*) filter (where fecha_lead >= now() - interval '30 days 12 hours')                            as vivos_30_dias,
  round(coalesce(sum(valor) filter (where fecha_lead >= now() - interval '30 days 12 hours'), 0))      as vivos_30_dias_monto,
  count(*) filter (where fecha_lead < now() - interval '30 days 12 hours')                             as antiguos,
  count(*) filter (where primera_grande >= now() - interval '24 hours')                                as nuevos_24_h,
  round(coalesce(sum(valor) filter (where primera_grande >= now() - interval '24 hours'), 0))          as nuevos_24_h_monto,
  count(*) filter (where not contactada)                                                               as sin_primer_contacto,
  count(*) filter (where respondio and fecha_lead >= now() - interval '30 days 12 hours'
                   and ultimo_movimiento < now() - interval '72 hours')                                as en_conversacion_sin_toque_72_h
from proy;
