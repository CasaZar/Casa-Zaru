-- ── CANDADO DE PROYECTO (no borrar) ──────────────────────────────────────
-- Este archivo es del COTIZADOR (cmxqorsyxoltrakxawro). Si se pega en el SQL
-- Editor de otro proyecto, este bloque falla primero y Postgres descarta el
-- resto del script: no se aplica nada. Hace falta porque el proyecto de
-- Gestión TIENE tablas "cotizaciones" y "quote_links" (restos vacíos de junio)
-- y un alter sobre ellas pasaría ahí sin ningún error.
do $candado$
begin
  if to_regclass('public.gestion_pedidos') is not null then
    raise exception 'PROYECTO EQUIVOCADO: este SQL es del COTIZADOR (cmxqorsyxoltrakxawro) y lo estás corriendo en GESTIÓN. No se aplicó nada.';
  end if;
  if to_regclass('public.cotizaciones') is null then
    raise exception 'PROYECTO EQUIVOCADO: este SQL es del COTIZADOR (cmxqorsyxoltrakxawro) y aquí no existe la tabla cotizaciones. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- Cerrar biblioteca_copiloto · Cotizador (04-11-2026)
--
-- La auditoría del 04-11 encontró la policy "allow_all" (rol public, ALL,
-- true/true): con la llave pública, que está en el HTML, cualquiera podía
-- leer, editar o borrar las 24 conversaciones de clientes (todas del
-- 06-07-2026). copiloto-cesar.html ya no se usa, así que la tabla se cierra
-- entera: NO se borra ninguna fila, solo deja de ser alcanzable por la API.
-- Queda legible para el respaldo diario (llave secreta) y por SQL.
--
-- Respaldo previo verificado: respaldo-cotizador-2026-11-03.zip trae las 24.
-- Idempotente: se puede correr dos veces sin error.
-- ══════════════════════════════════════════════════════════════════════════

drop policy if exists allow_all on public.biblioteca_copiloto;

revoke all on public.biblioteca_copiloto from anon, authenticated;

alter table public.biblioteca_copiloto enable row level security;
alter table public.biblioteca_copiloto force row level security;

-- Verificación: debe dar policies = 0, anon_lee = false, auth_lee = false,
-- force = true y filas = 24.
select
  (select count(*) from pg_policies
    where schemaname = 'public' and tablename = 'biblioteca_copiloto')          as policies,
  has_table_privilege('anon', 'public.biblioteca_copiloto', 'select')          as anon_lee,
  has_table_privilege('authenticated', 'public.biblioteca_copiloto', 'select') as auth_lee,
  (select relforcerowsecurity from pg_class
    where oid = 'public.biblioteca_copiloto'::regclass)                         as force,
  (select count(*) from public.biblioteca_copiloto)                             as filas;

-- ── ROLLBACK (solo si hubiera que reabrirla; no correr junto con lo de arriba)
-- grant select, insert, update, delete on public.biblioteca_copiloto to anon, authenticated;
-- create policy allow_all on public.biblioteca_copiloto for all to public using (true) with check (true);
-- alter table public.biblioteca_copiloto no force row level security;
