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
-- María José (marketing) en el panel + bucket «marketing» · Cotizador (11-11-2026)
--
-- Pedido del usuario el 11-11: María José ve TODO el cotizador (lo mismo que
-- el admin), más la pestaña Marketing y la Fototeca. No es vendedora: no tiene
-- cartera propia ni entra al reparto de clientes web.
--   1) es_equipo_panel() la incluye (toques, líneas, embudo, config, vendedores).
--   2) cotizaciones: lee y edita todas, igual que el admin (política aparte,
--      no se tocan las de admin/César/Jepe).
--   3) WhatsApp al día: lee las filas y el historial y puede marcar respondido.
--      wa_historial y wa_marcar se reescriben cambiando SOLO la lista de correos.
--   4) Fototeca: lee el bucket y las ediciones (editar sigue siendo solo admin).
--   5) Bucket privado «marketing»: marketing.json lo leen admin y María José;
--      lo sube solo el admin (la revisión de WhatsApp de los lunes).
-- Lo que NO hace: cotizador_valores (Manual) y config_seguimiento siguen
-- editándose solo con la cuenta admin. La cuenta de Auth la crea el usuario.
-- Idempotente. Rollback al final.
-- ══════════════════════════════════════════════════════════════════════════

-- 1) equipo del panel
create or replace function public.es_equipo_panel() returns boolean
language sql stable security definer set search_path = public as $$
  select lower(coalesce(auth.email(), '')) in ('hola@casazaru.cl', 'mariajose.mgrunen@gmail.com')
      or exists (select 1 from public.vendedores v where v.email = auth.email() and v.activo);
$$;
revoke all on function public.es_equipo_panel() from public, anon;
grant execute on function public.es_equipo_panel() to authenticated;

-- 2) cotizaciones
drop policy if exists "marketing lee cotizaciones" on public.cotizaciones;
create policy "marketing lee cotizaciones" on public.cotizaciones
  for select to authenticated using (lower(auth.email()) = 'mariajose.mgrunen@gmail.com');
drop policy if exists "marketing edita cotizaciones" on public.cotizaciones;
create policy "marketing edita cotizaciones" on public.cotizaciones
  for update to authenticated
  using (lower(auth.email()) = 'mariajose.mgrunen@gmail.com')
  with check (lower(auth.email()) = 'mariajose.mgrunen@gmail.com');

-- 3) WhatsApp al día
drop policy if exists "marketing lee pendientes" on public.whatsapp_pendientes;
create policy "marketing lee pendientes" on public.whatsapp_pendientes
  for select to authenticated using (lower(auth.email()) = 'mariajose.mgrunen@gmail.com' and deleted_at is null);
drop policy if exists "marketing lee revisiones" on public.whatsapp_revisiones;
create policy "marketing lee revisiones" on public.whatsapp_revisiones
  for select to authenticated using (lower(auth.email()) = 'mariajose.mgrunen@gmail.com');

do $wa$
declare f text; nueva text;
  vieja_lista constant text := $l$not in ('hola@casazaru.cl', 'crodriguez.casazaru@gmail.com')$l$;
  nueva_lista constant text := $l$not in ('hola@casazaru.cl', 'crodriguez.casazaru@gmail.com', 'mariajose.mgrunen@gmail.com')$l$;
begin
  foreach f in array array['public.wa_historial(integer)', 'public.wa_marcar(uuid, text)'] loop
    nueva := pg_get_functiondef(f::regprocedure);
    if position(nueva_lista in nueva) > 0 then
      raise notice '% ya la incluye', f;
    elsif position(vieja_lista in nueva) = 0 then
      raise exception '% no tiene la lista de correos esperada: revisar a mano', f;
    else
      execute replace(nueva, vieja_lista, nueva_lista);
      raise notice '% actualizada', f;
    end if;
  end loop;
end
$wa$;

-- 4) Fototeca
drop policy if exists "marketing lee fototeca" on storage.objects;
create policy "marketing lee fototeca" on storage.objects
  for select to authenticated using (bucket_id = 'fototeca' and lower(auth.email()) = 'mariajose.mgrunen@gmail.com');
drop policy if exists "marketing lee ediciones fototeca" on public.fototeca_ediciones;
create policy "marketing lee ediciones fototeca" on public.fototeca_ediciones
  for select to authenticated using (lower(auth.email()) = 'mariajose.mgrunen@gmail.com');

-- 5) bucket «marketing» (privado)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('marketing', 'marketing', false, 2097152, array['application/json'])
on conflict (id) do update set public = false;

drop policy if exists "marketing lee bucket marketing" on storage.objects;
create policy "marketing lee bucket marketing" on storage.objects
  for select to authenticated using (
    bucket_id = 'marketing' and lower(auth.email()) in ('hola@casazaru.cl', 'mariajose.mgrunen@gmail.com'));
drop policy if exists "admin sube bucket marketing" on storage.objects;
create policy "admin sube bucket marketing" on storage.objects
  for insert to authenticated with check (bucket_id = 'marketing' and lower(auth.email()) = 'hola@casazaru.cl');
drop policy if exists "admin reemplaza bucket marketing" on storage.objects;
create policy "admin reemplaza bucket marketing" on storage.objects
  for update to authenticated
  using (bucket_id = 'marketing' and lower(auth.email()) = 'hola@casazaru.cl')
  with check (bucket_id = 'marketing' and lower(auth.email()) = 'hola@casazaru.cl');

-- ── Verificación ──
select tablename, policyname, cmd from pg_policies
 where policyname like 'marketing %' or policyname like 'admin % bucket marketing' order by 1, 2;

-- ══ ROLLBACK ══
-- drop policy if exists "marketing lee cotizaciones" on public.cotizaciones;
-- drop policy if exists "marketing edita cotizaciones" on public.cotizaciones;
-- drop policy if exists "marketing lee pendientes" on public.whatsapp_pendientes;
-- drop policy if exists "marketing lee revisiones" on public.whatsapp_revisiones;
-- drop policy if exists "marketing lee fototeca" on storage.objects;
-- drop policy if exists "marketing lee ediciones fototeca" on public.fototeca_ediciones;
-- drop policy if exists "marketing lee bucket marketing" on storage.objects;
-- drop policy if exists "admin sube bucket marketing" on storage.objects;
-- drop policy if exists "admin reemplaza bucket marketing" on storage.objects;
-- (el bucket «marketing» se puede dejar; borrarlo exige vaciarlo antes)
-- es_equipo_panel(): volver a correr la definición de fototeca-acceso-contenido.sql.
-- wa_historial / wa_marcar: el mismo bloque $wa$ con las dos listas invertidas.
