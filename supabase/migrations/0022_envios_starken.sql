-- ── CANDADO DE PROYECTO (no borrar) ──────────────────────────────────────
-- Este archivo es de GESTIÓN (padnttpgzuotxeipjrry). Si se pega en el SQL
-- Editor de otro proyecto, este bloque falla primero y Postgres descarta el
-- resto del script: no se aplica nada.
do $candado$
begin
  if to_regclass('public.gestion_pedidos') is null then
    raise exception 'PROYECTO EQUIVOCADO: este SQL es de GESTIÓN (padnttpgzuotxeipjrry) y aquí no existe gestion_pedidos. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- 0022 · Envíos Starken emitidos desde la Gestión (24-10-2026)
--
-- Botón «Enviar con Starken» de Producción (solo admin): la Edge Function
-- starken-emitir crea la orden de flete (OF) en Starken y la anota acá. Una OF
-- es dinero y no se puede modificar una vez creada (solo anular), así que:
--
--   · CANDADO: antes de llamar a Starken se inserta la fila en 'emitiendo'.
--     El índice único parcial impide una segunda OF activa para el mismo
--     pedido: un doble clic o dos pestañas chocan acá, no en Starken.
--   · Nada se borra: una OF anulada queda con estado 'anulada'. No hay policy
--     de DELETE.
--   · Historial: cada cambio guarda la versión anterior en
--     envios_starken_historial (contrato de confiabilidad, 22-10-2026).
--
-- Ninguna credencial pasa por esta tabla: `solicitud` es lo que se mandó a
-- Starken SIN usuario ni clave (los quita la función).
-- Antes de aplicar: mirar supabase_migrations.schema_migrations; si la 0022 ya
-- existe, renumerar. Idempotente.
-- ══════════════════════════════════════════════════════════════════════════

create table if not exists public.envios_starken (
  id               bigint generated always as identity primary key,
  pedido           text not null references public.gestion_pedidos(num) on delete restrict,
  estado           text not null default 'emitiendo'
                   check (estado in ('emitiendo','emitida','error','anulada')),
  of_numero        text,
  destinatario     jsonb not null,              -- nombre, apellidos, teléfono, correo, dirección, comuna
  bultos           integer not null default 1 check (bultos between 1 and 30),
  kilos            numeric(10,3) not null check (kilos > 0 and kilos <= 2000),
  medidas          jsonb not null,              -- {largo, ancho, alto, modo: 'web'|'reales'} en cm
  valor_declarado  integer not null default 0 check (valor_declarado >= 0),
  precio_cotizado  integer check (precio_cotizado >= 0),   -- lo que mostró Starken antes de emitir, con IVA
  cuenta           text,
  solicitud        jsonb,                       -- lo enviado a Starken, sin credenciales
  respuesta        jsonb,                       -- lo que devolvió Starken
  error            text,
  anulada_at       timestamptz,
  created_at       timestamptz not null default now(),
  created_by       text default (auth.jwt() ->> 'email'),
  updated_at       timestamptz not null default now(),
  updated_by       text default (auth.jwt() ->> 'email'),
  constraint envios_starken_of_si_emitida check (estado <> 'emitida' or of_numero is not null)
);

create index if not exists envios_starken_pedido_idx on public.envios_starken (pedido);
-- El candado: una sola OF viva (emitiéndose o emitida) por pedido.
create unique index if not exists envios_starken_una_activa
  on public.envios_starken (pedido) where estado in ('emitiendo','emitida');
create unique index if not exists envios_starken_of_idx
  on public.envios_starken (of_numero) where of_numero is not null;

-- ── Historial: la versión anterior de cada fila ───────────────────────────
create table if not exists public.envios_starken_historial (
  id        bigint generated always as identity primary key,
  envio_id  bigint not null,
  ts        timestamptz not null default now(),
  por       text default (auth.jwt() ->> 'email'),
  accion    text not null check (accion in ('UPDATE','DELETE')),
  anterior  jsonb not null
);
create index if not exists envios_starken_historial_idx on public.envios_starken_historial (envio_id, ts);

create or replace function public.envios_starken_antes()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  new.updated_by := coalesce(auth.jwt() ->> 'email', new.updated_by);
  new.created_at := old.created_at;      -- lo creado no se reescribe
  new.created_by := old.created_by;
  new.pedido     := old.pedido;          -- una OF no cambia de pedido
  if old.estado = 'anulada' and new.estado <> 'anulada' then
    raise exception 'Una OF anulada no vuelve a activarse: emite una nueva';
  end if;
  return new;
end $$;
drop trigger if exists tr_envios_starken_antes on public.envios_starken;
create trigger tr_envios_starken_antes before update on public.envios_starken
  for each row execute function public.envios_starken_antes();

create or replace function public.envios_starken_historial_guardar()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.envios_starken_historial (envio_id, accion, anterior)
  values (old.id, tg_op, to_jsonb(old));
  return coalesce(new, old);
end $$;
drop trigger if exists tr_envios_starken_historial on public.envios_starken;
create trigger tr_envios_starken_historial after update or delete on public.envios_starken
  for each row execute function public.envios_starken_historial_guardar();

-- ── RLS: solo el admin (decisión del dueño, 20-10-2026) ──────────────────
alter table public.envios_starken enable row level security;
alter table public.envios_starken force row level security;
alter table public.envios_starken_historial enable row level security;
alter table public.envios_starken_historial force row level security;

drop policy if exists envios_starken_leer on public.envios_starken;
create policy envios_starken_leer on public.envios_starken
  for select to authenticated using (es_admin());
drop policy if exists envios_starken_crear on public.envios_starken;
create policy envios_starken_crear on public.envios_starken
  for insert to authenticated with check (es_admin());
drop policy if exists envios_starken_editar on public.envios_starken;
create policy envios_starken_editar on public.envios_starken
  for update to authenticated using (es_admin()) with check (es_admin());
-- Sin policy de DELETE: una OF no se borra, se anula.

drop policy if exists envios_starken_historial_leer on public.envios_starken_historial;
create policy envios_starken_historial_leer on public.envios_starken_historial
  for select to authenticated using (es_admin());

grant select, insert, update on public.envios_starken to authenticated;
grant select on public.envios_starken_historial to authenticated;
revoke all on public.envios_starken from anon;
revoke all on public.envios_starken_historial from anon;

-- Rollback (solo si la tabla está vacía; con OF reales, NO):
--   drop trigger tr_envios_starken_historial on public.envios_starken;
--   drop trigger tr_envios_starken_antes on public.envios_starken;
--   drop function public.envios_starken_historial_guardar(); drop function public.envios_starken_antes();
--   drop table public.envios_starken_historial; drop table public.envios_starken;

-- Registrar en el panel (Database → Migrations), pegándolo junto con este archivo:
-- insert into supabase_migrations.schema_migrations (version, name, statements)
-- values ('0022', 'envios_starken', array[$m0022$ <este archivo> $m0022$]);
