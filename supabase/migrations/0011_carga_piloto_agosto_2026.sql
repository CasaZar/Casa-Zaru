-- ══════════════════════════════════════════════════════════════════════════
-- MIGRACIÓN 0011 · CARGA PILOTO — documentos recibidos de agosto 2026
--
-- PROYECTO SUPABASE: padnttpgzuotxeipjrry
--
-- ── QUÉ ES ────────────────────────────────────────────────────────────────
-- Prueba de extremo a extremo de la 0010: los 79 documentos `received:true`
-- de agosto 2026 que Wasabil (MUVALE DISEÑO SPA) registra como recibidos de
-- proveedores, extraídos vía MCP (`get_documents` + `get_document`, uno por
-- uno), menos las 6 Notas de Crédito (sii_document_type_id 61) que se
-- excluyen a propósito (restan del gasto, no encajan en el flujo de
-- clasificación Inventario/Gasto Fijo — ver 0010).
--
-- Quedan 73 documentos, 85 líneas. No están clasificadas (`tipo` en null en
-- todas) — esta migración solo carga los datos crudos para probar el
-- circuito completo antes de decidir si se hace el backfill histórico de
-- los ~1.400 documentos restantes.
--
-- 6 de los 73 documentos (SODIMAC x3, IMPERIAL, EASY RETAIL, BCI) llegaron
-- de Wasabil sin el objeto `supplier` vinculado (get_document devolvía
-- supplier: null) — se completó proveedor_rut/proveedor_nombre a mano con
-- receiver_rut/receiver_name, que sí vienen siempre en la cabecera del
-- documento y son el mismo dato por otra vía.
--
-- `on conflict do nothing` en ambas tablas: correrla de nuevo no duplica
-- nada si algún documento ya quedó cargado.
--
-- Generada con supabase/../scratchpad/generar_sql_piloto.js a partir de
-- wasabil_pilot_agosto_2026.jsonl — ese script y ese JSONL NO forman parte
-- del repo, viven en el scratchpad de la sesión que hizo la extracción.
-- ══════════════════════════════════════════════════════════════════════════

-- Carga de datos: piloto de documentos recibidos de agosto 2026 (Wasabil).
-- Generado automáticamente desde wasabil_pilot_agosto_2026.jsonl.
-- Excluye Notas de Crédito (sii_document_type_id = 61) a propósito.

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260900009038, '6a4527d0-dff7-4878-af6c-ed485badc5ea', '634', 33, 'Factura de Venta', '6.896.910-7', 'HERNAN GABRIEL SANDOVAL ZUNIGA', '2026-08-29', 28600, 5434, 34034)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'RAULI', '', 1.1, 26000, 28600, 5434, 34034, NULL, false
from documentos_recibidos where wasabil_document = 20260900009038
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260900002595, '92877c8e-83c7-4896-86d2-4624ac6d2e92', '5315', 33, 'Factura de Venta', '77.891.523-5', 'FERRETERIA Y COMERCIAL JESSICA ELIANA SANCHEZ ABURTO E.I.R.L.', '2026-08-19', 1252, 238, 1490)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Detalle no disponible', NULL, 1, 1252, 1252, 238, 1490, NULL, false
from documentos_recibidos where wasabil_document = 20260900002595
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260900002594, '898063c1-3211-4b46-bc23-e95e93b1b818', '5352', 33, 'Factura de Venta', '77.891.523-5', 'FERRETERIA Y COMERCIAL JESSICA ELIANA SANCHEZ ABURTO E.I.R.L.', '2026-08-22', 7773, 1477, 9250)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Detalle no disponible', NULL, 1, 7773, 7773, 1477, 9250, NULL, false
from documentos_recibidos where wasabil_document = 20260900002594
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260900002593, 'f88439ba-2b4c-4c54-9073-46862d45294a', '5366', 33, 'Factura de Venta', '77.891.523-5', 'FERRETERIA Y COMERCIAL JESSICA ELIANA SANCHEZ ABURTO E.I.R.L.', '2026-08-24', 1975, 375, 2350)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Detalle no disponible', NULL, 1, 1975, 1975, 375, 2350, NULL, false
from documentos_recibidos where wasabil_document = 20260900002593
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260900002592, 'bd217ace-58e6-4b2a-bcd5-81bad63f8529', '5364', 33, 'Factura de Venta', '77.891.523-5', 'FERRETERIA Y COMERCIAL JESSICA ELIANA SANCHEZ ABURTO E.I.R.L.', '2026-08-24', 13840, 2630, 16470)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Detalle no disponible', NULL, 1, 13840, 13840, 2630, 16470, NULL, false
from documentos_recibidos where wasabil_document = 20260900002592
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260900002591, '9bf86043-57e0-42e3-8e0e-791bf2bdde4f', '5388', 33, 'Factura de Venta', '77.891.523-5', 'FERRETERIA Y COMERCIAL JESSICA ELIANA SANCHEZ ABURTO E.I.R.L.', '2026-08-26', 22445, 4265, 26710)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Detalle no disponible', NULL, 1, 22445, 22445, 4265, 26710, NULL, false
from documentos_recibidos where wasabil_document = 20260900002591
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260900002590, 'aa14f423-6ccb-418f-ae44-449266096361', '5402', 33, 'Factura de Venta', '77.891.523-5', 'FERRETERIA Y COMERCIAL JESSICA ELIANA SANCHEZ ABURTO E.I.R.L.', '2026-08-27', 14857, 2823, 17680)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Detalle no disponible', NULL, 1, 14857, 14857, 2823, 17680, NULL, false
from documentos_recibidos where wasabil_document = 20260900002590
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260900002589, '0cf7446e-2d20-4489-809c-4d2c06f3645f', '104026', 33, 'Factura de Venta', '89.747.000-4', 'Sociedad Aserradero Voipir Limitada', '2026-08-27', 32124, 6104, 38228)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Detalle no disponible', NULL, 1, 32124, 32124, 6104, 38228, NULL, false
from documentos_recibidos where wasabil_document = 20260900002589
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260900002588, '4bfe0e69-77be-44e2-b29b-365723a5665b', '5424', 33, 'Factura de Venta', '77.891.523-5', 'FERRETERIA Y COMERCIAL JESSICA ELIANA SANCHEZ ABURTO E.I.R.L.', '2026-08-29', 10672, 2028, 12700)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Detalle no disponible', NULL, 1, 10672, 10672, 2028, 12700, NULL, false
from documentos_recibidos where wasabil_document = 20260900002588
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800374229, 'c83f99f8-10aa-4270-94db-d6e1557c07e9', '541705', 33, 'Factura de Venta', '76.830.014-3', 'FLOW S A', '2026-08-31', 79215, 15051, 94266)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'SERVICIO DE PAGO Y RECAUDACION FLOW MES DE 08-2026', 'SERVICIO DE PAGO Y RECAUDACION FLOW MES DE 08-2026', 1, 79215, 79215, 15051, 94266, NULL, false
from documentos_recibidos where wasabil_document = 20260800374229
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800373997, 'e434fcaf-c5bf-4b7f-b333-532b58fea4df', '30193', 33, 'Factura de Venta', '76.917.961-5', 'IMPORTADORA DECOHOGAR ESPACIO SPA', '2026-08-31', 5882, 1118, 7000)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'POLERA UNICOLOR', 'POLERA UNICOLOR', 2, 2941.18, 5882, 1118, 7000, NULL, false
from documentos_recibidos where wasabil_document = 20260800373997
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800373522, 'c3de670f-c6a8-4082-82bb-152aa692016d', '978', 33, 'Factura de Venta', '77.194.395-0', 'SOCIEDAD EXPLOTADORA Y COMERCIALIZADORA DE MADERAS RENATTE TORREALBA Y', '2026-08-31', 1585340, 301215, 1886555)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'COIGUE V TABLA', '', 30.51, 24000, 732240, 139126, 871366, NULL, false
from documentos_recibidos where wasabil_document = 20260800373522
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 2, 'COIGUE VI TABLA', '', 4.66, 19000, 88540, 16823, 105363, NULL, false
from documentos_recibidos where wasabil_document = 20260800373522
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 3, 'RAULI HUALLE V', '', 2.5, 24000, 60000, 11400, 71400, NULL, false
from documentos_recibidos where wasabil_document = 20260800373522
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 4, 'MAÑIO V', '', 13.39, 24000, 321360, 61058, 382418, NULL, false
from documentos_recibidos where wasabil_document = 20260800373522
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 5, 'MAÑIO VI', '', 4, 19000, 76000, 14440, 90440, NULL, false
from documentos_recibidos where wasabil_document = 20260800373522
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 6, 'CIPRES SEGUNDA SELECCION', '', 19.2, 16000, 307200, 58368, 365568, NULL, false
from documentos_recibidos where wasabil_document = 20260800373522
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800349457, '855f61bf-66eb-41db-8818-b889a350ff7a', '149303951', 33, 'Factura de Venta', '96.792.430-K', 'SODIMAC S.A.', '2026-08-29', 39278, 7463, 46741)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'BARNIZ VITRIFICANTE SBR 1GL', '', 1, 39278.151261, 39278, 7463, 46741, NULL, false
from documentos_recibidos where wasabil_document = 20260800349457
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800345079, 'd16576f9-f0ef-4f02-ad94-0702c885bf95', '79252', 33, 'Factura de Venta', '70.011.230-6', 'Cooperativa de Servicios para Pequenos Industriales y Artesanos de Villarrica Limitada', '2026-08-20', 10924, 2076, 13000)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Detalle no disponible', NULL, 1, 10924, 10924, 2076, 13000, NULL, false
from documentos_recibidos where wasabil_document = 20260800345079
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800311446, '2278000c-64dd-48a2-8797-452a18507854', '103877', 33, 'Factura de Venta', '89.747.000-4', 'Sociedad Aserradero Voipir Limitada', '2026-08-18', 8198, 1558, 9756)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Detalle no disponible', NULL, 1, 8198, 8198, 1558, 9756, NULL, false
from documentos_recibidos where wasabil_document = 20260800311446
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800311445, 'dee3fd03-4eee-4ec2-92cb-dffa2390538b', '131383', 33, 'Factura de Venta', '76.419.669-4', 'COMERCIAL FLORES LIMITADA', '2026-08-18', 3950, 751, 4701)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Detalle no disponible', NULL, 1, 3950, 3950, 751, 4701, NULL, false
from documentos_recibidos where wasabil_document = 20260800311445
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800311444, '5c59d7a9-2acc-405b-a998-205bc8bf8774', '1096505', 33, 'Factura de Venta', '78.633.060-2', 'SOC. AGRICOLA HUIFQUENCO Y CIA. LTDA.', '2026-08-26', 10055, 1910, 11965)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Detalle no disponible', NULL, 1, 10055, 10055, 1910, 11965, NULL, false
from documentos_recibidos where wasabil_document = 20260800311444
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800301172, 'd54fbcec-baca-4915-b3c0-8620b8b86039', '2764387', 33, 'Factura de Venta', '96.794.750-4', 'Starken SpA', '2026-08-31', 100689, 19131, 119820)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'TRANSPORTE CARGA Y ENCOMIENDA  PERIODO AGOSTO 2026', '', 1, 100689, 100689, 19131, 119820, NULL, false
from documentos_recibidos where wasabil_document = 20260800301172
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800301171, '30f9aae9-4f80-4070-9094-86cf1a303579', '2764386', 33, 'Factura de Venta', '96.794.750-4', 'Starken SpA', '2026-08-31', 531496, 100984, 632480)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'TRANSPORTE CARGA Y ENCOMIENDA  PERIODO AGOSTO 2026', '', 1, 531496, 531496, 100984, 632480, NULL, false
from documentos_recibidos where wasabil_document = 20260800301171
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800290889, '042b021b-810d-4d92-985d-852e0927258a', '103838', 33, 'Factura de Venta', '89.747.000-4', 'Sociedad Aserradero Voipir Limitada', '2026-08-17', 51771, 9836, 61607)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Detalle no disponible', NULL, 1, 51771, 51771, 9836, 61607, NULL, false
from documentos_recibidos where wasabil_document = 20260800290889
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800281662, '64f810cd-9c19-4f4e-bb8e-7ac521c6dc5f', '20444509', 33, 'Factura de Venta', '76.821.330-5', 'IMPERIAL S.A.', '2026-08-24', 240831, 45758, 286589)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'TABLERO MDF 3MM 1,52X2,44MT', '.', 35, 6168.07, 215882, 41018, 256900, NULL, false
from documentos_recibidos where wasabil_document = 20260800281662
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 2, 'FLETES A CLIENTES', '.', 1, 24948.74, 24949, 4740, 29689, NULL, false
from documentos_recibidos where wasabil_document = 20260800281662
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800279422, 'b79ab1ff-daed-4026-aaba-d64cfaa890b3', '1096096', 33, 'Factura de Venta', '78.633.060-2', 'SOC. AGRICOLA HUIFQUENCO Y CIA. LTDA.', '2026-08-24', 10055, 1910, 11965)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Detalle no disponible', NULL, 1, 10055, 10055, 1910, 11965, NULL, false
from documentos_recibidos where wasabil_document = 20260800279422
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800253087, '7c208a4f-531a-4837-b080-1776757cc38a', '905092', 33, 'Factura de Venta', '8.217.668-3', 'CARLOS ENRIQUE CESPEDES MEDINA', '2026-08-21', 11765, 2235, 14000)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Serv. Transporte OT2699944 desde Villarrica a Casa Matriz - Santiago', '', 1, 11765, 11765, 2235, 14000, NULL, false
from documentos_recibidos where wasabil_document = 20260800253087
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800247295, '4bcd2f9c-7245-4ad9-b417-9c9dae0d4f80', '1095268', 33, 'Factura de Venta', '78.633.060-2', 'SOC. AGRICOLA HUIFQUENCO Y CIA. LTDA.', '2026-08-20', 10055, 1910, 11965)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Detalle no disponible', NULL, 1, 10055, 10055, 1910, 11965, NULL, false
from documentos_recibidos where wasabil_document = 20260800247295
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800247294, '912f6dd1-e643-4d44-b597-1c244bb50bd0', '38786738', 33, 'Factura de Venta', '76.568.660-1', 'EASY RETAIL S.A.', '2026-08-20', 53726, 10208, 63934)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'BARNIZ VITROLUX 65 MATE NATURAL 1GL', 'Descuento Manual Mayorista $ 14593', 1, 58395, 46132, 8765, 54897, NULL, false
from documentos_recibidos where wasabil_document = 20260800247294
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 2, 'ANTICORROSIVO AQUATECH NEGRO 1/4 GL', 'Descuento Manual Mayorista $ 2854', 1, 9992, 7594, 1443, 9037, NULL, false
from documentos_recibidos where wasabil_document = 20260800247294
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800243257, '33ce4831-7420-4219-a4ee-71424ed31493', '14711439', 33, 'Factura de Venta', '77.398.220-1', 'MercadoLibre Chile LTDA', '2026-08-20', 4682, 889, 5571)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Rollo Film Stretch Alusa 300 Mts 1,7kg Embalaje Negro', '', 1, 4682, 4682, 890, 5572, NULL, false
from documentos_recibidos where wasabil_document = 20260800243257
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800243256, '9fb216e5-4084-4a9b-a888-349ef9a79e77', '14711440', 33, 'Factura de Venta', '77.398.220-1', 'MercadoLibre Chile LTDA', '2026-08-20', 4682, 889, 5571)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Rollo Film Stretch Alusa 300 Mts 1,7kg Embalaje Negro', '', 1, 4682, 4682, 890, 5572, NULL, false
from documentos_recibidos where wasabil_document = 20260800243256
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800243255, '92c19a09-9aff-4dff-8454-4da63c310b11', '14711441', 33, 'Factura de Venta', '77.398.220-1', 'MercadoLibre Chile LTDA', '2026-08-20', 4682, 889, 5571)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Rollo Film Stretch Alusa 300 Mts 1,7kg Embalaje Negro', '', 1, 4682, 4682, 890, 5572, NULL, false
from documentos_recibidos where wasabil_document = 20260800243255
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800243254, 'ca964edc-8378-4f83-8eca-f0f87b9e2cdb', '14711443', 33, 'Factura de Venta', '77.398.220-1', 'MercadoLibre Chile LTDA', '2026-08-20', 4682, 889, 5571)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Rollo Film Stretch Alusa 300 Mts 1,7kg Embalaje Negro', '', 1, 4682, 4682, 890, 5572, NULL, false
from documentos_recibidos where wasabil_document = 20260800243254
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800243246, 'd7080a1b-1ff5-4348-8e8c-032303140534', '14711433', 33, 'Factura de Venta', '77.398.220-1', 'MercadoLibre Chile LTDA', '2026-08-20', 4682, 889, 5571)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Rollo Film Stretch Alusa 300 Mts 1,7kg Embalaje Negro', '', 1, 4682, 4682, 890, 5572, NULL, false
from documentos_recibidos where wasabil_document = 20260800243246
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800242944, 'cc039e8f-989e-465e-a251-7e35704a0c2f', '546469', 33, 'Factura de Venta', '76.353.910-5', 'SUPERMERCADO SANTA VICTORIA LTDA.', '2026-08-20', 3504, 666, 4170)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'XLPXX1X$1390 PH CONFORT DH 22MT 4 ROLLOS D', '', 3, 1168.0672, 3504, 666, 4170, NULL, false
from documentos_recibidos where wasabil_document = 20260800242944
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800242652, '04c83056-b9a7-4d40-a171-ca61fcc20d80', '6477', 33, 'Factura de Venta', '77.382.218-2', 'ADELPACK LTDA', '2026-08-20', 127500, 24225, 151725)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'ESQUINERO CARTON - 50 x 50 x 1500 MM - BLANCO', '', 300, 425, 127500, 24225, 151725, NULL, false
from documentos_recibidos where wasabil_document = 20260800242652
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800239023, 'd2d61f74-9096-4ce3-bcb4-3ac819f825b6', '6989', 33, 'Factura de Venta', '76.814.411-7', 'Prism4 Estudio de diseño Limitada', '2026-08-20', 15000, 2850, 17850)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Adhesivo Troquelado (Ecosolvente)', 'Stickers impresos en alta calidad EPSON Adhesivo PVC.En caso de necesitar que el adhesivo sea más resistente al desgaste por uso constante, te sugerimos solicitar una cotización que incorpore laminado o impresión UV . Cada producto viene con la opción de dos diseños. Si deseas añadir otro diseño adicional, puedes hacerlo costo extra. 1/2 metro de cada etiqueta (2 diseños)', 1, 15000, 15000, 2850, 17850, NULL, false
from documentos_recibidos where wasabil_document = 20260800239023
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800237084, 'a62530eb-8cc7-476a-9cdc-c0f10b561df6', '6981', 33, 'Factura de Venta', '76.814.411-7', 'Prism4 Estudio de diseño Limitada', '2026-08-20', 13445, 2555, 16000)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Impresión de hoja/pliego (Láser 33x48 Cm)', 'etiquetas de 7,3x7,3 en papel couché de 300 grs por ambas caras', 4, 3361.25, 13445, 2555, 16000, NULL, false
from documentos_recibidos where wasabil_document = 20260800237084
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800234422, '80d0b4ee-c520-47cb-959c-f5461673f8e9', '5161', 33, 'Factura de Venta', '77.891.523-5', 'FERRETERIA Y COMERCIAL JESSICA ELIANA SANCHEZ ABURTO E.I.R.L.', '2026-08-03', 23504, 4466, 27970)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Detalle no disponible', NULL, 1, 23504, 23504, 4466, 27970, NULL, false
from documentos_recibidos where wasabil_document = 20260800234422
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800234421, '2425f481-8c49-49cc-871b-7697aef6ccb2', '5214', 33, 'Factura de Venta', '77.891.523-5', 'FERRETERIA Y COMERCIAL JESSICA ELIANA SANCHEZ ABURTO E.I.R.L.', '2026-08-10', 23504, 4466, 27970)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Detalle no disponible', NULL, 1, 23504, 23504, 4466, 27970, NULL, false
from documentos_recibidos where wasabil_document = 20260800234421
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800234420, '88ae3639-fd77-4772-9a07-8ca2d73a42f5', '5230', 33, 'Factura de Venta', '77.891.523-5', 'FERRETERIA Y COMERCIAL JESSICA ELIANA SANCHEZ ABURTO E.I.R.L.', '2026-08-11', 13857, 2633, 16490)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Detalle no disponible', NULL, 1, 13857, 13857, 2633, 16490, NULL, false
from documentos_recibidos where wasabil_document = 20260800234420
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800234419, '07fa1db6-2695-47e8-a65a-8ce48d86d6d7', '5225', 33, 'Factura de Venta', '77.891.523-5', 'FERRETERIA Y COMERCIAL JESSICA ELIANA SANCHEZ ABURTO E.I.R.L.', '2026-08-11', 5849, 1111, 6960)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Detalle no disponible', NULL, 1, 5849, 5849, 1111, 6960, NULL, false
from documentos_recibidos where wasabil_document = 20260800234419
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800234418, 'd613c86e-8bdd-4408-bbe9-5aeded0e5db2', '5291', 33, 'Factura de Venta', '77.891.523-5', 'FERRETERIA Y COMERCIAL JESSICA ELIANA SANCHEZ ABURTO E.I.R.L.', '2026-08-18', 27529, 5231, 32760)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Detalle no disponible', NULL, 1, 27529, 27529, 5231, 32760, NULL, false
from documentos_recibidos where wasabil_document = 20260800234418
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800234417, 'a49491f2-d24e-4acf-97c4-15cffdd7e636', '5294', 33, 'Factura de Venta', '77.891.523-5', 'FERRETERIA Y COMERCIAL JESSICA ELIANA SANCHEZ ABURTO E.I.R.L.', '2026-08-18', 2437, 463, 2900)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Detalle no disponible', NULL, 1, 2437, 2437, 463, 2900, NULL, false
from documentos_recibidos where wasabil_document = 20260800234417
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800225921, '8c349437-8c1a-4a9d-958c-ae2fb0231333', '903896', 33, 'Factura de Venta', '8.217.668-3', 'CARLOS ENRIQUE CESPEDES MEDINA', '2026-08-19', 126050, 23950, 150000)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Serv. Transporte OT2699890 desde Villarrica a Casa Matriz - Santiago', '', 1, 126050, 126050, 23950, 150000, NULL, false
from documentos_recibidos where wasabil_document = 20260800225921
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800216764, '756a3710-66e7-4fa9-aaba-1f33ab03310b', '1094711', 33, 'Factura de Venta', '78.633.060-2', 'SOC. AGRICOLA HUIFQUENCO Y CIA. LTDA.', '2026-08-18', 20109, 3821, 23930)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Detalle no disponible', NULL, 1, 20109, 20109, 3821, 23930, NULL, false
from documentos_recibidos where wasabil_document = 20260800216764
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800166392, '394c31b7-93fe-41cb-b026-e26ac789ca31', '1094007', 33, 'Factura de Venta', '78.633.060-2', 'SOC. AGRICOLA HUIFQUENCO Y CIA. LTDA.', '2026-08-13', 1639, 311, 1950)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Detalle no disponible', NULL, 1, 1639, 1639, 311, 1950, NULL, false
from documentos_recibidos where wasabil_document = 20260800166392
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800161244, '97c4e609-5a0e-407e-a17e-72f01034b64d', '901411', 33, 'Factura de Venta', '8.217.668-3', 'CARLOS ENRIQUE CESPEDES MEDINA', '2026-08-13', 50420, 9580, 60000)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Serv. Transporte OT2668924 desde Villarrica a Casa Matriz - Santiago', '', 1, 50420, 50420, 9580, 60000, NULL, false
from documentos_recibidos where wasabil_document = 20260800161244
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800160742, '987a603f-3bb2-420c-b1f8-dba38922c465', '2164', 33, 'Factura de Venta', '76.228.195-3', 'SOCIEDAD AGROFORESTAL CARELMAPU LIMITADA', '2026-08-13', 24750, 4703, 29453)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'PLANTAS RAULI', '', 25, 990, 24750, 4703, 29453, NULL, false
from documentos_recibidos where wasabil_document = 20260800160742
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800159942, '08ce5b7d-2eae-4d61-9682-ea3d4f69d54f', '14605164', 33, 'Factura de Venta', '77.398.220-1', 'MercadoLibre Chile LTDA', '2026-08-13', 4682, 889, 5571)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Rollo Film Stretch Alusa 300 Mts 1,7kg Embalaje Negro', '', 1, 4682, 4682, 890, 5572, NULL, false
from documentos_recibidos where wasabil_document = 20260800159942
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800159937, '191fb19b-3204-43f5-ae6b-30fb728d8dbc', '14605143', 33, 'Factura de Venta', '77.398.220-1', 'MercadoLibre Chile LTDA', '2026-08-13', 4682, 889, 5571)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Rollo Film Stretch Alusa 300 Mts 1,7kg Embalaje Negro', '', 1, 4682, 4682, 890, 5572, NULL, false
from documentos_recibidos where wasabil_document = 20260800159937
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800159936, '7c00b2b6-5a14-4861-854c-e8c5772ffc7d', '14605147', 33, 'Factura de Venta', '77.398.220-1', 'MercadoLibre Chile LTDA', '2026-08-13', 4682, 889, 5571)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Rollo Film Stretch Alusa 300 Mts 1,7kg Embalaje Negro', '', 1, 4682, 4682, 890, 5572, NULL, false
from documentos_recibidos where wasabil_document = 20260800159936
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800159935, '2852af35-646a-40d1-a51f-5032918cec41', '14605115', 33, 'Factura de Venta', '77.398.220-1', 'MercadoLibre Chile LTDA', '2026-08-13', 4682, 889, 5571)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Rollo Film Stretch Alusa 300 Mts 1,7kg Embalaje Negro', '', 1, 4682, 4682, 890, 5572, NULL, false
from documentos_recibidos where wasabil_document = 20260800159935
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800159934, '1f525788-d472-4fd7-8804-f786e4173cc9', '14605118', 33, 'Factura de Venta', '77.398.220-1', 'MercadoLibre Chile LTDA', '2026-08-13', 4682, 889, 5571)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Rollo Film Stretch Alusa 300 Mts 1,7kg Embalaje Negro', '', 1, 4682, 4682, 890, 5572, NULL, false
from documentos_recibidos where wasabil_document = 20260800159934
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800159932, 'e11af47a-dd94-42c5-940e-937d960aa7b0', '14605134', 33, 'Factura de Venta', '77.398.220-1', 'MercadoLibre Chile LTDA', '2026-08-13', 4682, 889, 5571)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Rollo Film Stretch Alusa 300 Mts 1,7kg Embalaje Negro', '', 1, 4682, 4682, 890, 5572, NULL, false
from documentos_recibidos where wasabil_document = 20260800159932
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800159931, 'ab0061fe-5784-457b-9ba1-9211eba0b681', '14605139', 33, 'Factura de Venta', '77.398.220-1', 'MercadoLibre Chile LTDA', '2026-08-13', 4682, 889, 5571)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Rollo Film Stretch Alusa 300 Mts 1,7kg Embalaje Negro', '', 1, 4682, 4682, 890, 5572, NULL, false
from documentos_recibidos where wasabil_document = 20260800159931
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800159930, '4a73c314-ec8c-45b4-88d6-5deaa2138356', '14605138', 33, 'Factura de Venta', '77.398.220-1', 'MercadoLibre Chile LTDA', '2026-08-13', 4682, 889, 5571)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Rollo Film Stretch Alusa 300 Mts 1,7kg Embalaje Negro', '', 1, 4682, 4682, 890, 5572, NULL, false
from documentos_recibidos where wasabil_document = 20260800159930
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800156665, '2af0a20f-ac5a-436e-8d74-c1678c5c7031', '28633', 33, 'Factura de Venta', '12.358.319-1', 'MARIO WILIAM ZAGAL SEPULVEDA', '2026-08-13', 27647, 5253, 32900)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'CARTON CORRUGADO 1 20 X 25 MTS', 'CARTON CORRUGADO 1 20 X 25 MTS', 1, 27647.06, 27647, 5253, 32900, NULL, false
from documentos_recibidos where wasabil_document = 20260800156665
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800153610, '8161c86b-e6c2-4ec2-af2a-f3440ff2fb55', '229587', 34, 'Factura Exenta', '77.751.367-2', 'Mercado Pago Lending Ltda', '2026-08-01', 17868, 0, 17868)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Detalle no disponible', NULL, 1, 17868, 17868, 0, 17868, NULL, true
from documentos_recibidos where wasabil_document = 20260800153610
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800153609, '1f2d77a4-98d6-4686-bcaf-ae655d9b25f7', '130729', 33, 'Factura de Venta', '76.419.669-4', 'COMERCIAL FLORES LIMITADA', '2026-08-03', 3109, 591, 3700)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Detalle no disponible', NULL, 1, 3109, 3109, 591, 3700, NULL, false
from documentos_recibidos where wasabil_document = 20260800153609
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800146998, 'c0c688e4-09fb-4399-b1cb-4b5412893c31', '38483967', 33, 'Factura de Venta', '76.568.660-1', 'EASY RETAIL S.A.', '2026-08-12', 64213, 12200, 76413)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'TABLERO MDF 3X1520X2440MM', 'Descuento Manual Mayorista $ 1169', 2, 9824, 18665, 3546, 22211, NULL, false
from documentos_recibidos where wasabil_document = 20260800146998
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 2, 'BARNIZ VITROLUX 65 MATE NATURAL 1GL', 'Descuento Manual Mayorista $ 15288', 1, 58395, 45548, 8654, 54202, NULL, false
from documentos_recibidos where wasabil_document = 20260800146998
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800139205, '8c1e34cc-7d91-4467-8e90-773a29c3c233', '18317368', 33, 'Factura de Venta', '78.921.690-8', 'WOM SpA', '2026-08-01', 23676, 4498, 28174)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Detalle no disponible', NULL, 1, 23676, 23676, 4498, 28174, NULL, false
from documentos_recibidos where wasabil_document = 20260800139205
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800139204, 'c80c4c26-a237-4b60-be27-1b23f00b38ae', '78912', 33, 'Factura de Venta', '70.011.230-6', 'Cooperativa de Servicios para Pequenos Industriales y Artesanos de Villarrica Limitada', '2026-08-03', 16387, 3114, 19501)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Detalle no disponible', NULL, 1, 16387, 16387, 3114, 19501, NULL, false
from documentos_recibidos where wasabil_document = 20260800139204
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800139203, '21826355-bb4e-4539-bb33-a1573decfc28', '103600', 33, 'Factura de Venta', '89.747.000-4', 'Sociedad Aserradero Voipir Limitada', '2026-08-03', 104402, 19836, 124238)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Detalle no disponible', NULL, 1, 104402, 104402, 19836, 124238, NULL, false
from documentos_recibidos where wasabil_document = 20260800139203
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800139202, 'bc6fd445-ec24-45ca-ae46-652ba7d11723', '30610529', 33, 'Factura de Venta', '97.006.000-6', 'BANCO DE CREDITO E INVERSIONES', '2026-08-07', 3404, 647, 4051)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'COMISION POR PLAN CUENTA CORRIENTE', '', 1, 0, 3404, 647, 4051, NULL, false
from documentos_recibidos where wasabil_document = 20260800139202
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800131704, '3e3e4b38-ebaf-4c23-a9bc-0966797b581e', '148803598', 33, 'Factura de Venta', '96.792.430-K', 'SODIMAC S.A.', '2026-08-11', 58606, 11135, 69741)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'PULIDORA ALAMBRICA 1300W CUN13', '', 1, 58605.88, 58606, 11135, 69741, NULL, false
from documentos_recibidos where wasabil_document = 20260800131704
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800129865, '1575de6b-2348-4636-9858-4619c81be9c8', '627', 33, 'Factura de Venta', '6.896.910-7', 'HERNAN GABRIEL SANDOVAL ZUNIGA', '2026-08-11', 106200, 20178, 126378)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'CASTAÑO', '', 4, 22000, 88000, 16720, 104720, NULL, false
from documentos_recibidos where wasabil_document = 20260800129865
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 2, 'RAULI', '', 1, 18200, 18200, 3458, 21658, NULL, false
from documentos_recibidos where wasabil_document = 20260800129865
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800106333, '9da4c56c-b17e-43e6-a267-1b0bd735a528', '148810456', 33, 'Factura de Venta', '96.792.430-K', 'SODIMAC S.A.', '2026-08-08', 11794, 2241, 14035)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'PACK 2 POMO LATON33MM NG MT CU', '', 1, 3743.69, 3744, 711, 4455, NULL, false
from documentos_recibidos where wasabil_document = 20260800106333
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 2, 'BISAGRA C/S CURVA 35MM 110 2UN', '', 1, 1508.4, 1508, 287, 1795, NULL, false
from documentos_recibidos where wasabil_document = 20260800106333
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 3, 'BISAGRA C/S CURVA 35MM 110 2UN', '', 1, 1508.4, 1508, 287, 1795, NULL, false
from documentos_recibidos where wasabil_document = 20260800106333
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 4, 'ORGANIZADOR DOBLE 15 COMPARTI', '', 1, 5033.61, 5034, 956, 5990, NULL, false
from documentos_recibidos where wasabil_document = 20260800106333
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800100326, 'b3aec44e-e042-4f4d-b3d8-4edc6d6488b0', '1092586', 33, 'Factura de Venta', '78.633.060-2', 'SOC. AGRICOLA HUIFQUENCO Y CIA. LTDA.', '2026-08-07', 9552, 1815, 11367)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Detalle no disponible', NULL, 1, 9552, 9552, 1815, 11367, NULL, false
from documentos_recibidos where wasabil_document = 20260800100326
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800083552, '345e250a-fa23-468e-a1de-fa28643cb0e0', '15954', 33, 'Factura de Venta', '76.686.231-4', 'LA CIMA COWORK PUERTO VARAS SPA', '2026-08-06', 20000, 3800, 23800)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'ARRIENDO OFICINA COWORK', '', 1, 20000, 20000, 3800, 23800, NULL, false
from documentos_recibidos where wasabil_document = 20260800083552
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800082834, '64a3d8d0-a873-478a-af3b-bd3fb12a46c7', '625', 33, 'Factura de Venta', '6.896.910-7', 'HERNAN GABRIEL SANDOVAL ZUNIGA', '2026-08-06', 220000, 41800, 261800)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'CASTAÑO', '', 10, 22000, 220000, 41800, 261800, NULL, false
from documentos_recibidos where wasabil_document = 20260800082834
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800077766, 'ca749bc0-ae62-4996-bdd7-3c9dca2962d9', '2457', 33, 'Factura de Venta', '76.259.051-4', 'APICOLA ALEXANDER BUSCHE EMPRESA INDIVIDUAL DE RESPONSABILIDAD LIMITADA', '2026-08-06', 19500, 3705, 23205)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'cera estampada', '', 1.5, 13000, 19500, 3705, 23205, NULL, false
from documentos_recibidos where wasabil_document = 20260800077766
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800067616, '4efd41a1-90b2-4b67-84d2-a875631ac3e9', '14495400', 33, 'Factura de Venta', '77.398.220-1', 'MercadoLibre Chile LTDA', '2026-08-05', 40303, 7657, 47960)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Aceite De Coco Organico Extra Virgen Cocoma 1000ml', '', 4, 10076, 40303, 7658, 47961, NULL, false
from documentos_recibidos where wasabil_document = 20260800067616
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800036439, '27b18160-cea0-486a-aa4a-e2af85a114ab', '2899592', 33, 'Factura de Venta', '76.516.950-K', 'Mercado Pago Operadora S.A.', '2026-08-01', 81018, 15393, 96411)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Detalle no disponible', NULL, 1, 81018, 81018, 15393, 96411, NULL, false
from documentos_recibidos where wasabil_document = 20260800036439
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800036438, '2b8fadb8-4419-4456-92ff-0367cf241f27', '15255615', 33, 'Factura de Venta', '77.398.220-1', 'MercadoLibre Chile LTDA', '2026-08-01', 56495, 10734, 67229)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Detalle no disponible', NULL, 1, 56495, 56495, 10734, 67229, NULL, false
from documentos_recibidos where wasabil_document = 20260800036438
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800036437, 'd8888218-cc72-4478-9aeb-9fc6aa79f733', '1091585', 33, 'Factura de Venta', '78.633.060-2', 'SOC. AGRICOLA HUIFQUENCO Y CIA. LTDA.', '2026-08-03', 20109, 3821, 23930)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Detalle no disponible', NULL, 1, 20109, 20109, 3821, 23930, NULL, false
from documentos_recibidos where wasabil_document = 20260800036437
on conflict (documento_id, linea_n) do nothing;

insert into documentos_recibidos (wasabil_document, wasabil_uuid, folio, sii_document_type_id, sii_tipo_nombre, proveedor_rut, proveedor_nombre, fecha, neto, iva, total)
values (20260800001711, '4e04d66a-1c05-4f5f-aeec-d601307e78d5', '10852', 33, 'Factura de Venta', '77.391.967-4', 'Zamunda SpA', '2026-08-01', 34990, 6648, 41638)
on conflict (wasabil_document) do nothing;

insert into documentos_recibidos_lineas (documento_id, linea_n, item_nombre, glosa, cantidad, precio_unit, subtotal, iva, total, codigo, es_exento)
select id, 1, 'Plan Growth Wasabil', '', 1, 34990, 34990, 6648, 41638, NULL, false
from documentos_recibidos where wasabil_document = 20260800001711
on conflict (documento_id, linea_n) do nothing;
