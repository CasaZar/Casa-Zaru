# Casa Zaru — Reglas del Proyecto

## Archivo principal
`casa_zaru_v16.html` — single-file HTML con Firebase Realtime DB. Hacer **ediciones puntuales (str_replace)**, nunca regenerar el archivo completo.

## Esquema Firebase
- Clave universal: `numStr` (número de pedido como string, ej. `"1451"`)
- 5 colecciones: `pedidos`, `produccion`, `finanzas`, `pixel`, `costos`
- **Producción es la fuente de verdad**

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

## API Anthropic
Model string: `claude-sonnet-4-6`

## SheetJS
`document.scripts[0]` es SheetJS embebido (~835 KB). **No tocarlo nunca.**
