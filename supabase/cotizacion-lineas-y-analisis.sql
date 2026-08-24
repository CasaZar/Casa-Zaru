-- ══════════════════════════════════════════════════════════════
-- Casa Zaru · Cotizador — guardar el detalle de lo cotizado
-- Proyecto: cmxqorsyxoltrakxawro  («ZARU · Cotizador (público y panel)»)
--
-- CONTEXTO
-- `cotizacion_lineas` existe desde el día uno pero está VACÍA: el código
-- armaba las líneas y se las pasaba a saveQuote() como segundo argumento,
-- pero la función solo recibía uno, así que se descartaban en silencio.
-- Resultado: de cada cotización solo sabemos el producto y los tres
-- totales. No sabemos qué medidas se piden, ni qué modelos, ni cuántos m².
--
-- POR QUÉ UNA FUNCIÓN Y NO UN INSERT DIRECTO
-- El insert de `cotizaciones` no puede usar .select() (con RLS el público
-- inserta pero no lee), así que el navegador NO conoce el id de la fila
-- que acaba de crear y no puede llenar `cotizacion_lineas.cotizacion_id`.
-- Esta función lo resuelve por `numero`, que sí conoce.
--
-- SEGURIDAD
-- Es SECURITY DEFINER pero solo ESCRIBE, nunca devuelve datos. Un tercero
-- con la anon key (que es pública, viaja en el navegador) podría a lo más
-- agregar líneas a una cotización cuyo número adivine — el mismo alcance
-- que ya tiene hoy para insertar cotizaciones. No abre ninguna lectura.
-- ══════════════════════════════════════════════════════════════

create or replace function public.guardar_lineas(p_numero text, p_lineas jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  -- uuid, NO bigint: cotizaciones.id y cotizacion_lineas.cotizacion_id son
  -- uuid (verificado contra la base el 24-08-2026). Con bigint la función
  -- reventaba al crearse.
  v_id uuid;
begin
  if p_numero is null or p_lineas is null then return; end if;
  -- la función es pública: si llega algo que no es un arreglo,
  -- jsonb_array_elements lanzaría excepción. Mejor salir callado.
  if jsonb_typeof(p_lineas) <> 'array' then return; end if;

  -- OJO: `numero` NO es único. Verificado el 24-08-2026 contra la base:
  -- "N° CL-0726-100" está repetido 152 veces. Buscar solo por número pegaría
  -- las líneas a una cotización cualquiera de ese grupo.
  -- Por eso se acota a los últimos 10 minutos: esta función la llama el
  -- navegador un instante después de insertar, así que la fila recién creada
  -- es la única candidata real. Si no hay ninguna reciente, no hace nada.
  -- "nulls last" porque en Postgres un ORDER BY ... DESC pone los NULL PRIMERO.
  select c.id into v_id
  from cotizaciones c
  where c.numero = p_numero
    and c.fecha_creacion >= now() - interval '10 minutes'
  order by c.fecha_creacion desc nulls last
  limit 1;

  if v_id is null then return; end if;

  -- idempotente: si ya tiene líneas (doble clic, reintento), no duplica
  if exists (select 1 from cotizacion_lineas l where l.cotizacion_id = v_id) then
    return;
  end if;

  insert into cotizacion_lineas (cotizacion_id, modelo, largo_cm, ancho_cm, cantidad, m2)
  select v_id,
         nullif(e->>'modelo',''),
         (e->>'largo_cm')::numeric,
         (e->>'ancho_cm')::numeric,
         coalesce((e->>'cantidad')::int, 1),
         (e->>'m2')::numeric
  from jsonb_array_elements(p_lineas) as e;
end;
$$;

grant execute on function public.guardar_lineas(text, jsonb) to anon;

-- ── verificación ──
-- Cotiza algo real en el sitio y después, con una sesión del panel iniciada:
--   select c.numero, c.producto, l.modelo, l.largo_cm, l.ancho_cm, l.cantidad, l.m2
--   from cotizaciones c join cotizacion_lineas l on l.cotizacion_id = c.id
--   order by c.fecha_creacion desc limit 20;
