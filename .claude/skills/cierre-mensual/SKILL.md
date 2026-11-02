---
name: cierre-mensual
description: Cierre mensual y semanal de Casa Zaru con números de gerente de finanzas — libro Excel de 19 hojas (resumen con semáforo, cuadre semanal con cada pago justificado, historial mes a mes, madera, Starken, gastos fijos, caja, ventas, por cobrar y pagar, sueldos, bencina, marketing y CAC, ferias, cotizador, facturas recibidas y emitidas, IVA, deudas) y el tablero HTML + PDF en Drive. Actívala cuando el usuario pida "cierre mensual", "cierre de <mes>", "cierre de la semana", "cuadre semanal", "qué gastos faltan justificar", "libro del mes", "tablero", "estado de resultados", "cuánto ganamos/perdimos", "en qué estamos fallando" o "el Excel del cierre".
---

# Cierre mensual — libro Excel y tablero

**Método (acordado el 15 y 17-10-2026), en tres niveles:**
1. **Solo, todos los días:** Gestión (respaldo 03:00), facturas de Wasabil (tarea 08:03) y cotizador.
2. **Lunes 10:15, tarea "CasaZaru - Tablero Semanal"** (`correr-tablero.ps1` → `libro-mensual.ps1` del mes en
   curso): el usuario baja antes a Descargas la cartola BCI completa, la de Banco de Chile y el reporte de
   liquidaciones de Mercado Pago (`settlement_v2-*.xlsx`); el script elige la cartola que mejor cubre el mes, clasifica
   con `reglas-cierre.csv`, manda lo menor a $20.000 a "Otros gastos", y deja en Drive el libro del mes,
   `Tablero Casa Zaru.html` y `Tablero Casa Zaru.pdf` (el PDF es el que se abre desde el enlace de Drive y en el
   celular: Drive muestra el HTML como código). Claude corre la conciliación (skill `conciliacion`) y deja máximo 3
   preguntas con respuesta propuesta. Cada respuesta se convierte en regla para que no vuelva a preguntarse.
   **El cuadre semanal es la hoja Semanas del libro** (desde el 22-10): cada peso que salió de BCI, Banco de Chile y la
   tarjeta de Mercado Pago, por semana de lunes a domingo, con su justificación (factura N°, regla, traspaso, menor a
   $20.000). Lo único que pide acción es lo que dice SIN JUSTIFICAR; eso mismo sale en el tablero (bloque de la última
   semana completa) y en "Qué falta para cerrar el mes". No se arma con scripts sueltos.
3. **Día 2, tarea "CasaZaru - Cierre Mensual Gestion"** (`correr-cierre.ps1`): PDF + libro + tablero del mes cerrado.
   Al usuario se le dan tres cifras: resultado, caja y por cobrar.

**Para bancos o inversionistas:** hoja Resumen (números, semáforo, estado de resultados) + hoja Historial (mes a mes,
se acumula sola en `Casa Zaru Planillas\historial-mensual.csv`) + el tablero. La hoja Sueldos es confidencial: sacarla.
**Qué está fallando:** el semáforo del Resumen y del tablero, con umbrales en `Casa Zaru Planillas\metas.csv`
(meta de venta, margen mínimo, publicidad máxima, por cobrar máximo, meses de caja).

**El Excel no se rellena a mano** (se regenera solo y se perdería): lo que el usuario decide va a los archivos privados
de `Casa Zaru Planillas`: `reglas-cierre.csv` (clasificación), `ferias.csv`, `creditos.csv`, `por-pagar-manual.csv`,
`metas.csv`. Claude los edita con la respuesta del usuario (manteniendo la marca UTF-8).

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
  `{mes, gasto, fuente}` (+ `confirmado` cuando el usuario ya eligió el reporte por sobre lo pagado con las
  tarjetas: apaga ese aviso). Las facturas de Meta en Wasabil cubren solo una parte: no usarlas como gasto.
  **La tarjeta prepago de Mercado Pago paga Facebook, Claude, Manychat, bencina, cursos y compras en Mercado
  Libre** (19-10). Las liquidaciones no traen el nombre del comercio; el CSV del estado de cuenta sí, desde
  oct-2026 (columna `STORE_NAME`, vacía en compras de Mercado Libre). Los nombres van a `~/.casazaru/mp-nombres.csv`
  (Fecha;Monto;Nombre;Fuente), escribiendo «Facebook» para los «Facebk *…»; si faltan, pedir capturas de la
  actividad en la web de Mercado Pago. Con eso el script clasifica cada pago con las reglas y toma Facebook como
  gasto real de Meta si falta el json. Sin nombre, el pago queda en una bolsa y sale un aviso.
  Si el botón «Abrir» del estado no deja archivo (Chrome bloquea descargas seguidas), abrir con navigate la URL
  `/balance/reports/account_status/statements/<uuid>/download?format=csv` que muestra read_network_requests.
- **Liquidaciones de Mercado Pago**: el script las lee directo de Descargas (`settlement_v2-1038334230-*`, xlsx o
  csv; ese número es la cuenta de Casa Zaru, hay settlements de otros negocios). Ya no hace falta `mp-AAAA-MM-canal.csv`.
- **Ajustes manuales** (`ajustes.csv`: Fecha;Concepto;Monto;Categoria;Nota) para decisiones del usuario que no
  están en ningún sistema; entran al resultado y se listan en el Resumen. Dejarlo vacío si no hay.
- **Reporte de liquidaciones de Mercado Pago** (`settlement_v2-*.xlsx`, trae el canal de cada cobro:
  Point, Link de Pago, Checkout Pro, Mercado Libre) → `mp-AAAA-MM-canal.csv` (`id;plataforma`).
  Sin él, las ventas de feria se separan por la comisión. Ojo: hay `settlement_v2` de otros negocios en
  Descargas; usar solo el que el usuario diga que es de Casa Zaru.
- **Tarjeta Visa Empresa 8340 de Banco de Chile** (desde el 19-10 paga Google Ads, Meta y el F29): Banco de Chile →
  Tarjetas → movimientos. Para cerrar el mes hacen falta los dos export en Descargas: `MovimientosFacturados.xls` (el
  estado de cuenta, que cierra cerca del 28) y `MovimientosNoFacturados.xls` bajado después del fin de mes (lo cargado
  entre el cierre del estado y el 31). Desde el 01-11 el cargador lee los dos formatos: una compra que sale en ambos se
  cuenta una vez por fecha y monto, y una reversa anula su cargo. Solo el facturado trae los cargos propios de la
  tarjeta (intereses, comisiones, impuesto DL 3475), que van a Comisiones bancarias por `reglas-cierre.csv`; la
  comisión de administración mensual calza con la factura exenta de Banco de Chile y no se cuenta dos veces. Un
  export en dólares no se lee. Reglas: FACEBK = Publicidad Meta (suma al gasto real de Meta si falta
  `meta-AAAA-MM.json`), GOOGLE ADS = pago de factura ya contada, SII RECAUDAC (SII 11001 en el facturado) = impuestos.
  Cada cobro de Meta a la Visa trae aparte una comisión de compra internacional del 2,54 % (octubre 2026).
  El pago de la tarjeta, cuando llegue, es traspaso. Ojo: lo pagado a Facebook trae IVA; el reporte de Meta no.
- **Banco de Chile tiene dos cuentas**: la FAN Emprende 75243-30 (caja chica del taller, la que usa el libro) y la
  cuenta corriente 42159-00 (Profit First / SII, al 19-10 solo traspasos de entrada). Si la cartola no alcanza y la
  sesión del banco está abierta, los movimientos se leen en la web (solo lectura) y van a
  `~/.casazaru/movs-extra-AAAA-MM.csv` (Fecha;Cuenta;Glosa;Cargo;Abono;Saldo;Canal;Fuente). Solo cuentan los posteriores
  a la última fecha de la cartola, así que bajar después una cartola nueva no duplica nada. La sesión se corta sola al
  cambiar de cuenta: no volver a ingresar con clave, pedir la cartola.
- **Capturas de Mercado Pago posteriores a la última liquidación**: sus pagos entran igual como salidas de la tarjeta
  (con aviso), y alargan la fecha hasta la que la semana se da por cubierta.
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
- Una factura justifica un solo pago: si dos cargos calzan "≈" con el mismo folio (dos cargas de bencina y una sola
  factura), el segundo vuelve a ser pago sin factura y se clasifica por regla. Un pago cuya glosa dice "factura <mes>"
  sin número ("Pago final factura agosto", Renatte) también es pago de factura ya contada.
- Hojas, en este orden: Resumen, Semanas (cuadre semanal), Historial, Madera (por proveedor), Starken (cobrado vs
  todos los fletes), Gastos fijos (con la venta necesaria para cubrirlos), Caja, Ventas, Por cobrar y pagar, Sueldos
  (confidencial), Bencina, Marketing y CAC, Pasarelas, Ferias, Cotizador, Facturas recibidas y emitidas, IVA, Deudas.
- Hoja Pasarelas (desde el 01-11-2026): % que se lleva Venti, Flow y Mercado Pago por pedido (Gestión: `pasarela`,
  `costo_mp`, `costo_shopify`, con IVA) y la factura de comisión del mes al lado. Venti y Flow facturan a fin de mes lo
  del mes, así que se cuadran con Gestión; Mercado Pago no (factura el día 1 y junta Point y Mercado Libre). Las tarifas
  vigentes salen de `Casa Zaru Planillas\tarifas-pasarelas.csv`: actualizarlo si cambian, no el script. Venti cobra
  2,75 % + IVA en crédito, pero 4,74 % si el cliente usa las 3 cuotas sin interés (activadas en su panel).
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

## Planillas «por mes» (desde el 31-10-2026)

Cinco libros con la misma estructura — **Resumen + una hoja por mes**, filas marcadas en rojo sobre crema — que el
día 2 regenera `correr-cierre.ps1` vía `.claude/informes/por-mes/todas.ps1` (también a mano: `todas.ps1 -Anio 2026`).
Salen a `Casa Zaru Planillas\<nombre> AAAA por mes.xlsx` y se copian a `G:\Mi unidad\Casa Zaru\Finanzas\`.

| Libro | Fila = | Rojo = | Fuente que hay que mantener |
|---|---|---|---|
| Compras madera | una compra | sin factura | `Casa Zaru Planillas\Compras madera AAAA - cruce.csv` (lo arma el cruce a mano: Wasabil + bancos + chat del taller) |
| Starken | una OF del portal | OF sin pedido | `Casa Zaru Planillas\por-mes\starken\` (exports del portal, `map_ano.csv`, `fin_all.csv`, `facturas-starken.csv`) |
| Sueldos | un pago BCI al equipo o Previred | glosa que no dice sueldo | `$EQUIPO` en `Casa Zaru Planillas\por-mes\config.ps1` (RUT → nombre) |
| Bencina | una carga | sin factura | cartolas en Descargas + `~/.casazaru/mp-AAAA-MM.csv` y `mp-nombres.csv` |
| Publicidad | un cobro de Meta o Google | cobro de Meta sin factura | `Casa Zaru Planillas\por-mes\wasabil-pub.csv` (facturas de Meta y Google bajadas de Wasabil) + la planilla de gastos |

Reglas: el motor Excel es `engine.ps1` (copia del de `libro-mensual.ps1` + estilo 16 «pesos en rojo»); todo lo privado
(RUT, nombres, carpetas de datos) va en `config.ps1`, **fuera del repo**. `fuentes.ps1` une todas las cartolas de
Descargas en un caché (`%LOCALAPPDATA%\CasaZaru\por-mes`) que se rehace solo cuando aparece una cartola nueva. El primer
semestre sale de `Gastos 1er Semestre AAAA Clasificado.xlsx` (ya clasificado); de ahí en adelante, de cartolas y tarjetas.
Si el usuario edita un libro en Google Sheets, la siguiente corrida lo pisa: lo que haya que corregir va en la fuente.
