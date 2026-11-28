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

-- ═══════════════════════════════════════════════════════════════════════
-- Casa Zaru · Borrar el género guardado en Pixel (Ley 21.719, minimización)
-- 28-11-2026. Parche de datos, no de esquema: no va en migrations/.
-- PENDIENTE DE APLICAR.
--
-- Desde agosto la Gestión no adivina ni guarda el género, y el Excel de
-- Pixel para Meta va sin esa columna (decisión del 21-10-2026). Quedaron
-- 35 filas viejas (22-05 al 05-06-2026) con data->>'gen' = 'M'/'F'.
-- La papelera (gestion_borrados) no tiene ninguna fila de Pixel con género.
--
-- Solo saca la clave «gen» del data (data - 'gen'): no toca nada más.
-- gestion_pixel no tiene trigger de historial en UPDATE (solo la papelera
-- en DELETE), así que el valor no queda copiado en otra tabla.
-- Idempotente: el WHERE exige que la clave exista.
--
-- SIN ROLLBACK, a propósito: el objetivo es que el dato deje de existir, y
-- escribir los valores viejos aquí los publicaría en un repo público. El
-- respaldo previo es el diario en Drive; vence solo (30 días el diario,
-- 12 meses el mensual), como dice el procedimiento de derechos.
-- ═══════════════════════════════════════════════════════════════════════

-- 1) Ver antes. Al 28-11: 114 filas tienen la clave, 35 con valor y 79
--    vacía. Se saca de las 114 (la vacía tampoco sirve). index.html ya no
--    lee ni escribe «gen».
select count(*) as con_clave,
       count(*) filter (where coalesce(data->>'gen','') <> '') as con_valor
from gestion_pixel
where data ? 'gen';

-- 2) Borrar la clave
update gestion_pixel
set data = data - 'gen'
where data ? 'gen';

-- 3) Verificar (debe decir 0; el UPDATE de arriba debe decir 114 filas)
select count(*) as filas_con_genero
from gestion_pixel
where data ? 'gen';
