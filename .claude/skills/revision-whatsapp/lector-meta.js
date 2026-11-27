// Lector de la bandeja de WhatsApp (5558) en Meta Business Suite · solo lectura.
// Se pega una vez por sesión con javascript_tool en la pestaña de la bandeja (inbox/wec, pestaña WhatsApp).
// No escribe, no envía y no reacciona. Solo hace clic en la lista de chats y, si se le pide, en
// «Marcar como no leído».
//
// Uso (cada llamada devuelve poco texto, porque la herramienta corta cerca de 1.000 caracteres):
//   await Z.lista('2026-11-25T13:35')   → recorre la lista y guarda los chats con actividad desde esa hora
//   Z.resumenLista(0)                  → la lista en páginas: n|nombre|hora|NO LEÍDO|preview
//   await Z.leerTodos({saltar:[...]})  → abre cada chat de la lista (salvo los de saltar), sube hasta la hora
//                                        de corte y guarda solo lo nuevo, con teléfono e id del hilo
//   Z.pagina(0)                        → lo leído, en páginas de 900 caracteres
//   await Z.noLeidos()                 → nombres en negrita (sin leer) de la lista completa
//   await Z.marcarNoLeido('Nombre')    → abre ese chat y lo deja como no leído (para devolver el estado)
//   Z.ver('texto')                     → lleva a la vista el mensaje con ese texto (para capturar comprobantes)
(() => {
  const Z = window.Z = window.Z || {};
  const dormir = ms => new Promise(r => setTimeout(r, ms));
  const DIAS = { dom: 0, lun: 1, mar: 2, 'mié': 3, mie: 3, jue: 4, vie: 5, 'sáb': 6, sab: 6 };
  const MESES = { ene: 0, feb: 1, mar: 2, abr: 3, may: 4, jun: 5, jul: 6, ago: 7, sept: 8, sep: 8, oct: 9, nov: 10, dic: 11 };

  // «10:16 am», «Mar, 5:39 pm», «16 nov 2026, 12:07 pm», «Hoy», «Ayer», «Lun» → Date (null si no es fecha)
  Z.fecha = (s, ahora = new Date()) => {
    s = (s || '').trim().toLowerCase().replace(/\u202f|\u00a0/g, ' ');
    const hm = s.match(/(\d{1,2}):(\d{2})\s*(a\.?\s*m\.?|p\.?\s*m\.?)$/);
    const h = hm ? ((+hm[1] % 12) + (/p/.test(hm[3]) ? 12 : 0)) : 23, mi = hm ? +hm[2] : 59;
    const base = new Date(ahora); base.setHours(h, mi, 0, 0);
    if (/^\d{1,2}:\d{2}/.test(s) || s === 'hoy') return base;
    if (s.startsWith('ayer')) { base.setDate(base.getDate() - 1); return base; }
    const d = s.match(/^(dom|lun|mar|mié|mie|jue|vie|sáb|sab)[a-zéá]*(?=\s|,|$)/);
    if (d) { let k = (ahora.getDay() - DIAS[d[1]] + 7) % 7; if (k === 0) k = 7; base.setDate(base.getDate() - k); return base; }
    const f = s.match(/^(\d{1,2}) (\w+)\.? (\d{4})/);
    if (f && MESES[f[2].slice(0, 4).replace('.', '')] !== undefined) return new Date(+f[3], MESES[f[2].slice(0, 4).replace('.', '')], +f[1], h, mi);
    if (f && MESES[f[2].slice(0, 3)] !== undefined) return new Date(+f[3], MESES[f[2].slice(0, 3)], +f[1], h, mi);
    return null;
  };

  // Ubica la lista de chats (columna izquierda) y su contenedor con scroll. Se rehace en cada llamada
  // porque Meta redibuja la lista cuando entra un mensaje o se marca un chat.
  Z.ubicar = () => {
    const filas = [...document.querySelectorAll('div')].filter(d => d.childElementCount >= 5 && d.getBoundingClientRect().left < 700 &&
      [...d.children].filter(c => /\n(\d{1,2}:\d{2}\s?[ap]m|Hoy|Ayer|Lun|Mar|Mié|Jue|Vie|Sáb|Dom)[a-zéá]*(?=\s|,|$)/i.test(c.innerText || '')).length >= 4);
    Z.filas = filas.sort((a, b) => b.childElementCount - a.childElementCount)[0];
    let p = Z.filas; Z.sc = null;
    while (p) { const cs = getComputedStyle(p); if (/(auto|scroll)/.test(cs.overflowY) && p.scrollHeight > p.clientHeight) { Z.sc = p; break; } p = p.parentElement; }
    return !!(Z.filas && Z.sc);
  };

  const nombreDe = fila => (fila.innerText || '').trim().split('\n')[0];
  const enNegrita = fila => { const n = nombreDe(fila); return [...fila.querySelectorAll('span,div')].some(e => e.childElementCount === 0 && e.textContent.trim() === n && +getComputedStyle(e).fontWeight >= 600); };
  const horaDe = fila => { const ps = (fila.innerText || '').split('\n').map(x => x.trim()).slice(1); return ps.find(x => /^\d{1,2}:\d{2}\s?[ap]m$/i.test(x)) || ps.find(x => /^(Hoy|Ayer|Lun|Mar|Mié|Jue|Vie|Sáb|Dom)[a-zéá]*$/i.test(x)) || ps.find(x => /^\d{1,2} \w+/.test(x)) || ''; };

  // Meta a veces escribe el día entero («jueves»): todos los patrones aceptan «Jue» y «jueves» (27-11).
  // horaDe salta la primera línea (el nombre), para que «Martina» o «Domingo» no se lean como día.
  // Recorre la lista de arriba abajo hasta pasar la hora de corte. Guarda en Z.movidos.
  Z.lista = async (desde) => {
    Z.corte = new Date(desde); if (!Z.ubicar()) return 'NO ENCONTRÉ LA LISTA';
    Z.sc.scrollTop = 0; await dormir(900);
    const vistos = new Map(); let pasado = 0;
    for (let i = 0; i < 60 && pasado < 3; i++) {
      Z.ubicar();
      for (const f of Z.filas.children) {
        const n = nombreDe(f); if (!n || vistos.has(n)) continue;
        const h = horaDe(f), d = Z.fecha(h);
        const ps = f.innerText.trim().split('\n');
        vistos.set(n, { nombre: n, hora: h, fecha: d, noLeido: enNegrita(f), preview: (ps[1] || '').slice(0, 70) });
        // «Lun», «Mar»… sin hora quedan a las 23:59 de ese día: entran si el día toca el corte
        if (d && d < Z.corte && !/^(Lun|Mar|Mié|Jue|Vie|Sáb|Dom|Ayer)[a-zéá]*$/i.test(h)) pasado++;
        else if (d && /^(Lun|Mar|Mié|Jue|Vie|Sáb|Dom|Ayer)[a-zéá]*$/i.test(h) && d < new Date(Z.corte.getTime() - 864e5)) pasado++;
      }
      const antes = Z.sc.scrollTop; Z.sc.scrollTop += 450; await dormir(800);
      if (Z.sc.scrollTop === antes) { await dormir(1500); if (Z.sc.scrollTop === antes) break; }
    }
    Z.sc.scrollTop = 0;
    Z.todos = [...vistos.values()];
    Z.movidos = Z.todos.filter(x => x.fecha && (x.fecha >= Z.corte || (/^(Lun|Mar|Mié|Jue|Vie|Sáb|Dom|Ayer)[a-zéá]*$/i.test(x.hora) && x.fecha >= Z.corte)));
    Z.leidoAntes = Z.todos.filter(x => x.noLeido).map(x => x.nombre);
    return `lista: ${Z.todos.length} · movidos desde el corte: ${Z.movidos.length} · sin leer: ${Z.leidoAntes.length}`;
  };

  Z.resumenLista = (pag = 0, tam = 18) => Z.movidos.slice(pag * tam, pag * tam + tam)
    .map((x, i) => `${pag * tam + i}|${x.nombre.slice(0, 30)}|${x.hora}${x.noLeido ? '|NO LEÍDO' : ''}|${x.preview.slice(0, 45)}`).join('\n');

  // Abre un chat haciendo clic en su nombre en la lista. Espera a que cambie el hilo seleccionado.
  Z.abrir = async (nombre) => {
    Z.ubicar(); Z.sc.scrollTop = 0; await dormir(500);
    let fila = null;
    for (let i = 0; i < 40 && !fila; i++) {
      Z.ubicar(); fila = [...Z.filas.children].find(f => nombreDe(f) === nombre);
      if (!fila) { Z.sc.scrollTop += 450; await dormir(550); }
    }
    if (!fila) return false;
    fila.scrollIntoView({ block: 'center' }); await dormir(350);
    const antes = new URL(location.href).searchParams.get('selected_item_id');
    const t = [...fila.querySelectorAll('span,div')].find(e => e.childElementCount === 0 && e.textContent.trim() === nombre) || fila;
    const b = t.getBoundingClientRect(), x = b.left + 5, y = b.top + b.height / 2;
    for (const ev of ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click']) t.dispatchEvent(new MouseEvent(ev, { bubbles: true, cancelable: true, clientX: x, clientY: y, view: window }));
    for (let i = 0; i < 20; i++) { await dormir(300); if (new URL(location.href).searchParams.get('selected_item_id') !== antes) break; }
    await dormir(1500);
    return true;
  };

  const panelMensajes = () => [...document.querySelectorAll('div')].filter(d => { const cs = getComputedStyle(d), b = d.getBoundingClientRect(); return /(auto|scroll)/.test(cs.overflowY) && b.left > 450 && b.left < 900 && d.clientHeight > 200; }).sort((a, b) => b.clientHeight - a.clientHeight)[0];
  const textoChat = () => { const body = document.body.innerText, a = body.indexOf('Mover a listo'), b = body.indexOf('Responde en WhatsApp');
    return body.slice(a + 13, b > 0 ? b : undefined).replace(/\n?Respuesta sugerida[\s\S]*$/, '').replace(/\n[\u200b ]*\n/g, '\n').replace(/^(\d:\d\d)\n\1$/gm, '[audio $1]'); };
  const telefono = () => { const body = document.body.innerText, b = body.indexOf('Responde en WhatsApp'); return ((body.slice(b).match(/\+56[\d ]{9,14}/) || [''])[0]).replace(/\D/g, ''); };
  const SEP = /^(Hoy|Ayer|Lun|Mar|Mié|Jue|Vie|Sáb|Dom)[a-zéá]*(, \d{1,2}:\d{2}\s?[ap]m)?$|^\d{1,2}:\d{2}\s?[ap]m$|^\d{1,2} \w+\.? \d{4}, \d{1,2}:\d{2}\s?[ap]m$/i;

  // Del texto del chat, lo que viene desde el último separador de fecha anterior al corte.
  const desdeCorte = (txt) => {
    const ls = txt.split('\n'); let ini = 0, viejo = false;
    ls.forEach((l, i) => { if (SEP.test(l.trim())) { const d = Z.fecha(l); if (d && d < Z.corte) { ini = i + 1; viejo = true; } } });
    // contexto: las 4 líneas anteriores al corte, marcadas
    const ctx = viejo ? ls.slice(Math.max(0, ini - 5), ini).join(' / ') : '';
    return { viejo, ctx: ctx.slice(-300), nuevo: ls.slice(ini).join('\n').trim() };
  };

  // Lee un chat: sube hasta encontrar un separador anterior al corte (máx. 6 subidas).
  Z.leer = async (nombre) => {
    if (!(await Z.abrir(nombre))) return { nombre, error: 'no encontrado' };
    const ms = panelMensajes();
    let r = desdeCorte(textoChat());
    for (let i = 0; i < 6 && !r.viejo && ms; i++) { ms.scrollTop = 0; await dormir(1700); r = desdeCorte(textoChat()); }
    return { nombre, id: new URL(location.href).searchParams.get('selected_item_id'), tel: telefono(), antes: r.ctx, nuevo: r.nuevo, completo: r.viejo };
  };

  Z.leerTodos = async ({ saltar = [], solo = null } = {}) => {
    Z.res = [];
    const lista = (solo || Z.movidos.map(x => x.nombre)).filter(n => !saltar.some(s => n.startsWith(s)));
    for (const n of lista) { try { Z.res.push(await Z.leer(n)); } catch (e) { Z.res.push({ nombre: n, error: String(e) }); } }
    Z.texto = Z.res.map(r => `### ${r.nombre} · tel ${r.tel || '?'} · id ${r.id || '?'}${r.completo ? '' : ' · (no llegué al corte: ver más arriba)'}${r.error ? ' · ERROR ' + r.error : ''}\n` +
      (r.antes ? `[antes] ${r.antes}\n` : '') + (r.nuevo || '')).join('\n\n');
    return `leídos ${Z.res.length} · texto ${Z.texto.length} car. · páginas ${Math.ceil(Z.texto.length / 900)}`;
  };
  Z.pagina = (i, tam = 900) => Z.texto.slice(i * tam, i * tam + tam);

  Z.noLeidos = async () => {
    Z.ubicar(); Z.sc.scrollTop = 0; await dormir(800); const s = new Set();
    for (let i = 0; i < 30; i++) { Z.ubicar(); for (const f of Z.filas.children) if (enNegrita(f)) s.add(nombreDe(f)); const a = Z.sc.scrollTop; Z.sc.scrollTop += 450; await dormir(650); if (Z.sc.scrollTop === a) break; }
    Z.sc.scrollTop = 0; return [...s];
  };

  // Devuelve un chat a «no leído». Busca el botón por su nombre accesible.
  Z.marcarNoLeido = async (nombre) => {
    if (nombre && !(await Z.abrir(nombre))) return 'no encontrado ' + nombre;
    const cand = [...document.querySelectorAll('[aria-label],[role=button],div,span')].filter(e => (e.getAttribute('aria-label') || '') === 'Marcar como no leído' || (e.childElementCount === 0 && e.textContent.trim() === 'Marcar como no leído'));
    for (const c of cand) {
      const btn = c.closest('[role=button],button') || c; const b = btn.getBoundingClientRect(); if (!b.width) continue;
      const x = b.left + b.width / 2, y = b.top + b.height / 2;
      for (const ev of ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click']) btn.dispatchEvent(new MouseEvent(ev, { bubbles: true, cancelable: true, clientX: x, clientY: y, view: window }));
      await dormir(1200);
      Z.ubicar(); const f = [...Z.filas.children].find(f => nombreDe(f) === nombre);
      if (!nombre || (f && enNegrita(f))) return 'marcado ' + (nombre || '');
    }
    return 'NO SE PUDO marcar ' + nombre + ' (usar find «Marcar como no leído» + clic por ref)';
  };

  Z.ver = (txt) => { const el = [...document.querySelectorAll('div,span')].filter(e => e.textContent.includes(txt)).sort((a, b) => a.textContent.length - b.textContent.length)[0]; if (!el) return 'no'; el.scrollIntoView({ block: 'center' }); return 'ok'; };
  return 'lector listo';
})();
