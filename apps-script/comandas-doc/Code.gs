// Comandas de taller → Google Doc «COMANDA PEDIDO» (26-10-2026).
//
// Web app que llama Producción (botón «Cargar al Doc»). Corre como la cuenta
// dueña del Doc; la app no lleva ninguna credencial de Google. Quien llama se
// identifica con su JWT de Supabase y acá se valida contra Supabase antes de
// leer o escribir nada: sin sesión válida de la Gestión no pasa.
//
// Propiedades del script (Configuración del proyecto → Propiedades):
//   DOC_ID   el Doc donde se escribe. Para probar, el ID de una COPIA del Doc.
//
// Acciones (POST, cuerpo JSON como text/plain para evitar el preflight CORS):
//   estado   → qué piezas ya están en el Doc, por clave pedido|producto|medida
//   revisar  → qué pasaría con estas piezas (pestaña, nueva o repetida), sin escribir
//   cargar   → escribe las que no están; las repetidas se saltan
//
// El formato de página es el de gen-1586.ps1 (22-10-2026), que a su vez copia el
// .docx de buildEtiquetaChildren en index.html. Si cambia uno, cambiar el otro.

var SB_URL = 'https://padnttpgzuotxeipjrry.supabase.co';
var ROLES_OK = ['admin', 'taller', 'vendedor'];

function doPost(e) {
  var out;
  try {
    var req = JSON.parse((e && e.postData && e.postData.contents) || '{}');
    var usuario = validarSesion_(req.jwt, req.apikey);
    var docId = PropertiesService.getScriptProperties().getProperty('DOC_ID');
    if (!docId) throw new Error('Falta la propiedad DOC_ID en el script');
    if (req.accion === 'estado') out = { ok: true, claves: indice_(docId).claves };
    else if (req.accion === 'revisar') out = { ok: true, plan: planificar_(docId, req.piezas || []).resumen };
    else if (req.accion === 'cargar') out = cargar_(docId, req.piezas || [], usuario);
    else throw new Error('Acción desconocida');
  } catch (err) {
    out = { ok: false, error: String(err && err.message || err) };
  }
  return ContentService.createTextOutput(JSON.stringify(out)).setMimeType(ContentService.MimeType.JSON);
}

// ── Autenticación ─────────────────────────────────────────────────────────
// El JWT lo firma Supabase; /auth/v1/user lo rechaza si es falso o venció.
// La apikey es la pública del proyecto (la misma del HTML): no da acceso sola.
function validarSesion_(jwt, apikey) {
  if (!jwt || !apikey) throw new Error('Sin sesión');
  var h = { apikey: apikey, Authorization: 'Bearer ' + jwt };
  var r = UrlFetchApp.fetch(SB_URL + '/auth/v1/user', { headers: h, muteHttpExceptions: true });
  if (r.getResponseCode() !== 200) throw new Error('Sesión no válida: vuelve a entrar a la Gestión');
  var email = JSON.parse(r.getContentText()).email || '';
  var q = UrlFetchApp.fetch(SB_URL + '/rest/v1/gestion_usuarios?select=rol&email=eq.' + encodeURIComponent(email),
    { headers: h, muteHttpExceptions: true });
  var filas = q.getResponseCode() === 200 ? JSON.parse(q.getContentText()) : [];
  var rol = filas.length ? filas[0].rol : '';
  if (ROLES_OK.indexOf(rol) < 0) throw new Error('Tu cuenta no tiene permiso para cargar comandas');
  return email;
}

// ── Claves ────────────────────────────────────────────────────────────────
// Misma normalización que _cmdNorm en index.html.
function norm_(s) {
  return String(s == null ? '' : s).toUpperCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
    .replace(/,/g, '.').replace(/\s+/g, ' ').trim();
}
function clave_(pedido, producto, dims) { return norm_(pedido) + '|' + norm_(producto) + '|' + norm_(dims); }
// «SEMANA 31 DE AGOSTO» = «SEMANA 31 AGOSTO» y «03» = «3». «SEMANA 26.2 OCTUBRE»
// (pestaña extra que existe en el Doc) queda distinta a propósito.
function normSemana_(t) {
  return norm_(t).replace(/[^A-Z0-9. ]/g, ' ').replace(/\b(DEL?|SEM)\b/g, ' ').replace(/\b0+(\d)/g, '$1').replace(/\s+/g, ' ').trim();
}

// ── Lectura del Doc ───────────────────────────────────────────────────────
// Con DocumentApp y getText() por pestaña: ~3 s para todo el Doc. La API de
// Docs con máscara de campos tardaba 12–36 s (y rechaza sub-máscaras dentro de
// table(...)). En el texto, cada celda de tabla es una línea, así que una página
// se lee: PEDIDO: N / semana / NOMBRE: … / canal / producto / … / medida «… X … CMS».
function tabsDeDoc_(doc) {
  var out = [];
  (function rec(ts) { ts.forEach(function (t) { out.push(t); rec(t.getChildTabs()); }); })(doc.getTabs());
  return out;
}
function comandasDeTexto_(texto) {
  var L = texto.split(/[\n\t]/).map(function (s) { return s.trim(); });
  var out = [];
  for (var i = 0; i < L.length; i++) {
    var m = /^PEDIDO:\s*(.+)$/i.exec(L[i]);
    if (!m) continue;
    var c = { pedido: m[1].trim(), producto: '', dims: '' };
    var j = i + 1, fin = Math.min(L.length, i + 14);
    while (j < fin && !/^NOMBRE:/i.test(L[j])) j++;
    if (j < fin) c.producto = L[j + 2] || '';   // NOMBRE → canal → producto
    for (var k = j + 3; k < fin; k++) {
      if (/^PEDIDO:/i.test(L[k])) break;
      if (/\sX\s.*CMS$/i.test(L[k])) { c.dims = L[k]; break; }
    }
    out.push(c);
  }
  return out;
}
// Índice fresco: pestañas (id, título) y claves → títulos de pestaña donde están.
function leerIndice_(docId) {
  var doc = DocumentApp.openById(docId), tabs = [], claves = {};
  tabsDeDoc_(doc).forEach(function (t) {
    var titulo = t.getTitle();
    tabs.push({ id: t.getId(), titulo: titulo });
    comandasDeTexto_(t.asDocumentTab().getBody().getText()).forEach(function (c) {
      var ck = clave_(c.pedido, c.producto, c.dims);
      (claves[ck] = claves[ck] || []).push(titulo);
    });
  });
  // Cerrar para que el próximo openById (el de las imágenes) vea lo que se escriba por la API.
  doc.saveAndClose();
  return { tabs: tabs, claves: claves };
}
// Para «estado» y «revisar»: 10 min de caché. «cargar» siempre lee fresco.
function indice_(docId, fresco) {
  var cache = CacheService.getScriptCache(), k = 'idx_' + docId, hit = fresco ? null : cache.get(k);
  if (hit) return JSON.parse(hit);
  var idx = leerIndice_(docId), s = JSON.stringify(idx);
  if (s.length < 95000) cache.put(k, s, 600);
  return idx;
}
// Pestañas planas de una respuesta de la API de Docs (para finDeTab_).
function tabsPlanas_(doc) {
  var out = [];
  (function rec(ts) { (ts || []).forEach(function (t) { out.push(t); rec(t.childTabs); }); })(doc.tabs);
  return out;
}

// Páginas pegadas a mano a veces traen la medida vacía o repetida («120 X 30 CMS
// 120 X 30 CMS»). Mismo pedido y producto con una medida así cuenta como cargada:
// es preferible saltarse una página a duplicarla. Igual que _cmdBuscar en index.html.
function parecida_(claves, ck) {
  var p = ck.split('|'), pref = p[0] + '|' + p[1] + '|', dims = p[2];
  for (var k in claves) {
    if (k.indexOf(pref) !== 0) continue;
    var d = k.slice(pref.length);
    if (!d || (dims && d.indexOf(dims) >= 0)) return claves[k][0];
  }
  return '';
}

// ── Plan: a qué pestaña va cada pieza y cuáles ya están ───────────────────
// Una clave repetida N veces en el Doc cubre N piezas iguales del pedido.
function planificar_(docId, piezas, fresco) {
  var idx = indice_(docId, fresco), usadas = {}, items = [];
  piezas.forEach(function (p) {
    var ck = clave_(p.pedido, p.producto, p.dims);
    var n = usadas[ck] = (usadas[ck] || 0) + 1;
    var ya = idx.claves[ck] && idx.claves[ck].length >= n ? idx.claves[ck][n - 1] : '';
    if (!ya && n === 1) ya = parecida_(idx.claves, ck);
    var tab = null, ns = normSemana_(p.semana);
    idx.tabs.forEach(function (t) { if (!tab && normSemana_(t.titulo) === ns) tab = t; });
    items.push({ p: p, ya: ya, tab: tab });
  });
  var resumen = items.map(function (it) {
    return { pedido: it.p.pedido, producto: it.p.producto, dims: it.p.dims, semana: it.p.semana,
      ya: it.ya, tabExiste: !!it.tab };
  });
  return { items: items, resumen: resumen };
}

// ── Escritura ─────────────────────────────────────────────────────────────
function cargar_(docId, piezas, usuario) {
  var lock = LockService.getScriptLock();
  if (!lock.tryLock(30000)) throw new Error('Otra carga está en curso; prueba en un minuto');
  try {
    var plan = planificar_(docId, piezas, true);
    var porSemana = {}, orden = [];
    plan.items.forEach(function (it) {
      if (it.ya) return;
      var ns = normSemana_(it.p.semana);
      if (!porSemana[ns]) { porSemana[ns] = { titulo: it.p.semana, tab: it.tab, piezas: [] }; orden.push(ns); }
      porSemana[ns].piezas.push(it.p);
    });
    var cargadas = [], creadas = [];
    orden.forEach(function (ns) {
      var g = porSemana[ns], tabId;
      if (g.tab) tabId = g.tab.id;
      else {
        var r = Docs.Documents.batchUpdate({ requests: [{ addDocumentTab: { tabProperties: { title: g.titulo.replace(/\b0(\d)/, '$1')} } }] }, docId);
        tabId = r.replies[0].addDocumentTab.tabProperties.tabId;
        creadas.push(g.titulo);
      }
      escribirEnTab_(docId, tabId, g.piezas);
      g.piezas.forEach(function (p) { cargadas.push({ pedido: p.pedido, producto: p.producto, semana: g.titulo }); });
    });
    console.log('cargar: ' + usuario + ' → ' + cargadas.length + ' páginas');
    return { ok: true, cargadas: cargadas, creadas: creadas, saltadas: plan.resumen.filter(function (x) { return x.ya; }) };
  } finally {
    // Aunque falle a medias, el Doc pudo cambiar: la caché ya no sirve.
    CacheService.getScriptCache().remove('idx_' + docId);
    lock.releaseLock();
  }
}

// Fin del cuerpo de una pestaña (índice del último salto de línea).
function finDeTab_(docId, tabId) {
  var doc = Docs.Documents.get(docId, { includeTabsContent: true,
    fields: 'revisionId,tabs(tabProperties(tabId),childTabs(tabProperties(tabId),documentTab(body(content(endIndex)))),documentTab(body(content(endIndex))))' });
  var t = tabsPlanas_(doc).filter(function (x) { return x.tabProperties.tabId === tabId; })[0];
  var cont = t.documentTab.body.content;
  return { cursor: cont[cont.length - 1].endIndex - 1, vacia: cont.length <= 2 && cont[cont.length - 1].endIndex <= 2, rev: doc.revisionId };
}

function escribirEnTab_(docId, tabId, piezas) {
  // Tandas de 5 páginas: cada tanda relee el final de la pestaña.
  for (var i = 0; i < piezas.length; i += 5) {
    var fin = finDeTab_(docId, tabId);
    var lote = piezas.slice(i, i + 5);
    var arm = armarRequests_(tabId, fin.cursor, lote, fin.vacia);
    Docs.Documents.batchUpdate({ requests: arm.requests, writeControl: { requiredRevisionId: fin.rev } }, docId);
    ponerImagenes_(docId, tabId, arm.marcas);
  }
}

// Las imágenes van con DocumentApp (acepta el PNG directo); la API de Docs
// solo inserta desde una URL pública. Se deja una marca de texto y se reemplaza.
function ponerImagenes_(docId, tabId, marcas) {
  if (!marcas.length) return;
  var docA = DocumentApp.openById(docId);
  var body = docA.getTab(tabId).asDocumentTab().getBody();
  marcas.forEach(function (m) {
    var hit = body.findText(m.marca);
    if (!hit) return;
    var txt = hit.getElement().asText(), par = txt.getParent().asParagraph();
    txt.deleteText(hit.getStartOffset(), hit.getEndOffsetInclusive());
    if (m.png) {
      var blob = Utilities.newBlob(Utilities.base64Decode(m.png), 'image/png', 'comanda.png');
      par.appendInlineImage(blob).setWidth(430).setHeight(215); // px = 322,5 × 161,25 pt
    }
  });
  // Sin esto la próxima lectura por la API de Docs no ve las imágenes y los
  // índices de la siguiente tanda salen corridos.
  docA.saveAndClose();
}

function armarRequests_(TAB, cursor, piezas, tabVacia) {
  var R = [], marcas = [];
  function Pt(m) { return { magnitude: m, unit: 'PT' }; }
  function Loc(i) { return { index: i, tabId: TAB }; }
  function Rng(a, b) { return { startIndex: a, endIndex: b, tabId: TAB }; }
  function Ins(i, t) { R.push({ insertText: { text: t, location: Loc(i) } }); }
  // Un rango vacío (celda sin texto, p. ej. BORDE de una puerta) hace fallar todo el lote.
  function EstP(a, b, st, f) { if (b <= a) return; R.push({ updateParagraphStyle: { range: Rng(a, b), paragraphStyle: st, fields: f } }); }
  function EstT(a, b, st, f) { if (b <= a) return; R.push({ updateTextStyle: { range: Rng(a, b), textStyle: st, fields: f } }); }
  function Gris(v) { return { color: { rgbColor: { red: v, green: v, blue: v } } }; }
  var B0 = { color: { color: { rgbColor: {} } }, width: Pt(0), dashStyle: 'SOLID' };
  function TablaSinBordes(t) {
    R.push({ updateTableCellStyle: { tableStartLocation: Loc(t), tableCellStyle: { borderTop: B0, borderBottom: B0, borderLeft: B0, borderRight: B0 }, fields: 'borderTop,borderBottom,borderLeft,borderRight' } });
    R.push({ updateTableColumnProperties: { tableStartLocation: Loc(t), columnIndices: [0, 1], tableColumnProperties: { widthType: 'FIXED_WIDTH', width: Pt(240.1) }, fields: 'width,widthType' } });
  }
  // Llena de atrás hacia adelante una tabla recién creada (2 columnas) que empieza en t.
  function LlenarTabla(t, textos) {
    var n = textos.length, k;
    for (k = n - 1; k >= 0; k--) if (textos[k]) Ins(t + 3 + Math.floor(k / 2) * 5 + 2 * (k % 2), textos[k]);
    var ini = [], acum = 0;
    for (k = 0; k < n; k++) { ini.push(t + 3 + Math.floor(k / 2) * 5 + 2 * (k % 2) + acum); acum += textos[k].length; }
    return { ini: ini, largo: 2 + (n / 2) * 5 + acum };
  }
  var c = cursor;
  piezas.forEach(function (m, idx) {
    var pb, tIns, base;
    if (tabVacia && idx === 0) { pb = null; tIns = c; base = c; }
    else { Ins(c, '\n'); pb = c + 1; tIns = c + 1; base = pb; }
    R.push({ insertTable: { rows: 2, columns: 2, location: Loc(tIns) } });
    var ini1 = tIns + 1;
    var txt1 = ['PEDIDO: ' + m.pedido, m.semana, 'NOMBRE: ' + m.nombre, m.canal];
    var x1 = LlenarTabla(ini1, txt1);
    c = ini1 + x1.largo;
    var bloque = m.producto + '\n \n' + m.cant + '\n' + m.dims + '\n' + m.madera + '\n ';
    Ins(c, bloque);
    var pProd = c, pDiv1 = pProd + m.producto.length + 1, pCant = pDiv1 + 2, pDims = pCant + m.cant.length + 1;
    var pMad = pDims + m.dims.length + 1, pDiv2 = pMad + m.madera.length + 1;
    R.push({ insertTable: { rows: 4, columns: 2, location: Loc(pDiv2 + 1) } });
    var ini2 = pDiv2 + 2;
    var txt2 = ['ESPESOR', 'BORDE', m.espesor, m.borde, 'ACABADO', 'TEÑIDO', m.acabado, m.tenido];
    var x2 = LlenarTabla(ini2, txt2);
    c = ini2 + x2.largo;
    var obsTxt = m.obs ? 'OBS: ' + m.obs + '\n' : '\n';
    Ins(c, obsTxt);
    var pObs = c, pImg = c + obsTxt.length;
    // Solo letras y números: findText() la toma como expresión regular (con [[ ]] fallaba).
    var marca = 'ZZIMG' + Utilities.getUuid().replace(/-/g, '').slice(0, 10) + 'ZZ';
    Ins(pImg, marca);
    marcas.push({ marca: marca, png: m.png || '' });
    c = pImg + marca.length;

    EstP(base, pImg + 1, { alignment: 'START', lineSpacing: 100, spacingMode: 'NEVER_COLLAPSE', spaceAbove: Pt(0), spaceBelow: Pt(0) }, 'alignment,lineSpacing,spacingMode,spaceAbove,spaceBelow');
    EstT(base, pImg, { fontSize: Pt(9), weightedFontFamily: { fontFamily: 'Arial', weight: 400 }, bold: false }, 'fontSize,weightedFontFamily,bold,foregroundColor');
    if (pb) EstP(pb, pb + 1, { pageBreakBefore: true }, 'pageBreakBefore');
    TablaSinBordes(ini1);
    var i = x1.ini;
    EstP(i[1], i[1] + txt1[1].length, { alignment: 'END' }, 'alignment');
    EstP(i[3], i[3] + txt1[3].length, { alignment: 'END' }, 'alignment');
    EstT(i[1], i[1] + txt1[1].length, { foregroundColor: Gris(0.33333334) }, 'foregroundColor');
    EstT(i[3], i[3] + txt1[3].length, { fontSize: Pt(8), foregroundColor: Gris(0.53333336) }, 'fontSize,foregroundColor');
    EstP(pProd, pProd + 1, { spaceAbove: Pt(2), spaceBelow: Pt(5) }, 'spaceAbove,spaceBelow');
    [pDiv1, pDiv2].forEach(function (pd) {
      EstP(pd, pd + 1, { borderBottom: { color: { color: { rgbColor: {} } }, width: Pt(0.75), padding: Pt(1), dashStyle: 'SOLID' }, spaceBelow: Pt(9) }, 'borderBottom,spaceBelow');
      EstT(pd, pd + 1, { fontSize: Pt(2) }, 'fontSize');
    });
    EstP(pCant, pDims + 1, { alignment: 'CENTER', spaceBelow: Pt(3) }, 'alignment,spaceBelow');
    EstP(pMad, pMad + 1, { alignment: 'CENTER', spaceBelow: Pt(9) }, 'alignment,spaceBelow');
    EstT(pCant, pMad + m.madera.length, { bold: true, fontSize: Pt(40) }, 'bold,fontSize');
    TablaSinBordes(ini2);
    i = x2.ini;
    [0, 1, 4, 5].forEach(function (q) { EstT(i[q], i[q] + txt2[q].length, { fontSize: Pt(8), foregroundColor: Gris(0.53333336) }, 'fontSize,foregroundColor'); });
    [2, 3, 6, 7].forEach(function (q) { if (txt2[q]) EstT(i[q], i[q] + txt2[q].length, { bold: true, fontSize: Pt(26) }, 'bold,fontSize'); });
    EstP(pObs, pObs + 1, { spaceBelow: Pt(8) }, 'spaceBelow');
    EstP(pImg, pImg + 1, { alignment: 'CENTER' }, 'alignment');
  });
  return { requests: R, marcas: marcas };
}
