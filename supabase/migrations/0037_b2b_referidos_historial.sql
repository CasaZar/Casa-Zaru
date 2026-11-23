-- ── CANDADO DE PROYECTO (no borrar) ──────────────────────────────────────
-- Este archivo es de GESTIÓN (padnttpgzuotxeipjrry). Si se pega en el SQL
-- Editor de otro proyecto, este bloque falla primero y Postgres descarta el
-- resto del script: no se aplica nada.
do $candado$
begin
  if to_regclass('public.gestion_pedidos') is null then
    raise exception 'PROYECTO EQUIVOCADO: este SQL es de GESTIÓN (padnttpgzuotxeipjrry) y aquí no existe gestion_pedidos. No se aplicó nada.';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'b2b_empresas' and column_name = 'profesional') then
    raise exception 'Falta la migración 0036 (b2b_empresas.profesional). Correrla primero.';
  end if;
  if to_regclass('public.ventas_por_cargar') is null then
    raise exception 'Falta ventas_por_cargar (ficha de venta del cotizador).';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- 0037 · Cuenta Casa Zaru: historial y ventas referidas (23-11-2026)
--
-- 1) HISTORIAL. b2b_empresas y b2b_compras ganan updated_at / updated_by y
--    una tabla *_historial con la versión anterior de cada UPDATE o DELETE
--    (contrato de confiabilidad). Mismo patrón que b2b_avisos (0026).
--
-- 2) VENTAS REFERIDAS. Decisión del dueño, 23-11-2026: lo que compra un
--    cliente que trae un profesional suma COMPLETO a la cuenta de ese
--    profesional. Cada documento (boleta o factura) del pedido deja una fila
--    tipo 'REFERIDA', origen 'referido', en la cuenta del profesional.
--    · Quién es el profesional del pedido: gestion_finanzas.data->'prof'
--      si existe la clave (la Gestión la escribe al cargar la ficha y se
--      puede corregir ahí; null = sin profesional); si no, la ficha de venta
--      del cotizador (ventas_por_cargar.ficha->'prof') ya cargada a ese pedido.
--    · Si el documento es una FACTURA al mismo RUT del profesional, no se
--      duplica: esa ya suma por b2b_desde_documento.
--    · Si el profesional no tiene cuenta, se abre sola (profesional = true).
--      Si tiene una cuenta desactivada, no se toca nada.
--    · Si al pedido se le quita el profesional, sus filas quedan anuladas
--      (no se borran). Si se cambia de profesional, la fila se mueve.
--    Un documento puede quedar dos veces en b2b_compras (la factura de la
--    empresa cliente y la referida del profesional): el índice único de
--    documento se separa en dos parciales.
--
-- Antes de aplicar: mirar supabase_migrations.schema_migrations; si la 0037
-- ya existe, renumerar. Idempotente.
--
-- ROLLBACK (respaldar antes las filas origen = 'referido' y los historiales):
--   drop trigger tr_b2b_referido_doc on public.gestion_documentos;
--   drop trigger tr_b2b_referido_fin on public.gestion_finanzas;
--   drop trigger tr_b2b_referido_vpc on public.ventas_por_cargar;
--   drop function public.b2b_referido_trg(); drop function public.b2b_referidos_sync(text);
--   drop function public.b2b_prof_de_pedido(text);
--   delete from public.b2b_compras where tipo = 'REFERIDA';
--   drop index public.b2b_compras_ref_idx; drop index public.b2b_compras_doc_idx;
--   create unique index b2b_compras_doc_idx on public.b2b_compras (documento_id) where documento_id is not null;
--   recrear b2b_desde_documento con «on conflict (documento_id) where documento_id is not null»;
--   restaurar los check de tipo (FACTURA, NC) y origen (app, wasabil, manual);
--   drop trigger tr_b2b_empresas_historial / tr_b2b_compras_historial / tr_b2b_*_tocar;
--   drop table public.b2b_empresas_historial, public.b2b_compras_historial;
--   alter table … drop column updated_at, drop column updated_by (en las dos).
-- ══════════════════════════════════════════════════════════════════════════


-- ── 1) Historial ─────────────────────────────────────────────────────────
alter table public.b2b_empresas add column if not exists updated_at timestamptz,
                                add column if not exists updated_by text;
alter table public.b2b_compras  add column if not exists updated_at timestamptz,
                                add column if not exists updated_by text;

create or replace function public.b2b_tocar()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  new.updated_by := coalesce(auth.jwt() ->> 'email', current_user);
  return new;
end $$;

drop trigger if exists tr_b2b_empresas_tocar on public.b2b_empresas;
create trigger tr_b2b_empresas_tocar before update on public.b2b_empresas
  for each row execute function public.b2b_tocar();
drop trigger if exists tr_b2b_compras_tocar on public.b2b_compras;
create trigger tr_b2b_compras_tocar before update on public.b2b_compras
  for each row execute function public.b2b_tocar();

create table if not exists public.b2b_empresas_historial (
  id         bigint generated always as identity primary key,
  empresa_id bigint not null,
  ts         timestamptz not null default now(),
  por        text default (auth.jwt() ->> 'email'),
  accion     text not null check (accion in ('UPDATE', 'DELETE')),
  anterior   jsonb not null
);
create index if not exists b2b_empresas_hist_idx on public.b2b_empresas_historial (empresa_id, ts);

create table if not exists public.b2b_compras_historial (
  id        bigint generated always as identity primary key,
  compra_id bigint not null,
  ts        timestamptz not null default now(),
  por       text default (auth.jwt() ->> 'email'),
  accion    text not null check (accion in ('UPDATE', 'DELETE')),
  anterior  jsonb not null
);
create index if not exists b2b_compras_hist_idx on public.b2b_compras_historial (compra_id, ts);

create or replace function public.b2b_empresas_historial_guardar()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.b2b_empresas_historial (empresa_id, accion, anterior)
  values (old.id, tg_op, to_jsonb(old));
  return coalesce(new, old);
end $$;
drop trigger if exists tr_b2b_empresas_historial on public.b2b_empresas;
create trigger tr_b2b_empresas_historial after update or delete on public.b2b_empresas
  for each row execute function public.b2b_empresas_historial_guardar();

create or replace function public.b2b_compras_historial_guardar()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.b2b_compras_historial (compra_id, accion, anterior)
  values (old.id, tg_op, to_jsonb(old));
  return coalesce(new, old);
end $$;
drop trigger if exists tr_b2b_compras_historial on public.b2b_compras;
create trigger tr_b2b_compras_historial after update or delete on public.b2b_compras
  for each row execute function public.b2b_compras_historial_guardar();

alter table public.b2b_empresas_historial enable row level security;
alter table public.b2b_empresas_historial force  row level security;
alter table public.b2b_compras_historial  enable row level security;
alter table public.b2b_compras_historial  force  row level security;
drop policy if exists b2b_empresas_hist_leer on public.b2b_empresas_historial;
create policy b2b_empresas_hist_leer on public.b2b_empresas_historial
  for select to authenticated using (public.zaru_rol() = 'admin');
drop policy if exists b2b_compras_hist_leer on public.b2b_compras_historial;
create policy b2b_compras_hist_leer on public.b2b_compras_historial
  for select to authenticated using (public.zaru_rol() = 'admin');
grant select on public.b2b_empresas_historial, public.b2b_compras_historial to authenticated;
revoke all on public.b2b_empresas_historial, public.b2b_compras_historial from anon;


-- ── 2) Ventas referidas ──────────────────────────────────────────────────
alter table public.b2b_compras drop constraint if exists b2b_compras_tipo_check;
alter table public.b2b_compras add constraint b2b_compras_tipo_check
  check (tipo in ('FACTURA', 'NC', 'REFERIDA'));
alter table public.b2b_compras drop constraint if exists b2b_compras_origen_check;
alter table public.b2b_compras add constraint b2b_compras_origen_check
  check (origen in ('app', 'wasabil', 'manual', 'referido'));
comment on column public.b2b_compras.tipo is
  'FACTURA / NC de la propia cuenta, o REFERIDA: documento de un cliente que trajo este profesional (0037).';

-- Un documento: una fila propia (factura de la empresa) y, aparte, una referida.
drop index if exists public.b2b_compras_doc_idx;
create unique index b2b_compras_doc_idx on public.b2b_compras (documento_id)
  where documento_id is not null and tipo <> 'REFERIDA';
create unique index if not exists b2b_compras_ref_idx on public.b2b_compras (documento_id)
  where documento_id is not null and tipo = 'REFERIDA';

-- b2b_desde_documento: igual que antes, con el conflicto apuntando al índice nuevo.
create or replace function public.b2b_desde_documento()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_rut text;
  v_emp bigint;
  v_fin jsonb;
begin
  if new.tipo <> 'FACTURA' then return new; end if;
  v_rut := public.b2b_norm_rut(new.rut);
  if v_rut is null then return new; end if;

  select id into v_emp from public.b2b_empresas where rut = v_rut and activa;

  -- Empresa sin cuenta: se abre sola (solo RUT de empresa; las personas no).
  if v_emp is null and public.b2b_es_rut_empresa(v_rut)
     and not exists (select 1 from public.b2b_empresas where rut = v_rut) then
    select f.data into v_fin from public.gestion_finanzas f where f.num = new.num;
    insert into public.b2b_empresas (rut, razon_social, contacto, celular, email, giro, notas, creado_por)
    values (v_rut,
            coalesce(nullif(btrim(v_fin->>'razon_social'), ''), nullif(btrim(new.cliente), ''), 'Empresa ' || v_rut),
            nullif(btrim(new.cliente), ''),
            nullif(btrim(v_fin->>'celular'), ''),
            coalesce(nullif(btrim(new.email), ''), nullif(btrim(v_fin->>'email'), '')),
            nullif(btrim(v_fin->>'giro'), ''),
            'Cuenta abierta sola al emitir la factura' || coalesce(' ' || new.folio, '') || ' del pedido ' || new.num,
            new.creado_por)
    on conflict (rut) do nothing
    returning id into v_emp;
    if v_emp is null then select id into v_emp from public.b2b_empresas where rut = v_rut; end if;
  end if;

  if v_emp is null then return new; end if;
  insert into public.b2b_compras (empresa_id, fecha, monto, tipo, detalle, folio, pedido, origen, documento_id, anulada, creado_por)
  values (v_emp, coalesce(new.fecha, current_date), coalesce(new.monto, 0), 'FACTURA',
          coalesce(new.producto, new.detalle), new.folio, new.num, 'app', new.id, new.anulada, new.creado_por)
  on conflict (documento_id) where documento_id is not null and tipo <> 'REFERIDA' do update
    set fecha = excluded.fecha, monto = excluded.monto, detalle = excluded.detalle,
        folio = excluded.folio, anulada = excluded.anulada, empresa_id = excluded.empresa_id;
  return new;
end $$;

-- Quién es el profesional de un pedido. null = ninguno.
create or replace function public.b2b_prof_de_pedido(p_num text, out rut text, out nombre text)
language plpgsql stable security definer set search_path = public as $$
declare
  v_fin jsonb;
begin
  select f.data into v_fin from public.gestion_finanzas f where f.num = p_num;
  if v_fin ? 'prof' then
    -- La Gestión manda: lo que diga Finanzas (incluido «sin profesional»).
    rut    := public.b2b_norm_rut(v_fin->'prof'->>'rut');
    nombre := nullif(btrim(v_fin->'prof'->>'nombre'), '');
    if rut is null then nombre := null; end if;
    return;
  end if;
  select public.b2b_norm_rut(v.ficha->'prof'->>'rut'), nullif(btrim(v.ficha->'prof'->>'nombre'), '')
    into rut, nombre
  from public.ventas_por_cargar v
  where v.pedido_num = p_num and v.estado = 'cargada'
    and public.b2b_norm_rut(v.ficha->'prof'->>'rut') is not null
  order by v.id desc
  limit 1;
end $$;

-- Deja las filas REFERIDA de un pedido como corresponde. Idempotente.
create or replace function public.b2b_referidos_sync(p_num text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_rut text;
  v_nom text;
  v_emp bigint;
  d record;
begin
  if p_num is null or btrim(p_num) = '' then return; end if;
  select r.rut, r.nombre into v_rut, v_nom from public.b2b_prof_de_pedido(p_num) r;

  if v_rut is not null then
    select id into v_emp from public.b2b_empresas where rut = v_rut and activa;
    if v_emp is null then
      if exists (select 1 from public.b2b_empresas where rut = v_rut) then
        return;   -- cuenta desactivada: no se toca
      end if;
      insert into public.b2b_empresas (rut, razon_social, contacto, profesional, notas, creado_por)
      values (v_rut, coalesce(v_nom, 'Profesional ' || v_rut), v_nom, true,
              'Cuenta de profesional abierta sola por la venta referida del pedido ' || p_num,
              coalesce(auth.jwt() ->> 'email', 'b2b_referidos'))
      on conflict (rut) do nothing
      returning id into v_emp;
      if v_emp is null then select id into v_emp from public.b2b_empresas where rut = v_rut and activa; end if;
      if v_emp is null then return; end if;
    end if;
  end if;

  for d in
    select * from public.gestion_documentos
    where num = p_num and tipo in ('BOLETA', 'FACTURA')
  loop
    if v_emp is not null and not (d.tipo = 'FACTURA' and public.b2b_norm_rut(d.rut) = v_rut) then
      insert into public.b2b_compras (empresa_id, fecha, monto, tipo, detalle, folio, pedido, origen, documento_id, anulada, creado_por)
      values (v_emp, coalesce(d.fecha, d.creado::date), coalesce(d.monto, 0), 'REFERIDA',
              case when public.b2b_norm_rut(d.rut) = v_rut then 'Compra propia · pedido ' else 'Venta referida · pedido ' end || p_num,
              null, p_num, 'referido', d.id, d.anulada, coalesce(auth.jwt() ->> 'email', 'b2b_referidos'))
      on conflict (documento_id) where documento_id is not null and tipo = 'REFERIDA' do update
        set empresa_id = excluded.empresa_id, fecha = excluded.fecha, monto = excluded.monto,
            detalle = excluded.detalle, anulada = excluded.anulada
        where (b2b_compras.empresa_id, b2b_compras.fecha, b2b_compras.monto, b2b_compras.detalle, b2b_compras.anulada)
              is distinct from (excluded.empresa_id, excluded.fecha, excluded.monto, excluded.detalle, excluded.anulada);
    else
      update public.b2b_compras set anulada = true
      where documento_id = d.id and tipo = 'REFERIDA' and not anulada;
    end if;
  end loop;
end $$;

-- Un solo trigger para las tres tablas que pueden cambiar el resultado.
create or replace function public.b2b_referido_trg()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_table_name = 'gestion_documentos' then
    if new.tipo in ('BOLETA', 'FACTURA') then perform public.b2b_referidos_sync(new.num); end if;
    if tg_op = 'UPDATE' and old.num is distinct from new.num then perform public.b2b_referidos_sync(old.num); end if;
  elsif tg_table_name = 'gestion_finanzas' then
    if tg_op = 'INSERT' then
      if new.data ? 'prof' then perform public.b2b_referidos_sync(new.num); end if;
    elsif old.data->'prof' is distinct from new.data->'prof' or (old.data ? 'prof') <> (new.data ? 'prof') then
      perform public.b2b_referidos_sync(new.num);
    end if;
  elsif tg_table_name = 'ventas_por_cargar' then
    if tg_op = 'INSERT' or old.pedido_num is distinct from new.pedido_num
       or old.estado is distinct from new.estado
       or old.ficha->'prof' is distinct from new.ficha->'prof' then
      perform public.b2b_referidos_sync(new.pedido_num);
      if tg_op = 'UPDATE' and old.pedido_num is distinct from new.pedido_num then
        perform public.b2b_referidos_sync(old.pedido_num);
      end if;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists tr_b2b_referido_doc on public.gestion_documentos;
create trigger tr_b2b_referido_doc after insert or update on public.gestion_documentos
  for each row execute function public.b2b_referido_trg();
drop trigger if exists tr_b2b_referido_fin on public.gestion_finanzas;
create trigger tr_b2b_referido_fin after insert or update on public.gestion_finanzas
  for each row execute function public.b2b_referido_trg();
drop trigger if exists tr_b2b_referido_vpc on public.ventas_por_cargar;
create trigger tr_b2b_referido_vpc after insert or update on public.ventas_por_cargar
  for each row execute function public.b2b_referido_trg();

revoke all on function public.b2b_prof_de_pedido(text) from public, anon, authenticated;
revoke all on function public.b2b_referidos_sync(text) from public, anon, authenticated;

-- Lo que ya exista (fichas cargadas o Finanzas con profesional).
select public.b2b_referidos_sync(x.num)
from (
  select pedido_num as num from public.ventas_por_cargar where estado = 'cargada' and ficha ? 'prof'
  union
  select num from public.gestion_finanzas where data ? 'prof'
) x;

-- Registrar en el panel (Database → Migrations), pegándolo junto con este archivo:
-- insert into supabase_migrations.schema_migrations (version, name, statements)
-- values ('0037', 'b2b_referidos_historial', array[<etiqueta m0037 entre signos $> <este archivo> <la misma etiqueta>]);
