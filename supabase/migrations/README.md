# Migraciones y SQL de Supabase

Leer antes de escribir cualquier migración o `.sql`. Movido desde `CLAUDE.md` el 03-11-2026 para que no se
cargue en cada mensaje; las reglas son las mismas.

## Migraciones
Van en **`supabase/migrations/<NNNN>_<nombre>.sql`**, correlativas desde `0001`. Los ceros a la
izquierda no son adorno: la versión se guarda como **texto**, así que sin relleno la `10` quedaría
ordenada entre la `1` y la `2`.

El registro de lo aplicado lo lleva Supabase en `supabase_migrations.schema_migrations`, que es lo
que muestra Database → Migrations en el panel. Como no hay CLI (ver `CLAUDE.md`), las migraciones se
aplican a mano en el SQL Editor, y **hay que insertar la fila ahí también**, si no el panel no la ve:

```sql
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('0005', 'nombre_corto', array[$mig$ <contenido del .sql> $mig$]);
```

⚠️ La etiqueta de la cita (`$mig$`) **no puede aparecer dentro del archivo**: si la migración la
menciona en un comentario (todas lo hacen, porque llevan este mismo recordatorio al final), la cita se
corta ahí y el editor tira `syntax error at or near "archivo"`. Usar una etiqueta propia por
migración, por ejemplo `$m0023$`. Pasó con la 0023 el 26-10-2026.

**No llevar una tabla de migraciones propia** — ya existe una y duplicarla es pedir que diverjan.

Estado: el 3 sep 2026 estaban aplicadas y registradas `0001`–`0003` y `0005`–`0014`; al 16-10 el
repo llega a la `0018`. Lo aplicado de verdad se mira en `schema_migrations`, no en esta línea.
**No existe ninguna `0004`**, ni en el repo ni en la base — el hueco es a propósito y no hay nada
pendiente ahí.

⚠️ **Antes de numerar una migración nueva, hacer `git pull` y además mirar
`supabase_migrations.schema_migrations`.** Hay más de una sesión trabajando sobre este repo a la vez:
la `0014` casi sale numerada `0013` porque el clon local estaba atrasado y no tenía todavía la
`0013_limpia_placeholder_item_nombre` que otra sesión ya había pusheado y aplicado. La base sabía la
verdad y la carpeta no. El número libre es el siguiente al mayor de **ambos**.

Los `.sql` sueltos (fuera de `migrations/`) son parches corridos a mano y **no registrados**.
Dejarlos fuera de `migrations/` es deliberado: si se movieran ahí, `db push` los re-ejecutaría.

## Cada proyecto tiene su carpeta, y no se mezclan
Separado el 15-09-2026:

| Carpeta | Proyecto | Qué va |
|---|---|---|
| `supabase/` (y `supabase/migrations/`) | Gestión `padnttpgzuotxeipjrry` | migraciones y parches de Gestión |
| `supabase-cotizador/` | Cotizador `cmxqorsyxoltrakxawro` | todo el SQL del cotizador público y del panel |

**Todo `.sql` suelto empieza con un CANDADO DE PROYECTO**: un `do $candado$` que falla si se pega en
el SQL Editor equivocado, y como Postgres corre el script entero en una sola transacción, no se
aplica nada. No borrarlo, y copiarlo en todo archivo nuevo. El del Cotizador revisa que **no**
exista `gestion_pedidos` (no alcanza con pedir `cotizaciones`: Gestión tiene una vacía y un
`alter` pasaría ahí sin error). Un archivo nunca debe tener bloques para los dos proyectos: se parte
en dos, uno por carpeta (así se hizo con `brief-matinal-acceso.sql`).
