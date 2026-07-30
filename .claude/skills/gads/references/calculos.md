# Cálculos obligatorios

Corre todos los que los datos permitan **antes** de escribir hallazgos. Cada fila
de la tabla de hallazgos debe citar uno de estos números como evidencia.

## 1. CPA máximo permitido (el número que define "caro")

```
Margen de contribución por venta = Ticket promedio × Margen %
CPA máximo por venta            = Margen de contribución por venta
CPA máximo por cotización       = Margen de contribución × Tasa de cierre cotización→venta
CPA objetivo                    = CPA máximo por cotización × (1 − buffer)   [buffer 30-40%]
```

Ejemplo: ticket $800.000, margen 35% ⇒ $280.000 de contribución. Tasa de cierre
20% ⇒ el equilibrio está en **$56.000 por cotización**; con buffer 35%, el
objetivo operativo es ~$36.000. Todo juicio de "CPA alto/bajo" se compara contra
este número, nunca contra un benchmark de industria.

## 2. tROAS de equilibrio

```
ROAS de equilibrio = 1 / Margen de contribución %
```

Margen 35% ⇒ equilibrio en 2,86x sobre ingreso. Un tROAS configurado por debajo
de eso es una orden explícita de perder plata; uno muy por encima asfixia el
volumen. Compara siempre el tROAS configurado contra este número y contra el ROAS
que la cuenta realmente consigue.

## 3. Split brand vs non-brand

Del informe de términos de búsqueda, separa los términos que contienen la marca
(y sus variantes y errores de tipeo) del resto. Recalcula por separado: coste,
conversiones, CPA y ROAS.

```
% de conversiones atribuidas a marca = Conv. brand / Conv. total
ROAS non-brand = Valor conv. non-brand / Coste non-brand
```

Si el ROAS non-brand es sustancialmente peor que el agregado, el rendimiento de
la cuenta está sostenido por demanda que ya existía. Ese es el diagnóstico de
incrementalidad, y suele ser la oportunidad #1.

En PMax verifica si hay exclusión de marca activa. Si no la hay, declara el ROAS
de esa campaña **no interpretable** hasta separarlo.

## 4. N-gramas de desperdicio

Descompón cada término de búsqueda en unigramas y bigramas; agrega coste,
clics y conversiones por n-grama.

```
Umbral de desperdicio: n-grama con Coste > 2 × CPA objetivo y 0 conversiones
```

Ordena por coste descendente y reporta el top 10. Cada uno es un candidato a
negativo, con el monto exacto que libera al mes. Revisa también n-gramas con
conversiones pero CPA > 2× el objetivo: esos no se niegan, se aíslan.

Señales de intención incompatible a buscar explícitamente: `gratis`, `barato`,
`usado`, `segunda mano`, `curso`, `cómo hacer`, `planos`, `DIY`, `empleo`,
`trabajo`, `sueldo`, nombres de competidores, ciudades fuera del área de
despacho.

## 5. Lectura del impression share

```
IS + IS perdido (presupuesto) + IS perdido (ranking) ≈ 100%
```

- **IS perdido por presupuesto alto** ⇒ hay demanda rentable sin comprar. Si el
  CPA de esa campaña está bajo el objetivo, subir presupuesto es la acción de
  mayor retorno y menor riesgo de la cuenta. Cuantifica:
  `Conversiones adicionales estimadas = Conv. actuales × (IS perdido presupuesto / IS actual)`
  y márcalo como estimación lineal, que es optimista.
- **IS perdido por ranking alto** ⇒ problema de calidad o de puja. Cruza con los
  tres componentes del Nivel de calidad para decidir cuál de los dos es.
- **IS alto con CPA sobre el objetivo** ⇒ estás comprando toda la subasta a
  pérdida; el problema es la puja, no la cobertura.

## 6. Umbral de señal por campaña

```
Conversiones últimos 30 días, por campaña
< 15  ⇒ smart bidding no puede funcionar; la estrategia es el hallazgo
15-30 ⇒ tCPA inestable; esperable volatilidad alta de CPA
30+   ⇒ tCPA viable
50+   ⇒ tROAS viable
```

Si una campaña con tCPA tiene menos de 15 conversiones/mes, ese es un hallazgo de
severidad alta en el Nivel 4, y muy probablemente arrastra un problema de
consolidación de estructura del Nivel 2.

## 7. Ventana de conversión vs. ciclo real

```
Si Ventana de conversión configurada < Días promedio cotización→venta:
  % de ventas invisibles para el algoritmo ≈ % de cierres que ocurren después de la ventana
```

Con ciclo largo y ventana corta, el algoritmo optimiza sobre una muestra sesgada
hacia los cierres rápidos, que casi nunca son los de mayor ticket. Es un hallazgo
de Nivel 1, severidad crítica, y bloquea la interpretación de todo lo demás.

## 8. Higiene de conversiones (Nivel 1)

Revisa la pantalla de conversiones y responde explícitamente:

- ¿Hay más de una acción **primaria** contando el mismo evento? (doble conteo)
- ¿Hay conversiones importadas de GA4 **y** el tag nativo de Ads midiendo lo
  mismo?
- ¿La contabilización es "todas" donde debería ser "una"? (formularios repetidos
  inflan el volumen)
- ¿Hay acciones primarias de intención débil — clic a WhatsApp, vista de página,
  scroll — mezcladas con las de negocio? El algoritmo optimiza a lo primario:
  cada micro-conversión primaria le enseña a comprar tráfico barato de baja
  intención.
- ¿Existe importación de conversiones offline? Si no, el techo de la cuenta es
  estructural, no de gestión.

## 9. Canibalización Ads ↔ orgánico

Cruza consultas de Search Console con términos de búsqueda de Ads:

```
Consultas con posición orgánica media ≤ 3 y gasto en Ads > 0
```

Reporta el gasto acumulado en esas consultas. No es automáticamente desperdicio
—defenderse en la subasta puede ser correcto— pero es dinero que exige
justificación explícita, y es candidato natural a un test de holdout geográfico.
