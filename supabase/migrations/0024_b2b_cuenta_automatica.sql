-- ── CANDADO DE PROYECTO (no borrar) ──────────────────────────────────────
-- Este archivo es de GESTIÓN (padnttpgzuotxeipjrry). Si se pega en el SQL
-- Editor de otro proyecto, este bloque falla primero y Postgres descarta el
-- resto del script: no se aplica nada.
do $candado$
begin
  if to_regclass('public.gestion_pedidos') is null then
    raise exception 'PROYECTO EQUIVOCADO: este SQL es de GESTIÓN (padnttpgzuotxeipjrry) y aquí no existe gestion_pedidos. No se aplicó nada.';
  end if;
  if to_regclass('public.b2b_empresas') is null then
    raise exception 'Falta la migración 0019_b2b_cuentas. Correrla primero.';
  end if;
end
$candado$;
-- ─────────────────────────────────────────────────────────────────────────

-- ══════════════════════════════════════════════════════════════════════════
-- 0024 · Cuenta empresa automática al emitir una factura (29-10-2026)
--
-- Hasta ahora la cuenta la abría una persona («+ Empresa» o el aviso al
-- escribir el RUT) y la app solo sumaba facturas a cuentas existentes. En la
-- primera semana se facturó a dos empresas nuevas y nadie abrió la cuenta,
-- así que no sumaron nada. Decisión del dueño: cuando sale una FACTURA desde
-- Finanzas a un RUT de EMPRESA (parte numérica ≥ 50.000.000: los que empiezan
-- en 5, 6, 7, 8 o 9), la base crea la cuenta sola. Las personas naturales con
-- factura (RUT bajo 50 millones) siguen abriéndose a mano.
--
-- La razón social se saca de gestion_finanzas (data->>'razon_social'), que es
-- donde la escribe la app al cargar la venta; gestion_documentos.cliente trae
-- el nombre de la persona, que queda como contacto. Al insertar la empresa
-- dispara tr_b2b_vincular_documentos, que engancha todas sus facturas.
--
-- Relleno: crea las cuentas de las facturas ya emitidas a RUT de empresa sin
-- cuenta (al 29-10 eran 4: folios 181 a 185). Idempotente.
--
-- ROLLBACK: volver a crear b2b_desde_documento() con el texto de 0019 (sección
-- «Factura emitida desde la app»). Las cuentas creadas se pueden desactivar
-- con activa = false; no hace falta borrarlas.
-- ══════════════════════════════════════════════════════════════════════════

-- ¿Es RUT de empresa? Parte numérica desde 50.000.000.
create or replace function public.b2b_es_rut_empresa(p text)
returns boolean language sql immutable as $$
  select case when public.b2b_norm_rut(p) is null then false
              else split_part(public.b2b_norm_rut(p), '-', 1)::bigint >= 50000000 end
$$;

create or replace function public.b2b_desde_documento()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_rut text;
  v_emp bigint;
  v_fin jsonb;
begin
  if new.tipo <> 'FACTURA' then return new; end if;
  v_rut := public.b2b_norm_rut(new.rut);
  if v_rut is null then return new; end if;

  select id into v_emp from public.b2b_empresas where rut = v_rut and activa;

  -- Empresa sin cuenta: se abre sola (solo RUT de empresa; las personas no).
  if v_emp is null and public.b2b_es_rut_empresa(v_rut)
     and not exists (select 1 from public.b2b_empresas where rut = v_rut) then
    select f.data into v_fin from public.gestion_finanzas f where f.num = new.num;
    insert into public.b2b_empresas (rut, razon_social, contacto, celular, email, giro, notas, creado_por)
    values (v_rut,
            coalesce(nullif(btrim(v_fin->>'razon_social'), ''), nullif(btrim(new.cliente), ''), 'Empresa ' || v_rut),
            nullif(btrim(new.cliente), ''),
            nullif(btrim(v_fin->>'celular'), ''),
            coalesce(nullif(btrim(new.email), ''), nullif(btrim(v_fin->>'email'), '')),
            nullif(btrim(v_fin->>'giro'), ''),
            'Cuenta abierta sola al emitir la factura' || coalesce(' ' || new.folio, '') || ' del pedido ' || new.num,
            new.creado_por)
    on conflict (rut) do nothing
    returning id into v_emp;
    -- tr_b2b_vincular_documentos ya enganchó esta factura; lo de abajo solo la actualiza.
    if v_emp is null then select id into v_emp from public.b2b_empresas where rut = v_rut; end if;
  end if;

  if v_emp is null then return new; end if;
  insert into public.b2b_compras (empresa_id, fecha, monto, tipo, detalle, folio, pedido, origen, documento_id, anulada, creado_por)
  values (v_emp, coalesce(new.fecha, current_date), coalesce(new.monto, 0), 'FACTURA',
          coalesce(new.producto, new.detalle), new.folio, new.num, 'app', new.id, new.anulada, new.creado_por)
  on conflict (documento_id) where documento_id is not null do update
    set fecha = excluded.fecha, monto = excluded.monto, detalle = excluded.detalle,
        folio = excluded.folio, anulada = excluded.anulada, empresa_id = excluded.empresa_id;
  return new;
end $$;

-- ── Relleno: empresas que ya tienen factura emitida por la app y no tienen cuenta ──
insert into public.b2b_empresas (rut, razon_social, contacto, celular, email, giro, notas, creado_por)
select distinct on (public.b2b_norm_rut(d.rut))
  public.b2b_norm_rut(d.rut),
  coalesce(nullif(btrim(f.data->>'razon_social'), ''), nullif(btrim(d.cliente), ''), 'Empresa ' || public.b2b_norm_rut(d.rut)),
  nullif(btrim(d.cliente), ''),
  nullif(btrim(f.data->>'celular'), ''),
  coalesce(nullif(btrim(d.email), ''), nullif(btrim(f.data->>'email'), '')),
  nullif(btrim(f.data->>'giro'), ''),
  'Cuenta abierta sola (relleno 0024) por la factura ' || coalesce(d.folio, '?') || ' del pedido ' || d.num,
  d.creado_por
from public.gestion_documentos d
left join public.gestion_finanzas f on f.num = d.num
where d.tipo = 'FACTURA' and not d.anulada
  and public.b2b_es_rut_empresa(d.rut)
  and not exists (select 1 from public.b2b_empresas e where e.rut = public.b2b_norm_rut(d.rut))
order by public.b2b_norm_rut(d.rut), d.fecha desc nulls last, d.id desc
on conflict (rut) do nothing;

-- Registro en el panel (Database → Migrations). Sin CLI hay que hacerlo a mano,
-- con una etiqueta de cita que NO aparezca en este archivo (ver CLAUDE.md).
