-- ── CANDADO DE PROYECTO (no borrar) ──────────────────────────────────────
-- Este archivo es del COTIZADOR (cmxqorsyxoltrakxawro). Si se pega en el SQL
-- Editor de otro proyecto, falla primero y no se aplica nada.
do $candado$
begin
  if to_regclass('public.gestion_pedidos') is not null then
    raise exception 'PROYECTO EQUIVOCADO: este SQL es del COTIZADOR (cmxqorsyxoltrakxawro) y lo estás corriendo en GESTIÓN. No se aplicó nada.';
  end if;
  if to_regclass('public.mensajes_envios') is null then
    raise exception 'FALTA LA 0006 (no existe mensajes_envios). No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- Prueba de las reglas de envío de la 0006. NO DEJA NADA GUARDADO y NO ENVÍA NADA:
-- solo inserta reservas de mentira en la base y termina SIEMPRE con un error a
-- propósito («PRUEBA 0006 TERMINADA … TODO OK»), que deshace todo.
do $prueba$
declare
  c bigint; c2 bigint; c3 bigint; e1 bigint; fallo text := '';
begin
  insert into public.mensajes_chats (canal, contacto_id, nombre) values ('whatsapp', 'PRUEBA-0006-A', 'Prueba A') returning id into c;

  -- 1) el cliente todavía no escribe: ventana cerrada
  begin
    insert into public.mensajes_envios (clave, chat_id, texto, por) values ('prueba-0006-clave-01', c, 'Hola', 'hola@casazaru.cl');
    fallo := fallo || ' [1 sin ventana PASO]';
  exception when others then
    if sqlerrm not like 'ENVIO RECHAZADO: la ventana%' then fallo := fallo || ' [1 otro error: ' || sqlerrm || ']'; end if;
  end;

  insert into public.mensajes (chat_id, meta_id, direccion, autor, texto, payload, enviado_at)
    values (c, 'prueba-0006-m1', 'entrante', 'cliente', 'hola', '{}'::jsonb, now());

  -- 2) envío válido: pasa
  begin
    insert into public.mensajes_envios (clave, chat_id, texto, por) values ('prueba-0006-clave-02', c, 'Hola, cómo estás?', 'hola@casazaru.cl') returning id into e1;
  exception when others then fallo := fallo || ' [2 valido rechazado: ' || sqlerrm || ']';
  end;

  -- 3) la misma clave no entra dos veces (doble clic / reintento)
  begin
    insert into public.mensajes_envios (clave, chat_id, texto, por) values ('prueba-0006-clave-02', c, 'Hola, cómo estás?', 'hola@casazaru.cl');
    fallo := fallo || ' [3 clave repetida PASO]';
  exception when unique_violation then null;
    when others then fallo := fallo || ' [3 otro error: ' || sqlerrm || ']';
  end;

  -- 4) precio sin completar
  begin
    insert into public.mensajes_envios (clave, chat_id, texto, por) values ('prueba-0006-clave-04', c, 'Queda en [PRECIO: peldaño 90]', 'hola@casazaru.cl');
    fallo := fallo || ' [4 PRECIO PASO]';
  exception when others then
    if sqlerrm not like 'ENVIO RECHAZADO: falta completar un precio%' then fallo := fallo || ' [4 otro error: ' || sqlerrm || ']'; end if;
  end;

  -- 5) «nativa»
  begin
    insert into public.mensajes_envios (clave, chat_id, texto, por) values ('prueba-0006-clave-05', c, 'Es madera Nativa del sur', 'hola@casazaru.cl');
    fallo := fallo || ' [5 nativa PASO]';
  exception when others then
    if sqlerrm not like 'ENVIO RECHAZADO: el texto dice «nativa»%' then fallo := fallo || ' [5 otro error: ' || sqlerrm || ']'; end if;
  end;

  -- 6) «al tiro»
  begin
    insert into public.mensajes_envios (clave, chat_id, texto, por) values ('prueba-0006-clave-06', c, 'Te respondo al tiro', 'hola@casazaru.cl');
    fallo := fallo || ' [6 al tiro PASO]';
  exception when others then
    if sqlerrm not like 'ENVIO RECHAZADO: el texto dice «al tiro»%' then fallo := fallo || ' [6 otro error: ' || sqlerrm || ']'; end if;
  end;

  -- 7) signo de apertura
  begin
    insert into public.mensajes_envios (clave, chat_id, texto, por) values ('prueba-0006-clave-07', c, '¿Cómo estás?', 'hola@casazaru.cl');
    fallo := fallo || ' [7 signo de apertura PASO]';
  exception when others then
    if sqlerrm not like 'ENVIO RECHAZADO: el texto usa signos de apertura%' then fallo := fallo || ' [7 otro error: ' || sqlerrm || ']'; end if;
  end;

  -- 8) «alternativa» NO es «nativa»: pasa (y es la segunda reserva en curso)
  begin
    insert into public.mensajes_envios (clave, chat_id, texto, por) values ('prueba-0006-clave-08', c, 'Otra alternativa es el castaño.', 'hola@casazaru.cl');
  exception when others then fallo := fallo || ' [8 alternativa rechazada: ' || sqlerrm || ']';
  end;

  -- 9) tope: con dos saliendo, la tercera no entra
  begin
    insert into public.mensajes_envios (clave, chat_id, texto, por) values ('prueba-0006-clave-09', c, 'Sigues interesado?', 'hola@casazaru.cl');
    fallo := fallo || ' [9 tercer toque PASO]';
  exception when others then
    if sqlerrm not like 'ENVIO RECHAZADO: ya van 2 mensajes%' then fallo := fallo || ' [9 otro error: ' || sqlerrm || ']'; end if;
  end;

  -- 10) chat tomado por otra persona: no entra un tercero, sí el dueño y sí quien lo tomó
  insert into public.mensajes_chats (canal, contacto_id) values ('whatsapp', 'PRUEBA-0006-B') returning id into c2;
  insert into public.mensajes (chat_id, meta_id, direccion, autor, texto, payload, enviado_at)
    values (c2, 'prueba-0006-m2', 'entrante', 'cliente', 'hola', '{}'::jsonb, now());
  update public.mensajes_chats set estado = 'de_cesar', tomado_por = 'vendedor@prueba.cl', tomado_at = now() where id = c2;
  begin
    insert into public.mensajes_envios (clave, chat_id, texto, por) values ('prueba-0006-clave-10', c2, 'Hola', 'otro@prueba.cl');
    fallo := fallo || ' [10 tercero en chat tomado PASO]';
  exception when others then
    if sqlerrm not like 'ENVIO RECHAZADO: este chat lo lleva otra persona%' then fallo := fallo || ' [10 otro error: ' || sqlerrm || ']'; end if;
  end;
  begin
    insert into public.mensajes_envios (clave, chat_id, texto, por) values ('prueba-0006-clave-11', c2, 'Hola', 'hola@casazaru.cl');
    insert into public.mensajes_envios (clave, chat_id, texto, por) values ('prueba-0006-clave-12', c2, 'Hola', 'vendedor@prueba.cl');
  exception when others then fallo := fallo || ' [10 dueño o tomador rechazado: ' || sqlerrm || ']';
  end;

  -- 11) Instagram todavía no
  insert into public.mensajes_chats (canal, contacto_id) values ('instagram', 'PRUEBA-0006-C') returning id into c3;
  insert into public.mensajes (chat_id, meta_id, direccion, autor, texto, payload, enviado_at)
    values (c3, 'prueba-0006-m3', 'entrante', 'cliente', 'hola', '{}'::jsonb, now());
  begin
    insert into public.mensajes_envios (clave, chat_id, texto, por) values ('prueba-0006-clave-13', c3, 'Hola', 'hola@casazaru.cl');
    fallo := fallo || ' [11 instagram PASO]';
  exception when others then
    if sqlerrm not like 'ENVIO RECHAZADO: por ahora solo se puede enviar por WhatsApp%' then fallo := fallo || ' [11 otro error: ' || sqlerrm || ']'; end if;
  end;

  -- 12) nadie queda como «enviado» sin el id de Meta
  begin
    update public.mensajes_envios set estado = 'enviado' where id = e1;
    fallo := fallo || ' [12 enviado sin id PASO]';
  exception when check_violation then null;
  end;

  -- 13) el cambio de estado deja historial
  update public.mensajes_envios set estado = 'fallo', error = 'prueba' where id = e1;
  if not exists (select 1 from public.mensajes_historial where tabla = 'mensajes_envios' and fila_id = e1) then
    fallo := fallo || ' [13 falta historial del envio]';
  end if;

  raise exception 'PRUEBA 0006 TERMINADA (todo se deshace): %',
    case when fallo = '' then 'TODO OK, 13 de 13' else 'FALLOS:' || fallo end;
end
$prueba$;
