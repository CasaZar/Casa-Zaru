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
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '0014') then
    raise exception 'FALTA LA 0014: aplicar antes 0014_bandeja_avisos.sql. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- 0017 · COTIZADOR · Bandeja: frases de la casa que el dueño corrige desde Mensajes (26-11-2026)
--
-- Pedido del dueño: «dejar alguna parte donde yo pueda ir corrigiendo ciertas frases, frases fijas
-- que siempre decimos, que ya son protocolares». Hasta hoy esas frases vivían dentro del código de la
-- función y cambiarlas obligaba a desplegar.
--
--   mensajes_frases   una frase con su situación («cuándo»). Tres tipos:
--       fija        el asistente la dice tal cual cuando se da la situación (saludo, aviso de cotización,
--                   plazo…). La de clave «aviso_cotiza» es el texto que sale solo antes del link.
--       preferida   frases que en los chats del 5558 ayudaron a vender: las usa cuando calzan.
--       evitar      nunca las dice. La función además revisa cada borrador: si trae una de estas,
--                   no sale solo y queda para una persona.
--   La escribe SOLO la función (ruta /frases, con la sesión del dueño). El equipo de la bandeja la lee.
--   Toda versión anterior queda en mensajes_historial (trigger), y se borra con deleted_at.
--
-- Semillas: frases que ya estaban en las instrucciones del asistente y las de RW\frases.tsv que
-- terminaron en compra (sin las que dependen de cupo, stock o montos, que el asistente no sabe).
-- Idempotente (las semillas llevan clave y no se repiten). Rollback al final.
-- ══════════════════════════════════════════════════════════════════════════

create table if not exists public.mensajes_frases (
  id          bigint generated always as identity primary key,
  tipo        text not null check (tipo in ('fija', 'preferida', 'evitar')),
  clave       text check (clave is null or clave ~ '^[a-z_]{3,30}$'),
  cuando      text not null check (length(btrim(cuando)) between 3 and 300),
  frase       text not null check (length(btrim(frase)) between 2 and 800),
  activo      boolean not null default true,
  orden       integer not null default 100 check (orden between 0 and 10000),
  deleted_at  timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  updated_by  text not null default coalesce(auth.jwt() ->> 'email', 'mensajes-webhook'),
  constraint mensajes_frases_clave_uk unique (clave),
  -- Lo que el asistente va a decir cumple las mismas reglas que un envío: sin signos de apertura y
  -- nunca «nativa». Las frases «evitar» quedan libres (justamente son las que no se dicen).
  constraint mensajes_frases_limpia check (
    tipo = 'evitar' or (frase !~ '[¡¿]' and frase !~* '(^|[^a-záéíóúüñ])nativ[ao]s?([^a-záéíóúüñ]|$)'))
);
comment on table public.mensajes_frases is
  'Frases de la casa para el asistente de la bandeja (fija / preferida / evitar). Las edita el dueño desde Mensajes vía la función mensajes-webhook (/frases).';
create index if not exists mensajes_frases_vivas_idx on public.mensajes_frases (tipo, orden) where deleted_at is null;

-- Quién cambió: con la llave de servicio no hay correo en el JWT, así que vale el updated_by que manda
-- la función (el correo de quien editó). Sin eso, «mensajes-webhook».
create or replace function public.mensajes_frases_sellar()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  new.updated_by := coalesce(auth.jwt() ->> 'email',
                             case when new.updated_by is distinct from old.updated_by then new.updated_by end,
                             'mensajes-webhook');
  return new;
end $$;
revoke all on function public.mensajes_frases_sellar() from public, anon, authenticated;

drop trigger if exists tr_mensajes_frases_sellar on public.mensajes_frases;
create trigger tr_mensajes_frases_sellar before update on public.mensajes_frases
  for each row execute function public.mensajes_frases_sellar();
drop trigger if exists tr_mensajes_frases_hist on public.mensajes_frases;
create trigger tr_mensajes_frases_hist after update or delete on public.mensajes_frases
  for each row execute function public.mensajes_historial_guardar();

alter table public.mensajes_frases enable row level security;
alter table public.mensajes_frases force  row level security;
drop policy if exists mensajes_frases_leer on public.mensajes_frases;
create policy mensajes_frases_leer on public.mensajes_frases
  for select to authenticated using (public.mensajes_puede_leer());

revoke all on public.mensajes_frases from public, anon, authenticated;
grant select on public.mensajes_frases to authenticated;
grant select, insert, update on public.mensajes_frases to service_role;

-- Semillas
insert into public.mensajes_frases (tipo, clave, cuando, frase, orden, updated_by) values
  ('fija', 'saludo', 'Primer mensaje nuestro en el chat (después ya no se presenta)',
   'Hola [nombre], cómo estás? Te escribe César de Casa Zaru.', 10, 'migración 0017'),
  ('fija', 'aviso_cotiza', 'Apenas el cliente da sus medidas: sale solo mientras se arma su cotización',
   'Listo, voy a preparar tu cotización. Dame unos minutos y te la envío.', 20, 'migración 0017'),
  ('fija', 'plazo', 'Cuando pregunten cuánto se demora',
   'La fabricación toma de 7 a 15 días hábiles desde que se confirma el pedido.', 30, 'migración 0017'),
  ('fija', 'despedida_no', 'Cuando el cliente dice que no le interesa o que ya compró en otro lado',
   'Muchas gracias por escribirnos. Si más adelante lo necesitas, aquí estamos.', 40, 'migración 0017'),
  ('preferida', 'plano_antes', 'Medidas especiales o el cliente tiene dudas de las medidas',
   'Antes de fabricar te mandamos un plano con todas las medidas para que lo apruebes.', 10, 'migración 0017'),
  ('preferida', 'precio_escasez', 'Compara maderas por precio o pregunta por qué una vale más',
   'El precio no pasa por la dureza sino por la escasez; todas son funcionales.', 20, 'migración 0017'),
  ('preferida', 'no_recomiendo', 'Pide una madera o terminación que no conviene para ese uso',
   'Es funcional, pero no lo recomiendo para ese uso.', 30, 'migración 0017'),
  ('preferida', 'muestras_tono', 'Duda del tono o de la madera (después lo sigue una persona)',
   'Podemos preparar unas muestras en distintos tonos para que las apruebes antes de fabricar.', 40, 'migración 0017'),
  ('preferida', 'ensamble', 'Pregunta si la cubierta o la mesa es de una sola pieza',
   'Son ensambles con maderos de a lo más 15 cm: la pieza completa tiende a curvarse y el ensamble resiste mucho mejor.', 50, 'migración 0017'),
  ('preferida', 'espesor', 'Pide un espesor de 5 o 6 cm',
   'El espesor máximo es 4 cm; con un regrueso en el borde se logra un espesor aparente mayor.', 60, 'migración 0017'),
  ('evitar', 'te_sale', 'Para hablar de precios (decir «tiene un valor de», «queda en»)', 'te sale', 10, 'migración 0017'),
  ('evitar', 'te_adjunto', 'El asistente no puede mandar archivos ni fotos', 'te adjunto', 20, 'migración 0017'),
  ('evitar', 'te_mando_fotos', 'El asistente no puede mandar fotos: manda el link del catálogo', 'te mando fotos', 30, 'migración 0017')
on conflict (clave) do nothing;

-- Registro
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('0017', 'bandeja_frases', array[
  'create table mensajes_frases (fija / preferida / evitar; RLS + FORCE; select para el equipo; escribe solo la función);',
  'triggers: mensajes_frases_sellar (guarda quién editó) e historial en mensajes_historial;',
  'semillas: 4 fijas, 6 preferidas (frases.tsv que terminaron en compra) y 3 a evitar.'
])
on conflict (version) do nothing;

-- Verificación. Debe dar: tabla 1 · rls true · policies 1 · triggers 2 · semillas 13 · anon_lee false · registrada 1.
select
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'mensajes_frases')                                         as tabla,
  (select c.relrowsecurity and c.relforcerowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'mensajes_frases')                                         as rls,
  (select count(*) from pg_policies where schemaname = 'public' and tablename = 'mensajes_frases')        as policies,
  (select count(*) from pg_trigger where tgrelid = 'public.mensajes_frases'::regclass and not tgisinternal) as triggers,
  (select count(*) from public.mensajes_frases where updated_by = 'migración 0017')                        as semillas,
  (select has_table_privilege('anon', 'public.mensajes_frases', 'select'))                                 as anon_lee,
  (select count(*) from supabase_migrations.schema_migrations where version = '0017')                      as registrada;

-- Rollback (NO correr junto con lo de arriba). Antes, respaldar las filas si el dueño ya editó frases:
--   select * from public.mensajes_frases;   (copiar el resultado)
--   drop table public.mensajes_frases;
--   drop function public.mensajes_frases_sellar();
--   delete from supabase_migrations.schema_migrations where version = '0017';
-- La función sigue funcionando sin la tabla: usa el aviso de cotización de siempre y no agrega frases.
