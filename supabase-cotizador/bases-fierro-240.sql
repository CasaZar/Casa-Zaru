-- ── CANDADO DE PROYECTO (no borrar) ──────────────────────────────────────
-- Este archivo es del COTIZADOR (cmxqorsyxoltrakxawro). Si se pega en el SQL
-- Editor de otro proyecto, este bloque falla primero y Postgres descarta el
-- resto del script: no se aplica nada. Hace falta porque el proyecto de
-- Gestión TIENE tablas "cotizaciones" y "quote_links" (restos vacíos de junio)
-- y un alter sobre ellas pasaría ahí sin ningún error.
do $candado$
begin
  if to_regclass('public.gestion_pedidos') is not null then
    raise exception 'PROYECTO EQUIVOCADO: este SQL es del COTIZADOR (cmxqorsyxoltrakxawro) y lo estás corriendo en GESTIÓN. No se aplicó nada.';
  end if;
  if to_regclass('public.cotizaciones') is null then
    raise exception 'PROYECTO EQUIVOCADO: este SQL es del COTIZADOR (cmxqorsyxoltrakxawro) y aquí no existe la tabla cotizaciones. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════
-- BASES DE FIERRO SUELTAS: corte en 240 cm (08-10-2026)
--
-- Campaña «Agrega base a tu cubierta». Precio al cliente, con IVA:
--   cubierta hasta 240 cm  → $289.900
--   cubierta sobre 240 cm  → $319.900
--
-- Lo guardado en el Manual pisa al código, y ahí estaban los 5 tramos con
-- "cliente" en 0 (el Manual sugería costo + IVA = margen cero). El Manual no
-- deja agregar tramos, por eso va por SQL: queda igual que los defaults de
-- cotizador-clientes.html. Idempotente: se puede correr de nuevo.
-- ══════════════════════════════════════════════════════════════════

update cotizador_valores
set valor = '[
  {"nombre":"Base rectangular hasta 240 cm","forma":"rectangular","largoMax":240,"costo":175000,"cliente":289900},
  {"nombre":"Base rectangular 241–280 cm","forma":"rectangular","largoMax":280,"costo":175000,"cliente":319900},
  {"nombre":"Base rectangular 281–320 cm","forma":"rectangular","largoMax":320,"costo":210000,"cliente":319900},
  {"nombre":"Base rectangular 321–360 cm","forma":"rectangular","largoMax":360,"costo":245000,"cliente":319900},
  {"nombre":"Base redonda (cruz / trípode)","forma":"redonda","largoMax":150,"costo":150000,"cliente":249900},
  {"nombre":"Par de bancas (fierro)","forma":"bancas","largoMax":280,"costo":140000,"cliente":0}
]'::jsonb,
    updated_at = now(),
    updated_by = 'sql: bases-fierro-240'
where clave = 'basesFierro';

-- Verificación: tiene que mostrar 6 tramos, el primero con largoMax 240.
select jsonb_array_length(valor) as tramos, valor->0->>'largoMax' as primer_tope,
       valor->0->>'cliente' as hasta_240, valor->1->>'cliente' as sobre_240
from cotizador_valores where clave = 'basesFierro';
