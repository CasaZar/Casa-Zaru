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

-- ══════════════════════════════════════════════════════════════════
-- EMBUDO: de qué anuncio viene cada visita (12-11-2026)
--
-- Proyecto: cmxqorsyxoltrakxawro («ZARU · Cotizador»). NO es la Gestión.
-- Correr en el SQL Editor de ese proyecto. Idempotente.
--
-- Hasta hoy la columna canal hacía dos trabajos: por dónde entró la persona
-- (web, link compartido, link de vendedor) y qué anuncio la trajo (el
-- utm_source: ig, fb, facebook, google, klaviyo…). Desde el 28-10 la tienda
-- (snippet cz-origen) agrega el utm a todo link al cotizador, así que un
-- tercio de las visitas web quedó como «ig» o «fb» y el embudo «web» pareció
-- caer a la mitad.
--
-- Ahora van separados:
--   canal    por dónde entró: 'web', 'link' o el ?src= de un vendedor
--   fuente   utm_source (en minúsculas): ig, fb, facebook, google, klaviyo…
--            sin utm: 'google_ads' si trae gclid/gbraid/wbraid, 'meta' si
--            trae solo fbclid
--   campana  utm_campaign: la campaña del anuncio
--   anuncio  utm_content: el anuncio puntual (Meta manda el nombre del anuncio)
--   medio    utm_medium: la ubicación (Instagram_Reels, Facebook_Stories…)
-- El cotizador las llena desde el commit que acompaña a este archivo. Antes de
-- correr esto, el cotizador NO las manda (si las mandara sin las columnas,
-- PostgREST rechazaría el insert entero y se perdería el evento).
--
-- 2) TRASPASO de lo viejo: las filas cuyo canal es un utm_source (no 'web',
-- no 'link', no un vendedor) pasan ese valor a fuente y quedan canal = 'web'.
-- Al 12-11 son 997 filas (desde el 03-09): ig 412, fb 272, facebook 171,
-- an 47, google 46, klaviyo 44, th 2, meta 2, «3D=» 1. Vendedores que se
-- respetan: cesar/k7m2, jepe/p4x9 (VENDEDORES en el cotizador).
-- Las filas viejas no tienen campaña ni anuncio: ese dato no se guardaba.
--
-- ROLLBACK (deja todo como antes de este archivo):
--   update public.embudo_eventos set canal = fuente
--    where fuente is not null and canal = 'web';
--   alter table public.embudo_eventos
--     drop column if exists fuente, drop column if exists campana,
--     drop column if exists anuncio, drop column if exists medio;
--   (y revertir el commit del cotizador ANTES de borrar las columnas)
-- ══════════════════════════════════════════════════════════════════

alter table public.embudo_eventos
  add column if not exists fuente  text,
  add column if not exists campana text,
  add column if not exists anuncio text,
  add column if not exists medio   text;

-- el anon escribe acá: que no pueda mandar textos gigantes
alter table public.embudo_eventos drop constraint if exists embudo_eventos_origen_largo;
alter table public.embudo_eventos
  add constraint embudo_eventos_origen_largo
  check (coalesce(length(fuente), 0)  <= 100
     and coalesce(length(campana), 0) <= 300
     and coalesce(length(anuncio), 0) <= 300
     and coalesce(length(medio), 0)   <= 100);

-- traspaso de lo viejo (idempotente: después del primer run ya no calza nada)
update public.embudo_eventos
   set fuente = lower(canal),
       canal  = 'web'
 where canal is not null
   and canal not in ('web', 'link', 'cesar', 'k7m2', 'jepe', 'p4x9')
   and fuente is null;

-- comprobación: debe quedar solo web / link / vendedores en canal
select canal, fuente, count(*) as filas
  from public.embudo_eventos
 group by 1, 2
 order by 3 desc;
