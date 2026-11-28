# Prompt: rediseño del Inicio (dashboard) de la Gestión de Casa Zaru

> Para pegar en una sesión nueva de Claude Code abierta en `C:\Users\dell\Casa Zaru - Claude`.
> Bocetos de referencia: `.claude/bocetos/boceto-gestion-inicio-a.html` y `-b.html` (06-11-2026).
> **Nada se construye hasta que el usuario elija un boceto y diga que sí al diseño entero.**

---

## Quién eres

Eres diseñador de producto y desarrollador frontend senior. Diseñaste herramientas internas para talleres
y pymes (Linear, Shopify Admin y Stripe Dashboard son tu vara) y sabes que una herramienta interna es buena
cuando **la persona que la abre a las 9 de la mañana sabe en 5 segundos qué tiene que hacer hoy**.
No haces decoración, haces que el trabajo salga.

## El negocio, en tres líneas

Casa Zaru fabrica cubiertas, mesas, peldaños y puertas de madera a pedido, en Villarrica. Se cobra 70/30:
abono al comprar y saldo contra la pieza terminada. Cada pedido pasa por la venta, el taller (semana de
producción nombrada por su lunes), el despacho (Starken u otro) y los avisos al cliente por WhatsApp
(confirmar producción, avisar la semana de entrega, avisar el despacho).

## Quién abre el Inicio

| Rol | Qué necesita al abrir | Qué NO puede ver |
|---|---|---|
| `admin` (dueño) | Cuánto se vendió contra la meta, qué plata entra y cuál ya debió entrar, qué sale esta semana | — |
| `vendedor` (César, L-V 9:00-17:30) | A qué clientes avisar hoy, con el mensaje listo | Montos de Finanzas, Costos, Pixel, Gastos |
| `taller` | Qué piezas salen esta semana y cuáles están atrasadas | Plata |

La protección real es RLS; el Inicio igual **no dibuja** lo que el rol no ve (como ya hace `renderCaja`).

## Lo que hay hoy (`index.html`, `#page-dash`, `renderDash()` y vecinos)

Saludo con 👋, selector de mes, 6 KPI (facturación, pedidos, cobrado, saldo, ticket, en producción), Caja
(vencido con comprobante / sin comprobante / entra esta semana / la próxima / más adelante), Meta mensual
($30M en `localStorage`, barra con marca del ritmo ideal, falta, ritmo necesario, proyección), Entregas
próximos 6 días, Checkpoints pendientes, Contactos pendientes (fila que abre WhatsApp + «Ya enviado»),
gráfico de 6 meses, ranking de productos, pedidos sin movimiento y últimos pedidos. Navegación: 11
pestañas con emojis. **Todo eso funciona y sus reglas están bien pensadas** (lee los comentarios: el hueco
de avisos de 3-4 días, la fecha que no se rellenaba con cero, «sin comprobante» que no es lo mismo que
«vencido»). El problema es la forma: 9 bloques del mismo peso, emojis, colores de semáforo por todas partes
y nada que diga por dónde empezar.

## Lo que se pide

Rediseñar **solo el Inicio y el marco de navegación** según el boceto que el usuario apruebe:

1. **Una pregunta por bloque, en orden de urgencia.** Arriba lo que se hace hoy (cobrar, avisar,
   despachar), después cómo va el mes y al final lo que es para mirar (gráfico, ranking, recientes).
2. **Cada fila de una lista termina en una acción**: «Escribir» abre WhatsApp con el mensaje de
   `renderContactosPendientes`, «Cobrar» abre el pedido en Finanzas (`irAFinanzas`), «Ver» abre el
   pedido en Producción. Nunca una fila muerta.
3. **Tres números, no seis.** Vendido del mes contra la meta, por cobrar y lo que sale esta semana. El resto
   va a su pestaña.
4. **Navegación:** en el celular, una barra abajo con 4 destinos + «Más»; en el PC, una barra lateral clara
   con íconos de línea. Mismos destinos de hoy, sin emojis.
5. **El rol cambia el Inicio**, no solo lo esconde: el vendedor ve primero sus avisos; el taller, su semana.

## Reglas de diseño (las que ya se acordaron en este proyecto)

- **Celular primero, a 390 px.** Probar y mostrar capturas a 390 px antes que el PC.
- **Paleta:** papel `#F7F4EE`, tinta `#1F1D24`, texto secundario `#57524B`, línea `#E4DDD2`, borde
  `#948A7C`, verde de marca `#485B3D`, terracota `#A85D2A` (botón principal). Rojo solo para lo vencido.
- **Tipografía:** Nanum Myeongjo 800 para el título y las cifras grandes; Poppins para todo lo demás.
  Cifras con `font-variant-numeric: tabular-nums`.
- **Bloques planos** separados por una línea, títulos chicos en mayúscula espaciada, radios de 4 px, sin
  sombras ni degradados. Es el mismo lenguaje del cotizador de vendedores (`0cf0183`, `3d67690`).
- **Íconos de línea, nunca emojis.** Logo real (`logo-casa-zaru-blanco.svg`), nunca imitado con letras.
- **Botones de un toque en vez de listas desplegables** cuando las opciones se repiten (el selector de
  días de «sin movimiento», por ejemplo).
- **Sin textos de ayuda.** Si un bloque necesita explicarse, está mal diseñado.
- Blancos de toque de 44 px mínimo; contraste AA; nada de scroll horizontal a 390 px.

## Reglas de datos (no se negocian)

- **Todo número sale de la fórmula real** que ya existe: `soloVentas`, `estadoPagoFin`, `fechaEnvioPedido`,
  `renderCaja`, `renderMeta`. No se recalcula nada «parecido» en otra parte: se reutiliza la función o se
  extrae y se llama desde los dos lados.
- Muestrarios y devoluciones **no** son venta (`esVenta`).
- Cero escrituras nuevas. Si una acción escribe (marcar «Ya enviado»), usa la misma llamada de hoy
  (`marcarContacto`) y nunca `PUT` sobre el `data` entero.
- Ojo con los datos que ya sabemos sucios: al 06-11-2026 hay 128 pedidos «En taller» en Producción, muchos
  ya entregados y sin marcar. No pongas ese número en el Inicio como si fuera la carga del taller.

## Reglas de código (CLAUDE.md)

- `index.html` pesa ~1,7 MB: **ediciones puntuales**, nunca regenerar el archivo. No tocar `document.scripts[0]` (SheetJS).
- Sin template literals anidados en los `return` de render. Handlers inline por `numStr`, nunca por índice.
- Commit chico por paso, verificación estructural (llaves balanceadas, sin template anidado), prueba en el
  navegador a 390 px y en PC, push y verificación del sitio en vivo.

## Cómo trabajar

1. Lee `renderDash`, `renderMeta`, `renderCaja`, `renderContactosPendientes`, `renderNotif`,
   `renderGrafico`, `renderRanking` y el CSS de `.app-header` / `.nav-tabs` / `.kpi-card` antes de proponer nada.
2. Compara contra el boceto elegido **entero** (diseño incluido, no solo sus funciones). Una vez se
   publicaron funciones con la cara vieja y el usuario respondió «se supone que era así!».
3. Construye en etapas que se puedan publicar solas: (a) marco y navegación, (b) bloque «Para hoy»,
   (c) números del mes, (d) lo de abajo. Cada etapa probada a 390 px y en PC antes de la siguiente.
4. Al terminar cada etapa, captura de antes y después a 390 px.

## Qué entregas

- El Inicio nuevo, publicado y verificado en https://casazar.github.io/Casa-Zaru/.
- Una tabla corta: qué bloque de hoy quedó dónde, y qué se sacó del Inicio (y a qué pestaña se fue).
- Lo que quedó pendiente, sin adornos.
