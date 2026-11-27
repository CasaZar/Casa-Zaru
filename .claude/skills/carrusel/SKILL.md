---
name: carrusel
description: Arma carruseles de Instagram de Casa Zaru que la gente guarde, con datos verificados — investiga (datos propios de las bases en solo lectura, ergonomía, ciencia de la madera) con fuente primaria y nivel 🟢/🟡/🔴 por cifra, se DETIENE para que el usuario revise la tabla, y recién con su sí arma el carrusel en Canva editable por capas. Actívala cuando el usuario pida "/carrusel", "un carrusel", "carrusel de Instagram", "láminas para redes", "contenido con datos", "post que la gente guarde", o pegue el prompt de investigación de datos para contenido. No es para anuncios de Meta (usa todo-es-un-anuncio) ni para correos (copy-correos).
---

# /carrusel: carruseles con datos que se pueden respaldar

Un dato equivocado nos quita credibilidad. **Si no se puede respaldar, no entra.**

El trabajo tiene dos etapas con una pausa obligatoria entre medio:

> **investigar → tabla → el usuario revisa → (sí explícito) → Canva**

Un «dale» a la idea o a la lista de temas no aprueba las cifras ni el diseño. Ver las memorias
`feedback_boceto_antes_de_construir` y `feedback_recomendar_no_es_permiso`.

## Antes de empezar

1. Leer `referencia/fuentes.md` (en esta carpeta). Tiene:
   - las cifras externas que ya están verificadas, con su fuente,
   - qué sitios se pueden leer y cuáles bloquean,
   - las plantillas SQL,
   - la lista de mitos.

   **Reutilizar lo que ya está en 🟢 en vez de investigarlo de nuevo.**
2. Leer la última investigación con cifras propias en `G:\Mi unidad\Casa Zaru\Contenido\Carruseles\`. Las
   cifras del negocio **no van en el repo**, porque es público.
3. Si el usuario no dijo el tema, proponer 3 a 5 carruseles, armados solo con lo que ya está en 🟢, y esperar
   que elija.

## Etapa 1: investigar

Persona: investigador senior que mezcla tres oficios:
- ergonomía y diseño de muebles (antropometría, ISO/EN/BIFMA),
- ciencia de la madera,
- verificación de datos periodística.

Casa Zaru hace muebles de **madera noble** (nunca «nativa») a mano en el sur de Chile.

**Reglas de la investigación**
1. **Fuente primaria siempre**: la norma, el libro o el paper original. Si solo aparece un blog que la cita,
   buscar el original. Si no aparece, es 🔴.
2. **Dos fuentes independientes** para toda cifra que vaya en grande. Dos retailers que copian lo mismo
   cuentan como una sola.
3. **La cifra tal cual dice la fuente**, con su unidad, su rango y la página, tabla o sección. Si se
   convierte o se redondea, decirlo.
4. **Buscar la contradicción.** Si dos fuentes no coinciden, mostrar las dos y explicar por qué (año, país,
   uso).
5. **Separar norma de costumbre**: «la norma dice» es distinto de «se suele usar».
6. **Chile primero**: OGUC, INN, INFOR y MINVU van por sobre el dato extranjero.
7. **Nada exagerado.** Si el estudio es chico, viejo, de laboratorio o financiado por la industria, decirlo.
8. **Nunca de memoria.** Una cifra que no se leyó en la fuente en esta sesión, o que no está ya en
   `referencia/fuentes.md`, es 🔴.
9. **Nada pirata.** Normas y libros de pago (NCh, EN, ISO, Neufert, Panero) solo se usan si el usuario
   pasa su copia. Se buscan alternativas oficiales y gratuitas (MINVU, INSST, OSHA, extensión universitaria).

**Niveles**
- 🟢 norma o fuente primaria más una segunda fuente independiente.
- 🟡 una sola fuente sólida. Puede publicarse, avisado.
- 🔴 no verificado. **No se publica.**

**Datos propios** (Supabase en solo lectura, por el MCP):
- Gestión: `supabase-gestion`.
- Cotizador: `supabase-cotizador`.

Para cada cifra va la consulta SQL exacta, el período y el número de casos (n), con los percentiles 25, 50
y 75 cuando corresponda. Nada redondeado de cabeza. Las plantillas están en `referencia/fuentes.md`.

**Cómo leer fuentes que bloquean**
- Primero WebSearch para ubicar la URL; después el agente `web-fetch`.
- Si devuelve 403 o un captcha, probar con el Chrome del usuario (`get_page_text`). Sirve para HTML, no
  para PDF.
- Los estudios se leen por la API de Europe PMC
  (`ebi.ac.uk/europepmc/webservices/rest/search?query=EXT_ID:<PMID>&resultType=core&format=json`),
  que trae el abstract completo.
- Un PDF que `web-fetch` guarda pero no lee se extrae con el script de PowerShell descrito en
  `referencia/fuentes.md`.
- No reintentar una URL que ya falló, y anotar en la referencia el sitio que bloquea.

**Qué se entrega** (archivo .md en `G:\Mi unidad\Casa Zaru\Contenido\Carruseles\<fecha>-<tema>.md`)

1. Una tabla por frente, con estas columnas:
   `| Dato (como iría en la lámina) | Cifra exacta y unidad | Fuente primaria (autor, título, año, página o URL) | 2.ª fuente | Nivel | Notas y matices |`
2. La propuesta de carrusel, de 6 a 8 láminas, solo con 🟢 (o 🟡 avisado):
   - portada con gancho,
   - una idea por lámina,
   - la línea chica de fuente en cada lámina,
   - la última lámina con el cierre a **casazaru.cl/cotizador**.
3. La lista de lo que no se pudo verificar, con el porqué y cómo se destraba.
4. Las frases que NO hay que decir (mitos del rubro).

Al terminar, actualizar `referencia/fuentes.md` con:
- las cifras externas nuevas que quedaron en 🟢 o 🟡,
- los sitios que bloquean y los que funcionan,
- los mitos nuevos.

Nada de cifras propias del negocio en ese archivo.

**Y parar.** Mostrar el resumen y preguntar si se arma.

## Etapa 2: armar en Canva (solo con el sí explícito)

Toda pieza se entrega **en Canva y editable**. Nunca como PNG plano. Ver la memoria
`feedback_canva_editable_capas`.

- **Formato** 1080 × 1440 (3:4).
- **Capas**: cada texto y cada número en su propia capa de texto, para que el equipo corrija sin pasar
  por Claude.
- **Receta que funciona**:
  1. `create-design` genera una sola página: usarla para la portada.
  2. `merge-designs` duplica la página 1, con `page_numbers` [1,1,…] en una sola operación.
  3. En cada copia:
     - `update_fill` para la foto,
     - `replace_text` sobre las capas que ya traen la fuente de marca (con `add_text` sale la fuente por
       defecto),
     - el logo como imagen.
- **Fotos**: de la Fototeca, subidas como asset.
- **Logo**: el real, en SVG, desde `Cotizador/fotos`. Nunca imitarlo con letras.
- **Degradado**: un PNG transparente subido, como una sola capa. Los rectángulos semitransparentes se ven
  como escalones.
- **Paleta**: verde `#485B3D`, terracota `#B5652E`, dorado `#D4AC74`, crema `#F1ECE4`.
- **Fuentes**: Playfair Display para los títulos y Poppins para el texto.
- **Íconos**: de línea, finos, en café. **Sin emojis.**
- **Gráficos de datos** (barras, percentiles): seguir la skill `dataviz`. El número va en su capa de texto,
  no quemado en la imagen.
- **Mensaje**: una idea por lámina, el número grande y su unidad al lado.
- **Fuente**: la línea chica abajo de cada lámina, con autor y año, o «Cotizador Casa Zaru, período, n».
- **Cierre**: la última lámina lleva a casazaru.cl/cotizador.

## Revisión antes de entregar

- [ ] Buscar «nativ» en todos los textos. Debe dar cero.
- [ ] Ninguna cifra 🔴 en ninguna lámina. Las 🟡 van avisadas en el resumen al usuario.
- [ ] Cada lámina con dato tiene su línea de fuente.
- [ ] Ninguna frase de la lista de mitos de `referencia/fuentes.md`.
- [ ] Las cifras propias calzan con la consulta: se recalculan si pasó más de una semana.
- [ ] Cantidades siempre con su unidad (cm, %, mm).
- [ ] Estilo de la marca: madera noble, «hecha para durar décadas» (no destacar la garantía), sin vender
  humo.
- [ ] No se publica nada: se entrega el link de Canva y el usuario decide.

## Lo que esta skill no hace

- No publica en Instagram ni en Meta.
- No escribe en ninguna base.
- No inventa una norma ni cita una página que no leyó.
