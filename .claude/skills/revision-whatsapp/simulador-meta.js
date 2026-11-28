// Extractor para simular el bot con chats reales del 5558 (Meta Business Suite, inbox/wec, pestaña WhatsApp).
// SOLO LECTURA: hace clic en la lista de chats y lee. Nunca escribe, envía ni reacciona.
// Abrir un chat lo marca como leído: ANTES de usarlo, sacar la foto de los no leídos con el filtro
// «No leídos» encendido (S.fotoNoLeidos) y no abrir ninguno de esos.
//
// Uso (pegar entero con javascript_tool; cada llamada devuelve poco texto):
//   await S.fotoNoLeidos()        → con el filtro «No leídos» ENCENDIDO: guarda S.noLeidos
//   S.correr(prefijos)            → con el filtro APAGADO: recorre la lista y lee los chats cuyo nombre
//                                   empieza con alguno de los prefijos (salvo los no leídos). En segundo
//                                   plano: mirar S.estado()
//   S.preparar()                  → arma S.datos = {C01: {nombre, mensajes:[…]}} con RUT, teléfonos,
//                                   correos y cuentas tapados, lista para /simular
// Pasar S.datos a la pestaña del panel: textarea + ctrl+c / ctrl+v reales (y pisar el portapapeles después).
// 27-11-2026: así se hizo la simulación con 60 chats.
// OJO: la lista solo se pinta con la pestaña de Meta AL FRENTE. Mientras corre, intercalar screenshots chicos
// de esa pestaña; si queda atrás, el recorrido llega al fondo sin abrir nada. Lo que falló queda en S.pendientes:
// volver a correr S.correr(S.pendientes).
(() => {
  const S = window.S = window.S || {};
  const dormir = ms => new Promise(r => setTimeout(r, ms));

  // Lista de chats (columna izquierda) y sus filas visibles.
  S.lista = () => [...document.querySelectorAll('div')].find(d => { const r = d.getBoundingClientRect(); const cs = getComputedStyle(d); return r.left > 60 && r.left < 120 && r.width > 300 && r.top > 150 && /(auto|scroll)/.test(cs.overflowY) && d.scrollHeight > d.clientHeight; });
  S.filas = () => [...S.lista().querySelectorAll('div')].filter(d => { const r = d.getBoundingClientRect(); return r.height > 50 && r.height < 80 && r.width > 300 && d.innerText && d.innerText.includes('\n'); }).filter((d, i, a) => !a.some(o => o !== d && o.contains(d)));
  const nombre = f => (f.innerText || '').trim().split('\n')[0];
  // Panel de mensajes (centro) y nombre del chat abierto (para no leer el chat equivocado).
  S.panel = () => [...document.querySelectorAll('div')].filter(d => { const cs = getComputedStyle(d), b = d.getBoundingClientRect(); return /(auto|scroll)/.test(cs.overflowY) && b.left > 450 && b.left < 900 && d.clientHeight > 200 && (d.innerText || '').length > 0; }).sort((a, b) => (b.innerText || '').length - (a.innerText || '').length)[0];
  S.cabecera = () => { let best = null, fs = 0; for (const e of document.querySelectorAll('span,div,h1,h2,h3')) { if (e.childElementCount) continue; const r = e.getBoundingClientRect(); if (!(r.left > 1290 && r.top > 60 && r.top < 130 && r.width > 0 && r.height > 0)) continue; const t = e.textContent.trim(); if (t.length < 2) continue; const f = parseFloat(getComputedStyle(e).fontSize); if (f > fs) { fs = f; best = t; } } return best || ''; };
  const clic = (f, n) => { const t = [...f.querySelectorAll('span,div')].find(e => e.childElementCount === 0 && e.textContent.trim() === n) || f; const b = t.getBoundingClientRect(), x = b.left + 5, y = b.top + b.height / 2; for (const ev of ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click']) t.dispatchEvent(new MouseEvent(ev, { bubbles: true, cancelable: true, clientX: x, clientY: y, view: window })); };

  // Lee el chat abierto: sube hasta el principio y separa cliente (izquierda) / Casa Zaru (derecha) / sistema.
  S.leerAbierto = async () => {
    const p = S.panel(); let h = -1;
    for (let i = 0; i < 15 && p.scrollHeight !== h; i++) { h = p.scrollHeight; p.scrollTop = 0; await dormir(1500); }
    const pr = p.getBoundingClientRect();
    const burbuja = el => { let e = el; while (e && e !== p) { const bg = getComputedStyle(e).backgroundColor; const b = e.getBoundingClientRect(); if (bg && bg !== 'rgba(0, 0, 0, 0)' && bg !== 'transparent' && b.width < pr.width * 0.85) return e; e = e.parentElement; } return null; };
    const w = document.createTreeWalker(p, NodeFilter.SHOW_TEXT); const out = []; let n, last = null;
    while ((n = w.nextNode())) {
      const t = n.textContent.replace(/\u200b/g, '').trim(); if (!t) continue;
      const bu = burbuja(n.parentElement); let lado = 'S';
      if (bu) { const b = bu.getBoundingClientRect(); lado = (b.left - pr.left) < (pr.right - b.right) ? 'CLI' : 'CZ'; }
      if (last && last.bu === bu && bu) { last.t += '\n' + t; continue; }
      last = { bu, lado, t }; out.push(last);
    }
    return out.map(o => o.lado + ': ' + o.t.replace(/\n/g, ' / '));
  };

  S.fotoNoLeidos = async () => {
    const sc = S.lista(), s = new Set(); sc.scrollTop = 0; await dormir(1200);
    for (let i = 0; i < 60; i++) { for (const f of S.filas()) s.add(nombre(f)); const a = sc.scrollTop; sc.scrollTop += 400; await dormir(900); if (sc.scrollTop === a) { await dormir(1500); if (sc.scrollTop === a) break; } }
    sc.scrollTop = 0; S.noLeidos = [...s]; return S.noLeidos.length + ' sin leer';
  };

  S.correr = (prefijos) => {
    S.conv = S.conv || {}; S.log = []; S.fin = false; S.parar = false;
    const nl = new Set(S.noLeidos || []); const pend = new Set(prefijos);
    // Prefijos de 10+ caracteres calzan por el comienzo; los cortos («Pablo», «Mary»), solo exactos.
    const calza = n => [...pend].find(p => p.length >= 10 ? n.startsWith(p) : n === p);
    (async () => {
      // Meta rehace la lista al abrir un chat: se vuelve a buscar en cada paso y se sigue desde la misma altura.
      let pos = 0; S.lista().scrollTop = 0; await dormir(1500);
      for (let paso = 0; paso < 80 && pend.size && !S.parar; paso++) {
        for (const f of S.filas()) {
          const n = nombre(f), p = calza(n); if (!p || S.parar) continue;
          if (nl.has(n)) { pend.delete(p); S.log.push(n + ' · sin leer, no se abre'); continue; }
          try {
            clic(f, n); await dormir(2500);
            const cab = S.cabecera();
            if (!cab || cab.slice(0, 10) !== n.slice(0, 10)) { S.log.push(n + ' ≠ ' + cab); continue; }
            pend.delete(p);
            S.conv[n] = (await S.leerAbierto()).join('\n');
          } catch (e) { S.log.push(n + ' ERR ' + String(e).slice(0, 80)); }
          await dormir(600);
        }
        let sc = S.lista(); if (sc.scrollTop < pos) { sc.scrollTop = pos; await dormir(800); sc = S.lista(); }
        const a = sc.scrollTop; sc.scrollTop += 450; await dormir(1200); sc = S.lista(); pos = sc.scrollTop;
        if (pos === a) { await dormir(2000); sc = S.lista(); pos = sc.scrollTop; if (pos === a) break; }
      }
      S.pendientes = [...pend]; S.fin = true;
    })();
    return pend.size + ' por buscar';
  };
  S.estado = () => ({ leidos: Object.keys(S.conv || {}).length, log: (S.log || []).slice(-4), fin: S.fin, faltan: S.fin ? S.pendientes : undefined });

  // Del texto leído a mensajes con fecha. Los separadores («Vie, 5:39 pm», «16 nov 2026, 12:07 pm») dan la
  // hora; los mensajes entre dos separadores van de a un minuto. `hoy` = la fecha del día de la lectura.
  S.armar = (n, hoy = new Date()) => {
    const MES = { ene: 1, feb: 2, mar: 3, abr: 4, may: 5, jun: 6, jul: 7, ago: 8, sep: 9, oct: 10, nov: 11, dic: 12 };
    const DIA = { dom: 0, lun: 1, mar: 2, mie: 3, 'mié': 3, jue: 4, vie: 5, sab: 6, 'sáb': 6 };
    const fijar = (y, mes, dia, h, m, pm) => Date.parse(y + '-' + String(mes).padStart(2, '0') + '-' + String(dia).padStart(2, '0') + 'T' + String(h % 12 + (pm ? 12 : 0)).padStart(2, '0') + ':' + String(m).padStart(2, '0') + ':00-03:00');
    let t = null, msgs = [], saltar = false;
    for (const l of S.conv[n].split('\n')) {
      if (l.startsWith('S: ')) {
        const s = l.slice(3).trim();
        if (/respondi[oó] a/i.test(s)) { saltar = true; continue; }
        const hm = s.match(/(\d{1,2}):(\d{2})\s*(am|pm)/i); if (!hm) continue;
        const d0 = new Date(hoy); let y = d0.getFullYear(), mes = d0.getMonth() + 1, dia = d0.getDate();
        const f = s.match(/(\d{1,2})(?: de)? (ene|feb|mar|abr|may|jun|jul|ago|sep|oct|nov|dic)\w*\.?(?: (\d{4}))?/i);
        const d = s.match(/^(lun|mar|mi[eé]|jue|vie|s[aá]b|dom)\w*,/i);
        if (f) { dia = +f[1]; mes = MES[f[2].toLowerCase()]; if (f[3]) y = +f[3]; }
        else if (d || /^ayer/i.test(s)) { const k = d ? ((d0.getDay() - DIA[d[1].toLowerCase()] + 7) % 7 || 7) : 1; const x = new Date(d0); x.setDate(x.getDate() - k); y = x.getFullYear(); mes = x.getMonth() + 1; dia = x.getDate(); }
        const nt = fijar(y, mes, dia, +hm[1], +hm[2], /pm/i.test(hm[3]));
        if (!t || nt > t) t = nt;
        continue;
      }
      const m = l.match(/^(CLI|CZ): ?(.*)$/);
      if (!m) continue;
      if (saltar) { saltar = false; continue; }
      let texto = m[2].split(' / ').join('\n').trim();
      // Lo que no es un mensaje: contadores, mensajes borrados, la respuesta de ausencia, vistas previas de links.
      if (!texto || /^\d{1,2}$/.test(texto) || /no estamos disponibl|^Eliminaste este mensaje|^Se elimin[oó] este mensaje/i.test(texto)) continue;
      if (/^https:\/\/cotizador\.casazaru\.cl\/?$|^Si prefieres, puedes dejarnos un mensaje/i.test(texto)) continue;
      texto = texto.replace(/^(Cotizador en Línea · Casa Zaru|Starken \| Tus envíos)[^\n]*(\n|$)/i, '').trim();
      if (/^Cotizador en Línea · Casa Zaru|^Starken \| Tus envíos/i.test(texto) || !texto) continue;
      let autor = m[1] === 'CLI' ? 'cliente' : 'cesar', tipo = 'text';
      if (/^https?:\/\/\S*(casazaru|drive\.google|starken)/i.test(texto)) autor = 'cesar';
      if (/^Message can't be displayed/i.test(texto)) { tipo = 'image'; texto = texto.replace(/^Message can't be displayed[^\n]*(WhatsApp Business App\.)?\s*/i, '').trim() || null; }
      else if (/^(\d:\d\d)(\n\1)?$/.test(texto)) { tipo = 'audio'; texto = null; }
      else if (/\.(pdf|docx?|xlsx?|dwg)\b[^\n]*\b(KiB|MiB|KB|MB)\b/i.test(texto)) { tipo = 'document'; }
      t = (t || Date.parse('2026-11-01T10:00:00-03:00')) + 60000;
      msgs.push({ autor, tipo, texto, enviado_at: new Date(t).toISOString() });
    }
    return msgs;
  };

  S.preparar = (maxMsgs = 50) => {
    const tapar = s => s == null ? s : s.replace(/[\w.+-]+@[\w-]+\.[\w.]+/g, '[correo]').replace(/\b\d{1,2}\.?\d{3}\.?\d{3}-[\dkK]\b/g, '[rut]').replace(/\+?\d[\d \-]{6,}\d/g, m => (m.replace(/\D/g, '').length >= 7 ? '[número]' : m)).slice(0, 700);
    const out = {}; S.alias = {}; let i = 0;
    for (const k of Object.keys(S.conv)) {
      let m; try { m = S.armar(k); } catch (e) { continue; }
      m = m.map(x => Object.assign({}, x, { texto: tapar(x.texto) })).slice(-maxMsgs);
      if (!m.some((x, j) => x.autor === 'cliente' && m[j + 1] && m[j + 1].autor === 'cesar')) continue;
      const a = 'C' + String(++i).padStart(2, '0'); S.alias[a] = k; out[a] = { nombre: k.split(/[ (]/)[0], mensajes: m };
    }
    S.datos = out; return Object.keys(out).length + ' chats · ' + JSON.stringify(out).length + ' car.';
  };
  return 'simulador listo';
})();
