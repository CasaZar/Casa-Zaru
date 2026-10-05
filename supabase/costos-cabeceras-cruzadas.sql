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
-- Casa Zaru · Costos: cabeceras cruzadas de la época Firebase (05-10-2026)
--
-- Parche suelto, corrido a mano y NO registrado en schema_migrations.
--
-- En gestion_costos, las filas 1453 y 1469 tenían las líneas de costo correctas,
-- pero la cabecera (cliente, producto, venta) era de otro pedido:
--   1453 decía Alexander Mhule, venta $0; sus líneas (Raulí 45×50 = 0,225 m²)
--        son de Barrientos Lobos, que es el 1453 en Finanzas.
--   1469 decía Marcela Paz, venta $647.105; sus líneas (3 repisas de Mañío =
--        0,76 m²) son de Soledad Puelma, que es el 1469 en Finanzas.
-- Mhule (D1024) y Neira (D1025) son devoluciones: se quedan sin fila de Costos.
--
-- Las 3 filas con clave Firebase (cmp…) tenían la cabecera correcta pero ningún
-- costo (sin líneas, o líneas en $0). Carrasco ya está completo en la 1455.
-- La venta es la de Finanzas.
--
-- Copia previa de las 5 filas en Drive:
--   Respaldos Gestion\costos-cabeceras-cruzadas-antes-de-arreglar-2026-10-05.json
--
-- Todo o nada: si alguna fila no está como se esperaba (por ejemplo, porque
-- ya se corrió), se lanza un error y no se aplica nada.
-- ══════════════════════════════════════════════════════════════

do $arreglo$
declare n int;
begin
  update gestion_costos
     set data = data || jsonb_build_object(
           'nombre', 'LUIS ORLANDO', 'apellido', 'BARRIENTOS LOBOS',
           'producto', 'BANQUETA LLANQUIHUE', 'fecha', '23-05-2026',
           'semana', 'SEMANA 19 MAYO', 'venta_total', 123225)
   where num = '1453' and data->>'apellido' ilike '%MHULE%';
  get diagnostics n = row_count;
  if n <> 1 then raise exception '1453: se esperaba 1 fila con cabecera de Mhule, hubo %. No se aplicó nada.', n; end if;

  update gestion_costos
     set data = data || jsonb_build_object(
           'nombre', 'SOLEDAD', 'apellido', 'PUELMA',
           'producto', 'REPISA', 'fecha', '27-05-2026',
           'semana', 'SEMANA 8 JUNIO', 'venta_total', 244744)
   where num = '1469' and data->>'nombre' ilike 'MARCELA%';
  get diagnostics n = row_count;
  if n <> 1 then raise exception '1469: se esperaba 1 fila con cabecera de Marcela Paz, hubo %. No se aplicó nada.', n; end if;

  -- Solo se borran si de verdad no tienen ningún costo con monto.
  delete from gestion_costos c
   where c.num in ('cmphs3szq6', 'cmpij66dt7', 'cmpikozzy25')
     and not exists (
           select 1 from jsonb_array_elements(coalesce(c.data->'lineas', '[]'::jsonb)) l
            where coalesce((l->>'total')::numeric, 0) <> 0);
  get diagnostics n = row_count;
  if n <> 3 then raise exception 'cmp…: se esperaba borrar 3 filas vacías, hubo %. No se aplicó nada.', n; end if;
end
$arreglo$;

-- Resultado: deberían quedar 1453 Barrientos Lobos y 1469 Puelma, y ninguna fila cmp….
select num, data->>'nombre' as nombre, data->>'apellido' as apellido,
       data->>'producto' as producto, data->>'venta_total' as venta,
       jsonb_array_length(coalesce(data->'lineas', '[]'::jsonb)) as lineas
  from gestion_costos
 where num in ('1453', '1469', '1455') or num like 'cmp%'
 order by num;
