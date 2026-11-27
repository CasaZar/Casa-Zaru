# Referencia de /carrusel: fuentes verificadas, accesos, SQL y mitos

Este archivo está en el repo, que es **público**. Aquí van solo datos externos y públicos.
Las cifras del negocio (cotizaciones, ventas, maderas vendidas) van en `G:\Mi unidad\Casa Zaru\Contenido\Carruseles\`.

Última actualización: 26-11-2026. Cada fila dice cuándo y dónde se leyó. Si una cifra va a ir en grande y
tiene más de un año, se vuelve a mirar.

## 1. Cifras externas ya verificadas

### Ciencia de la madera

| Dato | Cifra tal cual | Fuente primaria | 2.ª fuente | Nivel |
|---|---|---|---|---|
| La madera es higroscópica: toma y suelta humedad hasta equilibrarse con el aire | «Wood is a hygroscopic material which loses and gains moisture as a result of changes in humidity» | Hiziroglu S. (2017) *Dimensional Changes in Wood*, NREM-5009, Oklahoma State Univ. Extension | Reeb J.E. *Wood and Moisture Relationships*, EM 8600, Oregon State Univ. Extension (1995, rev. 2024) | 🟢 |
| Punto de saturación de las fibras | «Fsp for most wood species falls in the range of 25% to 30% MC» (secuoya ~22 %, abedul hasta 35 %) | Reeb, EM 8600 | Hiziroglu 2017: 28 % «for practical purposes» | 🟢 |
| Contracción por dirección (del punto de saturación a seco al horno) | Tangencial «about 8%», radial «about 4%», longitudinal «about 0.1%». La madera juvenil o de reacción llega hasta 2 % longitudinal. | Reeb, EM 8600 | Hiziroglu 2017, Tabla 1 por especie (ej. roble blanco 10,5 % tang. / 5,6 % rad., de verde a seco al horno) | 🟢 |
| Humedad de equilibrio según HR del aire | Para 30–90 °F: 30 % HR → 6 % · 40 % → 7–8 % · 50 % → 9–10 % · 60 % → 10–11 % · 70 % → 12–13 % · 80 % → 15–16 % · 90 % → 20–21 % | Reeb, EM 8600, Tabla 1 | Penn State Extension, S. Weikert, *Understanding Equilibrium Moisture Content* (video y transcripción): a 70 °F, 40 % HR → 7,7 %; 77 % HR → 14,9 % | 🟢 |
| Humedad recomendada al instalar muebles de interior | Tabla 12-2, «Interior: woodwork, flooring, furniture, wood trim»: mayor parte de EE. UU. 8 % promedio (piezas 6–10) · sudoeste seco 6 (4–9) · «Damp, warm coastal area» 11 (8–13) | USDA FPL, *Wood Handbook* (1999, FPL-GTR-113), cap. 12 (W. T. Simpson), p. 12-3 | Reeb, EM 8600: «For products to be used inside heated buildings, use wood with an MC of about 7%» | 🟢 (es dato de EE. UU.) |
| Fórmula del cambio de dimensión, válida entre 6 % y 14 % | ΔD = D × C × (Hf − Hi). Coeficientes por punto de humedad: roble blanco C_R 0,00180 / C_T 0,00365 · cerezo negro 0,00126 / 0,00248 · nogal negro 0,00190 / 0,00274 · arce azucarero 0,00165 / 0,00353 | Wood Handbook 1999, cap. 12, ec. 12-2 y Tabla 12-5 | Fórmula equivalente: DC = OD × SV × (ΔCH ÷ PSF), Hiziroglu 2017 | 🟢 |
| Ejemplo ya calculado | Cubierta de 60 cm de ancho, roble blanco, de 8 % a 12 %: 60 × 0,00365 × 4 = 0,88 cm (tangencial); 60 × 0,00180 × 4 = 0,43 cm (radial) | Cálculo propio con la Tabla 12-5 | — | 🟢 (decir «ejemplo con roble americano») |
| El acabado frena, no sella | «Protective coatings can retard dimensional changes in wood but do not prevent them» | Wood Handbook 1999, cap. 12, p. 12-1 | Reeb, EM 8600: «will not completely stop moisture exchange… it will slow it considerably». Recomienda sellar todas las caras. | 🟢 |
| Instalar a la humedad de servicio evita grietas en muebles | «…avoiding problems such as floor buckling or cracks in furniture» | Wood Handbook 1999, cap. 12, p. 12-3 | Reeb, EM 8600: «It should have an MC equal to the EMC where it will be used» | 🟢 |
| Chile: humedad de la madera igual a la del lugar de servicio | NCh 1198: «…igual al correspondiente a la humedad de equilibrio del lugar donde prestará servicio». Se citan 12 % (calefacción intermitente) y 9 % (continua). | NCh 1198 (de pago, **no leída**), visto solo en un resultado de búsqueda | — | 🔴 los porcentajes · el principio ya está en 🟢 por las dos fuentes de arriba |

### Tablas de picar

| Dato | Cifra tal cual | Fuente primaria | 2.ª fuente | Nivel |
|---|---|---|---|---|
| El plástico no es más higiénico que la madera | Laboratorio: se recuperaron menos bacterias de la madera que del plástico, nuevo o usado. No respalda que el plástico sea más sanitario. | Ak NO, Cliver DO, Kaspar CW (1994) *J Food Prot* 57(1):16-22, Univ. of Wisconsin–Madison, PMID 31113021 | Aviat F. et al. (2016) *Compr Rev Food Sci Food Saf* 15(3):491-505, PMID 33401823 · Cliver DO (2006) *J AOAC Int* 89(2):538-542, UC Davis, PMID 16640304 | 🟢 |
| El plástico rayado cuesta limpiarlo | «knife-scarred plastic… is very difficult to clean and disinfect» | Cliver 2006 | Ak et al. (1994b) *J Food Prot* 57:23-30, PMID 31113026 | 🟢 |
| Las bacterias no mueren al instante en la madera: quedan en los poros | «Bacteria in the wood pores are not killed instantly, but neither do they return to the surface» | Cliver 2006 | — | 🟡 |
| Un estudio epidemiológico: la tabla de plástico en casa fue riesgo y la de madera no | «one of these studies indicated that use of plastic cutting boards in home kitchens is hazardous, whereas use of wooden cutting boards is not» | Cliver 2006 (cita el estudio; el original no está identificado) | — | 🟡 no ponerlo en grande |

Límite que siempre hay que decir: son estudios de laboratorio con tablas contaminadas a propósito, no cocinas reales.

### Madera y bienestar

| Dato | Cifra tal cual | Fuente primaria | 2.ª fuente | Nivel |
|---|---|---|---|---|
| Prometedor, pero con poca evidencia | Revisión sistemática de 9 estudios, de 12 a 119 personas, riesgo de sesgo alto en 3: «visual wood exposure may lead to certain favourable outcomes, but the evidence is limited» | Lipovac D, Burnard MD (2020) *Indoor and Built Environment*, doi 10.1177/1420326X20927437 | Burnard MD, Kutnar A (2015) *Wood Sci Technol* 49:969-986 | 🟢 |

Financiamiento: InnoRenew CoE (Horizon 2020), un centro de investigación en madera. Parte del efecto podría deberse al olor y no a lo visual.

### Ergonomía

| Dato | Cifra tal cual | Fuente primaria | 2.ª fuente | Nivel |
|---|---|---|---|---|
| Distancia a la pantalla | «between 20 and 40 inches (50 and 100 cm) from the eye to the front surface of the computer screen» | OSHA eTool *Computer Workstations: Monitors* | CCOHS (Canadá), *Positioning the Monitor*: «about an arm's length» (sin cifra) | 🟡 |
| Altura de la pantalla | «The top of the monitor should be at or slightly below eye level»; centro 15–20° bajo la horizontal | OSHA, misma página | CCOHS (sin cifra de ángulo) | 🟡 (cerca de 🟢 en lo cualitativo) |
| Espacio para las piernas | 20 in (52 cm) de ancho · 17 in (44 cm) de fondo a la rodilla · 24 in (60 cm) a los pies · 4 in (10 cm) de alto al pie | OSHA eTool …/components/work-space | — | 🟡 |
| Pasillo de trabajo en cocina con isla | 42″ (1067 mm) una persona cocinando · 48″ (1219 mm) varias | NKBA *Kitchen Planning Guidelines* (2022), visto en el extracto indexado del PDF | — | 🟡 guía de EE. UU., es costumbre |
| OGUC: huella y contrahuella solo en escaleras de evacuación | Art. 4.2.11 n.º 2: huella «no inferior a 0,28 m», contrahuella entre 0,13 y 0,18 m. El capítulo rige áreas comunes de edificios colectivos y edificios de uso público (art. 4.2.1). | OGUC, leída en modulor.cl («sincronizado con BCN», 02-10-2026) | BCN no cargó | 🟡 confirmar en BCN |
| OGUC: barandas de 0,95 m, salvo en la vivienda unifamiliar | Art. 4.2.7: altura «no inferior a 0,95 m». Art. 4.2.1 inc. 3: el 4.2.7 rige «con excepción de las viviendas unifamiliares» y de las escaleras interiores de los departamentos. | OGUC (modulor.cl) | — | 🟡 |
| Regla de Blondel | 2 contrahuellas + 1 huella ≈ 63–64 cm, con rangos de 60–65 cm según la fuente | F. Blondel, *Cours d'architecture* (1675–1683), no leído | Guías técnicas (UNCuyo: 61–63 cm) | 🟡 costumbre, no norma |

**Pistas sin leer todavía** (fuentes gratuitas y oficiales; leerlas antes de usar):
- MINVU, *Cuadro Normativo y Tabla de Espacios y Usos Mínimos para el Mobiliario* (Res. Ex. 7712 de 2017 y
  actualizaciones), en minvu.gob.cl. Según los extractos:
  - Mesa de comedor de 120 × 70 cm.
  - Mesón de cocina de 70 × 50 cm, con 80 cm de circulación.
  - Circulaciones de 70 cm como mínimo.

  Son mínimos de vivienda social, no medidas cómodas.
- INSST (España), *Guía técnica para la evaluación de los riesgos de pantallas de visualización* (2021) y la
  NTP 602. Según un extracto de segunda mano: mesa de 72 cm (rango de 65 a 75 cm).

**En 🔴, sin fuente abierta:** Neufert (60 cm por persona), Panero & Zelnik (espacio detrás de la silla), EN
527-1 (altura de escritorio), el diámetro de mesa redonda por comensales y la altura de mesa frente al
asiento.

## 2. Qué sitios se pueden leer (probado el 26-11-2026)

| Sitio | Resultado | Cómo leerlo |
|---|---|---|
| fpl.fs.usda.gov / research.fs.usda.gov (Wood Handbook) | 403, incluso desde Chrome; el PDF de treesearch no trae texto | Copia de la ed. 1999 en `blog.spib.org/wp-content/uploads/2021/07/ch12.pdf` → `web-fetch` la guarda → `scripts/pdf-texto.ps1` |
| pubmed.ncbi.nlm.nih.gov | `web-fetch`: pide cookies; Chrome: captcha | API de Europe PMC: `https://www.ebi.ac.uk/europepmc/webservices/rest/search?query=EXT_ID:<PMID>&resultType=core&format=json`. Desde Chrome trae el abstract completo; `web-fetch` lo resume. |
| link.springer.com | Pide login | Buscar copia en Zenodo o en el repositorio de la universidad |
| kb.nkba.org (PDF) | 403; en Chrome el PDF no trae texto. La edición vigente es de pago. | Solo el extracto indexado |
| web.archive.org | Bloqueado para `web-fetch` | — |
| bcn.cl/leychile | Queda en «cargando» | modulor.cl (espejo sincronizado), confirmando en BCN a mano |
| bibliotecadigital.infor.cl | Redirige a 127.0.0.1 (roto) | — |
| cybertesis.uach.cl | Conexión rechazada | — |
| osha.gov, extension.oregonstate.edu, extension.okstate.edu, extension.psu.edu | Se leen bien (`web-fetch` o Chrome) | — |
| zenodo.org (PDF) | `web-fetch` los guarda; algunos se pueden extraer | `scripts/pdf-texto.ps1` |

**Extraer un PDF:** `scripts/pdf-texto.ps1 -Entrada <pdf> -Salida <txt>`. Tarda ~2,5 min por capítulo, así
que conviene correrlo en segundo plano. Sirve con fuentes estándar; con PDF escaneados o fuentes CID sale
basura.

## 3. Plantillas SQL de datos propios (solo lectura)

**Medidas de cubierta por uso.** Cotizador (`supabase-cotizador`). `quote_links.data` tiene:
- `p`: producto,
- `uso`: comedor/cocina/escritorio/bano/quincho/repisa/exterior/otro,
- `rows[]`: `lg` (largo), `an` (fondo) y `ca` (cantidad),
- `qnum`: el número de cotización.

```sql
with q as (
  select distinct on (data->>'qnum') data->>'qnum' qnum, data->>'uso' uso, data->'rows' rws, created_at
  from quote_links
  where data->>'p'='cubierta' and data ? 'qnum' and coalesce(data->>'test','') = ''
  order by data->>'qnum', id desc
), l as (
  select qnum, uso, (r->>'lg')::numeric lg, (r->>'an')::numeric an
  from q, jsonb_array_elements(rws) r
  where (r->>'lg') ~ '^[0-9.]+$' and (r->>'an') ~ '^[0-9.]+$'
    and (r->>'lg')::numeric between 20 and 600 and (r->>'an')::numeric between 10 and 300
)
select uso, count(distinct qnum) cotiz, count(*) lineas,
 percentile_cont(array[0.25,0.5,0.75]) within group (order by lg) largo_p25_50_75,
 percentile_cont(array[0.25,0.5,0.75]) within group (order by an) fondo_p25_50_75,
 mode() within group (order by lg) largo_moda, mode() within group (order by an) fondo_moda,
 (select min(created_at)::date from q) desde, (select max(created_at)::date from q) hasta
from l group by uso order by 2 desc;
```

El cotizador público **no pregunta madera ni espesor**. Esos datos salen solo de lo vendido.

**Madera y espesor vendidos.** Gestión (`supabase-gestion`). `gestion_produccion.data.lineas[]` tiene
`producto`, `madera`, `espesor`, `largo`, `ancho`, `cantidad` y `observaciones`. Se excluyen la postventa y
los registros que no son venta.

```sql
with l as (
 select p.num, upper(coalesce(l->>'producto','')) prod,
  translate(upper(trim(coalesce(l->>'madera',''))),'ÁÉÍÓÚ','AEIOU') m0, nullif(l->>'espesor','') esp
 from gestion_produccion p, jsonb_array_elements(p.data->'lineas') l
 where coalesce(p.data->>'tipo_registro','venta') in ('venta','') and coalesce(p.data->>'postventa_id','')=''
   and coalesce(l->>'observaciones','') not ilike '%POST VENTA%'
), c as (
 select *, case when m0 in ('MANIO','MAÑO','MANO') then 'MAÑIO' when m0 in ('PINO OREGON','OREGON') then 'OREGON'
   when m0 like 'COIHUE%' then 'COIHUE' else m0 end madera,
 case when prod ~ 'PELDA|ESCAL' then 'peldaño' when prod ~ 'PUERTA|GRANERO' then 'puerta'
   when prod ~ 'BAÑO|BANO|LAVAMANO|VANITOR' then 'baño' when prod ~ 'ESCRITORIO' then 'escritorio'
   when prod ~ 'COCINA|ISLA|MESON|MESÓN' then 'cocina' when prod ~ 'MESA|COMEDOR' then 'mesa' else 'resto' end uso
 from l)
select uso, madera, count(distinct num) pedidos from c
where madera not in ('','SIN MADERA') group by 1,2 order by 1,3 desc;
```

Las fechas de `gestion_produccion` son texto (`DD-MM-YYYY` o ISO): convertirlas antes de sacar el período.

**Tiempo de cotización a venta.** Cotizador, tabla `cotizaciones`. `fecha_concretada` es cuando el vendedor
marca la venta, no el día del pago.

```sql
with c as (select extract(epoch from fecha_concretada - fecha_creacion)/86400.0 dias from cotizaciones
  where not coalesce(eliminada,false) and fecha_concretada is not null and fecha_concretada >= fecha_creacion)
select count(*) n, percentile_cont(array[0.25,0.5,0.75]) within group (order by dias) p25_50_75,
 count(*) filter (where dias<=1) d1, count(*) filter (where dias<=7) d7, count(*) filter (where dias<=30) d30 from c;
```

## 4. Frases que NO se dicen

- «La madera mata las bacterias» / «la madera es antibacteriana». Cliver 2006: no mueren al instante.
  Decir «no es menos higiénica que el plástico».
- «La ley exige X cm de contrahuella en tu escalera». En Chile solo rige para escaleras de evacuación de
  edificios.
- «La norma dice que la cubierta de cocina va a 90 cm». Es costumbre (36″ en EE. UU.), no norma.
- «Una madera bien seca ya no se mueve». Siempre sigue la humedad del aire.
- «El barniz sella la madera». La frena, no la sella.
- «La madera baja el estrés un X %» / «3.500 latidos menos al día» (pino cembro). No hay estudio verificable.
- «Neufert dice 60 cm por persona». No verificado.
- «Madera nativa». Es **madera noble**.
- Destacar «garantía de 5 años» en marketing. El mensaje es «hecha para durar décadas».
