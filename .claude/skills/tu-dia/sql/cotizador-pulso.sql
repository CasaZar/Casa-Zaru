-- Cerebro Zaru · Pulso desde el COTIZADOR (cmxqorsyxoltrakxawro). Solo lectura.
-- Correr con mcp__supabase-cotizador__execute_sql. Nunca en el proyecto de la Gestión.
-- «Ayer» = día anterior en hora de Santiago. Mediana = mismo día de la semana, 8 semanas previas.
with hoy as (select (now() at time zone 'America/Santiago')::date d),
c as (select * from cotizaciones where coalesce(eliminada,false)=false),
dia as (select (fecha_creacion at time zone 'America/Santiago')::date f, count(*) n, sum(total_medio) monto from c group by 1)
select
  (select coalesce(n,0) from dia,hoy where f=hoy.d-1) cot_ayer,
  (select round(coalesce(monto,0)) from dia,hoy where f=hoy.d-1) monto_ayer,
  (select percentile_cont(0.5) within group (order by n) from dia,hoy where f in (select (hoy.d-1-7*k) from generate_series(1,8) k)) mediana_mismo_dia_8sem,
  (select count(*) from c where estado='enviada' and fecha_creacion >= now()-interval '7 days' and fecha_creacion < now()-interval '1 day'
     and not exists (select 1 from toques t where t.cotizacion_id=c.id)) sin_primer_toque,
  (select count(*) from c where estado='enviada' and total_medio>=1000000 and fecha_creacion >= now()-interval '7 days' and fecha_creacion < now()-interval '1 day'
     and not exists (select 1 from toques t where t.cotizacion_id=c.id)) sin_primer_toque_1m,
  (select round(coalesce(sum(total_medio),0)) from c where estado='enviada' and total_medio>=1000000 and fecha_creacion >= now()-interval '7 days' and fecha_creacion < now()-interval '1 day'
     and not exists (select 1 from toques t where t.cotizacion_id=c.id)) sin_primer_toque_1m_monto,
  (select count(*) from whatsapp_pendientes where deleted_at is null and estado='pendiente') whatsapp_pendientes,
  (select count(*) from c,hoy where estado='ganado' and (fecha_concretada at time zone 'America/Santiago')::date >= date_trunc('month',hoy.d)) ganadas_mes;
