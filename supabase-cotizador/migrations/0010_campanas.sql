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
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '0009')
     or to_regprocedure('public.mensajes_historial_guardar()') is null
     or to_regprocedure('public.es_equipo_panel()') is null then
    raise exception 'FALTA LA 0009 (o mensajes_historial_guardar / es_equipo_panel): revisar el orden antes de seguir. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- 0010 · COTIZADOR · Panel de campañas (21-11-2026)
--
-- Hasta hoy la campaña de peldaños vivía en una constante del código
-- (CAMPANA = { nota, desde, hasta }): para repetirla o hacer otra había que
-- tocar el HTML. Ahora cada campaña es una fila: a quién (producto + filtros),
-- el mensaje (con variables), la oferta, las fechas y el estado. El panel lee
-- la que está ACTIVA y la muestra arriba de Seguimiento, igual que antes.
--
-- Los resultados NO se guardan aquí: se calculan en el panel desde el
-- historial de cada cliente (la nota de la campaña en seg_historial) y sus
-- cotizaciones ganadas, por cliente y no por cotización.
--
--   campanas   una fila por campaña. `nota` = lo que queda escrito en el
--              historial del cliente (única: es lo que une la campaña con sus
--              resultados). Una sola activa a la vez (índice único parcial).
--
-- Escribe solo el dueño (hola@casazaru.cl); lee el equipo del panel. Sin
-- borrado físico: deleted_at. Cada cambio guarda la versión anterior en
-- mensajes_historial (tabla = 'campanas').
--
-- Siembra la campaña de octubre como «terminada», con la MISMA nota que ya
-- tienen sus 72 clientes («Campaña peldaños»): no toca ninguna cotización.
--
-- Idempotente. Rollback al final.
--
-- APLICADA el 23-11-2026 en el SQL Editor del Cotizador (desde el Chrome del
-- dueño, con su ok; después de la 0011, que otra sesión aplicó antes).
-- Verificación: tabla 1, rls_force true, policies 3, triggers 2, anon_algo 0,
-- auth_borra false, filas 1; confirmado aparte por el MCP (versiones 0009,0010,0011).
-- Panel en vivo: 72 escritos · 11 respondieron · 7 recotizados · 4 compraron · $5.184.929.
-- ══════════════════════════════════════════════════════════════════════════

create table if not exists public.campanas (
  id          bigint generated always as identity primary key,
  nombre      text not null check (length(btrim(nombre)) between 3 and 80),
  nota        text not null unique check (length(btrim(nota)) between 3 and 80 and nota = btrim(nota)),
  estado      text not null default 'borrador' check (estado in ('borrador','activa','pausada','terminada')),
  desde       date,
  hasta       date,
  producto    text not null check (producto ~ '^[a-z]{3,30}$'),       -- se busca dentro de cotizaciones.producto
  filtros     jsonb not null default '{}'::jsonb check (jsonb_typeof(filtros) = 'object'),
  mensaje     text not null default '' check (length(mensaje) <= 2000),
  oferta      text check (length(oferta) <= 300),                    -- lo que se ofrece, en una línea
  instruccion text check (length(instruccion) <= 600),                -- qué hace el vendedor si contesta
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  updated_by  text not null default coalesce(auth.jwt() ->> 'email', 'sql'),
  deleted_at  timestamptz,
  check (hasta is null or desde is null or hasta >= desde),
  -- una campaña activa tiene que poder mandarse: fechas y mensaje
  check (estado <> 'activa' or (desde is not null and hasta is not null and length(btrim(mensaje)) >= 20)),
  check (deleted_at is null or estado <> 'activa')
);
create unique index if not exists campanas_una_activa
  on public.campanas ((true)) where estado = 'activa' and deleted_at is null;

create or replace function public.campanas_sellar()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  new.updated_by := coalesce(auth.jwt() ->> 'email', 'sql');
  return new;
end $$;

drop trigger if exists tr_campanas_sellar on public.campanas;
create trigger tr_campanas_sellar before update on public.campanas
  for each row execute function public.campanas_sellar();
drop trigger if exists tr_campanas_hist on public.campanas;
create trigger tr_campanas_hist after update or delete on public.campanas
  for each row execute function public.mensajes_historial_guardar();

-- ── RLS: lee el equipo del panel; escribe solo el dueño; nadie borra ──
alter table public.campanas enable row level security;
alter table public.campanas force  row level security;
drop policy if exists campanas_leer on public.campanas;
create policy campanas_leer on public.campanas
  for select to authenticated using (public.es_equipo_panel());
drop policy if exists campanas_crear on public.campanas;
create policy campanas_crear on public.campanas
  for insert to authenticated with check (lower(auth.email()) = 'hola@casazaru.cl');
drop policy if exists campanas_editar on public.campanas;
create policy campanas_editar on public.campanas
  for update to authenticated
  using (lower(auth.email()) = 'hola@casazaru.cl')
  with check (lower(auth.email()) = 'hola@casazaru.cl');
revoke all on public.campanas from anon, authenticated;
grant select, insert, update on public.campanas to authenticated;

-- ── Siembra: la campaña de octubre, tal como corrió (texto del 21-10) ──
insert into public.campanas (nombre, nota, estado, desde, hasta, producto, filtros, mensaje, oferta, instruccion, updated_by)
values (
  'Peldaños · 10 % sobre $1M',
  'Campaña peldaños',
  'terminada',
  '2026-10-21', '2026-10-30',
  'peldano',
  '{"incluir_cerradas": true, "sacar_compraron": true, "sacar_otro_lado": true, "sacar_desistio": false, "solo_antes_de": "2026-10-21", "excluir_notas": []}'::jsonb,
  E'{saludo}, ¿cómo estás?{soy}\n\n{hace} cotizaste unos peldaños {con_nosotros} y quería saber si el proyecto sigue en pie.\n\nSi es así, estamos con un 10% de descuento en peldaños para compras sobre $1.000.000, hasta el 30 de octubre. Coméntame y te actualizo la cotización con el descuento.\n\nSaludos.',
  '10 % en peldaños sobre $1.000.000, hasta el 30-10',
  'Si contesta, recotiza con «＋ Nueva cotización» y el descuento especial de 10%.',
  'migracion-0010'
)
on conflict (nota) do nothing;

-- Registro
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('0010', 'campanas', array[
  'create table campanas (una fila por campaña: nota unica, estado, fechas, producto, filtros, mensaje, oferta; una sola activa); ver supabase-cotizador/migrations/0010_campanas.sql;',
  'triggers: sellar updated_at/by + historial en mensajes_historial;',
  'RLS + FORCE; lee es_equipo_panel(); inserta/edita solo hola@casazaru.cl; sin delete; anon sin permisos;',
  'siembra: «Campaña peldaños» de octubre como terminada.'
])
on conflict (version) do nothing;

-- Verificación. Debe dar: tabla 1 · rls_force true · policies 3 · triggers 2 ·
-- anon_algo 0 · auth_borra false · filas 1 · ultima 0010.
select
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'campanas')                                     as tabla,
  (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.campanas'::regclass) as rls_force,
  (select count(*) from pg_policies where schemaname = 'public' and tablename = 'campanas')     as policies,
  (select count(*) from pg_trigger where tgrelid = 'public.campanas'::regclass and not tgisinternal) as triggers,
  (select count(*) from unnest(array['select','insert','update','delete','truncate']) p
    where has_table_privilege('anon', 'public.campanas', p))                                   as anon_algo,
  has_table_privilege('authenticated', 'public.campanas', 'delete')                            as auth_borra,
  (select count(*) from public.campanas)                                                       as filas,
  (select max(version) from supabase_migrations.schema_migrations)                             as ultima;

-- Rollback (NO correr junto con lo de arriba; respaldar antes: select * from public.campanas):
--   drop table public.campanas;
--   drop function public.campanas_sellar();
--   delete from supabase_migrations.schema_migrations where version = '0010';
