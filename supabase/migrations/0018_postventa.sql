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
-- 0018 · Post venta (16-10-2026)
--
-- Un caso por cada problema después de la venta: llegó dañado, falla,
-- garantía, cambio. El caso apunta al pedido ORIGINAL, que sigue contando como
-- venta (antes la única herramienta era marcar el pedido "Devolución", y eso lo
-- sacaba de toda estadística). Si hay que rehacer o reparar, el caso crea un
-- trabajo aparte en Producción (pedido_trabajo), a $0 y de tipo DEVOLUCION
-- ("Post venta" en pantalla); lo que cuesta se carga en la tarjeta de Costos de
-- ese trabajo, que sigue siendo solo del admin. Por eso esta tabla no guarda
-- montos: la ven y la usan los tres roles.
--
-- Relacional (id identity), como el módulo de gastos: se habla por PostgREST.
-- Idempotente.
-- ══════════════════════════════════════════════════════════════════════════

create table if not exists public.postventa (
  id              bigint generated always as identity primary key,
  pedido_origen   text not null,
  cliente         text,
  celular         text,
  producto        text,
  motivo          text not null default 'danado'
                  check (motivo in ('danado','falla','cambio','otro')),
  accion          text not null default 'por_definir'
                  check (accion in ('por_definir','reparar','rehacer','reenviar','reembolsar')),
  estado          text not null default 'abierto'
                  check (estado in ('abierto','retiro','taller','reenviado','cerrado')),
  of_retiro       text,
  pedido_trabajo  text,
  notas           text,
  historial       jsonb not null default '[]'::jsonb,
  creado          timestamptz not null default now(),
  creado_por      text default (auth.jwt() ->> 'email'),
  actualizado     timestamptz not null default now(),
  cerrado         timestamptz
);

create index if not exists postventa_origen_idx on public.postventa (pedido_origen);
create index if not exists postventa_estado_idx on public.postventa (estado);

alter table public.postventa enable row level security;
alter table public.postventa force row level security;

-- Leen, crean y editan los tres roles (decisión del dueño: "todos").
drop policy if exists postventa_leer on public.postventa;
create policy postventa_leer on public.postventa
  for select to authenticated using (es_usuario());

drop policy if exists postventa_crear on public.postventa;
create policy postventa_crear on public.postventa
  for insert to authenticated with check (es_usuario());

drop policy if exists postventa_editar on public.postventa;
create policy postventa_editar on public.postventa
  for update to authenticated using (es_usuario()) with check (es_usuario());

-- Borrar, solo el admin: un caso cerrado es historia, no basura.
drop policy if exists postventa_borrar on public.postventa;
create policy postventa_borrar on public.postventa
  for delete to authenticated using (es_admin());

grant select, insert, update, delete on public.postventa to authenticated;
