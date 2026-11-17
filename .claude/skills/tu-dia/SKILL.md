---
name: tu-dia
description: Cerebro Zaru — arma la pantalla diaria «Tu día» (qué no se puede pasar, pulso del negocio, qué decidir, mensajes para el equipo, una idea para crecer, deudas, semáforo por área) a partir de pendientes.csv, las planillas y las dos bases de Supabase en solo lectura, y la escribe en la página privada. Cierra antes el día anterior con lo que el usuario marcó. Actívala cuando el usuario pida "tu día", "/tu-dia", "arma el día", "qué tengo hoy", "qué se me está pasando", "el cerebro", o cuando corra la tarea programada de las 07:30.
---

# /tu-dia — Cerebro Zaru

Una corrida al día (lunes a sábado, 07:30, tarea programada «cerebro-tu-dia»). **Solo lee** las fuentes
de negocio: nunca escribe en Supabase, Shopify, Klaviyo, Meta ni Wasabil, y nunca manda mensajes (los
deja redactados para que el usuario los copie). Escribe solo en `G:\Mi unidad\Casa Zaru\Cerebro\` y en la
base de la página.

**El repo es público:** este archivo, los `.ps1` y los `.sql` no llevan nombres, montos ni teléfonos.
Todo lo que tiene datos vive en Drive (`Cerebro\`) o en la base privada de la página.

## Dónde está cada cosa

| Qué | Dónde |
|---|---|
| Dónde se ve | Gestión → pestaña **«Mi día»** (solo admin). Tablas `cerebro_dias` y `cerebro_marcas` del proyecto Gestión (migración 0030). La página aparte (artifact) se dio de baja el 11-11 |
| Inventario | `Cerebro\pendientes.csv`, `areas.csv`, `calendario.csv` |
| Áreas | 27 áreas en 5 grupos (`areas.csv` → columna `grupo`: vender, marketing, hacer, plata, base). Todo pendiente nuevo lleva un `area` que exista ahí; si no calza ninguna, preguntar antes de inventar una |
| Días armados (respaldo) | `Cerebro\dias\<fecha>.json` |
| Bitácora y cierres | `Cerebro\bitacora.md`, `Cerebro\cierres.txt`, `Cerebro\respaldos\` |
| Aprendizajes | `Cerebro\insights.csv` (`fecha,insight,evidencia,confianza`) |
| Deudas | `C:\Users\dell\Casa Zaru Planillas\cuotas-creditos.csv` y `por-pagar-manual.csv` (solo lectura) |
| Scripts | `.claude/cerebro/armar-dia.ps1`, `componer-dia.ps1`, `cerrar-dia.ps1`, `publicar-dia.ps1` |
| Consultas | `sql/gestion-pulso.sql` (MCP gestión), `sql/cotizador-pulso.sql` y `sql/cotizador-proyectos.sql` (MCP cotizador) |

Los `.ps1` se corren desde **Bash** con
`powershell.exe -NoProfile -ExecutionPolicy Bypass -File .claude/cerebro/<script>.ps1 ...`
(la herramienta PowerShell bloquea `G:\`). Rutas con `C:/...`, nunca `/c/...`. Archivos temporales en el
scratchpad.

## Dónde vive el día (Gestión, migración 0030)

- `cerebro_dias(fecha, data)` → el JSON que arma `componer-dia.ps1`. Lo escribe **solo** la Edge Function
  `cerebro-dia`, que llama `publicar-dia.ps1` con el secreto de `%USERPROFILE%\.casazaru\cerebro-token.txt`
  (nunca imprimirlo). La pestaña muestra la fecha más reciente.
- `cerebro_marcas(fecha, data)` → `{hechos:{id:true}, decisiones:{id:"hacer|delegar|matar"}, notas,
  encargos:{id:ISO}, actualizado}`. Lo escribe la pestaña cuando el usuario marca. **Claude solo lo lee**,
  con `mcp__supabase-gestion__execute_sql`: `select data from public.cerebro_marcas where fecha = '<f>'`.
- `encargos` = lo que el usuario tocó con «Resolver con Claude»: copió el encargo para pegarlo en una
  sesión. La corrida de las 07:30 **no los ejecuta** (nada de trabajo pagado por su cuenta): los lista en el
  resumen y, si el pendiente sigue abierto en `pendientes.csv` y lleva más de 2 días encargado, lo dice.

Si la función falla, el JSON igual queda en `Cerebro\dias\` y se dice en el resumen. **No hay respaldo en otra
página**: el artifact de antes se dio de baja el 11-11-2026.

## Procedimiento

1. **Cerrar el día anterior.** Tomar el último día armado (`select max(fecha) from public.cerebro_dias`). Si es
   anterior a hoy y no está en `cierres.txt`: leer sus marcas por el MCP y guardarlas en
   `<scratchpad>\marcas-<esa fecha>.json` (si no hay fila, `{}`), y
   correr `cerrar-dia.ps1 -Fecha <esa fecha> -Marcas <json>`. Es idempotente y respalda `pendientes.csv`
   antes de escribir. Las notas dictadas quedan en la bitácora: si alguna es un pendiente nuevo, agregarlo a
   `pendientes.csv` (siguiente `P###`, con respaldo previo) y decirlo en el resumen.
2. **Calcular.** `armar-dia.ps1 -Fecha <hoy> -Salida <scratchpad>\calc-<hoy>.json`. Saca alarmas (vence en
   ≤ 10 días), semáforo por área, lo fijo de 14 días, deudas, candidatos a decidir, equipo, salud de
   respaldos y tareas, y git sin commit.
3. **Pulso.** Correr `sql/gestion-pulso.sql` con `mcp__supabase-gestion__execute_sql` y
   `sql/cotizador-pulso.sql` con `mcp__supabase-cotizador__execute_sql` (nunca los dos proyectos en una
   consulta). Las cifras van **tal cual** salen: no redondear de cabeza ni recalcular. Si una consulta
   falla, esa cifra va como «sin dato» y la fuente a `fuentes_fallidas`.
   **Proyectos (desde el 14-11-2026):** correr también `sql/cotizador-proyectos.sql` con el MCP del
   cotizador. Son los clientes con $1,5 M o más abierto, que llama el dueño (panel del cotizador →
   pestaña «Proyectos»). Si `nuevos_24_h` o `sin_primer_contacto` es mayor que cero, va en `foco`
   («Llamar hoy a N proyectos nuevos por $X: panel → Proyectos»). Si `en_conversacion_sin_toque_72_h`
   es mayor que cero, va como `pulso.raro` cuando no haya algo más grave. Una de las `pulso.cifras`
   es «Proyectos vivos» (`vivos_30_dias`, con `vivos_30_dias_monto` en `comp`). Nunca nombres ni
   teléfonos: la lista con nombres vive en el panel.
   **Proyectos de la semana (desde el 17-11-2026):** correr también `sql/cotizador-proyectos-semana.sql`
   (MCP cotizador). Es el número 4 de los lunes: `contactados` (llamadas + «Lo contacté»), `propuestas` y
   `ganados` de la semana que empezó el lunes; es la misma cuenta que el panel (Proyectos y Actividad).
   Los lunes, correrlo también con la semana anterior (desfase −7 en la CTE `sem`) y mostrar las dos.
   **Cruce de datos (desde el 16-11-2026, etapa 1):** correr `sql/cotizador-cruce.sql` (MCP cotizador) y
   `sql/gestion-cruce.sql` (MCP gestión) y guardar cada resultado **tal cual** en
   `<scratchpad>\cruce-cotizador.json` y `<scratchpad>\cruce-gestion.json` (traen nombres y teléfonos:
   nunca al repo). Después:
   `cruzar-dia.ps1 -Fecha <hoy> -Cotizador ... -Gestion ... -Marcas <scratchpad>\marcas-<día anterior>.json -Salida <scratchpad>\cruce-<hoy>.json`.
   Marca las ventas ganadas en el Cotizador que no tienen pedido en la Gestión; lo que el usuario descartó en
   la pestaña (`marcas.cruce[id].accion = "descartar"`) pasa a `Cerebro\cruce-descartes.csv` y no vuelve a
   salir. El script decide qué calza: no corregir su lista a mano. Si `sin_pedido` es mayor que cero, va en
   `foco` con el monto que imprime el script. Si una de las dos consultas falla, no se pasa `-Cruce` y
   «Cruce de datos» va a `fuentes_fallidas`.
   **Etapa 3, chat contra pedido (desde el 16-11-2026).** No hay que pasar nada: el script lee solo
   `Revision WhatsApp\fichas-venta.json` (lo deja la skill `revision-whatsapp`, paso 6c) y lo compara con
   el `det` que trae `gestion-cruce.sql`. Avisa de la venta cerrada por chat sin pedido y de las diferencias
   de dirección, documento, madera, medidas, envío y total. **No abrir WhatsApp desde esta corrida**: si la
   última revisión tiene más de 2 días, la sección lo muestra sola.
   **Etapa 2, pagos (desde el 16-11-2026).** Antes de correr `cruzar-dia.ps1`:
   - **Avisos por correo.** Con el conector de Gmail (cuenta de la empresa), buscar los avisos de
     transferencia de los últimos 3 días: `newer_than:3d {subject:transferencia subject:"Itaú informa"
     "recibiste una transferencia"} -in:sent`. Los bancos mandan formatos distintos (BCI, Banco de Chile,
     Santander, Itaú, BICE, Falabella, Estado…): leer cada mensaje (`get_thread`, texto plano; un hilo de BCI
     junta varios) y quedarse **solo con la plata RECIBIDA** en las cuentas de la empresa. Fuera lo que la
     empresa envió («la transferencia se realizó con éxito», «Firmaste con éxito»), aunque esté en el mismo hilo.
     Escribir `<scratchpad>\pagos-nuevos.json`:
     `[{"fecha":"AAAA-MM-DD","hora":"HH:MM","monto":123456,"pagador":"...","rut":"12345678-9","comentario":"...","banco":"..."}]`
     (monto entero, sin puntos; `rut` y `comentario` vacíos si el aviso no los trae). Pasarlo con
     `-PagosNuevos`, **también si quedó vacío `[]`**: así la fuente figura revisada hoy. Si Gmail no está
     disponible, no pasar el parámetro: la sección muestra sola que los avisos están atrasados.
   - **Cartola.** Si en Descargas hay una `*Movimientos_Detallado_Cuenta_7175*.xlsx` más nueva que
     `cartola_leida` de `Cerebro\pagos-estado.json`, pasarla a CSV con
     `.claude/skills/conciliacion/scripts/leer-cartola-bci.ps1 -Salida <scratchpad>\bci.csv` y agregar
     `-Cartola <scratchpad>\bci.csv`. No pedirle la cartola al usuario: la sección ya avisa cuando tiene más de 7 días.
   El script suma todo a `Cerebro\pagos.csv` (cada pago una vez) y cruza los últimos 21 días contra los
   abonos: «Pagó y no hay pedido», «Pago sin marcar en Finanzas» y «Plata que entró y no sé de quién es».
   No ve Mercado Pago, Flow ni Venti (no mandan aviso por correo): eso sigue saliendo de la conciliación
   con cartola. Nunca marcar abonos desde la corrida: lo hace el usuario con el botón de la pestaña.
4. **Barrido de olvidos** (solo lectura, rápido): logs de tareas programadas de las últimas 24 h, último
   respaldo (si pasa de 36 h es alarma), promesas nuevas en `promesas-pendientes.md` de la revisión de
   WhatsApp si existe. Lo que aparezca y no esté en `pendientes.csv`, se agrega (con respaldo previo).
5. **Narrativa** (`<scratchpad>\narrativa-<hoy>.json`):
   - `foco`: una o dos frases con lo que no se puede pasar hoy.
   - `pulso.cifras`: `{k,label,valor,fmt:"plata"|"num",comp,tono:"bien"|"mal"|"igual",fuente}` (6 como
     máximo) y `pulso.raro`: lo único que se sale de lo normal, con su cifra.
   - `decidir`: hasta 4 de `candidatos_decidir`. Primero lo que tiene 5 o más saltos, después lo que lleva
     más días esperando. `porque` en una frase: qué cuesta seguir sin decidir.
   - `mensajes`: uno por persona de `equipo` (claves exactas: los nombres que trae `calc`). En párrafos,
     cortos, sin «al tiro». Son mensajes **del usuario** a su equipo; no se envían.
   - `crecer`: una sola idea **con evidencia en datos** (`id` de un pendiente existente o nuevo,
     `impacto` calculado). Si no hay una con respaldo, no inventar: `crecer` va `null`.
   - `fuentes_ok` / `fuentes_fallidas`.
6. **Componer.** `componer-dia.ps1 -Calc ... -Narrativa ... -Cruce <scratchpad>\cruce-<hoy>.json -Salida "G:/Mi unidad/Casa Zaru/Cerebro/dias/<hoy>.json"`.
   Ordena las alarmas (de hoy a 3 días, luego lo vencido, luego el resto), deja 12 y calcula `mostrados`,
   que es lo que el cierre de mañana usa para sumar saltos.
7. **Publicar.** `publicar-dia.ps1 -Dia "G:/Mi unidad/Casa Zaru/Cerebro/dias/<hoy>.json"` → tiene que decir
   `OK 200`. Confirmar con el MCP: `select fecha, updated_at from public.cerebro_dias order by fecha desc limit 1`.
   Si dice `SIN_TOKEN` o `ERROR`, no publicar en otro lado: decirlo en el resumen (el día queda en Drive).
7b. **«Mi día» del equipo (desde el 17-11-2026).** Quien tiene día propio está en
   `Cerebro\equipo\personas.json` (hoy: marketing). Su pantalla es `mi-dia.html` del sitio del Cotizador
   (repo Cotizador), tablas `equipo_dias` / `equipo_marcas` del proyecto **Cotizador** (migración 0003).
   Solo lleva lo suyo: nunca plata, impuestos, RR. HH. ni alarmas de ventas.
   - **Cerrar ayer** (junto con el paso 1): por cada persona, leer sus marcas con el MCP del cotizador
     (`select data from public.equipo_marcas where correo = '<correo>' and fecha = '<ayer>'`; sin fila → `{}`),
     guardarlas en `<scratchpad>\marcas-equipo-<dueño>-<ayer>.json` y correr
     `cerrar-equipo.ps1 -Fecha <ayer> -Dueno <dueño> -Marcas <json>`. Listo → hecho (o vuelve al dueño si
     `listo-cuando.csv` dice `vuelve`); Bloqueada → esperando 3 días; Mañana o sin marcar → un salto. Lo que
     junta 3 saltos, queda bloqueado por el dueño o vuelve para decidir, componer lo pone solo en «Decidir».
   - **Armar hoy** (entre los pasos 2 y 6): correr `sql/cotizador-marketing.sql` con el MCP del cotizador,
     guardar el resultado TAL CUAL en `<scratchpad>\marketing-<hoy>.json` y correr
     `armar-equipo.ps1 -Fecha <hoy> -Calc <calc> -Pulso <marketing.json>`. Elige 3 misiones (lo fijo de hoy o
     mañana primero, después lo que vence antes), la cola, la rutina del día, el pulso y las ideas de WhatsApp.
     Corre ANTES de `componer-dia.ps1`: así tu «Equipo» muestra sus misiones con lo que hizo ayer, y sus
     pendientes no te suman saltos a ti.
   - **Publicar** (después del paso 7): `publicar-equipo.ps1 -Fecha <hoy>` → `OK <dueño> 200`. Usa la llave de
     `%USERPROFILE%\.casazaru\equipo-token.txt` (nunca imprimirla). Si falla, el día queda en
     `Cerebro\equipo\<dueño>\` y se dice en el resumen.
   - Pendiente nuevo de marketing: dueño la persona y, si se puede, su «Listo cuando» en
     `Cerebro\equipo\listo-cuando.csv` (y `al_terminar=vuelve` si al final decide el dueño).
8. **Resumen** en el chat (corto, en español): lo que vence hoy y mañana, la cifra rara, cuántos se
   cerraron ayer, fuentes que fallaron, los encargos «en manos de Claude» y que se ve en Gestión → «Mi día».

## Los lunes, además

- `foco` de la semana: las 3 cosas que mueven más plata o riesgo.
- Auditoría del cerebro: pendientes `abierto` sin `proxima_revision` o con más de 30 días sin
  `ultima_verificacion` → «verificar». Áreas con revisión atrasada → alarma. Anotar en `bitacora.md`.
- Si el último informe de `/auditoria` tiene más de 8 días, va como alarma (no correrla desde acá).

## Reglas

- Todo número sale de un script o una consulta; si no se puede calcular, «sin dato».
- Nada se pisa sin respaldo: `pendientes.csv` se copia a `respaldos\` antes de cada escritura.
- Nada de multi-agentes ni workflows.
- `Colegio`, `PUERTO OCTAY` y las finanzas de la pareja no son Casa Zaru: no entran.
- «Madera noble», nunca «nativa». Íconos de línea, nada de emojis.
