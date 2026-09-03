-- El script de carga piloto (0011) escribió 'Detalle no disponible' en item_nombre
-- cuando Wasabil no traía nombre de línea, en vez de dejarlo NULL como corresponde
-- (glosa sí quedó NULL en esos mismos casos). Corrige el dato de origen para que el
-- filtro "sin ítem/glosa" de la vista de Recibidos las detecte.
update documentos_recibidos_lineas
set item_nombre = null
where item_nombre = 'Detalle no disponible';
