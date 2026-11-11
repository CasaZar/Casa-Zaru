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
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- Baja de Jepe + visita de prueba del embudo · Cotizador (11-11-2026)
--
-- Pedido del usuario el 11-11 («elimina a jepe», «pon el sql tú y córrelo»).
--   1) Jepe ya no trabaja aquí (cuenta Auth bloqueada el 03-11). Ya no estaba en
--      la tabla vendedores, pero las políticas «equipo lee cotizaciones» y
--      «equipo edita cotizaciones» todavía le daban leer y editar sus propias
--      cotizaciones (user_email = su correo). Se recrean iguales, SIN su cláusula.
--      Sus 64 cotizaciones antiguas NO se tocan: el admin y María José las siguen
--      viendo. En el panel queda de baja (VENDEDORES[].baja, repo Cotizador).
--   2) Se borra la fila 6280 de embudo_eventos: una «visita» que registró Claude
--      el 11-11 a las 11:36 UTC al abrir el cotizador en localhost, antes de que
--      embudoTick() dejara de contar en local (EMBUDO_LOCAL). Respaldo de la fila
--      en el rollback. Es la única fila de esa sesión.
-- Idempotente: se puede correr dos veces.
-- APLICADO el 11-11-2026 en cmxqorsyxoltrakxawro (SQL Editor). Verificado: 0 políticas
-- con el correo de Jepe, las de César intactas, fila 6280 ya no existe.
-- ══════════════════════════════════════════════════════════════════════════

-- 1) políticas de cotizaciones sin Jepe
drop policy if exists "equipo lee cotizaciones" on public.cotizaciones;
create policy "equipo lee cotizaciones" on public.cotizaciones
  for select to authenticated
  using (
    auth.email() = 'hola@casazaru.cl'
    or asignado_a = auth.email()
    or (auth.email() = 'crodriguez.casazaru@gmail.com'
        and (user_email = 'crodriguez.casazaru@gmail.com'
             or user_email = 'hola@casazaru.cl'
             or (user_email is null and asignado_a is null)))
  );

drop policy if exists "equipo edita cotizaciones" on public.cotizaciones;
create policy "equipo edita cotizaciones" on public.cotizaciones
  for update to authenticated
  using (
    auth.email() = 'hola@casazaru.cl'
    or asignado_a = auth.email()
    or (auth.email() = 'crodriguez.casazaru@gmail.com'
        and (user_email = 'crodriguez.casazaru@gmail.com'
             or user_email = 'hola@casazaru.cl'
             or (user_email is null and asignado_a is null)))
  )
  with check (
    auth.email() = 'hola@casazaru.cl'
    or asignado_a = auth.email()
    or (auth.email() = 'crodriguez.casazaru@gmail.com'
        and (user_email = 'crodriguez.casazaru@gmail.com'
             or user_email = 'hola@casazaru.cl'
             or (user_email is null and asignado_a is null)))
  );

-- 2) la visita de prueba (amarrada a id + sesión + paso: no puede borrar otra cosa)
delete from public.embudo_eventos
 where id = 6280 and sesion = '3gz1xmhfmwc1mnxj' and paso = 'visita';

-- verificación: 0 políticas con Jepe y 0 filas de esa sesión
select (select count(*) from pg_policies
         where qual ilike '%jeperomanosorio%' or with_check ilike '%jeperomanosorio%') as politicas_con_jepe,
       (select count(*) from public.embudo_eventos where sesion = '3gz1xmhfmwc1mnxj') as visitas_de_prueba;

-- ── ROLLBACK ─────────────────────────────────────────────────────────────
-- 1) devolverle el acceso a Jepe: recrear las dos políticas agregando al final de
--    using (y del with check en la de update):
--      or (auth.email() = 'jeperomanosorio@gmail.com' and user_email = 'jeperomanosorio@gmail.com')
-- 2) la fila borrada, tal cual estaba:
--    insert into public.embudo_eventos (id, creado, sesion, paso, producto, canal)
--    values (6280, '2026-11-11T11:36:16.40417+00:00', '3gz1xmhfmwc1mnxj', 'visita', null, 'web');
