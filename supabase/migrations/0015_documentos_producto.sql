-- El producto que salió impreso en el documento.
--
-- Va aparte de `detalle` a propósito, porque en el DTE son dos líneas
-- distintas: `producto` es el nombre del ítem ("Cubierta para escritorio") y
-- `detalle` la glosa del pago ("Abono", "Saldo final"). Y va aparte del
-- producto del pedido en Producción porque no siempre coinciden: se factura
-- "mesa de reunión" lo que en el taller es "Mesa Lago Llanquihue".
--
-- Sin esta columna, el historial por cliente mostraría el monto y el folio
-- pero no qué se le facturó, que es lo primero que uno quiere ver.

alter table public.gestion_documentos add column if not exists producto text;
