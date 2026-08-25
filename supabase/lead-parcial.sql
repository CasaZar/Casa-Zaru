-- ══════════════════════════════════════════════════════════════
-- Casa Zaru · CAPTURA DEL LEAD ANTES DE LA PÁGINA DE VALOR
--
-- Problema que resuelve:
--   Hoy la cotización se guarda recién al llegar a la pantalla de precios (s3).
--   El cliente escribe su nombre y su WhatsApp en el paso 2, pero si abandona
--   en la página intermedia ("Tu pieza, hecha a mano") ese contacto se pierde:
--   no queda en la tabla ni en la cola de seguimiento del panel.
--
-- Cómo lo resuelve:
--   El paso 2 inserta una fila incompleta (nombre + contacto + producto, sin
--   totales) usando el permiso de INSERT que el público YA tiene. Al llegar al
--   paso 3, la misma pestaña completa esa fila con los totales y el link.
--
-- Por qué NO se agrega una política de UPDATE para anon:
--   Eso dejaría que cualquiera con la clave pública editara CUALQUIER
--   cotización (montos, contactos, estado de venta). En vez de eso se usa una
--   función SECURITY DEFINER acotada, igual que get_quote_link y
--   next_quote_number: el público solo puede hacer UNA cosa muy específica.
--
-- Candados de la función:
--   1. Pide un token aleatorio que solo conoce la pestaña que creó la fila.
--   2. Solo toca filas que sigan marcadas como incompletas → una cotización ya
--      cerrada no se puede reescribir, ni siquiera con el token.
--   3. Solo escribe 4 campos. No puede tocar estado, monto_cierre, ni nada
--      del seguimiento comercial.
--
-- Pegar completo en Supabase → proyecto "Cotizador Interno"
-- (cmxqorsyxoltrakxawro) → SQL Editor → Run.
-- NO tiene relación con el proyecto de Gestión ni con la tabla de Producción.
-- ══════════════════════════════════════════════════════════════

-- ── 1. Columnas nuevas ──
-- lead_incompleto: marca la fila como "todavía sin precios". El panel la usa
-- para distinguir un lead que se cayó en la página de valor de una cotización
-- terminada. Por defecto false, así TODAS las filas que ya existen quedan
-- correctamente marcadas como completas, sin tener que tocarlas.
alter table cotizaciones
  add column if not exists lead_incompleto boolean not null default false;

-- completar_token: secreto de un solo uso que la pestaña del cliente guarda en
-- memoria (nunca viaja en la URL ni se muestra). Sin él no se puede completar
-- la fila, aunque se conozca el número de cotización.
alter table cotizaciones
  add column if not exists completar_token uuid;

-- Índice para que la búsqueda por token sea inmediata. Parcial: solo indexa las
-- filas que están pendientes, que son pocas y de vida corta.
create index if not exists idx_cotizaciones_completar_token
  on cotizaciones (completar_token)
  where lead_incompleto = true;

-- ── 2. Función para completar la cotización ──
-- Devuelve true si completó la fila; false si el token no existe o si esa
-- cotización ya estaba cerrada.
--
-- Contrato para el lado JS (importante, evita filas duplicadas):
--   · Hay token y devuelve true  → listo.
--   · Hay token y devuelve false → la fila YA quedó completa (p. ej. un reintento
--     después de un corte de red). NO insertar: sería una fila duplicada.
--   · No hay token (link compartido, o falló el insert del paso 2)
--                                → recién ahí se hace el insert normal de siempre.
create or replace function completar_cotizacion(
  tok      uuid,
  t_bajo   int,
  t_medio  int,
  t_alto   int,
  lnk      text
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  filas int;
begin
  if tok is null then
    return false;
  end if;

  update cotizaciones
     set total_bajo      = t_bajo,
         total_medio     = t_medio,
         total_alto      = t_alto,
         link            = coalesce(lnk, link),
         lead_incompleto = false,
         completar_token = null      -- se quema el token: sirve una sola vez
   where completar_token = tok
     and lead_incompleto = true;

  get diagnostics filas = row_count;
  return filas > 0;
end
$$;

grant execute on function completar_cotizacion(uuid, int, int, int, text) to anon;

-- ── 3. Verificación (opcional, para correr después y confirmar que quedó bien) ──
-- Debe devolver 0 filas incompletas justo después de aplicar este script:
--   select count(*) from cotizaciones where lead_incompleto;
--
-- Y con el cotizador ya actualizado, para ver los leads que se cayeron en la
-- página de valor (el dato nuevo que hoy se pierde):
--   select numero, cliente, contacto, producto, fecha_creacion
--     from cotizaciones
--    where lead_incompleto
--    order by fecha_creacion desc;
