-- ══════════════════════════════════════════════════════════════════
-- EMBUDO DEL COTIZADOR PÚBLICO — cuántos entran vs cuántos cotizan
--
-- Proyecto: cmxqorsyxoltrakxawro («ZARU · Cotizador»). NO es la Gestión.
-- Correr en el SQL Editor de ese proyecto. Idempotente: se puede
-- correr de nuevo sin romper nada.
--
-- Quién escribe: el navegador de cada cliente (anon), vía embudoTick()
-- en cotizador-clientes.html. Insert-only y sin .select(): el anon no
-- puede leer, editar ni borrar lo que hay — solo agregar filas.
-- Quién lee: el panel (sesión iniciada), vía la RPC embudo_resumen.
-- ══════════════════════════════════════════════════════════════════

create table if not exists public.embudo_eventos (
  id      bigint generated always as identity primary key,
  creado  timestamptz not null default now(),
  sesion  text not null,                -- id aleatorio por sesión de navegación (sessionStorage)
  paso    text not null check (paso in ('visita','producto','datos','cotizacion')),
  producto text,                        -- qué eligió (null en el paso visita)
  canal   text                          -- 'web', ?src= del vendedor o utm_source
);

create index if not exists embudo_eventos_creado_idx
  on public.embudo_eventos (creado);

alter table public.embudo_eventos enable row level security;
alter table public.embudo_eventos force row level security;

drop policy if exists embudo_insert_publico on public.embudo_eventos;
create policy embudo_insert_publico on public.embudo_eventos
  for insert to anon, authenticated with check (true);

-- Lectura directa solo con sesión (el panel usa la RPC, pero esto deja
-- inspeccionar la tabla cruda desde el panel logueado si hace falta).
drop policy if exists embudo_select_equipo on public.embudo_eventos;
create policy embudo_select_equipo on public.embudo_eventos
  for select to authenticated using (true);

grant insert on public.embudo_eventos to anon, authenticated;
grant select on public.embudo_eventos to authenticated;

-- Resumen agregado para el panel: sesiones distintas por día y paso.
-- security definer para no depender de grants de lectura; el candado es
-- el revoke/grant de execute de abajo (solo authenticated).
create or replace function public.embudo_resumen(dias int default 30)
returns table(dia date, paso text, sesiones bigint)
language sql stable security definer set search_path = public as $$
  select (creado at time zone 'America/Santiago')::date as dia,
         paso,
         count(distinct sesion)::bigint as sesiones
  from embudo_eventos
  where creado >= now() - make_interval(days => greatest(1, least(dias, 365)))
  group by 1, 2
  order by 1, 2
$$;

revoke execute on function public.embudo_resumen(int) from public, anon;
grant execute on function public.embudo_resumen(int) to authenticated;
