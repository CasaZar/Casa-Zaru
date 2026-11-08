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
-- «WhatsApp al día» · Cotizador (08-11-2026)
--
-- Lo que la revisión de WhatsApp (skill revision-whatsapp) encuentra sin
-- responder en el 5558 se muestra en el panel, arriba de «Hoy», SEPARADO del
-- seguimiento de cotizaciones y fuera de la meta del día.
--
-- Una fila por chat (chat_id = id del hilo en Meta Business Suite). Cada
-- revisión la reescribe con wa_cargar(); César la cierra con wa_marcar()
-- («Ya respondí» / «No corresponde»). Nadie escribe la tabla directo: solo
-- esas dos funciones. Lectura: solo el admin y César (el 5558 es de ellos).
-- Nada se borra: estado 'cerrado' cuando la revisión ya no lo trae, y cada
-- cambio deja la versión anterior en whatsapp_pendientes_historial.
-- Idempotente. Rollback al final.
-- ══════════════════════════════════════════════════════════════════════════

create table if not exists public.whatsapp_pendientes (
  id           uuid primary key default gen_random_uuid(),
  chat_id      text not null unique check (length(chat_id) between 1 and 80),
  cliente      text not null check (length(cliente) between 1 and 120),
  telefono     text check (telefono ~ '^[0-9]{8,15}$'),
  tipo         text not null check (tipo in ('responder','promesa','plata')),
  prioridad    smallint not null default 50 check (prioridad between 0 and 999),
  espera_desde timestamptz,
  contexto     text check (length(contexto) <= 600),
  cita         text check (length(cita) <= 400),
  mensaje      text check (length(mensaje) <= 1500),
  monto        integer check (monto >= 0),
  pedido       text check (length(pedido) <= 20),
  revision_at  timestamptz not null,
  estado       text not null default 'pendiente'
               check (estado in ('pendiente','respondido','no_corresponde','cerrado')),
  resuelto_at  timestamptz,
  resuelto_por text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  updated_by   text default (auth.jwt() ->> 'email'),
  deleted_at   timestamptz
);
create index if not exists whatsapp_pendientes_estado_idx
  on public.whatsapp_pendientes (estado, prioridad);

-- historial: la versión ANTERIOR de cada fila, en cada cambio
create table if not exists public.whatsapp_pendientes_historial (
  hid     bigint generated always as identity primary key,
  fila_id uuid not null,
  op      text not null check (op in ('UPDATE','DELETE')),
  ts      timestamptz not null default now(),
  por     text default (auth.jwt() ->> 'email'),
  antes   jsonb not null
);
create index if not exists whatsapp_pendientes_historial_fila_idx
  on public.whatsapp_pendientes_historial (fila_id, ts desc);

create or replace function public.whatsapp_pendientes_hist()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  insert into public.whatsapp_pendientes_historial (fila_id, op, antes)
  values (old.id, tg_op, to_jsonb(old));
  if tg_op = 'UPDATE' then
    new.updated_at := now();
    new.updated_by := coalesce(auth.jwt() ->> 'email', new.updated_by);
    return new;
  end if;
  return old;
end $$;

drop trigger if exists whatsapp_pendientes_hist on public.whatsapp_pendientes;
create trigger whatsapp_pendientes_hist
  before update or delete on public.whatsapp_pendientes
  for each row execute function public.whatsapp_pendientes_hist();

-- RLS: el equipo del 5558 lee; nadie escribe directo
alter table public.whatsapp_pendientes enable row level security;
alter table public.whatsapp_pendientes force row level security;
alter table public.whatsapp_pendientes_historial enable row level security;
alter table public.whatsapp_pendientes_historial force row level security;

drop policy if exists "5558 lee pendientes" on public.whatsapp_pendientes;
create policy "5558 lee pendientes" on public.whatsapp_pendientes
  for select to authenticated using (
    auth.email() in ('hola@casazaru.cl', 'crodriguez.casazaru@gmail.com')
    and deleted_at is null
  );

revoke all on public.whatsapp_pendientes from anon;
revoke insert, update, delete on public.whatsapp_pendientes from authenticated;
grant select on public.whatsapp_pendientes to authenticated;
revoke all on public.whatsapp_pendientes_historial from anon, authenticated;

-- ── wa_cargar: la revisión sube lo que encontró (solo el admin) ──
-- p_filas = [{chat_id, cliente, telefono, tipo, prioridad, espera_desde,
--             contexto, cita, mensaje, monto, pedido}, ...]
-- · chat que viene  → queda 'pendiente' con los datos nuevos, SALVO que César
--   lo haya cerrado después de la hora de la revisión (su marca es más nueva).
-- · chat pendiente que NO viene → 'cerrado' (la revisión ya no lo ve abierto).
create or replace function public.wa_cargar(p_revision timestamptz, p_filas jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  f jsonb; n_nuevos int := 0; n_act int := 0; n_resp int := 0; n_cerr int := 0;
  ids text[] := '{}'; r public.whatsapp_pendientes;
begin
  if coalesce(auth.email(), '') <> 'hola@casazaru.cl' then
    raise exception 'Solo el admin carga la revisión de WhatsApp';
  end if;
  if p_revision is null or p_revision > now() + interval '5 minutes' then
    raise exception 'Hora de revisión inválida';
  end if;
  if jsonb_typeof(p_filas) <> 'array' or jsonb_array_length(p_filas) > 200 then
    raise exception 'p_filas debe ser una lista de hasta 200 chats';
  end if;

  for f in select * from jsonb_array_elements(p_filas) loop
    ids := ids || (f ->> 'chat_id');
    select * into r from public.whatsapp_pendientes where chat_id = f ->> 'chat_id';
    if not found then
      insert into public.whatsapp_pendientes
        (chat_id, cliente, telefono, tipo, prioridad, espera_desde, contexto, cita,
         mensaje, monto, pedido, revision_at)
      values
        (f ->> 'chat_id', f ->> 'cliente', nullif(f ->> 'telefono', ''), f ->> 'tipo',
         coalesce((f ->> 'prioridad')::smallint, 50), (f ->> 'espera_desde')::timestamptz,
         f ->> 'contexto', f ->> 'cita', f ->> 'mensaje', (f ->> 'monto')::integer,
         f ->> 'pedido', p_revision);
      n_nuevos := n_nuevos + 1;
    elsif r.estado in ('respondido','no_corresponde') and r.resuelto_at >= p_revision then
      n_resp := n_resp + 1;          -- César lo cerró después de la revisión: manda él
    else
      update public.whatsapp_pendientes set
        cliente = f ->> 'cliente', telefono = nullif(f ->> 'telefono', ''), tipo = f ->> 'tipo',
        prioridad = coalesce((f ->> 'prioridad')::smallint, 50),
        espera_desde = (f ->> 'espera_desde')::timestamptz, contexto = f ->> 'contexto',
        cita = f ->> 'cita', mensaje = f ->> 'mensaje', monto = (f ->> 'monto')::integer,
        pedido = f ->> 'pedido', revision_at = p_revision, estado = 'pendiente',
        resuelto_at = null, resuelto_por = null, deleted_at = null
      where id = r.id;
      n_act := n_act + 1;
    end if;
  end loop;

  update public.whatsapp_pendientes set
    estado = 'cerrado', resuelto_at = now(), resuelto_por = 'revision'
  where estado = 'pendiente' and revision_at < p_revision and not (chat_id = any(ids));
  get diagnostics n_cerr = row_count;

  return jsonb_build_object('nuevos', n_nuevos, 'actualizados', n_act,
                            'ya_resueltos', n_resp, 'cerrados', n_cerr);
end $$;

-- ── wa_marcar: «Ya respondí» / «No corresponde» / deshacer (admin y César) ──
create or replace function public.wa_marcar(p_id uuid, p_estado text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if coalesce(auth.email(), '') not in ('hola@casazaru.cl', 'crodriguez.casazaru@gmail.com') then
    raise exception 'Sin acceso';
  end if;
  if p_estado not in ('pendiente','respondido','no_corresponde') then
    raise exception 'Estado inválido: %', p_estado;
  end if;
  update public.whatsapp_pendientes set
    estado = p_estado,
    resuelto_at  = case when p_estado = 'pendiente' then null else now() end,
    resuelto_por = case when p_estado = 'pendiente' then null else auth.email() end
  where id = p_id and deleted_at is null;
  if not found then raise exception 'No existe ese chat'; end if;
end $$;

revoke all on function public.wa_cargar(timestamptz, jsonb) from public, anon;
revoke all on function public.wa_marcar(uuid, text) from public, anon;
grant execute on function public.wa_cargar(timestamptz, jsonb) to authenticated;
grant execute on function public.wa_marcar(uuid, text) to authenticated;
revoke all on function public.whatsapp_pendientes_hist() from public, anon, authenticated;

-- ── Verificación (debe dar 2 tablas con RLS forzado y 2 funciones) ──
select c.relname, c.relrowsecurity as rls, c.relforcerowsecurity as forzado
from pg_class c where c.relname in ('whatsapp_pendientes','whatsapp_pendientes_historial');
select proname from pg_proc where proname in ('wa_cargar','wa_marcar');

-- ══ ROLLBACK (no correr salvo que se quiera deshacer todo) ══
-- drop function if exists public.wa_cargar(timestamptz, jsonb);
-- drop function if exists public.wa_marcar(uuid, text);
-- drop trigger if exists whatsapp_pendientes_hist on public.whatsapp_pendientes;
-- drop function if exists public.whatsapp_pendientes_hist();
-- drop table if exists public.whatsapp_pendientes_historial;
-- drop table if exists public.whatsapp_pendientes;
