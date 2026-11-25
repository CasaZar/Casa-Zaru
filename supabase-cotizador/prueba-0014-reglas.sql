-- ── CANDADO DE PROYECTO (no borrar) ──────────────────────────────────────
-- Este archivo es del COTIZADOR (cmxqorsyxoltrakxawro). Si se pega en el SQL
-- Editor de otro proyecto, falla primero y no se aplica nada.
do $candado$
begin
  if to_regclass('public.gestion_pedidos') is not null then
    raise exception 'PROYECTO EQUIVOCADO: este SQL es del COTIZADOR (cmxqorsyxoltrakxawro) y lo estás corriendo en GESTIÓN. No se aplicó nada.';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '0014') then
    raise exception 'FALTA LA 0014. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- Prueba de la 0014: cuándo toca avisar al equipo.
-- NO DEJA NADA GUARDADO y NO ENVÍA NADA: termina SIEMPRE con un error a propósito, que deshace todo.
-- Las horas son simuladas: lunes 23-11-2026 a las 10:00 de Chile como punto de partida.
do $prueba$
declare
  t0 timestamptz := timestamptz '2026-11-23 10:00:00-03';
  c bigint; m1 bigint; m2 bigint; m3 bigint; b1 bigint; n int; r record; fallo text := '';
begin
  -- 1) horario
  if not public.mensajes_en_horario(timestamptz '2026-11-23 12:00-03')
     or public.mensajes_en_horario(timestamptz '2026-11-23 08:59-03')
     or public.mensajes_en_horario(timestamptz '2026-11-23 17:30-03')
     or not public.mensajes_en_horario(timestamptz '2026-11-28 11:00-03')
     or public.mensajes_en_horario(timestamptz '2026-11-28 14:00-03')
     or public.mensajes_en_horario(timestamptz '2026-11-29 11:00-03') then
    fallo := fallo || ' [1 horario]';
  end if;

  insert into public.mensajes_chats (canal, contacto_id, nombre) values ('whatsapp', 'PRUEBA-0014', 'Prueba Catorce') returning id into c;
  insert into public.mensajes (chat_id, meta_id, direccion, autor, texto, payload, enviado_at)
    values (c, 'prueba-0014-m1', 'entrante', 'cliente', 'hola, necesito una cubierta', '{}'::jsonb, t0) returning id into m1;

  -- 2) recién llegado y sin borrador: todavía no avisa; a los 90 segundos sí
  select count(*) into n from public.mensajes_avisos_por_enviar(t0 + interval '30 seconds') a where a.chat_id = c;
  if n <> 0 then fallo := fallo || ' [2 aviso antes de tiempo]'; end if;
  select count(*) into n from public.mensajes_avisos_por_enviar(t0 + interval '2 minutes') a where a.chat_id = c and a.tipo = 'nuevo' and a.mensaje_id = m1;
  if n <> 1 then fallo := fallo || ' [2 no aviso a los 2 minutos]'; end if;

  -- 3) con borrador agendado para salir solo: no avisa. Desagendado: avisa de inmediato, con nombre de pila
  insert into public.mensajes_borradores (chat_id, mensaje_id, texto, modelo, auto_desde)
    values (c, m1, 'Hola, cómo estás?', 'prueba', t0 + interval '2 minutes') returning id into b1;
  select count(*) into n from public.mensajes_avisos_por_enviar(t0 + interval '5 minutes') a where a.chat_id = c;
  if n <> 0 then fallo := fallo || ' [3 aviso con respuesta automatica agendada]'; end if;
  update public.mensajes_borradores set auto_desde = null where id = b1;
  select * into r from public.mensajes_avisos_por_enviar(t0 + interval '10 seconds') a where a.chat_id = c and a.tipo = 'nuevo';
  if r.mensaje_id is distinct from m1 or r.nombre <> 'Prueba' or r.texto <> 'hola, necesito una cubierta' or not r.en_horario then
    fallo := fallo || ' [3 con borrador no aviso de inmediato o datos malos]';
  end if;

  -- 4) una vez registrado, no se repite; un segundo mensaje del cliente en la misma espera tampoco avisa
  insert into public.mensajes_avisos (tipo, chat_id, mensaje_id) values ('nuevo', c, m1);
  insert into public.mensajes (chat_id, meta_id, direccion, autor, texto, payload, enviado_at)
    values (c, 'prueba-0014-m2', 'entrante', 'cliente', 'es de 200 x 60', '{}'::jsonb, t0 + interval '1 minute') returning id into m2;
  select count(*) into n from public.mensajes_avisos_por_enviar(t0 + interval '10 minutes') a where a.chat_id = c;
  if n <> 0 then fallo := fallo || ' [4 se repitio el aviso]'; end if;
  begin
    insert into public.mensajes_avisos (tipo, chat_id, mensaje_id) values ('nuevo', c, m1);
    fallo := fallo || ' [4 LA BASE ACEPTO EL MISMO AVISO DOS VECES]';
  exception when unique_violation then null; end;

  -- 5) espera: a 1 h 59 no, a 2 h 01 sí (12:01, en horario), con el texto del último mensaje
  select count(*) into n from public.mensajes_avisos_por_enviar(t0 + interval '1 hour 59 minutes') a where a.chat_id = c;
  if n <> 0 then fallo := fallo || ' [5 espera antes de 2 horas]'; end if;
  select * into r from public.mensajes_avisos_por_enviar(t0 + interval '2 hours 1 minute') a where a.chat_id = c;
  if r.tipo is distinct from 'espera' or r.mensaje_id <> m1 or r.texto <> 'es de 200 x 60' then fallo := fallo || ' [5 no aviso la espera]'; end if;
  -- fuera de horario (20:00) no sale; a las 9:00 del día siguiente sí
  select count(*) into n from public.mensajes_avisos_por_enviar(t0 + interval '10 hours') a where a.chat_id = c and a.tipo = 'espera';
  if n <> 0 then fallo := fallo || ' [5 espera fuera de horario]'; end if;
  select count(*) into n from public.mensajes_avisos_por_enviar(t0 + interval '23 hours') a where a.chat_id = c and a.tipo = 'espera';
  if n <> 1 then fallo := fallo || ' [5 espera no salio a las 9:00]'; end if;
  insert into public.mensajes_avisos (tipo, chat_id, mensaje_id) values ('espera', c, m1);

  -- 6) cierra: la ventana se cuenta desde el ÚLTIMO mensaje (10:01). A 20 h 59 no; a 21 h 02 sí; cerrada, nada
  select count(*) into n from public.mensajes_avisos_por_enviar(t0 + interval '20 hours 59 minutes') a where a.chat_id = c;
  if n <> 0 then fallo := fallo || ' [6 cierra antes de tiempo]'; end if;
  select * into r from public.mensajes_avisos_por_enviar(t0 + interval '21 hours 2 minutes') a where a.chat_id = c;
  if r.tipo is distinct from 'cierra' or r.mensaje_id <> m2 or r.cierra_at <> t0 + interval '24 hours 1 minute' then
    fallo := fallo || ' [6 no aviso el cierre]';
  end if;
  select count(*) into n from public.mensajes_avisos_por_enviar(t0 + interval '24 hours 2 minutes') a where a.chat_id = c;
  if n <> 0 then fallo := fallo || ' [6 aviso con la ventana cerrada]'; end if;

  -- 7) una persona responde: no queda nada que avisar. El cliente vuelve a escribir: aviso nuevo, de ESA espera
  insert into public.mensajes (chat_id, meta_id, direccion, autor, texto, payload, enviado_at, enviado_por)
    values (c, 'prueba-0014-p1', 'saliente', 'bandeja', 'Hola, te ayudo.', '{}'::jsonb, t0 + interval '3 hours', 'persona@prueba.cl');
  select count(*) into n from public.mensajes_avisos_por_enviar(t0 + interval '22 hours') a where a.chat_id = c;
  if n <> 0 then fallo := fallo || ' [7 aviso despues de responder]'; end if;
  insert into public.mensajes (chat_id, meta_id, direccion, autor, texto, payload, enviado_at)
    values (c, 'prueba-0014-m3', 'entrante', 'cliente', null, '{}'::jsonb, t0 + interval '4 hours') returning id into m3;
  select * into r from public.mensajes_avisos_por_enviar(t0 + interval '4 hours 2 minutes') a where a.chat_id = c;
  if r.tipo is distinct from 'nuevo' or r.mensaje_id <> m3 or r.texto not like '[%]' then fallo := fallo || ' [7 no aviso la respuesta del cliente]'; end if;

  -- 8) seguridad y forma de las tablas
  if has_table_privilege('anon', 'public.mensajes_push', 'select') or has_table_privilege('authenticated', 'public.mensajes_push', 'select')
     or has_table_privilege('authenticated', 'public.mensajes_push', 'insert') or has_table_privilege('authenticated', 'public.mensajes_avisos', 'insert')
     or has_function_privilege('anon', 'public.mensajes_avisos_por_enviar(timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'public.mensajes_avisos_por_enviar(timestamptz)', 'execute') then
    fallo := fallo || ' [8 PERMISOS DE MAS]';
  end if;
  begin
    insert into public.mensajes_push (usuario, endpoint, p256dh, auth) values ('persona@prueba.cl', 'http://sin-https.example/x', repeat('a', 87), repeat('b', 22));
    fallo := fallo || ' [8 acepto un endpoint sin https]';
  exception when check_violation then null; end;
  insert into public.mensajes_push (usuario, endpoint, p256dh, auth) values ('persona@prueba.cl', 'https://fcm.googleapis.com/prueba-0014', repeat('a', 87), repeat('b', 22));
  begin
    insert into public.mensajes_push (usuario, endpoint, p256dh, auth) values ('otra@prueba.cl', 'https://fcm.googleapis.com/prueba-0014', repeat('a', 87), repeat('b', 22));
    fallo := fallo || ' [8 acepto el mismo dispositivo dos veces]';
  exception when unique_violation then null; end;
  begin
    insert into public.mensajes_avisos (tipo, chat_id) values ('nuevo', c);
    fallo := fallo || ' [8 acepto un aviso sin mensaje]';
  exception when check_violation then null; end;

  raise exception 'PRUEBA 0014 TERMINADA (todo se deshace): %',
    case when fallo = '' then 'TODO OK, 8 de 8' else 'FALLOS:' || fallo end;
end
$prueba$;
