-- ── CANDADO DE PROYECTO (no borrar) ──────────────────────────────────────
-- Este archivo es del COTIZADOR (cmxqorsyxoltrakxawro). Si se pega en el SQL
-- Editor de otro proyecto, este bloque falla primero y Postgres descarta el
-- resto del script: no se aplica nada.
do $candado$
begin
  if to_regclass('public.gestion_pedidos') is not null then
    raise exception 'PROYECTO EQUIVOCADO: este SQL es del COTIZADOR (cmxqorsyxoltrakxawro) y lo estás corriendo en GESTIÓN. No se aplicó nada.';
  end if;
  if to_regclass('public.cotizaciones') is null then
    raise exception 'PROYECTO EQUIVOCADO: este SQL es del COTIZADOR (cmxqorsyxoltrakxawro) y aquí no existe la tabla cotizaciones. No se aplicó nada.';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '0017') then
    raise exception 'FALTA LA 0017: aplicar antes 0017_bandeja_frases.sql. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- 0018 · COTIZADOR · Bandeja: «Devolver al asistente» por fin puede devolver el chat (26-11-2026)
--
-- La 0017 agregó la ruta /soltar y el botón «Devolver al asistente», pero el trigger de la 0004
-- mensajes_chat_no_destomar rechaza TODO update que deje tomado_por en null («Un chat tomado no
-- vuelve a la bandeja»). Resultado: el botón respondía siempre «No se pudo devolver el chat».
--
-- Ahora el chat puede volver al asistente solo si es a propósito:
--   · lo hace la función (rol service_role; el navegador no tiene permiso de update en esta tabla), y
--   · el mismo update deja estado = 'por_aprobar' y tomado_at en null, que es exactamente lo que
--     manda /soltar (después de revisar que quien pide es el dueño o quien lleva el chat).
-- Cualquier otro update que borre tomado_por sigue fallando como antes. La versión anterior del chat
-- queda en mensajes_historial (trigger de la 0004), así que se sabe quién lo llevaba.
-- Idempotente. Rollback al final.
-- ══════════════════════════════════════════════════════════════════════════

create or replace function public.mensajes_chat_no_destomar()
returns trigger language plpgsql as $$
begin
  if old.tomado_por is not null and new.tomado_por is null then
    if current_user = 'service_role' and new.estado = 'por_aprobar' and new.tomado_at is null then
      return new;   -- /soltar: devolver al asistente (0018)
    end if;
    raise exception 'Un chat tomado no vuelve a la bandeja.';
  end if;
  return new;
end $$;

-- Registro
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('0018', 'bandeja_soltar', array[
  'create or replace function mensajes_chat_no_destomar: deja devolver el chat al asistente solo a service_role con estado por_aprobar y tomado_at null (ruta /soltar).'
])
on conflict (version) do nothing;

-- Verificación. Debe dar: permite_soltar true · registrada 1.
select
  (select pg_get_functiondef('public.mensajes_chat_no_destomar'::regproc) like '%service_role%') as permite_soltar,
  (select count(*) from supabase_migrations.schema_migrations where version = '0018')            as registrada;

-- Rollback (NO correr junto con lo de arriba): vuelve a la versión de la 0004.
--   create or replace function public.mensajes_chat_no_destomar()
--   returns trigger language plpgsql as $f$
--   begin
--     if old.tomado_por is not null and new.tomado_por is null then
--       raise exception 'Un chat tomado no vuelve a la bandeja.';
--     end if;
--     return new;
--   end $f$;
--   delete from supabase_migrations.schema_migrations where version = '0018';
