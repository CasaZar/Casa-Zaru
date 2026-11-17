-- ══════════════════════════════════════════════════════════════════════════
-- 0001_estado_actual · COTIZADOR (cmxqorsyxoltrakxawro) · 17-11-2026
--
-- LÍNEA BASE. Es el esquema `public` del Cotizador tal como estaba en producción
-- el 17-11-2026 (más los buckets y las policies de storage), leído del catálogo
-- con el MCP de solo lectura: 18 tablas, 21 funciones, 3 triggers, 41 policies
-- en public + 5 en storage, RLS y permisos. Verificado contra la base: el md5
-- del código de las 21 funciones y del DDL de las 18 tablas calza. Desde aquí, todo cambio de esquema del Cotizador va en
-- supabase-cotizador/migrations/<NNNN>_<nombre>.sql y se registra en
-- supabase_migrations.schema_migrations (ver supabase/migrations/README.md).
--
-- EN PRODUCCIÓN NO SE CORRE: el esquema ya existe. El bloque de abajo lo
-- impide (si ya hay una tabla `cotizaciones`, aborta y no aplica nada; eso
-- también frena pegarlo en Gestión). La 0001 se anota en schema_migrations con
-- supabase-cotizador/registro-migraciones.sql, sin ejecutarla.
--
-- Sirve para: (1) que exista un punto de partida versionado, (2) recrear el
-- Cotizador en un proyecto vacío si se pierde el actual (después: restaurar
-- los datos desde el respaldo diario con restaurar-prueba.ps1).
--
-- Los .sql sueltos de supabase-cotizador/ quedan como historia: lo que hicieron
-- ya está contenido aquí. Fiel al estado vivo a propósito, incluidas cosas que
-- conviene corregir después en migraciones propias (no aquí; las tres
-- primeras las corrigió la 0002 el mismo 17-11):
--   · cotizacion_lineas y vendedores no tienen FORCE RLS.
--   · anon/authenticated tienen TRUNCATE y otros permisos amplios en varias
--     tablas (el default de Supabase; RLS no cubre TRUNCATE, aunque PostgREST
--     no lo expone).
--   · whoami() es un resto de depuración ejecutable por anon.
--   · biblioteca_copiloto queda cerrada (sin policies ni permisos) desde el 17-11.
--
-- ROLLBACK: no aplica en producción (no se ejecuta ahí). En un proyecto nuevo
-- donde se haya corrido, se deshace borrando lo creado: drop de las 18 tablas
-- y 21 funciones de abajo, y de los buckets publico, fototeca y marketing.
-- ══════════════════════════════════════════════════════════════════════════

-- ── CANDADO (no borrar) ──────────────────────────────────────────────────
do $candado$
begin
  if to_regclass('public.gestion_pedidos') is not null then
    raise exception 'PROYECTO EQUIVOCADO: esta es la línea base del COTIZADOR (cmxqorsyxoltrakxawro) y lo estás corriendo en GESTIÓN. No se aplicó nada.';
  end if;
  if to_regclass('public.cotizaciones') is not null then
    raise exception 'LÍNEA BASE YA APLICADA: este proyecto ya tiene el esquema del Cotizador. La 0001 solo se corre en un proyecto vacío; para registrarla usar registro-migraciones.sql. No se aplicó nada.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

create extension if not exists pgcrypto with schema extensions;
create extension if not exists "uuid-ossp" with schema extensions;

-- ══ 1. TABLAS ═════════════════════════════════════════════════════════════

create table if not exists public.asistente_mensajes (
  id bigint generated always as identity not null,
  creado timestamp with time zone default now() not null,
  sesion text not null,
  numero text,
  rol text not null,
  texto text not null,
  derivar boolean default false not null,
  prueba boolean default false not null,
  modelo text,
  tokens_entrada integer,
  tokens_salida integer,
  tokens_cache integer,
  constraint asistente_mensajes_pkey PRIMARY KEY (id),
  constraint asistente_mensajes_modelo_check CHECK (((modelo IS NULL) OR (length(modelo) <= 60))),
  constraint asistente_mensajes_numero_check CHECK (((numero IS NULL) OR (numero ~ '^[A-Za-z0-9-]{1,40}$'::text))),
  constraint asistente_mensajes_rol_check CHECK ((rol = ANY (ARRAY['user'::text, 'assistant'::text]))),
  constraint asistente_mensajes_sesion_check CHECK ((sesion ~ '^[a-z0-9]{8,40}$'::text)),
  constraint asistente_mensajes_texto_check CHECK (((length(texto) >= 1) AND (length(texto) <= 6000)))
);

create table if not exists public.biblioteca_copiloto (
  id uuid default gen_random_uuid() not null,
  fecha timestamp with time zone default now(),
  resultado text not null,
  conversacion text not null,
  fuente_lead text,
  analisis jsonb,
  notas text,
  constraint biblioteca_copiloto_pkey PRIMARY KEY (id),
  constraint biblioteca_copiloto_resultado_check CHECK ((resultado = ANY (ARRAY['ganada'::text, 'en_desarrollo'::text, 'perdida'::text])))
);

create table if not exists public.config_seguimiento (
  id integer default 1 not null,
  corte_monto_prioritario integer default 400000 not null,
  techo_prioritarios_activos integer default 60 not null,
  meta_toques_lunes integer default 8 not null,
  meta_toques_normal integer default 15 not null,
  meta_toques_sabado integer default 0 not null,
  dias_cierre_backlog integer default 14 not null,
  dias_cierre_cadencia integer default 40 not null,
  updated_at timestamp with time zone default now() not null,
  constraint config_seguimiento_pkey PRIMARY KEY (id),
  constraint config_seguimiento_id_check CHECK ((id = 1))
);

create table if not exists public.cotizaciones (
  id uuid default gen_random_uuid() not null,
  numero text not null,
  cliente text not null,
  producto text not null,
  total_bajo numeric,
  total_medio numeric,
  total_alto numeric,
  vidrio_tipo text,
  vidrio_monto numeric,
  estado text default 'enviada'::text,
  user_email text,
  fecha_creacion timestamp with time zone default now(),
  fecha_concretada timestamp with time zone,
  contacto text,
  seguimiento jsonb default '[false, false, false, false, false]'::jsonb,
  dias_seguimiento integer,
  link text,
  seg_etapa smallint default 0,
  seg_proxima date,
  seg_historial jsonb default '[]'::jsonb,
  asignado_a text,
  motivo_perdida text,
  monto_cierre numeric,
  eliminada boolean default false,
  elim_motivo text,
  elim_por text,
  elim_fecha timestamp with time zone,
  canal text,
  b2b_dcto numeric,
  interesado boolean default false,
  respondio boolean default false not null,
  fecha_primera_respuesta timestamp with time zone,
  fecha_primer_contacto timestamp with time zone,
  cliente_recurrente boolean default false not null,
  telefono_valido boolean,
  motivo_pausa text,
  fecha_agendada date,
  origen jsonb,
  interesado_por text,
  interesado_fecha timestamp with time zone,
  lead_manual text,
  ficha_venta jsonb,
  constraint cotizaciones_pkey PRIMARY KEY (id),
  constraint cotizaciones_estado_check CHECK ((estado = ANY (ARRAY['enviada'::text, 'ganado'::text, 'perdida'::text]))),
  constraint cotizaciones_lead_manual_no_vacio CHECK (((lead_manual IS NULL) OR (length(btrim(lead_manual)) > 0))),
  constraint ficha_venta_estado_ok CHECK (((ficha_venta IS NULL) OR ((jsonb_typeof(ficha_venta) = 'object'::text) AND ((ficha_venta ->> 'estado'::text) = ANY (ARRAY['borrador'::text, 'enviada'::text, 'confirmada'::text])))))
);

create table if not exists public.cotizacion_lineas (
  id uuid default gen_random_uuid() not null,
  cotizacion_id uuid,
  linea integer,
  modelo text,
  largo_cm numeric,
  ancho_cm numeric,
  cantidad integer default 1,
  m2 numeric,
  constraint cotizacion_lineas_pkey PRIMARY KEY (id)
);

create table if not exists public.cotizador_valores (
  clave text not null,
  valor jsonb not null,
  updated_at timestamp with time zone default now() not null,
  updated_by text,
  constraint cotizador_valores_pkey PRIMARY KEY (clave)
);

create table if not exists public.embudo_eventos (
  id bigint generated always as identity not null,
  creado timestamp with time zone default now() not null,
  sesion text not null,
  paso text not null,
  producto text,
  canal text,
  fuente text,
  campana text,
  anuncio text,
  medio text,
  constraint embudo_eventos_pkey PRIMARY KEY (id),
  constraint embudo_eventos_origen_largo CHECK (((COALESCE(length(fuente), 0) <= 100) AND (COALESCE(length(campana), 0) <= 300) AND (COALESCE(length(anuncio), 0) <= 300) AND (COALESCE(length(medio), 0) <= 100))),
  constraint embudo_eventos_paso_check CHECK ((paso = ANY (ARRAY['visita'::text, 'producto'::text, 'medidas'::text, 'datos'::text, 'cotizacion'::text, 'whatsapp'::text, 'duda'::text, 'muestrario'::text])))
);

create table if not exists public.errores_cliente (
  id bigint generated always as identity not null,
  ts timestamp with time zone default now() not null,
  app text not null,
  usuario text default (auth.jwt() ->> 'email'::text),
  mensaje text not null,
  stack text,
  url text,
  ua text,
  version text,
  extra jsonb,
  constraint errores_cliente_pkey PRIMARY KEY (id),
  constraint errores_cliente_app_check CHECK ((app = ANY (ARRAY['cotizador'::text, 'panel'::text, 'cuenta'::text, 'prueba'::text]))),
  constraint errores_cliente_extra_check CHECK (((extra IS NULL) OR (pg_column_size(extra) <= 4000))),
  constraint errores_cliente_mensaje_check CHECK (((length(mensaje) >= 1) AND (length(mensaje) <= 2000))),
  constraint errores_cliente_stack_check CHECK ((length(stack) <= 8000)),
  constraint errores_cliente_ua_check CHECK ((length(ua) <= 300)),
  constraint errores_cliente_url_check CHECK ((length(url) <= 500)),
  constraint errores_cliente_version_check CHECK ((length(version) <= 40))
);

create table if not exists public.fototeca_ediciones (
  item_id text not null,
  campos jsonb default '{}'::jsonb not null,
  en_papelera_at timestamp with time zone,
  eliminada_at timestamp with time zone,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  updated_by text default (auth.jwt() ->> 'email'::text),
  constraint fototeca_ediciones_pkey PRIMARY KEY (item_id),
  constraint fototeca_ediciones_campos_check CHECK (((jsonb_typeof(campos) = 'object'::text) AND ((campos - ARRAY['producto'::text, 'madera'::text, 'uso'::text, 'calidad'::text, 'ia'::text, 'descripcion'::text, 'etiquetas'::text, 'ambiente'::text, 'etapa'::text]) = '{}'::jsonb) AND ((NOT (campos ? 'ia'::text)) OR ((campos ->> 'ia'::text) = ANY (ARRAY['sí'::text, 'posible'::text, 'no'::text]))) AND ((NOT (campos ? 'calidad'::text)) OR ((jsonb_typeof((campos -> 'calidad'::text)) = 'number'::text) AND ((((campos ->> 'calidad'::text))::integer >= 1) AND (((campos ->> 'calidad'::text))::integer <= 5)))) AND ((NOT (campos ? 'etiquetas'::text)) OR (jsonb_typeof((campos -> 'etiquetas'::text)) = 'array'::text)))),
  constraint fototeca_ediciones_check CHECK (((eliminada_at IS NULL) OR (en_papelera_at IS NOT NULL))),
  constraint fototeca_ediciones_item_id_check CHECK ((item_id ~ '^(M[0-9]{4}|g[0-9a-f]{10})$'::text))
);

create table if not exists public.fototeca_ediciones_historial (
  hid bigint generated always as identity not null,
  item_id text not null,
  op text not null,
  ts timestamp with time zone default now() not null,
  por text default (auth.jwt() ->> 'email'::text),
  antes jsonb not null,
  constraint fototeca_ediciones_historial_pkey PRIMARY KEY (hid),
  constraint fototeca_ediciones_historial_op_check CHECK ((op = ANY (ARRAY['UPDATE'::text, 'DELETE'::text])))
);

create table if not exists public.fototeca_usos (
  id bigint generated always as identity not null,
  item_id text not null,
  canal text not null,
  fecha date default CURRENT_DATE not null,
  link text,
  quitado_at timestamp with time zone,
  created_at timestamp with time zone default now() not null,
  created_by text default (auth.jwt() ->> 'email'::text),
  updated_at timestamp with time zone default now() not null,
  updated_by text default (auth.jwt() ->> 'email'::text),
  constraint fototeca_usos_pkey PRIMARY KEY (id),
  constraint fototeca_usos_canal_check CHECK ((canal = ANY (ARRAY['post'::text, 'reel'::text, 'historia'::text, 'anuncio'::text, 'correo'::text]))),
  constraint fototeca_usos_fecha_check CHECK (((fecha >= '2020-01-01'::date) AND (fecha <= (CURRENT_DATE + 1)))),
  constraint fototeca_usos_item_id_check CHECK ((item_id ~ '^(M[0-9]{4}|g[0-9a-f]{10})$'::text)),
  constraint fototeca_usos_link_check CHECK (((link IS NULL) OR ((link ~ '^https://'::text) AND (length(link) <= 500))))
);

create table if not exists public.fototeca_usos_historial (
  hid bigint generated always as identity not null,
  uso_id bigint not null,
  op text not null,
  ts timestamp with time zone default now() not null,
  por text default (auth.jwt() ->> 'email'::text),
  antes jsonb not null,
  constraint fototeca_usos_historial_pkey PRIMARY KEY (hid),
  constraint fototeca_usos_historial_op_check CHECK ((op = ANY (ARRAY['UPDATE'::text, 'DELETE'::text])))
);

create table if not exists public.quote_links (
  id bigint generated always as identity not null,
  token text not null,
  data jsonb not null,
  created_at timestamp with time zone default now(),
  constraint quote_links_pkey PRIMARY KEY (id),
  constraint quote_links_token_key UNIQUE (token)
);

create table if not exists public.toques (
  id bigint generated always as identity not null,
  cotizacion_id uuid not null,
  tipo text not null,
  ts timestamp with time zone default now() not null,
  hecho_por text,
  constraint toques_pkey PRIMARY KEY (id),
  constraint toques_tipo_check CHECK ((tipo = ANY (ARRAY['p1'::text, 'p2'::text, 'p3'::text, 'p4'::text, 'cadencia'::text, 'agendado'::text, 'llamada'::text])))
);

create table if not exists public.vendedores (
  email text not null,
  nombre text not null,
  activo boolean default true,
  creado timestamp with time zone default now(),
  constraint vendedores_pkey PRIMARY KEY (email)
);

create table if not exists public.whatsapp_pendientes (
  id uuid default gen_random_uuid() not null,
  chat_id text not null,
  cliente text not null,
  telefono text,
  tipo text not null,
  prioridad smallint default 50 not null,
  espera_desde timestamp with time zone,
  contexto text,
  cita text,
  mensaje text,
  monto integer,
  pedido text,
  revision_at timestamp with time zone not null,
  estado text default 'pendiente'::text not null,
  resuelto_at timestamp with time zone,
  resuelto_por text,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  updated_by text default (auth.jwt() ->> 'email'::text),
  deleted_at timestamp with time zone,
  constraint whatsapp_pendientes_pkey PRIMARY KEY (id),
  constraint whatsapp_pendientes_chat_id_key UNIQUE (chat_id),
  constraint whatsapp_pendientes_chat_id_check CHECK (((length(chat_id) >= 1) AND (length(chat_id) <= 80))),
  constraint whatsapp_pendientes_cita_check CHECK ((length(cita) <= 400)),
  constraint whatsapp_pendientes_cliente_check CHECK (((length(cliente) >= 1) AND (length(cliente) <= 120))),
  constraint whatsapp_pendientes_contexto_check CHECK ((length(contexto) <= 600)),
  constraint whatsapp_pendientes_estado_check CHECK ((estado = ANY (ARRAY['pendiente'::text, 'respondido'::text, 'no_corresponde'::text, 'cerrado'::text]))),
  constraint whatsapp_pendientes_mensaje_check CHECK ((length(mensaje) <= 1500)),
  constraint whatsapp_pendientes_monto_check CHECK ((monto >= 0)),
  constraint whatsapp_pendientes_pedido_check CHECK ((length(pedido) <= 20)),
  constraint whatsapp_pendientes_prioridad_check CHECK (((prioridad >= 0) AND (prioridad <= 999))),
  constraint whatsapp_pendientes_telefono_check CHECK ((telefono ~ '^[0-9]{8,15}$'::text)),
  constraint whatsapp_pendientes_tipo_check CHECK ((tipo = ANY (ARRAY['responder'::text, 'promesa'::text, 'plata'::text])))
);

create table if not exists public.whatsapp_pendientes_historial (
  hid bigint generated always as identity not null,
  fila_id uuid not null,
  op text not null,
  ts timestamp with time zone default now() not null,
  por text default (auth.jwt() ->> 'email'::text),
  antes jsonb not null,
  constraint whatsapp_pendientes_historial_pkey PRIMARY KEY (hid),
  constraint whatsapp_pendientes_historial_op_check CHECK ((op = ANY (ARRAY['UPDATE'::text, 'DELETE'::text])))
);

create table if not exists public.whatsapp_revisiones (
  id bigint generated always as identity not null,
  revision_at timestamp with time zone not null,
  desde timestamp with time zone,
  chats integer not null,
  nuevos integer default 0 not null,
  actualizados integer default 0 not null,
  ya_resueltos integer default 0 not null,
  cerrados integer default 0 not null,
  forzada boolean default false not null,
  nota text,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  updated_by text default (auth.jwt() ->> 'email'::text),
  constraint whatsapp_revisiones_pkey PRIMARY KEY (id),
  constraint whatsapp_revisiones_chats_check CHECK ((chats >= 0)),
  constraint whatsapp_revisiones_check CHECK (((desde IS NULL) OR (desde <= revision_at))),
  constraint whatsapp_revisiones_nota_check CHECK ((length(nota) <= 300))
);

-- ══ 2. LLAVES FORÁNEAS E ÍNDICES ══════════════════════════════════════════

alter table public.cotizacion_lineas add constraint cotizacion_lineas_cotizacion_id_fkey FOREIGN KEY (cotizacion_id) REFERENCES public.cotizaciones(id) ON DELETE CASCADE;
alter table public.toques add constraint toques_cotizacion_id_fkey FOREIGN KEY (cotizacion_id) REFERENCES public.cotizaciones(id);

create index if not exists asistente_mensajes_creado_idx ON public.asistente_mensajes USING btree (creado DESC);
create index if not exists asistente_mensajes_numero_idx ON public.asistente_mensajes USING btree (numero) WHERE (numero IS NOT NULL);
create index if not exists asistente_mensajes_sesion_idx ON public.asistente_mensajes USING btree (sesion, id);
create index if not exists embudo_eventos_creado_idx ON public.embudo_eventos USING btree (creado);
create index if not exists errores_cliente_ts_idx ON public.errores_cliente USING btree (ts DESC);
create index if not exists fototeca_ediciones_historial_item_idx ON public.fototeca_ediciones_historial USING btree (item_id, ts DESC);
create index if not exists fototeca_usos_item_idx ON public.fototeca_usos USING btree (item_id);
create unique index if not exists fototeca_usos_unico ON public.fototeca_usos USING btree (item_id, canal, fecha) WHERE (quitado_at IS NULL);
create index if not exists idx_toques_cotizacion ON public.toques USING btree (cotizacion_id);
create index if not exists idx_toques_ts ON public.toques USING btree (ts);
create index if not exists whatsapp_pendientes_estado_idx ON public.whatsapp_pendientes USING btree (estado, prioridad);
create index if not exists whatsapp_pendientes_historial_fila_idx ON public.whatsapp_pendientes_historial USING btree (fila_id, ts DESC);
create index if not exists whatsapp_revisiones_rev_idx ON public.whatsapp_revisiones USING btree (revision_at DESC);

-- ══ 3. FUNCIONES ══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.embudo_resumen(dias integer DEFAULT 30)
 RETURNS TABLE(dia date, paso text, sesiones bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select (creado at time zone 'America/Santiago')::date as dia,
         paso,
         count(distinct sesion)::bigint as sesiones
  from embudo_eventos
  where creado >= now() - make_interval(days => greatest(1, least(dias, 365)))
  group by 1, 2
  order by 1, 2
$function$;

CREATE OR REPLACE FUNCTION public.errores_cliente_limpiar()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n integer;
begin
  delete from public.errores_cliente where ts < now() - interval '90 days';
  get diagnostics n = row_count;
  return n;
end $function$;

CREATE OR REPLACE FUNCTION public.es_equipo_panel()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select lower(coalesce(auth.email(), '')) in ('hola@casazaru.cl', 'mariajose.mgrunen@gmail.com')
      or exists (select 1 from public.vendedores v where v.email = auth.email() and v.activo);
$function$;

CREATE OR REPLACE FUNCTION public.fototeca_ediciones_hist()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  insert into public.fototeca_ediciones_historial (item_id, op, antes)
  values (old.item_id, tg_op, to_jsonb(old));
  if tg_op = 'UPDATE' then
    new.updated_at := now();
    new.updated_by := coalesce(auth.jwt() ->> 'email', new.updated_by);
    return new;
  end if;
  return old;
end $function$;

CREATE OR REPLACE FUNCTION public.fototeca_editar(p_ids text[], p_accion text, p_campos jsonb DEFAULT '{}'::jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n integer := 0;
begin
  if lower(coalesce(auth.email(), '')) <> 'hola@casazaru.cl' then
    raise exception 'Solo el admin puede editar la Fototeca';
  end if;
  if p_accion not in ('campos','papelera','restaurar','vaciar') then
    raise exception 'Acción desconocida: %', p_accion;
  end if;
  if p_accion = 'vaciar' then
    update public.fototeca_ediciones set eliminada_at = now()
     where en_papelera_at is not null and eliminada_at is null;
    get diagnostics n = row_count;
    return n;
  end if;
  if coalesce(array_length(p_ids, 1), 0) = 0 or array_length(p_ids, 1) > 2000 then
    raise exception 'Hay que mandar entre 1 y 2000 piezas';
  end if;
  -- las que no tienen fila todavía
  insert into public.fototeca_ediciones (item_id)
  select distinct unnest(p_ids) on conflict (item_id) do nothing;
  if p_accion = 'campos' then
    update public.fototeca_ediciones set campos = campos || coalesce(p_campos, '{}'::jsonb)
     where item_id = any(p_ids) and campos is distinct from campos || coalesce(p_campos, '{}'::jsonb);
  elsif p_accion = 'papelera' then
    update public.fototeca_ediciones set en_papelera_at = now()
     where item_id = any(p_ids) and en_papelera_at is null;
  else
    update public.fototeca_ediciones set en_papelera_at = null
     where item_id = any(p_ids) and en_papelera_at is not null and eliminada_at is null;
  end if;
  get diagnostics n = row_count;
  return n;
end $function$;

CREATE OR REPLACE FUNCTION public.fototeca_marca_usos()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select lower(coalesce(auth.email(), '')) in ('hola@casazaru.cl', 'emerge.smm@gmail.com', 'mariajose.mgrunen@gmail.com')
$function$;

CREATE OR REPLACE FUNCTION public.fototeca_marcar_uso(p_ids text[], p_canal text, p_fecha date DEFAULT CURRENT_DATE, p_link text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n integer;
begin
  if not public.fototeca_marca_usos() then raise exception 'Esta cuenta no puede marcar usos en la Fototeca'; end if;
  if coalesce(array_length(p_ids, 1), 0) = 0 or array_length(p_ids, 1) > 500 then
    raise exception 'Hay que mandar entre 1 y 500 piezas';
  end if;
  insert into public.fototeca_usos (item_id, canal, fecha, link)
  select distinct unnest(p_ids), p_canal, coalesce(p_fecha, current_date), nullif(trim(p_link), '')
  on conflict (item_id, canal, fecha) where quitado_at is null do nothing;
  get diagnostics n = row_count;
  return n;
end $function$;

CREATE OR REPLACE FUNCTION public.fototeca_quitar_uso(p_id bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n integer;
begin
  if not public.fototeca_marca_usos() then raise exception 'Esta cuenta no puede marcar usos en la Fototeca'; end if;
  update public.fototeca_usos set quitado_at = now() where id = p_id and quitado_at is null;
  get diagnostics n = row_count;
  return n;
end $function$;

CREATE OR REPLACE FUNCTION public.fototeca_usos_hist()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  insert into public.fototeca_usos_historial (uso_id, op, antes) values (old.id, tg_op, to_jsonb(old));
  if tg_op = 'UPDATE' then
    new.updated_at := now();
    new.updated_by := coalesce(auth.jwt() ->> 'email', new.updated_by);
    return new;
  end if;
  return old;
end $function$;

CREATE OR REPLACE FUNCTION public.get_quote_link(tok text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select data || jsonb_build_object('_f', created_at)
  from quote_links
  where token = tok
  limit 1
$function$;

CREATE OR REPLACE FUNCTION public.guardar_lineas(p_numero text, p_lineas jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
begin
  if p_numero is null or p_lineas is null then return; end if;
  if jsonb_typeof(p_lineas) <> 'array' then return; end if;

  select c.id into v_id
  from cotizaciones c
  where c.numero = p_numero
    and c.fecha_creacion >= now() - interval '10 minutes'
  order by c.fecha_creacion desc nulls last
  limit 1;

  if v_id is null then return; end if;

  if exists (select 1 from cotizacion_lineas l where l.cotizacion_id = v_id) then
    return;
  end if;

  insert into cotizacion_lineas (cotizacion_id, modelo, largo_cm, ancho_cm, cantidad, m2)
  select v_id,
         nullif(e->>'modelo',''),
         (e->>'largo_cm')::numeric,
         (e->>'ancho_cm')::numeric,
         coalesce((e->>'cantidad')::int, 1),
         (e->>'m2')::numeric
  from jsonb_array_elements(p_lineas) as e;
end;
$function$;

CREATE OR REPLACE FUNCTION public.next_quote_number(k text)
 RETURNS text
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select 'N° CL-' || k || '-' || lpad(
    (coalesce(max((regexp_replace(numero, '^.*-', ''))::int), 0) + 1)::text, 3, '0')
  from cotizaciones
  where numero like 'N° CL-' || k || '-%'
    and regexp_replace(numero, '^.*-', '') ~ '^[0-9]+$'
$function$;

CREATE OR REPLACE FUNCTION public.restore_test_cargar(tabla text, filas jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n integer;
begin
  if to_regclass(format('restore_test.%I', tabla)) is null then
    raise exception 'restore_test.% no existe: correr restore_test_preparar() primero', tabla;
  end if;
  execute format('insert into restore_test.%I select * from jsonb_populate_recordset(null::restore_test.%I, $1)', tabla, tabla)
    using filas;
  get diagnostics n = row_count;
  return n;
end $function$;

CREATE OR REPLACE FUNCTION public.restore_test_limpiar()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  execute 'drop schema if exists restore_test cascade';
end $function$;

CREATE OR REPLACE FUNCTION public.restore_test_preparar()
 RETURNS text[]
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare t record; creadas text[] := '{}';
begin
  execute 'drop schema if exists restore_test cascade';
  execute 'create schema restore_test';
  for t in select tablename from pg_tables where schemaname = 'public' order by 1 loop
    execute format('create table restore_test.%I (like public.%I including defaults)', t.tablename, t.tablename);
    creadas := creadas || t.tablename;
  end loop;
  return creadas;
end $function$;

CREATE OR REPLACE FUNCTION public.restore_test_resumen()
 RETURNS TABLE(tabla text, filas bigint, sumas jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare t record; c record; n bigint; s jsonb; v numeric;
begin
  for t in select tablename from pg_tables where schemaname = 'restore_test' order by 1 loop
    execute format('select count(*) from restore_test.%I', t.tablename) into n;
    s := '{}'::jsonb;
    for c in
      select column_name from information_schema.columns
      where table_schema = 'restore_test' and table_name = t.tablename
        and data_type in ('smallint','integer','bigint','numeric','real','double precision')
      order by ordinal_position
    loop
      execute format('select coalesce(sum(%I), 0) from restore_test.%I', c.column_name, t.tablename) into v;
      s := s || jsonb_build_object(c.column_name, v);
    end loop;
    tabla := t.tablename; filas := n; sumas := s;
    return next;
  end loop;
end $function$;

CREATE OR REPLACE FUNCTION public.wa_cargar(p_revision timestamp with time zone, p_filas jsonb, p_desde timestamp with time zone DEFAULT NULL::timestamp with time zone, p_forzar boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  f jsonb; n_nuevos int := 0; n_act int := 0; n_resp int := 0; n_cerr int := 0;
  ids text[] := '{}'; r public.whatsapp_pendientes;
  n_pend int; n_a_cerrar int; nombres text; ult timestamptz; lista jsonb;
begin
  if coalesce(auth.email(), '') <> 'hola@casazaru.cl' then
    raise exception 'Solo el admin carga la revisión de WhatsApp';
  end if;
  if p_revision is null or p_revision > now() + interval '5 minutes' then
    raise exception 'Hora de revisión inválida';
  end if;
  if p_desde is not null and p_desde > p_revision then
    raise exception 'p_desde no puede ser después de la hora de la revisión';
  end if;
  if jsonb_typeof(p_filas) <> 'array' or jsonb_array_length(p_filas) > 200 then
    raise exception 'p_filas debe ser una lista de hasta 200 chats';
  end if;

  select max(revision_at) into ult from public.whatsapp_revisiones;
  if ult is not null and p_revision < ult then
    raise exception 'Ya hay una revisión más nueva cargada (%). No se aplicó nada.', ult;
  end if;

  select coalesce(array_agg(e ->> 'chat_id'), '{}') into ids
  from jsonb_array_elements(p_filas) e;

  -- freno: ¿cuántos pendientes cerraría esta carga?
  select count(*) into n_pend from public.whatsapp_pendientes
  where estado = 'pendiente' and deleted_at is null;
  select count(*), string_agg(cliente, ', ' order by prioridad)
    into n_a_cerrar, nombres
  from public.whatsapp_pendientes
  where estado = 'pendiente' and deleted_at is null
    and revision_at < p_revision and not (chat_id = any(ids));
  if not p_forzar and n_a_cerrar > 3 and n_a_cerrar * 2 > n_pend then
    raise exception 'FRENO: esta carga cerraría % de % pendientes (%). Si la revisión fue completa y esos chats de verdad se respondieron, repetirla con p_forzar => true. No se aplicó nada.',
      n_a_cerrar, n_pend, nombres;
  end if;

  for f in select * from jsonb_array_elements(p_filas) loop
    select * into r from public.whatsapp_pendientes where chat_id = f ->> 'chat_id';
    if not found then
      insert into public.whatsapp_pendientes
        (chat_id, cliente, telefono, tipo, prioridad, espera_desde, contexto, cita,
         mensaje, monto, pedido, revision_at)
      values
        (f ->> 'chat_id', f ->> 'cliente', nullif(f ->> 'telefono', ''), f ->> 'tipo',
         coalesce((f ->> 'prioridad')::smallint, 50), (f ->> 'espera_desde')::timestamptz,
         f ->> 'contexto', f ->> 'cita', f ->> 'mensaje', (f ->> 'monto')::integer,
         f ->> 'pedido', p_revision);
      n_nuevos := n_nuevos + 1;
    elsif r.estado in ('respondido','no_corresponde') and r.resuelto_at >= p_revision then
      n_resp := n_resp + 1;          -- César lo cerró después de la revisión: manda él
    else
      update public.whatsapp_pendientes set
        cliente = f ->> 'cliente', telefono = nullif(f ->> 'telefono', ''), tipo = f ->> 'tipo',
        prioridad = coalesce((f ->> 'prioridad')::smallint, 50),
        espera_desde = (f ->> 'espera_desde')::timestamptz, contexto = f ->> 'contexto',
        cita = f ->> 'cita', mensaje = f ->> 'mensaje', monto = (f ->> 'monto')::integer,
        pedido = f ->> 'pedido', revision_at = p_revision, estado = 'pendiente',
        resuelto_at = null, resuelto_por = null, deleted_at = null
      where id = r.id;
      n_act := n_act + 1;
    end if;
  end loop;

  with c as (
    update public.whatsapp_pendientes set
      estado = 'cerrado', resuelto_at = now(), resuelto_por = 'revision'
    where estado = 'pendiente' and deleted_at is null
      and revision_at < p_revision and not (chat_id = any(ids))
    returning cliente
  )
  select count(*), coalesce(jsonb_agg(cliente), '[]') into n_cerr, lista from c;

  insert into public.whatsapp_revisiones
    (revision_at, desde, chats, nuevos, actualizados, ya_resueltos, cerrados, forzada)
  values (p_revision, p_desde, jsonb_array_length(p_filas), n_nuevos, n_act, n_resp, n_cerr,
          p_forzar and n_a_cerrar > 3 and n_a_cerrar * 2 > n_pend);

  return jsonb_build_object('nuevos', n_nuevos, 'actualizados', n_act,
                            'ya_resueltos', n_resp, 'cerrados', n_cerr,
                            'cerrados_quienes', lista);
end $function$;

CREATE OR REPLACE FUNCTION public.wa_historial(p_dias integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d0 timestamptz; res jsonb;
begin
  if coalesce(auth.email(), '') not in ('hola@casazaru.cl', 'crodriguez.casazaru@gmail.com', 'mariajose.mgrunen@gmail.com') then
    raise exception 'Sin acceso';
  end if;
  d0 := now() - make_interval(days => least(greatest(coalesce(p_dias, 30), 1), 120));

  with versiones as (
    select p.id as fila_id, to_jsonb(p) as v, 1 as actual
    from public.whatsapp_pendientes p where p.deleted_at is null
    union all
    select h.fila_id, h.antes, 0 from public.whatsapp_pendientes_historial h
  ), cierres as (
    select distinct on (fila_id, (v ->> 'resuelto_at')::timestamptz)
           fila_id, v, (v ->> 'resuelto_at')::timestamptz as cuando
    from versiones
    where v ->> 'estado' in ('respondido','no_corresponde','cerrado')
      and v ->> 'resuelto_at' is not null
      and (v ->> 'resuelto_at')::timestamptz >= d0
    order by fila_id, (v ->> 'resuelto_at')::timestamptz, actual desc
  )
  select jsonb_build_object(
    'cierres', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', c.fila_id, 'cliente', c.v ->> 'cliente', 'tipo', c.v ->> 'tipo',
               'estado', c.v ->> 'estado', 'resuelto_at', c.cuando,
               'resuelto_por', c.v ->> 'resuelto_por', 'contexto', c.v ->> 'contexto',
               'monto', c.v -> 'monto', 'pedido', c.v ->> 'pedido',
               'espera_desde', c.v ->> 'espera_desde',
               'vigente', (p.estado = c.v ->> 'estado' and p.resuelto_at = c.cuando))
             order by c.cuando desc)
      from cierres c join public.whatsapp_pendientes p on p.id = c.fila_id), '[]'::jsonb),
    'revisiones', coalesce((
      select jsonb_agg(jsonb_build_object(
               'revision_at', r.revision_at, 'desde', r.desde, 'chats', r.chats,
               'nuevos', r.nuevos, 'actualizados', r.actualizados,
               'ya_resueltos', r.ya_resueltos, 'cerrados', r.cerrados,
               'forzada', r.forzada, 'nota', r.nota)
             order by r.revision_at desc)
      from public.whatsapp_revisiones r where r.revision_at >= d0), '[]'::jsonb)
  ) into res;
  return res;
end $function$;

CREATE OR REPLACE FUNCTION public.wa_marcar(p_id uuid, p_estado text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if coalesce(auth.email(), '') not in ('hola@casazaru.cl', 'crodriguez.casazaru@gmail.com', 'mariajose.mgrunen@gmail.com') then
    raise exception 'Sin acceso';
  end if;
  if p_estado not in ('pendiente','respondido','no_corresponde') then
    raise exception 'Estado inválido: %', p_estado;
  end if;
  update public.whatsapp_pendientes set
    estado = p_estado,
    resuelto_at  = case when p_estado = 'pendiente' then null else now() end,
    resuelto_por = case when p_estado = 'pendiente' then null else auth.email() end
  where id = p_id and deleted_at is null;
  if not found then raise exception 'No existe ese chat'; end if;
end $function$;

CREATE OR REPLACE FUNCTION public.whatsapp_pendientes_hist()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  insert into public.whatsapp_pendientes_historial (fila_id, op, antes)
  values (old.id, tg_op, to_jsonb(old));
  if tg_op = 'UPDATE' then
    new.updated_at := now();
    new.updated_by := coalesce(auth.jwt() ->> 'email', new.updated_by);
    return new;
  end if;
  return old;
end $function$;

CREATE OR REPLACE FUNCTION public.whoami()
 RETURNS text
 LANGUAGE sql
AS $function$ select current_user::text $function$;

-- ══ 4. TRIGGERS DE HISTORIAL ══════════════════════════════════════════════

create or replace trigger fototeca_ediciones_hist BEFORE DELETE OR UPDATE ON public.fototeca_ediciones FOR EACH ROW EXECUTE FUNCTION public.fototeca_ediciones_hist();
create or replace trigger fototeca_usos_hist BEFORE DELETE OR UPDATE ON public.fototeca_usos FOR EACH ROW EXECUTE FUNCTION public.fototeca_usos_hist();
create or replace trigger whatsapp_pendientes_hist BEFORE DELETE OR UPDATE ON public.whatsapp_pendientes FOR EACH ROW EXECUTE FUNCTION public.whatsapp_pendientes_hist();

-- ══ 5. RLS ════════════════════════════════════════════════════════════════

alter table public.asistente_mensajes enable row level security; alter table public.asistente_mensajes force row level security;
alter table public.biblioteca_copiloto enable row level security; alter table public.biblioteca_copiloto force row level security;
alter table public.config_seguimiento enable row level security; alter table public.config_seguimiento force row level security;
alter table public.cotizacion_lineas enable row level security;
alter table public.cotizaciones enable row level security; alter table public.cotizaciones force row level security;
alter table public.cotizador_valores enable row level security; alter table public.cotizador_valores force row level security;
alter table public.embudo_eventos enable row level security; alter table public.embudo_eventos force row level security;
alter table public.errores_cliente enable row level security; alter table public.errores_cliente force row level security;
alter table public.fototeca_ediciones enable row level security; alter table public.fototeca_ediciones force row level security;
alter table public.fototeca_ediciones_historial enable row level security; alter table public.fototeca_ediciones_historial force row level security;
alter table public.fototeca_usos enable row level security; alter table public.fototeca_usos force row level security;
alter table public.fototeca_usos_historial enable row level security; alter table public.fototeca_usos_historial force row level security;
alter table public.quote_links enable row level security; alter table public.quote_links force row level security;
alter table public.toques enable row level security; alter table public.toques force row level security;
alter table public.vendedores enable row level security;
alter table public.whatsapp_pendientes enable row level security; alter table public.whatsapp_pendientes force row level security;
alter table public.whatsapp_pendientes_historial enable row level security; alter table public.whatsapp_pendientes_historial force row level security;
alter table public.whatsapp_revisiones enable row level security; alter table public.whatsapp_revisiones force row level security;

-- ══ 6. POLICIES ═══════════════════════════════════════════════════════════

create policy asistente_equipo_lee on public.asistente_mensajes as permissive for select to authenticated using (es_equipo_panel());
create policy "equipo lee config seguimiento" on public.config_seguimiento as permissive for select to authenticated using (true);
create policy "solo admin edita config seguimiento" on public.config_seguimiento as permissive for update to authenticated using ((auth.email() = 'hola@casazaru.cl'::text)) with check ((auth.email() = 'hola@casazaru.cl'::text));
create policy "solo equipo lee config" on public.config_seguimiento as restrictive for select to authenticated using (es_equipo_panel());
create policy auth_full_lineas on public.cotizacion_lineas as permissive for all to authenticated using (true) with check (true);
create policy clientes_insert_lineas on public.cotizacion_lineas as permissive for insert to anon with check (true);
create policy "solo equipo borra lineas" on public.cotizacion_lineas as restrictive for delete to authenticated using (es_equipo_panel());
create policy "solo equipo edita lineas" on public.cotizacion_lineas as restrictive for update to authenticated using (es_equipo_panel()) with check (es_equipo_panel());
create policy "solo equipo lee lineas" on public.cotizacion_lineas as restrictive for select to authenticated using (es_equipo_panel());
create policy "equipo edita cotizaciones" on public.cotizaciones as permissive for update to authenticated using (((auth.email() = 'hola@casazaru.cl'::text) OR (asignado_a = auth.email()) OR ((auth.email() = 'crodriguez.casazaru@gmail.com'::text) AND ((user_email = 'crodriguez.casazaru@gmail.com'::text) OR (user_email = 'hola@casazaru.cl'::text) OR ((user_email IS NULL) AND (asignado_a IS NULL)))))) with check (((auth.email() = 'hola@casazaru.cl'::text) OR (asignado_a = auth.email()) OR ((auth.email() = 'crodriguez.casazaru@gmail.com'::text) AND ((user_email = 'crodriguez.casazaru@gmail.com'::text) OR (user_email = 'hola@casazaru.cl'::text) OR ((user_email IS NULL) AND (asignado_a IS NULL))))));
create policy "equipo inserta cotizaciones" on public.cotizaciones as permissive for insert to authenticated with check (true);
create policy "equipo lee cotizaciones" on public.cotizaciones as permissive for select to authenticated using (((auth.email() = 'hola@casazaru.cl'::text) OR (asignado_a = auth.email()) OR ((auth.email() = 'crodriguez.casazaru@gmail.com'::text) AND ((user_email = 'crodriguez.casazaru@gmail.com'::text) OR (user_email = 'hola@casazaru.cl'::text) OR ((user_email IS NULL) AND (asignado_a IS NULL))))));
create policy "marketing edita cotizaciones" on public.cotizaciones as permissive for update to authenticated using ((lower(auth.email()) = 'mariajose.mgrunen@gmail.com'::text)) with check ((lower(auth.email()) = 'mariajose.mgrunen@gmail.com'::text));
create policy "marketing lee cotizaciones" on public.cotizaciones as permissive for select to authenticated using ((lower(auth.email()) = 'mariajose.mgrunen@gmail.com'::text));
create policy "publico inserta cotizacion" on public.cotizaciones as permissive for insert to anon with check (true);
create policy "solo admin actualiza valores" on public.cotizador_valores as permissive for update to authenticated using ((auth.email() = 'hola@casazaru.cl'::text)) with check ((auth.email() = 'hola@casazaru.cl'::text));
create policy "solo admin escribe valores" on public.cotizador_valores as permissive for insert to authenticated with check ((auth.email() = 'hola@casazaru.cl'::text));
create policy "todos leen valores" on public.cotizador_valores as permissive for select to anon, authenticated using (true);
create policy embudo_insert_publico on public.embudo_eventos as permissive for insert to anon, authenticated with check (true);
create policy embudo_select_equipo on public.embudo_eventos as permissive for select to authenticated using (true);
create policy "solo equipo lee embudo" on public.embudo_eventos as restrictive for select to authenticated using (es_equipo_panel());
create policy errores_cliente_publico_escribe on public.errores_cliente as permissive for insert to anon, authenticated with check (true);
create policy "lectores fototeca leen ediciones" on public.fototeca_ediciones as permissive for select to authenticated using ((lower(auth.email()) = ANY (ARRAY['hola@casazaru.cl'::text, 'crodriguez.casazaru@gmail.com'::text, 'emerge.smm@gmail.com'::text])));
create policy "marketing lee ediciones fototeca" on public.fototeca_ediciones as permissive for select to authenticated using ((lower(auth.email()) = 'mariajose.mgrunen@gmail.com'::text));
create policy "admin lee historial fototeca" on public.fototeca_ediciones_historial as permissive for select to authenticated using ((lower(auth.email()) = 'hola@casazaru.cl'::text));
create policy "lectores fototeca leen usos" on public.fototeca_usos as permissive for select to authenticated using ((lower(auth.email()) = ANY (ARRAY['hola@casazaru.cl'::text, 'crodriguez.casazaru@gmail.com'::text, 'emerge.smm@gmail.com'::text, 'mariajose.mgrunen@gmail.com'::text])));
create policy "admin lee historial usos" on public.fototeca_usos_historial as permissive for select to authenticated using ((lower(auth.email()) = 'hola@casazaru.cl'::text));
create policy "equipo crea link" on public.quote_links as permissive for insert to authenticated with check (true);
create policy "publico crea link" on public.quote_links as permissive for insert to anon with check (true);
create policy "equipo deshace toques" on public.toques as permissive for delete to authenticated using (true);
create policy "equipo lee toques" on public.toques as permissive for select to authenticated using (true);
create policy "equipo registra toques" on public.toques as permissive for insert to authenticated with check (true);
create policy "solo equipo del panel" on public.toques as restrictive for all to authenticated using (es_equipo_panel()) with check (es_equipo_panel());
create policy "solo equipo lee vendedores" on public.vendedores as restrictive for select to authenticated using (es_equipo_panel());
create policy "vendedores insert admin" on public.vendedores as permissive for insert to authenticated with check ((auth.email() = 'hola@casazaru.cl'::text));
create policy "vendedores select autenticados" on public.vendedores as permissive for select to authenticated using (true);
create policy "vendedores update admin" on public.vendedores as permissive for update to authenticated using ((auth.email() = 'hola@casazaru.cl'::text));
create policy "5558 lee pendientes" on public.whatsapp_pendientes as permissive for select to authenticated using (((auth.email() = ANY (ARRAY['hola@casazaru.cl'::text, 'crodriguez.casazaru@gmail.com'::text])) AND (deleted_at IS NULL)));
create policy "marketing lee pendientes" on public.whatsapp_pendientes as permissive for select to authenticated using (((lower(auth.email()) = 'mariajose.mgrunen@gmail.com'::text) AND (deleted_at IS NULL)));
create policy "5558 lee revisiones" on public.whatsapp_revisiones as permissive for select to authenticated using ((auth.email() = ANY (ARRAY['hola@casazaru.cl'::text, 'crodriguez.casazaru@gmail.com'::text])));
create policy "marketing lee revisiones" on public.whatsapp_revisiones as permissive for select to authenticated using ((lower(auth.email()) = 'mariajose.mgrunen@gmail.com'::text));

-- ══ 7. PERMISOS ═══════════════════════════════════════════════════════════
-- Un proyecto nuevo de Supabase le da todo a anon y authenticated por defecto:
-- primero se quita y después se deja exactamente lo que había el 17-11.

do $permisos$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end
$permisos$;

grant delete, insert, references, select, trigger, truncate, update on public.config_seguimiento to anon, authenticated;
grant delete, insert, references, select, trigger, truncate, update on public.cotizacion_lineas to anon, authenticated;
grant delete, insert, references, select, trigger, truncate, update on public.cotizaciones to anon, authenticated;
grant delete, insert, references, select, trigger, truncate, update on public.cotizador_valores to anon, authenticated;
grant delete, insert, references, select, trigger, truncate, update on public.embudo_eventos to anon, authenticated;
grant delete, insert, references, select, trigger, truncate, update on public.quote_links to anon, authenticated;
grant delete, insert, references, select, trigger, truncate, update on public.toques to anon, authenticated;
grant delete, insert, references, select, trigger, truncate, update on public.vendedores to anon, authenticated;
grant insert, references, trigger, truncate on public.errores_cliente to anon, authenticated;
grant references, select, trigger, truncate on public.fototeca_ediciones to authenticated;
grant references, select, trigger, truncate on public.fototeca_ediciones_historial to authenticated;
grant references, select, trigger, truncate on public.fototeca_usos to authenticated;
grant references, select, trigger, truncate on public.fototeca_usos_historial to authenticated;
grant references, select, trigger, truncate on public.whatsapp_pendientes to authenticated;
grant select on public.asistente_mensajes to authenticated;
grant select on public.whatsapp_revisiones to authenticated;
-- biblioteca_copiloto, whatsapp_pendientes_historial: sin permisos para anon ni authenticated.

-- Funciones: por defecto las ejecuta cualquiera; se quita a todos y se devuelve
-- solo a quien la tenía el 17-11.
do $funciones$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
end
$funciones$;

grant execute on function public.fototeca_ediciones_hist() to public;
grant execute on function public.fototeca_usos_hist() to public;
grant execute on function public.get_quote_link(text) to public;
grant execute on function public.guardar_lineas(text, jsonb) to public;
grant execute on function public.next_quote_number(text) to public;
grant execute on function public.whoami() to public;
grant execute on function public.embudo_resumen(integer) to authenticated;
grant execute on function public.es_equipo_panel() to authenticated;
grant execute on function public.fototeca_editar(text[], text, jsonb) to authenticated;
grant execute on function public.fototeca_marca_usos() to authenticated;
grant execute on function public.fototeca_marcar_uso(text[], text, date, text) to authenticated;
grant execute on function public.fototeca_quitar_uso(bigint) to authenticated;
grant execute on function public.wa_cargar(timestamp with time zone, jsonb, timestamp with time zone, boolean) to authenticated;
grant execute on function public.wa_historial(integer) to authenticated;
grant execute on function public.wa_marcar(uuid, text) to authenticated;
-- errores_cliente_limpiar, restore_test_*, whatsapp_pendientes_hist: solo el dueño (y la llave secreta).

-- ══ 8. STORAGE ════════════════════════════════════════════════════════════

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('publico',   'publico',   true,  null,    null),
  ('fototeca',  'fototeca',  false, 5242880, array['image/jpeg','application/json']),
  ('marketing', 'marketing', false, 2097152, array['application/json'])
on conflict (id) do nothing;

create policy "admin reemplaza bucket marketing" on storage.objects as permissive for update to authenticated using (((bucket_id = 'marketing'::text) AND (lower(auth.email()) = 'hola@casazaru.cl'::text))) with check (((bucket_id = 'marketing'::text) AND (lower(auth.email()) = 'hola@casazaru.cl'::text)));
create policy "admin sube bucket marketing" on storage.objects as permissive for insert to authenticated with check (((bucket_id = 'marketing'::text) AND (lower(auth.email()) = 'hola@casazaru.cl'::text)));
create policy "equipo lee fototeca" on storage.objects as permissive for select to authenticated using (((bucket_id = 'fototeca'::text) AND (lower(auth.email()) = ANY (ARRAY['hola@casazaru.cl'::text, 'crodriguez.casazaru@gmail.com'::text, 'emerge.smm@gmail.com'::text]))));
create policy "marketing lee bucket marketing" on storage.objects as permissive for select to authenticated using (((bucket_id = 'marketing'::text) AND (lower(auth.email()) = ANY (ARRAY['hola@casazaru.cl'::text, 'mariajose.mgrunen@gmail.com'::text]))));
create policy "marketing lee fototeca" on storage.objects as permissive for select to authenticated using (((bucket_id = 'fototeca'::text) AND (lower(auth.email()) = 'mariajose.mgrunen@gmail.com'::text)));

-- Fuera de esta migración (no son esquema): las filas de cotizador_valores y
-- vendedores (vienen en el respaldo diario), las Edge Functions de
-- supabase-cotizador/functions/ y sus secretos (se cargan en el panel).
