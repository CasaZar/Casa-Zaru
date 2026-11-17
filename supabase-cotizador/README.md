# SQL del COTIZADOR — proyecto `cmxqorsyxoltrakxawro`

Todo lo de esta carpeta se corre en el proyecto **«ZARU · Cotizador (público y panel)»**,
nunca en el de Gestión. Lo de `../supabase/` es de Gestión (`padnttpgzuotxeipjrry`).

- Cada archivo empieza con un **candado de proyecto**: si se pega en el SQL Editor equivocado,
  falla antes de tocar nada. No borrarlo.
- **Migraciones (desde el 17-11-2026):** todo cambio de esquema nuevo va en
  `migrations/<NNNN>_<nombre>.sql`, con candado, rollback escrito y su propio `insert` en
  `supabase_migrations.schema_migrations` (mismas reglas que `../supabase/migrations/README.md`;
  etiqueta de cita propia, p. ej. `$m0002$`). La `0001_estado_actual` es la **línea base**: el esquema
  completo tal como estaba ese día. No se corre en producción (su candado aborta si ya existe
  `cotizaciones`); sirve para recrear el proyecto desde cero. Se registró con
  `registro-migraciones.sql`. La `0002` (FORCE, permisos de más y `whoami`) está aplicada; la
  siguiente libre es la `0003` (mirar antes `schema_migrations`).
- Los `.sql` sueltos de esta carpeta son parches anteriores corridos a mano: quedan como historia, ya
  están contenidos en la `0001` y **no se vuelven a correr**.
- Un archivo nuevo para este proyecto va acá y lleva el mismo candado (copiarlo de cualquier
  archivo de la carpeta).

## Edge Functions (`functions/`)

Las funciones de servidor de este proyecto. No hay CLI en el PC, así que se despliegan desde el
panel (Edge Functions → Deploy a new function → Via Editor); el encabezado de cada `index.ts`
dice el nombre, los secretos que necesita y si hay que apagar «Verify JWT». Los secretos se cargan
en el panel y **nunca** se escriben en estos archivos: el repo es público.

- `starken-tarifa` — precio del despacho con la API de Cotización de Starken.
- `asistente` — responde al instante las dudas de quien cotiza (14-11-2026). Necesita antes
  `asistente.sql` (tabla `asistente_mensajes` e interruptor en `cotizador_valores`) y el secreto
  `ANTHROPIC_API_KEY`. Parte apagado: se prende cambiando `estado` a `prueba` o `activo`.
- `respaldo-cotizador` — respaldo diario de todas las tablas a Drive (zip en «Respaldos Cotizador»); lo
  llaman los crons de `respaldo-diario.sql`. Reemplaza la tarea de Windows del PC (26-10-2026).
