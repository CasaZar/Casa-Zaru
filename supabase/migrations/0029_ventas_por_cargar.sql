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
-- 0029 · Ventas por cargar: del Cotizador a Producción (11-11-2026)
--
-- Etapa 2 de conectar el Cotizador con la Gestión. Cuando el cliente confirma
-- la ficha de venta en el panel del Cotizador (otro proyecto Supabase,
-- cmxqorsyxoltrakxawro), el panel la manda acá. En Producción aparece en la
-- banda «Por cargar»; el admin la carga como pedido con el formulario de
-- siempre (confirmOrder) o la descarta con un motivo.
--
-- El panel del Cotizador NO tiene sesión en este proyecto: llega como anon.
-- Por eso anon no tiene NINGÚN permiso sobre la tabla: solo puede ejecutar
-- recibir_venta_cotizador(), que valida, inserta y no devuelve datos. No puede
-- leer, cambiar ni borrar nada de la Gestión. Lo que llegue nunca se convierte
-- solo en pedido: alguien lo revisa en la banda.
--
-- Una cotización = una fila (unique cotizacion_id): reintentos y dobles toques
-- no duplican. Si se descartó y el cliente vuelve a confirmar, la misma fila
-- vuelve a «por_cargar» con la ficha nueva (queda la anterior en historial).
-- Cargada es final y apunta al pedido (pedido_num).
--
-- Antes de aplicar: mirar supabase_migrations.schema_migrations; si la 0029
-- ya existe, renumerar. Idempotente.
-- ══════════════════════════════════════════════════════════════════════════

create table if not exists public.ventas_por_cargar (
  id             bigint generated always as identity primary key,
  cotizacion_id  uuid not null unique,
  cotizacion_num text check (cotizacion_num is null or length(cotizacion_num) <= 40),
  cliente        text not null check (length(btrim(cliente)) between 1 and 200),
  contacto       text check (contacto is null or length(contacto) <= 200),
  vendedor       text check (vendedor is null or length(vendedor) <= 60),
  total          integer not null check (total > 0 and total < 1000000000),
  ficha          jsonb not null check (jsonb_typeof(ficha) = 'object' and length(ficha::text) <= 20000),
  estado         text not null default 'por_cargar' check (estado in ('por_cargar','cargada','descartada')),
  pedido_num     text,
  motivo         text check (motivo is null or length(motivo) <= 300),
  recibida_at    timestamptz not null default now(),
  cargada_at     timestamptz,
  created_at     timestamptz not null default now(),
  created_by     text default coalesce(auth.jwt() ->> 'email', 'cotizador'),
  updated_at     timestamptz not null default now(),
  updated_by     text default coalesce(auth.jwt() ->> 'email', 'cotizador'),
  constraint vpc_cargada_con_pedido check ((estado = 'cargada') = (pedido_num is not null)),
  constraint vpc_descartada_con_motivo check (estado <> 'descartada' or length(btrim(coalesce(motivo,''))) > 0)
);
comment on table public.ventas_por_cargar is 'Fichas de venta confirmadas en el panel del Cotizador, por cargar como pedido en Producción (0029). Entran solo por recibir_venta_cotizador(); nunca se borran.';

-- Un pedido viene de una sola ficha.
create unique index if not exists vpc_pedido_unico
  on public.ventas_por_cargar (pedido_num) where pedido_num is not null;
create index if not exists vpc_estado_idx on public.ventas_por_cargar (estado, recibida_at);

create table if not exists public.ventas_por_cargar_historial (
  id        bigint generated always as identity primary key,
  venta_id  bigint not null,
  ts        timestamptz not null default now(),
  por       text default coalesce(auth.jwt() ->> 'email', 'cotizador'),
  accion    text not null check (accion in ('UPDATE','DELETE')),
  anterior  jsonb not null
);
create index if not exists vpc_hist_idx on public.ventas_por_cargar_historial (venta_id, ts);

-- Reglas de cambio. Desde la Gestión solo se carga o se descarta; la ficha no
-- se edita (se corrige en el formulario del pedido). La única forma de volver
-- a «por_cargar» es que el Cotizador la mande de nuevo (función de abajo).
create or replace function public.ventas_por_cargar_antes()
returns trigger language plpgsql as $$
begin
  if new.cotizacion_id is distinct from old.cotizacion_id then
    raise exception 'La cotización de una venta por cargar no cambia';
  end if;
  if old.estado = 'cargada' then
    raise exception 'Esta venta ya se cargó como el pedido %: no cambia más', old.pedido_num;
  end if;
  if new.estado = 'por_cargar' then
    if old.estado = 'por_cargar' and (new.ficha, new.cliente, new.contacto, new.vendedor, new.total, new.cotizacion_num)
       is distinct from (old.ficha, old.cliente, old.contacto, old.vendedor, old.total, old.cotizacion_num)
       and coalesce(current_setting('zaru.vpc_reenvio', true), '') <> 'si' then
      raise exception 'La ficha no se edita en la Gestión: cárgala y corrige el pedido';
    end if;
    if old.estado = 'descartada' and coalesce(current_setting('zaru.vpc_reenvio', true), '') <> 'si' then
      raise exception 'Una venta descartada vuelve solo si el Cotizador la manda de nuevo';
    end if;
    new.motivo := null;
  else
    if (new.ficha, new.cliente, new.contacto, new.vendedor, new.total, new.cotizacion_num)
       is distinct from (old.ficha, old.cliente, old.contacto, old.vendedor, old.total, old.cotizacion_num) then
      raise exception 'La ficha no se edita en la Gestión: cárgala y corrige el pedido';
    end if;
  end if;
  if new.estado = 'cargada' and old.estado <> 'cargada' then new.cargada_at := now(); end if;
  new.updated_at := now();
  new.updated_by := coalesce(auth.jwt() ->> 'email', 'cotizador');
  new.created_at := old.created_at;
  new.created_by := old.created_by;
  return new;
end $$;
drop trigger if exists tr_vpc_antes on public.ventas_por_cargar;
create trigger tr_vpc_antes before update on public.ventas_por_cargar
  for each row execute function public.ventas_por_cargar_antes();

create or replace function public.ventas_por_cargar_historial_guardar()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.ventas_por_cargar_historial (venta_id, accion, anterior)
  values (old.id, tg_op, to_jsonb(old));
  return coalesce(new, old);
end $$;
drop trigger if exists tr_vpc_historial on public.ventas_por_cargar;
create trigger tr_vpc_historial after update or delete on public.ventas_por_cargar
  for each row execute function public.ventas_por_cargar_historial_guardar();


-- ── La única puerta de entrada desde el Cotizador ───────────────────────
-- Devuelve 'nueva', 'ya_estaba' (reintento: no cambia nada), 'reabierta'
-- (estaba descartada y volvió) o 'ya_cargada'. Nunca devuelve datos.
create or replace function public.recibir_venta_cotizador(p jsonb)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_cot   uuid;
  v_fila  public.ventas_por_cargar%rowtype;
  v_total integer;
begin
  if p is null or jsonb_typeof(p) <> 'object' or length(p::text) > 20000 then
    raise exception 'ficha inválida';
  end if;
  begin
    v_cot := (p->>'cotizacion_id')::uuid;
  exception when others then
    raise exception 'cotizacion_id inválido';
  end;
  if v_cot is null then raise exception 'falta cotizacion_id'; end if;
  if jsonb_typeof(p->'ficha') <> 'object' or p->'ficha'->>'estado' <> 'confirmada' then
    raise exception 'la ficha no está confirmada';
  end if;
  v_total := round((p->'ficha'->'calc'->>'total')::numeric);
  -- freno contra un llenado masivo con la llave pública
  if (select count(*) from public.ventas_por_cargar where estado = 'por_cargar') >= 300 then
    raise exception 'demasiadas ventas por cargar: revisar la Gestión';
  end if;

  select * into v_fila from public.ventas_por_cargar where cotizacion_id = v_cot;
  if not found then
    insert into public.ventas_por_cargar (cotizacion_id, cotizacion_num, cliente, contacto, vendedor, total, ficha)
    values (v_cot, left(nullif(p->>'cotizacion_num',''), 40), left(btrim(p->>'cliente'), 200), left(p->>'contacto', 200),
            left(p->>'vendedor', 60), v_total, p->'ficha');
    return 'nueva';
  end if;
  if v_fila.estado = 'cargada' then return 'ya_cargada'; end if;
  if v_fila.estado = 'por_cargar' then return 'ya_estaba'; end if;
  perform set_config('zaru.vpc_reenvio', 'si', true);
  update public.ventas_por_cargar
     set estado = 'por_cargar', ficha = p->'ficha', total = v_total, cliente = left(btrim(p->>'cliente'), 200),
         contacto = left(p->>'contacto', 200), vendedor = left(p->>'vendedor', 60),
         cotizacion_num = left(nullif(p->>'cotizacion_num',''), 40), recibida_at = now()
   where id = v_fila.id;
  perform set_config('zaru.vpc_reenvio', '', true);
  return 'reabierta';
end $$;
revoke all on function public.recibir_venta_cotizador(jsonb) from public;
grant execute on function public.recibir_venta_cotizador(jsonb) to anon, authenticated;

-- ── Y la vuelta: qué pasó con cada ficha ────────────────────────────────
-- El panel pregunta por SUS cotizaciones (uuid que solo él conoce) y recibe
-- el estado, el N° de pedido si ya se cargó y el motivo si se descartó. Así
-- la cotización muestra su pedido y, si se descartó, vuelve a abrirse. Nada
-- más sale de la Gestión. Máximo 200 por llamada.
create or replace function public.estado_ventas_cotizador(ids uuid[])
returns table (cotizacion_id uuid, estado text, pedido_num text, motivo text)
language sql stable security definer set search_path = public as $$
  select v.cotizacion_id, v.estado, v.pedido_num, v.motivo
    from public.ventas_por_cargar v
   where ids is not null and cardinality(ids) <= 200 and v.cotizacion_id = any(ids);
$$;
revoke all on function public.estado_ventas_cotizador(uuid[]) from public;
grant execute on function public.estado_ventas_cotizador(uuid[]) to anon, authenticated;


-- ── RLS ───────────────────────────────────────────────────────────────────
-- Solo el admin ve la banda, carga y descarta. Nadie borra. anon no toca la
-- tabla: entra solo por la función de arriba.
alter table public.ventas_por_cargar           enable row level security;
alter table public.ventas_por_cargar           force  row level security;
alter table public.ventas_por_cargar_historial enable row level security;
alter table public.ventas_por_cargar_historial force  row level security;

drop policy if exists vpc_leer on public.ventas_por_cargar;
create policy vpc_leer on public.ventas_por_cargar
  for select to authenticated using (public.zaru_rol() = 'admin');
drop policy if exists vpc_cambiar on public.ventas_por_cargar;
create policy vpc_cambiar on public.ventas_por_cargar
  for update to authenticated
  using (public.zaru_rol() = 'admin')
  with check (public.zaru_rol() = 'admin' and estado in ('cargada','descartada'));

drop policy if exists vpc_hist_leer on public.ventas_por_cargar_historial;
create policy vpc_hist_leer on public.ventas_por_cargar_historial
  for select to authenticated using (public.zaru_rol() = 'admin');

grant select, update on public.ventas_por_cargar to authenticated;
grant select on public.ventas_por_cargar_historial to authenticated;
revoke all on public.ventas_por_cargar, public.ventas_por_cargar_historial from anon;


-- Rollback (las ventas recibidas se pierden; respaldarlas antes con
--   select * from public.ventas_por_cargar;):
--   drop function public.recibir_venta_cotizador(jsonb); drop function public.estado_ventas_cotizador(uuid[]);
--   drop table public.ventas_por_cargar_historial; drop table public.ventas_por_cargar;
--   drop function public.ventas_por_cargar_historial_guardar(); drop function public.ventas_por_cargar_antes();

-- Registrar en el panel (Database → Migrations), pegándolo junto con este archivo:
-- insert into supabase_migrations.schema_migrations (version, name, statements)
-- values ('0029', 'ventas_por_cargar', array[$m0029$ <este archivo> $m0029$]);
