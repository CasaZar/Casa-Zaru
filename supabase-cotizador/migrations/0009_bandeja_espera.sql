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
  if to_regclass('public.mensajes_links') is null
     or not exists (select 1 from supabase_migrations.schema_migrations where version = '0008') then
    raise exception 'FALTA LA 0008: aplicar antes 0008_asistente_links.sql. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- 0009 · COTIZADOR · Bandeja: la respuesta automática espera antes de salir (19-11-2026)
--
-- Pedido del dueño: que el asistente no conteste al segundo. Unos 2 minutos para una
-- respuesta normal y 5 si está «preparando» una cotización.
--
--   mensajes_borradores.auto_desde   desde cuándo ese borrador puede salir solo. Lo pone la
--                                    función al redactar (solo en los chats de AUTO_SOLO_CHATS).
--                                    null = no sale solo (lo normal: lo aprueba una persona).
--   pg_cron + pg_net                 cada minuto la base mira si hay algo cuya espera se cumplió y,
--                                    SOLO si lo hay, llama a la función (ruta /despachar).
--
-- La ruta /despachar no recibe datos ni lleva llave: solo puede enviar lo ya agendado, y la
-- función vuelve a pasar todas las reglas (chat de prueba, ventana de 24 h, tope de 2 sin
-- respuesta, chat tomado, texto limpio). Cada borrador sale a lo más una vez: su reserva en
-- mensajes_envios usa una clave fija y esa columna es unique.
-- Si el cliente escribe de nuevo antes de que se cumpla la espera, el borrador caduca y no sale.
--
-- Para apagarlo sin tocar la función:  select cron.unschedule('bandeja-despachar');
-- Idempotente. Rollback al final.
-- ══════════════════════════════════════════════════════════════════════════

alter table public.mensajes_borradores add column if not exists auto_desde timestamptz;
comment on column public.mensajes_borradores.auto_desde is
  'Desde cuándo puede salir solo (respuesta automática con espera). null = no sale solo.';
create index if not exists mensajes_borr_auto_idx on public.mensajes_borradores (auto_desde)
  where auto_desde is not null and estado = 'pendiente';

-- Un borrador que ya no está pendiente no puede quedar agendado.
create or replace function public.mensajes_borrador_desagenda()
returns trigger language plpgsql as $$
begin
  if new.estado <> 'pendiente' then new.auto_desde := null; end if;
  return new;
end $$;
drop trigger if exists tr_mensajes_borr_desagenda on public.mensajes_borradores;
create trigger tr_mensajes_borr_desagenda before insert or update on public.mensajes_borradores
  for each row execute function public.mensajes_borrador_desagenda();

create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

-- La tarea: cada minuto, y solo si hay algo listo, un POST a la función.
do $tarea$
begin
  if exists (select 1 from cron.job where jobname = 'bandeja-despachar') then
    perform cron.unschedule('bandeja-despachar');
  end if;
  perform cron.schedule('bandeja-despachar', '* * * * *', $job$
    select net.http_post(
      url := 'https://cmxqorsyxoltrakxawro.supabase.co/functions/v1/mensajes-webhook/despachar',
      body := '{}'::jsonb,
      headers := '{"Content-Type": "application/json"}'::jsonb,
      timeout_milliseconds := 20000
    )
    where exists (
      select 1 from public.mensajes_borradores
       where estado = 'pendiente' and auto_desde is not null and auto_desde <= now()
    );
  $job$);
end
$tarea$;

-- Registro
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('0009', 'bandeja_espera', array[
  'alter table mensajes_borradores add column auto_desde timestamptz (+ índice parcial);',
  'trigger tr_mensajes_borr_desagenda: un borrador que deja de estar pendiente pierde su auto_desde;',
  'create extension pg_cron, pg_net;',
  'cron bandeja-despachar: cada minuto, si hay un borrador con la espera cumplida, POST a mensajes-webhook/despachar.'
])
on conflict (version) do nothing;

-- Verificación. Debe dar: columna 1 · trg_borr 4 · extensiones 2 · tarea 1 · activa true · agendados 0 · ultima 0009.
select
  (select count(*) from information_schema.columns
    where table_schema = 'public' and table_name = 'mensajes_borradores' and column_name = 'auto_desde')  as columna,
  (select count(*) from pg_trigger where tgrelid = 'public.mensajes_borradores'::regclass and not tgisinternal) as trg_borr,
  (select count(*) from pg_extension where extname in ('pg_cron', 'pg_net'))                              as extensiones,
  (select count(*) from cron.job where jobname = 'bandeja-despachar')                                     as tarea,
  (select bool_and(active) from cron.job where jobname = 'bandeja-despachar')                             as activa,
  (select count(*) from public.mensajes_borradores where auto_desde is not null)                          as agendados,
  (select max(version) from supabase_migrations.schema_migrations)                                        as ultima;

-- Rollback (NO correr junto con lo de arriba):
--   select cron.unschedule('bandeja-despachar');
--   drop trigger tr_mensajes_borr_desagenda on public.mensajes_borradores;
--   drop function public.mensajes_borrador_desagenda();
--   drop index public.mensajes_borr_auto_idx;
--   alter table public.mensajes_borradores drop column auto_desde;
--   delete from supabase_migrations.schema_migrations where version = '0009';
--   (pg_cron y pg_net pueden quedar instaladas: sin tarea no hacen nada)
