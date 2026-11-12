-- ── CANDADO DE PROYECTO (no borrar) ──────────────────────────────────────
-- Este archivo es de GESTIÓN (padnttpgzuotxeipjrry). Si se pega en el SQL
-- Editor de otro proyecto, este bloque falla primero y Postgres descarta el
-- resto del script: no se aplica nada.
do $candado$
begin
  if to_regclass('public.gestion_pedidos') is null then
    raise exception 'PROYECTO EQUIVOCADO: este SQL es de GESTIÓN (padnttpgzuotxeipjrry) y aquí no existe gestion_pedidos. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- 0031 · «Mi día» solo para el dueño (12-11-2026)
--
-- Pedido del usuario: Mi día (deudas, plata, mensajes para el equipo y, desde
-- ahora, la revisión de WhatsApp con «10 minutos con César») lo ve SOLO su
-- cuenta personal. La cuenta hola@ sigue siendo admin de todo lo demás, pero
-- se usa en el Chrome de la oficina, que también ocupa César.
--
--   gestion_usuarios.dueno   marca la(s) cuenta(s) dueña(s). Solo cuenta si
--                            además el rol es admin. Nadie la puede cambiar
--                            desde la app: gestion_usuarios no tiene política
--                            de escritura (solo «leer_mi_usuario»).
--   es_dueno()               lo que usan las políticas de cerebro_*.
--
-- El correo de la cuenta dueña NO va en este archivo (el repo es público): se
-- marca aparte, en el SQL Editor, con
--   insert into public.gestion_usuarios (email, rol, nombre, dueno) values ('<correo>', 'admin', 'Dueño', true)
--   on conflict (email) do update set rol = 'admin', dueno = true;
-- Idempotente.
-- ══════════════════════════════════════════════════════════════════════════

alter table public.gestion_usuarios add column if not exists dueno boolean not null default false;
comment on column public.gestion_usuarios.dueno is 'Cuenta dueña: la única que ve «Mi día» (0031). Solo vale con rol admin.';

create or replace function public.es_dueno()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from gestion_usuarios u
     where lower(u.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
       and u.rol = 'admin' and u.dueno
  )
$$;
revoke all on function public.es_dueno() from public, anon;
grant execute on function public.es_dueno() to authenticated;

-- Las políticas de la 0030 pasan de «admin» a «dueño».
drop policy if exists cerebro_dias_leer on public.cerebro_dias;
create policy cerebro_dias_leer on public.cerebro_dias
  for select to authenticated using (public.es_dueno());

drop policy if exists cerebro_marcas_leer on public.cerebro_marcas;
create policy cerebro_marcas_leer on public.cerebro_marcas
  for select to authenticated using (public.es_dueno());
drop policy if exists cerebro_marcas_crear on public.cerebro_marcas;
create policy cerebro_marcas_crear on public.cerebro_marcas
  for insert to authenticated with check (public.es_dueno());
drop policy if exists cerebro_marcas_cambiar on public.cerebro_marcas;
create policy cerebro_marcas_cambiar on public.cerebro_marcas
  for update to authenticated
  using (public.es_dueno()) with check (public.es_dueno());

drop policy if exists cerebro_hist_leer on public.cerebro_historial;
create policy cerebro_hist_leer on public.cerebro_historial
  for select to authenticated using (public.es_dueno());

-- Verificación: 5 políticas con es_dueno y ninguna de cerebro con zaru_rol.
select count(*) filter (where qual ilike '%es_dueno%' or with_check ilike '%es_dueno%') as con_dueno,
       count(*) filter (where qual ilike '%zaru_rol%' or with_check ilike '%zaru_rol%') as con_admin
  from pg_policies where tablename in ('cerebro_dias','cerebro_marcas','cerebro_historial');

-- Rollback (vuelve a «cualquier admin»):
--   recrear las 5 políticas de arriba cambiando public.es_dueno() por (public.zaru_rol() = 'admin');
--   drop function public.es_dueno();
--   alter table public.gestion_usuarios drop column dueno;

-- Registrar en el panel (Database → Migrations), pegándolo junto con este archivo:
-- insert into supabase_migrations.schema_migrations (version, name, statements)
-- values ('0031', 'mi_dia_solo_dueno', array[$m0031$ <este archivo> $m0031$]);
