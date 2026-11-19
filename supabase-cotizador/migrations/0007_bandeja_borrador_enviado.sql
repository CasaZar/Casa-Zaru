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
  if to_regclass('public.mensajes_envios') is null
     or not exists (select 1 from supabase_migrations.schema_migrations where version = '0006') then
    raise exception 'FALTA LA 0006: aplicar antes 0006_bandeja_envios.sql. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- 0007 · COTIZADOR · Bandeja: el borrador que se usó queda marcado (19-11-2026)
--
-- En la primera prueba real (18-11, 23:56) el dueño envió el borrador que tenía
-- en pantalla justo después de que entrara otro mensaje suyo. Ese borrador ya
-- estaba «caducado», la función solo marcaba los «pendientes» y quedó sin
-- marcar como enviado. El envío sí quedó bien registrado en mensajes_envios.
--
-- Arreglo: lo hace la base y no depende del orden de pasos de la función.
-- Cuando una reserva pasa a «enviado», su borrador queda como «enviado» (si el
-- texto salió igual) o «editado_enviado» (si la persona lo cambió), con el texto
-- final y quién lo aprobó. Vale aunque el borrador ya estuviera caducado.
--
-- Incluye el arreglo del único envío hecho hasta hoy (el de la prueba): 1 fila
-- de mensajes_borradores; su versión anterior queda en mensajes_historial.
-- Idempotente. Rollback al final.
--
-- APLICADA el 19-11-2026 en el SQL Editor del Cotizador (con ok del dueño).
-- Verificación: triggers_envios 4, enviados_sin_marcar 0, borradores_enviados 1,
-- última 0007. Regla probada con supabase-cotizador/prueba-0007-reglas.sql: 4 de 4.
-- ══════════════════════════════════════════════════════════════════════════

create or replace function public.mensajes_envio_marca_borrador()
returns trigger language plpgsql as $$
begin
  if new.estado = 'enviado' and old.estado is distinct from 'enviado' and new.borrador_id is not null then
    update public.mensajes_borradores b
       set estado = case when btrim(b.texto) = btrim(new.texto) then 'enviado' else 'editado_enviado' end,
           texto_final = new.texto,
           aprobado_por = new.por
     where b.id = new.borrador_id and b.chat_id = new.chat_id and b.estado in ('pendiente', 'caducado');
  end if;
  return new;
end $$;

drop trigger if exists tr_mensajes_envios_borrador on public.mensajes_envios;
create trigger tr_mensajes_envios_borrador after update on public.mensajes_envios
  for each row execute function public.mensajes_envio_marca_borrador();

-- Lo ya enviado cuyo borrador quedó sin marcar (hoy: el de la prueba del 18-11).
update public.mensajes_borradores b
   set estado = case when btrim(b.texto) = btrim(e.texto) then 'enviado' else 'editado_enviado' end,
       texto_final = e.texto,
       aprobado_por = e.por
  from public.mensajes_envios e
 where e.estado = 'enviado' and e.borrador_id = b.id and e.chat_id = b.chat_id
   and b.estado in ('pendiente', 'caducado');

-- Registro
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('0007', 'bandeja_borrador_enviado', array[
  'trigger tr_mensajes_envios_borrador: al pasar una reserva a enviado, su borrador queda enviado o editado_enviado, aunque estuviera caducado;',
  'arreglo de los borradores de envios ya hechos (1 fila, la prueba del 18-11).'
])
on conflict (version) do nothing;

-- Verificación. Debe dar: triggers_envios 4 · enviados_sin_marcar 0 · ultima 0007.
select
  (select count(*) from pg_trigger where tgrelid = 'public.mensajes_envios'::regclass and not tgisinternal) as triggers_envios,
  (select count(*) from public.mensajes_envios e join public.mensajes_borradores b on b.id = e.borrador_id
    where e.estado = 'enviado' and b.estado not in ('enviado', 'editado_enviado'))                          as enviados_sin_marcar,
  (select count(*) from public.mensajes_borradores where estado in ('enviado', 'editado_enviado'))         as borradores_enviados,
  (select max(version) from supabase_migrations.schema_migrations)                                          as ultima;

-- Rollback (NO correr junto con lo de arriba):
--   drop trigger tr_mensajes_envios_borrador on public.mensajes_envios;
--   drop function public.mensajes_envio_marca_borrador();
--   delete from supabase_migrations.schema_migrations where version = '0007';
--   (el borrador arreglado se puede volver a «caducado» desde mensajes_historial)
