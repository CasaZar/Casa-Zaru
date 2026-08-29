# FIX pendiente: la función corrompe el PDF en el camino de "Verificar estado"

**Síntoma** (28-08-2026): boletas/facturas que llegan a Drive "en blanco".
Son PDFs de ~356 KB (los sanos pesan ~200 KB) llenos de `EF BF BD` — el
carácter U+FFFD. Es la firma de **binario leído como texto**: cada byte
inválido en UTF-8 se reemplaza por "�" y el PDF crece 1,77× y queda
irrecuperable.

**Patrón confirmado**: los 5 corruptos (pedidos 1515, 1516, 1525, 1526, 1535)
son emisiones donde el SII tardó — dos documentos seguidos o confirmación
lenta — y el PDF se subió desde el flujo de **check/estado**, no desde la
creación. El camino de creación sube bien; el de check corrompe.

**Dónde**: Edge Function `smart-action-a-wasabil-emitir` (proyecto
`padnttpgzuotxeipjrry`). En la rama del `action:'check'`, donde baja el PDF
de Wasabil antes de mandarlo en base64 al Apps Script de Drive.

**El bug y su arreglo** (el código exacto vive solo en el panel de Supabase;
este es el patrón a buscar y su reemplazo):

```ts
// MAL — .text() reemplaza los bytes binarios con U+FFFD y el PDF muere
const pdfText = await resp.text();
const pdfBase64 = btoa(unescape(encodeURIComponent(pdfText)));

// BIEN — bytes crudos de punta a punta
const buf = new Uint8Array(await resp.arrayBuffer());
let bin = '';
for (let i = 0; i < buf.length; i += 0x8000) {
  bin += String.fromCharCode(...buf.subarray(i, i + 0x8000));
}
const pdfBase64 = btoa(bin);
```

**Para aplicarlo**: Dashboard de Supabase → Edge Functions →
`smart-action-a-wasabil-emitir` → editar la rama de check → desplegar
**nueva versión** (editar sin desplegar no cambia nada, igual que en el
Apps Script).

**Cómo verificar futuros archivos** (sin abrirlos):
`head -c 40 archivo.pdf | od -An -tx1 | grep efbfbd` → si aparece, corrupto.

**Cómo se repararon los 5 de agosto**: los PDF de Wasabil se bajan sin auth
desde `document_pdf_url` (URL firmada). Se buscó cada documento con el MCP de
Wasabil por nombre del receptor, se bajaron los 9 PDFs (varios pedidos tenían
dos documentos y solo un archivo en Drive) y se reescribieron en
`G:\Mi unidad\Casa Zaru\Boletas y Facturas - Ventas 2026`.
