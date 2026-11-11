-- Cerebro Zaru · Pulso desde la GESTIÓN (padnttpgzuotxeipjrry). Solo lectura.
-- Correr con mcp__supabase-gestion__execute_sql. Nunca en el proyecto del Cotizador.
-- saldo = total − (abono1+abono2+abono3) (igual que saldoFin() de index.html; saldo_monto es un campo muerto).
-- Documento pendiente = misma regla que _doc3Requerido/_docsListos (doc N = abono N), desde 2026-09-01.
with hoy as (select (now() at time zone 'America/Santiago')::date d),
f as (
  select num, data d,
    case when data->>'fecha' ~ '^\d{1,2}/\d{1,2}/\d{4}$' then to_date(data->>'fecha','DD/MM/YYYY') end fecha,
    coalesce(nullif(data->>'total','')::numeric,0) total,
    coalesce(nullif(data->>'abono1','')::numeric,0) a1,
    coalesce(nullif(data->>'abono2','')::numeric,0) a2,
    coalesce(nullif(data->>'abono3','')::numeric,0) a3,
    coalesce(nullif(data->>'val_prod','')::numeric,0) val_prod,
    coalesce((data->>'doc1_emitida')::boolean,false) e1,
    coalesce((data->>'doc2_emitida')::boolean,false) e2,
    coalesce((data->>'doc3_emitida')::boolean,false) e3,
    coalesce(nullif(data->>'doc2_monto','')::numeric,0) m2,
    coalesce((data->>'sin_documento')::boolean,false) sin_doc
  from gestion_finanzas
  where coalesce(nullif(data->>'tipo',''),'VENTA')='VENTA'),
s as (select f.*, total-a1-a2-a3 saldo from f),
docp as (
  select num, 1 doc, a1 monto from s, hoy where fecha >= date '2026-09-01' and not sin_doc and a1>0 and not e1
  union all select num, 2, a2 from s where fecha >= date '2026-09-01' and not sin_doc and a2>0 and not e2
  union all select num, 3, a3 from s where fecha >= date '2026-09-01' and not sin_doc and a3>0 and not e3 and not (e2 and (m2=0 or m2>=a2+a3))),
dormida as (
  select s.num, s.saldo, (p.data->>'dia_envio') dia_envio
  from s join gestion_produccion p on p.num=s.num, hoy
  where s.saldo>0 and p.data->>'dia_envio' ~ '^\d{4}-\d{2}-\d{2}$' and (p.data->>'dia_envio')::date < hoy.d)
select
  (select coalesce(sum(val_prod),0) from s,hoy where date_trunc('month',fecha)=date_trunc('month',hoy.d)) venta_mes,
  (select count(*) from s,hoy where date_trunc('month',fecha)=date_trunc('month',hoy.d)) pedidos_mes,
  (select coalesce(sum(val_prod),0) from s,hoy where fecha >= (date_trunc('month',hoy.d) - interval '1 month')::date and fecha <= (hoy.d - interval '1 month')::date) venta_mes_ant_misma_fecha,
  (select coalesce(sum(saldo),0) from s where saldo>0) por_cobrar,
  (select count(*) from s where saldo>0) pedidos_con_saldo,
  (select count(*) from docp) docs_pendientes,
  (select coalesce(sum(monto),0) from docp) docs_pendientes_monto,
  (select coalesce(sum(saldo),0) from dormida) dormida_monto,
  (select count(*) from dormida) dormida_n,
  (select json_agg(dormida order by dia_envio) from dormida) dormida_detalle,
  (select count(*) from ventas_por_cargar where estado not in ('cargada','descartada')) ventas_por_cargar;
