-- Cerebro Zaru · «Para contenido» del «Mi día» de marketing: lo que sale del taller esta semana.
-- Proyecto GESTIÓN (padnttpgzuotxeipjrry), solo lectura: correr con mcp__supabase-gestion__execute_sql.
-- Solo producto, medidas, madera y comuna: NUNCA nombres, teléfonos ni montos (va a la pantalla de otra persona).
-- Semana de envío = la del lunes de hoy («SEMANA 16 NOVIEMBRE», reference_semanas_produccion). Solo ventas.
-- Guardar el resultado TAL CUAL en <scratchpad>\contenido-<hoy>.json y pasarlo a armar-equipo.ps1 -Contenido.
with hoy as (select (now() at time zone 'America/Santiago')::date d),
lunes as (select (d - (extract(isodow from d)::int - 1))::date l from hoy),
sem as (
  select 'SEMANA ' || extract(day from l)::int || ' ' ||
    (array['ENERO','FEBRERO','MARZO','ABRIL','MAYO','JUNIO','JULIO','AGOSTO','SEPTIEMBRE','OCTUBRE','NOVIEMBRE','DICIEMBRE'])[extract(month from l)::int] s
  from lunes
)
select p.num,
  l->>'producto' as producto, l->>'madera' as madera,
  l->>'largo' as largo, l->>'ancho' as ancho, l->>'cantidad' as cantidad,
  p.data->'_cliente'->>'ct' as comuna
from gestion_produccion p
cross join sem
cross join lateral jsonb_array_elements(case when jsonb_typeof(p.data->'lineas') = 'array' then p.data->'lineas' else '[]'::jsonb end) l
where upper(trim(p.data->>'envio')) = sem.s
  and upper(coalesce(p.data->>'tipo', 'VENTA')) = 'VENTA'
order by p.num;
