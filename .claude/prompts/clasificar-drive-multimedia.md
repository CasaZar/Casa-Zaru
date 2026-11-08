# Prompt — Clasificar las fotos y videos del Drive de Casa Zaru

> Pegar tal cual en una sesión nueva (o decir «sigue el prompt de clasificar-drive-multimedia»).
> Escrito el 08-11-2026 después de medir el Drive.

## Objetivo
Clasificar **cada foto y video** de Casa Zaru que hay en `G:\Mi unidad` (Drive de hola@casazaru.cl) por
**producto**, **madera**, **tipo** (foto/video) y **para qué sirve**, mirando el contenido de verdad
(no solo el nombre del archivo ni la carpeta). Los videos se revisan por cuadros, no se suponen.

## Lo que ya se sabe (no volver a medirlo)
- ~4.900 archivos de medios (≈4.000 fotos, ≈900 videos, 69 GB), pero **casi la mitad son duplicados**:
  únicos por nombre+tamaño ≈ 2.500, de los cuales ≈ 480 son videos.
- `Biblioteca Multimedia Casa Zaru` (03-11-2026) son **accesos directos** a los originales, ya separados en
  6 grupos gruesos (Productos, Maderas, Instalaciones, Anuncios, Taller, Otros). No es clasificación por
  producto ni madera. No duplicar trabajo: clasificar el **original** una sola vez.
- La masa sin clasificar está en `Marketing y Anuncios\Fotos y Videos Casa Zaru\FOTOS Y VIDEOS TALLER`
  (~1.150) y en las carpetas «Archivos sueltos», «We transfer», «MARTES», «VIDEOS Y FOTOS JUNIO 2026».
- **Fuera de alcance:** `Respaldo PC`, `Empanadas Puerto Octay`, `Brasa Nativa`, `Google AI Studio`,
  bocetos, capturas de pantalla del cotizador, PDFs y catálogos.
- No hay ffmpeg. Los cuadros de video se sacan con `.claude/scripts/cuadros.ps1` (WinRT, probado el
  08-11 con VID-20260203-WA0122.mp4).

## Referencias para reconocer la madera (usarlas, no adivinar de memoria)
Carpetas ya rotuladas por persona → son la **verdad de referencia**:
`Fotos Productos\TIPOS DE MADERA\` → CASTAÑO, COIHUE, RAULÍ, LENGA, PINO OREGÓN, MAÑÍO, CIPRÉS,
COMBINADAS, CASTAÑO/COIHUE/OREGÓN TEÑIDO, MUESTRAS 7 MADERA. Y las fichas en `.claude/fichas/maderas/`.
Antes de clasificar, mirar 3-4 fotos de cada una y escribir una «chuleta» corta: color, veta, nudos,
cómo se ve con aceite. Las siete maderas del catálogo: **Castaño, Coihue, Raulí, Lenga, Oregón, Mañío,
Ciprés** (+ teñidos y combinadas). Laurel está deprecado. Nunca escribir «nativa» (decir «madera noble»).

## Categorías
**Producto** (una): cubierta de cocina · isla · cubierta de baño/vanitorio · escritorio · repisa ·
cubremuro · peldaños/escalera · puerta · mesa de comedor · mesa de centro · mesa lateral · banca ·
base de mesa (fierro) · tablón/materia prima · muestra de madera · otro · no se ve producto.

**Madera:** una de las 7, teñido (cuál), combinada, o «no se distingue».
**Confianza de la madera:** alta / media / baja. Si es baja, no se fuerza: va a «revisar».
**Etapa:** taller (fabricación) · terminado en taller · instalado donde el cliente · fondo blanco/catálogo
· anuncio ya armado (con textos encima).
**Uso sugerido:** catálogo/ficha · anuncio · testimonio/cliente · proceso/historia · descartar
(borrosa, repetida, sin producto, persona sin permiso a la vista).
**Videos además:** duración, horizontal/vertical, si tiene audio hablado o subtítulos, y una línea de
qué pasa (ej. «aplican aceite a cubierta de castaño, 30 s, vertical»).

## Método
1. Inventario a CSV: ruta, nombre, tamaño, fecha, tipo, hash/nombre+tamaño para agrupar duplicados.
   Se clasifica un archivo por grupo de duplicados; el resto hereda.
2. Primero lo ya rotulado por carpeta (madera o producto en el nombre de la carpeta) → se confirma
   con una mirada rápida, no se reclasifica a ciegas.
3. Fotos: hojas de contacto de 3×3 miniaturas (~400 px c/u) con el nombre en cada recuadro, para no
   abrir 2.000 imágenes de a una. Si la madera no se distingue en miniatura, abrir esa foto sola.
4. Videos: 4 cuadros repartidos en la duración (más si dura >60 s), juntos en una hoja.
5. Anotar todo en el CSV. Nada se mueve, renombra ni borra en el Drive en esta etapa.
6. Entregar: planilla (Google Sheet en `Casa Zaru\Biblioteca`) con filtros por producto/madera/tipo,
   un resumen con conteos reales (de la planilla, no de cabeza) y la lista «revisar» para el equipo.
7. Solo con el ok del usuario, en una segunda etapa: crear la estructura de carpetas
   `Biblioteca por producto\<Producto>\<Madera>\{Fotos,Videos}` con **accesos directos** (no copias,
   no mover originales: hay links en anuncios, Shopify y la Biblioteca actual que apuntan a ellos).

## Reglas
- Avanzar por lotes de ~200 y guardar el CSV después de cada lote (si se corta, se retoma).
- Mostrar una muestra de 20 clasificaciones al usuario después del primer lote para calibrar antes de
  seguir con el resto.
- Preguntar antes de lanzar subagentes en paralelo (costo).
- Nada al repo público: el CSV y las hojas de contacto van al scratchpad y a Drive.
