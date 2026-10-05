---
name: cierre-mensual
description: Cierre mensual de Casa Zaru con números de gerente de finanzas — arma el libro Excel de 14 hojas (resumen y estado de resultados, caja, ventas, por cobrar y pagar, madera, bencina, sueldos y fijos, marketing y CAC, ferias, cotizador, facturas recibidas y emitidas, IVA, deudas). Actívala cuando el usuario pida "cierre mensual", "cierre de <mes>", "libro del mes", "estado de resultados", "cuánto ganamos/perdimos" o "el Excel del cierre".
---

# Cierre mensual — libro Excel

Genera `G:\Mi unidad\Casa Zaru\Informes Gestion\Libro mensual Casa Zaru AAAA-MM.xlsx` con
`.claude/informes/libro-mensual.ps1 -Mes AAAA-MM`. El script no clasifica por su cuenta: usa la
planilla de gastos Wasabil (categorías oficiales) y `reglas-cierre.csv`. **No armar mapas de
proveedores aparte** (ya pasó una vez y hubo que borrarlo).

## 1. Pedir al usuario lo que solo él puede bajar
- Cartola **BCI 7175** detallada (`*Movimientos_Detallado_Cuenta_7175*.xlsx`) y **Banco de Chile**
  (`cartola*.xls`) del mes, en Descargas.
- **Mercado Pago**: estado de cuenta del mes. Mejor en Excel/CSV con descripción; si llega en PDF,
  pasarlo a `%USERPROFILE%\.casazaru\mp-AAAA-MM.csv` (separador `;`, columnas
  fecha;hora;mov;tipo;id;monto;otros) y `mp-AAAA-MM.json` (saldo_inicial, saldo_final).
  **Validar**: saldo inicial + movimientos − comisiones = saldo final, y las comisiones = las del PDF.
- **Gasto real de Meta** del mes (reporte mensual de anuncios) → `meta-AAAA-MM.json`
  `{mes, gasto, fuente}`. Las facturas de Meta en Wasabil cubren solo una parte: no usarlas como gasto.

## 2. Bajar de Wasabil (MCP, llamadas de a una, nunca en paralelo)
- `report_documents` emitidos del mes (`received:false`, `trxType:sale`, groupBy
  day, sii_document_type_id, folio, receiver, origin_platform; sum neto/iva/total) →
  `emitidas-AAAA-MM.csv` (fecha;tipo;folio;rut;cliente;plataforma;neto;iva;total).
  **Validar** contra el resumen por tipo del mismo mes antes de seguir.
- Resumen por tipo (trx_type, received, sii_document_type_id) → `sii-AAAA-MM.json`.
- Escribir esos archivos con la herramienta Write, no con PowerShell: el filtro de la terminal
  confunde la palabra "del" (p. ej. "COMERCIALIZADORA DEL PACIFICO") con el comando de borrar.

## 3. Correr y auditar ANTES de mostrar
```
$env:LIBRO_DEBUG = '<scratchpad>\movs.csv'; .\libro-mensual.ps1 -Mes AAAA-MM -Salida <scratchpad>
```
- Revisar POR CLASIFICAR en `movs.csv`. Si un pago del banco se repite cada mes, agregar la regla
  en `C:\Users\dell\Casa Zaru Planillas\reglas-cierre.csv` (Fuente;Patron;Monto;Categoria;...),
  la primera que calza gana. Ojo: los bancos borran las tildes ("Devolucin prstamo").
- Un pago cuya glosa dice "Factura <mes> <n°>" es pago de una factura de otro mes: no es gasto del
  mes (regla "Pago de factura").
- El resultado tiene que cuadrar con sus partes y la caja con los saldos de las cartolas.
  Si el número es extremo, buscar el pago grande mal clasificado antes de decirlo.
- Recién ahí generar en Drive (sin `-Salida`).

## 4. Qué decirle al usuario
Resultado del mes, margen bruto, caja, CAC y los avisos de "Para revisar antes de cerrar"
(boletas repetidas, emisiones sin folio en Gestión, saldos pagados sin marcar, proveedores sin
factura, Mercado Pago sin detalle, IVA de ferias). Todo número sale del script, nunca de cabeza.

## Supuestos del libro (decirlos si preguntan)
- Montos sin IVA. Pago sin factura = costo completo (no hay IVA que recuperar).
- Sueldos: lo pagado en el mes (se pagan a mes vencido, así que en rigor son los del mes anterior).
- Ventas = pedidos de Gestión por fecha de venta + boletas de Mercado Libre + ventas con Point en las
  fechas de cada feria (`ferias.csv`).
- Comisión de César: tramo según valor producto con IVA, % aplicado sobre el valor sin IVA.
- La hoja Sueldos tiene datos por persona: el archivo no se comparte.
