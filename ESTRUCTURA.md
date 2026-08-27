# Casa Zaru — cómo está armado el sistema

> Documento de traspaso. Léelo completo antes de tocar nada: hay dos trampas
> de nombres que hacen perder horas.

---

## 1. Mapa rápido

Son **3 repos**, **3 sitios** y **3 proyectos de Supabase**. Ninguno se llama
como uno esperaría.

| Repo (cuenta `CasaZar`) | Carpeta local | Qué contiene | Dónde se publica |
|---|---|---|---|
| `Casa-Zaru` | `C:\Users\dell\Casa Zaru - Claude` | **El repo de trabajo.** Todo el código, los SQL, las skills | `casazar.github.io/Casa-Zaru/` |
| `Cotizador` | `C:\Users\dell\Cotizador` | Solo copia de despliegue (HTML + fotos + CNAME) | **cotizador.casazaru.cl** |
| `casa-zaru-gastos` | `C:\Users\dell\casa-zaru-gastos` | App de gastos (Vite + React) | **casazaru-gastos.netlify.app** |

**Se trabaja siempre en `Casa Zaru - Claude`.** Las otras dos carpetas son
destino, no origen.

---

## 2. ⚠️ Trampa n°1 — los `index.html` son dos apps distintas

Hay dos archivos que se llaman igual y **no tienen nada que ver**:

- `Casa Zaru - Claude/index.html` (1,3 MB) → **la GESTIÓN** (pedidos, producción,
  finanzas, costos, pixel). Es la app interna de la oficina.
- `Cotizador/index.html` (~430 KB) → **el COTIZADOR PÚBLICO**.

Desde el 27-08-2026 cada app vive SOLO en su repo (antes el fuente del
cotizador estaba en la carpeta de Gestión y se copiaba — 213 commits de un
archivo que no le pertenecía):

```
Casa Zaru - Claude/          <- SOLO la Gestión   (Supabase padntt…)
  index.html
  copiloto-cesar.html        <- copiloto de ventas (Supabase cmxqor…)
Cotizador/                   <- SOLO el Cotizador (Supabase cmxqor…)
  index.html                 <- el que sirve el dominio
  cotizador-clientes.html    <- copia con el nombre historico (mismo hash)
```

---

## 3. ⚠️ Trampa n°2 — los proyectos de Supabase están con el nombre cruzado

| Ref del proyecto | Nombre en el dashboard | Lo que REALMENTE es |
|---|---|---|
| `cmxqorsyxoltrakxawro` | "Cotizador **Interno**" | El cotizador **público** + panel de seguimiento |
| `padnttpgzuotxeipjrry` | "Cotizador **Clientes**" | **La Gestión** |
| `rmktkhjteghbheyrkfxs` | — | App de finanzas personal (Yunta/Dinus). **No es Casa Zaru** |

**Guíate por el `ref` de la URL, nunca por el nombre del dashboard.**

Tablas de cada uno:

- **cmxqor…** (cotizador): `cotizaciones`, `cotizador_valores`, `quote_links`,
  `toques`, `config_seguimiento`
- **padntt…** (gestión): `gestion_pedidos`, `gestion_produccion`,
  `gestion_finanzas`, `gestion_costos`, `gestion_pixel`, `gestion_clientes`,
  `gestion_historial`, `gestion_usuarios`

---

## 4. Cómo se despliega

**Cotizador** (esto es lo que más se toca):

1. Editar `Cotizador/cotizador-clientes.html` (el fuente vive AHI desde el
   27-08-2026; ya no hay copia en la carpeta de Gestión)
2. Copiarlo a `Cotizador/index.html` (el dominio sirve `index.html`)
3. Commit y push en el repo Cotizador — uno solo

Los dos archivos deben quedar con el mismo hash. Si el sitio "no se actualiza",
lo primero que hay que revisar es si se copió a `index.html`.

**Gestión:** commit y push en `Casa-Zaru`; GitHub Pages publica solo.

**Gastos:** commit y push; Netlify hace el build solo (`npm run build` → `dist/`).

> ⚠️ **GitHub Pages no funciona con repos privados en el plan gratuito.** Si se
> pone `Casa-Zaru` en privado, la Gestión se cae con 404 al instante. Poner el
> repo público **no** expone datos: lo que protege la Gestión es el login + RLS
> de Supabase (la clave `anon` está a la vista en el código a propósito, y las
> 8 tablas responden 401 sin sesión).

---

## 5. Reglas de código que no se pueden romper

**Template literals anidados** — un backtick dentro del `${}` de otro template
**rompe el navegador** aunque Node lo acepte. Nunca en un `return` de función
render.

```js
// MAL — pantalla en blanco
return `<td>${`valor ${x}`}</td>`;

// BIEN
const inner = 'valor ' + x;
return `<td>${inner}</td>`;
```

**Handlers inline** — en `onclick`/`onchange` usar siempre el `numStr` (número
de pedido como string), **nunca el índice de la fila**: el índice se desalinea
apenas hay un filtro de mes activo.

```js
onclick="editar(${index})"     // MAL
onclick="editar('${numStr}')"  // BIEN
```

**Tabla de finanzas** — el número de `<th>` tiene que ser igual al de `<td>`
(hoy 20 = 20). Verificar antes de agregar o sacar columnas.

**SheetJS** — `document.scripts[0]` en `index.html` es la librería SheetJS
embebida, ~835 KB minificados. **No tocar nunca.**

**Ediciones puntuales** — estos archivos son de 375 KB y 1,2 MB. Se editan por
reemplazo de texto (`str_replace`), jamás regenerando el archivo completo.

---

## 6. El Manual le gana al código

Los precios, valores y protocolos **no viven en el HTML**. Viven en la tabla
`cotizador_valores` de Supabase y se editan desde el **Manual** dentro del panel.

Si una clave ya fue guardada desde el Manual, **lo guardado le gana al valor
que está en el código**. Cambiar el HTML no sirve de nada en ese caso — hay que
cambiarlo en el Manual.

---

## 7. Otras piezas

- **Firebase** — la app de gastos todavía corre sobre Firebase RTDB
  (`casa-zaru---gastos-default-rtdb`). El Firebase viejo de la Gestión quedó
  congelado como respaldo tras la migración a Supabase.
- **Edge Function** `create-draft-order` — puente cotizador → Shopify. Escrita
  y sin desplegar; el botón fue revertido del cotizador público a propósito.
- **Netlify Function** `leer-documento` — lee boletas con GPT-4o para la app de
  gastos. Filtra por origen (devuelve 403 desde afuera).
- **Apps Script** — recordatorio de seguimiento + planilla de gastos Wasabil.
- **Tarea diaria 8:03** — reporte de gastos Wasabil por correo.

---

## 8. Pendientes conocidos

1. 🔴 **La base de Firebase de la app de gastos está abierta.** Se lee sin
   ninguna autenticación: `proveedores`, `config`, `inventario`, `margen`,
   `registros`, `deudas` — y la app maneja sueldos. No hay login. Es lo más
   urgente de todo el stack. Se arregla con reglas `auth != null` + pantalla de
   login.
2. `finanzas-casa` no tiene git ni respaldo de ningún tipo.
3. Rotar la key de Anthropic y la `service_role` de Supabase.
4. `rls-por-vendedor.sql` escrito y sin correr (proyecto del cotizador: hoy
   cualquier login puede leer y editar todo por API directa).
