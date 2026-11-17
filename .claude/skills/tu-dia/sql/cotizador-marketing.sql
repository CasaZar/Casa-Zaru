-- Cerebro Zaru · Pulso de MARKETING para el «Mi día» del equipo (COTIZADOR cmxqorsyxoltrakxawro). Solo lectura.
-- Correr con mcp__supabase-cotizador__execute_sql y guardar el resultado TAL CUAL en <scratchpad>\marketing-<hoy>.json.
-- Cotizaciones por origen: ayer (día anterior en hora de Santiago) y últimos 7 días.
-- Reglas (mismas marcas que deja el cotizador en «origen»):
--   vendedor   = la hizo un vendedor desde su panel (canal no nulo)
--   google     = gclid / gbraid / wbraid o utm_source google
--   meta       = fbclid o utm_source fb / ig / facebook / instagram / meta
--   web        = llegó por el sitio sin clic de anuncio (ref o sesión, sin los anteriores)
--   sin_origen = sin dato de origen
with hoy as (select (now() at time zone 'America/Santiago')::date d),
c as (select fecha_creacion, origen, canal from cotizaciones
      where coalesce(eliminada,false)=false and fecha_creacion >= now() - interval '9 days'),
k as (select (fecha_creacion at time zone 'America/Santiago')::date f,
  case when canal is not null then 'vendedor'
       when origen ? 'gclid' or origen ? 'gbraid' or origen ? 'wbraid' or lower(origen->>'utm_source') in ('google','gads') then 'google'
       when origen ? 'fbclid' or lower(origen->>'utm_source') in ('fb','ig','facebook','instagram','meta') then 'meta'
       when origen ? 'ref' or origen ? 'ses' then 'web'
       else 'sin_origen' end o
  from c)
select o,
  count(*) filter (where f = hoy.d - 1) ayer,
  count(*) filter (where f between hoy.d - 7 and hoy.d - 1) semana
from k, hoy group by o order by o;
