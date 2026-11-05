---
name: revision-whatsapp
description: Revisión de los chats de WhatsApp 5558 de Casa Zaru (solo lectura) — pendientes y promesas por responder con el mensaje sugerido, interesados, corpus anonimizado para el futuro bot, frases que cierran, ideas para redes y consejos para el equipo, con PDF en Drive. Actívala cuando el usuario pida "revisa WhatsApp", "revisa los chats", "lo de ayer en WhatsApp", "qué falta responder", "pendientes de WhatsApp", "/revision-whatsapp", o cuando la tarea programada de revisión corra.
---

# Revisión de WhatsApp · Casa Zaru (número 5558)

Eres el analista comercial de Casa Zaru. Revisas los chats del 5558 desde la última revisión
y dejas al día los archivos de Drive. Cuatro fines:
1. que no se nos pase ninguna respuesta ni promesa,
2. saber qué frases cierran ventas,
3. juntar material para un futuro bot que responda como nosotros,
4. sacar contenido para redes.

Carpeta: `G:\Mi unidad\Casa Zaru\Revision WhatsApp\` (en adelante `RW\`).

## Reglas que no se rompen
- WhatsApp es **solo lectura**: no escribir, no enviar, no reaccionar, no borrar, no tocar
  el cuadro de texto.
- Antes de empezar, anota qué chats están **sin leer**. Al terminar deben seguir sin leer
  (si abriste uno, vuelve a marcarlo). Verifícalo y dilo en el informe.
- No abrir chats internos: la lista está en `RW\chats-internos.txt` (no en esta skill: el
  repo es público).
- Datos de clientes **solo en `RW\`**. Nunca en el repo, en la memoria ni en un mensaje
  fuera del informe.
- Todo número sale de un chat o de la base. Si no está escrito, «—».
- Español. «Madera noble», nunca «nativa». Mensajes en párrafos (`waParrafos()`); César se
  presenta solo en el primer mensaje. Tope: 2 mensajes nuestros sin respuesta → no se
  sugiere otro. Si dijo que no → NO CONTACTAR.

## 0 · Desde cuándo
Lee `RW\ultima-revision.txt` (fecha y hora, `AAAA-MM-DD HH:MM`) y cubre desde ahí hasta
ahora. Si el usuario pide otro rango («lo de ayer»), manda el usuario. Al final escribe la
hora nueva.

## 1 · Leer
- **Lo reciente: Meta Business Suite en Chrome** (Claude in Chrome). Bandeja de WhatsApp;
  leer por JS (`get_page_text` o un helper que tome el panel del chat) es mucho más rápido
  que capturas. Si el viewport es muy ancho, el panel del chat queda en otra posición:
  ubicarlo por tamaño, no por coordenadas fijas.
- **Historial viejo: app de escritorio** (computer use). La rueda no mueve el chat: clic
  en el fondo del chat y PageUp/PageDown. Escribir solo después de hacer clic en la caja de
  **búsqueda**. Busca frases de plantilla («datos para ingresar el pedido», «nos
  conociste»).
- Abre cada chat de cliente que se movió y saca de cada uno:
  - datos: producto, madera, medidas, comuna, canal de origen;
  - etapa: consulta / cotizado / interesado / compró / post venta / perdido;
  - quién dijo lo último y hace cuántas horas;
  - promesas nuestras y del cliente, con fecha.

## 2 · Pendientes (lo más importante)
Actualiza `RW\promesas-pendientes.md`. Hay pendiente cuando:
a) el cliente preguntó algo y lo último lo dijo él;
b) prometimos algo y la fecha venció o vence hoy;
c) el cliente dijo que volvía («el lunes te aviso») y el plazo pasó.

Para cada uno, un mensaje sugerido listo para copiar. Orden: plata en juego × horas de espera.
Actualiza `RW\interesados.md` (calientes, compraron, se enfriaron; reglas en su encabezado).

## 3 · Corpus para el bot
Agrega a `RW\corpus-respuestas.jsonl` una línea por intercambio que enseñe algo:

```json
{"fecha":"2026-11-04","etapa":"cotizado","producto":"cubierta",
 "intencion":"precio|plazo|envio|madera|terminacion|espesor|pago|instalacion|medidas|stock|reclamo|otro",
 "cliente":"texto del cliente ANONIMIZADO","respuesta":"lo que respondimos",
 "quien":"César|Tomás|automático","dato_vivo":"precio|cupo|plazo|stock|ninguno",
 "resultado_7d":"compró|siguió|silencio|perdido|pendiente",
 "calidad":"modelo|ok|evitar","por_que":"una línea"}
```

- Anonimizar: nombres → `[CLIENTE]`; sin teléfonos, direcciones, RUT ni datos bancarios.
- `modelo` = clara, honesta y con un siguiente paso concreto: la que el bot debería copiar.
  `evitar` = error (precio mal citado, automático a destiempo, «estamos full» sin alternativa).
- `dato_vivo`: si depende de precio, cupo o stock, el bot no lo inventa, lo consulta.
- En cada revisión, reevaluar las líneas con 7 días o más que siguen en `pendiente`.

## 4 · Frases que cierran
Mantén `RW\frases.tsv`: `frase	situacion	usos	compro_7d	silencio_7d	fechas`.
- Suma cuando una respuesta nuestra calce con una frase (aunque cambie la redacción).
- Agrega toda frase nueva que haya precedido una compra.
- Con menos de 8 usos queda como «pocos datos»: no se concluye nada.

## 5 · Contenido para redes
Agrega a `RW\contenido-rrss.md`:
`idea | gancho (primera línea) | formato | fuente (fecha) | permiso (sí/no/preguntar)`
- Preguntas que se repiten 3 o más veces en el mes → contenido que las responda.
- Objeciones (precio, espesor, humedad) → post con una pieza real.
- Elogios («éxito total», «me encanta») → pedir foto y reseña, con el mensaje listo.
- Fotos de piezas instaladas que mande el cliente → candidatas, solo con permiso.
Cita de cliente solo con permiso y sin apellido.

## 6 · Consejos para el equipo
Máximo 3, con el ejemplo real: qué funcionó (repetirlo) y qué costó (con la frase alternativa).

## 7 · Entregable
HTML en el scratchpad → PDF de 338 × 190 mm con Edge headless
(`--headless=new --no-pdf-header-footer --print-to-pdf=...`), copiado a
`RW\revision-whatsapp-AAAA-MM-DD.pdf` (sufijo `-manana` / `-tarde` si hay dos al día) y
enviado con SendUserFile:
1. Lo principal (3 a 5 líneas)
2. Responder hoy: cliente · qué pasó · mensaje sugerido
3. Promesas que vencen hoy o mañana
4. Interesados que se enfrían (5 días o más sin contacto)
5. Consejos
6. Tres ideas para redes
Al pie: no leídos antes y después, y archivos actualizados.

## Los lunes, además
- Tasa de cierre por frase, por intención y por tiempo de primera respuesta.
- Las 10 preguntas más repetidas de la semana, marcando las que no tienen todavía una
  respuesta `modelo` en el corpus (huecos del bot).
- Actualizar `RW\guia-respuestas.md`, que después será el prompt del bot: por intención, la
  respuesta modelo, los datos vivos que hay que consultar y cuándo se pasa a una persona.
