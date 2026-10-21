'use strict';
const L = ['es', 'en', 'pt'];
const D = {
  lang: ['Idioma', 'Language', 'Idioma'], theme: ['Tema', 'Theme', 'Tema'], auto: ['Automático', 'Auto', 'Automático'], light: ['Claro', 'Light', 'Claro'], dark: ['Oscuro', 'Dark', 'Escuro'],
  runAll: ['Ejecutar todo', 'Run all', 'Executar tudo'], export: ['Exportar JSON', 'Export JSON', 'Exportar JSON'], clear: ['Limpiar', 'Clear', 'Limpar'], run: ['Ejecutar', 'Run', 'Executar'],
  nav: ['Secciones', 'Sections', 'Seções'], nForms: ['Formularios', 'Forms', 'Formulários'], nUi: ['Interacción', 'UI', 'Interação'], nMedia: ['Multimedia', 'Media', 'Multimídia'], nApi: ['APIs web', 'Web APIs', 'APIs web'],
  nHttp: ['Cliente HTTP', 'HTTP client', 'Cliente HTTP'], nPerf: ['Rendimiento', 'Performance', 'Desempenho'], nCss: ['CSS y render', 'CSS & render', 'CSS e render'], nDiag: ['Diagnóstico', 'Diagnostics', 'Diagnóstico'], console: ['Consola', 'Console', 'Console'],
  submit: ['Enviar', 'Submit', 'Enviar'], reset: ['Reiniciar', 'Reset', 'Reiniciar'], addField: ['Añadir campo', 'Add field', 'Adicionar campo'], valid: ['Formulario válido', 'Form valid', 'Formulário válido'], invalid: ['Formulario inválido', 'Form invalid', 'Formulário inválido'],
  chars: ['caracteres', 'chars', 'caracteres'], pwRule: ['Mínimo 8 caracteres y un dígito', 'Min 8 chars and a digit', 'Mínimo 8 caracteres e um dígito'], events: ['Eventos', 'Events', 'Eventos'], remove: ['Quitar', 'Remove', 'Remover'],
  btnP: ['Primario', 'Primary', 'Primário'], btnS: ['Secundario', 'Secondary', 'Secundário'], btnD: ['Destructivo', 'Destructive', 'Destrutivo'], btnX: ['Deshabilitado', 'Disabled', 'Desabilitado'], btnLoad: ['Botón de carga', 'Loading button', 'Botão de carga'], loadingBtn: ['Cargando…', 'Loading…', 'Carregando…'],
  feat: ['Función', 'Feature', 'Recurso'], sw: ['Interruptor', 'Switch', 'Interruptor'], menu: ['Menú', 'Menu', 'Menu'], notify: ['Notificar', 'Notify', 'Notificar'], openModal: ['Abrir modal', 'Open modal', 'Abrir modal'], copy: ['Copiar', 'Copy', 'Copiar'],
  ctxHint: ['Clic derecho o Mayús+F10', 'Right-click or Shift+F10', 'Clique direito ou Shift+F10'], acc: ['Acordeón', 'Accordion', 'Acordeão'], accBody: ['Contenido desplegado.', 'Expanded content.', 'Conteúdo expandido.'],
  list: ['Lista dinámica (arrastra o usa ↑↓)', 'Dynamic list (drag or use ↑↓)', 'Lista dinâmica (arraste ou use ↑↓)'], newItem: ['Nuevo elemento', 'New item', 'Novo item'], add: ['Añadir', 'Add', 'Adicionar'], edit: ['Editar', 'Edit', 'Editar'], del: ['Eliminar', 'Delete', 'Excluir'], save: ['Guardar', 'Save', 'Salvar'],
  ok: ['Aceptar', 'OK', 'OK'], cancel: ['Cancelar', 'Cancel', 'Cancelar'], confirmT: ['Confirmar acción', 'Confirm action', 'Confirmar ação'], confirmQ: ['¿Eliminar este elemento?', 'Delete this item?', 'Excluir este item?'], modalT: ['Modal', 'Modal', 'Modal'], modalM: ['Escape o Cancelar para cerrar.', 'Press Escape or Cancel to close.', 'Escape ou Cancelar para fechar.'],
  done: ['Hecho', 'Done', 'Pronto'], copied: ['Copiado', 'Copied', 'Copiado'], copyFail: ['No se pudo copiar', 'Copy failed', 'Falha ao copiar'], on: ['activado', 'on', 'ativado'], off: ['desactivado', 'off', 'desativado'],
  pickImg: ['Imagen local (máx 5 MB)', 'Local image (max 5 MB)', 'Imagem local (máx 5 MB)'], imgLoad: ['Cargando imagen…', 'Loading image…', 'Carregando imagem…'], imgOk: ['Imagen cargada', 'Image loaded', 'Imagem carregada'], imgErr: ['Error al cargar la imagen remota', 'Remote image failed to load', 'Falha ao carregar a imagem remota'],
  imgAlt: ['Foto de demostración', 'Demo photo', 'Foto de demonstração'], badType: ['Tipo no válido', 'Invalid type', 'Tipo inválido'], tooBig: ['Archivo demasiado grande', 'File too large', 'Arquivo muito grande'], prevOk: ['Vista previa lista', 'Preview ready', 'Pré-visualização pronta'],
  vFail: ['Vídeo no disponible (recurso externo bloqueado o sin conexión).', 'Video unavailable (external resource blocked or offline).', 'Vídeo indisponível (recurso externo bloqueado ou offline).'], dur: ['duración', 'duration', 'duração'], pos: ['posición', 'position', 'posição'],
  cvAlt: ['Gráfico animado', 'Animated chart', 'Gráfico animado'], svgAlt: ['Ilustración SVG interactiva', 'Interactive SVG', 'Ilustração SVG interativa'], svgBtn: ['Alternar forma', 'Toggle shape', 'Alternar forma'], cvClick: ['Clic en', 'Click at', 'Clique em'],
  send: ['Enviar petición', 'Send request', 'Enviar requisição'], badJson: ['JSON no válido en', 'Invalid JSON in', 'JSON inválido em'], netErr: ['Error de red/CORS', 'Network/CORS error', 'Erro de rede/CORS'], timeout: ['Tiempo agotado', 'Timed out', 'Tempo esgotado'], aborted: ['Cancelado', 'Cancelled', 'Cancelado'], noReq: ['Sin petición en curso', 'No request in flight', 'Sem requisição em andamento'],
  cssNote: ['CSS.supports indica soporte declarado, no renderizado correcto: revisa visualmente cada muestra.', 'CSS.supports reports declared support, not correct rendering: inspect each sample visually.', 'CSS.supports indica suporte declarado, não renderização correta: confira cada amostra visualmente.'],
  st_ok: ['OK', 'OK', 'OK'], st_unsupported: ['No compatible', 'Unsupported', 'Não suportado'], st_denied: ['Permiso denegado', 'Permission denied', 'Permissão negada'], st_insecure: ['Contexto inseguro', 'Insecure context', 'Contexto inseguro'], st_blocked: ['Recurso bloqueado', 'Blocked resource', 'Recurso bloqueado'], st_error: ['Error', 'Error', 'Erro'], st_pending: ['Sin ejecutar', 'Not run', 'Não executado'], st_fail: ['Fallo', 'Fail', 'Falha'],
  stReady: ['Listo', 'Ready', 'Pronto'], stRun: ['Ejecutando…', 'Running…', 'Executando…'], stDone: ['Completado', 'Completed', 'Concluído'], online: ['en línea', 'online', 'online'], offline: ['sin conexión', 'offline', 'offline'], manual: ['(manual)', '(manual)', '(manual)'],
  cleared: ['Resultados limpiados', 'Results cleared', 'Resultados limpos'], exported: ['Informe exportado', 'Report exported', 'Relatório exportado'], dMem: ['Memoria JS', 'JS memory', 'Memória JS'], dErr: ['Errores capturados', 'Captured errors', 'Erros capturados']
};
const $ = (s, r = document) => r.querySelector(s), $$ = (s, r = document) => [...r.querySelectorAll(s)];
const el = (tag, props = {}, ...kids) => { const e = document.createElement(tag); Object.assign(e, props); e.append(...kids); return e; };
const wait = ms => new Promise(r => setTimeout(r, ms));
const tmo = (p, ms = 6000) => Promise.race([p, new Promise((_, rej) => setTimeout(() => rej(Object.assign(new Error('timeout'), { name: 'TimeoutError' })), ms))]);
const store = { get(k) { try { return localStorage.getItem(k); } catch { return null; } }, set(k, v) { try { localStorage.setItem(k, v); return true; } catch { return false; } } };

/* ---- State ---- */
const S = { lang: 'es', theme: 'auto', results: [], errors: [], last: {}, started: new Date().toISOString() };
const t = k => (D[k] || [k, k, k])[L.indexOf(S.lang)];

/* ---- Results / log ---- */
function record(cat, id, st, ms, detail = '') {
  const r = { cat, name: id, status: st, ms: +ms.toFixed(2), detail: String(detail).slice(0, 300) };
  S.results.push(r); S.last[cat + ':' + id] = r;
  const log = $('#log'); log.textContent += `[${cat}] ${id}: ${st} (${r.ms} ms) ${r.detail}\n`;
  log.textContent = log.textContent.split('\n').slice(-200).join('\n');
  paint(cat, id); updStats();
}
function updStats() { const ok = S.results.filter(r => r.status === 'ok').length; $('#stats').textContent = `✔ ${ok} · ✖ ${S.results.length - ok}`; }
function showSec(id) { $$('main > section:not(#console)').forEach(x => { x.hidden = x.id !== id; }); $$('#nav a').forEach(a => a.setAttribute('aria-current', a.hash === '#' + id ? 'page' : 'false')); }
function paint(cat, id) {
  const row = $(`[data-row="${cat}:${id}"]`); if (!row) return;
  const r = S.last[cat + ':' + id], b = $('.badge', row);
  b.dataset.st = r ? r.status : 'pending'; b.textContent = t('st_' + (r ? r.status : 'pending'));
  $('small', row).textContent = r ? `${r.ms} ms — ${r.detail}` : '';
}
const classify = e => {
  const n = e && e.name || '';
  if (e && e.unsupported) return 'unsupported';
  if (n === 'NotAllowedError' || n === 'SecurityError') return 'denied';
  if (n === 'TypeError' && /fetch|network|load/i.test(e.message)) return 'blocked';
  return 'error';
};
window.addEventListener('error', e => S.errors.push(String(e.message).slice(0, 200)));
window.addEventListener('unhandledrejection', e => S.errors.push(String(e.reason).slice(0, 200)));

/* ---- Rows renderer ---- */
function renderRows(box, cat, items) {
  box.replaceChildren(...items.map(it => {
    const row = el('div', { className: 'row' }); row.dataset.row = `${cat}:${it.id}`;
    const nm = el('span', { textContent: it.id + (it.manual ? ' ' + t('manual') : '') });
    const bt = el('button', { className: 'btn', type: 'button', textContent: t('run') }); bt.dataset.run = `${cat}:${it.id}`;
    row.append(nm, bt, el('span', { className: 'badge' }), el('small'));
    if (it.demo) { const d = el('div', { className: 'demo ' + it.demo[0] }); it.demo[1].forEach(x => d.append(el('span', { textContent: x }))); if (it.dir) d.dir = it.dir; row.append(d); d.style.gridColumn = '1/-1'; }
    return row;
  }));
  items.forEach(it => paint(cat, it.id));
}

/* ---- Web API lab ---- */
const base = () => $('#base').value.replace(/\/$/, '');
const A = [
  { id: 'fetch', has: () => 'fetch' in window, run: async () => { const c = new AbortController(); const r = await tmo(fetch(base() + '/todos/1', { signal: c.signal }), 8000); if (!r.ok) throw new Error('HTTP ' + r.status); return JSON.stringify(await r.json()); } },
  { id: 'AbortController', has: () => 'AbortController' in window && 'fetch' in window, run: async () => { const c = new AbortController(); const p = fetch(base() + '/posts', { signal: c.signal }); c.abort(); try { await p; } catch (e) { if (e.name === 'AbortError') return 'AbortError'; throw e; } throw new Error('not aborted'); } },
  { id: 'URL', has: () => 'URL' in window, run: async () => { const u = new URL('https://example.com/a?x=1'); u.searchParams.append('q', 'ñ &'); return `${u.href} x=${u.searchParams.get('x')}`; } },
  { id: 'storage', has: () => { try { return !!(localStorage && sessionStorage); } catch { return false; } }, run: async () => { localStorage.setItem('nx_t', 'a'); sessionStorage.setItem('nx_t', 'b'); const r = localStorage.getItem('nx_t') + sessionStorage.getItem('nx_t'); localStorage.removeItem('nx_t'); sessionStorage.removeItem('nx_t'); return r; } },
  { id: 'clipboard', sec: 1, has: () => !!navigator.clipboard, run: async () => { await navigator.clipboard.writeText('NativaX'); return 'writeText'; } },
  { id: 'vibrate', manual: 1, has: () => 'vibrate' in navigator, run: async () => 'result=' + navigator.vibrate(50) },
  { id: 'share', manual: 1, sec: 1, has: () => 'share' in navigator, run: async () => { await navigator.share({ title: 'NativaX', url: location.href }); return 'shared'; } },
  { id: 'onLine', has: () => 'onLine' in navigator, run: async () => String(navigator.onLine) },
  { id: 'matchMedia', has: () => 'matchMedia' in window, run: async () => ['(prefers-color-scheme: dark)', '(prefers-reduced-motion: reduce)', '(hover: hover)', '(pointer: coarse)'].map(q => q + '=' + matchMedia(q).matches).join(' ') },
  { id: 'IntersectionObserver', has: () => 'IntersectionObserver' in window, run: () => tmo(new Promise(res => { const o = new IntersectionObserver(e => { o.disconnect(); res('intersecting=' + e[0].isIntersecting); }); o.observe($('#probe')); })) },
  { id: 'ResizeObserver', has: () => 'ResizeObserver' in window, run: () => tmo(new Promise(res => { const p = $('#probe'); let n = 0; const o = new ResizeObserver(() => { if (++n === 2) { o.disconnect(); res('callbacks=' + n); } }); o.observe(p); p.classList.toggle('wide'); })) },
  { id: 'MutationObserver', has: () => 'MutationObserver' in window, run: () => tmo(new Promise(res => { const p = $('#probe'); const o = new MutationObserver(m => { o.disconnect(); res('records=' + m.length); }); o.observe(p, { childList: true }); p.append(el('i')); p.replaceChildren(); })) },
  { id: 'requestAnimationFrame', has: () => 'requestAnimationFrame' in window, run: () => tmo(new Promise(res => { let n = 0; const s = performance.now(); const f = () => ++n < 10 ? requestAnimationFrame(f) : res(`10 frames in ${(performance.now() - s).toFixed(1)} ms`); requestAnimationFrame(f); })) },
  { id: 'timers', has: () => true, run: () => new Promise(res => { let n = 0; setTimeout(() => { const i = setInterval(() => { if (++n === 3) { clearInterval(i); res('timeout + 3 ticks, interval cleared'); } }, 20); }, 20); }) },
  { id: 'performance', has: () => 'performance' in window, run: async () => { performance.mark('a'); performance.mark('b'); const m = performance.measure('ab', 'a', 'b'); const nav = performance.getEntriesByType('navigation')[0]; return `now=${performance.now().toFixed(1)} measure=${m.duration.toFixed(3)} dcl=${nav ? nav.domContentLoadedEventEnd.toFixed(0) : 'n/a'}`; } },
  { id: 'crypto', has: () => !!(window.crypto && crypto.getRandomValues), run: async () => [...crypto.getRandomValues(new Uint8Array(8))].map(b => b.toString(16).padStart(2, '0')).join('') },
  { id: 'Intl', has: () => 'Intl' in window, run: async () => { const l = S.lang; return [new Intl.DateTimeFormat(l, { dateStyle: 'full', timeStyle: 'short' }).format(new Date()), new Intl.NumberFormat(l, { style: 'currency', currency: 'EUR' }).format(1234567.891), new Intl.RelativeTimeFormat(l, { numeric: 'auto' }).format(-1, 'day')].join(' | '); } },
  { id: 'geolocation', manual: 1, sec: 1, has: () => 'geolocation' in navigator, run: () => new Promise((res, rej) => navigator.geolocation.getCurrentPosition(p => res(`${p.coords.latitude.toFixed(3)}, ${p.coords.longitude.toFixed(3)}`), e => rej(Object.assign(new Error(e.message), { name: e.code === 1 ? 'NotAllowedError' : 'GeoError' })), { timeout: 8000 })) },
  { id: 'WebWorker', has: () => 'Worker' in window && 'Blob' in window, run: () => tmo(new Promise((res, rej) => { const u = URL.createObjectURL(new Blob(['onmessage=e=>{let s=0;for(let i=0;i<e.data;i++)s+=i;postMessage(s)}'], { type: 'text/javascript' })); const w = new Worker(u); const end = () => { w.terminate(); URL.revokeObjectURL(u); }; w.onmessage = e => { end(); res('sum=' + e.data); }; w.onerror = e => { end(); rej(new Error(e.message || 'worker error')); }; w.postMessage(1e6); })) },
  { id: 'File/Blob', has: () => 'Blob' in window && 'FileReader' in window, run: async () => { const f = $('#file').files[0]; const b = f || new Blob(['NativaX ñ'], { type: 'text/plain' }); const txt = f ? '(local file)' : await b.text(); const u = URL.createObjectURL(b); URL.revokeObjectURL(u); return `${b.size} bytes ${txt.slice(0, 30)}`; } },
  { id: 'BroadcastChannel', has: () => 'BroadcastChannel' in window, run: () => tmo(new Promise(res => { const a = new BroadcastChannel('nx'), b = new BroadcastChannel('nx'); b.onmessage = e => { a.close(); b.close(); res('received ' + e.data); }; a.postMessage('ping'); })) },
  { id: 'WebSocket', has: () => 'WebSocket' in window, run: () => tmo(new Promise((res, rej) => { let w; try { w = new WebSocket($('#wsurl').value); } catch (e) { return rej(e); } w.onopen = () => w.send('ping'); w.onmessage = e => { w.close(); res('echo ' + String(e.data).slice(0, 40)); }; w.onerror = () => rej(new TypeError('network error: WebSocket blocked or unreachable')); }), 7000) },
  { id: 'IndexedDB', has: () => 'indexedDB' in window, run: () => new Promise((res, rej) => { const q = indexedDB.open('nx', 1); q.onupgradeneeded = () => q.result.createObjectStore('s'); q.onerror = () => rej(q.error); q.onsuccess = () => { const db = q.result, tx = db.transaction('s', 'readwrite'), s = tx.objectStore('s'); s.put('v', 'k'); const g = s.get('k'); s.delete('k'); tx.oncomplete = () => { db.close(); res('get=' + g.result + ', deleted'); }; tx.onerror = () => rej(tx.error); }; }) },
  { id: 'WebAnimations', has: () => 'animate' in Element.prototype, run: async () => { const a = $('#probe').animate([{ opacity: 1 }, { opacity: .4 }], { duration: 300 }); a.pause(); const p = a.playState; a.play(); a.cancel(); return `${p} → ${a.playState}`; } }
];
async function runApi(id) {
  const a = A.find(x => x.id === id), s = performance.now();
  if (a.sec && !isSecureContext) return record('api', id, 'insecure', 0, 'isSecureContext=false');
  if (!a.has()) return record('api', id, 'unsupported', 0, '');
  try { record('api', id, 'ok', performance.now() - s, await a.run()); }
  catch (e) { record('api', id, classify(e), performance.now() - s, `${e.name}: ${e.message}`); }
}

/* ---- Performance microtests ---- */
const sb = () => $('#sandbox');
const P = [
  ['DOM create/query/remove', () => { const f = document.createDocumentFragment(); for (let i = 0; i < 300; i++) f.append(el('div', { className: 'x' })); sb().append(f); const n = sb().querySelectorAll('.x').length; sb().replaceChildren(); if (n !== 300) throw new Error(n); }],
  ['Events + delegation', () => { let c = 0; const h = e => { if (e.target.matches('button')) c++; }; sb().addEventListener('click', h); for (let i = 0; i < 100; i++) sb().append(el('button')); $$('button', sb()).forEach(b => b.click()); sb().removeEventListener('click', h); sb().replaceChildren(); if (c !== 100) throw new Error(c); }],
  ['Arrays/objects', () => { const a = Array.from({ length: 1e5 }, (_, i) => i); const r = a.map(x => x * 2).filter(x => x % 3 === 0).reduce((s, x) => s + x, 0); const o = { ...{ a: 1 }, r }; if (!o.r) throw new Error('x'); }],
  ['Map/Set/WeakMap', () => { const m = new Map(), s = new Set(), w = new WeakMap(), k = []; for (let i = 0; i < 2e4; i++) { m.set(i, i); s.add(i % 100); const o = {}; k.push(o); w.set(o, i); } if (s.size !== 100 || m.size !== 2e4 || w.get(k[5]) !== 5) throw new Error('x'); }],
  ['Promises/async', async () => { const r = await Promise.all(Array.from({ length: 200 }, async (_, i) => { await null; return i; })); if (r.length !== 200) throw new Error('x'); }],
  ['Timers', async () => { for (let i = 0; i < 10; i++) await wait(0); }],
  ['JSON', () => { const o = Array.from({ length: 2000 }, (_, i) => ({ i, s: 'ñ' + i, a: [i] })); if (JSON.parse(JSON.stringify(o)).length !== 2000) throw new Error('x'); }],
  ['RegExp', () => { const m = 'a@b.co x@y.org '.repeat(2000).match(/[\w.]+@[\w.]+\.\w+/g); if (m.length !== 4000) throw new Error(m.length); }],
  ['Unicode', () => { const s = 'e\u0301👨‍👩‍👧'; if (s.normalize('NFC').length !== 1 + s.length - 2 && s.normalize('NFC').length >= s.length) throw new Error('nfc'); if ([...'😀a'].length !== 2) throw new Error('cp'); }],
  ['Classes/inheritance', () => { class A { constructor() { this.v = 1; } get() { return this.v; } } class B extends A { get() { return super.get() + 1; } } let s = 0; for (let i = 0; i < 1e4; i++) s += new B().get(); if (s !== 2e4) throw new Error(s); }],
  ['Component lifecycle', () => { for (let i = 0; i < 200; i++) { const c = el('div'), b = el('button'), h = () => 0; b.addEventListener('click', h); c.append(b); sb().append(c); b.removeEventListener('click', h); c.remove(); } }],
  ['Mass DOM update', () => { const n = Array.from({ length: 500 }, () => sb().appendChild(el('span'))); n.forEach((x, i) => { x.textContent = i; }); sb().replaceChildren(); }],
  ['Task order', async () => { const o = []; setTimeout(() => o.push('macro'), 0); Promise.resolve().then(() => o.push('micro')); o.push('sync'); await wait(5); if (o.join() !== 'sync,micro,macro') throw new Error(o.join()); }],
  ['Math/search', () => { const n = 1e5, s = new Uint8Array(n + 1); let c = 0; for (let i = 2; i <= n; i++) if (!s[i]) { c++; for (let j = i * i; j <= n; j += i) s[j] = 1; } const a = Array.from({ length: 1e5 }, (_, i) => i); let lo = 0, hi = a.length - 1; while (lo < hi) { const m = (lo + hi) >> 1; a[m] < 77777 ? lo = m + 1 : hi = m; } if (c !== 9592 || lo !== 77777) throw new Error(c + ',' + lo); }],
  ['UI responsiveness', async () => { let gap = 0, last = performance.now(); for (let i = 0; i < 20; i++) { const e = performance.now() + 4; while (performance.now() < e); await wait(0); const n = performance.now(); gap = Math.max(gap, n - last - 4); last = n; } if (gap > 100) throw new Error('gap ' + gap.toFixed(0) + ' ms'); }]
];
async function runPerf(id) {
  const p = P.find(x => x[0] === id); const n = 10, times = [];
  try { for (let i = 0; i < 2; i++) await p[1](); for (let i = 0; i < n; i++) { const s = performance.now(); await p[1](); times.push(performance.now() - s); }
    times.sort((a, b) => a - b); const f = x => x.toFixed(2);
    record('perf', id, 'ok', times.reduce((a, b) => a + b, 0), `min ${f(times[0])} / med ${f(times[n >> 1])} / max ${f(times[n - 1])} ms (${n} iter, 2 warmup)`);
  } catch (e) { record('perf', id, 'fail', 0, e.message); }
}

/* ---- CSS tests ---- */
const C = [
  { id: 'flexbox', sup: [['display', 'flex']], demo: ['', ['A', 'B', 'C']] }, { id: 'grid', sup: [['display', 'grid']], demo: ['d-grid', ['1', '2', '3']] },
  { id: 'sticky', sup: [['position', 'sticky']], demo: ['d-sticky', ['sticky', 'b', 'c', 'd', 'e']] }, { id: 'z-index/stacking', sup: [['z-index', '2'], ['isolation', 'isolate']], demo: ['d-z', ['top', 'under']] },
  { id: 'gradient/shadow/alpha', sup: [['background', 'linear-gradient(red,blue)'], ['box-shadow', '0 0 4px red']], demo: ['d-grad', ['fx']] }, { id: 'transform 3D', sup: [['transform', 'rotateY(10deg)'], ['perspective', '10px']], demo: ['d-3d', ['3D']] },
  { id: 'animation', sup: [['animation', 'x 1s']], demo: ['d-anim', ['↻']] }, { id: 'variables', sup: [['color', 'var(--x)']], demo: ['', ['var()']] },
  { id: 'selectors/:has', sup: [['selector(:has(a))']], demo: ['d-sel', ['a', 'b', 'c']] }, { id: 'text wrap', sup: [['overflow-wrap', 'anywhere']], demo: ['d-long', ['Supercalifragilisticoespialidosoextraordinariamente']] },
  { id: 'RTL', sup: [['direction', 'rtl']], dir: 'rtl', demo: ['', ['مرحبا', 'שלום', '1']] }, { id: 'unicode/emoji', sup: [['font-variant-emoji', 'emoji']], demo: ['', ['😀', '👨‍👩‍👧', 'ñ', '漢', 'ß']] },
  { id: 'hidden/visibility', sup: [['visibility', 'hidden']], demo: ['d-hid', ['hidden', 'none', 'shown']] }, { id: 'fonts', sup: [['font-display', 'swap']], demo: ['', ['Aa']], fonts: true }
];
async function runCss(id) {
  const c = C.find(x => x.id === id), s = performance.now();
  const res = c.sup.map(a => a.length === 1 ? CSS.supports(a[0]) : CSS.supports(a[0], a[1]));
  let extra = ''; if (c.fonts) { try { extra = ' fonts.status=' + document.fonts.status; } catch { extra = ' fonts n/a'; } }
  record('css', id, res.every(Boolean) ? 'ok' : (res.some(Boolean) ? 'ok' : 'unsupported'), performance.now() - s, `supports=${res.join(',')}${extra} (inspect visually)`);
}

/* ---- Registry of runners ---- */
const RUN = { api: runApi, perf: runPerf, css: runCss };
const LISTS = { api: () => A.map(a => ({ id: a.id, manual: a.manual })), perf: () => P.map(p => ({ id: p[0] })), css: () => C.map(c => ({ id: c.id, demo: c.demo, dir: c.dir })) };
const BOX = { api: '#apis', perf: '#perfs', css: '#csss' };
async function runCat(cat) { for (const it of LISTS[cat]()) { if (it.manual) continue; await RUN[cat](it.id); await wait(0); } }
async function runAll() { showSec('api'); await wait(50); $('#status').textContent = t('stRun'); for (const c of Object.keys(RUN)) await runCat(c); $('#status').textContent = t('stDone'); }

/* ---- i18n / theme ---- */
const mq = matchMedia('(prefers-color-scheme: dark)');
function applyTheme() { document.documentElement.dataset.theme = S.theme === 'auto' ? (mq.matches ? 'dark' : 'light') : S.theme; }
function applyLang() {
  document.documentElement.lang = S.lang;
  $$('[data-i18n]').forEach(n => { n.textContent = t(n.dataset.i18n); });
  $$('[data-i18n-label]').forEach(n => n.setAttribute('aria-label', t(n.dataset.i18nLabel)));
  $('#img').alt = t('imgAlt'); $('#prev').alt = t('pickImg');
  for (const c of Object.keys(BOX)) renderRows($(BOX[c]), c, LISTS[c]());
  renderList(); renderDiag(); updCount(); $('#status').textContent = t('stReady'); $('#dt').textContent = t('modalT'); $('#dm').textContent = t('modalM');
  $$('#dyn button').forEach(b => { b.textContent = t('remove'); });
}

/* ---- Toast / dialog ---- */
const toast = m => { const d = el('div', { textContent: m }); $('#toasts').append(d); setTimeout(() => d.remove(), 2500); };
function ask(title, msg) { const d = $('#dlg'); $('#dt').textContent = title; $('#dm').textContent = msg; const opener = document.activeElement; d.showModal(); return new Promise(res => { const fin = v => { d.close(); d.removeEventListener('close', onc); res(v); opener && opener.focus && opener.focus(); }; const onc = () => res(false); $('#dok').onclick = () => fin(true); $('#dno').onclick = () => fin(false); d.addEventListener('close', onc, { once: true }); }); }

/* ---- Forms ---- */
function formInit() {
  const f = $('#f'), evs = {}, bump = e => { evs[e.type] = (evs[e.type] || 0) + 1; $('#evs').textContent = Object.entries(evs).map(([k, v]) => k + ':' + v).join(' '); };
  ['input', 'change', 'invalid', 'submit'].forEach(n => f.addEventListener(n, bump, true)); ['focus', 'blur'].forEach(n => f.addEventListener(n, bump, true));
  const ta = f.elements.ta; const cnt = () => { $('#cnt').textContent = `${ta.value.length}/${ta.maxLength} ${t('chars')}`; };
  const pw = f.elements.password;
  const chk = () => { pw.setCustomValidity(''); if (pw.validity.patternMismatch) pw.setCustomValidity(t('pwRule')); };
  f.addEventListener('input', e => { cnt(); chk(); $('#rv').textContent = f.elements.range.value; $('#fout').textContent = JSON.stringify(vals(), null, 1); });
  const vals = () => { const o = {}; new FormData(f).forEach((v, k) => { o[k] = k === 'password' ? '•'.repeat(String(v).length) : (k in o ? [].concat(o[k], v) : v); }); return o; };
  f.addEventListener('submit', e => { e.preventDefault(); chk(); const ok = f.checkValidity(); const ul = $('#ferr'); ul.replaceChildren();
    if (!ok) $$(':invalid', f).forEach(i => ul.append(el('li', { textContent: `${i.name || i.type}: ${i.validationMessage}` })));
    $('#fstate').textContent = ok ? '✔ ' + t('valid') : '✖ ' + t('invalid'); $('#fout').textContent = JSON.stringify(vals(), null, 1); if (ok) toast(t('done')); });
  f.addEventListener('reset', () => setTimeout(() => { cnt(); $('#rv').textContent = '50'; $('#ferr').replaceChildren(); $('#fstate').textContent = ''; $('#fout').textContent = ''; $('#dyn').replaceChildren(); }));
  let n = 0; $('#addField').onclick = () => { n++; const i = el('input', { name: 'dyn' + n, type: 'text', required: true }); const b = el('button', { type: 'button', className: 'btn', textContent: t('remove') }); const w = el('label', {}, 'dyn' + n, i); const box = el('div', {}, w, b); b.onclick = () => box.remove(); $('#dyn').append(box); i.focus(); };
  cnt();
}

/* ---- UI catalog ---- */
let items = ['Alpha', 'Beta', 'Gamma'], editing = -1, drag = -1, cnt = 0;
const updCount = () => { $('#count').textContent = cnt; };
function renderList() {
  const ul = $('#items'); ul.replaceChildren(...items.map((x, i) => {
    const li = el('li', { draggable: true }); li.dataset.i = i;
    const body = editing === i ? el('input', { value: x, maxLength: 40 }) : el('span', { textContent: x }); if (editing === i) body.dataset.edit = 1;
    const mk = (a, txt, lbl) => { const b = el('button', { className: 'btn', type: 'button', textContent: txt, title: lbl }); b.dataset.a = a; b.dataset.i = i; return b; };
    li.append(body, mk('up', '↑', ''), mk('down', '↓', ''), mk(editing === i ? 'save' : 'edit', editing === i ? t('save') : t('edit'), ''), mk('del', t('del'), '')); return li; }));
}
function uiInit() {
  $('#inc').onclick = () => { cnt++; updCount(); }; $('#dec').onclick = () => { cnt--; updCount(); };
  $('#feat').onclick = e => { const b = e.currentTarget, v = b.getAttribute('aria-pressed') !== 'true'; b.setAttribute('aria-pressed', v); toast(`${t('feat')}: ${t(v ? 'on' : 'off')}`); };
  $('#sw').onclick = e => { const b = e.currentTarget, v = b.getAttribute('aria-checked') !== 'true'; b.setAttribute('aria-checked', v); toast(`${t('sw')}: ${t(v ? 'on' : 'off')}`); };
  $('#load').onclick = async e => { const b = e.currentTarget; b.disabled = true; b.setAttribute('aria-busy', 'true'); b.textContent = t('loadingBtn'); await wait(1000); b.disabled = false; b.removeAttribute('aria-busy'); b.textContent = t('btnLoad'); toast(t('done')); };
  $('#toast').onclick = () => toast(t('notify'));
  $('#del').onclick = async () => { if (await ask(t('confirmT'), t('confirmQ'))) toast(t('done')); };
  $('#open').onclick = () => ask(t('modalT'), t('modalM'));
  $('#copy').onclick = async () => { const txt = 'NativaX'; try { await navigator.clipboard.writeText(txt); toast(t('copied')); } catch { const ta = el('textarea', { value: txt }); document.body.append(ta); ta.select(); const ok = document.execCommand && document.execCommand('copy'); ta.remove(); toast(ok ? t('copied') : t('copyFail')); } };
  const mb = $('#mbtn'), mn = $('#mnu'), closeM = () => { mn.hidden = true; mb.setAttribute('aria-expanded', 'false'); };
  mb.onclick = () => { mn.hidden = !mn.hidden; mb.setAttribute('aria-expanded', String(!mn.hidden)); if (!mn.hidden) $('button', mn).focus(); };
  document.addEventListener('click', e => { const a = e.target.closest('[data-act]'); if (a) { toast(a.dataset.act); closeM(); $('#mnu2').hidden = true; } else if (!e.target.closest('#mnu,#mbtn')) { closeM(); $('#mnu2').hidden = true; } });
  document.addEventListener('keydown', e => { if (e.key === 'Escape') { closeM(); $('#mnu2').hidden = true; } });
  $('#ctx').addEventListener('contextmenu', e => { e.preventDefault(); const m = $('#mnu2'); m.hidden = false; m.style.left = Math.min(e.clientX || 20, innerWidth - 140) + 'px'; m.style.top = (e.clientY || 20) + 'px'; $('button', m).focus(); });
  const tabs = $$('[role=tab]'); const sel = i => tabs.forEach((x, j) => { x.setAttribute('aria-selected', j === i); x.tabIndex = j === i ? 0 : -1; $('#' + x.getAttribute('aria-controls')).hidden = j !== i; if (j === i) x.focus(); });
  tabs.forEach((x, i) => { x.onclick = () => sel(i); x.onkeydown = e => { if (e.key === 'ArrowRight') sel((i + 1) % tabs.length); if (e.key === 'ArrowLeft') sel((i + tabs.length - 1) % tabs.length); }; });
  $('#lf').onsubmit = e => { e.preventDefault(); const v = $('#li').value.trim(); if (v) { items.push(v); $('#li').value = ''; renderList(); } };
  const ul = $('#items');
  ul.onclick = e => { const b = e.target.closest('button'); if (!b) return; const i = +b.dataset.i;
    if (b.dataset.a === 'del') items.splice(i, 1); else if (b.dataset.a === 'edit') editing = i; else if (b.dataset.a === 'save') { const v = $('input', ul).value.trim(); if (v) items[i] = v; editing = -1; }
    else { const j = b.dataset.a === 'up' ? i - 1 : i + 1; if (j >= 0 && j < items.length) [items[i], items[j]] = [items[j], items[i]]; }
    renderList(); };
  ul.ondragstart = e => { drag = +e.target.closest('li').dataset.i; }; ul.ondragover = e => e.preventDefault();
  ul.ondrop = e => { e.preventDefault(); const li = e.target.closest('li'); if (!li || drag < 0) return; const j = +li.dataset.i; items.splice(j, 0, items.splice(drag, 1)[0]); drag = -1; renderList(); };
}

/* ---- Media ---- */
function mediaInit() {
  const img = $('#img'), st = $('#imgst'); st.textContent = t('imgLoad');
  img.onload = () => { st.textContent = t('imgOk'); }; img.onerror = () => { st.textContent = t('imgErr'); img.removeAttribute('srcset'); img.src = 'data:image/svg+xml,' + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="640" height="360"><rect width="100%" height="100%" fill="#888"/></svg>'); };
  if (img.complete && img.naturalWidth) img.onload();
  let url = null; $('#file').onchange = e => { const f = e.target.files[0], s = $('#fst'), p = $('#prev'); if (url) URL.revokeObjectURL(url); p.hidden = true; if (!f) return;
    if (!/^image\//.test(f.type)) { s.textContent = '✖ ' + t('badType'); return; } if (f.size > 5 * 1048576) { s.textContent = '✖ ' + t('tooBig'); return; }
    url = URL.createObjectURL(f); p.onerror = () => { s.textContent = '✖ ' + t('imgErr'); p.hidden = true; }; p.onload = () => { s.textContent = '✔ ' + t('prevOk'); p.hidden = false; }; p.src = url; };
  const fmt = x => isFinite(x) ? x.toFixed(1) + 's' : '–';
  const hook = (m, box, evs, fail) => { const ev = []; const upd = e => { if (e) ev.push(e.type); box.textContent = `${ev.slice(-4).join(' › ')} | ${t('dur')} ${fmt(m.duration)} | ${t('pos')} ${fmt(m.currentTime)} | ${m.paused ? 'paused' : 'playing'}`; };
    evs.forEach(n => m.addEventListener(n, n === 'timeupdate' ? () => upd() : upd)); m.addEventListener('error', fail); };
  const vev = ['loadstart', 'loadedmetadata', 'canplay', 'play', 'pause', 'timeupdate', 'ended'];
  const v = $('#vid'); hook(v, $('#vst'), vev, () => { $('#vfb').hidden = false; $('#vst').textContent = 'error'; record('media', 'video', 'blocked', 0, 'error event'); }); v.addEventListener('loadedmetadata', () => record('media', 'video', 'ok', 0, 'duration ' + fmt(v.duration)), { once: true });
  const a = $('#aud'); hook(a, $('#ast'), ['loadstart', 'loadedmetadata', 'canplay', 'play', 'pause', 'ended'], () => { $('#ast').textContent = 'error'; record('media', 'audio', 'blocked', 0, 'error event'); }); a.addEventListener('loadedmetadata', () => record('media', 'audio', 'ok', 0, 'duration ' + fmt(a.duration)), { once: true });
  const cv = $('#cv'), ctx = cv.getContext('2d'); let w = 300, h = 160, ph = 0, raf = 0;
  const size = () => { const r = devicePixelRatio || 1, cw = cv.clientWidth || 300; cv.width = Math.round(cw * r); cv.height = Math.round(160 * r); ctx.setTransform(r, 0, 0, r, 0, 0); w = cw; h = 160; };
  const draw = () => { const cs = getComputedStyle(document.documentElement); ctx.clearRect(0, 0, w, h); ctx.fillStyle = cs.getPropertyValue('--ac'); for (let i = 0; i < 12; i++) { const bh = (Math.sin(ph + i * .6) * .4 + .5) * (h - 20); ctx.fillRect(10 + i * (w - 20) / 12, h - bh, (w - 20) / 12 - 4, bh); } ph += .04; raf = requestAnimationFrame(draw); };
  if (ctx) { size(); if ('ResizeObserver' in window) new ResizeObserver(size).observe(cv); draw(); cv.onclick = e => { const r = cv.getBoundingClientRect(); $('#cvst').textContent = `${t('cvClick')} (${Math.round((e.clientX - r.left) * w / r.width)}, ${Math.round((e.clientY - r.top) * h / r.height)})`; }; document.addEventListener('visibilitychange', () => { cancelAnimationFrame(raf); if (!document.hidden) draw(); }); }
  ['c1', 'c2'].forEach(id => { const n = $('#' + id); const f = () => n.classList.toggle('on'); n.onclick = f; n.onkeydown = e => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); f(); } }; });
}

/* ---- HTTP client ---- */
let hctl = null;
function httpInit() {
  const out = (s, b) => { $('#hs').textContent = s; $('#hr').textContent = b; };
  $('#hf').onsubmit = async e => {
    e.preventDefault(); let hd = {}, body; const m = $('#hm').value;
    try { hd = JSON.parse($('#hh').value || '{}'); } catch { return out(`${t('badJson')} headers`, ''); }
    const rb = $('#hb').value.trim(); if (rb && m !== 'GET') { try { JSON.parse(rb); body = rb; } catch { return out(`${t('badJson')} body`, ''); } if (!Object.keys(hd).some(k => k.toLowerCase() === 'content-type')) hd['Content-Type'] = 'application/json'; }
    hctl = new AbortController(); let timedOut = false; const to = setTimeout(() => { timedOut = true; hctl.abort(); }, +$('#ht').value || 8000); const s = performance.now(); out('…', '');
    try { const r = await fetch($('#hu').value, { method: m, headers: hd, body, signal: hctl.signal }); const txt = await r.text(); const d = (performance.now() - s).toFixed(0);
      out(`HTTP ${r.status} ${r.statusText} — ${d} ms${r.ok ? '' : ' (HTTP error)'}`, [...r.headers].map(([k, v]) => `${k}: ${v}`).join('\n') + '\n\n' + txt.slice(0, 5000)); record('http', m, r.ok ? 'ok' : 'error', +d, 'HTTP ' + r.status); }
    catch (er) { const d = performance.now() - s; const msg = er.name === 'AbortError' ? (timedOut ? t('timeout') : t('aborted')) : `${t('netErr')}: ${er.message}`; out(msg, ''); record('http', m, er.name === 'AbortError' ? 'error' : 'blocked', d, msg); }
    finally { clearTimeout(to); hctl = null; } };
  $('#hc').onclick = () => hctl ? hctl.abort() : ($('#hs').textContent = t('noReq'));
}

/* ---- Diagnostics / report ---- */
function diagData() {
  const m = performance.memory;
  return { userAgent: navigator.userAgent, window: `${outerWidth}x${outerHeight}`, viewport: `${innerWidth}x${innerHeight}`, devicePixelRatio, language: navigator.language, online: navigator.onLine, systemDark: mq.matches, orientation: (screen.orientation && screen.orientation.type) || (innerWidth > innerHeight ? 'landscape' : 'portrait'), secureContext: isSecureContext, jsMemoryMB: m ? +(m.usedJSHeapSize / 1048576).toFixed(1) : null };
}
function renderDiag() {
  const d = diagData(), dl = $('#dg'); dl.replaceChildren(); Object.entries(d).forEach(([k, v]) => dl.append(el('dt', { textContent: k === 'jsMemoryMB' ? t('dMem') : k }), el('dd', { textContent: v === null ? 'n/a' : String(v) })));
  dl.append(el('dt', { textContent: 'Intl' }), el('dd', { textContent: `${new Intl.DateTimeFormat(S.lang, { dateStyle: 'medium' }).format(new Date())} · ${new Intl.NumberFormat(S.lang).format(1234567.89)}` }), el('dt', { textContent: t('dErr') }), el('dd', { textContent: S.errors.length ? S.errors.join(' | ') : '0' }));
}
function exportReport() {
  const d = diagData(); delete d.userAgent; d.userAgentFamily = (navigator.userAgent.match(/(Firefox|Edg|Chrome|Safari)\//) || ['', 'unknown'])[1];
  const caps = Object.fromEntries(A.map(a => [a.id, a.has() && !(a.sec && !isSecureContext)]));
  const rep = { generated: new Date().toISOString(), started: S.started, environment: d, capabilities: caps, tests: S.results, totals: { run: S.results.length, ok: S.results.filter(r => r.status === 'ok').length, durationMs: +S.results.reduce((a, r) => a + r.ms, 0).toFixed(1) }, errors: S.errors };
  const u = URL.createObjectURL(new Blob([JSON.stringify(rep, null, 2)], { type: 'application/json' })); const a = el('a', { href: u, download: 'nativax-report.json' }); document.body.append(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(u), 1000); toast(t('exported'));
}

/* ---- Boot ---- */
document.addEventListener('DOMContentLoaded', () => {
  S.lang = store.get('nx_lang') || (L.includes(navigator.language.slice(0, 2)) ? navigator.language.slice(0, 2) : 'es'); S.theme = store.get('nx_theme') || 'auto';
  $('#lang').value = S.lang; $('#theme').value = S.theme; applyTheme();
  $('#lang').onchange = e => { S.lang = e.target.value; store.set('nx_lang', S.lang); applyLang(); };
  $('#theme').onchange = e => { S.theme = e.target.value; store.set('nx_theme', S.theme); applyTheme(); };
  mq.addEventListener('change', () => { if (S.theme === 'auto') applyTheme(); });
  document.addEventListener('click', e => { const b = e.target.closest('[data-run]'); if (b) { const [c, id] = b.dataset.run.split(':'); RUN[c](id); } });
  $('#runAll').onclick = runAll; $('#export').onclick = exportReport;
  $('#clear').onclick = () => { S.results = []; S.last = {}; S.errors = []; $('#log').textContent = ''; $$('[data-row]').forEach(r => { const [c, id] = r.dataset.row.split(':'); paint(c, id); }); renderDiag(); toast(t('cleared')); };
  window.addEventListener('online', () => { renderDiag(); toast(t('online')); }); window.addEventListener('offline', () => { renderDiag(); toast(t('offline')); }); window.addEventListener('resize', renderDiag);
  $('#nav').addEventListener('click', e => { const a = e.target.closest('a'); if (!a) return; e.preventDefault(); showSec(a.hash.slice(1)); history.replaceState(null, '', a.hash); window.scrollTo({ top: 0 }); });
  showSec($('main > section' + (location.hash || '#forms')) ? location.hash.slice(1) || 'forms' : 'forms');
  formInit(); uiInit(); mediaInit(); httpInit(); applyLang();
});
