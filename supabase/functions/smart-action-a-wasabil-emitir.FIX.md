# PDFs "en blanco" en Drive — diagnóstico y arreglo (APLICADO 28-08-2026)

**Síntoma**: boletas/facturas llegaban a Drive corruptas — PDFs de ~356 KB
(los sanos ~200 KB) llenos de `EF BF BD` (U+FFFD): binario pasado por una
decodificación de texto. Irreversible. Afectó a los pedidos 1515, 1516,
1525, 1526 y 1535.

**Causa REAL** (la primera hipótesis culpaba al download de la Edge Function
y el código la refutó — `subirADrive` siempre usó `arrayBuffer()` y estaba
sano): el nombre del archivo no llevaba folio, así que el **segundo documento
de un mismo pedido** (abono y saldo, o una factura re-emitida) repetía el
nombre del primero. El Apps Script de Drive, al encontrar que el archivo ya
existía, tomaba su rama de "actualizar existente", **que escribe como texto**
— y ahí se destruían los bytes. Todos los corruptos eran colisiones de
nombre; todos los sanos eran nombres nuevos.

**Arreglo aplicado** (desplegado por el usuario el 28-08-2026): la función
agrega `- Folio NNNN` al nombre en los dos caminos (creación y check), con el
helper `nombreArchivo()`. Nombres únicos por documento → la rama enferma del
Apps Script no vuelve a ejecutarse.

**Cómo se ve que funciona**: la próxima emisión aparece en Drive como
`"1550. Cliente - Abono - Folio 7241.pdf"`. Chequeo de corrupción sin abrir:
`head -c 40 archivo.pdf | od -An -tx1 | grep efbfbd` → vacío = sano.

**Segunda capa APLICADA (31-08-2026)**: la rama de "archivo existe" del Apps
Script (proyecto "Proyecto sin título", cuenta hola@casazaru.cl) se corrigió
—bota el archivo viejo con `setTrashed` y crea uno nuevo con `createFile(blob)`,
nunca más `setContent` de texto— y se desplegó como **Versión 3** sobre la
misma implementación activa (la URL /exec no cambió; "Wasabil" y el "Sin
título" viejo son implementaciones archivadas, no se tocaron). Verificado de
punta a punta subiendo un PDF DOS VECES con el mismo nombre por el /exec real:
la segunda subida devolvió un fileId distinto (prueba de que corre la versión
nueva) y el archivo en Drive quedó byte a byte idéntico al original. Respaldos
del codigo original y el corregido en C:/Users/dell/.casazaru/respaldos/.

**Los 5 corruptos de agosto ya fueron reparados** re-bajando los 9 documentos
desde Wasabil (los `document_pdf_url` se descargan sin auth) y reescribiendo
`G:\Mi unidad\Casa Zaru\Boletas y Facturas - Ventas 2026`.
