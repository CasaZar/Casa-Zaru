# Bandeja de mensajes (WhatsApp 0141 + Instagram)

Boceto aprobado el 18-11-2026: `.claude/boceto-bandeja-mensajes.html`.
Sin WhatsApp Web automatizado: solo las APIs oficiales de Meta (sin riesgo de baneo).
**Vive en el proyecto del COTIZADOR** (`cmxqorsyxoltrakxawro`), decidido el 18-11: César trabaja en ese panel y cada chat se cruza con su cotización. Leen el dueño y los vendedores activos (`mensajes_puede_leer()`); marketing no.

## Piezas
| Pieza | Dónde | Estado |
|---|---|---|
| Tablas, reglas y RLS | `supabase-cotizador/migrations/0004_bandeja_mensajes.sql` | **Aplicada 18-11** (verificada; reglas probadas 11/11) |
| Webhook + borradores + /conocimiento + /suscribir | `supabase-cotizador/functions/mensajes-webhook/index.ts` (un solo archivo) | **Desplegada 18-11**, Verify JWT apagado, **sin secretos** (rechaza todo) |
| Pestaña «Mensajes» en el panel de seguimiento del Cotizador | `C:\Users\dell\Cotizador` | Pendiente (etapa 1) |
| Subir corpus y guía del 5558 | paso nuevo en la skill `revision-whatsapp` + script PC | Pendiente |

## Reglas que viven en la base (no en el JS)
- Un mensaje nuestro que no salió de la bandeja (eco de la app del celular) = **César entró**: el chat
  pasa a `de_cesar` para siempre y los borradores pendientes caducan.
- En un chat de César, Claude **sigue sugiriendo** (pedido del 18-11), pero el borrador queda
  `para='cesar'`. La base **rechaza todo mensaje automático** en ese chat.
- Todo envío desde la bandeja lleva el nombre de quién lo aprobó.
- Webhook idempotente: `meta_id` único (Meta reintenta).

## Cómo aprende
1. **Del 5558:** la revisión diaria ya arma `corpus-respuestas.jsonl` (anonimizado, con `calidad`
   modelo/ok/evitar y `resultado_7d`) y los lunes `guia-respuestas.md`. Un paso nuevo los sube a
   `POST /mensajes-webhook/conocimiento`. Cada borrador del 0141 lleva la guía, 25 respuestas
   modelo y 8 errores a evitar. Si una línea se reevalúa (compró / silencio), se actualiza sola.
2. **Del 0141 (etapa 2):** cuando un humano edita un borrador antes de enviarlo, el par
   «lo que propuso Claude / lo que salió» entra como ejemplo (`bandeja_editado`), y las respuestas de
   César en sus chats como `bandeja_cesar`. Los lunes la revisión mide cuánto se edita por intención.
3. Un ejemplo malo se apaga con `activo=false`; no se borra.

## Etapa 0 — trámite con Meta (lo hace el dueño)
⚠️ **Decisión pendiente:** según la documentación revisada el 18-11 (fuentes de partners; confirmar
en la de Meta), la **coexistencia** (el 0141 sigue en la app del celular Y en la API) solo se activa
por *Embedded Signup* de un **Tech Provider o partner (BSP)**. Caminos:

- **A · Un BSP con coexistencia** (360dialog, Wati, etc.): lo más rápido; costo mensual del BSP.
  El webhook se apunta a esta función (formato Cloud API).
- **B · Casa Zaru como Tech Provider propio:** sin BSP, pero hay que pasar la revisión de la app de
  Meta (permisos avanzados `whatsapp_business_messaging` / `_management`) y Meta advierte que el paso
  es irreversible. Más lento e incierto.
- **C · 0141 solo en la API (sin coexistencia):** gratis y simple, pero el 0141 sale de la app del
  celular: César contesta solo desde la bandeja. Antes, exportar los chats del 0141.

Pasos comunes: verificar el negocio en el Business Manager; conectar Instagram (permiso
`instagram_manage_messages`) a la misma app; suscribir los campos `messages` y, con coexistencia,
`smb_message_echoes`; cargar los secretos listados al inicio de `index.ts`.

## Costos
- Responder dentro de 24 h desde el último mensaje del cliente: texto libre.
- Fuera de la ventana: solo plantillas aprobadas, pagadas por mensaje.
- Claude: un borrador por mensaje entrante; medir en la etapa 1.

## Lo que hay en Meta (revisado 18-11-2026, sesión de Cote, solo lectura)
- Negocio Casa Zaru (`362752910245258`) **verificado**.
- Cuentas de WhatsApp: «Casa Zaru» `3041222646093756` = 5558 (app, conectado, calidad alta, falta método
  de pago); «Casa Zaru - Manychat» `1323717016492821` = +56 9 9305 1122 (en la API vía ManyChat, socio
  ManyChat con acceso total); «Casa Zaru» `723376876737727` = sin acceso para Cote (probable 0141), 0 socios.
- Socios del negocio: ManyChat, Shopify by Meta, «Solutions Engineering Team» (sin revisar).
- Apps conectadas: ManyChat, Shopify. **Eliminadas: Clientify, Inbox, Kommo, Versu, WordPress App.**
- App propia del negocio: «ManejoTusAds» `1372396034822192` (admin: Cote).

## Camino elegido: D · el +56 9 9305 1122 (18-11-2026)
El usuario confirmó que el 1122 «quedó botado, no se usa». Ya está registrado en la Cloud API (vía
ManyChat), con nombre visible «Casa Zaru» y calidad alta. Se usa como número de la bandeja:
**sin coexistencia, sin BSP, sin tocar el 0141 ni el 5558.**

Pasos (cada uno con ok del usuario; los de Meta los hace él o se hacen en su Chrome con su ok):
1. Quitarle a ManyChat el acceso a la cuenta «Casa Zaru - Manychat» y desconectar la app ManyChat.
   Antes, mirar en ManyChat que no quede ningún flujo activo con ese número.
2. App de Meta (tipo Negocio) con el producto WhatsApp, enlazada a la cuenta `1323717016492821`.
   Ver si sirve «ManejoTusAds» o crear una propia («Casa Zaru Bandeja»).
3. Usuario del sistema con token permanente (permisos `whatsapp_business_messaging` y
   `whatsapp_business_management`) → secreto de la función, nunca al repo.
4. Registrar de nuevo el número con PIN de dos pasos propio (ManyChat pudo dejar uno; si no se sabe,
   se restablece desde el Administrador de WhatsApp).
5. Webhook de la app → `…/functions/v1/mensajes-webhook`, campo `messages`. `WA_PHONE_NUMBER_ID` = el del 1122.
6. Probar con un anuncio chico apuntando al 1122 antes de mover el resto.
7. Método de pago en la cuenta de WhatsApp (solo para plantillas fuera de 24 h).

Consecuencias para el diseño:
- Nadie tiene el 1122 en un celular: César contesta **desde la bandeja**. No habrá ecos
  `smb_message_echoes`; «César entró» pasa a ser un botón **Tomar chat** que fija `tomado_por`
  (la regla de la base sigue igual: chat tomado = nunca automático, borradores solo para él).
- Instagram va aparte, por la misma app (permiso `instagram_manage_messages`).

### Avance 18-11-2026 (noche)
- ManyChat: suscripción vencida, «Tu cuenta de WhatsApp está bloqueada». Sus registros muestran **37 mensajes
  entrantes al 1122 en las últimas 2 semanas que nadie recibió** (último hace ~5 días). Algo todavía manda gente
  a ese número; no está en el repo ni en el Cotizador. Buscar en anuncios antiguos, bio/links, Google.
- **Hecho:** quitado el acceso de ManyChat a la cuenta «Casa Zaru - Manychat» (queda con 0 socios).
- **No se pudo** quitar a ManyChat como socio del negocio: Meta lo bloquea mientras la cuenta publicitaria
  «Casa Zaru Ads» tenga saldo pendiente ($212.122 al 18-11). No hace falta para la bandeja.
- «ManejoTusAds» es una app de inicio de sesión (sin publicar, admin Cote): no sirve tal cual.
  La app de WhatsApp conviene crearla con la cuenta de Facebook del dueño, no la de Cote (quien la
  administra puede sacar tokens con acceso a los chats).

## Estado en Meta al 18-11-2026 (hecho con la sesión de Cote, con ok del dueño)
| Qué | Dato |
|---|---|
| App de Meta | **Casa Zaru Bandeja** · id `1678367953790415` · caso de uso WhatsApp · negocio Casa Zaru · **sin publicar** |
| Admin de la app | Cote (correo de contacto: el suyo). Falta agregar al dueño como administrador. |
| Política de privacidad de la app | `https://www.casazaru.cl/policies/privacy-policy` (guardada; responde 200) |
| Permisos de la app | `whatsapp_business_messaging` y `whatsapp_business_management`: «Listo para la prueba» (alcanza para activos propios; no hace falta revisión de la app) |
| Número | +56 9 9305 1122 · **phone number id `1190938267435299`** · Conectado · calidad Alta |
| Cuenta de WhatsApp | «Casa Zaru - Manychat» · **id `1323717016492821`** · 0 socios |
| Usuario del sistema | **Bandeja Mensajes** · id `61596650102866` · rol Employee · activos: la app (total) y esa cuenta (total). Nada más. |

No se creó ninguna cuenta ni número de prueba en el negocio (siguen las 3 cuentas de WhatsApp de antes).

⚠️ **NO TOCAR:** en la app → WhatsApp → Configuración hay un bloque «Cuenta de prueba · Eliminar tu negocio»
cuyo texto dice que elimina el portfolio comercial. No apretar «Eliminar» ahí.
⚠️ **NO TOCAR:** «Conviértete en proveedor de tecnología / Continuar registro» (irreversible, no se necesita).

### Lo que falta, en orden
1. **Supabase Cotizador:** aplicar `0004_bandeja_mensajes.sql` (SQL Editor, con ok) y desplegar la función
   `mensajes-webhook` (Via Editor, `index.ts` + `prompt.ts`, Verify JWT apagado).
2. **Secretos de la función** (los pega el dueño; nunca al repo ni al chat):
   - `META_APP_SECRET` → app → Configuración → Básica → «Clave secreta de la app» → Mostrar.
   - `META_VERIFY_TOKEN` y `CONOCIMIENTO_TOKEN` → dos textos largos al azar distintos.
   - `WA_TOKEN` → Usuarios del sistema → Bandeja Mensajes → **Generar token** → app «Casa Zaru Bandeja»,
     caducidad «Nunca», permisos `whatsapp_business_messaging` + `whatsapp_business_management`.
   - `WA_PHONE_NUMBER_ID` = `1190938267435299` · `WA_BUSINESS_ACCOUNT_ID` = `1323717016492821` (no son secretos).
   - `ANTHROPIC_API_KEY` (sin ella guarda mensajes pero no redacta).
3. **Webhook en la app** (WhatsApp → Configuración): URL
   `https://cmxqorsyxoltrakxawro.supabase.co/functions/v1/mensajes-webhook`, el mismo `META_VERIFY_TOKEN`,
   «Verificar y guardar», y suscribir el campo **messages**.
4. **Publicar la app.** Meta lo dice en esa misma pantalla: sin publicar solo llegan webhooks de prueba,
   nunca mensajes reales. Con la política de privacidad puesta no pide nada más.
5. **`POST …/mensajes-webhook/suscribir`** una vez (con `x-conocimiento-token`): engancha la app a la cuenta y
   lista qué apps reciben sus mensajes. Si aparece la de ManyChat, todavía escucha: avisar.
6. **Prueba:** escribirle al 1122 desde un celular propio y ver la fila en `mensajes` y su borrador.
7. Después: pestaña «Mensajes» en el panel, PIN de dos pasos propio, método de pago (solo para plantillas).

## Avance 18-11-2026 (noche, parte 2): Supabase del Cotizador
- **0004 aplicada** (pegada por Claude desde el Chrome del dueño, con su ok; texto comprobado por SHA-256 antes de
  ejecutar). Resultado: tablas 6 · RLS+FORCE 6 · policies 6 · triggers 14 · anon 0 · authenticated no escribe ·
  service_role inserta en las 6 · `schema_migrations` hasta 0004. Confirmado aparte por el MCP.
- **Reglas probadas** con `supabase-cotizador/prueba-0004-reglas.sql` (termina en error a propósito y deshace todo):
  «TODO OK, 11 de 11». Después, las seis tablas en 0 filas.
- **Función `mensajes-webhook` desplegada** (Via Editor; código idéntico al repo por SHA-256). Verify JWT apagado.
  Probada desde afuera sin secretos: GET 403, POST 500 «META_APP_SECRET sin configurar», rutas propias 500
  «CONOCIMIENTO_TOKEN sin configurar», PUT 405. Mientras no tenga secretos no guarda ni redacta nada.
- Canal en la base: `whatsapp` / `instagram` (ya no `wa0141`). Fuentes de ejemplos: `5558`, `bandeja_editado`, `bandeja_cesar`.
- Ojo al pegar por Chrome: el portapapeles falló (el dueño copió otra cosa en el medio y se pegó eso; la
  comprobación de hash lo frenó). Lo que sirve: pasar el texto en gzip+base64 por `javascript_tool`, descomprimir con
  `DecompressionStream`, comprobar el SHA-256 y recién ahí `monaco…setValue()` + Run en el mismo paso.
- En el SQL Editor quedó una consulta sin guardar con el script de prueba (inofensiva).

**Queda (en orden):** secretos de la función (los pega el dueño) → webhook en la app de Meta + campo `messages` →
publicar la app → `POST …/suscribir` → prueba escribiendo al 1122 → pestaña «Mensajes» en el panel.

### Secretos de `mensajes-webhook` al 18-11-2026 (noche)
Ya cargados: `ANTHROPIC_API_KEY` (existía en el proyecto), `WA_PHONE_NUMBER_ID`, `WA_BUSINESS_ACCOUNT_ID`.
Faltan (los pega el dueño): `CONOCIMIENTO_TOKEN`, `META_VERIFY_TOKEN`, `META_APP_SECRET`, `WA_TOKEN`.
Los dos textos al azar se guardan también en `%USERPROFILE%\.casazaru\conocimiento-token.txt` y
`meta-verify-token.txt` (el segundo se vuelve a pegar en el webhook de la app de Meta).
Cómo comprobar sin ver las llaves: POST sin firma debe dar 401 «firma» (hay `META_APP_SECRET`);
`/suscribir` sin token debe dar 401 «no autorizado» (hay `CONOCIMIENTO_TOKEN`).

### 18-11-2026 (noche, parte 3): llaves y enganche
- Las cuatro llaves quedaron en los secretos del Cotizador y comprobadas sin verlas: `CONOCIMIENTO_TOKEN`
  (200 con la del PC, 401 sin ella), `META_VERIFY_TOKEN` (la función devolvió el challenge), `META_APP_SECRET`
  (POST sin firma = 401 «firma») y `WA_TOKEN` (caducidad Nunca; se anula con «Revocar tokens» del usuario del sistema).
- `POST /suscribir` = 200, `success: true`. **Apps suscritas a la cuenta: solo «Casa Zaru Bandeja»** (ManyChat ya no escucha).
- Los dos textos al azar se crean/recopian con `.claude\bandeja-llave.ps1 -Nombre conocimiento-token|meta-verify-token`
  (nunca los muestra; si existen no los cambia). Se corre en la Terminal del dueño, no en la herramienta de Claude.
- Webhook en la app de Meta: URL ya escrita; falta pegar el token de verificación (lo pega el dueño) y «Verificar y guardar».
- Después: suscribir el campo `messages`, publicar la app y probar escribiendo al 1122.

### 18-11-2026 (22:25, hora de Chile): webhook verificado y app PUBLICADA
- Webhook de la app: URL de la función + token de verificación (lo pegó el dueño) → verificado (GET 200).
- Campo suscrito: **solo `messages`**. Meta envió su mensaje de ejemplo firmado y la función respondió 200
  (firma válida = `META_APP_SECRET` correcto); como el ejemplo trae otro número, no se guardó nada.
- **App publicada** (el botón ahora dice «Anular publicación»). Desde aquí los mensajes reales al 1122 se guardan
  y se les redacta un borrador. Nada se envía y todavía no hay pantalla para verlos: se miran por SQL
  (`mensajes_chats`, `mensajes`, `mensajes_borradores`) hasta construir la pestaña «Mensajes».
- ⚠️ Los registros de la función guardan la URL completa, y Meta manda el token de verificación en la URL: el
  `META_VERIFY_TOKEN` queda legible en los logs del proyecto (Claude lo vio al revisarlos). Ese texto solo sirve
  para el saludo inicial de Meta; no permite leer ni enviar nada. Rotarlo es opcional. Al consultar logs, cortar
  siempre la query: `splitByChar('?', event_message)[1]`.
- Falta: prueba real escribiendo al 1122, pestaña «Mensajes» en el panel, subir corpus/guía del 5558 por
  `/conocimiento`, PIN de dos pasos propio del número, agregar al dueño como admin de la app.

### 18-11-2026 22:27 · PRUEBA REAL OK
El dueño escribió «Hola, prueba» al 1122 desde su celular. En segundos: 1 chat (`whatsapp`, `por_aprobar`, con nombre,
teléfono y ventana de 24 h), 1 mensaje entrante y 1 borrador (`claude-sonnet-4-6`, `para='bandeja'`, revisión toda en
verde, saludo con la fórmula de la casa y sin signos de apertura). La llave de Anthropic del proyecto funciona.
Esa fila de prueba queda en la base (no se borra: es el primer registro real).
Siguiente trabajo: pestaña «Mensajes» en el panel de seguimiento (`C:\Users\dell\Cotizador`), etapa 1 = solo ver y copiar.

### 18-11-2026 22:35 · Pantalla «Mensajes» EN VIVO (etapa 1, solo lectura)
- `C:\Users\dell\Cotizador\mensajes.html` (commit 33c00fb del repo Cotizador) → https://cotizador.casazaru.cl/mensajes.html
  Página aparte del panel (como `mi-dia.html`) para no chocar con otras sesiones que editan `cotizador-clientes.html`.
  Falta el enlace desde el panel; hoy se entra por la dirección o desde la barra de `mensajes.html`.
- Qué hace: lista por estado (Por aprobar / De César / Esperando), chat, ventana de 24 h, borrador con la revisión
  de reglas y «Copiar borrador». Se actualiza sola cada 60 s. No escribe nada (RLS solo da lectura).
- Probada a 390 px con datos de mentira (`?local` + `mensajes-local.json`, que no se sube) y en vivo con la sesión
  del dueño: muestra el chat de prueba real con su borrador. Escape de HTML comprobado.
- **Límite real de la etapa 1:** el 1122 no está en ningún celular, así que «copiar» no alcanza para responder.
  Lo que hace útil la bandeja es la etapa 2: botón Enviar (ruta `/enviar` en la función, con la sesión del panel,
  que valida ventana de 24 h, tope de 2 toques y chat no tomado por otro) + botón «Tomar chat».

### 18-11-2026 23:03 · ETAPA 2 construida: Enviar con aprobación (falta la prueba real del dueño)
- **0006 aplicada** (`mensajes_envios`): reserva idempotente de cada envío; la base rechaza antes de enviar
  (ventana de 24 h, tope de 2 sin respuesta contando los que están saliendo, chat tomado por otro salvo el dueño,
  texto con `[PRECIO`, «nativa» como palabra entera, «al tiro», signos de apertura). Prueba `prueba-0006-reglas.sql`: 13 de 13.
- **Función redesplegada** (repo 589c969; idéntica por SHA-256): `/enviar` y `/tomar` piden la sesión del panel
  (token validado contra Auth; dueño o vendedor activo), CORS solo para `https://cotizador.casazaru.cl`.
  Sin sesión: 401. Flujo de `/enviar`: reserva → Meta → reserva «enviado» → fila en `mensajes` (autor `bandeja`,
  `enviado_por` = correo) → borrador `enviado` / `editado_enviado` → resto de pendientes `caducado`.
- **Candado de envío (cerrado por defecto):** variable `ENVIO_SOLO_CHATS=2` (el chat de prueba del dueño).
  Mientras no exista `ENVIO_ABIERTO=si`, a ningún otro chat se le puede enviar. Abrirlo SOLO con el sí del dueño.
- **Pantalla** `mensajes.html` (repo Cotizador a16e366, en vivo): borrador editable, Enviar con confirmación
  («No se puede deshacer»), Copiar, «Volver al borrador de Claude», «Tomar este chat» (con confirmación; no se deshace).
  El botón Enviar se apaga con su motivo si la ventana cerró, van 2 sin respuesta, es Instagram o el chat es de otro.
  La clave del envío se conserva mientras el texto no cambie: reintentar tras un corte no duplica.
  Probada a 390 px con `?local` (todo simulado): bloqueos, confirmación, envío, tomar.
- Pendiente de esta etapa: que el dueño apriete Enviar en su chat (id 2) y confirme que le llegó; después decidir
  cuándo abrir (`ENVIO_ABIERTO=si`). Sin método de pago en la cuenta de WhatsApp solo se responde dentro de 24 h.
- No hecho todavía: guardar como ejemplo las ediciones (`bandeja_editado`, hay que anonimizar), enlace desde el panel,
  cerrar/descartar chats, Instagram, plantillas fuera de 24 h, subir corpus/guía del 5558.

### 19-11-2026 00:15 · Prueba real del dueño OK + dos correcciones
- **Prueba real:** el dueño apretó Enviar en su chat (id 2) a las 23:56 y le llegó al celular. En la base: reserva
  `enviado` con id de Meta, mensaje `bandeja` a su nombre, sus respuestas entraron y el chat volvió a `por_aprobar`.
  Queda confirmado que dentro de las 24 h se responde sin método de pago en la cuenta de WhatsApp.
- **0007 aplicada (19-11):** el borrador usado queda `enviado` / `editado_enviado` aunque estuviera caducado
  (lo marca un trigger al pasar la reserva a `enviado`). Arregló la fila de la prueba. `prueba-0007-reglas.sql`: 4 de 4.
  Ojo: el clasificador de la app frenó el primer intento de aplicarla porque nadie la había pedido; toda migración
  nueva, por chica que sea, se le pregunta antes al dueño.
- **Pantalla (Cotizador 030a6f5):** Enviar relee el chat antes de abrir la confirmación; si llegó un mensaje nuevo lo
  muestra y avisa. Probado en `?local` simulando un mensaje que entra con la pantalla abierta.
- **Sigue cerrado:** `ENVIO_SOLO_CHATS=2`. Para abrir a clientes: variable `ENVIO_ABIERTO=si` (decisión del dueño).

### 19-11-2026 00:40 · Lo aprendido del 5558 ya alimenta los borradores
- Script `.claude/skills/revision-whatsapp/subir-conocimiento.ps1` (commit del repo de Gestión): lee
  `G:\Mi unidad\Casa Zaru\Revision WhatsApp\corpus-respuestas.jsonl` y `guia-respuestas.md` y los sube a `/conocimiento`.
- Primer cargue: 119 líneas en el corpus → **77 subidas (55 modelo, 22 evitar)**, 42 `ok` no se usan, 0 con posible
  dato personal, 28 respuestas con signos de apertura quitados. Guía: 1 versión (3.753 caracteres). Verificado en la
  base: 0 respuestas con ¡ ¿, 0 con «nativa», acentos bien.
- El paso quedó en la skill `revision-whatsapp` (§3, y los lunes tras actualizar la guía).
- Cada borrador lleva: la guía + hasta 25 modelo + hasta 8 evitar, tomados de las 40 filas más recientes.
  Mejora pendiente (pide redesplegar la función): pedir modelo y evitar por separado para que nunca falten los «evitar».
- Si una línea del corpus cambia de texto, entra como fila nueva y la vieja queda activa: revisar duplicados cada tanto
  (`activo=false` la apaga sin borrarla).
- Para ver un borrador hecho con lo aprendido hace falta un mensaje nuevo al 1122 (el pendiente del chat 2 es anterior).

### 19-11-2026 01:25 · Modo «conversar» para el dueño: respuesta automática SOLO en su chat
- Pedido del dueño: «quiero probarlo, lo dejas para conversar y que me responda». Función redesplegada (repo = desplegado,
  SHA-256 440ab025…) con `autoResponder`: tras redactar, si el chat está en **`AUTO_SOLO_CHATS`** (hoy `2`) y además en el
  candado de envío, el borrador sale solo como mensaje `automatico` (reserva con `por='automatico@bandeja'`).
- Frenos: mismas reglas de la base (0006), no sale si el borrador `necesita_humano`, `falta_precio`, trae palabra prohibida,
  el chat está tomado o no es WhatsApp; solo responde al ÚLTIMO mensaje del cliente; tope de 30 automáticos por hora.
- **No existe modo automático general.** Para apagar la prueba: borrar la variable `AUTO_SOLO_CHATS` (o dejarla vacía).
- **Antes de abrir lo automático a clientes (etapa 3):** falta la regla del dueño «una vez que entra a contestar César o yo,
  no respondas más esa conversación» aplicada a lo automático (hoy un envío humano desde la bandeja no «toma» el chat),
  los interruptores por tema del boceto y una decisión explícita suya.
- `contexto()` ahora pide `modelo` (25) y `evitar` (8) por separado.

### 19-11-2026 01:21 · El asistente manda catálogo y link del cotizador (Gestión 1bb6f18)
- **Por qué:** en la prueba del dueño un borrador decía «te mando algunas fotos» (el asistente solo escribe texto) y otro
  quedó con `[PRECIO…]` sin salir. El dueño: «Sí, enséñale».
- **Fotos:** nunca promete fotos. Si piden ver trabajos manda UN link de catálogo, copiado exacto (cubiertas, mesas,
  puertas, maderas; los 4 de Drive respondían 200). Producto sin catálogo (peldaños, repisas, especiales): `necesita_humano`.
- **Precios:** sigue sin escribir montos. Para cubierta, repisa, peldaño, puertas, mesa y revestimiento manda
  `https://www.casazaru.cl/cotizador?prod=<producto>&src=asistente` (redirige a cotizador.casazaru.cl conservando la query).
  Lo especial: pide medidas, comuna y plano, y `necesita_humano` («cotización especial»).
- **Dato para medir:** el cotizador público guarda `origen.src` y `origen.prod` de la URL, así que la cotización que el
  cliente haga desde ese link queda en `cotizaciones` con `origen->>'src' = 'asistente'`. Sale del único cálculo de
  precios (el del cotizador), sin copia en el servidor. `src` no está en ORIGEN_ANUNCIO: no la marca como anuncio.
- **Freno nuevo:** lista cerrada `LINKS_DE_LA_CASA`. Un borrador con cualquier otro link queda `links_ok=false` +
  `necesita_humano` («trae un link que no es de la casa») y no sale solo. Máximo dos links por mensaje (lo pide el prompt).
- `preview_url` encendido cuando el mensaje trae link.
- **Verificado:** editor antes = 440ab025… (df26c69), después y tras recargar = 782e788d…ca41 = archivo del repo.
  GET sin token 403, POST sin firma 401, `/enviar` sin sesión 401, `/conocimiento` sin token 401.
- **Falta:** que el dueño pruebe en su chat («tienen fotos de cubiertas», «cuánto sale una cubierta»); mostrar
  `links_ok` en la lista de chequeos de `mensajes.html`.
- **Pedido del dueño sin construir:** «deberíamos crear cotizaciones para que quede registrado que las hizo el bot».
  Con `src=asistente` ya queda la que el cliente termina. Lo que NO queda es a quién se le mandó el link y no cotizó
  (se puede contar desde `mensajes`: texto con `src=asistente`). Una cotización creada directo por el asistente exige
  calcular el precio en el servidor (otra copia de las fórmulas) o un link prellenado que hoy NO guarda (`#q=`):
  es etapa aparte, con boceto y su sí.

### 19-11-2026 07:51 · «El asistente cotiza»: construido, falta aplicar 0008 y desplegar la función
- Boceto aprobado (`.claude/boceto-asistente-cotiza.html`). El dueño sumó: puertas y mesas también; lo complicado
  (alturas que varían, formas raras) se cotiza aparte; quiere ver cuántos links se mandan y qué se cotiza.
- **Cómo funciona:** el modelo deja la marca `[LINK_COTIZACION]` y un objeto `cotizar`; la función revisa medidas
  (topes por producto), guarda fila en `mensajes_links` y cambia la marca por
  `casazaru.cl/cotizador?prod=<p>&c=<código>&src=asistente`. El cotizador llama `asistente_link_abrir` y rellena con
  `restoreProducto`. Cubierta/repisa/peldaños: directo a la cotización (se guarda al abrir). Puertas/mesas: medidas
  puestas, el cliente elige modelo y aprieta el botón. El teléfono nunca va al navegador: lo pone el trigger de
  `cotizaciones` desde el chat. Reabrir el link muestra la cotización ya hecha, no guarda otra.
- **Hecho:** Cotizador 8d577a6 EN VIVO (inerte sin la 0008: si el código no existe abre normal). Gestión 29251d7:
  `0008_asistente_links.sql` + `prueba-0008-reglas.sql` (9 puntos), SIN APLICAR. `index.ts` editado SIN desplegar ni commit.
- **Probado en local a 390 px con la base simulada** (sbClient.rpc/from reemplazados; no se guardó nada real):
  cubierta directa, puerta y mesa con medidas, mesa sin modelo frena, link ya cotizado reabre, código malo cae al normal.
- **Falta (con ok del dueño):** aplicar 0008 + correr la prueba; desplegar la función; prueba real en su chat.
- **Detalle a decidir después:** el botón de WhatsApp de la cotización lleva al 5558, no al 1122 del chat.

### 19-11-2026 08:04 · «El asistente cotiza» EN VIVO (solo en el chat de prueba)
- **0008 aplicada** (dueño: «Sí, aplica y despliega»). El editor avisó «tabla sin RLS / destructivo»: se corrió tal cual
  («Run without RLS»), porque el script activa RLS + FORCE él mismo. Verificado por MCP: tabla 1, rls_force true,
  funciones 4, trg_envios 5, trg_cotiz 1, anon abre sí, anon no lee la tabla ni el resumen, última 0008.
- **Prueba 0008: 9 de 9**, y después 0 links, 0 cotizaciones de prueba, 0 chats de prueba.
- **Función desplegada = repo** (SHA 5a471385…12ce). Editor antes 782e788d…, después y tras recargar 5a471385….
  GET 403, POST sin firma 401, /enviar sin sesión 401, /conocimiento sin token 401. Con la llave pública:
  abrir un código inexistente devuelve null; leer mensajes_links y asistente_resumen dan 42501.
- **Sigue cerrado a clientes:** ENVIO_SOLO_CHATS=2 y AUTO_SOLO_CHATS=2. Falta la prueba real del dueño en su chat.
- **Ojo al probar:** abrir el link de una cubierta GUARDA una cotización real a su nombre (queda con origen asistente).

### 19-11-2026 08:14 · Prueba real OK + espera de 2/5 min y envío en la cotización (a medio aplicar)
- **Prueba del dueño (08:06):** el asistente respondió con catálogo + link con código y salió solo. Tres fallas vistas:
  (1) usó 200 × 60 cm sin que el dueño diera medidas en ese momento (venían de mensajes viejos del chat);
  (2) dijo «el envío se cotiza aparte» y comentó la comuna («Vitacura lo tenemos cubierto»);
  (3) dos mensajes seguidos del cliente = dos borradores y dos links (uno quedó sin enviar).
- **Pedido:** que demore ~2 min, y 5 si prepara una cotización; al dar la comuna decir «Súper, actualizo la cotización»
  y cotizar también el envío.
- **Hecho y publicado:** Cotizador 793dbd4: el link puede traer la comuna (`d.com`, solo el nombre) y la cotización abre
  con el envío Starken (probado en local: Vitacura).
- **Escrito, SIN aplicar ni desplegar:** `0009_bandeja_espera.sql` (Gestión d9a1d38): `mensajes_borradores.auto_desde`
  + pg_cron/pg_net, tarea `bandeja-despachar` cada minuto que llama a `/despachar` solo si hay algo listo.
  `index.ts` (sin commit): agenda en vez de enviar (120 s, 300 s con cotización; AUTO_ESPERA_SEG / AUTO_ESPERA_COTIZA_SEG),
  ruta `/despachar` sin llave (no recibe datos; clave de reserva fija por borrador = sale una sola vez),
  `cotizar.comuna`, y reglas nuevas del prompt (solo medidas dichas en la conversación; envío en la misma cotización).
- **Orden obligatorio:** primero la 0009, después la función (sin la columna, la función nueva no agenda nada).
- Con la espera, la falla (3) deja de mandar doble: si entra otro mensaje, el borrador anterior caduca antes de salir.

### 19-11-2026 08:42 · Espera de 2/5 min y envío en la cotización: EN VIVO (solo chat de prueba)
- **0009 aplicada** (dueño: «Sí, aplica y despliega»): columna `auto_desde`, trigger de desagenda, pg_cron + pg_net,
  tarea `bandeja-despachar` activa cada minuto. Verificado por MCP.
- **Función desplegada = repo** (SHA ef8b8f84…36f6, Gestión, ver git log). `/despachar` sin nada agendado responde
  `{"ok":true,"listos":0,"enviados":0}`; GET 403, POST sin firma 401, /enviar y /conocimiento sin permiso 401.
- **Agregado a último minuto** (pantallazo del dueño, 08:32, aún con la versión vieja): el asistente pedía elegir la madera
  para cotizar el envío y enredaba el reborde. Reglas nuevas: para el envío basta la comuna; reborde, respaldo,
  perforaciones y teñido los suma una persona (manda la cotización de la pieza, pregunta en qué lados, y deriva).
- **Sin probar en real:** ningún mensaje pasó todavía por la espera. Para apagar la espera automática sin tocar la
  función: `select cron.unschedule('bandeja-despachar');` (los borradores quedan para aprobar a mano).
- **Pendiente de diseño:** el reborde existe en el cotizador pero solo para vendedores; si se quiere que el link lo
  incluya hay que abrirlo al público o dejar que el link lo traiga (boceto antes).

### 19-11-2026 09:14 · Aviso «voy a preparar tu cotización» + logo nítido en la vista previa
- **Prueba real de la espera OK:** mensaje del dueño 08:54:08 → respuesta con link y envío a Vitacura 09:00:04.
- **Pedido:** que primero diga que va a preparar la cotización y que la mande a los 3-5 minutos.
  Función desplegada = repo (SHA 44495229…97c1, Gestión, ver git log): aviso fijo `AVISO_COTIZA` sale al redactar
  (reserva `auto-aviso-<borrador>`, sin borrador_id), cotización agendada a 240 s; un aviso cada 15 min por chat.
  Ojo: aviso + cotización = 2 mensajes seguidos sin respuesta, que es el tope; después de eso no sale nada más solo
  hasta que el cliente conteste.
- **Logo borroso en la tarjeta del link:** og:image pasó de 200 a 299 px (Cotizador 999ab5c, archivo
  `fotos/logo-casa-zaru-og-299.png` hecho del de 600 con System.Drawing). Sigue bajo 300, queda como miniatura.
  WhatsApp guarda la vista previa por link: se ve en links nuevos.
- Sin probar en real el aviso.

### 20-11-2026 11:06 · Puntos aparte y uso de la cubierta
- Pedido del dueño: «que ocupe siempre puntos aparte y se vean algunas frases separadas» y «recuerda siempre preguntar
  también qué uso le quieren dar a la cubierta».
- Función desplegada = repo (SHA 59639b10…e674, Gestión, ver git log): `parrafos()` ordena en código (línea en blanco
  entre párrafos, máximo dos frases por párrafo; no toca líneas con link ni la marca) + regla en el prompt;
  en cubiertas pregunta siempre el uso (con medidas y comuna, o al cierre si ya salió la cotización).
- Verificado: /despachar 200 sin nada agendado; GET 403, POST sin firma 401, /enviar sin sesión 401.
- Sin ver todavía un mensaje real con el formato nuevo.
- Ojo: el asistente lee los últimos 30 mensajes del chat, sin tope de antigüedad. Ofrecido al dueño: ignorar lo que
  tenga más de unas horas para que cada conversación parta en blanco. Sin respuesta aún.

### 23-11-2026 09:48 · Estado antes de abrir al público + freno de persona (0011 escrita, SIN aplicar)
- **Estado:** flujo OK en el chat de prueba (20-11: aviso 10:59:32, cotización 11:04:03). Cron 1.440/1.440 en 24 h.
  5 links de cubierta enviados, **0 abiertos**: abrir/guardar/contacto desde el cotizador real sigue sin probarse.
- **6 chats de clientes reales sin responder** en el 1122 (ids 13, 26, 27, 31, 32, 33). 5 de 6 llegan del anuncio de Meta
  «Cubiertas de madera noble a medida» (source_id 1151942027210604, fb.me/55REHhMiP), que manda al 1122. 5 ya pasaron
  las 24 h (60 a 98 h) y no se les puede escribir sin plantilla; el 33 entró hoy 23-11 06:38 y vence mañana 06:38.
- **0011 escrita** (`0011_bandeja_freno_persona.sql` + prueba de 5 puntos): un envío desde el panel toma el chat.
  Ojo: al aplicarla, si el dueño usa Enviar en su chat de prueba (id 2), ese chat deja de responder solo para siempre.
- La 0010 del repo es del panel de campañas (otra sesión), sin aplicar; la 0011 no depende de ella.
- Link sin abrir para la prueba real del dueño: el de las 11:04 del 20-11 (cubierta 200 × 105, Vitacura).

### 23-11-2026 09:53 · 0011 APLICADA: si una persona responde desde la bandeja, el asistente se calla
- Dueño: «Sí, aplícala». Verificado por MCP: la función toma el chat con autor «bandeja»; 0 chats tomados (no cambió
  ninguno existente); registradas 0009 y 0011 (la 0010 de campañas sigue sin aplicar). Prueba 0011: 5 de 5, sin restos.
- **SIM del 1122 encontrada:** el dueño mandó foto de un celular con la SIM 2 «API +56993051122» activa (SIM 1 = 0141).
  NO registrar el 1122 en la app de WhatsApp ni WhatsApp Business de ese celular: lo sacaría de la API.
- El dueño pregunta si responder al chat abierto (id 33, vence 24-11 06:38) y dónde ver el WhatsApp del asistente
  (solo en cotizador.casazaru.cl/mensajes.html). Para responder a un cliente hay que ampliar ENVIO_SOLO_CHATS: decisión suya.

## 23-11-2026 · Envío abierto al chat 33 (Jose)

Con el sí del dueño: secreto `ENVIO_SOLO_CHATS` pasó de `2` a `2,33` (huella 20b8ddcf…, 13:55 UTC). `AUTO_SOLO_CHATS` sigue en `2` y no existe `ENVIO_ABIERTO`: en el 33 nada sale solo, solo con el botón Enviar. La ventana de Jose cierra el 24-11 06:38 (hora Chile). Para volver atrás: dejar `ENVIO_SOLO_CHATS` en `2`.

## 25-11-2026 · Avisos de la bandeja (0014)

Jose respondió el 23-11 a las 11:51 y nadie lo vio; su ventana cerró el 24-11 12:35. Boceto aprobado (`.claude/boceto-bandeja-avisos.html`).
- Página EN VIVO (Cotizador a9a7d3d): franja + sonido + «Quedan X h», consulta mínima cada 15 s, campana «Avisos», `mensajes-sw.js`, manifest e íconos.
- Gestión 1bc2aaf: migración `0014_bandeja_avisos.sql` SIN APLICAR, `prueba-0014-reglas.sql` (8 reglas), función con `/push` y `/avisos` SIN DESPLEGAR (sha256 24b4ee9a…). Desplegado sigue 59639b10….
- Cifrado RFC 8291 probado contra el ejemplo oficial: `.claude/prueba-push-cripto.html`, 12 de 12.
- Falta: ok del dueño para aplicar 0014 y desplegar; que él genere las llaves con `.claude/generar-llaves-avisos.html` y cree los secretos `VAPID_PUBLICA` y `VAPID_PRIVADA`; activar avisos en cada dispositivo y probar.
- Orden: 1) migración, 2) función, 3) llaves. Sin llaves la función no manda ni reserva avisos.

### 25-11-2026 · 0014 APLICADA y función desplegada

Migración aplicada en el SQL Editor (huella verificada), prueba 8 de 8 sin dejar filas. Función desplegada: sha256 24b4ee9aa2db03306081f31a7a34e6c7b0ef241d6e9ba4fc1b20accb3951b8e0 (repo = desplegado). `/avisos` responde `configurado:false` hasta que existan `VAPID_PUBLICA` y `VAPID_PRIVADA`. Puertas: GET 403, POST sin firma 401, /enviar /tomar /push sin sesión 401.
Falta: llaves (las genera el dueño), activar avisos en cada dispositivo y el aviso de prueba.

### 26-11-2026 · Llaves de avisos creadas

El dueño generó y pegó `VAPID_PUBLICA` y `VAPID_PRIVADA` (rotación: primera vez, 26-11-2026). `/avisos` ya responde con `tocan` (configurado). Falta: activar avisos en cada dispositivo y el aviso de prueba; todavía no se ha visto llegar una notificación real.

### 26-11-2026 · Aviso de prueba recibido

El dueño activó los avisos en su computador (Windows) y recibió la notificación de prueba: 4 pruebas, 4 entregadas. Falta activar en su celular y en los dispositivos de César. Aún no ha ocurrido un aviso por un cliente real (sin chats nuevos desde el 23-11).

### 26-11-2026 · Rediseño de Mensajes EN VIVO (Cotizador 514ed95)

Boceto aprobado: `.claude/boceto-mensajes-rediseno.html`. Grupos Responder / Esperando al cliente / Cerrados (calculados en la página), orden por urgencia, buscador, respuesta fija abajo, avisos solo cuando hay algo que revisar, «Escribirle desde mi WhatsApp» en chats cerrados, menú de tres puntos, dos paneles desde 900 px. Se quitó «Tomar este chat». Probado en local a 390 y 1280 px con datos de mentira; falta que el dueño lo vea con su sesión y datos reales.

### 26-11-2026 · Consulta de coexistencia enviada a YCloud

Correo enviado desde hola@casazaru.cl a service@ycloud.com (único correo publicado en ycloud.com), asunto «WhatsApp Coexistence + API for a Chilean number (+56): plan and pricing». Pregunta: Chile, si el plan gratis incluye coexistencia + API + webhook, cobros extra, medios de pago y portafolio de Meta existente. 360dialog no publica correo: solo chat wa.me/message/42YYE6GQTVMKK1 o llamada agendada; el texto quedó para que el dueño lo pegue desde su WhatsApp (pendiente).

### 26-11-2026 · Apertura para probar con el equipo + frases de la casa (EN VIVO 19:12 UTC)
- 26-11 noche, ajustes tras la prueba de las tres cubiertas (Gestión 26423dd, desplegado = repo, SHA 925e57b7…): varias piezas del mismo producto en una cotización; ancho recomendado si lo piden (vanitorio 50, cocina 60, escritorio 60); duda entre dos medidas = la primera; productos distintos = persona; corte «conversación anterior» si pasan 12 h (comuna de otro día se confirma); fotos/audios nombrados (no inventa archivos); un borrador que promete la cotización sin traerla queda para una persona.
- 26-11 noche, estilo César (Gestión 2242ff9, desplegado y verificado, SHA 7bbaa4e4…): saluda según la hora de Chile tras una pausa («Hola X, muy buen día. Cómo estás?»); «Te dejo la cotización de tu cubierta, con el precio en cada madera:»; cierre con plano para confirmar medidas, perforaciones para lavamanos/lavaplatos (baño/cocina) y «Para cuándo la necesitas?». En código: comuna que el cliente no escribió después del último corte de 12 h → borrador para una persona.
- 26-11 noche, «Devolver al asistente» NO funcionaba: el trigger mensajes_chat_no_destomar (0004) rechaza todo update con tomado_por null → /soltar daba 409. Arreglo: Cotizador 0018_bandeja_soltar.sql (af6b665), APLICADA 26-11 (permite_soltar true, registrada 1); deja soltar solo a service_role con estado por_aprobar y tomado_at null. Chat 2 devuelto al asistente.
- 26-11 noche, saludo «buen día, cómo estás?» UNA vez por día de Chile (Gestión 42633fa, desplegado y verificado, SHA 034f4ce7…): el modelo recibe si ya le escribimos hoy; si ya le escribimos y saluda igual, el código saca el saludo (SALUDO_DIA).
- 26-11 noche (27-11 UTC), «respondió algo nada que ver» (Gestión 67643cb, desplegado y verificado, SHA a226fabf…): con los últimos 30 mensajes el asistente veía las pruebas del 19-20/11 y preguntó por un «reborde», mandó «envío a Vitacura incluido» (borrador 54, ya enviado 02:18 UTC) y escribió «me confundí con otro cliente». Arreglo: lo de antes del último corte de 12 h va como «CONVERSACIÓN DE OTRO DÍA» (6 mensajes, solo referencia) y se responde a la «DE HOY»; candado fueraDeHoy → persona si nombra «reborde» o «envío a <Comuna>» que el cliente no dijo hoy, o frases raras («otro cliente», «soy un bot»); «Te preparo la cotización» sin link = promesa.
- 27-11, tiempos de respuesta (Gestión 7e21b29, desplegado y verificado, SHA 72bce6c3…): contados desde que llega el mensaje del cliente → saludo solo 30 s (AUTO_ESPERA_SALUDO_SEG), conversación 20-30 s al azar (AUTO_ESPERA_CHARLA_SEG), cotización: aviso inmediato y link a los 180 s (AUTO_ESPERA_COT_SEG; los nombres viejos AUTO_ESPERA_SEG/AUTO_ESPERA_COTIZA_SEG ya no se leen). Esperas ≤60 s las cumple la misma función (despacharUno) porque el cron corre cada minuto; la clave fija de la reserva evita doble envío. Candado PAGO_O_FECHA: anticipo, transferencia, cupos o «semana que viene» → persona (había inventado «el cupo más cercano, la semana que viene» y pedido «70 % de anticipo», este último caducó sin salir).
- Hecho el 26-11: 0017 aplicada + prueba «6 de 6»; función desplegada y verificada (sha256 bf56912e…34acc, 80.608 bytes); secretos `ENVIO_ABIERTO=si` y `AUTO_ABIERTO=si` (19:12 UTC); Cotizador 5b305b5 publicado. El chat 2 sigue tomado (de_cesar, 1 borrador pendiente) hasta que el dueño apriete «Devolver al asistente»: /soltar exige su sesión.
- Por qué el chat de prueba (2) no respondió solo: el dueño apretó Enviar a las 15:44 y eso lo tomó (0011). No había cómo devolverlo.
- Dueño: anuncios apagados; él, María José, Cristián y César escribirán al 1122 estos días. «Construye todo como quedaría», con lo aprendido del 5558 y un lugar para corregir frases fijas.
- Gestión 3c520bc: `0017_bandeja_frases.sql` (tabla mensajes_frases fija/preferida/evitar, 13 semillas), `prueba-0017-frases.sql` (6 reglas), función: frases en el prompt, «evitar» deja el borrador para una persona, aviso de cotización editable (clave aviso_cotiza), ejemplos «compró» primero (16 de 78 modelo), rutas /soltar y /frases, `AUTO_ABIERTO=si`.
- Cotizador 5b305b5 (commit LOCAL, sin push hasta desplegar): botón «Devolver al asistente», menú «Frases del asistente». Probado en local a 390 px.
- Para encender: aplicar 0017 + prueba, desplegar función (verificar sha256), secretos `ENVIO_ABIERTO=si` y `AUTO_ABIERTO=si`, push del Cotizador, devolver el chat 2. Para apagar: borrar `AUTO_ABIERTO` (y `ENVIO_ABIERTO`).
- Ojo: con eso abierto, también responde solo a los 6 clientes reales viejos si vuelven a escribir.
- 27-11, auditoría y lo que definió el dueño (Gestión 526be42 + fix del saludo; desplegado y verificado, SHA 027f9454…):
  - Horario: responde solo de 8:30 a 20:00 de Chile, todos los días. Fuera de horario sale al abrir (8:30 + 0-25 min al azar) y el saludo se escribe para esa hora. Una cotización nocturna sale con su aviso al abrir y el link 3 min después (`sacar()`).
  - Tiempos: saludo 30 s; conversación según lo largo (leer + escribir), entre 20 y 90 s; cotización: aviso a los 20-30 s y link a los 180 s. La función espera hasta 95 s. `AUTO_ESPERA_CHARLA_SEG` ya no se lee.
  - Pasa a César (no le escribe al cliente, push «Para César: <nombre>» con el motivo, etiqueta del chat): necesita_humano, audio, quiere pagar (`CLIENTE_PAGA`), producto que no hacemos (prompt), cliente antiguo (chat de más de 7 días, salvo `AUTO_SOLO_CHATS`), y plan B si Anthropic falla 2 veces (45 s de tope cada una) o no trae texto. Mientras nadie le conteste al cliente (y dentro del día), el asistente no se mete de nuevo en ese chat (`derivadoHoy`).
  - Saludo en 2 párrafos; 5 variantes del aviso de cotización (no repite una ya mandada al chat); «De dónde son» → «Estamos en Villarrica y hacemos entregas a todo Chile. Tú de dónde eres?»; el prompt ya no dice que un humano revisa cada borrador.
  - Los avisos llegan a todos los dispositivos con avisos activos en la bandeja: César tiene que activarlos en su celular. Tope de 2 sin respuesta: se ve en el panel (decisión del dueño).
