-- ── CANDADO DE PROYECTO (no borrar) ──────────────────────────────────────
-- Este archivo es del COTIZADOR (cmxqorsyxoltrakxawro). Si se pega en el SQL
-- Editor de otro proyecto, falla primero y no se aplica nada.
do $candado$
begin
  if to_regclass('public.gestion_pedidos') is not null then
    raise exception 'PROYECTO EQUIVOCADO: este SQL es del COTIZADOR (cmxqorsyxoltrakxawro) y lo estás corriendo en GESTIÓN. No se aplicó nada.';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'tr_mensajes_envios_borrador') then
    raise exception 'FALTA LA 0007 (no existe tr_mensajes_envios_borrador). No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- Prueba de la 0007: el borrador que se usó queda marcado. NO DEJA NADA GUARDADO
-- y NO ENVÍA NADA: termina SIEMPRE con un error a propósito, que deshace todo.
do $prueba$
declare
  c bigint; m1 bigint; m2 bigint; b1 bigint; b2 bigint; e1 bigint; e2 bigint; r record; fallo text := '';
begin
  insert into public.mensajes_chats (canal, contacto_id) values ('whatsapp', 'PRUEBA-0007') returning id into c;
  insert into public.mensajes (chat_id, meta_id, direccion, autor, texto, payload, enviado_at)
    values (c, 'prueba-0007-m1', 'entrante', 'cliente', 'hola', '{}'::jsonb, now()) returning id into m1;
  insert into public.mensajes_borradores (chat_id, mensaje_id, texto, modelo) values (c, m1, 'Hola, cómo estás?', 'prueba') returning id into b1;

  -- 1) texto igual al borrador, y el borrador ya CADUCADO (lo que pasó el 18-11): queda «enviado»
  update public.mensajes_borradores set estado = 'caducado' where id = b1;
  insert into public.mensajes_envios (clave, chat_id, borrador_id, texto, por)
    values ('prueba-0007-clave-01', c, b1, 'Hola, cómo estás?', 'hola@casazaru.cl') returning id into e1;
  if (select estado from public.mensajes_borradores where id = b1) <> 'caducado' then fallo := fallo || ' [1 se marco antes de enviar]'; end if;
  update public.mensajes_envios set estado = 'enviado', meta_id = 'prueba-0007-w1' where id = e1;
  select estado, texto_final, aprobado_por into r from public.mensajes_borradores where id = b1;
  if r.estado <> 'enviado' or r.texto_final <> 'Hola, cómo estás?' or r.aprobado_por <> 'hola@casazaru.cl' then
    fallo := fallo || ' [1 caducado igual no queda enviado: ' || r.estado || ']';
  end if;

  -- 2) texto distinto al borrador: queda «editado_enviado» con el texto final
  insert into public.mensajes (chat_id, meta_id, direccion, autor, texto, payload, enviado_at)
    values (c, 'prueba-0007-m2', 'entrante', 'cliente', 'y el precio?', '{}'::jsonb, now()) returning id into m2;
  insert into public.mensajes_borradores (chat_id, mensaje_id, texto, modelo) values (c, m2, 'Te lo confirmo hoy.', 'prueba') returning id into b2;
  insert into public.mensajes_envios (clave, chat_id, borrador_id, texto, por)
    values ('prueba-0007-clave-02', c, b2, 'Te lo confirmo mañana temprano.', 'hola@casazaru.cl') returning id into e2;
  update public.mensajes_envios set estado = 'enviado', meta_id = 'prueba-0007-w2' where id = e2;
  select estado, texto_final into r from public.mensajes_borradores where id = b2;
  if r.estado <> 'editado_enviado' or r.texto_final <> 'Te lo confirmo mañana temprano.' then
    fallo := fallo || ' [2 editado no queda editado_enviado: ' || r.estado || ']';
  end if;

  -- 3) un envío que falla NO marca el borrador
  update public.mensajes_borradores set estado = 'pendiente', texto_final = null, aprobado_por = null where id = b2;
  update public.mensajes_envios set estado = 'fallo', error = 'prueba' where id = e2;
  if (select estado from public.mensajes_borradores where id = b2) <> 'pendiente' then fallo := fallo || ' [3 un fallo marco el borrador]'; end if;

  -- 4) el historial guardó la versión anterior del borrador
  if not exists (select 1 from public.mensajes_historial where tabla = 'mensajes_borradores' and fila_id = b1) then
    fallo := fallo || ' [4 falta historial del borrador]';
  end if;

  raise exception 'PRUEBA 0007 TERMINADA (todo se deshace): %',
    case when fallo = '' then 'TODO OK, 4 de 4' else 'FALLOS:' || fallo end;
end
$prueba$;
