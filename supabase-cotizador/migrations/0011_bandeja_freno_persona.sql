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
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '0009') then
    raise exception 'FALTA LA 0009: aplicar antes 0009_bandeja_espera.sql. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- 0011 · COTIZADOR · Bandeja: si una persona responde, el asistente se calla (23-11-2026)
--
-- Regla del dueño: «una vez que entra a contestar César o yo, no respondas más esa
-- conversación». Hasta hoy solo se cumplía si la persona escribía desde el celular
-- (autor «externo») o apretaba «Tomar este chat». Un envío hecho desde la bandeja con
-- el botón Enviar NO tomaba el chat, y el asistente habría seguido respondiendo solo.
--
-- Cambio: un mensaje «bandeja» (lo envió una persona desde el panel) toma el chat a
-- nombre de quien lo envió, igual que el botón. Desde ahí:
--   · nada automático sale en ese chat (ya lo hacían cumplir mensajes_sin_auto_en_tomado
--     y la función, que mira tomado_por);
--   · los borradores siguen llegando, pero como sugerencia para esa persona;
--   · lo que estuviera agendado para salir solo se desagenda.
-- No toca los chats que ya existen: vale para los envíos de aquí en adelante.
-- (La 0010 es del panel de campañas y no tiene relación; esta no depende de ella.)
--
-- Idempotente. Rollback al final.
-- ══════════════════════════════════════════════════════════════════════════

create or replace function public.mensajes_tomar_chat()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.autor = 'externo' then
    update public.mensajes_chats
       set estado = 'de_cesar', tomado_por = coalesce(tomado_por, 'cesar'), tomado_at = coalesce(tomado_at, new.enviado_at)
     where id = new.chat_id and tomado_por is null;
    update public.mensajes_borradores set estado = 'caducado'
     where chat_id = new.chat_id and estado = 'pendiente';
  elsif new.autor = 'cliente' then
    update public.mensajes_chats
       set ultimo_entrante_at = greatest(coalesce(ultimo_entrante_at, new.enviado_at), new.enviado_at),
           toques_sin_respuesta = 0,
           estado = case when tomado_por is null then 'por_aprobar' else estado end
     where id = new.chat_id;
  elsif new.autor = 'bandeja' then
    -- una persona respondió desde el panel: el chat pasa a ser suyo
    update public.mensajes_chats
       set toques_sin_respuesta = toques_sin_respuesta + 1,
           estado = 'de_cesar',
           tomado_por = coalesce(tomado_por, lower(nullif(btrim(new.enviado_por), '')), 'cesar'),
           tomado_at = coalesce(tomado_at, new.enviado_at)
     where id = new.chat_id;
    update public.mensajes_borradores set auto_desde = null, para = 'cesar'
     where chat_id = new.chat_id and estado = 'pendiente';
  else -- automatico
    update public.mensajes_chats
       set toques_sin_respuesta = toques_sin_respuesta + 1,
           estado = case when tomado_por is null then 'esperando' else estado end
     where id = new.chat_id;
  end if;
  return new;
end $$;
revoke all on function public.mensajes_tomar_chat() from public, anon, authenticated;

-- Registro
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('0011', 'bandeja_freno_persona', array[
  'create or replace function mensajes_tomar_chat(): un mensaje bandeja (enviado por una persona desde el panel) toma el chat a su nombre, desagenda lo automático y deja los borradores como sugerencia.'
])
on conflict (version) do nothing;

-- Verificación. Debe dar: toma_bandeja true · trigger 1 · chats_tomados (los que ya había, no cambia) · registrada 1.
select
  (select position('new.autor = ''bandeja''' in pg_get_functiondef('public.mensajes_tomar_chat()'::regprocedure)) > 0) as toma_bandeja,
  (select count(*) from pg_trigger where tgrelid = 'public.mensajes'::regclass and tgname = 'tr_mensajes_tomar')     as trigger,
  (select count(*) from public.mensajes_chats where tomado_por is not null)                                           as chats_tomados,
  (select count(*) from supabase_migrations.schema_migrations where version = '0011')                                 as registrada;

-- Rollback (NO correr junto con lo de arriba): volver a crear mensajes_tomar_chat() con el cuerpo de
-- la 0004 (rama «else -- bandeja / automatico» sin tomar el chat) y
--   delete from supabase_migrations.schema_migrations where version = '0011';
-- Los chats que se hayan tomado mientras tanto quedan tomados (un chat tomado no vuelve a la bandeja).
