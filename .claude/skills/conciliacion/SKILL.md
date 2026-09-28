---
name: conciliacion
description: Conciliación semanal de pagos de Casa Zaru (app de Gestión) — cruza la cartola BCI 7175 y Mercado Pago contra los abonos marcados en Finanzas y los documentos emitidos, y devuelve qué pagos marcar, qué boletas/facturas emitir, qué saldos cobrar y qué plata entró sin dueño; además totales aparte de Point (ferias) y Mercado Libre. Actívala cuando el usuario pida "conciliación", "/conciliacion", "cruzar pagos", "qué pagos faltan marcar", "qué boletas faltan emitir", "estar al día con finanzas" o pase una cartola BCI / export de Mercado Pago.
---

# Conciliación semanal — pagos vs Finanzas vs documentos

Solo **Gestión** (proyecto Supabase `padnttpgzuotxeipjrry`). No mezclar con el Cotizador.

Resultado: cuatro tablas cortas que el usuario usa para marcar en Finanzas y
emitir desde el panel. **Esta skill no escribe en Finanzas ni emite nada por su
cuenta** — ver "Límites".

## 0. Insumos

| Qué | De dónde | Notas |
|---|---|---|
| Cartola BCI cuenta 7175 (Muvale Diseño SpA) | `Descargas\*Movimientos_Detallado_Cuenta_7175*.xlsx` | la trae el usuario; si no está, pedirla |
| Mercado Pago | export de actividad (csv/xlsx) o pantallazos | ver 0.1 |
| Finanzas | en vivo desde Chrome (preferido) o respaldo de Drive | ver 0.2 |
| Documentos emitidos | los campos `doc1_*`/`doc2_*` de Finanzas | Wasabil MCP solo para mirar un documento puntual |

⚠️ En Descargas hay archivos de **otros negocios del usuario** (Chilenidad,
Puerto Octay, Gastronómica Valenzuela, Chile Lindo, `mercadopago_settlement*.csv`,
`settlement_v2-*.csv`). **No usarlos** salvo que el usuario diga que son de Casa Zaru.

### 0.1 Mercado Pago → `mp.csv`
Formato que espera `cruzar.ps1`: `fecha,monto,quien,comentario,tipo`, con
`tipo` = `link` (cobro con link, "Venta – Nombre – 70% abono") · `web`
("Compra en Casa Zaru" = checkout Shopify) · `point` ("Venta con Point Smart 2"
= feria) · `ml` ("Venta en Mercado Libre") · `otro`.
- **No** incluir: rechazados, "Acreditación Dinero Plus" (es un crédito), los
  Point de $100 (pruebas — mencionarlos aparte).
- Si vienen pantallazos: transcribir, luego **releer cada imagen contra el csv**
  antes de seguir, y deduplicar las filas que se repiten entre pantallazos
  (mismo n° de operación). Decir hasta qué fecha cubren y si hay huecos entre
  pantallazos.

### 0.2 Finanzas
**En vivo (preferido):** sesión del usuario en Chrome (`mcp__claude-in-chrome__*`,
leer la skill `chrome-browser`). Pestaña nueva en `https://casazar.github.io/Casa-Zaru/`,
esperar ~4 s, y leer `finRecords` en **solo lectura** (no llamar a nada que
guarde). Gotchas del extractor:
- La salida se **corta** pasado cierto largo → leer por tramos de pedidos.
- Si la salida tiene cosas como `a2=123` o `&`, se **bloquea** ("Cookie/query
  string data") → usar `:` o espacios, nunca `=`.
- Cerrar la pestaña al terminar.

```js
await new Promise(r=>setTimeout(r,4000));
finRecords.filter(r=>Number(r.num)>=DESDE&&Number(r.num)<HASTA).sort((a,b)=>a.num-b.num)
 .map(r=>[r.num,(r.nombre||'')+' '+(r.apellido||''),r.tipo||'',r.canal_pago||'',Number(r.total)||0,
   Number(r.abono1)||0,Number(r.abono2)||0,Number(r.abono3)||0,saldoFin(r),Number(r.val_envio)||0,
   r.doc1_emitida?r.doc1_num:(r.doc1_procesando?'PROC':'-'),r.doc2_emitida?r.doc2_num:(r.doc2_procesando?'PROC':'-'),
   r.doc1_tipo||''].join(' | ')).join('\n')
```

**Respaldo (si no hay Chrome):** `scripts/leer-finanzas-respaldo.ps1` lee el
último `respaldo-gestion-*.json` de Drive (corre 03:00). Decir siempre la hora
del respaldo: lo marcado después no aparece.

## 1. Correr los scripts

Todo en el scratchpad de la sesión, nunca en el repo:

```powershell
$sk = "C:\Users\dell\Casa Zaru - Claude\.claude\skills\conciliacion\scripts"
& "$sk\leer-cartola-bci.ps1" -Salida "$tmp\bci.csv"            # toma la cartola más nueva de Descargas
& "$sk\leer-finanzas-respaldo.ps1" -Salida "$tmp\app.csv"       # o armar app.csv desde la lectura en vivo
& "$sk\cruzar.ps1" -Bci "$tmp\bci.csv" -Finanzas "$tmp\app.csv" -Mp "$tmp\mp.csv" -Salida "$tmp\cruce.csv" -Desde <fecha>
```

`cruzar.ps1` **propone** candidatos por monto (abono ya marcado, saldo, 70 %,
30 %), RUT y nombre. La asignación final la decide Claude con las reglas de abajo.
`-Desde`: el día siguiente a la última conciliación (o 1 del mes anterior la
primera vez). Aun así revisar los pedidos con saldo de semanas anteriores.

## 2. Reglas de cruce (aprendidas, no adivinar)

> El repo es **público**: acá no van nombres de clientes ni montos reales. Los
> casos concretos viven en la memoria local (`reference_conciliacion_pagos.md`).

- **No son ventas:** transferencias desde la otra cuenta de Muvale, desde las
  cuentas personales del dueño, `GETNET` $10, "Transferencia interna". El script
  las marca como internas; los nombres personales se leen de
  `%USERPROFILE%\.claude\conciliacion-excluir.txt` (local, fuera del repo).
- **Flow** deposita el **96,204 %** de lo cobrado (medido dos veces). Un depósito
  de Flow puede **juntar varios pagos** de distintos pedidos. En la app se marca
  el **bruto**, no el depósito.
- **Venti Pay:** tasa todavía no medida. Si se confirma un caso, anotarla acá.
- **Pagan terceros:** empresas, fundaciones o familiares pagan por el cliente, y
  el nombre de la transferencia no se parece al del pedido. Buscar por **monto y
  RUT de facturación** (el pedido guarda el RUT de quien factura), no solo por el
  nombre del cliente.
- **Transferencias partidas:** el cliente divide un pago (una transferencia chica
  de prueba y luego el resto; o el 70 % en dos partes). Probar **sumas** de pagos
  del mismo pagador contra 70 %, 30 %, saldo y abonos antes de declarar algo
  "sin dueño" — y revisar que la app no haya registrado solo la primera parte.
- **Nombres ambiguos:** un solo nombre en común ("Juan", "Cristóbal") no alcanza.
  Seguro = mismo RUT o nombre + apellido; probable = monto exacto y otro pagador.
  Deducido = inferencia (ej. dentro de un depósito de Flow) — **decirlo así**.
- **Pagos de más/menos chicos** (unos cientos o miles de pesos): reportar, no
  "arreglar" el total.
- **Campos mal usados:** un pago escrito en *Envío* en vez de en un abono infla el
  total y crea un saldo fantasma. Si el total de un pedido cambió desde la última
  conciliación, revisar `val_envio`.
- La cartola cubre solo esta cuenta BCI. Pagos a la otra cuenta de Muvale no se
  ven: no afirmar que alguien "no pagó", decir "no encontré el pago".

## 3. Documentos (boletas/facturas)

Cada pedido tiene **dos** documentos. El panel sugiere el monto con
`_montoSugeridoDoc` (index.html): **doc 1 = abono1**; **doc 2 = abono2 + abono3**
(o total − abono1 si no hay pagos después). Por eso, al proponer cómo marcar:
- Lo que cubre el doc 1 va **sumado en abono1** (si el 70 % llegó en dos
  transferencias, abono1 = la suma).
- Lo que cubre el doc 2 va en abono2/abono3. Un saldo en dos partes: una en
  abono2 y la otra en abono3.
- Si un pedido ya tiene doc 1 emitido y entra un pago que el doc 1 no cubrió, no
  hay doc 3: se factura dentro del doc 2.

Tipo de documento: el de `doc1_tipo` del pedido (FACTURA si tiene razón social/
giro). Ventas web (`canal_pago` con SHOPIFY) → la boleta la emite Shopify
("Integración"), no la app: no listarlas como pendientes.

Pendiente de emitir = pago marcado (o por marcar) cuyo documento no está emitido.
Documento emitido **sin pago visible** → reportarlo aparte.

## 4. Salida

Números **siempre del script o de un cálculo** (PowerShell), nunca de cabeza.
Formato, en este orden y corto:

1. **Cobertura** — cartola desde/hasta, MP desde/hasta (y si son pantallazos),
   Finanzas en vivo o respaldo de las HH:MM.
2. **Pagos por marcar** — `Pedido | Cliente | Pago (fecha, fuente) | Cómo dejarlo
   en Finanzas (abonoN = $X) | Saldo nuevo`, con ⚠️ donde hay que reordenar
   abonos (sección 3). Total al pie.
3. **Abonos marcados con otro monto** — `Dice Finanzas | Entró | Corregir`.
4. **Documentos por emitir** — `Pedido | Cliente | Doc 1/2 | Tipo | Monto | Ojo`.
   Totales de boletas y facturas por separado.
5. **Saldos sin pago visible** — ordenados por semana de despacho (los ya
   despachados primero). Total.
6. **Plata sin dueño** — ingresos sin candidato claro.
7. **Aparte:** total Point (feria) por día y total Mercado Libre. Recordar
   preguntar si esas ventas tienen boleta.

Guardar el resumen de la semana en la memoria del proyecto solo si aparece una
regla nueva (pagador nuevo, tasa de pasarela, etc.) — no el detalle.

## 5. Después de que el usuario marque

Si pide revisar: releer Finanzas **en vivo** y comparar pedido por pedido contra
lo propuesto (suma de abonos = pagado visto; abonos en el casillero correcto).
Reportar solo lo que no calza.

## Límites (no negociables)

- **No escribir en Finanzas** salvo pedido explícito del usuario para esos pedidos
  puntuales. Si lo pide: releer cada registro del servidor (`_releerFinanzas`),
  verificar que sigue como se revisó, cambiar solo esos campos, guardar con
  `_guardarFinanzasFirme`, dejar nota con `logHistorial` y releer para confirmar.
- **Nunca emitir** boletas/facturas: las emite el usuario desde el panel. El botón
  de Finanzas manda documentos REALES al SII.
- **Notas de crédito** por el MCP de Wasabil: solo con un "sí" explícito para esa
  nota, con `idempotencyKey` estable (`nc-<folio>-pedido-<num>`), y sin llamadas
  en paralelo al MCP (se cae). Suele quedar "Procesando" unos minutos: consultar
  con `get_documents` (`search: id:<document>`), nunca reintentar la creación.
- **Datos de clientes** (nombres, montos, RUT) solo en el scratchpad o en la
  respuesta al usuario — nunca en archivos del repo, que es público.
