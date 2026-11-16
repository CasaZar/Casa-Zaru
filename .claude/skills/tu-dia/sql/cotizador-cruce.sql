-- Cerebro Zaru · Cruce de datos, lado COTIZADOR (cmxqorsyxoltrakxawro). Solo lectura.
-- Correr con mcp__supabase-cotizador__execute_sql. Nunca en el proyecto de la Gestión.
-- Devuelve UNA fila con las cotizaciones ganadas de los últimos 30 días: es la entrada -Cotizador de
-- .claude/cerebro/cruzar-dia.ps1. El resultado se guarda tal cual en el scratchpad (trae nombres y
-- teléfonos: nunca al repo).
select coalesce(jsonb_agg(x order by x.concretada), '[]'::jsonb) as cruce
from (
  select numero, cliente, contacto, producto, canal,
         coalesce(monto_cierre, total_medio, total_alto, total_bajo) as monto,
         (fecha_concretada at time zone 'America/Santiago')::date as concretada,
         (fecha_creacion  at time zone 'America/Santiago')::date as creada,
         link
  from cotizaciones
  where not coalesce(eliminada, false)
    and estado = 'ganado'
    and fecha_concretada >= now() - interval '30 days'
) x;
