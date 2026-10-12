# Casa Zaru — SII y Wasabil: dónde está cada cosa

> Mapa de la facturación electrónica. No es una carpeta de trabajo aparte: todo
> esto es parte de la **Gestión** (`index.html` + Supabase `padnttpgzuotxeipjrry`).
> El repo es público: acá no van secretos, URLs de Apps Script ni datos de clientes.

---

## 1. Qué es qué

- **SII** — donde terminan los documentos. Casa Zaru **no le habla directo**: todo
  pasa por Wasabil.
- **Wasabil** — el facturador. API en `https://api.wasabil.com/api`, documentada en
  `app.wasabil.com/api-docs` (es una SPA: se lee con navegador). La cuenta ve
  **una sola empresa** (MUVALE DISEÑO SPA).
- **Gestión** — la pestaña Finanzas emite; `gestion_documentos` guarda el historial.

Códigos que aparecen en todas partes:

| Tipo SII | Documento | | Estado Wasabil (`status_id`) | Significa |
|---|---|---|---|---|
| 33 | Factura | | 2 | Procesando: **el documento ya existe**, falta que el SII conteste |
| 39 | Boleta | | 3 | Emitido y aceptado |
| 61 | Nota de crédito | | 4 | Terminó sin emitirse |
| 46 | Factura de compra | | | |

El 46 lo **emite Casa Zaru** a nombre de un proveedor extranjero (Meta, Google,
Shopify): es gasto, pero no es un documento "recibido".

---

## 2. Los tres circuitos

```
A. VENTAS (emitidos)     Finanzas ─> Edge Function ─> Wasabil ─> SII
                                          └─> PDF a Drive
B. VENTAS WEB            Shopify emite la boleta solo ─> la app la va a buscar
C. COMPRAS (recibidos)   SII ─> Wasabil ─> planilla de gastos diaria
                                       ├─> pestaña Recibidos de la app (piloto)
                                       └─> cierre mensual
```

**A. Emitidos.** Botón de Finanzas, dos documentos por pedido: **Doc 1 = abono**,
**Doc 2 = saldo**. Detalle en la sección 4.

**B. Boletas de Shopify.** Shopify boletea **cada orden pagada** (integración propia
de Wasabil) y deja el número de orden en `invoice_reference`. `traerBoletasWeb()`
las busca (acción `buscar_web`, solo lectura, exige sesión de admin), las pega a la
venta y avisa las que no calzan con ninguna. Ojo: una orden creada solo para sacar
una etiqueta de envío **también boletea**.

**C. Recibidos.** Wasabil sincroniza desde el SII lo que los proveedores le emiten a
la empresa. De ahí salen tres cosas independientes:

1. La **planilla de gastos** (privada), que una tarea diaria alimenta y clasifica.
2. La pestaña **Recibidos** de la app (`documentos_recibidos` + `_lineas`): cola de
   líneas por clasificar. Hoy solo tiene el piloto de agosto 2026, cargado a mano.
3. El **cierre mensual**, que baja de Wasabil las emitidas y el resumen por tipo.

---

## 3. Dónde vive cada pieza

### En este repo

| Pieza | Dónde |
|---|---|
| Edge Function puente (acciones: emitir, `check`, `buscar_web`) | `supabase/functions/smart-action-a-wasabil-emitir/index.ts` |
| Historia de los PDFs "en blanco" y su arreglo | `supabase/functions/smart-action-a-wasabil-emitir.FIX.md` |
| Emisión en la app | `index.html` → `prepararDocumento`, `toggleFinDoc`, `_tomarCandadoDocumento` / `_cerrarCandadoDocumento` / `_soltarCandadoDocumento` |
| Documentos que quedaron en cola | `verificarFinDoc`, `_consultarEstadoDoc`, `_seguirEmisionEnCola`, `_barrerEmisionesEnCola` |
| Anular / marcar a mano | `anularDocumento`, `marcarFinDocManual` |
| Boletas de Shopify | `traerBoletasWeb`, `_pegarBoletaWeb`, `renderAvisoBoletasWeb` |
| Historial por cliente | `loadDocumentos`, `documentosDeCliente` |
| Pestaña Recibidos | `renderRecibidos`, vista `v_documentos_recibidos_pendientes` |
| Límites para emitir y para notas de crédito | `.claude/skills/conciliacion/SKILL.md` → "Límites" |
| Qué bajar de Wasabil para el cierre | `.claude/skills/cierre-mensual/SKILL.md` → sección 2 |

Buscar las funciones por nombre: los números de línea de `index.html` se corren.

Migraciones (todas del proyecto de Gestión):

| N° | Qué hizo |
|---|---|
| `0007` / `0009` | Intento de traer a la base los documentos **emitidos** como transitorios, y su reversa. No queda nada vivo. |
| `0010` | `documentos_recibidos` y `documentos_recibidos_lineas` (staging de compras) |
| `0011` | Carga piloto: recibidos de agosto 2026 |
| `0012` | `gestion_documentos`: historial + candado antiduplicado |
| `0014` | Relleno de `gestion_documentos` con lo emitido en septiembre |
| `0015` | Columna `producto` en `gestion_documentos` |
| `0016` | Reclasificar líneas de Recibidos (unidad, snapshot del original, quién corrigió) |

### Fuera del repo (privado, a propósito)

| Pieza | Dónde |
|---|---|
| Planilla de gastos, reglas de cierre, alias de proveedores | `C:\Users\dell\Casa Zaru Planillas\` |
| Apps Script del receptor de gastos (código y config con URL + token) | misma carpeta: `apps-script-gastos-wasabil.gs`, `receptor-gastos-config.txt` |
| Carga de cartolas y cruce banco ↔ factura | misma carpeta: `cargar-cartolas.ps1`, `lib-xls.ps1` |
| Archivos del cierre (`emitidas-AAAA-MM.csv`, `sii-AAAA-MM.json`) | `C:\Users\dell\.casazaru\` |
| Respaldos del Apps Script que sube PDFs a Drive | `C:\Users\dell\.casazaru\respaldos\` |
| PDFs de boletas y facturas emitidas | Drive → `Casa Zaru\Boletas y Facturas - Ventas 2026` |
| Sheet mensual de gastos | Drive → "Gastos [Mes] Wasabil Oficiales" |
| Token de Wasabil y secretos de la subida a Drive | Secretos de la Edge Function: `WASABIL_API_TOKEN`, `DRIVE_UPLOAD_URL`, `DRIVE_UPLOAD_SECRET` |
| Tarea diaria `reporte-gastos-wasabil` (~8:00, solo con la app de Claude abierta) | `C:\Users\dell\.claude\scheduled-tasks\reporte-gastos-wasabil\` |
| Conector de Wasabil en Claude (consultas; también puede emitir) | Conectores de la cuenta de Claude |

---

## 4. Cómo se emite un documento, paso a paso

1. **Preparar.** Finanzas muestra monto, glosa y producto para revisarlos. Preparar
   no emite nada.
2. **Releer el servidor.** Si no se puede confirmar el estado real del pedido, no
   se emite.
3. **Validar datos.** Factura exige RUT válido, razón social, giro, dirección,
   comuna y ciudad.
4. **Confirmación final** en pantalla.
5. Se marca `docN_procesando` en Finanzas y se guarda.
6. **Se toma el candado**: se inserta la fila en `gestion_documentos`. El índice
   único `(num, doc_num) where not anulada` vive en Postgres.
   - Ya existe → no se emite.
   - No se pudo insertar → no se emite.
7. Recién ahí se llama a la Edge Function, que crea el documento en Wasabil
   (`POST /documents`, precio con IVA incluido).
8. La función espera hasta ~16 s la respuesta del SII.

Las cuatro salidas se tratan distinto, y esa diferencia es el corazón del sistema:

| Qué pasó | Qué hace la app |
|---|---|
| **Emitido** | Guarda folio y PDF, completa la fila, sube el PDF a Drive |
| **En cola** (el SII tarda) | El candado **se queda**. Reconsulta sola a los 20, 40, 60, 120, 300 y 600 s, y otra vez cada vez que se abre Finanzas |
| **Wasabil dice que no creó nada** | Suelta el candado |
| **Se cortó la red** | El candado **se queda**: no se sabe si el documento existe. Revisar en Wasabil antes de tocar nada |

El PDF queda en Drive como `<pedido>. <cliente> - <glosa> - Folio <n>.pdf`. El folio
en el nombre no es adorno: sin él, abono y saldo chocaban y el PDF se corrompía.

**Anular.** La nota de crédito se emite **en Wasabil**. El enlace "anular" de la app
solo registra el folio de la NC y libera el cupo para volver a emitir.

---

## 5. Reglas que no se rompen

- **Nunca probar emitiendo.** El botón manda documentos reales al SII y cada prueba
  quema un folio. Cada tramo se prueba solo:
  - Subida a Drive: POST directo al Apps Script con un PDF mínimo.
  - Estado de un documento: acción `check` con un `uuid` que ya existe. Consulta y
    sube el PDF; nunca crea.
- **Primero el candado, después la emisión.** Si no se puede registrar el
  documento, no se emite.
- **Ante un corte, no reintentar a ciegas.** Mirar si el pedido quedó con
  `docN_procesando` o con fila en `gestion_documentos`. Sin candado, Wasabil nunca
  se llamó y es seguro reintentar.
- **Columnas nuevas en `gestion_documentos`: la migración va ANTES del push.** Si el
  insert falla por columna inexistente, el candado bloquea todas las emisiones.
- **Notas de crédito**: solo con un sí explícito para esa nota.
- **Datos de clientes** (nombres, RUT, correos, montos) nunca en archivos del repo.
- Wasabil emite con `send_email: false`: **al cliente no le llega el documento**,
  hay que mandárselo.

---

## 6. Trampas conocidas

**API de Wasabil**

- La URL del PDF cambia de nombre según el endpoint: `document_pdf_url` al crear,
  `public_pdf_url` / `pdf_url` al consultar el estado. Aceptar las tres.
- Listar documentos es `POST /documents/query` con los filtros en el cuerpo.
  `GET /documents` da 405. El `search` acepta prefijos `ref:`, `folio:`, `receptor:`.
- Emitido o recibido lo decide el booleano `received`, **no** el tipo SII: un mismo
  tipo aparece en los dos lados.
- Montos: usar los campos `sent_*` (pesos enteros). Para cifras contables, el
  **total del documento**, nunca la suma de sus líneas.

**Conector de Wasabil en Claude**

- Llamadas **de a una**. En paralelo se cae la sesión, y aun de a una suele fallar
  una o dos veces: reintentar igual.
- `report_document_details` se cae si se agrupa por `sii_document_type_id`. El tipo
  se saca aparte con `report_documents`.

**SII**

- El registro de compras del SII **no trae glosa**: solo encabezado. El detalle vive
  en el DTE que manda el proveedor. Las boletas que llegan por sincronización
  aparecen como "Detalle no disponible".
- Las facturas tardías aparecen en Wasabil **9 a 11 días** después de su fecha. Por
  eso la tarea diaria mira 15 días atrás, y al cerrar el mes hay que comparar
  Wasabil completo contra la planilla.
- El SII a veces tarda más de un minuto en aceptar. Ver "En cola" en la sección 4.

**Apps Script** (hay dos: el que sube los PDFs a Drive y el receptor de gastos)

- Editar el código no actualiza la URL `/exec`: hay que publicar una **versión
  nueva** sobre la misma implementación.
- `/exec` responde con una redirección. En el receptor de gastos,
  `Invoke-RestMethod` la sigue mal y da 404 aunque el envío sí se haya hecho: usar
  `curl.exe -L` y no reintentar a ciegas.

**Datos**

- `doc1_num` / `doc2_num` de Finanzas se usaron meses como bloc de notas ("NO",
  "canje", "retira"). Para folios, la fuente es Wasabil o `gestion_documentos`.
- En `gestion_documentos`, `num` puede ser nulo: las ventas de plataforma no tienen
  pedido y se pegan al cliente por RUT o correo.

**Desplegar la Edge Function** — se hace desde el panel de Supabase (proyecto de
Gestión → Edge Functions → Code → Deploy). El nombre `smart-action-a-…` salió de un
error al crearla; la URL es lo que importa, no renombrar.

---

## 7. Qué falta

- **Recibidos**: clasificar cada línea como INVENTARIO o GASTO y volcarla a
  `factura_lineas`. Hoy la pestaña solo corrige glosa, cantidad, unidad y precio.
- **Recibidos**: no hay importador. El piloto de agosto se cargó a mano y la carga
  histórica (~1.400 documentos) está sin decidir.
- **Emisión**: la app manda un `idempotency_key` que la función todavía no usa.
