/**
 * Casa Zaru — arma «Biblioteca por producto» en Drive con ACCESOS DIRECTOS (no copia ni mueve originales).
 *
 * Cómo usarlo (una vez, con la cuenta hola@casazaru.cl):
 *   1. script.google.com → Nuevo proyecto → pegar este archivo entero → Guardar.
 *   2. Ejecutar la función `armarBiblioteca` y aceptar los permisos de Drive.
 *   3. Si se corta por tiempo (Apps Script corta a los 6 minutos), volver a ejecutarla: sigue donde quedó,
 *      porque se salta los accesos directos que ya existen.
 *
 * Lee `clasificacion.csv` de la carpeta «Casa Zaru/Biblioteca/Clasificacion 2026-11».
 * Estructura que crea:
 *   Biblioteca por producto/<Producto>/<Madera>/{Fotos|Videos}/<acceso directo>
 *   Biblioteca por producto/★ Mejores para contenido/<Producto>/...   (calidad 4-5, uso anuncio/catálogo/testimonio)
 * No incluye lo marcado «descartar» ni las copias.
 */
const CARPETA_DATOS = ['Casa Zaru', 'Biblioteca', 'Clasificacion 2026-11'];
const NOMBRE_CSV = 'clasificacion.csv';
const RAIZ = 'Biblioteca por producto';
const LIMITE_MS = 5 * 60 * 1000;

function armarBiblioteca() {
  const t0 = Date.now();
  let datos = DriveApp.getRootFolder();
  CARPETA_DATOS.forEach(n => { datos = hija_(datos, n, false); });
  const csv = datos.getFilesByName(NOMBRE_CSV);
  if (!csv.hasNext()) throw new Error('No encuentro ' + NOMBRE_CSV + ' en ' + CARPETA_DATOS.join('/'));
  const filas = Utilities.parseCsv(csv.next().getBlob().getDataAsString('UTF-8'));
  const h = filas.shift(); const i = n => h.indexOf(n);
  const raiz = hija_(datos.getParents().next(), RAIZ, true);
  const cache = {};
  let hechos = 0, saltados = 0;
  for (const f of filas) {
    if (Date.now() - t0 > LIMITE_MS) { Logger.log('Pausa por tiempo: ' + hechos + ' creados. Vuelve a ejecutar.'); return; }
    const uso = f[i('uso')], copia = f[i('copia_de')], id = f[i('drive_id')];
    if (!id || uso === 'descartar' || copia || f[i('clasificado')] !== 'sí') continue;
    const prod = cap_(f[i('producto')] || 'otro'), mad = cap_(f[i('madera')] || 'no se distingue');
    const tipo = f[i('tipo')] === 'video' ? 'Videos' : 'Fotos';
    const nombre = f[i('id')] + ' · ' + (f[i('descripcion')] || f[i('nombre')]).slice(0, 90);
    const destinos = [[prod, mad, tipo]];
    const q = +f[i('calidad')] || 0;
    if (q >= 4 && ['anuncio', 'catálogo', 'instalado donde el cliente', 'testimonio cliente'].includes(uso)) destinos.push(['★ Mejores para contenido', prod, tipo]);
    for (const ruta of destinos) {
      const clave = ruta.join('/');
      let carp = cache[clave];
      if (!carp) { carp = raiz; ruta.forEach(n => { carp = hija_(carp, n, true); }); cache[clave] = carp; }
      if (carp.getFilesByName(nombre).hasNext()) { saltados++; continue; }
      carp.createShortcut(id).setName(nombre);
      hechos++;
    }
  }
  Logger.log('Listo. Creados: ' + hechos + ' · ya existían: ' + saltados);
}

function hija_(padre, nombre, crear) {
  const it = padre.getFoldersByName(nombre);
  if (it.hasNext()) return it.next();
  if (!crear) throw new Error('No existe la carpeta ' + nombre);
  return padre.createFolder(nombre);
}
function cap_(s) { return s.charAt(0).toUpperCase() + s.slice(1); }
