---
name: cierre-semanal
description: Genera el reporte semanal de avance de Casa Zaru — venta acumulada del mes (base para la comisión de César), tramo de comisión vigente, y pedidos que despachan esta semana/próxima. Actívala cuando el usuario pida "cierre semanal", "cómo vamos este mes", "en qué tramo está César" o "qué despacha esta semana".
---

# Cierre semanal — reporte de avance

Reporte de avance, **no** un pago de comisión — la comisión real se liquida a fin de
mes. Este reporte muestra dónde está parado el mes y qué se despacha pronto, para
leer en 30 segundos.

## 0. Antes de calcular — confirma columnas, no asumas

Los nombres de columna pueden haber cambiado desde que se escribió esta skill.
Antes de filtrar nada, inspecciona con una consulta chica:

```
GET {SB_URL}/rest/v1/gestion_pedidos?select=*&limit=3
GET {SB_URL}/rest/v1/gestion_finanzas?select=*&limit=3
GET {SB_URL}/rest/v1/gestion_produccion?select=*&limit=3
headers: apikey: {SB_KEY}, Authorization: Bearer {SB_KEY}
```

`SB_URL` = `https://padnttpgzuotxeipjrry.supabase.co` (proyecto GESTIÓN — el mismo
que usa `index.html`). La API key pública (anon) está en `index.html` como
`SB_ANON` / `WASABIL_ANON_KEY` — reutilízala, es la misma que ya viaja en el
navegador del usuario, no es secreta.

Busca en las tres tablas:
- El campo de **vendedor** — si ya existe (`vendedor`, `vendedor_email` o similar,
  agregado después de esta skill), **úsalo y filtra por César directamente** — es
  más confiable que canal. Si no existe todavía, usa `canal = 'whatsapp'` como
  proxy (regla confirmada por el usuario: hoy no hay campo de vendedor limpio;
  la venta web también entra a veces por WhatsApp, así que esto es una
  aproximación, no un dato exacto — dilo si el usuario pregunta).
- El campo `val_prod` (valor producto, sin envío ni comisión de pago) — normalmente
  en `gestion_finanzas`. Es la base de cálculo confirmada — **nunca uses `total`
  bruto ni los campos `abono1/abono2/abono3`** para este cálculo (abono1 ha tenido
  histórico de inflarse, ver auditoría del proyecto — no es venta real, es cobro).
- El campo `semana` en `gestion_produccion` — texto tipo "SEMANA 10 AGOSTO",
  normalizado por `normalizaSemana()` en el código del panel.
- `numStr` es la clave universal — todas las tablas se unen por ese campo.

## 1. Venta acumulada del mes (base de comisión de César)

1. Trae todos los `numStr` de `gestion_pedidos` (o donde esté `canal`) con
   `canal = 'whatsapp'` (o `vendedor` = César si ya existe) y fecha de venta
   dentro del **mes calendario actual**.
2. Para cada `numStr`, trae `val_prod` desde `gestion_finanzas`.
3. Suma `val_prod` → ese es el volumen del mes.

## 2. Tramo de comisión vigente

Tramos confirmados por el usuario (2026-08-17), sobre volumen mensual de `val_prod`:

| Volumen mensual (val_prod) | Comisión |
|---|---|
| $0 – $14.999.999 | 2,0% |
| $15.000.000 – $24.999.999 | 2,5% |
| $25.000.000 o más | 3,5% |

Calcula: tramo vigente, comisión estimada acumulada (`volumen × %`), y cuánto falta
en pesos para alcanzar el siguiente tramo (si no está ya en el más alto). Si el
usuario quiere el número exacto a pagar, recuérdale que esto es una **estimación de
avance** — el cierre real de fin de mes debe confirmarse contra Finanzas.

## 3. Pedidos que despachan esta semana / próxima

Regla del taller: una semana se nombra con el LUNES que la abre, y el envío ocurre
la semana SIGUIENTE (semana 10 → despacha en la semana del 17).

1. Trae `gestion_produccion` con `semana` = la semana cuyo despacho cae en los
   próximos 7 días (la semana anterior a la semana de despacho objetivo).
2. Lista `numStr`, cliente, producto — agrupado por día de despacho si el dato
   existe.
3. Si algún pedido no tiene `semana` asignada, no lo pierdas silenciosamente —
   menciónalo aparte ("N pedidos sin semana, quedan fuera de este cálculo").

## 4. Formato de salida

Corto, para leer rápido — no una tabla larga:

```
*Cierre semanal Casa Zaru — [fecha]*

💰 Venta del mes (WhatsApp, val_prod): $X — tramo vigente: Y%
   Comisión acumulada estimada: $Z
   Faltan $W para pasar a [siguiente tramo]% (o "ya en el tramo máximo")

🚚 Despacha esta semana: N pedidos
   [numStr — cliente — producto] × hasta 8, resto como conteo

⚠️ [avisos: pedidos sin semana, datos que no cuadraron, supuestos usados]
```

Si algo falla (columna no existe, tabla vacía, error de red) dilo explícitamente —
nunca inventes un número.
