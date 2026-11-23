-- ── CANDADO DE PROYECTO (no borrar) ──────────────────────────────────────
-- Este archivo es del COTIZADOR (cmxqorsyxoltrakxawro). Si se pega en el SQL
-- Editor de otro proyecto, falla primero y no se aplica nada.
do $candado$
begin
  if to_regclass('public.gestion_pedidos') is not null then
    raise exception 'PROYECTO EQUIVOCADO: este SQL es del COTIZADOR (cmxqorsyxoltrakxawro) y lo estás corriendo en GESTIÓN. No se aplicó nada.';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '0011') then
    raise exception 'FALTA LA 0011. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- Prueba de la 0011: si una persona responde desde el panel, el asistente se calla.
-- NO DEJA NADA GUARDADO y NO ENVÍA NADA: termina SIEMPRE con un error a propósito, que deshace todo.
do $prueba$
declare
  c bigint; m1 bigint; m2 bigint; b1 bigint; b2 bigint; r record; fallo text := '';
begin
  insert into public.mensajes_chats (canal, contacto_id) values ('whatsapp', 'PRUEBA-0011') returning id into c;
  insert into public.mensajes (chat_id, meta_id, direccion, autor, texto, payload, enviado_at)
    values (c, 'prueba-0011-m1', 'entrante', 'cliente', 'hola', '{}'::jsonb, now()) returning id into m1;
  insert into public.mensajes_borradores (chat_id, mensaje_id, texto, modelo, auto_desde)
    values (c, m1, 'Hola, cómo estás?', 'prueba', now() + interval '2 minutes') returning id into b1;

  -- 1) un mensaje automático NO toma el chat y deja el borrador agendado
  insert into public.mensajes (chat_id, meta_id, direccion, autor, texto, payload, enviado_at)
    values (c, 'prueba-0011-a1', 'saliente', 'automatico', 'Listo, voy a preparar tu cotización.', '{}'::jsonb, now());
  select estado, tomado_por, toques_sin_respuesta into r from public.mensajes_chats where id = c;
  if r.tomado_por is not null or r.estado <> 'esperando' or r.toques_sin_respuesta <> 1 then
    fallo := fallo || ' [1 lo automatico tomo el chat o no conto: ' || r.estado || ']';
  end if;
  if (select auto_desde from public.mensajes_borradores where id = b1) is null then fallo := fallo || ' [1 lo automatico desagendo]'; end if;

  -- 2) una persona envía desde el panel: el chat queda a su nombre, en «de César», y se desagenda
  insert into public.mensajes (chat_id, meta_id, direccion, autor, texto, payload, enviado_at, enviado_por)
    values (c, 'prueba-0011-p1', 'saliente', 'bandeja', 'Hola, te ayudo.', '{}'::jsonb, now(), 'Persona@Prueba.cl');
  select estado, tomado_por, tomado_at, toques_sin_respuesta into r from public.mensajes_chats where id = c;
  if r.tomado_por is distinct from 'persona@prueba.cl' or r.estado <> 'de_cesar' or r.tomado_at is null or r.toques_sin_respuesta <> 2 then
    fallo := fallo || ' [2 el envio de una persona no tomo el chat: ' || coalesce(r.tomado_por, 'null') || ' ' || r.estado || ']';
  end if;
  select auto_desde, para, estado into r from public.mensajes_borradores where id = b1;
  if r.auto_desde is not null or r.para <> 'cesar' or r.estado <> 'pendiente' then
    fallo := fallo || ' [2 el borrador siguio agendado o no quedo como sugerencia]';
  end if;

  -- 3) desde ahí nada automático entra en ese chat
  begin
    insert into public.mensajes (chat_id, meta_id, direccion, autor, texto, payload, enviado_at)
      values (c, 'prueba-0011-a2', 'saliente', 'automatico', 'respuesta sola', '{}'::jsonb, now());
    fallo := fallo || ' [3 SALIO ALGO AUTOMATICO EN UN CHAT TOMADO]';
  exception when others then null; end;

  -- 4) el cliente responde: el chat sigue siendo de la persona y el borrador nuevo es solo sugerencia
  insert into public.mensajes (chat_id, meta_id, direccion, autor, texto, payload, enviado_at)
    values (c, 'prueba-0011-m2', 'entrante', 'cliente', 'gracias', '{}'::jsonb, now()) returning id into m2;
  select estado, tomado_por, toques_sin_respuesta into r from public.mensajes_chats where id = c;
  if r.tomado_por is distinct from 'persona@prueba.cl' or r.estado <> 'de_cesar' or r.toques_sin_respuesta <> 0 then
    fallo := fallo || ' [4 al responder el cliente el chat volvio a la bandeja]';
  end if;
  insert into public.mensajes_borradores (chat_id, mensaje_id, texto, modelo) values (c, m2, 'De nada.', 'prueba') returning id into b2;
  if (select para from public.mensajes_borradores where id = b2) <> 'cesar' then fallo := fallo || ' [4 el borrador nuevo no es sugerencia]'; end if;

  -- 5) una segunda persona que envía no le quita el chat a la primera
  insert into public.mensajes (chat_id, meta_id, direccion, autor, texto, payload, enviado_at, enviado_por)
    values (c, 'prueba-0011-p2', 'saliente', 'bandeja', 'otra persona', '{}'::jsonb, now(), 'otra@prueba.cl');
  if (select tomado_por from public.mensajes_chats where id = c) is distinct from 'persona@prueba.cl' then
    fallo := fallo || ' [5 cambio de dueno]';
  end if;

  raise exception 'PRUEBA 0011 TERMINADA (todo se deshace): %',
    case when fallo = '' then 'TODO OK, 5 de 5' else 'FALLOS:' || fallo end;
end
$prueba$;
