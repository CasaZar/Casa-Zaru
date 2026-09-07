-- Relleno de gestion_documentos con lo emitido en septiembre 2026.
--
-- La fuente es Wasabil, no la app: el campo doc1_num de gestion_finanzas se
-- usó por meses como bloc de notas ('NO', 'canje', 'retira', '7172 abono 1'),
-- asi que no sirve como indice de folios. De 179 documentos que la app da por
-- emitidos, solo 118 tienen algo numerico y ni todos esos son folios.
--
-- El numero de pedido se resuelve en dos pasos: primero el invoice_reference
-- que Wasabil guarda en las facturas, y si no, cruzando el folio contra
-- gestion_finanzas. Donde no se pueda, queda nulo: el documento igual aparece
-- en la ficha de su cliente, que es lo que se busca. Los nulos no chocan entre
-- si en un indice unico, asi que el candado antiduplicado no se debilita.

alter table public.gestion_documentos alter column num drop not null;

with nuevos (folio, tipo, monto, fecha, cliente, rut, email, uuid, pdf_url, ref) as (values
    ('157', 'FACTURA', 277240, '2026-09-01', 'PUNTA FLECHA SPA', '77.716.679-4', null, '8e9f4206-ecb0-4398-aa71-b18391dc1612', 'https://api.wasabil.com/api/documents/8e9f4206-ecb0-4398-aa71-b18391dc1612/document-pdf/1546_157_33_20260900007366.pdf', '1546'),
    ('158', 'FACTURA', 493361, '2026-09-02', 'Viviana Briceño', '13.818.762-4', null, '8479c138-8750-413c-af8a-4d30d94d520f', 'https://api.wasabil.com/api/documents/8479c138-8750-413c-af8a-4d30d94d520f/document-pdf/1521_158_33_20260900028471.pdf', '1521'),
    ('159', 'FACTURA', 135000, '2026-09-02', 'COMERCIALIZADORA DEL PACIFICO SPA', '77.669.350-2', 'milenko.stambuk@gmail.com', 'e539975c-0133-4a27-8659-522927fc36c9', 'https://api.wasabil.com/api/documents/e539975c-0133-4a27-8659-522927fc36c9/document-pdf/1532_159_33_20260900028645.pdf', '1532'),
    ('160', 'FACTURA', 172875, '2026-09-02', 'Mujica Wielandt Ltda', '76.303.527-1', 'manuelmujicad@gmail.com', '60b99414-1d01-4b15-ad2d-026114cdf551', 'https://api.wasabil.com/api/documents/60b99414-1d01-4b15-ad2d-026114cdf551/document-pdf/1533_160_33_20260900028696.pdf', '1533'),
    ('7258', 'BOLETA', 250000, '2026-09-01', 'Catalina Pérez', '18.392.390-0', 'ataperezv@gmail.com', '8b29bfb3-3c2d-43fa-8f0e-1a2ffe09c949', 'https://api.wasabil.com/api/documents/8b29bfb3-3c2d-43fa-8f0e-1a2ffe09c949/document-pdf/7258_39_20260900017765.pdf', null),
    ('7259', 'BOLETA', 46163, '2026-09-02', 'Lilian Marquez', '17.582.762-5', 'lilian.marquezz@gmail.com', 'ff694fe8-a316-4765-83ed-aa8a4ff71f08', 'https://api.wasabil.com/api/documents/ff694fe8-a316-4765-83ed-aa8a4ff71f08/document-pdf/7259_39_20260900028677.pdf', null),
    ('7260', 'BOLETA', 107714, '2026-09-02', 'Lilian Marquez', '17.582.762-5', 'lilian.marquezz@gmail.com', 'd2daa022-ad5a-47a9-a271-6565cad60ab4', 'https://api.wasabil.com/api/documents/d2daa022-ad5a-47a9-a271-6565cad60ab4/document-pdf/7260_39_20260900028676.pdf', null),
    ('7261', 'BOLETA', 188600, '2026-09-02', 'Juan Pablo Batlle', '13.832.406-0', 'jpbatlle@gmail.com', '95737dfc-7968-46ea-88f2-7e300e030883', 'https://api.wasabil.com/api/documents/95737dfc-7968-46ea-88f2-7e300e030883/document-pdf/7261_39_20260900028691.pdf', null),
    ('7262', 'BOLETA', 80817, '2026-09-02', 'Juan Pablo Batlle', '13.832.406-0', 'jpbatlle@gmail.com', '5a650a8e-9ea4-4654-90d7-162c8912f1c3', 'https://api.wasabil.com/api/documents/5a650a8e-9ea4-4654-90d7-162c8912f1c3/document-pdf/7262_39_20260900028693.pdf', null),
    ('7263', 'BOLETA', 604227, '2026-09-02', 'Cristobal Buneder', '18.467.560-9', null, '686c5ae2-1768-4518-9f41-b687b8ba5845', 'https://api.wasabil.com/api/documents/686c5ae2-1768-4518-9f41-b687b8ba5845/document-pdf/7263_39_20260900037528.pdf', null),
    ('7264', 'BOLETA', 12490, '2026-09-03', 'MacArena Fernanda Misleh Montero', '18.667.470-7', null, 'c350bd6b-18d4-4a80-b5d2-cf7ad23f35e6', 'https://api.wasabil.com/api/documents/c350bd6b-18d4-4a80-b5d2-cf7ad23f35e6/document-pdf/pack_2000014846319693_7264_39_20260900048139.pdf', 'pack/2000014846319693')
)
insert into public.gestion_documentos (num, doc_num, tipo, folio, monto, fecha, cliente, rut, email, uuid, pdf_url)
-- El invoice_reference sirve solo si parece un numero de pedido. En las ventas
-- de plataforma trae cosas como 'pack/2000014846319693' (boleta 7264), que no
-- es un pedido de Casa Zaru y no debe entrar como tal.
select coalesce(case when n.ref ~ '^[0-9]{3,5}$' then n.ref end, m.num),
       coalesce(m.doc_num, 1), n.tipo, n.folio, n.monto, n.fecha::date,
       n.cliente, n.rut, n.email, n.uuid, n.pdf_url
from nuevos n
left join lateral (
  select f.num,
         case when f.data->>'doc1_num' = n.folio then 1
              when f.data->>'doc2_num' = n.folio then 2 end as doc_num
  from gestion_finanzas f
  where f.data->>'doc1_num' = n.folio or f.data->>'doc2_num' = n.folio
  limit 1
) m on true
on conflict do nothing;

-- Marcar las anuladas por nota de credito (NC 23 y 24 del 03-09-2026).
with anuladas (folio, nc, motivo) as (values
    ('7261', '24', 'Anula boleta duplicada - pedido 1529'),
    ('7260', '23', 'Anula boleta duplicada - pedido 1527')
)
update public.gestion_documentos d
   set anulada = true, nc_folio = a.nc, nc_motivo = a.motivo
  from anuladas a
 where d.folio = a.folio;
