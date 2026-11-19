---
name: revision-starken
description: Revisión semanal de lo que cobra Starken — compara lo que Starken cobra hoy por cada orden de flete (OF) contra el precio con que se emitió desde la Gestión, detecta bultos re-medidos, OF perdidas o «cerradas con problema» que igual se cobran y envíos manuales cobrados por volumen, y lo deja en «Mi día» con el reclamo listo para copiar. Se corre con Starken PRO abierto en el Chrome del usuario. Actívala cuando el usuario pida "revisa Starken", "diferencias de Starken", "lo cobrado por Starken", "Starken cobró de más", "/revision-starken", o cuando sea lunes y diga que dejó Starken PRO abierto.
---

# Revisión de cobros de Starken

Solo lectura. Nada se reclama ni se paga desde acá: el reclamo lo manda el usuario
(o queda como borrador de Gmail con su ok). Nunca se emite una OF para probar.

## Por qué existe

Starken mide y pesa cada bulto al recibirlo y vuelve a liquidar la OF. Hasta el 18-11-2026 la Gestión
emitía con un cubo por kilos y la diferencia aparecía recién en la factura: OF 282024446 (pedido 1599)
se emitió a $37.670 y quedó en $110.740. Además, la OF 280019113 (pedido 1570) quedó «CERRADO CON
PROBLEMA», no se entregó y se cobró igual. Desde el 18-11 la ventana de emisión usa medidas reales;
esta revisión atrapa lo que igual cambie después.

## Pasos

1. **Sesión de Starken PRO.** El usuario la abre en su Chrome (la sesión vence en pocos minutos; yo
   nunca escribo la clave). Cargar las herramientas de Chrome en un solo ToolSearch y trabajar en una
   pestaña del grupo de esta sesión (`tabs_context_mcp` con `createIfEmpty`, navegar a
   `https://www.starkenpro.cl/dashboard-pro`).

2. **Precios al emitir (Gestión, MCP de solo lectura):**
   ```sql
   select of_numero, precio_cotizado, pedido from envios_starken
   where estado = 'emitida' and of_numero is not null and created_at > now() - interval '120 days';
   ```
   Armar el mapa `{"<of>":{"p":<precio_cotizado>,"n":"<pedido>"}}`.

3. **Comparar en Starken PRO:** leer `revisar.js` (esta carpeta), reemplazar `__MAPA__` por el mapa y
   `__DESDE__` por la fecha de hace 60 días, y correrlo con `javascript_tool` en la pestaña de Starken
   PRO. Devuelve solo los avisos; si dice «SIN SESION» o «HTTP 401», pedir al usuario que vuelva a entrar.
   Reglas que aplica:
   - **perdido**: estado con PROBLEMA, SINIESTRO, EXTRAVÍO, PERDIDO o ROBO (se cobra igual).
   - **remidio**: OF emitida desde la Gestión que Starken cobra más de $1.000 sobre lo cotizado al emitir.
   - **volumen**: OF sin precio al emitir (plugin de la web o Starken PRO a mano) con kilos de volumen
     sobre 1,2 veces el peso. No es reclamo seguro: hay que ver si el bulto iba así.
   Las anuladas no cuentan.

4. **Guardar para Mi día:** escribir el JSON tal cual (con Write) en
   `G:\Mi unidad\Casa Zaru\Cerebro\starken-revision.json` (Drive, nunca el repo: trae nombres de clientes).
   `cruzar-dia.ps1` lo lee en la corrida de las 07:30 y arma el grupo «Starken cobró distinto» en el
   Cruce de datos, con «Copiar reclamo» y «Ya lo vi» por aviso. Pasados 8 días la fuente sale como vieja.
   El id del aviso lleva el monto de hoy: si Starken vuelve a cambiar el cobro, el aviso reaparece.

5. **Contar en el chat:** tabla corta (OF, pedido o destinatario, antes → ahora, diferencia, qué pasó) y
   el total por reclamar. Si piden el reclamo, armar UN borrador de Gmail a la ejecutiva de cuenta con
   todas las OF (no enviarlo). Ver `reference_starken_api.md` en la memoria para correos y cuentas.

## Límites

- El reporte de Starken PRO solo existe con la sesión del usuario: esta revisión no corre sola.
- La factura llega a fin de mes con ciclo aprox. del 21 al 20: lo reliquidado después del 20 entra en
  la del mes siguiente.
- Nunca imprimir ni guardar el token de la sesión.
