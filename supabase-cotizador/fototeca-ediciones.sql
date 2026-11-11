-- ── CANDADO DE PROYECTO (no borrar) ──────────────────────────────────────
-- Este archivo es del COTIZADOR (cmxqorsyxoltrakxawro). Si se pega en el SQL
-- Editor de otro proyecto, este bloque falla primero y Postgres descarta el
-- resto del script: no se aplica nada.
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
-- Fototeca editable · Cotizador (11-11-2026)
--
-- La Fototeca (cotizador.casazaru.cl/fototeca.html) lee su índice de un
-- archivo fijo (datos.json en el bucket «fototeca»). Esta tabla guarda lo que
-- el admin corrige encima de ese índice, sin tocar el archivo:
--   · campos: los datos corregidos (producto, madera, uso, calidad, ia, …).
--   · en_papelera_at: está en la papelera (nadie la ve en la Fototeca).
--   · eliminada_at: se vació la papelera (fuera para siempre de la Fototeca).
--     El original en el Drive NO se toca.
-- Nada se borra: cada cambio deja la versión anterior en
-- fototeca_ediciones_historial.
-- Escribe SOLO hola@casazaru.cl y SOLO por la función fototeca_editar().
-- Leen quienes leen el bucket (admin, César y la persona de contenido), para
-- ver las correcciones y que lo de la papelera desaparezca también para ellos.
-- Idempotente. Rollback al final.
-- ══════════════════════════════════════════════════════════════════════════

create table if not exists public.fototeca_ediciones (
  item_id        text primary key check (item_id ~ '^(M[0-9]{4}|g[0-9a-f]{10})$'),
  campos         jsonb not null default '{}'::jsonb check (
                   jsonb_typeof(campos) = 'object'
                   and (campos - array['producto','madera','uso','calidad','ia','descripcion','etiquetas','ambiente','etapa']) = '{}'::jsonb
                   and (not campos ? 'ia' or campos->>'ia' in ('sí','posible','no'))
                   and (not campos ? 'calidad' or (jsonb_typeof(campos->'calidad') = 'number' and (campos->>'calidad')::int between 1 and 5))
                   and (not campos ? 'etiquetas' or jsonb_typeof(campos->'etiquetas') = 'array')),
  en_papelera_at timestamptz,
  eliminada_at   timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  updated_by     text default (auth.jwt() ->> 'email'),
  check (eliminada_at is null or en_papelera_at is not null)
);

create table if not exists public.fototeca_ediciones_historial (
  hid     bigint generated always as identity primary key,
  item_id text not null,
  op      text not null check (op in ('UPDATE','DELETE')),
  ts      timestamptz not null default now(),
  por     text default (auth.jwt() ->> 'email'),
  antes   jsonb not null
);
create index if not exists fototeca_ediciones_historial_item_idx
  on public.fototeca_ediciones_historial (item_id, ts desc);

create or replace function public.fototeca_ediciones_hist()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  insert into public.fototeca_ediciones_historial (item_id, op, antes)
  values (old.item_id, tg_op, to_jsonb(old));
  if tg_op = 'UPDATE' then
    new.updated_at := now();
    new.updated_by := coalesce(auth.jwt() ->> 'email', new.updated_by);
    return new;
  end if;
  return old;
end $$;

drop trigger if exists fototeca_ediciones_hist on public.fototeca_ediciones;
create trigger fototeca_ediciones_hist
  before update or delete on public.fototeca_ediciones
  for each row execute function public.fototeca_ediciones_hist();

alter table public.fototeca_ediciones enable row level security;
alter table public.fototeca_ediciones force row level security;
alter table public.fototeca_ediciones_historial enable row level security;
alter table public.fototeca_ediciones_historial force row level security;

-- leen los mismos que leen el bucket «fototeca»
drop policy if exists "lectores fototeca leen ediciones" on public.fototeca_ediciones;
create policy "lectores fototeca leen ediciones" on public.fototeca_ediciones
  for select to authenticated using (
    lower(auth.email()) in ('hola@casazaru.cl', 'crodriguez.casazaru@gmail.com', 'emerge.smm@gmail.com')
  );
drop policy if exists "admin lee historial fototeca" on public.fototeca_ediciones_historial;
create policy "admin lee historial fototeca" on public.fototeca_ediciones_historial
  for select to authenticated using (lower(auth.email()) = 'hola@casazaru.cl');

revoke all on public.fototeca_ediciones, public.fototeca_ediciones_historial from anon;
revoke insert, update, delete on public.fototeca_ediciones, public.fototeca_ediciones_historial from authenticated;
grant select on public.fototeca_ediciones, public.fototeca_ediciones_historial to authenticated;

-- ── único camino de escritura ──
-- p_accion: 'campos'    → mezcla p_campos sobre lo ya corregido (no pisa lo demás)
--           'papelera'  → a la papelera
--           'restaurar' → sale de la papelera
--           'vaciar'    → todo lo que está en la papelera queda eliminado (p_ids se ignora)
-- Devuelve cuántas piezas cambió.
create or replace function public.fototeca_editar(p_ids text[], p_accion text, p_campos jsonb default '{}'::jsonb)
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare n integer := 0;
begin
  if lower(coalesce(auth.email(), '')) <> 'hola@casazaru.cl' then
    raise exception 'Solo el admin puede editar la Fototeca';
  end if;
  if p_accion not in ('campos','papelera','restaurar','vaciar') then
    raise exception 'Acción desconocida: %', p_accion;
  end if;
  if p_accion = 'vaciar' then
    update public.fototeca_ediciones set eliminada_at = now()
     where en_papelera_at is not null and eliminada_at is null;
    get diagnostics n = row_count;
    return n;
  end if;
  if coalesce(array_length(p_ids, 1), 0) = 0 or array_length(p_ids, 1) > 2000 then
    raise exception 'Hay que mandar entre 1 y 2000 piezas';
  end if;
  -- las que no tienen fila todavía
  insert into public.fototeca_ediciones (item_id)
  select distinct unnest(p_ids) on conflict (item_id) do nothing;
  if p_accion = 'campos' then
    update public.fototeca_ediciones set campos = campos || coalesce(p_campos, '{}'::jsonb)
     where item_id = any(p_ids) and campos is distinct from campos || coalesce(p_campos, '{}'::jsonb);
  elsif p_accion = 'papelera' then
    update public.fototeca_ediciones set en_papelera_at = now()
     where item_id = any(p_ids) and en_papelera_at is null;
  else
    update public.fototeca_ediciones set en_papelera_at = null
     where item_id = any(p_ids) and en_papelera_at is not null and eliminada_at is null;
  end if;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.fototeca_editar(text[], text, jsonb) from public, anon;
grant execute on function public.fototeca_editar(text[], text, jsonb) to authenticated;

-- ── Verificación (debe dar 2 tablas con RLS forzada y la función) ──
select relname, relrowsecurity, relforcerowsecurity from pg_class
 where relname in ('fototeca_ediciones', 'fototeca_ediciones_historial');
select proname from pg_proc where proname = 'fototeca_editar';

-- ══ ROLLBACK (no correr salvo que se quiera deshacer todo; se pierden las correcciones) ══
-- drop function if exists public.fototeca_editar(text[], text, jsonb);
-- drop trigger if exists fototeca_ediciones_hist on public.fototeca_ediciones;
-- drop function if exists public.fototeca_ediciones_hist();
-- drop table if exists public.fototeca_ediciones_historial;
-- drop table if exists public.fototeca_ediciones;
