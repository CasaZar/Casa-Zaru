# Auditoría de Google — arranque

Para quien toma la auditoría. Léelo completo antes de descargar nada: el orden
importa.

## 0. Qué es esto

Una auditoría de la cuenta de Google Ads y del ecosistema Google (Search Console,
Performance Max, Merchant Center, Business Profile) hecha con la skill `/gads`,
que corre dentro de Claude Code sobre los reportes que tú exportes.

**La auditoría es de solo lectura.** No se pausa, no se cambia puja, no se
aplican recomendaciones mientras se audita. Todo cambio se decide después, con la
priorización en la mano.

## 1. Instalar la skill

La skill vive en este repo. Si ya lo tienes clonado:

```bash
git pull
```

Si no lo tienes:

```bash
git clone https://github.com/CasaZar/Casa-Zaru.git
```

Abre Claude Code **en la carpeta del repo** y escribe `/gads`. Si no aparece en
el autocompletar, cierra y vuelve a abrir Claude Code una vez: la carpeta
`.claude/skills/` recién existe después del pull y se detecta al arrancar.

Si prefieres tenerla disponible desde cualquier carpeta y no solo dentro del
repo, copia el directorio a tu carpeta personal de skills:
`~/.claude/skills/gads/` (en Windows: `C:\Users\<tu-usuario>\.claude\skills\gads\`).

## 2. Accesos que necesitas

Pídelos antes de empezar, porque algunos demoran:

- **Google Ads** — acceso de lectura como mínimo (Administración → Acceso y
  seguridad → invitar por correo). Con lectura alcanza para toda la auditoría.
- **Search Console** — propiedad de casazaru.cl, permiso de lectura.
- **Merchant Center** — solo si hay campañas de Shopping activas.
- **Google Business Profile** — la ficha de Google Maps.
- **GA4** — propiedad del sitio, lectura.

## 3. Los 4 números del negocio

Sin estos la auditoría no puede decidir si un CPA es caro o barato, porque el
techo se calcula desde el margen y no desde benchmarks de industria:

1. Ticket promedio de venta cerrada
2. Margen de contribución % — precio menos madera, herrajes, mano de obra directa
   y despacho. No es el margen bruto contable.
3. Tasa de cierre cotización → venta %
4. Días promedio entre cotización y cierre

Los dos últimos salen del panel de seguimiento. Pídelos como número real, no
estimado: la diferencia entre 15% y 25% de cierre mueve el CPA objetivo casi al
doble.

## 4. Los exports

Últimos 90 días, con comparación a los 90 anteriores. La lista completa —con la
ruta exacta de cada informe en la interfaz y las columnas que no pueden faltar—
está en `references/exports.md`.

**Si tienes poco tiempo, estos tres solos dan cerca del 70% de los hallazgos:**

1. **Términos de búsqueda**, 90 días — el más valioso de todos
2. **Campañas**, con las tres columnas de impression share: IS de búsqueda, IS
   perdido por presupuesto, IS perdido por ranking
3. **Captura de Objetivos → Conversiones**, mostrando primaria/secundaria,
   ventana de conversión y contabilización de cada acción

Deja todo en una sola carpeta.

### Alto acá si ves esto

En la pantalla de conversiones, si aparece **clic a WhatsApp, envío de formulario
o vista de página marcados como acción primaria**: detente y avísalo antes de
seguir descargando. Significa que el algoritmo lleva meses aprendiendo a comprar
el tráfico más barato que llena formularios, y el diagnóstico de toda la cuenta
cambia. Auditar el resto sobre esos datos es analizar una muestra que ya sabemos
sesgada.

## 5. Correr la auditoría

En Claude Code, dentro de la carpeta del repo:

```
/gads
```

Y le indicas la carpeta donde dejaste los exports, más los 4 números del punto 3.
La skill pide lo que falte. Si un dato no existe, dilo — va a marcar la
conclusión como supuesto en vez de inventarla.

## 6. Qué devuelve

Veredicto en 5 líneas y la oportunidad #1 con su cálculo, semáforo de los 6
niveles del método, tabla de hallazgos con evidencia numérica, priorización ICE,
3 quick wins de menos de una semana, plan 30/60/90, y la lista de lo que no se
pudo auditar con el export exacto que falta para cerrarlo.

## 7. Dos cosas que no hay que hacer

- **No aplicar las Recomendaciones de Google en bloque** ni perseguir el
  optimization score. Ese puntaje mide adopción de sugerencias, no rentabilidad.
- **No tocar la cuenta durante la auditoría.** Cambiar pujas o pausar campañas a
  mitad de la descarga contamina la comparación de periodos y dispara el
  reaprendizaje del algoritmo justo cuando estás midiendo.

## 8. El punto ciego conocido

Google no sabe cuáles de las cotizaciones se cerraron: eso vive en el panel de
seguimiento. Mientras no exista importación de conversiones offline, la auditoría
puede juzgar volumen y costo por cotización, pero **no calidad de lead**. Es una
limitación real del análisis, no un detalle — y probablemente sea una de las
recomendaciones que salgan.
