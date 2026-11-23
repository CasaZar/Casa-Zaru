-- ── CANDADO DE PROYECTO (no borrar) ──────────────────────────────────────
-- Este archivo es de GESTIÓN (padnttpgzuotxeipjrry). Si se pega en el SQL
-- Editor de otro proyecto, este bloque falla primero y Postgres descarta el
-- resto del script: no se aplica nada.
do $candado$
begin
  if to_regclass('public.gestion_pedidos') is null then
    raise exception 'PROYECTO EQUIVOCADO: este SQL es de GESTIÓN (padnttpgzuotxeipjrry) y aquí no existe gestion_pedidos. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════
-- Casa Zaru · Corregir «¿Cómo nos conoció?» (data->>'como') en Finanzas
-- 23-11-2026. Parche de datos, no de esquema: no va en migrations/.
-- APLICADO el 23-11-2026 (SQL Editor, verificado: 1611 Web, 1615 Instagram).
--
-- «TRANSFERENCIA» es medio de pago, no canal. Solo se corrigen las ventas
-- cuyo canal real está en el Cotizador (origen_eventos, por teléfono):
--   1611  TRANSFERENCIA → Web        CL-1026-265 (19-10) llegó desde www.casazaru.cl
--   1615  TRANSFERENCIA → Instagram  CL-1026-159 (12-10) llegó desde l.instagram.com
-- Las otras 7 (1613, 1614 TRANSFERENCIA; 1605, 1617, 1618, 1619, 1625
-- «Cotizador») las cotizó un vendedor y no dejaron rastro: se corrigen
-- cuando César diga cómo llegó cada una.
--
-- Solo toca la clave «como» (jsonb_set: mezcla, no pisa el data). Respaldo =
-- el valor anterior, escrito en el ROLLBACK de abajo. Idempotente: el WHERE
-- exige el valor viejo, así que correrlo dos veces no hace nada.
-- ══════════════════════════════════════════════════════════════

-- 1) Lo que se va a cambiar (debe devolver 2 filas):
select num, data->>'nombre' nombre, data->>'como' como_actual
from gestion_finanzas
where (num='1611' and data->>'como'='TRANSFERENCIA')
   or (num='1615' and data->>'como'='TRANSFERENCIA');

-- 2) Corrección:
update gestion_finanzas set data = jsonb_set(data,'{como}','"Web"')
 where num='1611' and data->>'como'='TRANSFERENCIA';
update gestion_finanzas set data = jsonb_set(data,'{como}','"Instagram"')
 where num='1615' and data->>'como'='TRANSFERENCIA';

-- 3) Verificación (debe mostrar Web e Instagram):
select num, data->>'como' como from gestion_finanzas where num in ('1611','1615') order by num;

-- ROLLBACK (respaldo de los valores anteriores):
-- update gestion_finanzas set data = jsonb_set(data,'{como}','"TRANSFERENCIA"') where num='1611' and data->>'como'='Web';
-- update gestion_finanzas set data = jsonb_set(data,'{como}','"TRANSFERENCIA"') where num='1615' and data->>'como'='Instagram';
