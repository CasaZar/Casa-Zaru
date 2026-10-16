---
name: cierre-mensual
description: Cierre mensual de Casa Zaru con números de gerente de finanzas — arma el libro Excel de 14 hojas (resumen y estado de resultados, caja, ventas, por cobrar y pagar, madera, bencina, sueldos y fijos, marketing y CAC, ferias, cotizador, facturas recibidas y emitidas, IVA, deudas). Actívala cuando el usuario pida "cierre mensual", "cierre de <mes>", "libro del mes", "estado de resultados", "cuánto ganamos/perdimos" o "el Excel del cierre".
---

# Cierre mensual — libro Excel

> **Desde el 15-10-2026 el cierre se hace de a poco, los lunes**, para que fin de mes no sea un atracón.
> El usuario solo baja la cartola BCI (completa, no "solo ingresos") y el movimiento de Mercado Pago.
> Claude corre la conciliación (skill `conciliacion`) y el libro del mes en curso en el scratchpad,
> clasifica lo obvio sin preguntar (con una regla en `reglas-cierre.csv` para que no vuelva a salir) y
> deja como máximo 3 preguntas, cada una con la respuesta propuesta. Gastos sin identificar bajo
> $20.000 van solos a "Otros gastos". El día 2 se arma el libro con las cuatro semanas ya limpias y al
> usuario se le dan tres cifras: resultado, caja y lo que falta cobrar.

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
- **Reporte de liquidaciones de Mercado Pago** (`settlement_v2-*.xlsx`, trae el canal de cada cobro:
  Point, Link de Pago, Checkout Pro, Mercado Libre) → `mp-AAAA-MM-canal.csv` (`id;plataforma`).
  Sin él, las ventas de feria se separan por la comisión. Ojo: hay `settlement_v2` de otros negocios en
  Descargas; usar solo el que el usuario diga que es de Casa Zaru.
- **Cartolas:** desde el 15-10 el script elige solo, por cuenta, la que tiene más movimientos dentro del
  mes (no la más nueva) y avisa si le faltan días o si no trae egresos. Antes tomaba la más nueva y una
  parcial dio un resultado falso de +$5,0M (06-10).
- **Ferias** (`ferias.csv`): fechas y la columna `Costos` (expresión regular que busca en el proveedor
  y en el detalle) para asignar a cada feria sus costos de la categoría Ferias. Sin ella, si hay dos
  ferias en el mes, los costos quedan "sin asignar".
- Al editar los CSV privados, mantener la marca UTF-8 (BOM): la herramienta de edición a veces la borra.

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
  mes (regla "Pago de factura ya contada"). Lo mismo el cargo de Shopify en la tarjeta: Shopify siempre
  llega con factura de compra.
- El cruce banco-factura marca "≈" cuando solo calzan monto y fecha. El script lo descarta en
  transferencias a personas (quincenas, horas y rendiciones calzaban con fletes de Céspedes) y cuando la
  factura es más de 3 días posterior al pago (un cargo del 28-09 calzaba con una factura del 09-10).
- La hoja Starken compara el envío de los pedidos que SALIERON en el mes con los fletes del mes. Día de salida:
  dia_envio de Seguimiento (se mueve con el cambio de fecha; Producción queda con la original), si no el de
  Producción, si no el lunes de la semana + 7 días. Los estimados con cambio de fecha avisado salen como aviso.
- Hojas, en este orden: Resumen, Madera (por proveedor), Starken (cobrado vs todos los fletes), Gastos
  fijos (con la venta necesaria para cubrirlos), Caja, Ventas, Por cobrar y pagar, Sueldos
  (confidencial), Bencina, Marketing y CAC, Ferias, Cotizador, Facturas recibidas y emitidas, IVA, Deudas.
- Si Gestión cambió después del respaldo de las 03:00, pasar `-Respaldo <copia al día>.json`.
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
