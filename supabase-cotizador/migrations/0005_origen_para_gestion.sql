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
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '0003') then
    raise exception 'FALTA LA 0003 en schema_migrations: revisar el orden antes de seguir. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- 0005_origen_para_gestion · COTIZADOR · 18-11-2026
--
-- De dónde llegan los clientes (boceto .claude/boceto-origen-clientes.html,
-- aprobado el 18-11). La Gestión necesita saber, por teléfono, por dónde
-- llegó cada persona la primera vez que cotizó, para proponer el origen al
-- cargar la venta y para el informe de qué canal vende.
--
-- Cómo viaja: la GESTIÓN viene a buscarlo (pg_cron + pg_net, migración 0035
-- de Gestión), llamando a origenes_para_gestion() con un secreto. El secreto
-- vive SOLO en la bóveda de la Gestión; acá se guarda su huella sha256, que
-- no sirve para llamar a la función. Sin el secreto la función no devuelve
-- nada. Ningún navegador participa.
--
-- Qué entrega: por cotización, la fecha, los últimos 8 dígitos del teléfono,
-- el N° CL, el producto, el total medio, quién la hizo (vendedor o web) y las
-- marcas del origen (utm, gclid, ref…). NO entrega nombre, correo ni el
-- contacto completo. Máximo 500 filas por llamada.
--
-- Orden: aplicar PRIMERO la 0035 de Gestión (genera el secreto y muestra la
-- huella), y después esta, pegando la huella donde dice PEGAR_HUELLA.
-- Antes de aplicar: mirar schema_migrations; si la 0005 ya existe, renumerar.
-- No toca ninguna fila de cotizaciones. Idempotente. Rollback al final.
-- ══════════════════════════════════════════════════════════════════════════

create schema if not exists privado;
revoke all on schema privado from public, anon, authenticated;

create table if not exists privado.llaves_externas (
  nombre      text primary key,
  huella      text not null check (huella ~ '^[0-9a-f]{64}$'),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  updated_by  text default current_user
);
revoke all on privado.llaves_externas from public, anon, authenticated;
comment on table privado.llaves_externas is 'Huellas sha256 de secretos de otros sistemas (0005). El secreto no se guarda acá.';

-- La huella la entrega la 0035 de Gestión. Reemplazar PEGAR_HUELLA (64 letras
-- y números) antes de correr. Si se corre de nuevo con otra huella, la cambia.
do $huella$
declare h text := lower(btrim('PEGAR_HUELLA'));
begin
  if h !~ '^[0-9a-f]{64}$' then
    raise exception 'Falta pegar la huella que mostró la 0035 de Gestión (64 letras y números) en lugar de PEGAR_HUELLA. No se aplicó nada.';
  end if;
  insert into privado.llaves_externas (nombre, huella) values ('gestion_origen', h)
  on conflict (nombre) do update set huella = excluded.huella, updated_at = now(), updated_by = current_user;
end
$huella$;

create or replace function public.origenes_para_gestion(p_secreto text, p_desde timestamptz)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare
  v_huella text;
begin
  select huella into v_huella from privado.llaves_externas where nombre = 'gestion_origen';
  if v_huella is null or p_secreto is null or length(p_secreto) < 32
     or encode(extensions.digest(p_secreto, 'sha256'), 'hex') <> v_huella then
    raise exception 'no autorizado' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(x order by x->>'fecha')
      from (
        select jsonb_build_object(
                 'id',        c.id,
                 'fecha',     c.fecha_creacion,
                 'tel8',      right(regexp_replace(c.contacto, '\D', '', 'g'), 8),
                 'numero',    c.numero,
                 'producto',  left(c.producto, 80),
                 'total',     round(coalesce(c.total_medio, c.total_bajo, 0)),
                 'vendedor',  nullif(split_part(coalesce(c.user_email, ''), '@', 1), ''),
                 'eliminada', coalesce(c.eliminada, false),
                 'estado',    c.estado,
                 'origen',    case when c.origen is null then null else
                                jsonb_strip_nulls(jsonb_build_object(
                                  'utm_source',   c.origen->>'utm_source',
                                  'utm_medium',   c.origen->>'utm_medium',
                                  'utm_campaign', c.origen->>'utm_campaign',
                                  'utm_content',  c.origen->>'utm_content',
                                  'utm_term',     c.origen->>'utm_term',
                                  'gad_campaignid', c.origen->>'gad_campaignid',
                                  'gclid',        case when c.origen ? 'gclid'  then true end,
                                  'gbraid',       case when c.origen ? 'gbraid' or c.origen ? 'wbraid' then true end,
                                  'fbclid',       case when c.origen ? 'fbclid' then true end,
                                  'ref',          c.origen->>'ref',
                                  'src',          c.origen->>'src',
                                  'profesional',  case when c.origen ? 'profesional' then true end,
                                  'tienda',       c.origen->'tienda'))
                              end
               ) as x
          from public.cotizaciones c
         where c.fecha_creacion > coalesce(p_desde, '2026-01-01'::timestamptz)
           and length(regexp_replace(coalesce(c.contacto, ''), '\D', '', 'g')) between 8 and 12
         order by c.fecha_creacion
         limit 500
      ) t
  ), '[]'::jsonb);
end $$;
revoke all on function public.origenes_para_gestion(text, timestamptz) from public;
grant execute on function public.origenes_para_gestion(text, timestamptz) to anon;

-- Registro
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('0005', 'origen_para_gestion', array[
  'privado.llaves_externas (huella sha256 de gestion_origen); funcion origenes_para_gestion(secreto, desde) para el cron de Gestion 0035'
])
on conflict (version) do nothing;

-- Verificación: huella_ok = true (si sale false, quedó PEGAR_HUELLA: correr de
-- nuevo con la huella), y la función existe.
select
  (select huella ~ '^[0-9a-f]{64}$' from privado.llaves_externas where nombre = 'gestion_origen') as huella_ok,
  to_regprocedure('public.origenes_para_gestion(text, timestamptz)') is not null                as funcion_ok,
  (select max(version) from supabase_migrations.schema_migrations)                                as ultima_migracion;

-- ── ROLLBACK (no correr junto con lo de arriba) ──────────────────────────
-- drop function if exists public.origenes_para_gestion(text, timestamptz);
-- delete from privado.llaves_externas where nombre = 'gestion_origen';
-- delete from supabase_migrations.schema_migrations where version = '0005';
-- (El esquema privado se deja: no estorba.)
