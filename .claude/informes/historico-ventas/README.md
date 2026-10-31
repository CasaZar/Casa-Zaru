# Histórico de ventas 2021-2026

Arma, a partir de las planillas viejas y del respaldo de Gestión, un solo histórico de ventas y de pedidos del taller.
Las salidas (CSV + xlsx) llevan nombres, correos y celulares: van a `Casa Zaru Planillas\historico` y a
`Drive\Casa Zaru\Finanzas\Historico ventas`, nunca al repo.

Cómo regenerarlo (PowerShell 5.1, sin Excel ni Python):

1. Exportar cada planilla a CSV (una carpeta por archivo, el nombre de la carpeta es la clave `a` de la configuración):
   `.\export-xlsx.ps1 -Path "...\VENTAS CASA ZARU 2024 .xlsx" -OutDir datos\v2024`
   (idem `v2025` = VENTAS CASA ZARU 2025 (1).xlsx, `vgen` = VENTAS GENERAL 2025 - 2026 (4).xlsx,
   `taller2024` = PEDIDOS CASA ZARU TALLER 2024.xlsx).
2. `.\consolidar.ps1 -Datos <carpeta datos>` (toma el último `respaldo-gestion-*.json` de Drive; `-SinDrive` para no copiar).

`lib-hist.ps1` trae el lector de números chilenos, fechas, el normalizador de encabezados y el escritor xlsx
(copiado de `libro-mensual.ps1`). `ver.ps1` muestra un CSV exportado de forma compacta para inspeccionar hojas.

Reglas que aplica: semanas por su lunes; serie oficial = planilla de ventas desde sep 2024 (valor del producto con IVA,
sin envío ni comisiones), antes el taller con el precio real cuando existe y, si solo hay costo de Cristián, costo × la razón
precio/costo mediana del mes (1,2 a 1,35 según la época). Piezas duplicadas entre hojas se marcan y no se cuentan.
Devoluciones y muestrarios no suman. Los detalles de cada época están en la hoja «Fuentes y notas» del xlsx.
## Cruce con el SII

`sii-ventas-mensual.csv` (en `Casa Zaru Planillas\historico`, privado) trae el Resumen del Registro de Ventas del SII por mes y
tipo de documento (`periodo;tipo;docs;exento;neto;iva;total;nombre`). Se saca de www4.sii.cl/consdcvinternetui con la sesión del
usuario en Chrome: el servicio `facadeService/getResumen` recibe `{rutEmisor, dvEmisor, ptributario, estadoContab: 'REGISTRO',
operacion: 'VENTA'}` y el token de la cookie `TOKEN` como `conversationId`; se puede pedir un período tras otro con `fetch`
desde la misma página (64 meses en menos de un minuto). Si el archivo existe, `consolidar.ps1` agrega las columnas SII y
`% documentado` = (33 + 39 + 41 + 48 − 61, con IVA) / serie bruta.
