# Cerebro Zaru — prompt de construcción

> Pegar esto completo al abrir una sesión nueva en `C:\Users\dell\Casa Zaru - Claude`.
> Este archivo no lleva cifras ni nombres de clientes. Los datos viven en la memoria y en Drive, no aquí,
> porque el repo es público.

---

## Quién soy y qué necesito

Soy Tomás, dueño de Casa Zaru (Muvale Diseño SpA). Quiero manejar todo el negocio en **2 horas al día**:
ventas, equipo y RR. HH., finanzas, impuestos, Shopify y la web, marketing, operación y sistemas.

Necesito un **segundo cerebro** que:
1. no deje pasar nada, ni lo que se me pasa a mí ni lo que se te pasa a ti;
2. cada mañana me diga qué hacer, en qué orden y por qué;
3. encuentre los **insights que mueven la aguja**, no ruido.

El diseño de la pantalla **ya está aprobado** (boceto «Tu día», 11-11-2026). Respétalo:
- Encabezado: fecha y el foco del día en una frase.
- **Que no se pase:** alarmas con fecha, visibles desde 10 días antes.
- **Pulso, 15 min:** 6 cifras y «lo raro de hoy».
- **Decidir, 40 min:** máximo 4 cosas que solo yo puedo resolver, con cuántos días llevan esperando.
- **Equipo, 30 min:** César, Cote y taller, con el mensaje listo para mandar.
- **Crecer, 25 min:** una sola mejora terminable.
- **Todas las áreas:** semáforo de 8 áreas, cada una con su cadencia de revisión.
- **Lo fijo del mes:** calendario recurrente.
- **Cierre, 10 min:** marco lo hecho, dicto lo nuevo, y lo que se salta 5 días se decide (hacer, delegar o matar).

Celular primero (390 px), paleta y tipografías de marca, íconos de línea y no emojis, todo en español.

---

## Reglas que no se negocian

- Lee primero `CLAUDE.md`, `ESTRUCTURA.md` y `MEMORY.md`. Cumple el **contrato de confiabilidad**.
- **Solo lectura** en todas las fuentes. El cerebro no escribe en Supabase, Shopify, Klaviyo, Meta ni
  Wasabil, y no manda mensajes. Propone; yo hago o apruebo.
- **Todo número sale de una fórmula real** y queda trazable (fuente, consulta, fecha). Si un dato no se
  puede calcular, se muestra como «sin dato» y no se estima.
- **Privacidad:** nada con nombres, montos ni teléfonos en el repo. Los datos del cerebro viven en
  `G:\Mi unidad\Casa Zaru\Cerebro\`. El repo solo guarda código sin datos.
- Supabase paginado (tope de 1000 filas). Gestión y Cotizador nunca en la misma consulta.
- Nada de multi-agentes ni workflows sin preguntarme antes.
- **Construir por etapas, una a la vez.** Cada etapa termina en algo que yo pruebo, y para pasar a la
  siguiente espera mi sí.

---

## Arquitectura

### 1. Fuente de verdad: `G:\Mi unidad\Casa Zaru\Cerebro\`

| Archivo | Qué guarda |
|---|---|
| `pendientes.csv` | Columnas: `id, area, titulo, dueno (yo/César/Cote/taller/Claude/externo), origen (nota, sesión o dato, con fecha), creado, vence, proxima_revision, estado (abierto/esperando/hecho/matado/delegado), saltos, impacto_$, evidencia, ultima_verificacion`. |
| `areas.csv` | Las 8 áreas con su cadencia de revisión, la fecha de la última revisión y qué fuentes la alimentan. |
| `calendario.csv` | Obligaciones recurrentes: Previred el 13; F29 y giro del IVA postergado el 20; sueldos, comisión y cierre a fin de mes; la rutina de los lunes; la restauración mensual. |
| `insights.csv` | Columnas: `id, fecha, palanca, hallazgo, evidencia, impacto_$ (fórmula), confianza, accion, estado, resultado_a_30_dias`. |
| `bitacora.md` | Decisiones del cierre diario, con fecha. |
| `promesas-claude.csv` | Lo que **Claude** dijo que haría o verificaría y todavía no cerró. |

Todo idempotente: correr dos veces el mismo día no duplica filas (la clave es `id` + fecha).

### 2. Recolectores (solo lectura)

| Fuente | Qué aporta |
|---|---|
| Supabase Gestión (MCP) | Pedidos, finanzas, documentos, `ventas_por_cargar` y gastos. |
| Supabase Cotizador (MCP) | Cotizaciones, toques y seguimientos vencidos. |
| Shopify | Pedidos y analítica. |
| Klaviyo | Borradores, flujos y métricas. |
| Meta | Solo la cuenta oficial. |
| Gmail | Hilos sin responder y borradores sin enviar. |
| Calendar | Eventos del día. |
| Drive | Informes, cartolas, `promesas-pendientes.md` y planillas. |
| Wasabil | Documentos pendientes, en lectura. |
| Memoria de Claude | Todos los `.md`. |
| Historial de sesiones | `search_session_transcripts`. |
| Logs de tareas programadas | Para saber si de verdad corrieron. |
| `git status` | Archivos sin commit. |

Si una fuente falla, el día igual sale y esa fuente aparece en el pulso como **«no se pudo leer: X»**.
Nunca se muestra un 0 silencioso: ya nos pasó con un `[]` de RLS.

### 3. Salida

Una página privada (Artifact) con el diseño aprobado y la capacidad de base de datos, para que lo que yo
marco quede guardado y tú lo leas al día siguiente. Además, un respaldo en
`Cerebro\dias\AAAA-MM-DD.html`. Se genera de lunes a sábado a las 07:30.

---

## Barrido de olvidos (lo que se nos pasa a los dos)

Corre todos los días antes de armar «Tu día». Cada hallazgo se convierte en un pendiente o en una alarma.

**Lo que se me pasa a mí**
- Pendientes que llevan más tiempo que la cadencia de su área.
- Ciclos abiertos en las herramientas:
  - borradores de Gmail y Klaviyo sin enviar;
  - cotizaciones de monto alto sin toque;
  - ventas por cargar;
  - abonos sin documento;
  - saldos por cobrar;
  - giros del SII;
  - facturas por vencer.
- Promesas a clientes en `promesas-pendientes.md`.
- Fechas que se acercan: calendario, vencimientos de facturas y condiciones como «cobrar después de».

**Lo que se te pasa a ti (Claude)**
- **Notas huérfanas:** en la memoria, cada frase con «falta», «pendiente», «sin construir», «sin enviar»,
  «por confirmar», «después del», «cuando» o una fecha futura debe tener una fila en `pendientes.csv`.
  Si no la tiene, se crea.
- **Promesas de sesiones:** busca en el historial de sesiones de los últimos 14 días frases como «te
  aviso», «queda pendiente», «siguiente paso», «lo reviso», preguntas mías sin respuesta y botones de
  cierre que nunca se contestaron. Todo eso va a `promesas-claude.csv`.
- **Notas viejas:** una nota de memoria de más de 30 días que afirma un estado («sin enviar», «en pausa»)
  se verifica contra el dato real. Si cambió, propone corregir la nota.
- **Contradicciones** entre la memoria, el código y los datos se marcan y se resuelven con evidencia.
- **Trabajo a medias:** archivos sin commit, bocetos aprobados sin construir y ramas abiertas.
- **Automatizaciones mudas:** tareas programadas cuyo log no muestra una corrida reciente, y respaldos de
  más de 36 horas.

**Auditoría del propio cerebro (cada lunes, una línea en el pulso)**
- Cuántas alarmas resultaron falsas.
- Cuántos pendientes tienen más de 14 días.
- Cuántos se mataron.
- Mi tasa de cumplimiento de la semana.
- Qué fuentes fallaron.

Si una regla genera ruido dos semanas seguidas, propón cambiarla.

---

## Insights que mueven la aguja

**La aguja:** `utilidad = leads × conversión × ticket × margen − gastos fijos`, más **caja** (cuánta plata
hay y cuándo llega). Todo insight tiene que colgar de una de esas palancas.

**Detectores**, cada uno con su consulta reproducible:
1. **Anomalía:** el valor de hoy o de la semana frente a la mediana de 8 semanas, en cotizaciones,
   ventas, ticket, tiempo al primer toque, CPC/CPA y aperturas.
2. **Embudo por producto y canal:** dónde cae la conversión, y su cambio contra el mes anterior.
3. **Plata dormida:** cotizaciones de monto alto abiertas, saldos por cobrar, reembolsos, cupones con
   saldo fantasma y ventas sin cargar.
4. **Fugas de margen:** materiales como % de la venta, costo por m² contra el estándar, fletes contra la
   venta, gastos fijos que crecen y suscripciones que nadie usa.
5. **Riesgos:**
   - caja frente a lo que vence en 30 días (IVA y sueldos);
   - concentración en un canal;
   - reportes o bloqueos en WhatsApp;
   - dependencia de una sola persona.
6. **Lo que funciona y no se escala:** el canal, la pieza o el mensaje con mejor conversión que recibe
   poco volumen.

**Filtro** antes de mostrar un insight:
- Puntaje = `impacto_$ mensual × confianza ÷ esfuerzo (horas)`.
- Se muestra solo si es **nuevo** (no repetido en 14 días), **accionable en menos de 1 día**, trae
  **evidencia** (consulta + cifra) y su impacto se calculó con fórmula.
- Máximo **1 al día** en «Crecer» y **3 el lunes** en «Foco de la semana».
- Lo demás queda en `insights.csv` sin molestar.

**Aprendizaje:** a los 30 días, cada insight que se actuó se mide contra su predicción. Anota el resultado
y ajusta la confianza de ese detector. Un detector que no acierta nunca se apaga.

---

## Etapas (una por vez, con mi sí entre cada una)

1. **Inventario.** Barrido completo de la memoria, el historial de sesiones, el repo y Drive para crear
   `pendientes.csv`, `areas.csv` y `calendario.csv`. Me lo muestras agrupado por área para que yo mate,
   delegue o confirme. Sin esto no hay cerebro.
2. **`/tu-dia` manual.** Una skill del proyecto que arma la página con los datos reales cuando yo la
   llamo. Se prueba a 390 px.
3. **Cierre diario.** La página guarda lo que marco; `/tu-dia` lo lee, actualiza `pendientes.csv`, cuenta
   los saltos y escribe la bitácora.
4. **Programado.** 07:30 de lunes a sábado. Revisar su log al día siguiente, porque las tareas siempre
   devuelven 0.
5. **Detectores de insights**, de a uno, partiendo por **plata dormida** y **anomalías**.
6. **Lunes:** foco de la semana y auditoría del cerebro.

Empieza por la etapa 1. Antes de escribir cualquier archivo, dime qué fuentes pudiste leer y cuáles no.
