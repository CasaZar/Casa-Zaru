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
  if to_regclass('public.mensajes_chats') is null
     or not exists (select 1 from supabase_migrations.schema_migrations where version = '0005') then
    raise exception 'FALTA LA 0004 o la 0005: revisar el orden antes de seguir. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- 0006 · COTIZADOR · Bandeja de mensajes, etapa 2: registro de envíos (18-11-2026)
--
-- El botón Enviar de mensajes.html llama a la Edge Function `mensajes-webhook`
-- (ruta /enviar). Antes de hablar con Meta, la función RESERVA el envío aquí;
-- recién si la base lo acepta, lo manda. Así las reglas viven en la base y un
-- envío no se puede repetir por un doble clic ni por un reintento.
--
--   mensajes_envios   una fila por intento de envío. `clave` única = idempotencia.
--                     Guarda quién lo aprobó, el texto, el resultado y el id de Meta.
--
-- Reglas que aplica mensajes_envio_permitido() ANTES de enviar:
--   · solo WhatsApp (Instagram todavía no);
--   · ventana de 24 horas abierta (fuera de ella solo valen plantillas);
--   · tope de 2 mensajes sin respuesta por chat (cuenta también los que están
--     saliendo en este momento);
--   · un chat tomado solo lo escribe quien lo tomó, o el dueño;
--   · el texto no lleva [PRECIO: …] sin completar, ni «nativa», ni «al tiro»,
--     ni signos de apertura (¡ ¿).
--
-- No cambia ni borra ninguna fila existente. Idempotente. Rollback al final.
--
-- APLICADA el 18-11-2026 en el SQL Editor del Cotizador (con ok del dueño).
-- Verificación: tabla 1, rls_force true, policies 1, triggers 3, anon_algo 0,
-- auth_escribe 0, service_inserta true, última 0006; confirmado aparte por el MCP.
-- Reglas probadas con supabase-cotizador/prueba-0006-reglas.sql: 13 de 13, sin dejar filas.
-- ══════════════════════════════════════════════════════════════════════════

create table if not exists public.mensajes_envios (
  id          bigint generated always as identity primary key,
  clave       text not null unique check (clave ~ '^[A-Za-z0-9-]{16,80}$'),
  chat_id     bigint not null references public.mensajes_chats(id),
  borrador_id bigint references public.mensajes_borradores(id),
  texto       text not null check (length(btrim(texto)) between 1 and 4000),
  por         text not null check (por = lower(por) and position('@' in por) > 1),   -- correo de quien aprobó
  estado      text not null default 'enviando' check (estado in ('enviando','enviado','fallo')),
  meta_id     text,                                                                  -- id del mensaje en Meta
  error       text check (length(error) <= 1000),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  updated_by  text not null default coalesce(auth.jwt() ->> 'email', 'mensajes-webhook'),
  check (estado <> 'enviado' or meta_id is not null)
);
create index if not exists mensajes_envios_chat_idx on public.mensajes_envios (chat_id, created_at);

create or replace function public.mensajes_envio_permitido()
returns trigger language plpgsql as $$
declare
  c public.mensajes_chats%rowtype;
  en_curso integer;
begin
  -- El bloqueo de la fila del chat pone en fila dos reservas simultáneas del mismo chat.
  select * into c from public.mensajes_chats where id = new.chat_id for update;
  if not found or c.deleted_at is not null then
    raise exception 'ENVIO RECHAZADO: el chat no existe.';
  end if;
  if c.canal <> 'whatsapp' then
    raise exception 'ENVIO RECHAZADO: por ahora solo se puede enviar por WhatsApp.';
  end if;
  if c.ultimo_entrante_at is null or c.ultimo_entrante_at < now() - interval '24 hours' then
    raise exception 'ENVIO RECHAZADO: la ventana de 24 horas está cerrada. Solo se le puede escribir con una plantilla aprobada.';
  end if;
  select count(*) into en_curso from public.mensajes_envios
   where chat_id = new.chat_id and estado = 'enviando' and created_at > now() - interval '2 minutes';
  if c.toques_sin_respuesta + en_curso >= 2 then
    raise exception 'ENVIO RECHAZADO: ya van 2 mensajes sin respuesta en este chat. No se insiste.';
  end if;
  if c.tomado_por is not null and lower(c.tomado_por) <> new.por and new.por <> 'hola@casazaru.cl' then
    raise exception 'ENVIO RECHAZADO: este chat lo lleva otra persona.';
  end if;
  if new.texto ~ '\[PRECIO' then
    raise exception 'ENVIO RECHAZADO: falta completar un precio. Busca [PRECIO: …] en el texto.';
  end if;
  if new.texto ~* '\mnativ[ao]s?\M' then
    raise exception 'ENVIO RECHAZADO: el texto dice «nativa». Se dice «madera noble».';
  end if;
  if new.texto ~* '\mal tiro\M' then
    raise exception 'ENVIO RECHAZADO: el texto dice «al tiro». Cámbialo por otra expresión.';
  end if;
  if new.texto ~ '[¡¿]' then
    raise exception 'ENVIO RECHAZADO: el texto usa signos de apertura (¡ o ¿). Solo van los de cierre.';
  end if;
  return new;
end $$;

drop trigger if exists tr_mensajes_envios_permitido on public.mensajes_envios;
create trigger tr_mensajes_envios_permitido before insert on public.mensajes_envios
  for each row execute function public.mensajes_envio_permitido();
drop trigger if exists tr_mensajes_envios_sellar on public.mensajes_envios;
create trigger tr_mensajes_envios_sellar before update on public.mensajes_envios
  for each row execute function public.mensajes_sellar();
drop trigger if exists tr_mensajes_envios_hist on public.mensajes_envios;
create trigger tr_mensajes_envios_hist after update or delete on public.mensajes_envios
  for each row execute function public.mensajes_historial_guardar();

-- ── RLS: leen el dueño y los vendedores activos; escribe solo la llave de servicio ──
alter table public.mensajes_envios enable row level security;
alter table public.mensajes_envios force  row level security;
drop policy if exists mensajes_envios_leer on public.mensajes_envios;
create policy mensajes_envios_leer on public.mensajes_envios
  for select to authenticated using (public.mensajes_puede_leer());
revoke all on public.mensajes_envios from anon, authenticated;
grant select on public.mensajes_envios to authenticated;

-- Registro
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('0006', 'bandeja_envios', array[
  'create table mensajes_envios (reserva idempotente de cada envio; ver supabase-cotizador/migrations/0006_bandeja_envios.sql);',
  'trigger mensajes_envio_permitido: solo WhatsApp, ventana de 24 h, tope de 2 sin respuesta, chat tomado, texto sin [PRECIO], nativa, al tiro ni signos de apertura;',
  'RLS + FORCE; select para authenticated solo si mensajes_puede_leer(); anon sin permisos.'
])
on conflict (version) do nothing;

-- Verificación. Debe dar: tabla 1 · rls_force true · policies 1 · triggers 3 ·
-- anon_algo 0 · auth_escribe 0 · service_inserta true · ultima 0006.
select
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'mensajes_envios')                              as tabla,
  (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.mensajes_envios'::regclass) as rls_force,
  (select count(*) from pg_policies where schemaname = 'public' and tablename = 'mensajes_envios') as policies,
  (select count(*) from pg_trigger where tgrelid = 'public.mensajes_envios'::regclass and not tgisinternal) as triggers,
  (select count(*) from unnest(array['select','insert','update','delete','truncate']) p
    where has_table_privilege('anon', 'public.mensajes_envios', p))                            as anon_algo,
  (select count(*) from unnest(array['insert','update','delete','truncate']) p
    where has_table_privilege('authenticated', 'public.mensajes_envios', p))                   as auth_escribe,
  has_table_privilege('service_role', 'public.mensajes_envios', 'insert')                      as service_inserta,
  (select max(version) from supabase_migrations.schema_migrations)                             as ultima;

-- Rollback (NO correr junto con lo de arriba; respaldar antes: select * from public.mensajes_envios):
--   drop table public.mensajes_envios;
--   drop function public.mensajes_envio_permitido();
--   delete from supabase_migrations.schema_migrations where version = '0006';
