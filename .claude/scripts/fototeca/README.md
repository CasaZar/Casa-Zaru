# Fototeca: cómo sumar una tanda de fotos y videos

La Fototeca vive en cotizador.casazaru.cl/fototeca.html. Su índice y sus hojas de miniaturas están en el
bucket privado `fototeca` del proyecto del Cotizador (`cmxqorsyxoltrakxawro`). Estos programas preparan
una tanda nueva. Se usaron así el 11-11-2026 con las fotos del PC: 4.170 archivos revisados y 1.156 publicados.

**Reglas que no se negocian**
- Nada de fotos, miniaturas, listas ni datos dentro del repo, que es público. Todo el trabajo queda en
  `%LOCALAPPDATA%\CasaZaru\fototeca\`. Las hojas de referencia de madera están en
  `G:\Mi unidad\Casa Zaru\Biblioteca\_referencias-madera`.
- Los originales nunca se mueven ni se borran: `6-a-drive.ps1` solo **copia** al Drive.
- Antes de publicar, alguien mira las repetidas dudosas y los descartes en hojas de contacto.
- La llave de la API sale de la variable de usuario `ANTHROPIC_API_KEY`; nunca se escribe en un archivo.
- Los programas van con BOM UTF-8: PowerShell 5.1 lee mal los acentos sin BOM, y eso estropea el prompt.

## Pasos

| # | Programa | Qué hace |
|---|---|---|
| 0 | (a mano) | Bajar `datos.json`, `datos-2.json` y las hojas `sNN.jpg` del bucket a `…\fototeca\fototeca-local\` |
| 1 | `1-lista.ps1 -Desde <id>` | Lista fotos y videos del PC que no están en el Drive (compara por tamaño). `-Desde` es el número siguiente al último `M####` publicado |
| 2 | `2-miniaturas.ps1` (+ `2b-…`) | Miniaturas de 512 px y cuadros de video sin ffmpeg. `2b` rehace las que salieron como ícono de OneDrive; OneDrive tiene que estar corriendo |
| 3 | `3-huellas-fototeca.ps1` | Huella (dHash) de cada foto ya publicada |
| 4 | `4-repetidas.ps1` | Saca las repetidas contra la Fototeca (distancia ≤ 3) y entre ellas (≤ 4) |
| 5 | `5-clasificar.ps1 -Batch` | Clasifica con la guía `.claude/prompts/clasificador-guia.md` (producto, madera, uso…). Por Batch cuesta la mitad. **Preguntar antes de gastar** |
| 6 | `6-a-drive.ps1` | Copia los originales útiles al Drive (`Biblioteca\<tanda>\<año>\1 Utiles\<producto>\`) |
| 7–8 | `7-diferencia-pares.ps1`, `8-rafagas.ps1` | Segunda pasada de repetidas: diferencia de color y ráfagas casi iguales. Revisar a ojo |
| 9 | `9-armar-indice.ps1 -Desde <hoja>` | Arma las hojas `sNN.jpg` y el índice nuevo para subir al bucket |

## Trampas conocidas
- **Límite del bucket: 5 MB por archivo.** `datos.json` tiene 4,95 MB, así que no se le suma nada. Las fotos
  del PC están en `datos-2.json`, que la página lee además del primero. Si una tanda futura no cabe en
  `datos-2.json`, hay que crear `datos-3.json` **y** enseñarle a `fototeca.html` a leerlo.
- El panel de Storage no pisa un archivo con el mismo nombre: para reemplazar, primero se borra el viejo,
  previo respaldo.
- Los renders de SketchUp y las fondo blanco engañan a la huella: dos tablas distintas sobre fondo
  liso parecen iguales. Por eso las dudosas se miran a ojo.
- En PowerShell `$t` y `$T` son la misma variable, y los alias `H` y `R` chocan con `Get-History`.
- Lo que se descarta, según la guía: renders y planos, el proyecto del colegio (melamina o terciado),
  fotos personales, capturas y documentos.

## Después de publicar
- Las fotos ya usadas en Instagram se marcan con `fototeca_marcar_uso` (canal `post` o `reel`, más el link).
  Se cruzó el perfil completo el 11-11-2026: 86 fotos. Hay un único uso por foto, canal y fecha.
- Los descartes que se cuelan se mandan a la papelera desde la página (`fototeca_editar`, acción `papelera`).
  Se recuperan hasta que alguien la vacíe.
