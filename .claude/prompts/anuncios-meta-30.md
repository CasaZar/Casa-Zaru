# Prompt — 30 anuncios de Meta para Casa Zaru (Ads Library + auditoría de Cote + Fototeca)

> Pegar entero en una sesión nueva de Claude Code, en `C:\Users\dell\Casa Zaru - Claude`.
> Adjuntar (o dejar en la carpeta indicada) la **última auditoría de Meta que entrega María José los
> lunes**. Si no está, pedírmela antes de empezar; no inventar sus cifras.

---

## Tu rol

Eres director creativo y estratega de performance de Casa Zaru. Tu trabajo es entregarme **30 anuncios
de Meta listos para producir y subir**, cada uno justificado: qué cambias respecto de lo que ya
corremos, por qué, y en qué nos diferencia de la competencia. Nada genérico: cada pieza sale de un dato
(nuestra auditoría, la Ads Library o la Fototeca) y lo dice.

## Quiénes somos (no negociable, usar tal cual)

Casa Zaru fabrica a medida, en su taller de **Villarrica**, cubiertas, mesas, puertas, peldaños y
muebles en **madera noble del sur de Chile**. Despacho a todo Chile.

Diferenciadores (son el corazón de los 30 anuncios):
1. **A tu medida**: fabricamos para ti, al centímetro. No es catálogo de bodega.
2. **Lista para instalar / lista para usar**: llega terminada, con **acabado protector**.
   «No tienes que barnizar nada» ni preocuparte de nada más.
3. **Traslado con garantía**: «Si llega con daño, la reponemos». Embalaje reforzado.
4. **Garantía** (verificar los años en casazaru.cl antes de escribirlo; la franja de la web dice 5 años).
5. **Madera noble del sur de Chile**, trabajada en Villarrica (origen = activo de marca, no esconderlo).
6. Fabricación **7 a 15 días hábiles**. Cera de mantención de **100 cc** incluida.
7. Cotización inmediata en línea: **casazaru.cl/cotizador**.

Reglas de texto (si alguna se rompe, el anuncio no sirve):
- **NUNCA «madera nativa»**. Decir «madera noble» o el nombre de la madera. Buscar «nativ» antes de entregar.
- Nunca «incluye instalación» ni «envío seguro» (no hay seguro: hay reposición si llega dañada).
- Puertas: no incluyen marco, bisagras, chapa ni manilla (el marco se cotiza aparte). No prometer otra cosa.
- El envío se cobra aparte según destino (o retiro en Villarrica). No decir «envío gratis».
- Nada de «al tiro»: «al instante» / «de inmediato».
- Si el anuncio lleva a WhatsApp, es el **0141** (solo anuncios), y el link al cotizador lleva los
  parámetros del brief (`utm_medium=paid` etc., ver
  `G:\Mi unidad\Casa Zaru\Claude Code - María José\BRIEF-ANUNCIOS-COTIZADOR.md`). Sin eso el cotizador
  manda el lead al número equivocado.
- Gráficas: sin emojis; íconos de línea café sobre banda gris clara, como la franja de la web. Paleta:
  verde `#485B3D`, terracota `#B5652E`, dorado `#D4AC74`, crema `#F1ECE4`; Playfair Display + Poppins.
  Usar el logo real (SVG), nunca imitarlo con letras.
- Todo número que pongas (precios, ventas, cifras de rendimiento) sale de una fuente real que citas.
  Si no lo tienes, escribe `[DATO: …]` y sigue.

## Paso 1 — Nuestra auditoría (lo que ya sabemos que funciona)

1. Leer la última auditoría de Meta de María José (adjunta) y, como respaldo, el artifact del informe
   semanal (`https://claude.ai/code/artifact/c41f31af-4a5c-4dc9-b3f2-c6399a6fc757`, con Artifact read).
2. Con el MCP de Meta **solo en lectura**, cuenta **1393145254729847** («Casa Zaru Ads»), y ninguna otra:
   - Rendimiento de los últimos 90 días **a nivel anuncio y conjunto** (no campaña: WhatsApp y compra
     web conviven en la misma campaña y a nivel campaña no se ve el reparto).
   - Para cada anuncio: formato, gancho (primeros 3 s o primera línea), producto, CTR, CPC, costo por
     conversación de WhatsApp, frecuencia, hook rate / thruplay si es video.
   - Ojo: las ventas se cargan desde WhatsApp, así que el píxel subestima el retorno. «No vende según
     Meta» no es razón para descartar un anuncio que trae conversaciones baratas.
3. Sacar: top 5 ganadores, top 5 perdedores, patrones (qué producto, qué formato, qué ángulo) y la
   fatiga (frecuencia > 3, CTR cayendo).

**No crear, activar, pausar ni editar nada en Meta.** Las escrituras del MCP están negadas en
`.claude/settings.json` y así se quedan.

## Paso 2 — Ads Library (competencia y referentes)

Con `ads_library_search` (Chile, anuncios activos) revisar:
- **Competencia directa**: mueblerías y talleres de madera a medida en Chile, cubiertas de madera,
  mesas de comedor de madera, puertas de madera, escaleras/peldaños, carpintería a medida. Buscar por
  palabras clave («cubierta de madera», «mesa a medida», «muebles a medida», «puertas de madera»,
  «madera maciza», «roble», «raulí», «coigüe») y por los nombres que vayan apareciendo.
- **Casa Zaru** misma en la Ads Library, para ver lo que el público ve hoy.
- **Referentes internacionales** del rubro mueble/DTC (marcas de mesas y muebles de madera a medida
  que corran mucho tiempo el mismo creativo: si un anuncio lleva meses activo, probablemente rinde).

Tabla por anunciante: qué ángulo usan, formato, oferta, cuánto tiempo lleva activo el anuncio
más antiguo, y **el hueco**: qué no dice nadie que nosotros sí podemos decir (medida exacta, lista
para instalar, reposición si llega dañada, taller en Villarrica, madera noble del sur).

## Paso 3 — Principios de marketing aplicados (no un resumen de libros)

Aplica, nombrándolos en cada justificación, los marcos que de verdad mueven anuncios hoy:
- **Meta 2025-2026 (Andromeda / Advantage+)**: el creativo es la segmentación. Se necesita
  **diversidad real de conceptos** (distinto ángulo, persona, formato), no 30 variaciones del mismo
  texto. Agrupar los 30 en ~8-10 conceptos con 3-4 ejecuciones cada uno.
- **Schwartz — niveles de conciencia**: anuncios para quien no sabe que existe la cubierta a medida,
  para quien compara, y para quien ya cotizó (remarketing).
- **Byron Sharp — disponibilidad mental y activos distintivos**: madera, taller, Villarrica, el verde y
  la terracota, la misma voz. Que se reconozca sin ver el logo.
- **Hormozi — ecuación de valor**: subir resultado soñado y certeza (garantía, reposición), bajar
  tiempo (7-15 días, lista para instalar) y esfuerzo (no tienes que hacer nada).
- **Cialdini**: prueba social (instalado donde el cliente, reseñas Judge.me), autoridad (oficio,
  años de taller), escasez honesta solo si es real.
- **Ogilvy / Hopkins / Sugarman**: titular específico, beneficio concreto, una idea por anuncio.
- **Video vertical**: gancho en 0-3 s, retención 3-15 s, CTA claro; subtítulos siempre (se ve sin sonido).

Y lo propio del rubro **mueble a medida**:
- Proceso y oficio venden (tronco → tabla → cepillado → acabado → embalaje).
- El miedo del comprador: medida mal tomada, que llegue dañada, que no sea como en la foto, el
  envío desde el sur. Cada miedo tiene su anuncio que lo desarma.
- Precio: anclar contra la alternativa (mueblería de retail, melamina, hacerlo uno mismo) y mostrar
  que se cotiza en segundos.
- Contenido de cliente real (UGC, foto en su casa) le gana a la foto de estudio en conversión.

## Paso 4 — Fototeca (con qué fotos y videos se arma cada anuncio)

Fuente: `G:\Mi unidad\Casa Zaru\Biblioteca\Clasificacion 2026-11\` (clasificacion.csv y
`clasificacion-google-fotos-2025-2026.csv`, columnas producto, madera, uso, calidad, descripción, ia)
y la Fototeca en `cotizador.casazaru.cl/fototeca.html`.
- Para cada anuncio, elegir 1-3 piezas por **id (M####)**, con calidad ≥ 4, `ia = no`, sin renders,
  sin el proyecto del colegio.
- **Preferir piezas «sin usar»** (tabla `fototeca_usos` del Cotizador, MCP `supabase-cotizador` en solo
  lectura) para no repetir lo que ya se vio en Instagram; si se reusa una ganadora, decirlo.
- Si un concepto no tiene material bueno, decir **qué hay que grabar** (toma, encuadre, duración) en
  vez de forzar una foto mala.

## Paso 5 — Entregable: 30 anuncios

Para **cada** anuncio, esta ficha:

| Campo | Contenido |
|---|---|
| N° y concepto | ej. «07 · Concepto C — Llega lista» |
| Etapa | Frío / Tibio / Remarketing (nivel de conciencia de Schwartz) |
| Objetivo y destino | WhatsApp 0141 o cotizador con UTM |
| Formato | Imagen 4:5, carrusel, video 9:16 (reel/historia) |
| Producto | cubierta, mesa, puerta, peldaños, etc. |
| Material | ids de la Fototeca, o «grabar: …» |
| Texto principal | listo para pegar, ≤ 125 caracteres visibles antes del «ver más» + resto |
| Titular | ≤ 40 caracteres |
| Descripción | opcional, corta |
| Texto en la imagen | lo que va sobreimpreso, máximo 7 palabras |
| Botón | Enviar mensaje / Cotizar / Más información |
| **Qué cambia vs. lo actual** | el anuncio nuestro que reemplaza o mejora, con su dato de la auditoría |
| **Diferenciador** | cuál de los 7 y por qué ese |
| **Por qué debería funcionar** | el principio + el dato (auditoría o Ads Library) |
| Qué medir y cuándo matarlo | métrica y umbral (ej. CTR < 0,8 % a los 3.000 impresiones) |

**Mínimo 10 de los 30 son video**, y cada video lleva **guion en tabla**: segundo a segundo
(0-3 gancho, 3-15 desarrollo, 15-30 cierre), toma, texto en pantalla, voz en off o lo que se dice a
cámara, y música/sonido. Pensar quién lo graba (taller, César, cliente) y que se pueda grabar con
celular en una mañana.

Ideas que deberían estar (no limitarse a estas):
- «Del árbol a tu mesa» en 20 s (proceso en el taller de Villarrica).
- Desembalaje del cliente: «llegó lista, la pusimos y listo».
- «¿Y si llega dañada?» → «La reponemos». Objeción convertida en anuncio.
- Medida exacta: huincha en el espacio del cliente → la cubierta calza al centímetro.
- Elige tu madera (las tarjetas de madera de la web).
- Antes / después del espacio.
- Comparación honesta vs. melamina/retail (sin nombrar marcas).
- Cotiza en 30 segundos (pantalla del cotizador).
- Reseñas reales leídas sobre la foto del producto instalado.
- Remarketing para quien cotizó y no compró (el 87 % de las ventas se cierra en ≤ 7 días).

## Al final

1. **Plan de prueba**: cómo subir los 30 sin quemar presupuesto (qué conceptos van primero, cuántos
   por conjunto, cuánto tiempo antes de decidir, presupuesto `[DATO]`). Respetar que WhatsApp es lo que
   trae conversaciones; no mover presupuesto a compra web sin datos.
2. **Lista de grabación**: todas las tomas que faltan, agrupadas por lugar (taller, casa de cliente,
   pantalla), para que Emerge o César las graben en una jornada.
3. **Revisión final**: buscar «nativ», «envío gratis», «envío seguro», «incluye instalación», «al tiro»
   y emojis en las gráficas. Cero coincidencias.

Entregar todo como página (Artifact) privada para compartir con María José, con un índice de los 30
y las fichas, más un `.csv` con una fila por anuncio para cargar en Ads Manager a mano.
