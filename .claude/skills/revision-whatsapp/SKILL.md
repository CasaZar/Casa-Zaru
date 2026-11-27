---
name: revision-whatsapp
description: Revisión de los chats de WhatsApp 5558 de Casa Zaru (solo lectura) — pendientes y promesas por responder con el mensaje sugerido, interesados, corpus anonimizado para el futuro bot, frases que cierran, ideas para redes, conteos de quién escribe y «10 minutos con César» (auditoría de vendedor senior), publicado en «Mi día» de la Gestión (sin PDF). Actívala cuando el usuario pida "revisa WhatsApp", "revisa los chats", "lo de ayer en WhatsApp", "qué falta responder", "pendientes de WhatsApp", "/revision-whatsapp", o cuando la tarea programada de revisión corra.
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
- **Además, todo chat que quede con respuesta pendiente (tipo `responder` del paso 8) se deja
  marcado como no leído**, aunque estuviera leído al empezar (pedido del usuario, 19-11-2026): así
  César lo ve en negrita. «Marcar como no leído» es el ícono del sobre en la cabecera del chat.
  Ojo: si al entrar Meta abre solo un chat, ese también se revisa.
- No abrir chats internos: la lista está en `RW\chats-internos.txt` (no en esta skill: el
  repo es público).
- Datos de clientes **solo en `RW\`**. Nunca en el repo, en la memoria ni en un mensaje
  fuera del informe.
- Todo número sale de un chat o de la base. Si no está escrito, «—».
- **Plata: siempre con captura.** `innerText` no trae imágenes, y los comprobantes son
  imágenes. Antes de decir «pagó», «no ha pagado» o «falta $X», subir en el chat hasta la
  cotización o el resumen y mirar con captura cada imagen desde ahí. Si no se pudo ver todo,
  se escribe «no vi el resto del chat», nunca «falta». (08-11: dos clientes quedaron como
  impagos y habían pagado.)
- Español. «Madera noble», nunca «nativa». Mensajes en párrafos (`waParrafos()`); César se
  presenta solo en el primer mensaje. Tope: 2 mensajes nuestros sin respuesta → no se
  sugiere otro. Si dijo que no → NO CONTACTAR.

## 0 · Desde cuándo
**Desde el 08-11-2026, una revisión al día que cubre el día anterior COMPLETO** (decisión del
usuario): todas las conversaciones que se movieron ayer, de 00:00 a 23:59, más lo que haya
llegado hoy hasta la hora de la revisión. Si la última revisión es más vieja que ayer a las
00:00, se cubre desde la última revisión: **nunca se deja un rato sin mirar**.
Lee `RW\ultima-revision.txt` (fecha y hora, `AAAA-MM-DD HH:MM`); el inicio es lo que sea
anterior entre esa hora y ayer a las 00:00. Ese inicio va como `p_desde` al subir al panel
(paso 8): si entre dos revisiones queda un hueco, el Historial del panel lo muestra en rojo.
Si el usuario pide otro rango, manda el usuario. Al final escribe la hora nueva.

**Desde el 27-11-2026 hay una revisión programada cada hora** (lun-vie 8:00 a 18:00 y sábado 8:00
a 14:00; tareas `revision-whatsapp-horas` y `revision-whatsapp-1230`, que ahora es la del sábado;
del 26-11 eran 5 al día). El panel del cotizador relee los pendientes solo cada 5 minutos, así que
César los ve sin recargar. En esas corridas el inicio es **solo
`ultima-revision.txt`** (no ayer 00:00), para no releer lo ya revisado; si ese archivo es de antes
de ayer, igual se cubre desde ahí. Reparto:
- **Todas:** pendientes y promesas (2), corpus (3), fichas de venta (6c), avisos de envío (6d),
  panel (8), Mi día (7) y los no leídos.
- **Avisos de envío (6d) en TODAS las pasadas, siempre completos** (pedido del usuario, 26-11-2026):
  la consulta de la Gestión, el chat de cada pedido de la ventana y la clasificación se rehacen en
  cada corrida, aunque no se haya movido ningún chat (un aviso que vence a las 14:00 no aparece si
  se copia el de la mañana). Nunca «no los rehíce en esta pasada». Si un pedido ya quedó `ok` en
  una pasada anterior de hoy y su chat no se movió, se puede arrastrar sin reabrirlo, diciéndolo.
  Si no hubo movimiento, igual se corre 6d y se actualizan `avisos-envio.md` y Mi día.
- **Solo la primera del día** (la de las 8:00, o la primera que corra): conteos del día anterior
  (6b), «10 minutos con César» (6), frases (4) e ideas para redes (5). Las demás los arrastran
  sin rehacerlos en `mi-dia-whatsapp.json`.
- Si no se movió ningún chat desde la última revisión: correr igual los avisos de envío (6d);
  el resto no se toca, se actualiza `ultima-revision.txt` y se dice «sin movimiento».
- Corrida sin nadie mirando: nada se escribe en la Gestión (las casillas `sin_marcar` quedan
  propuestas en Mi día) y nunca se escribe en WhatsApp.

## 1 · Leer
- **Lo reciente: Meta Business Suite en Chrome** (Claude in Chrome). Bandeja de WhatsApp;
  leer por JS (`get_page_text` o un helper que tome el panel del chat) es mucho más rápido
  que capturas. Si el viewport es muy ancho, el panel del chat queda en otra posición:
  ubicarlo por tamaño, no por coordenadas fijas.
- **Lector en una pasada (desde el 26-11-2026): `lector-meta.js`** (en esta carpeta; solo lee,
  no escribe nada en WhatsApp).
  1. Entrar por esta URL, que abre la pestaña de WhatsApp en un chat de cliente ya leído
     y NO abre solo un chat sin leer (`/inbox/all` sí lo hace, y `/inbox/whatsapp` va al inicio):
     `https://business.facebook.com/latest/inbox/wec?asset_id=362710543582828&business_id=362752910245258&selected_item_id=1302850209569422&thread_type=WEC_MESSAGE&mailbox_id=362710543582828`
  2. Leer el archivo con Read y pegarlo entero en `javascript_tool`: deja `window.Z`.
  3. `await Z.lista('<inicio ISO>')` → cuántos se movieron y cuántos sin leer; `Z.leidoAntes`
     es la lista de no leídos ANTES de abrir nada. `Z.resumenLista(0)`, `(1)`… los muestra.
     Los chats con hora «Mié/Ayer» (sin hora) entran siempre: mejor de más que de menos.
  4. `await Z.leerTodos({saltar:[…internos y proveedores…]})` y luego `Z.pagina(0)`, `(1)`…
     (900 caracteres cada una: `javascript_tool` corta a ~1000). Cada chat trae teléfono, id,
     las últimas líneas de antes del corte y todo lo nuevo; si dice «no llegué al corte», subir
     a mano. Usar `await` al nivel de arriba, no dentro de `(async()=>{})()` (devuelve `{}`).
  5. Comprobantes y fotos: `Z.ver('texto cercano')` + captura (las imágenes no salen en el texto).
  6. Al final: `await Z.marcarNoLeido(nombre)` para cada uno de `Z.leidoAntes` y cada `responder`;
     `await Z.noLeidos()` para verificar. Si devuelve «NO SE PUDO», `find` «Marcar como no leído»
     y clic por ref.
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
 "calidad":"modelo|ok|evitar","por_que":"una línea",
 "hora_cliente":"2026-11-08T19:09","hora_respuesta":"2026-11-09T09:40","espera_habil_min":40}
```

- **Horas (desde el 10-11-2026):** `hora_cliente` = hora del mensaje del cliente que abre el
  intercambio; `hora_respuesta` = hora de nuestro primer mensaje después de ese (no el
  automático de Meta). Hora de Chile, como la muestra Meta. Si todavía no respondimos,
  `hora_respuesta` = null y `espera_habil_min` = null (se completa en la revisión siguiente).
- **`espera_habil_min`** = minutos de espera contando **solo el horario de atención publicado**
  (el que dice la respuesta automática del 5558): lunes a viernes 9:00-18:00 y sábado
  10:00-14:00; domingos y feriados no cuentan. Si cambia la respuesta automática, cambia esto.
  Ejemplo: escribe el domingo 19:09 y respondemos el lunes 9:40 → 40 min (no 14 h 31 min).
  Si escribe dentro del horario, corre desde que escribió; si escribe fuera, corre desde la
  apertura siguiente. Si respondimos fuera de horario antes de la apertura → 0.

- Anonimizar: nombres → `[CLIENTE]`; sin teléfonos, direcciones, RUT ni datos bancarios.
- `modelo` = clara, honesta y con un siguiente paso concreto: la que el bot debería copiar.
  `evitar` = error (precio mal citado, automático a destiempo, «estamos full» sin alternativa).
- `dato_vivo`: si depende de precio, cupo o stock, el bot no lo inventa, lo consulta.
- En cada revisión, reevaluar las líneas con 7 días o más que siguen en `pendiente`.

### Subir lo aprendido a la bandeja de mensajes (desde el 19-11-2026)
El corpus ya no es solo «para el futuro bot»: los borradores de la bandeja (WhatsApp +56 9 9305 1122,
`cotizador.casazaru.cl/mensajes.html`) usan las respuestas `modelo` y `evitar` como ejemplo. **Al
terminar de actualizar el corpus, en cada revisión**, correr:

`powershell.exe -NoProfile -ExecutionPolicy Bypass -File .claude/skills/revision-whatsapp/subir-conocimiento.ps1`

- Sube las líneas `modelo` y `evitar` (las `ok` no) y `guia-respuestas.md`. Repetirlo no duplica; una
  línea reevaluada se actualiza. Con `-Simular` solo cuenta.
- El script **no sube** una línea con algo que parezca teléfono, correo, RUT o link: si avisa «Con
  posible dato personal: N», anonimizar esas líneas en el corpus y volver a correr.
- Quita los signos de apertura (¡ ¿) al subir, porque en la bandeja están prohibidos; el corpus de
  Drive no se toca. Por eso al marcar una línea como `modelo` no importa que César los haya usado.
- Si falla, no frena la revisión: anotarlo en la sección de WhatsApp de «Mi día» y seguir.
- Detalle del sistema: `.claude/bandeja-mensajes.md`.

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
Si una idea también sirve para un correo o un anuncio, agregarla como una línea en
«Candidatos» de `RW\temas-marketing.md` (fecha, idea, evidencia): el lunes se decide si pasa a
ficha (ver «Los lunes»).

## 6 · 10 minutos con César (auditoría de vendedor senior, desde el 12-11-2026)
Pedido del usuario: auditar las respuestas como un vendedor senior y dejarle a César consejos
que se lean y practiquen en 10 minutos. Reemplaza los antiguos «consejos para el equipo».

**Qué se audita:** TODAS las respuestas de César del período (no solo las que van al corpus),
con esta pauta:
1. **Velocidad:** `espera_habil_min`. Comprobantes de pago y clientes listos para pagar van
   primero en la cola; un cliente que pagó no espera horas.
2. **Descubrir antes de cotizar:** uso (interior/terraza/restaurante), medidas, comuna, para
   cuándo, y lo que el producto exige (mesas: sillas por lado y su ancho; repisas: herraje).
3. **Respuesta que calza:** la plantilla se adapta a lo que dijo el cliente (si dice terraza, no
   va el texto de interior). Nada técnico se afirma sin saberlo («sí, soporta»).
4. **Dato correcto:** plazo 7 a 15 días hábiles + tránsito, precios del cotizador, condiciones
   de venta. Sin «vender humo».
5. **Siguiente paso:** cada mensaje termina con UNA pregunta de sí o no o pidiendo el dato que
   falta (comuna, madera, abono).
6. **Cierre:** cuando el cliente está listo, pedir el abono con monto y fecha de producción.
7. **Malas noticias primero:** si una fecha se corre, avisar ese día con la fecha nueva, antes
   de que el cliente pregunte. Toda promesa lleva día.
8. **Forma:** se presenta en el primer mensaje, párrafos, sin «al tiro», «madera noble».

**Qué se entrega** (se lee en 10 minutos; tono de colega con experiencia, directo, sin retar):
- **Lo que repetir (1):** un caso real del período que salió bien y por qué.
- **Lo que cambiar (2):** caso real → qué costó → la frase mejor, lista para copiar.
- **Ejercicio de hoy (1):** algo de 2 minutos para practicar en el turno (p. ej. «antes de
  mandar cada cotización, revisa que termine en una pregunta»).
- **La cifra:** mediana de `espera_habil_min` del período y cuántas respuestas terminaron con
  siguiente paso, contra la revisión anterior.
Sin nombres de clientes (producto y situación). Un consejo no se repite más de 3 revisiones
seguidas salvo que siga pasando. Se guarda en `RW\coaching-cesar.md` (fecha, puntos, cifra)
para ver si mejora.

## 6b · Conteos del día (desde el 12-11-2026)
Para saber cuánta gente escribe. Una línea por **día calendario completo** (el «ayer» que cubre
la revisión; el rato de hoy se cuenta en la revisión siguiente) en `RW\conteos-diarios.csv`:
`dia,chats,nuevas,en_conversacion,clientes_pedido,fuera_horario,sin_responder,mediana_espera_min,revision`
- `chats`: chats de clientes con al menos un mensaje del cliente ese día (sin internos ni
  proveedores).
- `nuevas`: de esos, los que escribieron por primera vez (el hilo no tiene nada antes).
- `en_conversacion`: ya habían escrito antes y no tienen pedido.
- `clientes_pedido`: con pedido en la Gestión (compró o post venta).
  (`nuevas + en_conversacion + clientes_pedido = chats`.)
- `fuera_horario`: cuántos escribieron fuera de L-V 9-18 / sáb 10-14.
- `sin_responder`: al cierre del día, cuántos tenían lo último dicho por el cliente.
- `mediana_espera_min`: mediana de `espera_habil_min` de las respuestas de ese día (vacío si no
  hay datos). Si el día ya tiene línea, se reemplaza, no se duplica.
Solo números: ningún nombre ni teléfono en este archivo. Es solo el 5558 (el 0141 no se revisa).

## 6c · Fichas de venta para el cruce de datos (desde el 16-11-2026)
Pedido del usuario: que lo conversado con el cliente no se pierda al cargar el pedido (dirección de envío
distinta de la de facturación, RUT, madera, medidas, envío). Por cada chat que en el rango quedó en etapa
**compró** (cerró la venta: mandó sus datos para ingresar el pedido o el comprobante), dejar una ficha en
`RW\fichas-venta.json` (arreglo JSON, UTF-8 sin BOM). Si ya hay una ficha con el mismo `telefono` y `fecha`,
se reemplaza; las de más de 30 días se sacan. Formato:
```json
{"telefono":"+56 9 ...","cliente":"Nombre Apellido","fecha":"AAAA-MM-DD","producto":"cubierta de cocina",
 "madera":"Raulí","medidas":[{"largo":340,"ancho":120,"cantidad":1}],"total":1407858,
 "envio":{"direccion":"","comuna":"","ciudad":"","monto":null},
 "doc":{"tipo":"boleta|factura","rut":"","razon":"","giro":"","direccion":"","comuna":""}}
```
- `fecha` = el día en que cerró. Medidas en centímetros. `total` = lo acordado con envío incluido; `envio.monto`
  = solo el envío.
- **Solo lo que está escrito en el chat.** Lo que el chat no dice va vacío o `null`: un campo vacío no se
  compara. Nunca completar con lo que diga la Gestión o el Cotizador (eso anula el cruce) ni deducir.
- `doc.direccion` solo si el cliente dio una dirección de facturación distinta de la de envío.
- Si el cliente corrigió un dato más abajo en el chat, vale el último.
- Este archivo sí lleva dirección y RUT (es el dato que se cruza): vive solo en `RW\`, nunca en el repo, en
  `mi-dia-whatsapp.json` ni en el panel del cotizador.
La corrida de las 07:30 (`.claude/cerebro/cruzar-dia.ps1`) lo compara con el pedido de la Gestión y muestra
las diferencias en Mi día → «Cruce de datos». Acá no se compara nada.

## 6d · Avisos de envío: Gestión × Starken × chat (desde el 23-11-2026)
Pedido del usuario: controlar todos los días que a cada cliente se le avisó su envío. Hoy las casillas
de Seguimiento (`aviso_sem`, `aviso_lun`, `aviso_dia`, `comprobante`) las marca César a mano y nada
comprueba que el mensaje salió: el 23-11, de 9 envíos del 16 al 22-11 solo 2 tenían `aviso_dia` y
`comprobante`. **Regla: un aviso cuenta solo si el mensaje está en el chat.**

1. **Qué tocaba avisar (Gestión, MCP de solo lectura).** Pedidos con `dia_envio` entre hace 7 días y
   pasado mañana:
   ```sql
   select p.num, p.data->>'dia_envio' dia, p.data->'checks' checks, f.data->>'celular' cel,
          f.data->>'nombre' nombre, f.data->>'apellido' apellido,
          coalesce(e.of_numero::text, pr.data->>'of_starken') of_num, e.estado of_estado, e.created_at of_emitida
   from gestion_pedidos p
   left join gestion_finanzas f using(num) left join gestion_produccion pr using(num)
   left join lateral (select of_numero, estado, created_at from envios_starken s
                      where s.pedido = p.num and s.anulada_at is null order by created_at desc limit 1) e on true
   where p.data->>'dia_envio' ~ '^\d{4}-\d{2}-\d{2}$'
     and (p.data->>'dia_envio')::date between current_date - 7 and current_date + 2
   order by dia;
   ```
   Ventanas (las mismas de `AVISOS` en `index.html`): `aviso_sem` de −9 a −5 días del envío,
   `aviso_lun` de −4 a −2, `aviso_dia` de −2 a −1, `comprobante` de 0 a +1. Solo se exige lo que ya venció.
   Muestrarios, post venta y retiros en taller también se revisan: el cliente igual necesita saber cuándo.
2. **Qué salió de verdad (Starken PRO, si el usuario lo dejó abierto en Chrome).** Con la misma pestaña
   y el mismo acceso que usa la skill `revision-starken` (su `revisar.js` ya consulta las OF), anotar
   por OF el estado y la fecha de admisión. Si Starken PRO no está abierto o pide clave, saltarse este
   punto y decirlo en el resumen; nunca escribir la clave.
3. **Qué recibió el cliente (chat del 5558).** Abrir el chat por el celular de Finanzas y buscar
   NUESTROS mensajes desde la cotización: semana o fecha de envío (`aviso_sem`/`aviso_lun`), «sale
   mañana» o el día (`aviso_dia`), y el N° de OF, el link de seguimiento o la foto del comprobante
   (`comprobante`). Anotar fecha y hora del mensaje. Un mensaje que el cliente no ve (borrador en la
   caja de texto) no cuenta. Si no se pudo ver todo el chat, «no vi el resto del chat», nunca «no avisó».
4. **Clasificar cada pedido:**
   - **ok**: el aviso que tocaba está en el chat y la casilla marcada.
   - **sin_marcar**: está en el chat pero la casilla no. Se propone al usuario marcarla (lista con N° y
     qué casilla); se escribe solo con su ok, releyendo el pedido y mandando el objeto `checks` COMPLETO
     en el PATCH (PATCH mezcla solo el primer nivel).
   - **no_avisado**: la ventana venció y no hay mensaje. Va al panel (paso 8) como `tipo: 'promesa'`,
     prioridad 40-44 (comprobante y «sale mañana» primero), `pedido` = N°, `contexto` «Envío del DD-MM
     sin avisar: falta <aviso>», y `mensaje` con la fecha y, si hay, el N° de OF (dato que falte entre
     corchetes). Si la casilla estaba marcada sin mensaje, decirlo en el contexto: es el caso más grave.
   - **starken_no_calza**: salió sin OF en la Gestión, OF sin admitir pasado el día de envío, OF anulada
     con el pedido marcado como enviado, o fecha de admisión distinta del `dia_envio`. No va al panel de
     César: va al resumen y a `principal` de Mi día.
5. **Guardar** en `RW\avisos-envio.md` (Drive, nunca el repo) una tabla por revisión: pedido, cliente,
   día de envío, OF, qué tocaba, qué se vio en el chat (fecha/hora), clasificación. Arrastrar los
   `no_avisado` hasta verlos cumplidos, igual que las promesas.
6. **En Mi día**: una línea en `principal` («Envíos: N ok · N sin marcar · N sin avisar · N Starken no
   calza»), y los `sin_marcar` y `starken_no_calza` con su detalle en `promesas` (título = N° de pedido).

## 7 · Entregable: sección «WhatsApp» de Mi día (desde el 12-11-2026, YA NO hay PDF)
El usuario lo quiere en línea y solo para él: va en la Gestión → **Mi día**, que desde la
migración 0031 lee solo su cuenta dueña (ni hola@ ni César). Nada de PDF ni SendUserFile.
1. Escribir `RW\mi-dia-whatsapp.json` (reemplaza el anterior; UTF-8 sin BOM):
   ```json
   {"revision":"<ISO con -03:00>","cubre":"<texto corto: «miércoles 11-11 completo»>",
    "conteos":{"dia":"mié 11-11","chats":0,"nuevas":0,"en_conversacion":0,"clientes_pedido":0,
               "fuera_horario":0,"sin_responder":0,"mediana_espera_min":0},
    "serie":[{"dia":"29-10","chats":0,"nuevas":0}],
    "principal":["3 a 5 líneas"],
    "promesas":[{"titulo":"cliente o pedido","detalle":"qué","cuando":"hoy|mañana|DD-MM|esperando"}],
    "enfrian":[{"titulo":"…","detalle":"último toque y cuántos van"}],
    "cesar":{"cifras":[{"v":"1 h 43","l":"espera mediana"}],"repetir":"…",
             "cambiar":[{"titulo":"…","caso":"…","frase":"«…»"}],"ejercicio":"…"},
    "ideas":["tres ideas para redes"],"pendientes":0}
   ```
   - `conteos` = la línea del día de `RW\conteos-diarios.csv` (6b); `serie` = sus últimos 14 días.
   - `cesar` = lo de la sección 6, igual que en `coaching-cesar.md`.
   - `pendientes` = cuántos chats quedaron cargados en el panel (paso 8).
   - Puede llevar nombres de clientes (Mi día es privado), nunca RUT, teléfonos, direcciones ni
     datos bancarios. Lo que no se sepa: `null` o fuera, nunca inventado.
2. Publicar: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .claude/cerebro/publicar-whatsapp.ps1`
   Lo mete en el día más reciente de `Cerebro\dias\` y lo publica con la misma Edge Function de
   Mi día (`cerebro-dia`). La corrida de las 07:30 lo vuelve a copiar en el día nuevo
   (`componer-dia.ps1 -WhatsApp`), así que la sección no se pierde. Si responde `SIN_TOKEN` o
   `ERROR`, decirlo en el resumen.
3. Al usuario, en el chat: 3 a 5 líneas (lo principal + qué responder hoy) y «está en Mi día».
Los «Responder hoy» con su mensaje sugerido siguen yendo al panel del cotizador (paso 8), que es
donde César los responde.
Al pie: no leídos antes y después, y archivos actualizados.

## 8 · Subir los pendientes al panel («WhatsApp al día»)
Desde el 08-11-2026 lo de la sección 2 también aparece en el panel del cotizador
(`cotizador.casazaru.cl/?panel=…`), en el bloque «WhatsApp al día», **separado** del
seguimiento de cotizaciones y fuera de la meta del día. Lo ven solo el admin y César.
Requiere que `supabase-cotizador/whatsapp-al-dia.sql` esté aplicado (comprobarlo con el MCP
de solo lectura: `select to_regclass('public.whatsapp_pendientes')`). Si no está, saltarse
este paso y decirlo en el informe.

Cómo se sube (una sola llamada, después de escribir los archivos de Drive):
- Abrir el panel en el Chrome del usuario, que tiene la sesión del admin, y en la consola:
  `await sbClient.rpc('wa_cargar', { p_revision: '<hora de la revisión, ISO>', p_desde: '<inicio
  del paso 0, ISO>', p_filas: [...] })`.
  `p_revision` es la hora real en que terminó la lectura: una hora futura la rechaza la base.
  Solo el admin puede cargar. Mostrar al usuario el resumen que devuelve
  (`nuevos / actualizados / ya_resueltos / cerrados` y `cerrados_quienes`).
- **Va la lista COMPLETA de lo pendiente**, no solo lo nuevo: el chat que no viene se da por
  cerrado. Si César lo marcó respondido después de `p_revision`, se respeta su marca.
- **Freno** (`supabase-cotizador/whatsapp-al-dia-historial.sql`, 08-11): si la carga cerraría
  más de la mitad de lo pendiente (y más de 3), falla con «FRENO…», dice cuáles y no aplica
  nada. No se repite con `p_forzar: true` sin antes abrir cada uno de esos chats y confirmar
  que de verdad se respondió; decirle al usuario cuáles eran. Tampoco acepta una revisión más
  vieja que la última cargada.
- Cada carga queda en `whatsapp_revisiones` y en el panel (WhatsApp al día → Historial), junto
  con todo lo cerrado en 30 días y quién lo cerró. Después de subir, abrir el Historial y
  confirmar que la revisión aparece y que no hay aviso rojo de hueco.
- Una fila por chat:
  `chat_id` (id del hilo en Meta, estable entre revisiones) · `cliente` (nombre de pila y
  apellido como aparece) · `telefono` (solo dígitos con 56; obligatorio, ver abajo) · `tipo` · `prioridad` ·
  `espera_desde` (hora del último mensaje del cliente, ISO) · `contexto` (una línea: qué pasó)
  · `cita` (lo último que dijo, ≤ 400) · `mensaje` (el sugerido: párrafos separados por
  `\n\n`; todo dato que no sepamos va entre corchetes, `$[total]`, y el panel no deja
  enviarlo hasta que se complete) · `monto` (entero, solo si sale de un chat o de la base) ·
  `pedido` (N° de la Gestión si es cliente).
- `tipo` y `prioridad` (menor = más urgente):
  - `responder` 10-39: el cliente preguntó y lo último lo dijo él. Ya pagó o es post venta
    10-19 · le prometimos algo para hoy 20-29 · el resto 30-39, más arriba cuanto más espera.
  - `promesa` 40-59: algo que prometimos y vence (sin pregunta pendiente del cliente).
  - `plata` 60-79: el cliente dijo que pagaba o volvía; no hay que escribirle, solo mirar si
    llegó (sin `mensaje`).
- **No se suben**: chats con NO CONTACTAR, los que ya tienen 2 mensajes nuestros sin
  respuesta (tope), chats internos ni proveedores.
- **Teléfono: obligatorio en toda fila** (regla del usuario, 18-11-2026: «siempre debe tener
  el celu»). Cada hilo del 5558 es un número de WhatsApp, así que siempre existe: sacarlo del
  panel de contacto de Meta (columna derecha del hilo, «Detalles del contacto» / número bajo el
  nombre) al abrir cada chat, no al final. Solo dígitos con 56 (`56912345678`). Con él el panel
  arma «Responder» y «Abrir chat» (`whatsapp://send?phone=…`, abre la app del PC). Si Meta no
  lo muestra, cruzarlo con `cotizaciones.contacto` o con la Gestión por N° de pedido; un `null`
  es un error de la revisión: antes de cargar, contar las filas sin teléfono y, si hay alguna,
  volver a abrir esos chats. Nunca inventarlo ni sacarlo de un nombre parecido.
- Nunca se suben datos bancarios, RUT ni direcciones.

## Los lunes, además
- Tasa de cierre por frase, por intención y por tiempo de primera respuesta.
  Tiempo de respuesta = `espera_habil_min` (solo horario de atención): mediana de la semana,
  cuántos se respondieron en ≤ 30 min, ≤ 2 h y al día hábil siguiente, y compra a 7 días por
  tramo. Aparte, cuántos mensajes llegaron fuera de horario (dato para decidir turnos o un
  bot nocturno). Con menos de 8 casos por tramo: «pocos datos».
- Las 10 preguntas más repetidas de la semana, marcando las que no tienen todavía una
  respuesta `modelo` en el corpus (huecos del bot).
- Actualizar `RW\guia-respuestas.md`, que después será el prompt del bot: por intención, la
  respuesta modelo, los datos vivos que hay que consultar y cuándo se pasa a una persona.
  Desde el 19-11-2026 esa guía YA va dentro de las instrucciones de los borradores de la bandeja:
  después de actualizarla, correr `subir-conocimiento.ps1` (ver §3).

### Para Klaviyo, contenido y anuncios de Meta (desde el 09-11-2026)
Lo que se aprende en WhatsApp se convierte en campañas. Cada lunes, en `RW\temas-marketing.md`:

1. **Elegir 1 a 3 temas de la semana**, en este orden de fuerza:
   - lo que destrabó compras (corpus `compró` + `modelo`, `RW\voz-del-cliente\cierres-*.md`);
   - preguntas que se repiten 3 o más veces (las 10 de arriba);
   - objeciones (precio, plazo, espesor, humedad, «¿tienen tienda?»);
   - fallas nuestras que un aviso previo evita (qué revisar al recibir, cuándo llega).
   Para elegir un tema no hacen falta tasas: basta con que se repita. Antes de agregar uno,
   revisar que no esté ya en el archivo (si está, sumar la evidencia nueva a su ficha).
2. **Una ficha por tema**, con estas partes:
   - **Evidencia:** cuántas veces y en qué fechas, líneas del corpus o del estudio de cierres, y
     una cita anonimizada. Sin evidencia escrita no hay tema.
   - **Correo (Klaviyo):** segmento (suscritos sin compra · cotizó y no compró · clientes
     recientes · clientes antiguos), asunto y vista previa propuestos, ángulo en una línea y un
     solo botón al cotizador con `utm_source=klaviyo&utm_medium=email&utm_campaign=<tema>`.
     Las listas «Clientes Offline» y «Clientes WhatsApp» no reciben promociones (sin
     consentimiento). El texto final se escribe con `/copy-correos`.
   - **Contenido orgánico (redes):** formato (reel, carrusel, historia), gancho de la primera
     línea y qué hay que fotografiar o filmar en el taller. Si es para Cote, como misión con
     definición de «listo».
   - **Anuncio de Meta:** gancho, cuerpo y CTA; público (frío o remarketing); destino = el
     cotizador con `utm_medium=paid` (así el cotizador manda al WhatsApp de anuncios 0141, nunca
     al 5558); formato. Para armarlo a partir de material suelto, `todo-es-un-anuncio`.
   - **Fototeca:** una búsqueda de fotos para la ficha (p. ej. `vitrificado`). Probarla con
     `.claude\scripts\marketing-json.ps1 -Buscar "<q>"`: que traiga piezas que sirvan.
   - **Estado:** propuesto → boceto → aprobado → enviado o publicado → medido, con fecha.
3. **Medir lo que salió** (lunes siguiente): aperturas y clics en Klaviyo; cotizaciones con ese
   `utm_campaign` (columna `origen` de `cotizaciones`); ventas en la Gestión; y si la pregunta
   bajó en WhatsApp. Anotarlo en la ficha.

Reglas: nada se arma en Klaviyo ni en Meta sin boceto aprobado por el usuario (y nada se
programa, envía ni activa sin su sí explícito; el MCP de Meta está en solo lectura). Solo
datos que estén en la web, el cotizador o las condiciones de venta: «sin vender humo»,
«madera noble» y plazos de 7 a 15 días hábiles. Citas y fotos de clientes, solo con su
permiso y sin apellido. Ningún dato personal en este archivo: solo citas anonimizadas.
En el PDF del lunes, una sección «Para marketing» con los temas nuevos de la semana.

### Subir a la pestaña «Marketing» del panel (desde el 11-11-2026)
María José (marketing) trabaja desde la pestaña Marketing del panel del Cotizador, que lee
`marketing.json` del bucket PRIVADO `marketing` (lo leen solo `hola@` y ella). Después de
actualizar `temas-marketing.md`, `contenido-rrss.md`, `guia-respuestas.md` y el análisis del lunes:
1. `powershell -ExecutionPolicy Bypass -File .claude\scripts\marketing-json.ps1 -Salida <scratchpad>\marketing.json`
   Junta fichas, candidatos, ideas para redes, las 10 preguntas (SIN la columna de casos, que
   trae nombres) y `RW\reglas-marketing.md`, y elige 4 fotos por ficha del índice de la Fototeca
   (`Biblioteca\Clasificacion 2026-11\fototeca-datos.json`; si la Fototeca se republica, copiar
   ahí su `datos.json` nuevo).
2. Subirlo desde el Chrome del usuario, en `cotizador.casazaru.cl/?panel=zr25` con la sesión
   admin: `await sbClient.storage.from('marketing').upload('marketing.json', new Blob([texto],
   {type:'application/json'}), {upsert:true})`. Solo el admin puede subir.
3. Verificar: recargar el panel → Más → Marketing muestra la fecha del lunes.
Las reglas de la marca se cambian en `RW\reglas-marketing.md` (no en el código). Lo que va al
JSON no lleva datos personales, salvo los nombres de pila de la columna «fuente» de las ideas,
que solo se ven en el panel y nunca van en «Copiar para Claude».
