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
-- 0019 · Cuenta Casa Zaru para empresas (22-10-2026)
--
-- Una cuenta por empresa (RUT). Lo que compra se acumula por ciclos de 12
-- meses contados desde `inicio_ciclo`; sobre $1.500.000 acumulados la empresa
-- tiene 2 % de descuento en sus siguientes compras, sobre $3.000.000 un 5 %.
-- Es adicional al 5 % por transferencia del cotizador.
--
-- Dos tablas relacionales (como el módulo de gastos) y una vista:
--   b2b_empresas  la cuenta: RUT único, contacto, inicio del ciclo y un token
--                 para el link privado que ve el cliente.
--   b2b_compras   una fila por factura (monto con IVA, negativo si es nota de
--                 crédito). Origen: 'app' (la emitió Finanzas y la sumó el
--                 trigger), 'wasabil' (historia cargada una vez desde Wasabil)
--                 o 'manual' (botón «+ Compra a mano»).
--   v_b2b_cuentas ciclo vigente, acumulado, tramo y cuánto falta. LA FÓRMULA
--                 VIVE ACÁ, no en JS.
--
-- El trigger sobre gestion_documentos suma sola cada FACTURA que se emite
-- desde la app si el RUT es de una empresa registrada, y la marca anulada
-- cuando se anula con nota de crédito. Al registrar una empresa nueva se
-- enganchan las facturas que ya estaban en gestion_documentos con ese RUT.
--
-- La función b2b_estado(token) es lo único que puede leer la llave pública:
-- devuelve la cuenta de UNA empresa por su token (24 hex al azar), sin montos
-- de nadie más. Idempotente.
-- ══════════════════════════════════════════════════════════════════════════

-- RUT normalizado: sin puntos, dígito verificador en mayúscula, con guion.
-- '77.101.795-9' → '77101795-9'. Vacío o basura → null.
create or replace function public.b2b_norm_rut(p text)
returns text language sql immutable as $$
  select case
    when p is null then null
    when length(regexp_replace(upper(p), '[^0-9K]', '', 'g')) < 7 then null
    else regexp_replace(regexp_replace(upper(p), '[^0-9K]', '', 'g'), '(.)$', '-\1')
  end
$$;

create table if not exists public.b2b_empresas (
  id            bigint generated always as identity primary key,
  rut           text not null unique,                 -- siempre pasa por b2b_norm_rut
  razon_social  text not null,
  contacto      text,
  celular       text,
  email         text,
  giro          text,
  comuna        text,
  inicio_ciclo  date not null default current_date,   -- primera compra del programa
  token         text not null unique default encode(gen_random_bytes(12), 'hex'),
  activa        boolean not null default true,
  notas         text,
  creado        timestamptz not null default now(),
  creado_por    text default (auth.jwt() ->> 'email')
);

create table if not exists public.b2b_compras (
  id            bigint generated always as identity primary key,
  empresa_id    bigint not null references public.b2b_empresas(id) on delete cascade,
  fecha         date not null,
  monto         integer not null,                     -- total con IVA; negativo = nota de crédito
  tipo          text not null default 'FACTURA' check (tipo in ('FACTURA','NC')),
  detalle       text,
  folio         text,
  pedido        text,
  origen        text not null default 'manual' check (origen in ('app','wasabil','manual')),
  documento_id  bigint references public.gestion_documentos(id) on delete set null,
  anulada       boolean not null default false,
  creado        timestamptz not null default now(),
  creado_por    text default (auth.jwt() ->> 'email')
);

create index if not exists b2b_compras_empresa_idx on public.b2b_compras (empresa_id, fecha);
-- Un folio entra una sola vez, venga de donde venga (la historia de Wasabil y
-- el trigger de la app podrían traer la misma factura).
create unique index if not exists b2b_compras_folio_idx on public.b2b_compras (tipo, folio) where folio is not null;
create unique index if not exists b2b_compras_doc_idx on public.b2b_compras (documento_id) where documento_id is not null;

-- ── Fórmulas ──────────────────────────────────────────────────────────────
create or replace function public.b2b_tramo(p_acumulado bigint)
returns integer language sql immutable as $$
  select case when coalesce(p_acumulado,0) >= 3000000 then 5
              when coalesce(p_acumulado,0) >= 1500000 then 2
              else 0 end
$$;

-- Ciclo de 12 meses vigente a la fecha p_hoy, contado desde p_inicio.
create or replace function public.b2b_ciclo(p_inicio date, p_hoy date default current_date,
                                           out ciclo_inicio date, out ciclo_fin date)
language plpgsql immutable as $$
declare anios int;
begin
  if p_hoy < p_inicio then anios := 0;
  else anios := extract(year from age(p_hoy, p_inicio))::int; end if;
  ciclo_inicio := (p_inicio + make_interval(years => anios))::date;
  ciclo_fin    := (ciclo_inicio + interval '1 year' - interval '1 day')::date;
end $$;

-- ── Vista: la cuenta con sus números ─────────────────────────────────────
create or replace view public.v_b2b_cuentas with (security_invoker = on) as
with c as (
  select e.*, (public.b2b_ciclo(e.inicio_ciclo)).ciclo_inicio, (public.b2b_ciclo(e.inicio_ciclo)).ciclo_fin
  from public.b2b_empresas e
), s as (
  select c.id,
    coalesce(sum(k.monto) filter (where not k.anulada and k.fecha between c.ciclo_inicio and c.ciclo_fin), 0)::bigint as acumulado,
    coalesce(sum(k.monto) filter (where not k.anulada), 0)::bigint as total_historico,
    count(*) filter (where not k.anulada and k.tipo = 'FACTURA')::int as n_facturas,
    max(k.fecha) filter (where not k.anulada and k.tipo = 'FACTURA') as ultima_compra
  from c left join public.b2b_compras k on k.empresa_id = c.id
  group by c.id
)
select c.id, c.rut, c.razon_social, c.contacto, c.celular, c.email, c.giro, c.comuna,
  c.inicio_ciclo, c.token, c.activa, c.notas, c.creado, c.creado_por,
  c.ciclo_inicio, c.ciclo_fin,
  s.acumulado, s.total_historico, s.n_facturas, s.ultima_compra,
  public.b2b_tramo(s.acumulado) as tramo_pct,
  greatest(0, 1500000 - s.acumulado)::bigint as falta_2,
  greatest(0, 3000000 - s.acumulado)::bigint as falta_5,
  (c.ciclo_fin - current_date)::int as dias_ciclo
from c join s on s.id = c.id;

-- ── RLS ───────────────────────────────────────────────────────────────────
alter table public.b2b_empresas enable row level security;
alter table public.b2b_empresas force row level security;
alter table public.b2b_compras  enable row level security;
alter table public.b2b_compras  force row level security;

-- Los tres roles leen y registran (el vendedor abre cuentas y anota compras a
-- mano); borrar solo el admin.
drop policy if exists b2b_empresas_leer on public.b2b_empresas;
create policy b2b_empresas_leer   on public.b2b_empresas for select to authenticated using (es_usuario());
drop policy if exists b2b_empresas_crear on public.b2b_empresas;
create policy b2b_empresas_crear  on public.b2b_empresas for insert to authenticated with check (es_usuario());
drop policy if exists b2b_empresas_editar on public.b2b_empresas;
create policy b2b_empresas_editar on public.b2b_empresas for update to authenticated using (es_usuario()) with check (es_usuario());
drop policy if exists b2b_empresas_borrar on public.b2b_empresas;
create policy b2b_empresas_borrar on public.b2b_empresas for delete to authenticated using (es_admin());

drop policy if exists b2b_compras_leer on public.b2b_compras;
create policy b2b_compras_leer   on public.b2b_compras for select to authenticated using (es_usuario());
drop policy if exists b2b_compras_crear on public.b2b_compras;
create policy b2b_compras_crear  on public.b2b_compras for insert to authenticated with check (es_usuario());
drop policy if exists b2b_compras_editar on public.b2b_compras;
create policy b2b_compras_editar on public.b2b_compras for update to authenticated using (es_usuario()) with check (es_usuario());
drop policy if exists b2b_compras_borrar on public.b2b_compras;
create policy b2b_compras_borrar on public.b2b_compras for delete to authenticated using (es_admin());

grant select, insert, update, delete on public.b2b_empresas to authenticated;
grant select, insert, update, delete on public.b2b_compras  to authenticated;
grant select on public.v_b2b_cuentas to authenticated;
revoke all on public.b2b_empresas  from anon;
revoke all on public.b2b_compras   from anon;
revoke all on public.v_b2b_cuentas from anon;

-- ── Limpieza al escribir: el RUT siempre normalizado ─────────────────────
create or replace function public.b2b_empresas_antes()
returns trigger language plpgsql as $$
begin
  new.rut := public.b2b_norm_rut(new.rut);
  if new.rut is null then raise exception 'RUT inválido'; end if;
  new.razon_social := nullif(btrim(new.razon_social), '');
  if new.razon_social is null then raise exception 'Falta la razón social'; end if;
  return new;
end $$;
drop trigger if exists tr_b2b_empresas_antes on public.b2b_empresas;
create trigger tr_b2b_empresas_antes before insert or update on public.b2b_empresas
  for each row execute function public.b2b_empresas_antes();

-- ── Factura emitida desde la app → compra de la cuenta ───────────────────
-- Corre como dueño (security definer) porque el vendedor que emite no
-- necesita permisos sobre b2b_compras para que la cuenta se actualice.
create or replace function public.b2b_desde_documento()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_emp bigint;
begin
  if new.tipo <> 'FACTURA' then return new; end if;
  select id into v_emp from public.b2b_empresas where rut = public.b2b_norm_rut(new.rut) and activa;
  if v_emp is null then return new; end if;
  insert into public.b2b_compras (empresa_id, fecha, monto, tipo, detalle, folio, pedido, origen, documento_id, anulada, creado_por)
  values (v_emp, coalesce(new.fecha, current_date), coalesce(new.monto, 0), 'FACTURA',
          coalesce(new.producto, new.detalle), new.folio, new.num, 'app', new.id, new.anulada, new.creado_por)
  on conflict (documento_id) where documento_id is not null do update
    set fecha = excluded.fecha, monto = excluded.monto, detalle = excluded.detalle,
        folio = excluded.folio, anulada = excluded.anulada, empresa_id = excluded.empresa_id;
  return new;
end $$;
drop trigger if exists tr_b2b_desde_documento on public.gestion_documentos;
create trigger tr_b2b_desde_documento after insert or update on public.gestion_documentos
  for each row execute function public.b2b_desde_documento();

-- Empresa nueva: engancha las facturas que la app ya había emitido a ese RUT.
create or replace function public.b2b_vincular_documentos()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.b2b_compras (empresa_id, fecha, monto, tipo, detalle, folio, pedido, origen, documento_id, anulada, creado_por)
  select new.id, coalesce(d.fecha, d.creado::date), coalesce(d.monto, 0), 'FACTURA',
         coalesce(d.producto, d.detalle), d.folio, d.num, 'app', d.id, d.anulada, d.creado_por
  from public.gestion_documentos d
  where d.tipo = 'FACTURA' and public.b2b_norm_rut(d.rut) = new.rut
  on conflict do nothing;
  return new;
end $$;
drop trigger if exists tr_b2b_vincular_documentos on public.b2b_empresas;
create trigger tr_b2b_vincular_documentos after insert on public.b2b_empresas
  for each row execute function public.b2b_vincular_documentos();

-- ── Lo que ve el cliente con su link privado ─────────────────────────────
-- Devuelve UNA cuenta por token, o null. Es lo único que puede leer anon:
-- sin montos de otras empresas, sin listar nada. El token tiene 96 bits al
-- azar; adivinarlo no es un riesgo real.
create or replace function public.b2b_estado(p_token text)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'razon_social', v.razon_social, 'rut', v.rut, 'contacto', v.contacto,
    'ciclo_inicio', v.ciclo_inicio, 'ciclo_fin', v.ciclo_fin, 'dias_ciclo', v.dias_ciclo,
    'acumulado', v.acumulado, 'tramo_pct', v.tramo_pct, 'falta_2', v.falta_2, 'falta_5', v.falta_5,
    'compras', coalesce((
      select jsonb_agg(jsonb_build_object('fecha', k.fecha, 'detalle', k.detalle, 'folio', k.folio, 'monto', k.monto, 'tipo', k.tipo) order by k.fecha desc)
      from public.b2b_compras k
      where k.empresa_id = v.id and not k.anulada and k.fecha between v.ciclo_inicio and v.ciclo_fin), '[]'::jsonb)
  )
  from public.v_b2b_cuentas v
  where v.token = p_token and v.activa and length(p_token) >= 16
  limit 1
$$;
revoke all on function public.b2b_estado(text) from public;
grant execute on function public.b2b_estado(text) to anon, authenticated;

-- Registro en el panel (Database → Migrations). Sin CLI hay que hacerlo a mano:
-- insert into supabase_migrations.schema_migrations (version, name, statements)
-- values ('0019', 'b2b_cuentas', array[$mig$ <este archivo> $mig$]);
