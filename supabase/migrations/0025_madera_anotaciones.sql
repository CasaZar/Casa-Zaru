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
-- 0025 · Madera por pedido y fotos de llegada (01-11-2026)
--
-- Pestaña «Madera» de la Gestión, hecha para el taller:
--
--   1) ANOTACIONES. Por cada pedido, el taller anota los tablones que usó
--      ("2 tablones 2 × 8 en 3,2 m"). Cada tablón anotado es una fila; las
--      pulgadas las calcula la base (columna generada), no el navegador.
--      Escribir pasa SOLO por madera_anotar(): en una transacción inserta la
--      anotación, el CONSUMO del mayor y descuenta la bodega. Es idempotente
--      por client_id (un uuid que pone el celular): si el mismo tablón llega
--      dos veces (doble toque, reintento sin señal) se descuenta una sola vez.
--      Deshacer pasa SOLO por madera_anular(): no borra nada, marca la
--      anotación y escribe el movimiento inverso en el mayor.
--
--   2) LLEGADAS. Cuando llega madera, el taller sube la foto del cuaderno
--      (bucket privado madera-fotos) y elige el proveedor. Queda «por revisar»;
--      el admin la lee, anota lo que dice y la confirma contra la factura
--      recibida que respalda (documentos_recibidos) o como compra sin factura.
--      La foto NO mueve bodega: la entrada de stock sigue siendo una sola, la
--      factura. La foto es el respaldo.
--
--   3) v_madera_mes: por mes y especie, pulgadas compradas (líneas de facturas
--      recibidas) contra pulgadas anotadas en pedidos. Solo admin la ve llena:
--      respeta el RLS de documentos_recibidos.
--
-- Ningún nombre de proveedor ni monto va en este archivo (el repo es público):
-- proveedores.alias y proveedores.madera se llenan con un script aparte.
-- Antes de aplicar: mirar supabase_migrations.schema_migrations; si la 0025 ya
-- existe, renumerar. Idempotente.
-- ══════════════════════════════════════════════════════════════════════════


-- ── Proveedores de madera ─────────────────────────────────────────────────
-- alias = el nombre corto que se usa en el taller y sale en el botón.
alter table public.proveedores add column if not exists alias  text;
alter table public.proveedores add column if not exists madera boolean not null default false;


-- ── Largos por especie (editables) ────────────────────────────────────────
-- La pulgada maderera es 1″ × 10″ × un largo que DEPENDE DE LA ESPECIE
-- (dato del dueño, 01-11-2026): ciprés y oregón se venden con pulgada de
-- 3,2 m; el resto, con pulgada de 12 pies (3,6576 m). Un 2 × 10 de coihue en
-- 12 pies son 2 pulgadas, no 2,29.
--   pulg_base_m    = largo de la pulgada de esa especie, en metros
--   largo_tablon_m = largo en que viene el tablón (el botón por defecto)
-- Todo en metros. Se editan desde la pestaña Madera → Revisar (admin), no
-- en el código. Cada tablón anotado guarda la base con que se calculó, así
-- un cambio acá no reescribe lo ya anotado.
alter table public.inventario add column if not exists pulg_base_m    numeric(7,4) check (pulg_base_m > 0);
alter table public.inventario add column if not exists largo_tablon_m numeric(7,4) check (largo_tablon_m > 0);
update public.inventario
   set pulg_base_m    = coalesce(pulg_base_m,    case when especie in ('CIPRÉS','OREGÓN','PINO OREGÓN') then 3.2 else 3.6576 end),
       largo_tablon_m = coalesce(largo_tablon_m, case when especie in ('CIPRÉS','OREGÓN','PINO OREGÓN') then 3.2 else 3.6576 end)
 where sku like 'madera\_%' and (pulg_base_m is null or largo_tablon_m is null);

-- ── La pulgada maderera, en un solo lugar ─────────────────────────────────
--   pulgadas = piezas × espesor″ × ancho″ × largo_m / (10 × base_m)
--   2 tablones 2 × 8 de ciprés en 3,2 m   = 2 × 2 × 8 × 3,2 / 32        = 3,200 pulg
--   1 tablón 2 × 10 de coihue en 3,6576 m = 2 × 10 × 3,6576 / 36,576    = 2,000 pulg
-- El JS repite esta cuenta solo para mostrarla mientras se anota
-- (_aUnidadStock, unidad 'tablon'); lo que queda guardado es lo de acá.
create or replace function public.madera_pulgadas(
  piezas numeric, espesor numeric, ancho numeric, largo_m numeric, base_m numeric)
returns numeric language sql immutable as $$
  select round(piezas * espesor * ancho * largo_m / (10.0 * base_m), 3)
$$;


-- ══════════════════════════════════════════════════════════════════════════
-- 1) ANOTACIONES
-- ══════════════════════════════════════════════════════════════════════════
create table if not exists public.madera_anotaciones (
  id               bigint generated always as identity primary key,
  client_id        uuid not null unique,
  pedido_num       text not null check (btrim(pedido_num) <> ''),
  despacho         date,                       -- despacho del pedido, para agrupar por mes
  inventario_id    bigint not null references public.inventario(id),
  piezas           numeric(10,3) not null check (piezas > 0 and piezas <= 500),
  espesor_pulg     numeric(6,3)  not null check (espesor_pulg > 0 and espesor_pulg <= 24),
  ancho_pulg       numeric(6,3)  not null check (ancho_pulg > 0 and ancho_pulg <= 48),
  largo_m          numeric(7,4)  not null check (largo_m > 0 and largo_m <= 40),
  base_m           numeric(7,4)  not null check (base_m > 0),   -- largo de la pulgada de la especie al anotar
  pulgadas         numeric(14,3) generated always as
                   (public.madera_pulgadas(piezas, espesor_pulg, ancho_pulg, largo_m, base_m)) stored,
  mayor_id         bigint not null references public.mayor(id),
  reverso_mayor_id bigint references public.mayor(id),
  anulada_at       timestamptz,
  anulada_por      text,
  created_at       timestamptz not null default now(),
  created_by       text default (auth.jwt() ->> 'email'),
  updated_at       timestamptz not null default now(),
  updated_by       text default (auth.jwt() ->> 'email'),
  constraint madera_anot_reverso check ((anulada_at is null) = (reverso_mayor_id is null))
);
comment on table  public.madera_anotaciones is 'Tablones que el taller anotó por pedido. Se escribe solo con madera_anotar() / madera_anular().';
comment on column public.madera_anotaciones.pedido_num is 'numStr del pedido (gestion_produccion: num o data->>pedido). Sin FK: Producción tiene filas con llave de Firebase.';
comment on column public.madera_anotaciones.client_id  is 'uuid generado en el celular: hace idempotente el reintento.';

create index if not exists madera_anot_pedido_idx   on public.madera_anotaciones (pedido_num) where anulada_at is null;
create index if not exists madera_anot_despacho_idx on public.madera_anotaciones (despacho);

create table if not exists public.madera_anotaciones_historial (
  id            bigint generated always as identity primary key,
  anotacion_id  bigint not null,
  ts            timestamptz not null default now(),
  por           text default (auth.jwt() ->> 'email'),
  accion        text not null check (accion in ('UPDATE','DELETE')),
  anterior      jsonb not null
);
create index if not exists madera_anot_hist_idx on public.madera_anotaciones_historial (anotacion_id, ts);

-- Un tablón anotado no se edita: se anula y se anota de nuevo. Lo único que
-- puede cambiar es la anulación (y una vez anulado, no vuelve).
create or replace function public.madera_anotaciones_antes()
returns trigger language plpgsql as $$
begin
  if (new.client_id, new.pedido_num, new.inventario_id, new.piezas, new.espesor_pulg,
      new.ancho_pulg, new.largo_m, new.base_m, new.mayor_id, new.despacho)
     is distinct from
     (old.client_id, old.pedido_num, old.inventario_id, old.piezas, old.espesor_pulg,
      old.ancho_pulg, old.largo_m, old.base_m, old.mayor_id, old.despacho) then
    raise exception 'Un tablón anotado no se edita: se deshace y se anota de nuevo';
  end if;
  if old.anulada_at is not null and new.anulada_at is distinct from old.anulada_at then
    raise exception 'Una anotación deshecha no vuelve: anótala de nuevo';
  end if;
  new.updated_at := now();
  new.updated_by := coalesce(auth.jwt() ->> 'email', new.updated_by);
  new.created_at := old.created_at;
  new.created_by := old.created_by;
  return new;
end $$;
drop trigger if exists tr_madera_anotaciones_antes on public.madera_anotaciones;
create trigger tr_madera_anotaciones_antes before update on public.madera_anotaciones
  for each row execute function public.madera_anotaciones_antes();

create or replace function public.madera_anotaciones_historial_guardar()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.madera_anotaciones_historial (anotacion_id, accion, anterior)
  values (old.id, tg_op, to_jsonb(old));
  return coalesce(new, old);
end $$;
drop trigger if exists tr_madera_anotaciones_historial on public.madera_anotaciones;
create trigger tr_madera_anotaciones_historial after update or delete on public.madera_anotaciones
  for each row execute function public.madera_anotaciones_historial_guardar();


-- ── madera_anotar: el único camino de escritura ───────────────────────────
-- p_lineas: [{client_id, inventario_id, piezas, espesor, ancho, largo_m}]  (largo en metros)
-- p_ceco: el centro de costo que sugiere la app para el pedido (cecoSugerido);
-- si viene vacío se usa el de la especie, y si no hay, el general.
-- Devuelve las anotaciones (las nuevas y las que ya existían con ese client_id).
create or replace function public.madera_anotar(
  p_pedido text, p_despacho date, p_ceco smallint, p_lineas jsonb)
returns setof public.madera_anotaciones
language plpgsql security definer set search_path = public as $$
declare
  l        jsonb;
  v_cid    uuid;
  v_inv    public.inventario%rowtype;
  v_cat    smallint;
  v_ceco   smallint;
  v_hoy    date := (now() at time zone 'America/Santiago')::date;
  v_mes    text;
  v_pulg   numeric;
  v_unit   numeric;
  v_mayor  bigint;
  v_id     bigint;
  v_esp    text;
  v_desc   text;
begin
  if coalesce(public.zaru_rol(), '') not in ('admin','taller') then
    raise exception 'Solo el taller o el admin anotan madera' using errcode = '42501';
  end if;
  if p_pedido is null or btrim(p_pedido) = '' then
    raise exception 'Falta el número de pedido';
  end if;
  if not exists (select 1 from public.gestion_produccion g
                  where g.num = p_pedido or g.data ->> 'pedido' = p_pedido) then
    raise exception 'El pedido % no está en Producción', p_pedido;
  end if;
  if p_lineas is null or jsonb_typeof(p_lineas) <> 'array' or jsonb_array_length(p_lineas) = 0 then
    raise exception 'No hay tablones para anotar';
  end if;
  if jsonb_array_length(p_lineas) > 40 then
    raise exception 'Demasiados tablones en una sola anotación (%)', jsonb_array_length(p_lineas);
  end if;
  if p_ceco is not null and not exists (select 1 from public.centros_costo where id = p_ceco and activo) then
    raise exception 'El centro de costo % no existe o está inactivo', p_ceco;
  end if;
  select id into v_cat from public.gasto_categorias where nombre = 'Madera (proveedores)';
  if v_cat is null then
    raise exception 'Falta la categoría «Madera (proveedores)»';
  end if;
  v_mes := (array['ENERO','FEBRERO','MARZO','ABRIL','MAYO','JUNIO','JULIO','AGOSTO',
                  'SEPTIEMBRE','OCTUBRE','NOVIEMBRE','DICIEMBRE'])[extract(month from v_hoy)::int];

  for l in select * from jsonb_array_elements(p_lineas) loop
    v_cid := (l ->> 'client_id')::uuid;
    if v_cid is null then raise exception 'Tablón sin client_id'; end if;
    -- Dos llamadas con el mismo tablón a la vez: la segunda espera acá y
    -- después lo encuentra ya anotado.
    perform pg_advisory_xact_lock(hashtextextended(v_cid::text, 25));
    if exists (select 1 from public.madera_anotaciones where client_id = v_cid) then
      return query select * from public.madera_anotaciones where client_id = v_cid;
      continue;
    end if;

    select * into v_inv from public.inventario
     where id = (l ->> 'inventario_id')::bigint and sku like 'madera\_%'
     for update;
    if not found then
      raise exception 'Especie de madera desconocida (inventario %)', l ->> 'inventario_id';
    end if;

    -- La base de la pulgada la pone la ficha de la especie, no el celular.
    if v_inv.pulg_base_m is null then
      raise exception 'Falta el largo de la pulgada de %: se fija en Madera → Revisar', v_inv.especie;
    end if;
    v_pulg := public.madera_pulgadas((l ->> 'piezas')::numeric, (l ->> 'espesor')::numeric,
                                     (l ->> 'ancho')::numeric, (l ->> 'largo_m')::numeric,
                                     v_inv.pulg_base_m);
    if v_pulg is null or v_pulg <= 0 then
      raise exception 'Hay un tablón sin medida';
    end if;

    v_esp  := case when v_inv.especie like '%OREGÓN' then 'OREGÓN' else v_inv.especie end;
    v_ceco := coalesce(p_ceco,
                (select c.id from public.centros_costo c
                  where c.tipo = 'MADER' and c.activo and c.especie = v_esp order by c.id limit 1),
                (select c.id from public.centros_costo c
                  where c.tipo = 'GENERAL' and c.activo order by c.id limit 1));
    -- Mismo criterio que el consumo manual: costo promedio, y si la bodega
    -- todavía no tiene uno, el último costo de la ficha. Sin IVA.
    v_unit := coalesce(nullif(v_inv.costo_prom, 0), v_inv.ultimo_costo, 0);
    v_desc := 'Madera pedido ' || p_pedido || ' — ' ||
              trim(to_char((l ->> 'piezas')::numeric, 'FM999990.###'), '.') || ' × ' ||
              trim(to_char((l ->> 'espesor')::numeric, 'FM990.###'), '.') || '×' ||
              trim(to_char((l ->> 'ancho')::numeric, 'FM990.###'), '.') || ' en ' ||
              trim(to_char((l ->> 'largo_m')::numeric, 'FM990.####'), '.') || ' m';

    insert into public.mayor (fecha, mes, mes_n, descripcion, cantidad, unidad_id, inventario_id,
                              madera, categoria_id, centro_costo_id, pedido_num, monto,
                              grupo, origen_tipo, nota)
    values (v_hoy, v_mes, extract(month from v_hoy)::smallint, v_desc, v_pulg, v_inv.unidad_id, v_inv.id,
            v_inv.especie, v_cat, v_ceco, p_pedido, round(v_pulg * v_unit)::integer,
            'CONSUMO', 'consumo', 'anotación ' || v_cid)
    returning id into v_mayor;

    update public.inventario set stock = stock - v_pulg, actualizado_en = now() where id = v_inv.id;

    insert into public.madera_anotaciones (client_id, pedido_num, despacho, inventario_id, piezas,
                                           espesor_pulg, ancho_pulg, largo_m, base_m, mayor_id)
    values (v_cid, p_pedido, p_despacho, v_inv.id, (l ->> 'piezas')::numeric,
            (l ->> 'espesor')::numeric, (l ->> 'ancho')::numeric, (l ->> 'largo_m')::numeric,
            v_inv.pulg_base_m, v_mayor)
    returning id into v_id;

    return query select * from public.madera_anotaciones where id = v_id;
  end loop;

  -- El CECO del pedido, como hace el consumo manual: el primero que se asigna manda.
  if v_ceco is not null then
    insert into public.pedido_centro_costo (pedido_num, centro_costo_id, asignado_por)
    values (p_pedido, v_ceco, auth.jwt() ->> 'email')
    on conflict (pedido_num) do nothing;
  end if;
end $$;


-- ── madera_anular: deshacer sin borrar ────────────────────────────────────
-- Escribe el movimiento inverso (CONSUMO con cantidad y monto negativos, así
-- el costo del pedido vuelve a cero), devuelve las pulgadas a la bodega y
-- marca la anotación. Anular dos veces la misma no hace nada la segunda vez.
create or replace function public.madera_anular(p_ids bigint[])
returns setof public.madera_anotaciones
language plpgsql security definer set search_path = public as $$
declare
  a       public.madera_anotaciones%rowtype;
  m       public.mayor%rowtype;
  v_hoy   date := (now() at time zone 'America/Santiago')::date;
  v_rev   bigint;
begin
  if coalesce(public.zaru_rol(), '') not in ('admin','taller') then
    raise exception 'Solo el taller o el admin deshacen anotaciones' using errcode = '42501';
  end if;
  if p_ids is null or cardinality(p_ids) = 0 then
    return;
  end if;

  for a in select * from public.madera_anotaciones where id = any(p_ids) order by id for update loop
    if a.anulada_at is null then
      select * into m from public.mayor where id = a.mayor_id;
      insert into public.mayor (fecha, mes, mes_n, descripcion, cantidad, unidad_id, inventario_id,
                                madera, categoria_id, centro_costo_id, pedido_num, monto,
                                grupo, origen_tipo, nota)
      values (v_hoy,
              (array['ENERO','FEBRERO','MARZO','ABRIL','MAYO','JUNIO','JULIO','AGOSTO',
                     'SEPTIEMBRE','OCTUBRE','NOVIEMBRE','DICIEMBRE'])[extract(month from v_hoy)::int],
              extract(month from v_hoy)::smallint,
              'Deshace: ' || m.descripcion, -m.cantidad, m.unidad_id, m.inventario_id,
              m.madera, m.categoria_id, m.centro_costo_id, m.pedido_num, -m.monto,
              'CONSUMO', 'consumo', 'deshace anotación ' || a.client_id)
      returning id into v_rev;

      update public.inventario set stock = stock + a.pulgadas, actualizado_en = now()
       where id = a.inventario_id;

      update public.madera_anotaciones
         set anulada_at = now(), anulada_por = auth.jwt() ->> 'email', reverso_mayor_id = v_rev
       where id = a.id;
    end if;
    return query select * from public.madera_anotaciones where id = a.id;
  end loop;
end $$;

revoke all on function public.madera_anotar(text, date, smallint, jsonb) from public, anon;
revoke all on function public.madera_anular(bigint[]) from public, anon;
grant execute on function public.madera_anotar(text, date, smallint, jsonb) to authenticated;
grant execute on function public.madera_anular(bigint[]) to authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- 2) LLEGADAS (foto del cuaderno)
-- ══════════════════════════════════════════════════════════════════════════
create table if not exists public.madera_llegadas (
  id                    bigint generated always as identity primary key,
  client_id             uuid not null unique,
  proveedor_id          bigint references public.proveedores(id),   -- null = «Otro»: se ve en la foto
  fecha_llegada         date not null check (fecha_llegada >= date '2026-01-01'),
  foto_path             text not null unique
                        check (foto_path ~ '^[0-9]{4}-[0-9]{2}/[0-9a-f-]{36}\.(jpg|png|webp)$'),
  estado                text not null default 'por_revisar'
                        check (estado in ('por_revisar','confirmada','descartada')),
  -- Lo que dice la foto, una entrada por tablón:
  -- [{inventario_id, piezas, espesor, ancho, largo_m, texto}]  (largo en metros)
  leido                 jsonb check (leido is null or jsonb_typeof(leido) = 'array'),
  documento_recibido_id bigint references public.documentos_recibidos(id),
  sin_documento         boolean not null default false,
  revisada_por          text,
  revisada_at           timestamptz,
  nota                  text,
  created_at            timestamptz not null default now(),
  created_by            text default (auth.jwt() ->> 'email'),
  updated_at            timestamptz not null default now(),
  updated_by            text default (auth.jwt() ->> 'email'),
  constraint madera_llegada_confirmada check (
    estado <> 'confirmada' or (leido is not null and (documento_recibido_id is not null or sin_documento)))
);
comment on table public.madera_llegadas is 'Foto del cuaderno al llegar madera. Respaldo de la factura; no mueve bodega.';

create index if not exists madera_llegadas_estado_idx on public.madera_llegadas (estado, fecha_llegada);
create index if not exists madera_llegadas_doc_idx    on public.madera_llegadas (documento_recibido_id)
  where documento_recibido_id is not null;

create table if not exists public.madera_llegadas_historial (
  id          bigint generated always as identity primary key,
  llegada_id  bigint not null,
  ts          timestamptz not null default now(),
  por         text default (auth.jwt() ->> 'email'),
  accion      text not null check (accion in ('UPDATE','DELETE')),
  anterior    jsonb not null
);
create index if not exists madera_llegadas_hist_idx on public.madera_llegadas_historial (llegada_id, ts);

create or replace function public.madera_llegadas_antes()
returns trigger language plpgsql as $$
begin
  new.client_id  := old.client_id;       -- la foto y su llave no cambian
  new.foto_path  := old.foto_path;
  new.created_at := old.created_at;
  new.created_by := old.created_by;
  new.updated_at := now();
  new.updated_by := coalesce(auth.jwt() ->> 'email', new.updated_by);
  if new.estado is distinct from old.estado then
    new.revisada_at  := now();
    new.revisada_por := coalesce(auth.jwt() ->> 'email', new.revisada_por);
  end if;
  return new;
end $$;
drop trigger if exists tr_madera_llegadas_antes on public.madera_llegadas;
create trigger tr_madera_llegadas_antes before update on public.madera_llegadas
  for each row execute function public.madera_llegadas_antes();

create or replace function public.madera_llegadas_historial_guardar()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.madera_llegadas_historial (llegada_id, accion, anterior)
  values (old.id, tg_op, to_jsonb(old));
  return coalesce(new, old);
end $$;
drop trigger if exists tr_madera_llegadas_historial on public.madera_llegadas;
create trigger tr_madera_llegadas_historial after update or delete on public.madera_llegadas
  for each row execute function public.madera_llegadas_historial_guardar();


-- ── Bucket privado de fotos ───────────────────────────────────────────────
-- Privado: las fotos se ven con URL firmada, nunca con un link público.
-- Sin policy de UPDATE ni DELETE: una foto subida es respaldo y no se pisa.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('madera-fotos', 'madera-fotos', false, 10485760, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists madera_fotos_subir on storage.objects;
create policy madera_fotos_subir on storage.objects
  for insert to authenticated
  with check (bucket_id = 'madera-fotos' and public.zaru_rol() in ('admin','taller'));
drop policy if exists madera_fotos_ver on storage.objects;
create policy madera_fotos_ver on storage.objects
  for select to authenticated
  using (bucket_id = 'madera-fotos' and public.zaru_rol() in ('admin','taller'));


-- ══════════════════════════════════════════════════════════════════════════
-- 3) COMPRADO vs ANOTADO, por mes y especie
-- ══════════════════════════════════════════════════════════════════════════
-- La especie de una línea de factura recibida: la que se le haya asignado en
-- Recibidos, y si no, la que dice el texto (COIGUE V TABLA → coihue).
-- Las notas de crédito (61) restan.
create or replace view public.v_madera_mes with (security_invoker = true) as
with comprado as (
  select date_trunc('month', d.fecha)::date as mes,
         coalesce(
           (select i.id from public.inventario i where i.id = l.inventario_id and i.sku like 'madera\_%'),
           (select i.id from public.inventario i where i.sku =
              case
                when t.txt ~ 'COIG|COIH'   then 'madera_coihue'
                when t.txt ~ 'RAUL'        then 'madera_rauli'
                when t.txt ~ 'MANIO'       then 'madera_manio'
                when t.txt ~ 'CIPR'        then 'madera_cipres'
                when t.txt ~ 'CASTA'       then 'madera_castano'
                when t.txt ~ 'OREG'        then 'madera_oregon'
                when t.txt ~ 'LENGA'       then 'madera_lenga'
                when t.txt ~ 'LAUREL'      then 'madera_laurel'
              end)) as inventario_id,
         (case when d.sii_document_type_id = 61 then -1 else 1 end) * coalesce(l.cantidad, 0) as pulg,
         (case when d.sii_document_type_id = 61 then -1 else 1 end) * coalesce(l.subtotal, 0) as neto
  from public.documentos_recibidos_lineas l
  join public.documentos_recibidos d on d.id = l.documento_id
  cross join lateral (
    select translate(upper(coalesce(l.item_nombre, '') || ' ' || coalesce(l.glosa, '')),
                     'ÁÉÍÓÚÑ', 'AEIOUN') as txt) t
),
comp as (
  select mes, inventario_id, sum(pulg) as comprado_pulg, sum(neto) as comprado_neto
  from comprado where inventario_id is not null group by 1, 2
),
anot as (
  select date_trunc('month', coalesce(despacho, created_at::date))::date as mes,
         inventario_id, sum(pulgadas) as anotado_pulg, count(distinct pedido_num) as pedidos
  from public.madera_anotaciones where anulada_at is null group by 1, 2
)
select coalesce(c.mes, a.mes) as mes,
       i.id as inventario_id, i.sku, i.especie,
       round(coalesce(c.comprado_pulg, 0), 3) as comprado_pulg,
       round(coalesce(c.comprado_neto, 0))::bigint as comprado_neto,
       round(coalesce(a.anotado_pulg, 0), 3) as anotado_pulg,
       coalesce(a.pedidos, 0) as pedidos,
       round(coalesce(c.comprado_pulg, 0) - coalesce(a.anotado_pulg, 0), 3) as diferencia_pulg
from comp c
full join anot a on a.mes = c.mes and a.inventario_id = c.inventario_id
join public.inventario i on i.id = coalesce(c.inventario_id, a.inventario_id);


-- ── RLS ───────────────────────────────────────────────────────────────────
-- El taller lee anotaciones y llegadas (no tienen pesos) y sube fotos. Nadie
-- escribe anotaciones directo: solo las funciones. Editar una llegada
-- (revisarla) es del admin. No hay DELETE para nadie.
alter table public.madera_anotaciones           enable row level security;
alter table public.madera_anotaciones           force  row level security;
alter table public.madera_anotaciones_historial enable row level security;
alter table public.madera_anotaciones_historial force  row level security;
alter table public.madera_llegadas              enable row level security;
alter table public.madera_llegadas              force  row level security;
alter table public.madera_llegadas_historial    enable row level security;
alter table public.madera_llegadas_historial    force  row level security;

drop policy if exists madera_anot_leer on public.madera_anotaciones;
create policy madera_anot_leer on public.madera_anotaciones
  for select to authenticated using (public.zaru_rol() in ('admin','taller'));

drop policy if exists madera_anot_hist_leer on public.madera_anotaciones_historial;
create policy madera_anot_hist_leer on public.madera_anotaciones_historial
  for select to authenticated using (public.zaru_rol() = 'admin');

drop policy if exists madera_llegadas_leer on public.madera_llegadas;
create policy madera_llegadas_leer on public.madera_llegadas
  for select to authenticated using (public.zaru_rol() in ('admin','taller'));
drop policy if exists madera_llegadas_crear on public.madera_llegadas;
create policy madera_llegadas_crear on public.madera_llegadas
  for insert to authenticated
  with check (public.zaru_rol() in ('admin','taller')
              and estado = 'por_revisar' and leido is null
              and documento_recibido_id is null and not sin_documento);
drop policy if exists madera_llegadas_revisar on public.madera_llegadas;
create policy madera_llegadas_revisar on public.madera_llegadas
  for update to authenticated
  using (public.zaru_rol() = 'admin') with check (public.zaru_rol() = 'admin');

drop policy if exists madera_llegadas_hist_leer on public.madera_llegadas_historial;
create policy madera_llegadas_hist_leer on public.madera_llegadas_historial
  for select to authenticated using (public.zaru_rol() = 'admin');

grant select on public.madera_anotaciones, public.madera_anotaciones_historial,
                public.madera_llegadas_historial to authenticated;
grant select, insert, update on public.madera_llegadas to authenticated;
grant select on public.v_madera_mes to authenticated;
revoke all on public.madera_anotaciones, public.madera_anotaciones_historial,
              public.madera_llegadas, public.madera_llegadas_historial,
              public.v_madera_mes from anon;


-- Rollback (solo con las tablas vacías; con anotaciones reales, NO: primero
-- anularlas con madera_anular para que el mayor y la bodega queden cuadrados):
--   drop view public.v_madera_mes;
--   drop policy madera_fotos_subir on storage.objects; drop policy madera_fotos_ver on storage.objects;
--   delete from storage.buckets where id = 'madera-fotos';   -- solo si no tiene fotos
--   drop function public.madera_anular(bigint[]); drop function public.madera_anotar(text, date, smallint, jsonb);
--   drop table public.madera_llegadas_historial; drop table public.madera_llegadas;
--   drop table public.madera_anotaciones_historial; drop table public.madera_anotaciones;
--   drop function public.madera_llegadas_historial_guardar(); drop function public.madera_llegadas_antes();
--   drop function public.madera_anotaciones_historial_guardar(); drop function public.madera_anotaciones_antes();
--   drop function public.madera_pulgadas(numeric, numeric, numeric, numeric, numeric);
--   alter table public.inventario drop column pulg_base_m, drop column largo_tablon_m;
--   alter table public.proveedores drop column madera, drop column alias;

-- Registrar en el panel (Database → Migrations), pegándolo junto con este archivo:
-- insert into supabase_migrations.schema_migrations (version, name, statements)
-- values ('0025', 'madera_anotaciones', array[$m0025$ <este archivo> $m0025$]);
