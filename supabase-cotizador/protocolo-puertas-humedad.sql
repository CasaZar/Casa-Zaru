-- ── CANDADO DE PROYECTO (no borrar) ──────────────────────────────────────
-- Este archivo es del COTIZADOR (cmxqorsyxoltrakxawro). Si se pega en el SQL
-- Editor de otro proyecto, este bloque falla primero y Postgres descarta el
-- resto del script: no se aplica nada.
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

-- ══════════════════════════════════════════════════════════════════════════
-- Protocolo de puertas: humedad, armado, terminación y venta · Cotizador (16-11-2026)
--
-- Pedido del usuario el 16-11 tras dos post ventas (pedidos 1510 y 1515): dos
-- Panguipulli de castaño que se abrieron en las uniones en Santiago. Una se
-- abrió DENTRO de la casa del cliente, antes de instalarse: la causa principal
-- es la humedad de la madera, el sol la agrava.
--
-- Solo AGREGA cuatro entradas a la lista del Manual (cotizador_valores,
-- clave 'protocolos'). No toca las que ya están. Idempotente: cada entrada se
-- agrega solo si no existe una con el mismo título. Se pueden editar después
-- desde el Manual del panel, sin deploy.
-- ══════════════════════════════════════════════════════════════════════════

with nuevas(e) as (
  select jsonb_build_object('cat','Puertas','titulo','Humedad de la madera antes de fabricar','texto',
    'Medir CADA tabla con xilohigrómetro antes de cortar.' || chr(10) ||
    'Destino Santiago o el norte: 8 a 10 %. Destino sur: hasta 12 %.' || chr(10) ||
    'Si marca más, la tabla no se usa: se deja secando y se vuelve a medir.' || chr(10) ||
    'Foto del medidor en el pedido. Sin medición no se fabrica la puerta.' || chr(10) ||
    '(Rangos de referencia del rubro: ajustarlos cuando tengamos el medidor y datos propios.)')
  union all
  select jsonb_build_object('cat','Puertas','titulo','Armado que deja moverse a la madera','texto',
    'Nunca tablas encoladas de canto y fijas dentro del marco: al secarse se abren las uniones.' || chr(10) ||
    'Tablas machihembradas, o panel suelto en ranura del marco con holgura.' || chr(10) ||
    'Teñir y terminar la lengüeta ANTES de armar: si la tabla se encoge se ve madera terminada, no una raja.' || chr(10) ||
    'Puertas grandes o al sol: ofrecer la versión con alma alistonada contrachapada (más estable, más cara).')
  union all
  select jsonb_build_object('cat','Puertas','titulo','Terminación y despacho','texto',
    'Sellar las 6 caras, incluidos los cantos de arriba y de abajo, con las mismas manos por los dos lados.' || chr(10) ||
    'No despachar antes del secado total que indica el fabricante del producto (Osmo, barniz), contado desde la ÚLTIMA mano. Con frío, más.' || chr(10) ||
    'Una corrección de último minuto reinicia ese plazo.')
  union all
  select jsonb_build_object('cat','Puertas','titulo','Antes de vender una puerta','texto',
    'Preguntar siempre: ¿hacia dónde mira la puerta? ¿tiene alero?' || chr(10) ||
    'Norte o poniente sin alero: decirlo POR ESCRITO antes de cobrar: o se pone alero, o se hace la versión estable.' || chr(10) ||
    'Colores oscuros al sol: desaconsejar (se calientan mucho más y la madera se mueve más).' || chr(10) ||
    'Medidas: las toma Casa Zaru, o el cliente firma un plano con el vano libre (ancho y alto, en tres puntos).')
)
update cotizador_valores cv
set valor = cv.valor || coalesce((
      select jsonb_agg(n.e)
      from nuevas n
      where not exists (
        select 1 from jsonb_array_elements(cv.valor) x
        where x->>'titulo' = n.e->>'titulo')
    ), '[]'::jsonb),
    updated_at = now(),
    updated_by = 'protocolo-puertas-humedad.sql'
where cv.clave = 'protocolos';

-- Verificación: debe listar 8 títulos (4 de antes + 4 nuevos).
select x->>'cat' as cat, x->>'titulo' as titulo
from cotizador_valores, jsonb_array_elements(valor) x
where clave = 'protocolos';

-- ── ROLLBACK ─────────────────────────────────────────────────────────────
-- Valor exacto de 'protocolos' antes de este script (leído el 16-11-2026):
-- update cotizador_valores set valor = '[
--   {"cat": "Puertas", "texto": "Desde 90 cm de ancho de puerta: batientes, pieinazo y cabezales de 18 cm.\nBajo 90 cm de ancho: de 15 cm.", "titulo": "Ancho de batientes, pieinazo y cabezales"},
--   {"cat": "Revestimiento", "texto": "Espesor del revestimiento: 1,2 cm.\nDe un palo de 2\" salen 3 tablones: se raja en 3 a lo largo.", "titulo": "Espesor y rendimiento del palo"},
--   {"cat": "General", "texto": "Son 300 pesos en madera por paosavaso\nSon 100 pesos de osmo en dos manos", "titulo": "Posavasos"},
--   {"cat": "General", "texto": "valor caja blanca cera es 250  pesos la unidad.\nSe envian ceras, posavasos en estas cajas", "titulo": "Caja Cera"}
-- ]'::jsonb, updated_at = now(), updated_by = 'rollback protocolo-puertas-humedad'
-- where clave = 'protocolos';
