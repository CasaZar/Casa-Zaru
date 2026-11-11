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
| URL de la página | `G:\Mi unidad\Casa Zaru\Cerebro\config.json` → `artifact_url` (privada, `db` solo admin) |
| Inventario | `Cerebro\pendientes.csv`, `areas.csv`, `calendario.csv` |
| Días armados (respaldo) | `Cerebro\dias\<fecha>.json` |
| Bitácora y cierres | `Cerebro\bitacora.md`, `Cerebro\cierres.txt`, `Cerebro\respaldos\` |
| Aprendizajes | `Cerebro\insights.csv` (`fecha,insight,evidencia,confianza`) |
| Deudas | `C:\Users\dell\Casa Zaru Planillas\cuotas-creditos.csv` y `por-pagar-manual.csv` (solo lectura) |
| Scripts | `.claude/cerebro/armar-dia.ps1`, `componer-dia.ps1`, `cerrar-dia.ps1` |
| Consultas | `sql/gestion-pulso.sql` (MCP gestión), `sql/cotizador-pulso.sql` (MCP cotizador) |

Los `.ps1` se corren desde **Bash** con
`powershell.exe -NoProfile -ExecutionPolicy Bypass -File .claude/cerebro/<script>.ps1 ...`
(la herramienta PowerShell bloquea `G:\`). Rutas con `C:/...`, nunca `/c/...`. Archivos temporales en el
scratchpad.

## Base de la página (ArtifactData, `url` = `artifact_url`)

- `estado/actual` → `{fecha}`: el día que muestra la página.
- `dias/<fecha>` → el JSON que arma `componer-dia.ps1`. Lo escribe Claude.
- `marcas/<fecha>` → `{hechos:{id:true}, decisiones:{id:"hacer|delegar|matar"}, notas, actualizado}`. Lo
  escribe la página cuando el usuario marca. **Claude solo lo lee.**

Toda escritura a un documento que ya existe lleva `if_version` (leerlo antes).

## Procedimiento

1. **Cerrar el día anterior.** Leer `estado/actual`. Si su `fecha` es anterior a hoy y no está en
   `cierres.txt`: leer `marcas/<esa fecha>` con `out_dir` en el scratchpad (si no existe, usar `{}`), y
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
6. **Componer.** `componer-dia.ps1 -Calc ... -Narrativa ... -Salida "G:/Mi unidad/Casa Zaru/Cerebro/dias/<hoy>.json"`.
   Ordena las alarmas (de hoy a 3 días, luego lo vencido, luego el resto), deja 12 y calcula `mostrados`,
   que es lo que el cierre de mañana usa para sumar saltos.
7. **Publicar.** Con ArtifactData `batch`: `set dias/<hoy>` (`file_path` = el JSON de Drive) y
   `set estado/actual {fecha:<hoy>}` (con `if_version` si ya existe). Leer de vuelta `dias/<hoy>` para
   confirmar.
8. **Resumen** en el chat (corto, en español): lo que vence hoy y mañana, la cifra rara, cuántos se
   cerraron ayer, fuentes que fallaron y el link de la página.

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
