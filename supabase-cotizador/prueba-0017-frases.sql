-- Prueba de la 0017 (frases de la casa). Se corre DESPUÉS de aplicarla, en el SQL Editor del Cotizador.
-- No deja nada: termina siempre con un error a propósito, y Postgres deshace todo lo que hizo.
-- Resultado esperado: «PRUEBA 0017 TODO OK, 6 de 6».
do $prueba$
declare
  ok int := 0;
  v_id bigint;
  v_por text;
begin
  if to_regclass('public.gestion_pedidos') is not null or to_regclass('public.mensajes_frases') is null then
    raise exception 'PROYECTO EQUIVOCADO o falta aplicar la 0017.';
  end if;

  -- 1) una frase fija con signo de apertura se rechaza
  begin
    insert into public.mensajes_frases (tipo, cuando, frase) values ('fija', 'prueba', '¡Hola!');
  exception when check_violation then ok := ok + 1; end;

  -- 2) «nativa» se rechaza en una preferida
  begin
    insert into public.mensajes_frases (tipo, cuando, frase) values ('preferida', 'prueba', 'Es madera nativa del sur.');
  exception when check_violation then ok := ok + 1; end;

  -- 3) «alternativa» sí pasa (no es la palabra nativa)
  insert into public.mensajes_frases (tipo, cuando, frase) values ('preferida', 'prueba', 'Otra alternativa es el coihue.')
  returning id into v_id;
  ok := ok + 1;

  -- 4) una «evitar» puede llevar lo que sea
  insert into public.mensajes_frases (tipo, cuando, frase) values ('evitar', 'prueba', '¡al tiro!');
  ok := ok + 1;

  -- 5) al editar con updated_by, queda quien editó y la versión anterior va al historial
  update public.mensajes_frases set frase = 'Otra alternativa es el raulí.', updated_by = 'prueba@casazaru.cl' where id = v_id
  returning updated_by into v_por;
  if v_por = 'prueba@casazaru.cl'
     and exists (select 1 from public.mensajes_historial where tabla = 'mensajes_frases' and fila_id = v_id
                 and anterior ->> 'frase' = 'Otra alternativa es el coihue.') then
    ok := ok + 1;
  else
    raise notice 'falló el punto 5: updated_by = %', v_por;
  end if;

  -- 6) la clave no se repite
  begin
    insert into public.mensajes_frases (tipo, clave, cuando, frase) values ('fija', 'saludo', 'prueba', 'Hola');
  exception when unique_violation then ok := ok + 1; end;

  if ok = 6 then raise exception 'PRUEBA 0017 TODO OK, 6 de 6 (todo se deshizo)';
  else raise exception 'PRUEBA 0017 FALLÓ: % de 6', ok; end if;
end
$prueba$;
