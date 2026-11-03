# Prompt: fichas de bases de fierro (mesa y banca) y marco de puerta

Armar en Shopify tres fichas nuevas con la **misma estructura y lógica que la ficha de cubierta
«boceto C»**, ya armada en la copia del tema «PRUEBA ficha cubierta 03-11» (id 192923336738). Su
código está en `.claude/tema/cz-ficha-cubierta.liquid` y el boceto en `.claude/bocetos/boceto-ficha-cubierta-c.html`
y `boceto-ficha-puerta.html`. Leerlos antes de empezar. Más adelante estas fichas se van a ofrecer
como **upsell** en la ficha de cubierta de mesa, de banca y de puerta. Ese upsell **no** se arma ahora,
pero todo se deja listo para que se pueda conectar.

## Reglas (no se negocian)
- **Primero un boceto a 390 px**, y solo con mi sí se construye. Construir en una **copia del tema**, nunca en
  el vivo. Publicar en vivo solo con mi ok explícito.
- **Números calculados, nunca de cabeza.** Todo precio sale de la regla escrita abajo, y se me muestra la tabla
  para aprobar antes de cargarla en Shopify.
- No borrar los 3 productos en borrador que ya existen. Si se reemplazan, quedan en borrador.
- El texto dice «madera noble del sur de Chile», **nunca «nativa»**. Antes de publicar, buscar «nativ». Íconos de
  línea, sin emojis.
- Las condiciones de venta van tal cual: envío aparte según comuna (o retiro en Villarrica), 7 a 15 días
  hábiles, 5 años de garantía, «lista para instalar» (nunca «incluye instalación»).
- Tema por GraphQL (`themeDuplicate`, `themeFilesUpsert`) desde la sesión de Chrome en admin.shopify.com.
  Cada archivo nuevo va primero a `.claude/tema/`, con commit y push.

## Estructura que se repite (la del boceto C)
Miga · banda café «Paga en 3 cuotas sin interés» · foto con miniaturas · tarjeta con:
1. **Primera opción como tarjetas con foto y precio** (en cubiertas es la madera).
2. **Segunda opción como botones con precio**, dentro de la caja «Medida estándar · Se compra aquí».
3. **Caja de compra**: resumen de lo elegido, precio, «o 3 cuotas sin interés de $X» (precio ÷ 3, hacia arriba),
   el botón del tema, «Envío según tu comuna. Calcúlalo aquí» y los 3 sellos (5 años · 7 a 15 días hábiles ·
   asesoría por WhatsApp).
4. Venti, medios de pago y «Calcula tu envío» (cz-envio), como hoy.
5. **«A tu medida»**, con dibujo de cotas y botón al cotizador, solo donde aplique.
6. Descripción con «Leer más» y desplegables (Tiempo de fabricación, Envíos, Garantía).
7. Barra fija en el celular: «Otra medida» + «Agregar · $precio».

`cz-ficha-cubierta` hoy exige una opción de **madera** y otra de **tamaño**, y se activa solo con
`template.suffix contains 'cubierta'`. Hay que generalizarlo (o sacar un snippet hermano) para que la primera
opción pueda ser **forma** o **madera** y la segunda **largo** o **tamaño**, sin romper las 5 cubiertas.
Después de cualquier cambio, volver a probar las 5 cubiertas y comprobar que mesas y puertas no cambian.

## 1) Base de fierro para mesa
- **Hoy**: 3 productos en borrador, tipo «Base de mesa», cada uno con 1 sola variante de $289.900:
  `base-de-fierro-armable`, `base-trapecio-armable-de-fierro-negro`, `base-x-armable-de-fierro-negro`.
- **Propuesta (confirmar conmigo)**: un solo producto «Base de fierro para mesa», con
  - opción 1 **Forma**: Trapecio / X / Rectangular (tarjetas con la foto de cada una, sacadas de los 3 borradores);
  - opción 2 **Largo de la cubierta**: «Hasta 240 cm» $289.900 / «Más de 240 cm» $319.900. Precio decidido el
    08-10-2026, igual para las 3 formas.
- Fierro negro, armable, 71 cm de alto. Peso en Shopify: **21,7 kg** (regla de pesos para Starken).
  Revisar si el precio o el peso cambia con el largo.
- «A tu medida»: no lleva caja propia. Para mesas de más de 240 cm, línea «¿Tu mesa es más larga? Escríbenos
  por WhatsApp» (el número 5558, el de la web).
- **Para el upsell después**: el largo de la cubierta elegida en la ficha de cubierta de mesa tiene que alcanzar
  para escoger solo la variante (≤240 / >240).

## 2) Base de fierro para banca
- No existe en Shopify. Precio del cotizador (03-11-2026, con IVA): **$189.900 por base de fierro de banca**.
- El cotizador además cobra «sobredimensionado» por banca: +$20.000 sobre 290 cm y +$40.000 sobre 340 cm (no se
  suman). Si aplica a la base suelta, las variantes de **Largo de la banca** quedan en: hasta 290 cm $189.900,
  de 291 a 340 cm $209.900, más de 340 cm $229.900. **Preguntarme antes** si ese recargo va en la base sola.
- Preguntarme: formas disponibles, alto, peso y fotos.
- Upsell después: en la ficha de mesa con bancas y en una futura ficha de banca.

## 3) Marco con endolado para puerta
- Puertas: la hoja se vende sin marco, bisagras, chapa ni manilla, pero «el marco sí se puede cotizar aparte».
- Producto: **marco con endolado, un solo producto** (marco 90×30 mm + endolado 12 × 2 cm).
- Regla de precio (acordada el 31-08-2026, por metro lineal, con IVA, tarjeta):
  **ml = 2 × alto + ancho**. Tramo medio (Ciprés, Castaño, Mañío) $65.000/ml; tramo alto (Coihue, Raulí, Lenga)
  $70.500/ml.
- Opciones con la misma lógica que la puerta: **madera** (tarjetas) × **tamaño** (las mismas 8 medidas de las
  puertas: 70, 80, 90 y 100 de ancho × 200 y 210 de alto). Precios calculados con esa regla:

| Medida | ml | Medio | Alto |
|---|---|---|---|
| 70 × 200 | 4,7 | $305.500 | $331.350 |
| 80 × 200 | 4,8 | $312.000 | $338.400 |
| 90 × 200 | 4,9 | $318.500 | $345.450 |
| 100 × 200 | 5,0 | $325.000 | $352.500 |
| 70 × 210 | 4,9 | $318.500 | $345.450 |
| 80 × 210 | 5,0 | $325.000 | $352.500 |
| 90 × 210 | 5,1 | $331.500 | $359.550 |
| 100 × 210 | 5,2 | $338.000 | $366.600 |

- **Preguntarme antes de cargar**:
  - si se redondea a precios terminados en 900;
  - cuánto vale en **Pino Oregón** (no tiene tarifa: en la cotización del 31-08 no había oregón);
  - si entra la variante puerta pesada (marco 90×40 + endolado 3 cm, $70.000 / $76.000 por ml);
  - si las granero (9 medidas) llevan marco.
- «A tu medida»: con dibujo de cotas (alto a cada lado + ancho arriba) y botón a `cotizador.casazaru.cl/?prod=puertas`.
- **Para el upsell después**: la madera y la medida de la puerta elegida tienen que coincidir con una variante
  del marco, para ofrecer «Agrega el marco» con un toque.

## Entregables, en este orden
1. Tabla de variantes y precios de las 3 fichas, para que yo la apruebe.
2. Boceto 390 px de cada ficha (en `.claude/bocetos/`).
3. Con mi sí: productos en Shopify **en borrador**, plantillas y snippet en una copia del tema, capturas a
   390 px, y la confirmación de que cubiertas, mesas y puertas siguen iguales.
4. Antes y después, y esperar mi ok para publicar.
