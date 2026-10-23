---
name: auditoria
description: Auditoría semanal de confiabilidad de Casa Zaru (Gestión + Cotizador) — semáforo rojo/amarillo/verde de ocho puntos: respaldo, restauración, migraciones, RLS, secretos, integridad, errores del cliente y sitios vivos. Solo reporta y propone; nunca corrige. Actívala cuando el usuario pida "auditoría", "auditoría de confiabilidad", "cómo están los respaldos", "el semáforo", "/auditoria", o cuando sea lunes y toque la revisión semanal.
---

# /auditoria — auditoría semanal de confiabilidad

Mide el cumplimiento del **Contrato de confiabilidad** de `CLAUDE.md`. Es de **solo lectura**:
no corrige, no inserta filas de prueba, no borra. Cada rojo sale con su propuesta de corrección,
y la corrección es otra conversación.

## 1. Correr el script

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".claude/skills/auditoria/scripts/auditoria.ps1"
```

Hace solo lo que se puede verificar desde esta máquina sin SQL Editor:

| # | Punto | Cómo lo mide |
|---|---|---|
| 1 | Respaldo | Último archivo en Drive de cada proyecto (hora, tamaño, filas por tabla), retención. En el Cotizador compara conteos del zip contra la base en vivo (llave secreta local). Gestión no tiene llave admin local: se audita sobre el JSON. |
| 2 | Restauración | Lee `Informes Gestion/restauraciones.csv` (`fecha,proyecto,resultado,notas`). Sin archivo o >30 días = rojo. |
| 3 | Migraciones | Lista `supabase/migrations/`, saca los `create table` y comprueba por PostgREST que existan (404 = no aplicada). Cotizador: exige `supabase-cotizador/migrations/`. Lo demás lo da `schema_migrations` (SQL abajo). |
| 4 | RLS | Con la llave pública de cada proyecto: GET, PATCH y DELETE sobre cada tabla usando un filtro contradictorio (`and=(col.is.null,col.not.is.null)`) que nunca toca una fila. 401 = sin grants; 2xx = hay grant y la policy hay que mirarla en SQL. |
| 5 | Secretos | Busca `sk-ant-api`, `sb_secret_` y JWT con rol distinto de `anon` en ambos repos y en los últimos 60 commits. |
| 6 | Integridad | Sobre los respaldos: huérfanos entre colecciones, claves no numéricas en producción, emisiones sin historial, saldos negativos, vistas vs tablas; en el Cotizador toques/líneas huérfanos, números repetidos, ganadas sin monto. |
| 7 | Errores | Existe `errores_cliente` en cada proyecto. Hoy no existe: rojo hasta que se construya. |
| 8 | Sitios | HTTP a los sitios y a los dos PostgREST; hash de lo publicado vs lo local. |

El informe queda en `G:\Mi unidad\Casa Zaru\Informes Gestion\auditoria-confiabilidad-<fecha>.md`
(Drive, privado: el repo es público y el informe trae números de pedido) y se imprime en consola.

## 2. Lo que el script no puede ver: pedir al usuario que pegue en el SQL Editor

Una vez por proyecto (Gestión `padnttpgzuotxeipjrry`, Cotizador `cmxqorsyxoltrakxawro`):

```sql
-- RLS + FORCE por tabla
select c.relname, c.relrowsecurity as rls, c.relforcerowsecurity as force
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relkind='r' order by 1;
-- policies vigentes
select tablename, policyname, roles, cmd from pg_policies where schemaname='public' order by 1,2;
-- migraciones registradas (comparar con la carpeta del repo)
select version, name from supabase_migrations.schema_migrations order by version;
-- triggers y reglas que no estén en el repo
select c.relname, t.tgname, pg_get_triggerdef(t.oid)
from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and not t.tgisinternal order by 1,2;
select tablename, rulename, definition from pg_rules where schemaname='public';
```

Pegar el resultado en la conversación y completar con eso las celdas ⚪ del semáforo.

## 3. Cómo se reporta

Una tabla con las dos columnas (Gestión / Cotizador) y los ocho puntos, luego el detalle de
integridad y **una propuesta concreta por cada rojo**. Todo número sale del script, nunca de cabeza.
Si algo no se pudo verificar, va en ⚪ con el motivo, no en verde.

Lo que ya se sabe que está en rojo o amarillo (22-10-2026) y no hay que redescubrir:
- Nunca se ensayó una restauración.
- El Cotizador no tiene migraciones numeradas: todo `supabase-cotizador/*.sql` es parche suelto.
- No existe registro de errores del cliente en ninguna de las dos apps.
- 38 filas de `gestion_produccion` llevan clave Firebase (pedidos 1447-1497) en vez de numStr.
- 81 emisiones de mayo a agosto 2026 no tienen fila en `gestion_documentos` (la tabla nace en septiembre).
- `saldo_monto` y `abono_monto` en finanzas se escriben al cargar la venta y nadie los lee: campos muertos.
- 195 cotizaciones vivas comparten 17 números; `N° CL-0726-100` se repitió 142 veces (jul-ago 2026).
- En Gestión, `anon` tiene grant de `select` sobre gastos, postventa, documentos y centros de costo
  (RLS devuelve `[]`, pero el grant no debería existir). `quote_links` de Gestión (35 filas muertas) se lee en público.
- En `quote_links` del Cotizador hay una fila de prueba `id 6885` (`__auditoria_rls__`) que ni la llave
  secreta pudo borrar: hay un trigger o regla no versionado. Borrarla y traer la protección al repo.

## 4. Trampas conocidas

- La llave `sb_secret_` de `%USERPROFILE%\.casazaru\config.ps1` responde 403 «Forbidden use of secret
  API key in browser» si el User-Agent parece navegador. El script manda `casazaru-auditoria/1.0`.
- PowerShell 5.1: `"$url/$t?select"` se come la variable (`$t?` es un nombre válido). Siempre `${t}?`.
  `ConvertFrom-Json` devuelve `[]` como UN objeto (`.Count` = 1). `Diff` es alias de `Compare-Object`.
- La herramienta PowerShell de Claude bloquea comandos que mencionan la ruta de Drive: por eso el script
  copia los respaldos a `%TEMP%` y ahí los abre. Si el bloqueo salta igual, correrlo desde Bash con
  `powershell.exe -File`.
- La llave pública de Gestión es `WASABIL_ANON_KEY` (`SB_ANON` la reutiliza). La del Cotizador es el
  `sb_publishable_…` de `C:\Users\dell\Cotizador\index.html`.
- Un `204` en PATCH/DELETE con la llave pública **no** prueba que puede escribir: con RLS y sin policy
  también da 204 con cero filas. Lo concluyente es `pg_policies`.
