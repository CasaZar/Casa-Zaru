# Comandas → Google Doc «COMANDA PEDIDO»

Apps Script que usa el botón **📝 Cargar al Doc** de Producción (`index.html`, funciones `_cmd*`).
Escribe cada pieza en la pestaña de su **semana de producción** (`o.envio`, nombrada con el lunes). Si la
pestaña no existe, la crea. Se salta las piezas que ya están en **cualquier** pestaña, comparando
pedido + producto + medida, y le dice a la app cuáles están cargadas (la marca «✓ Doc» / «sin Doc»).

Sin secretos: el script corre con la cuenta dueña del Doc y solo atiende a quien manda un JWT válido de
la Gestión. Lo comprueba contra Supabase y además exige un rol en `gestion_usuarios`.

## Instalar (una vez, con la cuenta hola@casazaru.cl)

1. https://script.google.com → **Nuevo proyecto** → nombre «Comandas al Doc».
2. Configuración del proyecto (⚙) → marcar «Mostrar el archivo de manifiesto `appsscript.json`».
3. Pegar `Code.gs` y `appsscript.json` de esta carpeta, reemplazando lo que traen.
4. Configuración del proyecto → **Propiedades del script** → agregar `DOC_ID` =
   - para probar: `1p29DQMgapozlNEz-4QcUxtEvcclTo3fO1e7EUs-dzeQ` (copia «PRUEBA app — COMANDA PEDIDO (borrar)»)
   - en serio: `1ZnfEpcGpWcQ_PFCaFStimGX9r8axj7NHv6MzmdPnbmQ`
5. **Implementar → Nueva implementación** → tipo «Aplicación web» → Ejecutar como **Yo** → Quién tiene
   acceso **Cualquier usuario**. Autorizar los permisos que pide (Docs y conexión externa).
6. Copiar la URL que termina en `/exec` y ponerla en `COMANDAS_URL` de `index.html`.

Para pasar de la copia al Doc real basta cambiar `DOC_ID`. La URL no cambia.
Si se edita `Code.gs`: **Implementar → Gestionar implementaciones → editar → Versión nueva**. Si no se
hace, sigue corriendo la versión anterior.

## Cosas que conviene saber

- El formato de página es el de `gen-1586.ps1` (22-10-2026). Si cambia `buildEtiquetaChildren`, cambiar
  `armarRequests_` también.
- `_cmdNorm` (index.html) y `norm_` (Code.gs) tienen que normalizar igual, o la marca «✓ Doc» falla.
- El estado se guarda 10 min en caché del script. Si alguien pega páginas a mano, la marca tarda eso en verse.
- La API de Docs no inserta imágenes sin URL pública, así que el dibujo entra con DocumentApp: se deja una
  marca de texto `[[IMG-…]]` y se reemplaza. Si queda una marca a la vista, falló ese paso.
