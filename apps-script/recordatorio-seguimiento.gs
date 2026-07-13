/**
 * Casa Zaru — Recordatorio diario de seguimientos (15:00).
 * Lee las cotizaciones de Supabase, calcula a quién toca contactar HOY
 * (cadencia 1/3/7/14/30 días) y manda un correo a César y al admin.
 *
 * INSTALACIÓN (una sola vez):
 *  1. script.google.com → Nuevo proyecto → pega este archivo completo.
 *  2. Ejecuta la función `probarAhora` una vez y autoriza los permisos
 *     (Gmail + red). Revisa que llegue el correo de prueba.
 *  3. Menú izquierdo → ⏰ Activadores (Triggers) → Añadir activador:
 *       función: enviarRecordatorio | evento: por tiempo | tipo: diario |
 *       hora: 15:00–16:00. Guarda.
 *  Listo: cada día a las 15:00 llega el correo con los seguimientos del día.
 */

var SB_URL = 'https://cmxqorsyxoltrakxawro.supabase.co';
var SB_KEY = 'sb_publishable_Z4Bu9BnRkjiKmuCUzUGz0Q_hwxOc-Go';
var TZ = 'America/Santiago';

var CAD = [1, 3, 7, 14, 30];
var VENDEDORES = [
  { code:'cesar', nombre:'César', email:'crodriguez.casazaru@gmail.com', legacy:['hola@casazaru.cl'] }
];
var ADMIN_EMAIL = 'hola@casazaru.cl';
var PANEL_BASE = 'https://cotizador.casazaru.cl/';
var PNAME = {
  cubierta:'Cubiertas', repisa:'Repisa / Cubierta 2cm', peldano:'Peldaños',
  granero:'Puerta Granero', maciza:'Puerta Maciza', vidrios:'Puerta con Vidrios',
  revestimiento:'Revestimiento'
};

/* ── Helpers de fecha ── */
function isoHoy(){ return Utilities.formatDate(new Date(), TZ, 'yyyy-MM-dd'); }
function isoDe(dt){ return Utilities.formatDate(dt, TZ, 'yyyy-MM-dd'); }
function addDias(iso, n){ var p=iso.split('-'); var d=new Date(+p[0], +p[1]-1, +p[2]); d.setDate(d.getDate()+n); return isoDe(d); }

/* ── Origen/dueño (igual que el panel) ── */
function ownerCode(x){
  for (var i=0;i<VENDEDORES.length;i++){
    var v=VENDEDORES[i];
    if (x.user_email===v.email || x.asignado_a===v.email || (v.legacy && v.legacy.indexOf(x.user_email)!==-1)) return v.code;
  }
  return null;
}
function isWeb(x){ return !x.user_email && ownerCode(x)===null; }

function waPhone(c){
  var d=String(c||'').replace(/\D/g,'');
  if (d.length===11 && d.slice(0,3)==='569') return d;
  if (d.length===9 && d[0]==='9') return '56'+d;
  if (d.length===8) return '569'+d;
  if (d.length===11 && d.slice(0,2)==='56') return d;
  return null;
}
function clientKey(x){
  var t=waPhone(x.contacto); if (t) return 't'+t;
  var c=String(x.contacto||'').trim().toLowerCase(); if (c.indexOf('@')!==-1) return 'e'+c;
  var n=String(x.cliente||'').trim().toLowerCase().replace(/\s+/g,' ');
  return n ? 'n'+n : 'q'+x.id;
}
function dueDate(x){
  if ((x.estado||'enviada')!=='enviada') return null;
  var due;
  if (x.seg_proxima) due = String(x.seg_proxima).slice(0,10);
  else {
    var etapa = x.seg_etapa||0;
    if (etapa>=CAD.length || !x.fecha_creacion) return null;
    var b=new Date(x.fecha_creacion); b.setDate(b.getDate()+CAD[etapa]); due=isoDe(b);
  }
  if (due < addDias(isoHoy(),-30)) return null;
  return due;
}
function fmt(n){ return '$' + Math.round(n||0).toLocaleString('es-CL'); }

/* ── Traer cotizaciones enviadas desde Supabase ── */
function fetchEnviadas(){
  var url = SB_URL + '/rest/v1/cotizaciones?select=*&estado=eq.enviada';
  var res = UrlFetchApp.fetch(url, { headers: { apikey: SB_KEY, Authorization: 'Bearer ' + SB_KEY }, muteHttpExceptions: true });
  if (res.getResponseCode() >= 300) throw new Error('Supabase ' + res.getResponseCode() + ': ' + res.getContentText());
  return JSON.parse(res.getContentText());
}

/* ── Agrupar por cliente y quedarse con los que tocan HOY (vencidos + de hoy) ── */
function gruposDeHoy(rows){
  var map = {};
  rows.forEach(function(x){ var k=clientKey(x); (map[k]=map[k]||[]).push(x); });
  var hoy = isoHoy(), out = [];
  Object.keys(map).forEach(function(k){
    var qs = map[k].slice().sort(function(a,b){ return new Date(b.fecha_creacion||0)-new Date(a.fecha_creacion||0); });
    var lead = qs[0];
    var due = dueDate(lead);
    if (!due || due > hoy) return;   /* solo lo accionable hoy: vencidos + de hoy */
    var owner='web';
    for (var i=0;i<qs.length;i++){ var oc=ownerCode(qs[i]); if (oc){ owner=oc; break; } }
    var valor = qs.reduce(function(a,q){ return Math.max(a, q.total_alto||0); }, 0);
    out.push({ lead:lead, owner:owner, valor:valor, nQ:qs.length, vencido: due < hoy });
  });
  out.sort(function(a,b){ return b.valor-a.valor; });   /* mayor monto primero */
  return out;
}

/* ── Armar el cuerpo del correo (HTML) ── */
function htmlLista(grupos, titulo, panelUrl){
  if (!grupos.length) return '<p style="font-family:Arial;color:#555">Sin seguimientos para hoy en <b>'+titulo+'</b> 🎉</p>';
  var filas = grupos.map(function(g){
    var x=g.lead;
    var tel = x.contacto ? String(x.contacto) : 'sin contacto';
    var prod = PNAME[x.producto]||x.producto||'';
    var extra = g.nQ>1 ? ' · '+g.nQ+' cotizaciones' : '';
    var flag = g.vencido ? '<span style="color:#B91C1C;font-weight:bold">⏰ atrasado</span> ' : '';
    return '<tr>'+
      '<td style="padding:6px 10px;border-bottom:1px solid #eee">'+flag+'<b>'+(x.cliente||'—')+'</b><br><span style="color:#777;font-size:12px">'+tel+extra+'</span></td>'+
      '<td style="padding:6px 10px;border-bottom:1px solid #eee;color:#555">'+prod+'</td>'+
      '<td style="padding:6px 10px;border-bottom:1px solid #eee;text-align:right;font-weight:bold">'+fmt(g.valor)+'</td>'+
    '</tr>';
  }).join('');
  return '<h3 style="font-family:Arial;color:#7A5620;margin:16px 0 6px">'+titulo+' — '+grupos.length+' por contactar</h3>'+
    '<table style="border-collapse:collapse;width:100%;font-family:Arial;font-size:14px">'+filas+'</table>'+
    '<p style="margin:10px 0"><a href="'+panelUrl+'" style="background:#B8894A;color:#fff;text-decoration:none;padding:9px 18px;border-radius:8px;font-family:Arial;font-size:14px">Abrir panel y marcar →</a></p>';
}

/* ── Función principal (la que dispara el activador de las 15:00) ── */
function enviarRecordatorio(){
  var rows = fetchEnviadas();
  var grupos = gruposDeHoy(rows);
  var deCesar = grupos.filter(function(g){ return g.owner==='cesar'; });
  var deWeb   = grupos.filter(function(g){ return g.owner==='web'; });
  var hoyTxt  = Utilities.formatDate(new Date(), TZ, 'dd-MM-yyyy');

  /* Correo a César: sus clientes + los web */
  var cuerpoCesar =
    '<div style="max-width:640px;margin:auto">'+
    '<h2 style="font-family:Arial;color:#7A5620">¿Hiciste seguimiento a estas personas? · '+hoyTxt+'</h2>'+
    htmlLista(deCesar, '👤 Mis clientes', PANEL_BASE+'?panel=cesar')+
    htmlLista(deWeb,   '🌐 Clientes Web', PANEL_BASE+'?panel=cesar')+
    '</div>';
  MailApp.sendEmail({
    to: 'crodriguez.casazaru@gmail.com',
    subject: '📋 Seguimientos de hoy ('+(deCesar.length+deWeb.length)+') — '+hoyTxt,
    htmlBody: cuerpoCesar
  });

  /* Correo al admin: resumen general */
  var cuerpoAdmin =
    '<div style="max-width:640px;margin:auto">'+
    '<h2 style="font-family:Arial;color:#7A5620">Resumen de seguimientos · '+hoyTxt+'</h2>'+
    '<p style="font-family:Arial;color:#555">Total por contactar hoy: <b>'+grupos.length+'</b> · '+
      'César: '+deCesar.length+' · Web: '+deWeb.length+'</p>'+
    htmlLista(grupos, 'Todos los seguimientos', PANEL_BASE+'?panel=zr25')+
    '</div>';
  MailApp.sendEmail({
    to: ADMIN_EMAIL,
    subject: '📊 Resumen seguimientos ('+grupos.length+') — '+hoyTxt,
    htmlBody: cuerpoAdmin
  });
}

/* Ejecuta esto a mano una vez para probar (autoriza permisos y revisa el correo). */
function probarAhora(){ enviarRecordatorio(); }
