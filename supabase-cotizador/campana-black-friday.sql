-- ── CANDADO DE PROYECTO (no borrar) ──────────────────────────────────────
-- Este archivo es del COTIZADOR (cmxqorsyxoltrakxawro). Pegar DESPUÉS de la 0019.
do $candado$
begin
  if to_regclass('public.gestion_pedidos') is not null then
    raise exception 'PROYECTO EQUIVOCADO: este SQL es del COTIZADOR y lo estás corriendo en GESTIÓN. No se aplicó nada.';
  end if;
  if to_regclass('public.campanas') is null then
    raise exception 'PROYECTO EQUIVOCADO: aquí no existe la tabla campanas. No se aplicó nada.';
  end if;
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '0019') then
    raise exception 'FALTA LA 0019: aplicar antes 0019_campanas_varias_activas.sql. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- Campaña Black Friday (27-11-2026). Queda como BORRADOR: se revisa y se
-- activa en el panel (pestaña Campañas → Ver → Activar). Solo inserta una
-- fila; si ya existe la nota, no hace nada.
--   A quién: cotizaron en noviembre cualquier producto menos peldaños;
--   abiertas desde $500.000 (opción media) y cerradas desde $1.000.000;
--   sin los que compraron, compraron en otro lado o desistieron; sin nadie
--   que haya cotizado peldaños ni esté en esas campañas; los de 2 mensajes
--   sin respuesta salen aparte para evaluar.
insert into public.campanas (nombre, nota, estado, desde, hasta, producto, filtros, mensaje, oferta, instruccion)
select
  'Black Friday · 10 % con transferencia',
  'Campaña Black Friday',
  'borrador',
  date '2026-11-27',
  date '2026-11-30',
  'varios',
  jsonb_build_object(
    'productos',          jsonb_build_array('cubierta','repisa','granero','maciza','vidrios','revestimiento','mesa','revlibre','banca','pcocina','especial'),
    'cotizo_desde',       '2026-11-01',
    'monto_min',          500000,
    'monto_min_cerradas', 1000000,
    'incluir_cerradas',   true,
    'sacar_compraron',    true,
    'sacar_otro_lado',    true,
    'sacar_desistio',     true,
    'solo_antes_de',      '',
    'sacar_si_cotizo',    jsonb_build_array('peldano'),
    'excluir_notas',      jsonb_build_array('Campaña peldaños','Campaña peldaños · ronda 2'),
    'mostrar_tope',       true
  ),
  E'{saludo}, cómo estás?{soy}\n\n{hace} cotizaste {con_nosotros} y quería contarte que por Black Friday tenemos un 10% de descuento pagando por transferencia, hasta el lunes 30 de noviembre.\n\nSi el proyecto sigue en pie, coméntame y te actualizo la cotización con el descuento.\n\nSaludos.',
  '10 % pagando por transferencia, hasta el lunes 30-11',
  'Si contesta, recotiza con «＋ Nueva cotización» y en Descuento especial elige «10 % con transf.»: 5 % con tarjeta y 10 % justo pagando por transferencia. No uses el «10 %» (con transferencia daría 14,5 %).'
where not exists (select 1 from public.campanas where nota = 'Campaña Black Friday');

-- Verificación: debe salir la fila en borrador.
select id, nombre, estado, desde, hasta, producto from public.campanas where nota = 'Campaña Black Friday';

-- Para deshacer (solo si sigue en borrador y nadie fue escrito con la nota):
--   update public.campanas set deleted_at = now() where nota = 'Campaña Black Friday' and estado = 'borrador';
