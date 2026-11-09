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

-- ══════════════════════════════════════════════════════════════════════════
-- Fototeca dentro del panel · Cotizador (09-11-2026)
--
-- El buscador de fotos y videos (cotizador.casazaru.cl/fototeca.html) lee sus
-- miniaturas (s00.jpg … s21.jpg) y su índice (datos.json) de un bucket
-- PRIVADO. El repo del cotizador es público: esos archivos nunca van ahí.
--
-- · Bucket «fototeca», privado: sin sesión no se ve nada.
-- · Lee solo el equipo con sesión iniciada (admin y César). Para sumar a
--   alguien (la persona de contenido, por ejemplo), agregar su correo a la
--   lista y volver a correr este archivo.
-- · Nadie escribe desde el navegador: los archivos se suben desde el panel de
--   Supabase (Storage → fototeca), que usa la llave de servicio.
-- Idempotente. Rollback al final.
-- ══════════════════════════════════════════════════════════════════════════

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('fototeca', 'fototeca', false, 5242880, array['image/jpeg', 'application/json'])
on conflict (id) do update set
  public             = false,
  file_size_limit    = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "equipo lee fototeca" on storage.objects;
create policy "equipo lee fototeca" on storage.objects
  for select to authenticated using (
    bucket_id = 'fototeca'
    and auth.email() in ('hola@casazaru.cl', 'crodriguez.casazaru@gmail.com')
  );

-- ── Verificación (debe dar el bucket privado y 1 política) ──
select id, public, file_size_limit from storage.buckets where id = 'fototeca';
select policyname, cmd, roles from pg_policies
 where schemaname = 'storage' and tablename = 'objects' and policyname = 'equipo lee fototeca';

-- ══ ROLLBACK (no correr salvo que se quiera deshacer todo) ══
-- drop policy if exists "equipo lee fototeca" on storage.objects;
-- Vaciar el bucket desde Storage → fototeca y después:
-- delete from storage.buckets where id = 'fototeca';
