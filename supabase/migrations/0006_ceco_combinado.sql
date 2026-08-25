-- ══════════════════════════════════════════════════════════════════════════
-- MIGRACIÓN 0006 · CENTROS DE COSTO PARA PEDIDOS DE DOS MADERAS
--
-- PROYECTO SUPABASE: padnttpgzuotxeipjrry (el de la Gestión)
--
-- El catálogo de la 0005 tiene un CECO por especie, así que un pedido mitad
-- Coihue mitad Raulí no tenía dónde caer: cecoSugerido() se quedaba con la
-- especie de más m² y le cargaba TODO el consumo a esa, ensuciando su costo.
--
-- Se agregan los dos combinados que faltaban, uno por rama:
--
--   Mader2Tipo26  dos o más maderas, sin fierro
--   Mixto2Tipo26  dos o más maderas, con fierro
--
-- El código va en 12 caracteres exactos como todos los demás (el check de
-- centros_costo lo hace cumplir): "2Tipo" ocupa el mismo slot de 5 caracteres
-- que Orego, Casta o Coihu.
--
-- `especie` va en null a propósito. No son una especie, y así la rama por
-- especie de cecoSugerido() —que filtra por `c.especie && _normMad(c.especie)
-- === esp`— no los pesca por accidente; se buscan por código.
--
-- Pegar en Supabase → SQL Editor → Run. Es idempotente.
-- ══════════════════════════════════════════════════════════════════════════

insert into centros_costo (codigo, nombre, tipo, especie, orden) values
  ('Mader2Tipo26','Madera combinada','MADER', null,  8),
  ('Mixto2Tipo26','Mixto combinado', 'MIXTO', null, 18)
on conflict (codigo) do nothing;

comment on table centros_costo is
  'CECOs. El código va en 12 caracteres exactos por convención de la empresa. Los *2Tipo26 son los pedidos de dos o más maderas.';


-- ── Registro de la migración ──────────────────────────────────────────────
-- Al aplicar a mano hay que insertar la fila acá también, si no Database →
-- Migrations no la ve. La versión se guarda como TEXTO: los ceros a la
-- izquierda no son adorno.
--
--   insert into supabase_migrations.schema_migrations (version, name, statements)
--   values ('0006', 'ceco_combinado', array[$mig$ <contenido de este .sql> $mig$]);
