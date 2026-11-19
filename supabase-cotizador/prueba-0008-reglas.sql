-- ── CANDADO DE PROYECTO (no borrar) ──────────────────────────────────────
-- Este archivo es del COTIZADOR (cmxqorsyxoltrakxawro). Si se pega en el SQL
-- Editor de otro proyecto, falla primero y no se aplica nada.
do $candado$
begin
  if to_regclass('public.gestion_pedidos') is not null then
    raise exception 'PROYECTO EQUIVOCADO: este SQL es del COTIZADOR (cmxqorsyxoltrakxawro) y lo estás corriendo en GESTIÓN. No se aplicó nada.';
  end if;
  if to_regclass('public.mensajes_links') is null then
    raise exception 'FALTA LA 0008 (no existe mensajes_links). No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- Prueba de la 0008: links de cotización del asistente. NO DEJA NADA GUARDADO
-- (ni links ni cotizaciones) y NO ENVÍA NADA: termina SIEMPRE con un error a
-- propósito, que deshace todo.
do $prueba$
declare
  c bigint; l1 bigint; e1 bigint; r record; j jsonb; fallo text := '';
  cod text := 'prueba0008abc';
begin
  insert into public.mensajes_chats (canal, contacto_id, nombre, telefono)
    values ('whatsapp', 'PRUEBA-0008', 'Persona de Prueba', '56900000008') returning id into c;
  insert into public.mensajes (chat_id, meta_id, direccion, autor, texto, payload, enviado_at)
    values (c, 'prueba-0008-m1', 'entrante', 'cliente', 'cuanto sale una cubierta', '{}'::jsonb, now());
  insert into public.mensajes_links (codigo, chat_id, producto, datos, listo)
    values (cod, c, 'cubierta', '{"p":"cubierta","uso":"cocina","rows":[{"lg":240,"an":62,"ca":1}]}'::jsonb, true)
    returning id into l1;

  -- 1) un código mal formado no entra a la tabla
  begin
    insert into public.mensajes_links (codigo, chat_id, producto, datos) values ('CORTO', c, 'cubierta', '{}'::jsonb);
    fallo := fallo || ' [1 acepto un codigo malo]';
  exception when check_violation then null; end;

  -- 2) un producto fuera de la lista no entra
  begin
    insert into public.mensajes_links (codigo, chat_id, producto, datos) values ('prueba0008zzz', c, 'especial', '{}'::jsonb);
    fallo := fallo || ' [2 acepto un producto fuera de lista]';
  exception when check_violation then null; end;

  -- 3) abrir un código que no existe devuelve null y no rompe
  if public.asistente_link_abrir('noexiste00000') is not null then fallo := fallo || ' [3 abrio un codigo inexistente]'; end if;
  if public.asistente_link_abrir('x'' or 1=1 --') is not null then fallo := fallo || ' [3 abrio un codigo con basura]'; end if;

  -- 4) abrir el link: devuelve medidas y nombre, NO el teléfono, y anota la apertura
  j := public.asistente_link_abrir(cod);
  if j is null or j -> 'd' ->> 'p' <> 'cubierta' or (j ->> 'listo')::boolean is not true or j ->> 'n' <> 'Persona de Prueba' then
    fallo := fallo || ' [4 abrir no devolvio los datos: ' || coalesce(j::text, 'null') || ']';
  end if;
  if position('56900000008' in j::text) > 0 then fallo := fallo || ' [4 EL TELEFONO SALIO AL NAVEGADOR]'; end if;
  perform public.asistente_link_abrir(cod);
  select aperturas, abierto_at, enviado_at, cotizo_at into r from public.mensajes_links where id = l1;
  if r.aperturas <> 2 or r.abierto_at is null then fallo := fallo || ' [4 no conto las aperturas: ' || r.aperturas || ']'; end if;
  if r.enviado_at is not null then fallo := fallo || ' [4 quedo enviado sin envio]'; end if;

  -- 5) un envío que lleva el link lo deja «enviado»; uno que falla, no
  insert into public.mensajes_envios (clave, chat_id, texto, por)
    values ('prueba-0008-clave-01', c, 'Acá va: https://www.casazaru.cl/cotizador?prod=cubierta&c=' || cod || '&src=asistente', 'hola@casazaru.cl')
    returning id into e1;
  update public.mensajes_envios set estado = 'fallo', error = 'prueba' where id = e1;
  if (select enviado_at from public.mensajes_links where id = l1) is not null then fallo := fallo || ' [5 un fallo lo marco enviado]'; end if;
  insert into public.mensajes_envios (clave, chat_id, texto, por)
    values ('prueba-0008-clave-02', c, 'Acá va: https://www.casazaru.cl/cotizador?prod=cubierta&c=' || cod || '&src=asistente', 'hola@casazaru.cl')
    returning id into e1;
  update public.mensajes_envios set estado = 'enviado', meta_id = 'prueba-0008-w1' where id = e1;
  if (select enviado_at from public.mensajes_links where id = l1) is null then fallo := fallo || ' [5 el envio no lo marco enviado]'; end if;

  -- 6) la cotización que llega con el código queda amarrada y toma el WhatsApp del chat
  insert into public.cotizaciones (numero, cliente, contacto, producto, total_bajo, total_medio, total_alto, link, origen)
    values ('PRUEBA-0008-1', 'Persona de Prueba', null, 'cubierta', 1, 2, 3, 'https://www.casazaru.cl/cotizador?s=tokPrueba8',
            jsonb_build_object('c', cod, 'prod', 'cubierta'));
  select contacto, origen into r from public.cotizaciones where numero = 'PRUEBA-0008-1';
  if r.contacto is distinct from '+56900000008' then fallo := fallo || ' [6 no tomo el contacto del chat: ' || coalesce(r.contacto, 'null') || ']'; end if;
  if r.origen ->> 'src' <> 'asistente' or (r.origen ->> 'chat')::bigint <> c then fallo := fallo || ' [6 origen sin asistente/chat]'; end if;
  select cotizaciones, cotizacion_numero, cotizo_at into r from public.mensajes_links where id = l1;
  if r.cotizaciones <> 1 or r.cotizacion_numero <> 'PRUEBA-0008-1' or r.cotizo_at is null then fallo := fallo || ' [6 el link no quedo con su cotizacion]'; end if;
  j := public.asistente_link_abrir(cod);
  if j ->> 's' is distinct from 'tokPrueba8' then fallo := fallo || ' [6 reabrir no devuelve la cotizacion ya hecha]'; end if;

  -- 7) un contacto que el cliente sí escribió NO se pisa; la segunda cotización cuenta pero no cambia la primera
  insert into public.cotizaciones (numero, cliente, contacto, producto, total_bajo, total_medio, total_alto, origen)
    values ('PRUEBA-0008-2', 'Persona de Prueba', '+56 9 1111 2222', 'cubierta', 1, 2, 3, jsonb_build_object('c', cod));
  if (select contacto from public.cotizaciones where numero = 'PRUEBA-0008-2') <> '+56 9 1111 2222' then fallo := fallo || ' [7 piso el contacto escrito]'; end if;
  select cotizaciones, cotizacion_numero into r from public.mensajes_links where id = l1;
  if r.cotizaciones <> 2 or r.cotizacion_numero <> 'PRUEBA-0008-1' then fallo := fallo || ' [7 conteo o primera cotizacion mal]'; end if;

  -- 8) una cotización con un código desconocido, o sin código, se guarda igual y sin cambios
  insert into public.cotizaciones (numero, cliente, contacto, producto, total_bajo, total_medio, total_alto, origen)
    values ('PRUEBA-0008-3', 'Otra', null, 'cubierta', 1, 2, 3, jsonb_build_object('c', 'codigoquenoexiste', 'src', 'web'));
  select contacto, origen into r from public.cotizaciones where numero = 'PRUEBA-0008-3';
  if r.contacto is not null or r.origen ->> 'src' <> 'web' then fallo := fallo || ' [8 toco una cotizacion ajena]'; end if;
  insert into public.cotizaciones (numero, cliente, contacto, producto, total_bajo, total_medio, total_alto)
    values ('PRUEBA-0008-4', 'Otra', '+56 9 3333 4444', 'cubierta', 1, 2, 3);
  if not exists (select 1 from public.cotizaciones where numero = 'PRUEBA-0008-4') then fallo := fallo || ' [8 no guardo una cotizacion normal]'; end if;

  -- 9) el historial guardó la versión anterior del link
  if not exists (select 1 from public.mensajes_historial where tabla = 'mensajes_links' and fila_id = l1) then
    fallo := fallo || ' [9 falta historial del link]';
  end if;

  raise exception 'PRUEBA 0008 TERMINADA (todo se deshace): %',
    case when fallo = '' then 'TODO OK, 9 de 9' else 'FALLOS:' || fallo end;
end
$prueba$;
