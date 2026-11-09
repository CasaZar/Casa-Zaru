# Casa Zaru — Reglas del Proyecto

## Archivo principal
`index.html` — single-file HTML de ~1,7 MB. Hacer **ediciones puntuales (str_replace)**, nunca regenerar el archivo completo.

Ver `ESTRUCTURA.md` para el mapa completo (3 repos, 3 sitios, 3 proyectos Supabase).
Ver `WASABIL-SII.md` para todo lo de boletas, facturas, SII y Wasabil (dónde vive cada pieza,
cómo se emite, reglas y trampas).

## Entorno de trabajo

**Carpeta buena:** `C:\Users\dell\Casa Zaru - Claude`. Existe un clon viejo en
`OneDrive\Desktop\Casa Zaru Visual\Casa-Zaru` que quedó de un enredo — no trabajar ahí.

**En esta máquina NO hay Node, npm, CLI de Supabase ni `psql`.** Verificado el 15-09 y otra vez el
16-10-2026 (PATH + rutas habituales: nodejs, npm global, scoop, winget). `python` es solo el stub de
la Microsoft Store. Hubo una versión de esta sección que decía lo contrario («confirmado el 3 sep»):
estaba mal y se borró. Si alguien lo instala, correr `Get-Command node, supabase` antes de reescribir
esto.

**Lecturas de Supabase: MCP oficial en solo lectura** (desde el 03-11-2026). `.mcp.json` (local, en
`.gitignore`) define `supabase-gestion` y `supabase-cotizador`, cada uno amarrado a su `project_ref`
con `read_only=true`. Autenticados los dos el 04-11-2026. En la app de escritorio `/mcp` no ofrece
«Authenticate»: se autoriza desde la consola (`claude.exe` en una pestaña de terminal → `/mcp`), y la
sesión de la app lo toma al reconectar o en una sesión nueva. `.claude/settings.json` además niega las
herramientas que escriben (`apply_migration`, `deploy_edge_function`, ramas). Ojo: el MCP lee como
`supabase_read_only_user`, que no es superusuario pero tiene `bypassrls`: lee **sin RLS**, así que ve
todos los datos personales. Las escrituras **siguen** yendo por
migración pegada en el SQL Editor, con el ok del usuario. No sacar `read_only=true`.

Por eso todo lo que escribe en Supabase va por el **SQL Editor del panel** (o por HTTP contra PostgREST), y
`index.html` se prueba en el navegador: `.claude/static-server.ps1` + el Browser pane. Sin eso, las
verificaciones son estructurales (grep, balance de llaves, conteo de `<th>` vs `<td>`).

**Probar la app:** `.claude/static-server.ps1` la sirve en `localhost:5500` (también hay perfiles en
`.claude/launch.json`). Abrirla con `file://` funciona, pero un servidor evita bordes raros de ese origen.

**Publicar:** GitHub Pages sirve `main` en https://casazar.github.io/Casa-Zaru/ — un `git push` y
redeploya solo. ⚠️ **Pages no funciona con repos privados en el plan gratuito**: si el repo se pone
privado, el sitio cae con 404 al instante. Hay un `netlify.toml` listo como alternativa, configurado
para publicar **solo el HTML** y no los `.sql` ni la documentación.

## Backend: Supabase
El backend es **Supabase**, no Firebase (migrado). Tres proyectos:

| Ref | Nombre en el panel | Qué tiene |
|---|---|---|
| `padnttpgzuotxeipjrry` | «ZARU · Gestión (pedidos, finanzas, costos)» | **Es el de la Gestión**: `gestion_*`, el módulo de gastos, Recibidos, centros de costo. ⚠️ Tiene además `cotizaciones` / `cotizacion_lineas` (vacías) y `quote_links` (35 filas del 25-26 jun) que son **restos muertos** de antes de separar los proyectos: nada lee ni escribe ahí. Las cotizaciones reales están en el proyecto del Cotizador. |
| `cmxqorsyxoltrakxawro` | «ZARU · Cotizador (público y panel)» | El cotizador público y el panel de seguimiento (`cotizador_valores`, `toques`, `config_seguimiento`) |
| `rmktkhjteghbheyrkfxs` | — | No es Casa Zaru. No tocar. |

Los proyectos se renombraron el 22 ago 2026 justo para esto: antes el de la Gestión se llamaba
«Cotizador clientes», que era al revés de lo que uno espera, y se prestaba a tocar el proyecto
equivocado. Renombrar es seguro: el `ref`, las keys y los endpoints no cambian.

**Guiarse igual por el `ref` de la URL**, que es el identificador real y no depende de cómo se
llame el proyecto en el panel. PostgreSQL 17.6. Ambos están en la organización CasaZaru
(`ivbgokwoajlrqmruervf`), plan Free.


### Migraciones y SQL
**Antes de escribir una migración o cualquier `.sql`, leer `supabase/migrations/README.md`** (registro en
`schema_migrations`, etiqueta de cita propia, el hueco de la `0004`). Lo mínimo que no se olvida:
- `supabase/migrations/<NNNN>_<nombre>.sql`, con 4 dígitos. El número libre es el siguiente al mayor del
  repo (después de `git pull`) **y** de `schema_migrations`: hay varias sesiones a la vez.
- `supabase/` = Gestión, `supabase-cotizador/` = Cotizador. Nunca los dos proyectos en un mismo archivo.
- Todo `.sql` suelto empieza con el **candado de proyecto** (`do $candado$`). No borrarlo.

## Esquema de datos
Dos mitades, a propósito distintas.

**1) Pedidos** — tablas `gestion_*`, formato `num text primary key` + `data jsonb`.
Clave universal `numStr` (número de pedido como string, ej. `"1451"`):
`pedidos`, `produccion`, `finanzas`, `pixel`, `costos`, `historial`.
Se hablan con `api('coleccion/clave', metodo, data)`, que mantiene el contrato de la versión Firebase
(por eso las ~47 llamadas del archivo no cambiaron). El mapa `TABLA` traduce colección → tabla.
**Producción es la fuente de verdad.** Config dentro de la colección: `costos/__estandar`.

**2) Gastos** — siete tablas **relacionales** con FK reales, por PostgREST (`sbGet` / `sbInsert` /
`sbUpdate` / `sbDelete`), no por `api()`. Las fórmulas (`v_mayor`, `v_facturas`, `v_inventario`) viven
**solo en SQL**: no recalcularlas en JS; después de escribir, `recargarGastos()`. No es la app
`casa-zaru-gastos` (esa no se toca). Alcance, lo que falta y detalle: **`ESTRUCTURA.md` §9**.

## Roles
`admin` (todo) · `vendedor` (sin Finanzas/Costos/Pixel/Gastos) · `taller` (Producción + bodega).
La protección real es RLS en el servidor; el CSS `body.rol-*` es solo cosmético.

## Contrato de confiabilidad (vigente desde el 22-10-2026)
Claude actúa como ingeniero responsable de que la Gestión y el Cotizador no pierdan información.
Estas reglas no se negocian: si un pedido las contradice, decirlo **antes** de hacerlo.

**Datos**
- Nada se borra ni se pisa sin respaldo verificable previo. `PATCH`, nunca `PUT` sobre el `data` entero.
- Borrado lógico (`deleted_at` / `eliminada`) en tablas de negocio. `DELETE` físico solo con ok explícito
  del usuario y respaldo de esas filas.
- Toda tabla de negocio nueva lleva `created_at`, `updated_at`, `updated_by` y un trigger que guarda la
  versión anterior en una tabla de historial. Nunca se pierde el estado previo de un pedido, pago o cotización.
- La integridad vive en la base, no en el JS: FK, unique, check, not null. Si el navegador puede mandar algo
  inválido, la base lo rechaza.
- El esquema cambia SOLO por migración numerada, idempotente, con su rollback escrito y registrada en
  `schema_migrations`. Cero `ALTER` a mano sin archivo. (El Cotizador todavía no cumple esto: ver `/auditoria`.)

**Respaldo**
- Respaldo diario automático de los dos proyectos a Drive, por tabla, en formato restaurable. Retención
  objetivo: 30 diarios + 12 mensuales.
- Prueba de restauración mensual comparando conteos y sumas. Un respaldo que nunca se restauró no existe.
  Cada prueba se anota en `Informes Gestion/restauraciones.csv` (Drive): `fecha,proyecto,resultado,notas`.
- Si el último respaldo tiene más de 36 horas, avisar al abrir la sesión.
- Lo que vive solo en este PC (planillas, `~\.casazaru` sin llaves, memoria de Claude, archivos sin commit)
  se copia todos los días 14:00 a `G:\Mi unidad\Casa Zaru\Respaldo PC\` (tarea «CasaZaru - Respaldo PC»,
  `.claude/informes/respaldo-pc.ps1`). Nunca borra en Drive. La fecha de la última corrida está en `ultimo-respaldo.txt`.

**Seguridad**
- Ningún secreto en el repo, el HTML, la memoria ni los mensajes. RLS (+ FORCE) en toda tabla. La llave
  pública solo lee lo que debe. Toda rotación de llaves queda documentada con fecha.

**Cambios**
- Cada cambio: commit chico, verificación estructural (llaves balanceadas, `<th>` = `<td>`, sin template
  anidado), prueba en el navegador a 390 px, push y verificación del sitio en vivo.
- Antes de cualquier escritura masiva en la base, mostrar el `SELECT` con las filas afectadas y esperar el ok.
- Nunca probar emitiendo documentos reales al SII ni guardando cotizaciones reales.
- Si un cambio toca dinero, folios o stock: un solo camino de escritura, idempotente.

**Operación**
- Un runbook por escenario (cae Supabase, cae GitHub Pages, se borra una tabla, se filtra una llave), cada
  uno ensayado una vez. Pendientes de escribir.
- Los errores del cliente (`window.onerror`) se registran en una tabla y se revisan en `/auditoria`. Pendiente.
- Todo número que se muestre sale de la fórmula real, nunca de cabeza.

La auditoría semanal que mide el cumplimiento es la skill `/auditoria` (abajo).

## Skills del proyecto
Viven en `.claude/skills/`: `auditoria`, `cierre-semanal`, `analisis-cotizador`, `conciliacion`,
`cierre-mensual`, `gads`. Cuándo se activa cada una lo dice su propia descripción (y el detalle, su
`SKILL.md`). Invocarlas cuando el pedido calce, en vez de reconstruir el análisis a mano. `auditoria`
**solo reporta, no corrige**.

`.claude/settings.json` bloquea todas las operaciones de **escritura** del MCP de Meta Ads (crear o
activar campañas, editar catálogo, tocar el pixel). Lectura y análisis sí. No sacar esos `deny`.

## Reglas críticas de código

### Template literals
NUNCA usar template literals anidados (backtick dentro de `${}` de otro template) en los `return` de funciones render — rompen el browser aunque Node los acepte.

```js
// MAL — rompe el browser
return `<td>${`valor ${x}`}</td>`;

// BIEN — usar concatenación o variable intermedia
const inner = 'valor ' + x;
return `<td>${inner}</td>`;
```

### Handlers inline
En `onclick`/`onchange` inline usar siempre `numStr` como lookup, **nunca índice posicional** — el índice se desalinea con filtros de mes activos.

```js
// MAL
onclick="editar(${index})"

// BIEN
onclick="editar('${numStr}')"
```

### Tabla de finanzas
El número de `<th>` debe ser **igual** al de `<td>` (actualmente 21 = 21, desde que se sumó «Doc. 3» el 09-11-2026). Verificar antes de cualquier cambio de columnas.

### Documentos: uno por abono
Desde el 09-11-2026 (migración 0028) cada pedido tiene hasta tres documentos: **doc N = abono N**
(`_montoSugeridoDoc`). El doc 3 solo se pide si hay abono 3 que el doc 2 no cubrió (`_doc3Requerido`);
«listo» y «pendiente» pasan siempre por `_docsListos`. No volver a escribir `doc1_emitida&&doc2_emitida`.

### Cantidades: decimal + unidad, siempre
Toda cantidad de material es **decimal**, nunca entero: media pulgada de Coihue son $14.000 y hay ítems
del catálogo que se consumen de a 0,002 por m². Nunca `parseInt` ni `Math.round` sobre una cantidad.

- Cantidades → 3 decimales (`_f3`), `numeric(14,3)` en la base. Inputs `step="0.001"`.
- Valores unitarios → 2 decimales (`_f2`), `numeric(14,2)`. Un litro de sellador sale $3.982,46.
- Montos en pesos → enteros (`_pesos`), `integer`.
- En SQL se usa `numeric`, **nunca `float`/`double precision`**: con binario, 0,1 + 0,2 no da 0,3 y la
  valorización de bodega se desvía de a centavos.
- **Ninguna cantidad se muestra, guarda ni exporta sin su unidad al lado** (`fmtCant`). El check
  `cantidad_con_unidad` de la tabla `mayor` lo hace cumplir del lado de la base.
- Toda conversión de unidades pasa por `_aUnidadStock()`. No multiplicar factores sueltos.

### IVA
El módulo de costos, el inventario y el mayor van **sin IVA** (el IVA de compra es crédito fiscal).
La factura guarda `neto`, `iva` y `total` por separado; al mayor va el neto.

## API Anthropic
Model string: `claude-sonnet-4-6`

La key **nunca va en el código**: la escribe cada usuario y vive en su `localStorage`
(`zaru_api_key`). Hubo una embebida en `copiloto-cesar.html` que quedó siete semanas en el
historial de un repo público — se rotó, pero en git eso no se borra. No repetirlo.

Las llamadas van desde el navegador con `anthropic-dangerous-direct-browser-access`. El patrón
correcto ya existe en otra app del stack: la key vive como variable de entorno en una función
de servidor y nunca llega al cliente. Vale la pena migrar a eso.

## SheetJS
`document.scripts[0]` es SheetJS embebido (~835 KB). **No tocarlo nunca.**
