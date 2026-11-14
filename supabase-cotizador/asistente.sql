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

-- ═════════════════════════════════════════════════════════════════════════
-- Asistente del cotizador · conversaciones (14-11-2026)
--
-- El 28,7 % de las cotizaciones llega fuera del turno del vendedor y cierra
-- menos de la mitad (2,8 % contra 6,5 %). El asistente responde dudas al
-- instante desde la propia cotización (Edge Function `asistente`, que es la
-- única que escribe acá, con la llave de servicio).
--
-- Qué crea:
--   · asistente_mensajes: cada mensaje del cliente y cada respuesta. Solo se
--     agregan filas: nadie las edita ni las borra por la API. El equipo del
--     panel las lee (para que el vendedor vea al día siguiente qué preguntó el
--     cliente); el público no lee nada.
--   · la clave `asistente` en cotizador_valores: el interruptor.
--       estado: 'apagado' (no existe para nadie) · 'prueba' (solo con
--       ?asistente=1 en el link) · 'activo' (lo ven todos los clientes)
--       tope_sesion: mensajes del cliente por conversación
--       tope_dia: mensajes del cliente por día, entre todos
--     Parte APAGADO. Se cambia con un update sobre esa fila.
--
-- No guarda nombre, teléfono ni correo: solo la sesión anónima del navegador,
-- el número de la cotización y el texto. Idempotente.
--
-- Volver atrás:
--   update public.cotizador_valores set valor = jsonb_set(valor, '{estado}', '"apagado"') where clave = 'asistente';
--   (y, si se quiere sacar del todo) drop table public.asistente_mensajes;
--                                    delete from public.cotizador_valores where clave = 'asistente';
-- ═════════════════════════════════════════════════════════════════════════

create table if not exists public.asistente_mensajes (
  id             bigint generated always as identity primary key,
  creado         timestamptz not null default now(),
  sesion         text not null check (sesion ~ '^[a-z0-9]{8,40}$'),
  numero         text check (numero is null or numero ~ '^[A-Za-z0-9-]{1,40}$'),
  rol            text not null check (rol in ('user', 'assistant')),
  texto          text not null check (length(texto) between 1 and 6000),
  derivar        boolean not null default false,   -- la respuesta dejó algo para una persona
  prueba         boolean not null default false,   -- conversación de prueba (link con ?asistente=1 o localhost)
  modelo         text check (modelo is null or length(modelo) <= 60),
  tokens_entrada integer,
  tokens_salida  integer,
  tokens_cache   integer
);
create index if not exists asistente_mensajes_sesion_idx on public.asistente_mensajes (sesion, id);
create index if not exists asistente_mensajes_numero_idx on public.asistente_mensajes (numero) where numero is not null;
create index if not exists asistente_mensajes_creado_idx on public.asistente_mensajes (creado desc);

alter table public.asistente_mensajes enable row level security;
alter table public.asistente_mensajes force row level security;

drop policy if exists asistente_equipo_lee on public.asistente_mensajes;
create policy asistente_equipo_lee on public.asistente_mensajes
  for select to authenticated using (public.es_equipo_panel());
-- Sin policy de insert, update ni delete: solo escribe la función, con la llave de servicio.

revoke all on public.asistente_mensajes from anon, authenticated;
grant select on public.asistente_mensajes to authenticated;

insert into public.cotizador_valores (clave, valor, updated_by)
values ('asistente', '{"estado": "apagado", "tope_sesion": 12, "tope_dia": 400}'::jsonb, 'asistente.sql')
on conflict (clave) do nothing;

-- ── Verificación (sale al correrlo) ──
select (select count(*) from public.asistente_mensajes) as mensajes,
       (select valor from public.cotizador_valores where clave = 'asistente') as interruptor,
       (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.asistente_mensajes'::regclass) as rls_forzado;
