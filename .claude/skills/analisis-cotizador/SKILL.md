---
name: analisis-cotizador
description: Análisis semanal del Cotizador de Casa Zaru — qué se está cotizando (productos, medidas, modelos, ticket) y cómo va el seguimiento de los vendedores (tiempo al primer toque, cotizaciones sin tocar, ballenas abandonadas). Actívala cuando el usuario pida "análisis del cotizador", "cómo viene el cotizador", "qué se está cotizando", "cómo va el seguimiento" o invoque /analisis-cotizador.
---

# Análisis semanal del Cotizador

El objetivo **no** es un tablero de métricas. Es salir con **dos o tres cambios
concretos** que se puedan hacer esta semana. Si el análisis no termina en una
recomendación accionable, no sirvió.

## 0. De dónde salen los datos

Los baja la tarea local de los lunes 08:00 (`.claude/analisis/snapshot-cotizador.ps1`),
que usa la llave `service_role` guardada fuera del repo. **Nunca consultes Supabase
directo con la llave pública para esto** — no tiene permiso de lectura y vas a
recibir `[]` sin error, que parece "no hay datos" cuando en realidad hay muchos.

```
Get-Content C:\Users\dell\.casazaru\snapshots\ultimo.txt   # ruta del snapshot más reciente
```

Lee el `resumen.json` de esa carpeta. Si necesitas detalle que no está agregado,
está el crudo en `crudo\cotizaciones.json`, `crudo\lineas.json` y `crudo\toques.json`.

**Si el snapshot tiene más de 8 días o no existe**, dilo de entrada y ofrece correr
el script a mano antes de analizar — un análisis sobre datos viejos es peor que
ninguno.

## 1. Antes de concluir nada: mira cuánta base hay

En `totales`:

- `lineas_guardadas` en 0 o muy bajo respecto de `cotizaciones_historicas` significa
  que el detalle de piezas recién empezó a guardarse (la función `guardar_lineas`
  se creó el 21-08-2026; antes las líneas se descartaban). **Las secciones de
  medidas y modelos solo valen desde esa fecha** — dilo en vez de presentar
  conclusiones sobre 4 cotizaciones.
- Con menos de ~15 cotizaciones en la semana, no hables de tendencias. Describe
  lo que pasó y espera a tener base.

Nunca presentes un porcentaje sin el número absoluto al lado. "Subió 50%" sobre
2 cotizaciones no es información.

## 2. Qué se cotiza

De `semana` vs `semana_anterior`, `medidas_top`, `modelos_top`, `vidrio`, `canal`.

Lo que hay que buscar, en orden de utilidad:

- **Medidas repetidas.** Si una misma medida aparece muchas veces en un producto,
  es candidata a medida estándar en la web (o a stock). Ese es el hallazgo más
  accionable de todo el análisis.
- **Modelos que nadie cotiza.** Un modelo de puerta o mesa con cero cotizaciones
  varias semanas seguidas: o está mal presentado (foto, orden en la grilla) o
  sobra del catálogo. Revísalo contra el orden en que aparece en el cotizador.
- **Producto que cae contra la semana anterior**, cruzado con `canal`: si cayó
  justo el que tiene landing propia, sospecha del botón de esa landing antes que
  de la demanda.
- **Ticket promedio** por producto. Si baja, mira si es mezcla (se cotizan piezas
  más chicas) o si alguien está cotizando mal.

## 3. Seguimiento de vendedores

De `primer_toque_horas`, `sin_tocar`, `toques_por_vendedor`, `estados`.

- **`primer_toque_horas.mediana` es el número que más mueve la conversión.** El
  compromiso que el cotizador le promete al cliente es "dentro del día hábil".
  Si la mediana pasa de 24 h, eso es el titular del reporte, por encima de
  cualquier otra cosa.
- **`p90` importa tanto como la mediana**: una mediana buena con un p90 de 5 días
  significa que hay clientes olvidados aunque el promedio se vea bien.
- **`sin_tocar` se cuenta por CLIENTE, no por cotización.** Un cliente que pidió
  3 cotizaciones y recibió un toque en una sola está siendo atendido. Contar por
  cotización infla el número más del doble (507 "cotizaciones" cuando eran 235
  clientes) y además deja de ser comparable con el panel, que agrupa por
  cliente. Si alguna vez ves un número que no cuadra con lo que el usuario ve en
  pantalla, revisa primero esto.
- **Usa `sin_tocar.por_edad` antes que el total.** El panel solo muestra la cola
  del día; lo de más de 21 días vive en la pestaña **Backlog**. Decir "hay 235
  sin tocar" cuando en pantalla se ven 5 confunde. Di cuántos son de esta semana
  y cuántos son backlog viejo.
- **En el top, `monto` es la suma de TODAS las cotizaciones abiertas del
  cliente** — exagera cuando cotizó la misma pieza varias veces probando
  medidas, que es lo normal. Para dimensionar la venta usa `monto_max`, la
  cotización individual más grande. Menciona las dos si difieren mucho.
- **`toques_por_vendedor`**: si un vendedor tiene 0 toques la semana, dilo sin
  rodeos pero sin acusar — puede estar de vacaciones.

Ojo: `hecho_por` queda en null cuando el toque se marcó sin sesión iniciada. Si
ves mucho "(sin registrar)", el dato por vendedor no es confiable esa semana y
hay que decirlo.

## 4. Cadencia

La cadencia definida es **1-3-7-14-30 días**. Con `crudo\toques.json` puedes
contar, por cotización viva, cuántos toques lleva y cuántos días pasaron desde el
último, y compararlo con el escalón que le tocaría. Reporta cuántas están
atrasadas, no el detalle de cada una.

## 5. El entregable

Máximo una pantalla. En este orden:

1. **El titular** — una sola frase con lo más importante de la semana.
2. **Qué se cotizó** — tabla corta: producto, cotizaciones, monto, variación.
3. **Seguimiento** — primer toque (mediana y p90), cuántas sin tocar y por cuánta plata.
4. **Para hacer esta semana** — 2 o 3 acciones concretas, cada una con el dato que
   la respalda. Si una acción es un cambio en el cotizador, di qué archivo y qué
   parte.
5. **Lo que no se puede concluir todavía** — sé explícito con lo que falta base.

No adornes. Si la semana fue tranquila y no hay nada que cambiar, dilo en dos
líneas y termina.
