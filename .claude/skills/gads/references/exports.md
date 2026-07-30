# Qué exportar y desde dónde

Regla general: **últimos 90 días, con comparación a los 90 anteriores**. En Google
Ads, cada informe se descarga desde el ícono de descarga arriba a la derecha →
CSV (Excel). Segmenta por mes cuando el informe lo permita: sin eje temporal no se
detecta deriva.

## Google Ads — obligatorios

| # | Informe | Ruta en la UI | Columnas que no pueden faltar |
|---|---------|---------------|-------------------------------|
| 1 | Campañas | Campañas → Campañas | Tipo de campaña, Estrategia de puja, Coste, Impresiones, Clics, CTR, CPC medio, Conversiones, Valor de conversión, Coste/conv., % de conv., **IS de búsqueda**, **IS perdido (presupuesto)**, **IS perdido (ranking)** |
| 2 | Grupos de anuncios | Campañas → Grupos de anuncios | Las mismas + campaña padre |
| 3 | Palabras clave | Campañas → Audiencias, keywords y contenido → Palabras clave de búsqueda | Keyword, Tipo de concordancia, **Nivel de calidad**, **CTR esperado**, **Relevancia del anuncio**, **Experiencia de la página de destino**, Coste, Conv., Valor conv. |
| 4 | **Términos de búsqueda** | Misma sección → pestaña Términos de búsqueda | Término, Tipo de concordancia, Campaña, Coste, Clics, Conv., Valor conv. |
| 5 | Anuncios RSA | Campañas → Anuncios → tabla de anuncios | Estado, Eficacia del anuncio, Coste, Conv. — y aparte el **rendimiento de recursos** (clic en "Ver recursos": títulos/descripciones con etiqueta Baja/Buena/Óptima) |
| 6 | PMax | Campañas → la campaña PMax → Grupos de recursos + Estadísticas → Términos de búsqueda / categorías | Grupo de recursos, Coste, Conv., Valor conv.; categorías de búsqueda con volumen |
| 7 | Estadísticas de subasta | Campañas → seleccionar campañas → Estadísticas → Estadísticas de subasta | Dominio, Cuota de impresiones, Superposición, Posición superior, Cuota de la parte superior |
| 8 | Segmentos | Campañas → Segmentar por Dispositivo / Hora y día; y Ubicaciones → Informe de ubicaciones | Coste, Conv., Coste/conv. por segmento |
| 9 | Historial de cambios | Herramientas → Historial de cambios, 90 días | Fecha, Usuario, Tipo de cambio, Descripción |

## Google Ads — capturas de pantalla (no exportables)

- **Objetivos → Conversiones → Resumen**: nombre de cada acción, categoría,
  Fuente, **contabilización (todas / una)**, **ventana de conversión**,
  **Primaria vs Secundaria**, conversiones de los últimos 30 días.
- **Objetivos → Conversiones → Configuración**: modelo de atribución, enhanced
  conversions, consent mode.
- **Recomendaciones**: la pantalla completa con el optimization score (solo como
  inventario de lo que Google sugiere — no como objetivo).
- **Herramientas → Vinculación de cuentas**: estado del enlace con GA4, Merchant
  Center, Business Profile.

## Fuera de Google Ads

- **Search Console** → Rendimiento → Resultados de búsqueda: rango 16 meses,
  exportar Consultas y Páginas (clics, impresiones, CTR, posición media).
- **GA4** → Adquisición → Adquisición de tráfico, 90 días, por canal y por
  campaña; y el informe de conversiones por canal.
- **Merchant Center** (si hay Shopping) → Diagnóstico de productos: productos
  activos, rechazados, con advertencia, y el detalle de errores.
- **Business Profile** → Rendimiento: búsquedas de marca vs. descubrimiento,
  llamadas, solicitudes de indicaciones, clics al sitio.

## Casa Zaru — dato específico del negocio

La conversión que importa no está en Google: es **cotización → venta cerrada**,
que vive en el panel de seguimiento. Para cualquier conclusión sobre calidad de
lead hay que cruzar los términos de búsqueda con la tasa de cierre real por
origen. Si ese cruce no está disponible, la auditoría solo puede opinar sobre
volumen y coste de cotización, no sobre calidad — y hay que decirlo.
