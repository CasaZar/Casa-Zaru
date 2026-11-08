# Guía para clasificar fotos y videos de Casa Zaru

Casa Zaru fabrica a medida en madera noble (nunca escribir «nativa»): cubiertas de cocina, islas, cubiertas
de baño (vanitorios), escritorios, repisas, cubremuros, peldaños, puertas, mesas (comedor, centro, lateral),
bancas y bases de fierro. Taller en Villarrica. El material se usa para **hacer contenido** (anuncios,
redes, fichas de producto) y para que el vendedor (César) encuentre rápido la foto que necesita.

## Chuleta de maderas (sacada de las carpetas ya rotuladas)
- **Castaño**: amarillo-miel/dorado claro; **veta muy marcada en arcos y "catedrales"** (como fresno/roble),
  anillos visibles, algunos nudos. Con aceite queda dorado. Es la más "dibujada" de las claras.
- **Coihue**: **rosado-salmón a rojizo**, veta suave y lisa, casi sin nudos; a veces una tabla de albura más
  clara (crema) entre tablas rosadas. Uniforme y sobrio.
- **Raulí**: **anaranjado-rojizo cálido**, más saturado que el coihue, veta recta con algo de figura,
  tablas con tonos distintos (franjas naranjo/rojo). Aspecto "cereza".
- **Lenga**: **rosado-beige claro / café con leche**, veta fina; a menudo tablas con **franjas de albura
  crema** muy contrastadas. Más pálida y apagada que el coihue.
- **Oregón (pino oregón)**: **anillos de crecimiento muy marcados** (líneas paralelas oscuras y claras, "flamas"
  en V), anaranjado-salmón, nudos redondos. Se reconoce por el rayado fuerte.
- **Mañío**: **beige/crema muy claro, casi blanco-amarillento**, veta suave con figura discreta, algunos
  nudos pequeños oscuros. La más pálida.
- **Ciprés**: amarillo claro con **muchos nudos pequeños dispersos (puntitos café)**, veta ondulada. Si
  ves "lunares" por toda la superficie, es ciprés.
- **Teñido**: color café-rojizo oscuro uniforme (nogal/caoba) que no es natural → «coihue teñido»,
  «castaño teñido», «oregón teñido» si se intuye la base; si no, «teñido».
- **Combinada**: tablas de **dos o más maderas alternadas** con contraste fuerte (ej. raulí + castaño).
- **Pino (por confirmar)**: amarillo claro con nudos grandes y oscuros, típico de puertas tipo granero en bruto.
  No es del catálogo; úsalo como madera «pino (por confirmar)» con confianza baja.
- Si la foto es oscura, lejana, de otra cosa o muy procesada: madera = «no se distingue». No adivinar.
- Confusiones típicas: coihue vs raulí (raulí más naranjo); lenga vs coihue (lenga más pálida, franjas
  crema); mañío vs castaño (castaño tiene arcos marcados); ciprés vs oregón (ciprés = puntitos; oregón =
  rayas de anillos).

## Campos a llenar (una línea JSON por archivo)
```
{"id":"M0123",
 "producto":"cubierta de cocina|isla|cubierta de baño|escritorio|repisa|cubremuro|peldaños|puerta|mesa de comedor|mesa de centro|mesa lateral|consola o mesa de arrimo|velador|estantería o librero|rack de TV o mueble|banca|taburete o piso (wanco)|accesorio (cacho, cera, tabla de picar, etc.)|base de mesa|tabla o tablero suelto|muestra de madera|tablón o materia prima|otro|sin producto",
 "madera":"castaño|coihue|raulí|lenga|oregón|mañío|ciprés|combinada|coihue teñido|castaño teñido|oregón teñido|teñido|no se distingue",
 "confianza":"alta|media|baja",
 "etapa":"taller fabricando|terminado en taller|instalado cliente|fondo blanco catálogo|pieza gráfica o anuncio|otro",
 "ambiente":"cocina|baño|living|comedor|oficina|escalera|exterior|taller|feria|otro",
 "forma":"rectangular|redonda|ovalada|en L|con curva|borde vivo|otra|n/a",
 "uso":"catálogo|anuncio|testimonio cliente|proceso taller|detalle de madera|descartar",
 "calidad":1-5,
 "orientacion":"vertical|horizontal|cuadrada",
 "personas":true|false,
 "texto_encima":true|false,
 "descripcion":"una frase concreta y buscable, ej. 'Cubierta de cocina de castaño con lavaplatos bajo cubierta, cocina blanca, recién instalada'",
 "gancho":"(opcional) por qué sirve para contenido, ej. 'antes/después', 'veta espectacular', 'volcán de fondo'",
 "etiquetas":["palabras","clave","para","buscar"]}
```
Para **videos** agregar: `"que_pasa"` (qué ocurre a lo largo de los cuadros: "lijan la cubierta y aplican
aceite") y `"tipo_video"` (proceso|instalación|recorrido producto|testimonio|anuncio editado|otro).

Reglas:
- **calidad**: 5 = lista para anuncio/ficha (nítida, buena luz, producto completo); 3 = usable en historia
  o redes; 1 = borrosa, oscura, cortada o repetida → uso «descartar».
- Etiquetas en minúscula, en español, incluyendo madera y producto y detalles (lavaplatos, encimera,
  isla, patas de fierro, borde redondeado, curva, nudo, aceite, lijado, cnc, volcán, lago…).
- Capturas de pantalla, conversaciones de WhatsApp, cotizaciones, documentos → producto «otro», uso
  «descartar», descripción breve de qué es.
- Personas reconocibles (clientes) → `personas:true`; no describir quiénes son.
- No inventes. Si dudas entre dos, elige la más probable y baja la confianza.
