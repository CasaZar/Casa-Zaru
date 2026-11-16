-- Cerebro Zaru · Cruce de datos, lado GESTIÓN (padnttpgzuotxeipjrry). Solo lectura.
-- Correr con mcp__supabase-gestion__execute_sql. Nunca en el proyecto del Cotizador.
-- Devuelve UNA fila con las ventas de los últimos 60 días (sin muestrarios ni devoluciones): es la
-- entrada -Gestion de .claude/cerebro/cruzar-dia.ps1. El resultado se guarda tal cual en el scratchpad
-- (trae nombres y teléfonos: nunca al repo).
with f as (
  select num,
         data->>'nombre'   as nombre,
         data->>'apellido' as apellido,
         data->>'celular'  as celular,
         coalesce(nullif(data->>'tipo', ''), 'VENTA') as tipo,
         data->>'canal_pago' as canal_pago,
         coalesce(nullif(data->>'total', '')::numeric, 0)    as total,
         coalesce(nullif(data->>'val_prod', '')::numeric, 0) as val_prod,
         case when data->>'fecha' ~ '^\d{1,2}/\d{1,2}/\d{4}$' then to_date(data->>'fecha', 'DD/MM/YYYY') end as fecha
  from gestion_finanzas
)
select coalesce(jsonb_agg(f order by f.num), '[]'::jsonb) as cruce
from f
where tipo = 'VENTA' and fecha >= (now() at time zone 'America/Santiago')::date - 60;
