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
-- Fototeca para la persona de contenido · Cotizador (09-11-2026)
--
-- 1) Cierra un hueco: varias tablas del panel dejaban leer (y algunas borrar) a
--    CUALQUIER cuenta con sesión: toques, cotizacion_lineas, embudo_eventos,
--    config_seguimiento, vendedores. Mientras las únicas cuentas eran el equipo
--    no importaba; con una cuenta que solo debe ver la Fototeca, sí.
--    Se agregan políticas RESTRICTIVAS («solo equipo del panel»): se suman con
--    AND a las que ya existen, sin tocarlas. El equipo = admin + vendedores
--    activos (tabla vendedores). Los insert públicos (anon) no cambian.
-- 2) Suma Emerge.smm@gmail.com (contenido) a quienes leen el bucket «fototeca».
-- Idempotente. Rollback al final.
-- ══════════════════════════════════════════════════════════════════════════

create or replace function public.es_equipo_panel() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(auth.email(), '') = 'hola@casazaru.cl'
      or exists (select 1 from public.vendedores v where v.email = auth.email() and v.activo);
$$;
revoke all on function public.es_equipo_panel() from public, anon;
grant execute on function public.es_equipo_panel() to authenticated;

-- toques: todo el panel
drop policy if exists "solo equipo del panel" on public.toques;
create policy "solo equipo del panel" on public.toques
  as restrictive for all to authenticated using (public.es_equipo_panel()) with check (public.es_equipo_panel());

-- cotizacion_lineas: leer, editar, borrar (el insert lo hace guardar_lineas o el público)
drop policy if exists "solo equipo lee lineas" on public.cotizacion_lineas;
create policy "solo equipo lee lineas" on public.cotizacion_lineas
  as restrictive for select to authenticated using (public.es_equipo_panel());
drop policy if exists "solo equipo edita lineas" on public.cotizacion_lineas;
create policy "solo equipo edita lineas" on public.cotizacion_lineas
  as restrictive for update to authenticated using (public.es_equipo_panel()) with check (public.es_equipo_panel());
drop policy if exists "solo equipo borra lineas" on public.cotizacion_lineas;
create policy "solo equipo borra lineas" on public.cotizacion_lineas
  as restrictive for delete to authenticated using (public.es_equipo_panel());

-- lecturas del panel
drop policy if exists "solo equipo lee embudo" on public.embudo_eventos;
create policy "solo equipo lee embudo" on public.embudo_eventos
  as restrictive for select to authenticated using (public.es_equipo_panel());
drop policy if exists "solo equipo lee config" on public.config_seguimiento;
create policy "solo equipo lee config" on public.config_seguimiento
  as restrictive for select to authenticated using (public.es_equipo_panel());
drop policy if exists "solo equipo lee vendedores" on public.vendedores;
create policy "solo equipo lee vendedores" on public.vendedores
  as restrictive for select to authenticated using (public.es_equipo_panel());

-- Fototeca: equipo + contenido
drop policy if exists "equipo lee fototeca" on storage.objects;
create policy "equipo lee fototeca" on storage.objects
  for select to authenticated using (
    bucket_id = 'fototeca'
    and lower(auth.email()) in ('hola@casazaru.cl', 'crodriguez.casazaru@gmail.com', 'emerge.smm@gmail.com')
  );

-- ── Verificación ──
select tablename, policyname, permissive, cmd from pg_policies
 where policyname like 'solo equipo%' or policyname = 'equipo lee fototeca' order by 1, 2;

-- ══ ROLLBACK ══
-- drop policy if exists "solo equipo del panel" on public.toques;
-- drop policy if exists "solo equipo lee lineas" on public.cotizacion_lineas;
-- drop policy if exists "solo equipo edita lineas" on public.cotizacion_lineas;
-- drop policy if exists "solo equipo borra lineas" on public.cotizacion_lineas;
-- drop policy if exists "solo equipo lee embudo" on public.embudo_eventos;
-- drop policy if exists "solo equipo lee config" on public.config_seguimiento;
-- drop policy if exists "solo equipo lee vendedores" on public.vendedores;
-- drop function if exists public.es_equipo_panel();
-- y volver a correr fototeca-bucket.sql (deja la Fototeca solo para admin y César)
