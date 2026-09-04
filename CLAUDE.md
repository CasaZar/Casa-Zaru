# Casa Zaru — Reglas del Proyecto

## Archivo principal
`index.html` — single-file HTML de ~1.27 MB. Hacer **ediciones puntuales (str_replace)**, nunca regenerar el archivo completo.

Ver `ESTRUCTURA.md` para el mapa completo (3 repos, 3 sitios, 3 proyectos Supabase).

## Entorno de trabajo

**Carpeta buena:** `C:\Users\dell\Casa Zaru - Claude`. Existe un clon viejo en
`OneDrive\Desktop\Casa Zaru Visual\Casa-Zaru` que quedó de un enredo — no trabajar ahí.

**No hay Node, npm, psql ni el CLI de Supabase en esta máquina.** No proponer `npm install`,
`npm test` ni `supabase db push`: no van a correr. Las verificaciones son estructurales (grep,
balance de llaves, conteo de `<th>` vs `<td>`) y contra la base por HTTP.

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
| `padnttpgzuotxeipjrry` | «ZARU · Gestión (pedidos, finanzas, costos)» | **Es el de la Gestión**: `gestion_*`, el módulo de gastos, y además `cotizaciones` / `cotizacion_lineas` / `quote_links` |
| `cmxqorsyxoltrakxawro` | «ZARU · Cotizador (público y panel)» | El cotizador público y el panel de seguimiento (`cotizador_valores`, `toques`, `config_seguimiento`) |
| `rmktkhjteghbheyrkfxs` | — | No es Casa Zaru. No tocar. |

Los proyectos se renombraron el 22 ago 2026 justo para esto: antes el de la Gestión se llamaba
«Cotizador clientes», que era al revés de lo que uno espera, y se prestaba a tocar el proyecto
equivocado. Renombrar es seguro: el `ref`, las keys y los endpoints no cambian.

**Guiarse igual por el `ref` de la URL**, que es el identificador real y no depende de cómo se
llame el proyecto en el panel. PostgreSQL 17.6. Ambos están en la organización CasaZaru
(`ivbgokwoajlrqmruervf`), plan Free.


### Migraciones
Van en **`supabase/migrations/<NNNN>_<nombre>.sql`**, correlativas desde `0001`. Los ceros a la
izquierda no son adorno: la versión se guarda como **texto**, así que sin relleno la `10` quedaría
ordenada entre la `1` y la `2`.

El registro de lo aplicado lo lleva Supabase en `supabase_migrations.schema_migrations`, que es lo
que muestra Database → Migrations en el panel. Al aplicar a mano (SQL Editor o Management API) hay
que **insertar la fila ahí también**, si no el panel no la ve:

```sql
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('0005', 'nombre_corto', array[$mig$ <contenido del .sql> $mig$]);
```

**No llevar una tabla de migraciones propia** — ya existe una y duplicarla es pedir que diverjan.

Estado (verificado contra la base el 3 sep 2026): aplicadas y registradas `0001`–`0003`, `0005`–`0014`.
**No existe ninguna `0004`**, ni en el repo ni en la base — el hueco es a propósito y no hay nada
pendiente ahí.

⚠️ **Hay una divergencia**: la migración **`0013 limpia_placeholder_item_nombre` está aplicada en la
base pero no existe en el repo** (limpia el `'Detalle no disponible'` que dejó la carga piloto `0011`).
Antes de numerar una migración nueva, **mirar `supabase_migrations.schema_migrations`, no la carpeta**:
la carpeta se quedó corta y por eso la `0014` casi sale con el número de una que ya existía.

Los `.sql` sueltos en `supabase/` (fuera de `migrations/`) son parches viejos ya corridos a mano y
**no registrados**. Dejarlos ahí es deliberado: si se movieran a `migrations/`, `db push` los
re-ejecutaría.

## Alcance del módulo de gastos
Es el circuito **factura → bodega → costo del pedido**, para sacar el margen real por pedido.
No es un reemplazo de `casa-zaru-gastos`: esa app es aparte, corre sobre su propio Firebase y no se
toca. Hubo un intento de consolidar las dos (migraciones 0002 y 0003) que se revirtió a propósito.

**Qué está construido:** las dos ramas de la factura (insumo / gasto directo), el insumo entra a
bodega como activo, el gasto directo va al mayor, unidad obligatoria, cantidades decimales, madera
en pulgadas, permisos por rol.

**Qué falta:** el botón para que el taller **descuente bodega al costear un pedido**. Es la caja del
medio del diagrama y sin ella el margen sigue siendo teórico: `_aUnidadStock()` existe y está probada,
pero la conversión m²→pulgadas nunca se ejecuta porque solo se la llama desde el editor de facturas.
Falta también el modal que ofrece actualizar el costo estándar cuando cambia un precio de compra.

Las tablas están **vacías**: los catálogos (9 unidades, 25 categorías) sembrados, nada más.
## Esquema de datos
Dos mitades, a propósito distintas.

**1) Pedidos** — tablas `gestion_*`, formato `num text primary key` + `data jsonb`.
Clave universal `numStr` (número de pedido como string, ej. `"1451"`):
`pedidos`, `produccion`, `finanzas`, `pixel`, `costos`, `historial`.
Se hablan con `api('coleccion/clave', metodo, data)`, que mantiene el contrato de la versión Firebase
(por eso las ~47 llamadas del archivo no cambiaron). El mapa `TABLA` traduce colección → tabla.
**Producción es la fuente de verdad.** Config dentro de la colección: `costos/__estandar`.

**2) Gastos** — siete tablas **relacionales**, con `id bigint generated always as identity` y llaves
foráneas reales (migración `supabase/migrations/0001_gastos_inventario.sql`):
`unidades` · `gasto_categorias` · `proveedores` · `facturas` · `factura_lineas` · `inventario` · `mayor`

No usan `api()`: se hablan por PostgREST con `sbGet` / `sbInsert` / `sbUpdate` / `sbDelete`.
Un movimiento del mayor apunta a la línea de factura que lo originó, esa línea a un ítem de bodega y
ese ítem a su unidad; dentro de un jsonb esos vínculos serían texto que nadie valida.

Las lecturas van por vistas (`v_mayor`, `v_facturas`, `v_inventario`), que traen los campos calculados
(`estado`, `gasto_real`, `costo_periodo`, `valorizado`). **Esas fórmulas viven solo en SQL** — no
recalcularlas en JS. Después de escribir, recargar con `recargarGastos()` en vez de parchar el arreglo.

## Roles
`admin` (todo) · `vendedor` (sin Finanzas/Costos/Pixel/Gastos) · `taller` (Producción + bodega).
La protección real es RLS en el servidor; el CSS `body.rol-*` es solo cosmético.

## Skills del proyecto
Viven en `.claude/skills/`. Invocarlas cuando el pedido calce, en vez de reconstruir el análisis a mano:

| Skill | Cuándo se activa |
|---|---|
| `cierre-semanal` | "cierre semanal", "cómo vamos este mes", "en qué tramo está César", "qué despacha esta semana". Venta acumulada del mes, tramo de comisión y despachos. |
| `analisis-cotizador` | "análisis del cotizador", "qué se está cotizando", "cómo va el seguimiento". Productos, medidas y ticket cotizados, más tiempo al primer toque y cotizaciones sin tocar. |
| `gads` | Auditoría de Google Ads, Search Console, PMax, Merchant Center o Business Profile, a partir de exports CSV/Excel. **No** es para Meta ni para crear campañas. |

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
El número de `<th>` debe ser **igual** al de `<td>` (actualmente 20 = 20). Verificar antes de cualquier cambio de columnas.

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
