# SQL del COTIZADOR — proyecto `cmxqorsyxoltrakxawro`

Todo lo de esta carpeta se corre en el proyecto **«ZARU · Cotizador (público y panel)»**,
nunca en el de Gestión. Lo de `../supabase/` es de Gestión (`padnttpgzuotxeipjrry`).

- Cada archivo empieza con un **candado de proyecto**: si se pega en el SQL Editor equivocado,
  falla antes de tocar nada. No borrarlo.
- Son parches corridos a mano, **no migraciones**: no están registrados en
  `schema_migrations` y no los aplica `supabase db push`.
- Un archivo nuevo para este proyecto va acá y lleva el mismo candado (copiarlo de cualquier
  archivo de la carpeta).

## Edge Functions (`functions/`)

Las funciones de servidor de este proyecto. No hay CLI en el PC, así que se despliegan desde el
panel (Edge Functions → Deploy a new function → Via Editor); el encabezado de cada `index.ts`
dice el nombre, los secretos que necesita y si hay que apagar «Verify JWT». Los secretos se cargan
en el panel y **nunca** se escriben en estos archivos: el repo es público.

- `starken-tarifa` — precio del despacho con la API de Cotización de Starken.
