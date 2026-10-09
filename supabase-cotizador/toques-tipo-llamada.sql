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
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════
-- TOQUE POR LLAMADA (09-10-2026)
--
-- La tabla `toques` guarda cada seguimiento y quién lo hizo, pero su check
-- solo acepta p1, p2, p3, p4, cadencia y agendado. Una llamada no se podía
-- registrar como toque, y en las ventas grandes la llamada temprana aparece
-- una y otra vez (el cruce del 07-10 lo vio en 3 de 14 ventas leídas: "¿Te
-- puedo llamar?" en los primeros mensajes). Sin registro no se puede medir.
--
-- Este script solo AGREGA 'llamada' a los tipos permitidos. No toca filas.
-- Busca el check por su definición (no por nombre) para no depender de cómo
-- se llamó al crearlo, y falla si hay algún tipo que no conoce: así no se
-- borra un check que cuidaba otra cosa.
-- Después de aplicarlo, el panel necesita su botón "Llamé" (va aparte, en
-- C:\Users\dell\Cotizador). Mientras el botón no exista, esto no cambia nada.
-- ══════════════════════════════════════════════════════════════════

do $llamada$
declare
  c record;
  n int := 0;
  raros text;
begin
  -- 1) que no haya tipos fuera de la lista conocida (si los hay, algo cambió: no seguir)
  select string_agg(distinct tipo, ', ') into raros
    from toques
   where tipo not in ('p1','p2','p3','p4','cadencia','agendado');
  if raros is not null then
    raise exception 'La tabla toques tiene tipos que este script no conoce (%). No se aplicó nada.', raros;
  end if;

  -- 2) borrar el/los check sobre la columna tipo
  for c in
    select con.conname
      from pg_constraint con
      join pg_class rel on rel.oid = con.conrelid
      join pg_namespace ns on ns.oid = rel.relnamespace
     where ns.nspname = 'public' and rel.relname = 'toques' and con.contype = 'c'
       and pg_get_constraintdef(con.oid) ilike '%tipo%'
  loop
    execute format('alter table public.toques drop constraint %I', c.conname);
    n := n + 1;
  end loop;
  if n <> 1 then
    raise exception 'Se esperaba 1 check sobre toques.tipo y hubo %. No se aplicó nada.', n;
  end if;

  -- 3) el check nuevo, con 'llamada'
  alter table public.toques add constraint toques_tipo_check
    check (tipo in ('p1','p2','p3','p4','cadencia','agendado','llamada'));
end
$llamada$;

-- Resultado: debería mostrar el check con 'llamada' incluido.
select conname, pg_get_constraintdef(oid) as definicion
  from pg_constraint
 where conrelid = 'public.toques'::regclass and contype = 'c';
