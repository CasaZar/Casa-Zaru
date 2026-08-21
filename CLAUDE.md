# Casa Zaru — Reglas del Proyecto

## Archivo principal
`index.html` — single-file HTML de ~1.27 MB. Hacer **ediciones puntuales (str_replace)**, nunca regenerar el archivo completo.

Ver `ESTRUCTURA.md` para el mapa completo (3 repos, 3 sitios, 3 proyectos Supabase).

## Backend: Supabase
El backend es **Supabase**, no Firebase (migrado). Tres proyectos:

| Ref | Nombre en el panel | Qué tiene |
|---|---|---|
| `padnttpgzuotxeipjrry` | «Cotizador clientes» ⚠️ | **Es el de la Gestión**: `gestion_*`, el módulo de gastos, y además `cotizaciones` / `cotizacion_lineas` / `quote_links` |
| `cmxqorsyxoltrakxawro` | «cotizador-interno» | El cotizador público y el panel de seguimiento (`cotizador_valores`, `toques`, `config_seguimiento`) |
| `rmktkhjteghbheyrkfxs` | — | No es Casa Zaru. No tocar. |

⚠️ El nombre del panel engaña: **`padnttpgzuotxeipjrry` es el de la app de Gestión**, aunque se llame
«Cotizador clientes». Guiarse siempre por el `ref` de la URL. PostgreSQL 17.6.


## Alcance del módulo de gastos
Es el circuito **factura → bodega → costo del pedido**, para sacar el margen real por pedido.
No es un reemplazo de `casa-zaru-gastos`: esa app es aparte, corre sobre su propio Firebase y no se
toca. Hubo un intento de consolidar las dos (migraciones 0002 y 0003) que se revirtió a propósito.

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

## SheetJS
`document.scripts[0]` es SheetJS embebido (~835 KB). **No tocarlo nunca.**
