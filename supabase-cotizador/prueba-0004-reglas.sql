-- ── CANDADO DE PROYECTO (no borrar) ──────────────────────────────────────
-- Este archivo es del COTIZADOR (cmxqorsyxoltrakxawro). Si se pega en el SQL
-- Editor de otro proyecto, falla primero y no se aplica nada.
do $candado$
begin
  if to_regclass('public.gestion_pedidos') is not null then
    raise exception 'PROYECTO EQUIVOCADO: este SQL es del COTIZADOR (cmxqorsyxoltrakxawro) y lo estás corriendo en GESTIÓN. No se aplicó nada.';
  end if;
  if to_regclass('public.mensajes_chats') is null then
    raise exception 'FALTA LA 0004 (no existe mensajes_chats). No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- Prueba de las reglas de la 0004 (bandeja de mensajes). NO DEJA NADA GUARDADO:
-- termina SIEMPRE con un error a propósito («PRUEBA 0004 TERMINADA … TODO OK»),
-- y como todo corre en una sola transacción, Postgres deshace las filas de prueba.
-- El resultado se lee en el mensaje de ese error.
do $prueba$
declare
  c bigint; m1 bigint; b1 bigint; r record; fallo text := '';
begin
  insert into public.mensajes_chats (canal, contacto_id, nombre)
    values ('whatsapp', 'PRUEBA-0004', 'Prueba') returning id into c;

  -- 1) el cliente escribe: por_aprobar y ventana de 24 h marcada
  insert into public.mensajes (chat_id, meta_id, direccion, autor, texto, payload, enviado_at)
    values (c, 'prueba-0004-1', 'entrante', 'cliente', 'hola', '{}'::jsonb, now()) returning id into m1;
  select estado, toques_sin_respuesta as t, ultimo_entrante_at is not null as u into r from public.mensajes_chats where id = c;
  if r.estado <> 'por_aprobar' or not r.u then fallo := fallo || ' [1 cliente no deja por_aprobar]'; end if;

  -- 2) borrador en chat libre: para la bandeja
  insert into public.mensajes_borradores (chat_id, mensaje_id, texto, modelo)
    values (c, m1, 'borrador', 'prueba') returning id into b1;
  if (select para from public.mensajes_borradores where id = b1) <> 'bandeja' then fallo := fallo || ' [2 para <> bandeja]'; end if;

  -- 3) un envío desde la bandeja sin nombre de quién aprobó: la base lo rechaza
  begin
    insert into public.mensajes (chat_id, meta_id, direccion, autor, texto, payload, enviado_at)
      values (c, 'prueba-0004-2', 'saliente', 'bandeja', 'x', '{}'::jsonb, now());
    fallo := fallo || ' [3 bandeja sin nombre PASO]';
  exception when check_violation then null;
  end;

  -- 4) envío aprobado: esperando, 1 toque sin respuesta
  insert into public.mensajes (chat_id, meta_id, direccion, autor, texto, payload, enviado_at, enviado_por)
    values (c, 'prueba-0004-3', 'saliente', 'bandeja', 'x', '{}'::jsonb, now(), 'prueba');
  select estado, toques_sin_respuesta as t into r from public.mensajes_chats where id = c;
  if r.estado <> 'esperando' or r.t <> 1 then fallo := fallo || ' [4 bandeja no deja esperando/1]'; end if;

  -- 5) un borrador no se marca enviado sin aprobador
  begin
    update public.mensajes_borradores set estado = 'enviado' where id = b1;
    fallo := fallo || ' [5 enviado sin aprobador PASO]';
  exception when check_violation then null;
  end;

  -- 6) alguien escribe a mano (externo): el chat pasa a de_cesar y el borrador pendiente caduca
  insert into public.mensajes (chat_id, meta_id, direccion, autor, texto, payload, enviado_at)
    values (c, 'prueba-0004-4', 'saliente', 'externo', 'x', '{}'::jsonb, now());
  select estado, tomado_por into r from public.mensajes_chats where id = c;
  if r.estado <> 'de_cesar' or r.tomado_por is null then fallo := fallo || ' [6 externo no toma el chat]'; end if;
  if (select estado from public.mensajes_borradores where id = b1) <> 'caducado' then fallo := fallo || ' [6 borrador no caduca]'; end if;

  -- 7) nada automático en un chat tomado
  begin
    insert into public.mensajes (chat_id, meta_id, direccion, autor, texto, payload, enviado_at)
      values (c, 'prueba-0004-5', 'saliente', 'automatico', 'x', '{}'::jsonb, now());
    fallo := fallo || ' [7 automatico en chat tomado PASO]';
  exception when others then
    if sqlerrm not like 'CHAT TOMADO%' then fallo := fallo || ' [7 otro error: ' || sqlerrm || ']'; end if;
  end;

  -- 8) un chat tomado no vuelve a la bandeja
  begin
    update public.mensajes_chats set tomado_por = null, estado = 'por_aprobar' where id = c;
    fallo := fallo || ' [8 destomar PASO]';
  exception when others then
    if sqlerrm not like 'Un chat tomado%' then fallo := fallo || ' [8 otro error: ' || sqlerrm || ']'; end if;
  end;

  -- 9) el cliente vuelve a escribir en un chat tomado: sigue de_cesar y el borrador nuevo es para César
  insert into public.mensajes (chat_id, meta_id, direccion, autor, texto, payload, enviado_at)
    values (c, 'prueba-0004-6', 'entrante', 'cliente', 'y?', '{}'::jsonb, now()) returning id into m1;
  select estado, toques_sin_respuesta as t into r from public.mensajes_chats where id = c;
  if r.estado <> 'de_cesar' or r.t <> 0 then fallo := fallo || ' [9 chat tomado cambia de estado]'; end if;
  insert into public.mensajes_borradores (chat_id, mensaje_id, texto, modelo)
    values (c, m1, 'sugerencia', 'prueba') returning id into b1;
  if (select para from public.mensajes_borradores where id = b1) <> 'cesar' then fallo := fallo || ' [9 para <> cesar]'; end if;

  -- 10) Meta reintenta el mismo mensaje: no se duplica
  begin
    insert into public.mensajes (chat_id, meta_id, direccion, autor, texto, payload, enviado_at)
      values (c, 'prueba-0004-6', 'entrante', 'cliente', 'y?', '{}'::jsonb, now());
    fallo := fallo || ' [10 duplicado PASO]';
  exception when unique_violation then null;
  end;

  -- 11) el historial guardó las versiones anteriores del chat y del borrador
  if (select count(*) from public.mensajes_historial where tabla = 'mensajes_chats' and fila_id = c) < 3 then
    fallo := fallo || ' [11 falta historial del chat]';
  end if;
  if not exists (select 1 from public.mensajes_historial where tabla = 'mensajes_borradores') then
    fallo := fallo || ' [11 falta historial del borrador]';
  end if;

  raise exception 'PRUEBA 0004 TERMINADA (todo se deshace): %',
    case when fallo = '' then 'TODO OK, 11 de 11' else 'FALLOS:' || fallo end;
end
$prueba$;
