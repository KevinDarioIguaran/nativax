/* NativaX debug dashboard — local HTML, no HTTP server.
 *
 * Live data arrives through the native window bridge:
 *   - PyQt6-WebEngine: QWebChannel object "nativax" (window.NATIVAX_QT)
 *   - pywebview: window.pywebview.api
 *   - GTK/WebKit: window.NATIVAX_PUSH + nativax:// navigation hook
 * Opened directly in a browser it is read-only and uses dashboard_data.js.
 */
(() => {
  'use strict';

  let DATA = window.DASHBOARD_DATA || {};
  let LIVE = null;
  let STATUS = null;
  let MODE = 'tests';
  let VIEW = 'resumen';
  let SECTION = '';
  let QUERY = '';
  let STATUS_FILTER = '';
  let VSEL = '';
  let wasRunning = false;
  let lastLiveKey = '';
  let lastPollError = '';

  const $ = (s, root = document) => root.querySelector(s);
  const $$ = (s, root = document) => Array.from(root.querySelectorAll(s));
  const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[c]));
  const num = (v, d = 0) => (v === null || v === undefined || v === '') ? '—' : Number(v).toFixed(d);
  const pct = (v) => (v === null || v === undefined) ? '—' : `${Number(v).toFixed(2)} %`;
  const ms = (v) => (v === null || v === undefined) ? '—' : `${Math.round(Number(v))} ms`;

  function toast(msg) {
    const t = $('#toast');
    if (!t) return;
    t.textContent = msg;
    t.classList.add('show');
    clearTimeout(toast._t);
    toast._t = setTimeout(() => t.classList.remove('show'), 2600);
  }

  function dialog(title, html) {
    const d = $('#dlg');
    if (!d) return;
    $('#dlg-title').textContent = title;
    $('#dlg-body').innerHTML = html;
    d.showModal();
  }

  function hasRunData() {
    return !!(DATA.report && DATA.report.available);
  }

  function executedCount() {
    return (DATA.cases || []).filter((c) => c.status && c.status !== 'unrun').length;
  }

  function statusBadge(status) {
    const s = status || 'unrun';
    const label = {
      pass: 'pass', fail: 'fail', blocked: 'blocked', error: 'error',
      warn: 'warn', skip: 'skip', unrun: 'not run', running: 'running',
    }[s] || s;
    return `<span class="badge ${esc(s)}">${esc(label)}</span>`;
  }

  function emptyState(icon, title, text) {
    const ico = icon === '◌' ? '<i class="fa-solid fa-inbox"></i>' : icon;
    return `<div class="empty"><div class="ico">${ico}</div>` +
      `<b>${esc(title)}</b><div>${esc(text)}</div></div>`;
  }

  /* ---------------------------------------------------------------- bridges */
  function setupQtBridge() {
    if (typeof QWebChannel === 'undefined' || !window.qt ||
        !window.qt.webChannelTransport || window.NATIVAX_QT) return;
    new QWebChannel(window.qt.webChannelTransport, (channel) => {
      const obj = channel.objects.nativax;
      if (!obj) return;
      const call = (name, args = []) => new Promise((resolve) => {
        try {
          obj[name](...args, (raw) => {
            try { resolve(JSON.parse(raw)); } catch (e) { resolve(raw); }
          });
        } catch (e) { resolve(null); }
      });
      window.NATIVAX_QT = {
        get_data: () => call('get_data'),
        get_live: () => call('get_live'),
        run_tests: (scope, section, responsive, filt) =>
          call('run_tests', [scope, section, !!responsive, filt]),
        run_visual: (scope, caseId, section, widths) =>
          call('run_visual', [scope, caseId, section, widths]),
        stop: () => call('stop_run'),
      };
      poll();
    });
  }

  function nativeApi() {
    if (window.NATIVAX_QT) return { kind: 'qt', ...window.NATIVAX_QT };
    if (window.pywebview && window.pywebview.api) {
      const api = window.pywebview.api;
      return {
        kind: 'pywebview',
        get_data: () => api.get_data(),
        get_live: () => api.get_live(),
        run_tests: (scope, section, responsive, filt) =>
          api.run_tests(scope, section, responsive, filt),
        run_visual: (scope, caseId, section, widths) =>
          api.run_visual(scope, caseId, section, widths),
        stop: () => api.stop_run(),
      };
    }
    return null;
  }

  window.NATIVAX_PUSH = (payload) => {
    if (!payload) return;
    if (payload.data) {
      DATA = payload.data;
      renderAll();
    }
    if (payload.status) applyStatus(payload.status);
  };

  /* ------------------------------------------------------------------ status */
  async function poll() {
    if (window.NATIVAX_QT) return; // Qt pushes updates; avoid duplicate load
    let st = null;
    const api = nativeApi();
    if (api) {
      try {
        st = await api.get_live();
        lastPollError = '';
      } catch (e) {
        lastPollError = String(e);
      }
    }
    if (!st) {
      if (!LIVE && !DATA) return;
      st = { running: !!(LIVE && LIVE.running), progress: LIVE, log: [] };
    }
    applyStatus(st);
  }

  function applyStatus(st) {
    if (!st) return;
    STATUS = st;
    if (st.progress) LIVE = st.progress;
    const running = !!st.running || !!(LIVE && LIVE.running && !st.stale);
    const key = LIVE ? `${LIVE.updated_at}|${(LIVE.events || []).length}` : '';
    const changed = key !== lastLiveKey;
    lastLiveKey = key;

    renderRunState(running);
    if (changed) {
      renderSections();
      if (VIEW === 'envivo' || VIEW === 'visual') renderView(VIEW);
      renderJudge();
    } else {
      renderJudge();
    }

    if (wasRunning && !running) {
      refreshData();
    }
    wasRunning = running;
  }

  async function refreshData() {
    const api = nativeApi();
    if (!api) return;
    try {
      const fresh = await api.get_data();
      if (fresh && typeof fresh === 'object') {
        DATA = fresh;
        renderAll();
      }
    } catch (e) { /* keep the previous data */ }
  }

  /* ------------------------------------------------------------------- runs */
  function currentModeConfig() {
    if (MODE === 'visual') {
      return { scopes: [['case', 'Un case'], ['section', 'Section'], ['all', 'All']] };
    }
    return { scopes: [['all', 'All'], ['section', 'Section']] };
  }

  function syncControls() {
    const scope = $('#scope');
    const previous = scope.value;
    const cfg = currentModeConfig();
    scope.innerHTML = cfg.scopes.map(([v, l]) =>
      `<option value="${v}">${esc(l)}</option>`).join('');
    if (cfg.scopes.some(([v]) => v === previous)) scope.value = previous;

    $('#case-wrap').hidden = MODE !== 'visual';
    $('#widths-wrap').hidden = MODE !== 'visual';
    $('#sweep-wrap').hidden = true;
    $('#section-wrap').hidden = scope.value === 'all';
    $('#scope').onchange = () => {
      $('#section-wrap').hidden = scope.value === 'all';
    };
  }

  function selectedSection() {
    return parseInt($('#section').value || '1', 10) || 1;
  }

  async function startRun() {
    const api = nativeApi();
    const scope = $('#scope').value;
    const section = selectedSection();
    let result = null;

    if (MODE === 'visual') {
      const caseId = $('#case').value || '';
      if (api) {
        result = await api.run_visual(scope, caseId, section,
                                      $('#widths').value || '1024');
      } else if (window.NATIVAX_BRIDGE === 'gtk') {
        location.href = 'nativax://run?' + new URLSearchParams({
          kind: 'visual', scope, case: caseId, section: String(section),
          widths: $('#widths').value || '1024',
        }).toString();
        result = { started: true };
      }
    } else {
      const responsive = MODE === 'responsive';
      if (api) {
        result = await api.run_tests(scope, section, responsive, '');
      } else if (window.NATIVAX_BRIDGE === 'gtk') {
        location.href = 'nativax://run?' + new URLSearchParams({
          kind: 'lab', scope, section: String(section),
          responsive: responsive ? '1' : '0',
        }).toString();
        result = { started: true };
      }
    }

    if (!api && window.NATIVAX_BRIDGE !== 'gtk') {
      toast('Abre la ventana nativa (PyQt6-WebEngine) para ejecutar. ' +
            'El navegador es solo lectura.');
      return;
    }
    if (result && result.started === false) {
      toast(result.error || 'No se pudo iniciar la ejecución');
      return;
    }
    toast('Ejecución iniciada');
    showView(MODE === 'visual' ? 'visual' : 'envivo');
  }

  async function stopRun() {
    const api = nativeApi();
    if (api) {
      await api.stop();
      toast('Detención solicitada');
    } else if (window.NATIVAX_BRIDGE === 'gtk') {
      location.href = 'nativax://run?kind=stop';
    }
  }

  /* -------------------------------------------------------------- runs state */
  function renderRunState(running) {
    const dot = $('#run-dot');
    const text = $('#run-text');
    const bar = $('#run-bar');
    if (!dot) return;
    dot.className = 'dot' + (running ? ' running' : (LIVE && LIVE.summary ? ' pass' : ''));
    const p = LIVE || {};
    const total = Number(p.total || 0);
    const done = Number(p.done || 0);
    if (running) {
      const pctDone = total ? Math.min(100, Math.round((done / total) * 100)) : 0;
      bar.style.width = `${pctDone}%`;
      const cur = p.current;
      text.textContent = cur && cur.id
        ? `${done}/${total || '?'} · ${cur.id}`
        : `running ${p.kind || ''}`;
    } else if (p.summary || (STATUS && STATUS.exit_code !== null &&
                             STATUS.exit_code !== undefined)) {
      const s = p.summary || {};
      const label = p.kind === 'visual'
        ? `visual ${s.pass || 0} pass · ${s.fail || 0} fail · ${s.error || 0} error`
        : `lab ${s.pass || 0} pass · ${s.fail || 0} fail · ${s.blocked || 0} blocked`;
      text.textContent = `finished · ${label}`;
      bar.style.width = '100%';
    } else {
      text.textContent = 'No run';
      bar.style.width = '0';
    }
    $('#btn-run').disabled = !!running;
    $('#btn-stop').disabled = !running;
  }

  /* --------------------------------------------------------------- rendering */
  function renderAll() {
    renderSections();
    renderControls();
    renderView(VIEW);
    renderJudge();
    renderFoot();
  }

  function renderFoot() {
    const n = executedCount();
    const corpus = (DATA.cases || []).length;
    $('#side-foot').innerHTML = corpus
      ? `${corpus} cases registrados · ${n} executed.<br>` +
        (n ? 'Data comes from your local runs.' : 'No results yet.')
      : 'Sin corpus cargado.';
  }

  function renderControls() {
    const secSel = $('#section');
    const sections = DATA.sections || [];
    const prev = secSel.value;
    secSel.innerHTML = sections.map(([sid, name]) =>
      `<option value="${esc(String(parseInt(sid.replace('s', ''), 10)))}">` +
      `${esc(sid)} · ${esc(name)}</option>`).join('');
    const values = Array.from(secSel.options).map((o) => o.value);
    if (values.includes(prev)) secSel.value = prev;

    const caseSel = $('#case');
    const prevCase = caseSel.value;
    caseSel.innerHTML = (DATA.cases || []).map((c) =>
      `<option value="${esc(c.id)}">${esc(c.id)} · ${esc(c.name)}</option>`).join('');
    const caseValues = Array.from(caseSel.options).map((o) => o.value);
    if (caseValues.includes(prevCase)) caseSel.value = prevCase;
    else if (caseValues.length) caseSel.value = caseValues[0];

    syncControls();
  }

  function sectionCounts() {
    const out = {};
    for (const c of DATA.cases || []) {
      const row = out[c.sid] || (out[c.sid] = {
        total: 0, pass: 0, fail: 0, blocked: 0, error: 0, warn: 0,
        unrun: 0, done: 0,
      });
      row.total += 1;
      const st = c.status || 'unrun';
      row[st] = (row[st] || 0) + 1;
      if (st !== 'unrun') row.done += 1;
    }
    const live = (LIVE && LIVE.sections) || {};
    for (const [num, row] of Object.entries(live)) {
      const sid = `s${String(num).padStart(2, '0')}`;
      const target = out[sid] || (out[sid] = {
        total: 0, pass: 0, fail: 0, blocked: 0, error: 0, warn: 0,
        unrun: 0, done: 0,
      });
      target.total = Math.max(target.total, row.total || 0);
      target.done = Math.max(target.done, row.done || 0);
      for (const k of ['pass', 'fail', 'blocked', 'error', 'warn']) {
        target[k] = Math.max(target[k] || 0, row[k] || 0);
      }
    }
    return out;
  }

  function renderSections() {
    const host = $('#sections');
    if (!host) return;
    const sections = DATA.sections || [];
    const counts = sectionCounts();
    if (!sections.length) {
      host.innerHTML = '<div class="side-foot">No sections registered.</div>';
      return;
    }
    host.innerHTML = sections.map(([sid, name], index) => {
      const row = counts[sid] || { total: 0, done: 0, pass: 0, fail: 0,
                                   blocked: 0, error: 0, warn: 0 };
      const running = !!(LIVE && LIVE.running && LIVE.current &&
                         String(LIVE.current.section) === String(index + 1));
      let cls = 'unrun';
      if (running) cls = 'running';
      else if (row.fail || row.error) cls = 'fail';
      else if (row.warn || row.blocked) cls = 'warn';
      else if (row.pass) cls = 'pass';
      const active = SECTION === sid ? ' active' : '';
      const small = sid === 's17'
        ? `${(DATA.gaps || []).length} gaps`
        : `${row.done}/${row.total || 0}`;
      return `<button class="sec-item${active}" data-section="${esc(sid)}">` +
        `<span class="dot ${cls}"></span><b>${esc(sid)}</b>` +
        `<small>${esc(small)}</small></button>`;
    }).join('');
    $$('#sections .sec-item').forEach((btn) => {
      btn.onclick = () => {
        SECTION = btn.dataset.section;
        showView('resumen');
      };
    });
  }

  function showView(name) {
    VIEW = name;
    $$('#views button').forEach((b) =>
      b.classList.toggle('active', b.dataset.view === name));
    $$('.view').forEach((v) =>
      v.classList.toggle('active', v.id === `view-${name}`));
    renderView(name);
  }

  function renderView(name) {
    if (name === 'resumen') renderSummary();
    else if (name === 'envivo') renderEnVivo();
    else if (name === 'informes') renderReports();
    else if (name === 'visual') renderVisual();
    else if (name === 'rendimiento') renderPerformance();
    else if (name === 'historial') renderHistory();
    else if (name === 'artefactos') renderArtifacts();
  }

  function kpi(label, value, cls = '') {
    return `<div class="kpi ${cls}"><div class="v">${esc(value)}</div>` +
      `<div class="l">${esc(label)}</div></div>`;
  }

  function summaryOf() {
    if (LIVE && LIVE.summary) return LIVE.summary;
    if (DATA.report && DATA.report.summary) return DATA.report.summary;
    return null;
  }

  function renderSummary() {
    const host = $('#view-resumen');
    if (!host) return;
    const executed = executedCount();
    const s = summaryOf();
    const liveVisual = LIVE && LIVE.kind === 'visual' && LIVE.summary;

    if (!hasRunData() && !executed && !liveVisual) {
      host.innerHTML = emptyState('◌', 'No runs yet',
        'Run from the top bar. Results will appear here ' +
        'and in the judge on the right. No sample data.');
      return;
    }

    const sums = s || {};
    let html = `<section class="panel"><div class="panel-head">` +
      `<h2>Execution summary</h2>` +
      `<span class="hint">${esc(DATA.report && DATA.report.generated_at || '')}` +
      `</span></div><div class="kpis">` +
      kpi('Cases', sums.total ?? executed) +
      kpi('Pass', sums.pass ?? 0, 'pass') +
      kpi('Fail', sums.fail ?? 0, 'fail') +
      kpi('Blocked', sums.blocked ?? 0, 'blocked') +
      kpi('Error', sums.error ?? 0, 'error') +
      `</div></section>`;

    const counts = sectionCounts();
    html += `<section class="panel"><div class="panel-head">` +
      `<h2>Sections</h2><span class="hint">pass / total executed</span></div>` +
      `<div class="table-wrap"><table><thead><tr><th>Section</th><th>Status</th>` +
      `<th>Pass</th><th>Fail</th><th>Blocked</th><th>Error</th><th>Avance</th>` +
      `</tr></thead><tbody>` +
      (DATA.sections || []).map(([sid]) => {
        const r = counts[sid] || { total: 0, done: 0, pass: 0, fail: 0,
                                   blocked: 0, error: 0 };
        const pctDone = r.total ? Math.round((r.done / r.total) * 100) : 0;
        const cls = (r.fail || r.error) ? 'fail' : (r.pass ? 'pass' : 'unrun');
        return `<tr><td class="mono">${esc(sid)}</td><td>${statusBadge(cls)}</td>` +
          `<td class="num">${r.pass || 0}</td><td class="num">${r.fail || 0}</td>` +
          `<td class="num">${r.blocked || 0}</td><td class="num">${r.error || 0}</td>` +
          `<td><div class="bar-mini"><i class="i-pass" style="width:${pctDone}%"></i></div></td></tr>`;
      }).join('') + `</tbody></table></div></section>`;

    if (executed) {
      let rows = (DATA.cases || []).filter((c) =>
        (!SECTION || c.sid === SECTION) &&
        (!STATUS_FILTER || c.status === STATUS_FILTER) &&
        (!QUERY || `${c.id} ${c.name} ${c.repo}`.toLowerCase().includes(QUERY)));
      const total = rows.length;
      rows = rows.slice(0, 80);
      html += `<section class="panel"><div class="panel-head"><h2>Cases</h2>` +
        `<div class="filters"><input id="q" type="search" placeholder="Buscar case o repo…" value="${esc(QUERY)}">` +
        `<select id="f-status"><option value="">Alls</option>` +
        ['pass', 'fail', 'blocked', 'error', 'unrun'].map((v) =>
          `<option value="${v}"${STATUS_FILTER === v ? ' selected' : ''}>${v}</option>`).join('') +
        `</select></div></div>` +
        `<div class="table-wrap"><table><thead><tr><th>ID</th><th>Section</th>` +
        `<th>Name</th><th>ms</th><th>Status</th></tr></thead><tbody>` +
        rows.map((c) => `<tr><td class="mono">${esc(c.id)}</td>` +
          `<td>${esc(c.sid)}</td><td>${esc(c.name)}</td>` +
          `<td class="num">${c.ms ? num(c.ms) : '—'}</td>` +
          `<td>${statusBadge(c.status)}</td></tr>`).join('') +
        `</tbody></table></div><div class="hint" style="margin-top:8px">` +
        `${rows.length} of ${total} cases` +
        (SECTION ? ` · section ${esc(SECTION)}` : '') + `</div></section>`;
      setTimeout(() => {
        const q = $('#q');
        const f = $('#f-status');
        if (q) q.oninput = () => { QUERY = q.value.toLowerCase(); renderSummary(); };
        if (f) f.onchange = () => { STATUS_FILTER = f.value; renderSummary(); };
      }, 0);
    }
    host.innerHTML = html;
  }

  function stageIndex(stage) {
    if (!stage) return -1;
    if (stage === 'chrome') return 0;
    if (stage === 'chrome_done') return 1;
    if (stage === 'nativax') return 1;
    if (stage === 'nativax_done') return 2;
    if (stage === 'diff') return 2;
    if (stage === 'diff_done' || stage === 'comparison_done' || stage === 'case_done') return 3;
    return -1;
  }

  function pipelineHTML(stage) {
    const idx = stageIndex(stage);
    const cls = (i) => i < idx ? 'done' : (i === idx ? 'active' : '');
    return `<div class="pipeline">` +
      `<div class="step ${cls(0)}">1 · Chrome</div>` +
      `<div class="step ${cls(1)}">2 · NativaX</div>` +
      `<div class="step ${cls(2)}">3 · Diff</div>` +
      `</div>`;
  }

  function eventHTML(e) {
    const st = e.status || (e.type === 'stage' ? 'running' : '');
    const id = e.id || e.case || '';
    const label = e.type === 'stage'
      ? `etapa: ${e.stage || ''}`
      : e.type === 'section_start' ? `section ${e.section}`
      : e.type === 'section_done' ? `section ${e.section} finished`
      : e.type === 'case_start' ? 'inicio'
      : e.type === 'finish' ? 'fin'
      : '';
    return `<div class="event"><span class="id">${esc(id)}</span>` +
      `<span class="msg">${esc(label)}${e.name ? ' · ' + esc(e.name) : ''}` +
      `${e.message ? ' · ' + esc(e.message) : ''}</span>` +
      (st ? `<span class="st">${statusBadge(st)}</span>` : '') + `</div>`;
  }

  function renderEnVivo() {
    const host = $('#view-envivo');
    if (!host) return;
    if (!LIVE) {
      host.innerHTML = emptyState('◌', 'No run in progress',
        'Press Start in the top bar to watch each case run live. ' +
        'Screenshots are only produced in Chrome vs NativaX mode. ' +
        'The judge on the right shows the standards.');
      return;
    }
    const p = LIVE;
    const s = p.summary || {};
    const running = !!(p.running && !(STATUS && STATUS.stale));
    const done = Number(p.done || 0);
    const total = Number(p.total || 0);
    const pctDone = total ? Math.min(100, Math.round((done / total) * 100)) : 0;
    const cur = p.current || {};

    let html = `<section class="panel"><div class="panel-head">` +
      `<h2>${esc(p.title || 'Run')}</h2>` +
      `<span class="badge ${running ? 'running' : ((s.fail || s.error) ? 'fail' : 'pass')}">` +
      `${running ? 'running' : 'finished'}</span></div>` +
      `<div class="hint">${done} / ${total || '?'} cases · ${pctDone}% · ` +
      `${esc(p.kind === 'visual' ? 'Chrome vs NativaX' : 'laboratorio')}</div>` +
      `<div class="bar-mini" style="height:9px;margin:10px 0"><i class="i-pass" style="width:${pctDone}%"></i></div>`;

    if (p.kind === 'visual') {
      html += pipelineHTML(p.stage);
      const c = p.case || {};
      const m = c.metrics || {};
      html += `<div class="compare">` +
        `<figure><figcaption><span>Chrome</span></figcaption>` +
        `<img src="${esc(c.chrome || '')}" alt="Chrome" onload="console.log('img ok',this.src)" onerror="console.error('img fail',this.src)">` +
        `</figure>` +
        `<figure><figcaption><span>NativaX</span></figcaption>` +
        `<img src="${esc(c.nativax || '')}" alt="NativaX" onload="console.log('img ok',this.src)" onerror="console.error('img fail',this.src)">` +
        `</figure>` +
        `<figure><figcaption><span>Diff</span></figcaption>` +
        `<img src="${esc(c.diff || '')}" alt="Diff" onload="console.log('img ok',this.src)" onerror="console.error('img fail',this.src)">` +
        `</figure></div>`;
      html += `<div class="metrics">` +
        `<div class="metric"><div class="v">${pct(m.changed_percent)}</div><div class="l">change</div></div>` +
        `<div class="metric"><div class="v">${num(m.mae, 2)}</div><div class="l">MAE</div></div>` +
        `<div class="metric"><div class="v">${num(m.ssim, 4)}</div><div class="l">SSIM</div></div>` +
        `<div class="metric"><div class="v">${statusBadge(c.status)}</div><div class="l">current case</div></div>` +
        `</div>`;
    } else {
      html += `<div class="hint">Case actual: <b class="mono">` +
        `${esc(cur.id || '—')}</b> ${esc(cur.name || '')} ` +
        `${cur.status ? statusBadge(cur.status) : ''}</div>`;
    }
    html += `</section>`;

    html += `<section class="panel"><div class="panel-head">` +
      `<h2>Cases en vivo</h2><span class="hint">los últimos 120 eventos</span></div>` +
      `<div class="events">` +
      (p.events || []).slice(-120).reverse().map(eventHTML).join('') +
      `</div></section>`;

    if (STATUS && STATUS.log && STATUS.log.length) {
      html += `<section class="panel"><div class="panel-head"><h2>Salida del proceso</h2>` +
        `</div><pre class="log">${esc(STATUS.log.join('\n'))}</pre></section>`;
    }
    host.innerHTML = html;
  }

  function renderReports() {
    const host = $('#view-informes');
    if (!host) return;
    if (!DATA.report || !DATA.report.available) {
      host.innerHTML = emptyState('◌', 'No reports yet',
        'When a run finishes the real report is written to ' +
        'debug/reports/lab. No sample reports.');
      return;
    }
    const s = DATA.report.summary || {};
    let html = `<section class="panel"><div class="panel-head">` +
      `<h2>Lab report</h2><span class="hint">` +
      `${esc(DATA.report.generated_at || '')} · ${esc(DATA.report.label || '')}` +
      `</span></div><div class="kpis">` +
      kpi('Total', s.total ?? 0) + kpi('Pass', s.pass ?? 0, 'pass') +
      kpi('Fail', s.fail ?? 0, 'fail') + kpi('Blocked', s.blocked ?? 0, 'blocked') +
      kpi('Error', s.error ?? 0, 'error') + `</div></section>`;

    const reps = DATA.report_sections || [];
    html += `<section class="panel"><div class="panel-head"><h2>Reports by section</h2>` +
      `<span class="hint">${reps.length}</span></div><div class="table-wrap">` +
      `<table><thead><tr><th>Report</th><th>Total</th><th>Pass</th><th>Fail</th>` +
      `<th>Blocked</th><th>Error</th></tr></thead><tbody>` +
      reps.map((r) => `<tr><td class="mono">${esc(r.label || r.file)}</td>` +
        `<td class="num">${r.summary.total ?? 0}</td>` +
        `<td class="num">${r.summary.pass ?? 0}</td>` +
        `<td class="num">${r.summary.fail ?? 0}</td>` +
        `<td class="num">${r.summary.blocked ?? 0}</td>` +
        `<td class="num">${r.summary.error ?? 0}</td></tr>`).join('') +
      `</tbody></table></div></section>`;
    host.innerHTML = html;
  }

  function visualCase() {
    const cases = DATA.visual && DATA.visual.cases;
    if (!cases) return null;
    if (VSEL && cases[VSEL]) return cases[VSEL];
    const keys = Object.keys(cases);
    if (!keys.length) return null;
    VSEL = keys[keys.length - 1];
    return cases[VSEL];
  }

  function renderVisual() {
    const host = $('#view-visual');
    if (!host) return;
    const v = DATA.visual || {};
    const liveVisual = LIVE && LIVE.kind === 'visual';

    let html = '';
    if (liveVisual) {
      const p = LIVE;
      const c = p.case || {};
      const m = c.metrics || {};
      html += `<section class="panel"><div class="panel-head">` +
        `<h2>Live comparison</h2>` +
        `<span class="badge ${p.running ? 'running' : 'pass'}">` +
        `${p.running ? 'running' : 'finished'}</span></div>` +
        pipelineHTML(p.stage) +
        `<div class="hint">Case: <b class="mono">${esc(c.id || '—')}</b> ` +
        `${esc(c.name || '')} ${c.status ? statusBadge(c.status) : ''}</div>` +
        `<div class="compare">` +
        `<figure><figcaption><span>Chrome</span></figcaption>` +
        `<img src="${esc(c.chrome || '')}" alt="Chrome"></figure>` +
        `<figure><figcaption><span>NativaX</span></figcaption>` +
        `<img src="${esc(c.nativax || '')}" alt="NativaX"></figure>` +
        `<figure><figcaption><span>Diff</span></figcaption>` +
        `<img src="${esc(c.diff || '')}" alt="Diff"></figure></div>` +
        `<div class="metrics">` +
        `<div class="metric"><div class="v">${pct(m.changed_percent)}</div><div class="l">change</div></div>` +
        `<div class="metric"><div class="v">${num(m.mae, 2)}</div><div class="l">MAE</div></div>` +
        `<div class="metric"><div class="v">${num(m.ssim, 4)}</div><div class="l">SSIM</div></div>` +
        `<div class="metric"><div class="v">${num(m.rmse, 2)}</div><div class="l">RMSE</div></div>` +
        `</div></section>`;
    }

    if (!v.cases || !Object.keys(v.cases).length) {
      if (!liveVisual) {
        host.innerHTML = html + emptyState('◌', 'No comparisons yet',
          'Pick a case and press Chrome vs NativaX in the top bar. ' +
          'You will see Chrome → NativaX → diff as it runs.');
      } else {
        host.innerHTML = html;
      }
      return;
    }

    const summary = v.summary || {};
    html += `<section class="panel"><div class="panel-head">` +
      `<h2>Chrome vs NativaX results</h2><span class="hint">` +
      `${esc(v.generated_at || '')}</span></div><div class="kpis">` +
      kpi('Cases', summary.cases ?? 0) + kpi('Comparisons', summary.comparisons ?? 0) +
      kpi('Pass', summary.pass ?? 0, 'pass') + kpi('Warn', summary.warn ?? 0, 'warn') +
      kpi('Fail', summary.fail ?? 0, 'fail') + kpi('Error', summary.error ?? 0, 'error') +
      `</div><div class="hint" style="margin-top:10px">` +
      `Mean change ${pct(summary.mean_changed_percent)} · ` +
      `Mean SSIM ${num(summary.mean_ssim, 4)}</div></section>`;

    const keys = Object.keys(v.cases);
    const current = visualCase();
    const selected = VSEL;
    html += `<section class="panel"><div class="panel-head"><h2>Comparison by case</h2>` +
      `<div class="filters"><select id="v-case">` +
      keys.map((k) => `<option value="${esc(k)}"${k === selected ? ' selected' : ''}>` +
        `${esc(k)} · ${esc(v.cases[k].name || '')}</option>`).join('') +
      `</select></div></div>`;
    if (current) {
      const row = (current.results || [])[0] || {};
      const m = row.metrics || {};
      const chrome = row.chrome || {};
      const nativax = row.nativax || {};
      html += `<div class="compare">` +
        `<figure><figcaption><span>Chrome</span><span>${esc(row.width ? row.width + 'px' : '')}</span></figcaption>` +
        `<a href="${esc(chrome.url || '')}" target="_blank"><img src="${esc(chrome.url || '')}" alt="Chrome"></a></figure>` +
        `<figure><figcaption><span>NativaX</span></figcaption>` +
        `<a href="${esc(nativax.url || '')}" target="_blank"><img src="${esc(nativax.url || '')}" alt="NativaX"></a></figure>` +
        `<figure><figcaption><span>Diff</span></figcaption>` +
        `<a href="${esc(m.diff_url || '')}" target="_blank"><img src="${esc(m.diff_url || '')}" alt="Diff"></a></figure>` +
        `</div><div class="metrics">` +
        `<div class="metric"><div class="v">${pct(m.changed_percent)}</div><div class="l">change</div></div>` +
        `<div class="metric"><div class="v">${num(m.mae, 2)}</div><div class="l">MAE</div></div>` +
        `<div class="metric"><div class="v">${num(m.rmse, 2)}</div><div class="l">RMSE</div></div>` +
        `<div class="metric"><div class="v">${num(m.ssim, 4)}</div><div class="l">SSIM</div></div>` +
        `<div class="metric"><div class="v">${m.bbox ? esc(JSON.stringify(m.bbox)) : '—'}</div><div class="l">bbox</div></div>` +
        `<div class="metric"><div class="v">${statusBadge(row.status)}</div><div class="l">status</div></div>` +
        `</div>`;
    }
    html += `<div class="table-wrap"><table><thead><tr><th>Case</th><th>Section</th>` +
      `<th>Status</th><th>Mean change</th><th>Mean SSIM</th><th>Widths</th>` +
      `</tr></thead><tbody>` +
      keys.map((k) => {
        const c = v.cases[k];
        return `<tr><td class="mono">${esc(k)}</td><td>${esc(c.section)}</td>` +
          `<td>${statusBadge(c.status)}</td><td class="num">${pct(c.mean_changed_percent)}</td>` +
          `<td class="num">${num(c.mean_ssim, 4)}</td>` +
          `<td>${(c.results || []).map((r) => r.width + 'px').join(', ')}</td></tr>`;
      }).join('') + `</tbody></table></div></section>`;

    host.innerHTML = html;
    const sel = $('#v-case');
    if (sel) sel.onchange = () => { VSEL = sel.value; renderVisual(); };
  }

  function renderPerformance() {
    const host = $('#view-rendimiento');
    if (!host) return;
    const measured = (DATA.cases || []).filter((c) => Number(c.ms) > 0);
    if (!measured.length) {
      host.innerHTML = emptyState('◌', 'No performance data',
        'Durations come from your real runs. Run the ' +
        'lab to measure them.');
      return;
    }
    const total = measured.reduce((a, c) => a + Number(c.ms), 0);
    const max = Math.max(...measured.map((c) => Number(c.ms)));
    const rows = measured.slice().sort((a, b) => Number(b.ms) - Number(a.ms));
    const bySec = {};
    for (const c of measured) {
      const r = bySec[c.sid] || (bySec[c.sid] = { n: 0, ms: 0, max: 0 });
      r.n += 1;
      r.ms += Number(c.ms);
      r.max = Math.max(r.max, Number(c.ms));
    }
    let html = `<section class="panel"><div class="panel-head"><h2>Performance</h2>` +
      `<span class="hint">durations measured per case</span></div><div class="kpis">` +
      kpi('Measured cases', measured.length) +
      kpi('Total time', ms(total)) +
      kpi('Average', ms(total / measured.length)) +
      kpi('Maximum', ms(max)) + `</div></section>`;

    html += `<section class="panel"><div class="panel-head"><h2>By section</h2></div>` +
      `<div class="table-wrap"><table><thead><tr><th>Section</th><th>Cases</th>` +
      `<th>Total</th><th>Average</th><th>Maximum</th></tr></thead><tbody>` +
      Object.entries(bySec).sort((a, b) => b[1].ms - a[1].ms).map(([sid, r]) =>
        `<tr><td class="mono">${esc(sid)}</td><td class="num">${r.n}</td>` +
        `<td class="num">${ms(r.ms)}</td><td class="num">${ms(r.ms / r.n)}</td>` +
        `<td class="num">${ms(r.max)}</td></tr>`).join('') +
      `</tbody></table></div></section>`;

    html += `<section class="panel"><div class="panel-head"><h2>Slowest cases</h2></div>` +
      `<div class="table-wrap"><table><thead><tr><th>Case</th><th>Section</th>` +
      `<th>Duration</th><th>Status</th></tr></thead><tbody>` +
      rows.slice(0, 20).map((c) => `<tr><td class="mono">${esc(c.id)}</td>` +
        `<td>${esc(c.sid)}</td><td class="num">${ms(c.ms)}</td>` +
        `<td>${statusBadge(c.status)}</td></tr>`).join('') +
      `</tbody></table></div></section>`;
    host.innerHTML = html;
  }

  function renderHistory() {
    const host = $('#view-historial');
    if (!host) return;
    const hist = DATA.history || [];
    if (!hist.length) {
      host.innerHTML = emptyState('◌', 'No history',
        'No saved runs. History only contains what runs on ' +
        'this machine; no sample runs.');
      return;
    }
    host.innerHTML = `<section class="panel"><div class="panel-head">` +
      `<h2>Run history</h2><span class="hint">${hist.length}</span>` +
      `</div><div class="table-wrap"><table><thead><tr><th>Run</th><th>Fecha</th>` +
      `<th>Total</th><th>Pass</th><th>Fail</th><th>Blocked</th><th>Error</th>` +
      `</tr></thead><tbody>` +
      hist.slice().reverse().map((h) => {
        const t = h.totals || {};
        return `<tr data-run="${esc(h.run_id || '')}"><td class="mono">${esc(h.run_id || '')}</td>` +
          `<td>${esc(h.timestamp || '')}</td><td class="num">${t.total ?? 0}</td>` +
          `<td class="num">${t.pass ?? 0}</td><td class="num">${t.fail ?? 0}</td>` +
          `<td class="num">${t.blocked ?? 0}</td><td class="num">${t.error ?? 0}</td></tr>`;
      }).join('') + `</tbody></table></div></section>`;
    $$('#view-historial tr[data-run]').forEach((tr) => {
      tr.onclick = () => {
        const h = hist.find((x) => x.run_id === tr.dataset.run) || {};
        const existing = tr.nextElementSibling;
        if (existing && existing.classList.contains('hist-detail')) {
          existing.remove();
          return;
        }
        const row = document.createElement('tr');
        row.className = 'hist-detail';
        const cell = document.createElement('td');
        cell.colSpan = 7;
        cell.innerHTML = `<pre class="log" style="max-height:200px">${esc(JSON.stringify(h, null, 2))}</pre>`;
        row.appendChild(cell);
        tr.after(row);
      };
    });
  }

  function renderArtifacts() {
    const host = $('#view-artefactos');
    if (!host) return;
    const items = DATA.artifacts || [];
    if (!items.length) {
      host.innerHTML = emptyState('◌', 'No artifacts',
        'Chrome, NativaX and diff captures will appear here ' +
        'once you run a comparison.');
      return;
    }
    host.innerHTML = `<section class="panel"><div class="panel-head">` +
      `<h2>Artifacts visuales</h2><span class="hint">${items.length}</span></div>` +
      `<div class="artifacts">` +
      items.map((a) => `<div class="artifact" data-path="${esc(a.path)}">` +
        `<img src="${esc(a.url)}" alt="${esc(a.path)}" loading="lazy" ` +
        `onerror="this.style.display='none'">` +
        `<div class="mono" style="margin-top:5px;word-break:break-all">` +
        `${esc(a.path)}</div><div class="hint">${Math.round(a.size / 1024)} KB</div>` +
        `</div>`).join('') + `</div></section>`;
    $$('#view-artefactos .artifact').forEach((el) => {
      el.onclick = () => {
        const img = el.querySelector('img');
        if (img && img.src) window.open(img.src, '_blank');
      };
    });
  }

  /* ------------------------------------------------------------------ judge */
  function judgeSource() {
    if (LIVE) {
      return {
        kind: LIVE.kind || 'lab',
        running: !!LIVE.running && !(STATUS && STATUS.stale),
        summary: LIVE.summary || {},
        standards: LIVE.standards || {},
        title: LIVE.title || 'Ejecución',
        generated: LIVE.started_at || '',
      };
    }
    if (MODE === 'visual' && DATA.visual && DATA.visual.summary) {
      return {
        kind: 'visual', running: false,
        summary: DATA.visual.summary,
        standards: DATA.visual.thresholds || (DATA.standards &&
          DATA.standards.visual && DATA.standards.visual.thresholds) || {},
        title: 'Chrome vs NativaX',
        generated: DATA.visual.generated_at || '',
      };
    }
    if (DATA.report && DATA.report.available) {
      return {
        kind: 'lab', running: false,
        summary: DATA.report.summary || {}, standards: {},
        title: 'Laboratorio',
        generated: DATA.report.generated_at || '',
      };
    }
    return null;
  }

  function stdRow(label, value, state, rule) {
    const mark = state === 'ok' ? '✓' : state === 'bad' ? '✗'
      : state === 'warn' ? '!' : '·';
    return `<div class="std ${esc(state || '')}"><span class="mark">${mark}</span>` +
      `<span>${esc(label)}${rule ? `<div class="hint">${esc(rule)}</div>` : ''}</span>` +
      `<span class="val">${esc(value)}</span></div>`;
  }

  function stdBar(label, value, max, state, rule) {
    const v = (value === null || value === undefined || value === '—') ? 0 : Number(value);
    const m = (max === null || max === undefined) ? 100 : Number(max);
    const width = m ? Math.min(100, Math.max(0, (v / m) * 100)) : 0;
    const color = state === 'ok' ? 'var(--pass)' : state === 'bad' ? 'var(--fail)'
      : state === 'warn' ? 'var(--warn)' : 'var(--muted)';
    return `<div class="stdbar"><div class="stdbar-head">` +
      `<span>${esc(label)}</span><span class="val">${esc(value ?? '—')}` +
      `${rule ? ' · ' + esc(rule) : ''}</span></div>` +
      `<div class="bar-mini" style="height:8px"><i style="width:${width}%;background:${color}"></i></div></div>`;
  }

  function renderJudge() {
    const host = $('#judge-body');
    const badge = $('#judge-badge');
    if (!host || !badge) return;
    const src = judgeSource();
    const defaults = (DATA.standards && DATA.standards.visual &&
                      DATA.standards.visual.thresholds) || {};

    if (!src) {
      badge.className = 'badge unrun';
      badge.textContent = 'no run';
      const t = defaults;
      host.innerHTML = `<div class="judge-meta">The judge evaluates each run. ` +
        `No results yet: these are the standards that will apply.</div>` +
        `<div class="judge-section">` +

        stdRow('Pass', '—', '', 'assertion holds') +
        stdRow('Fail', '—', '', 'real regression; verdict fails') +
        stdRow('Blocked', '—', '', 'capability not implemented (s17)') +
        stdRow('Error', '—', '', 'harness exception; never a pass') +
        `</div><div class="judge-section">` +
        stdRow('Max change', `≤ ${num(t.max_changed_percent, 1)} %`, '',
               'changed pixels allowed for pass') +
        stdRow('Warn', `≤ ${num(t.warn_changed_percent, 1)} %`, '', 'above that is fail') +
        stdRow('MAE', `≤ ${num(t.max_mae, 1)}`, '', 'mean absolute error') +
        stdRow('SSIM', `≥ ${num(t.min_ssim, 2)}`, '', 'structural similarity') +
        stdRow('Tolerancia', `≤ ${num(t.tolerance, 0)}/255`, '', 'per-channel difference ignored') +
        `</div>`;
      return;
    }

    const s = src.summary || {};
    const running = src.running;
    let verdict = 'unrun';
    let verdictText = 'NO RUN';
    if (running) {
      verdict = 'running';
      verdictText = 'RUNNING';
    } else if (src.kind === 'visual') {
      const bad = (Number(s.fail) || 0) + (Number(s.error) || 0);
      verdict = bad ? 'fail' : ((Number(s.comparisons) || 0) ? 'pass' : 'unrun');
      verdictText = bad ? 'FAIL' : ((Number(s.comparisons) || 0)
        ? 'PASS' : 'NO COMPARISONS');
    } else {
      const bad = (Number(s.fail) || 0) + (Number(s.error) || 0);
      verdict = bad ? 'fail' : ((Number(s.total) || 0) ? 'pass' : 'unrun');
      verdictText = bad ? 'FAIL' : ((Number(s.total) || 0) ? 'PASS' : 'NO CASES');
    }
    badge.className = `badge ${verdict}`;
    badge.textContent = verdictText;

    let html = `<div class="verdict ${verdict}">${esc(verdictText)}</div>` +
      `<div class="judge-meta">${esc(src.title)}` +
      (src.generated ? `<br>${esc(src.generated)}` : '') + `</div>`;

    if (src.kind === 'visual') {
      const t = src.standards || defaults;
      const liveCase = (LIVE && LIVE.case) || {};
      const m = liveCase.metrics || {};
      const changed = m.changed_percent ?? (s.mean_changed_percent ?? null);
      const mae = m.mae ?? null;
      const ssim = m.ssim ?? (s.mean_ssim ?? null);
      const okChanged = changed === null ? '' :
        (Number(changed) <= Number(t.max_changed_percent ?? 2) ? 'ok' : 'bad');
      const okMae = mae === null ? '' :
        (Number(mae) <= Number(t.max_mae ?? 6) ? 'ok' : 'bad');
      const okSsim = ssim === null ? '' :
        (Number(ssim) >= Number(t.min_ssim ?? 0.9) ? 'ok' : 'bad');
      const mismatch = m.size_mismatch;
      html += `<div class="judge-section">` +
        stdBar('Change', `${pct(changed)}`, t.max_changed_percent ?? 2,
               okChanged, `≤ ${num(t.max_changed_percent, 1)} %`) +
        stdBar('MAE', `${num(mae, 2)}`, t.max_mae ?? 6, okMae,
               `≤ ${num(t.max_mae, 1)}`) +
        stdBar('SSIM', `${num(ssim, 4)}`, 1, okSsim,
               `≥ ${num(t.min_ssim, 2)}`) +
        stdBar('Tamaño', mismatch === undefined ? '—' : (mismatch ? 'distinto' : 'igual'),
               1, mismatch === true ? 'bad' : (mismatch === false ? 'ok' : ''),
               'igual = ok') +
        stdBar('Tolerancia', `${num(t.tolerance, 0)}/255`, 255, 'ok',
               'ignored difference') +
        `</div><div class="judge-section"><h3>Real counts</h3>` +
        stdRow('Comparisons', num(s.comparisons ?? 0), '', '') +
        stdRow('Pass', num(s.pass ?? 0), (Number(s.pass) || 0) ? 'ok' : '', '') +
        stdRow('Warn', num(s.warn ?? 0), (Number(s.warn) || 0) ? 'warn' : '', 'no es pass') +
        stdRow('Fail', num(s.fail ?? 0), (Number(s.fail) || 0) ? 'bad' : 'ok', 'must be 0') +
        stdRow('Error', num(s.error ?? 0), (Number(s.error) || 0) ? 'bad' : 'ok', 'must be 0') +
        `</div>`;
    } else {
      const resp = src.standards && src.standards.responsive;
      html += `<div class="judge-section">` +
        stdBar('Cases', num(s.total ?? 0), s.total ?? 1, '', 'really executed') +
        stdBar('Pass', num(s.pass ?? 0), s.total ?? 1, (Number(s.pass) || 0) ? 'ok' : '', '') +
        stdBar('Fail', num(s.fail ?? 0), s.total ?? 1, (Number(s.fail) || 0) ? 'bad' : 'ok', 'must be 0') +
        stdBar('Error', num(s.error ?? 0), s.total ?? 1, (Number(s.error) || 0) ? 'bad' : 'ok', 'must be 0') +
        stdBar('Blocked', num(s.blocked ?? 0), s.total ?? 1, (Number(s.blocked) || 0) ? 'warn' : 'ok', 's17 gaps') +
        `</div>`;
    }

    if (src.kind === 'visual') {
      const worst = (s.worst || []).slice(0, 6);
      if (worst.length) {
        html += `<div class="judge-section"><h3>Cases (worst first)</h3>` +
          worst.map((w) => `<div class="judge-case" data-case="${esc(w.id)}">` +
            `<span class="id">${esc(w.id)}</span> ${statusBadge(w.status)}` +
            `<span class="val">${pct(w.mean_changed_percent)}</span>` +
            `</div>`).join('') + `</div>`;
        setTimeout(() => {
          $$('#judge-body .judge-case').forEach((el) => {
            el.onclick = () => {
              VSEL = el.dataset.case;
              showView('visual');
            };
          });
        }, 0);
      }
    }

    if (src.kind === 'lab') {
      const bad = (DATA.cases || []).filter((c) => c.status === 'fail' || c.status === 'error').slice(0, 8);
      if (bad.length) {
        html += `<div class="judge-section"><h3>Failing cases (select)</h3>` +
          bad.map((c) => `<div class="judge-case" data-case="${esc(c.id)}">` +
            `<span class="id">${esc(c.id)}</span> ${statusBadge(c.status)}` +
            `<span class="val">${ms(c.ms)}</span></div>`).join('') + `</div>`;
        setTimeout(() => {
          $$('#judge-body .judge-case').forEach((el) => {
            el.onclick = () => {
              const c = (DATA.cases || []).find((x) => x.id === el.dataset.case);
              if (!c) return;
              // show details inline in the judge, no modal
              const host = $('#judge-body');
              const detail = host.querySelector('.judge-detail');
              const html = `<div class="judge-detail" style="margin-top:8px">` +
                `<div class="hint">Section ${esc(c.sid)} · ${esc(c.name)}</div>` +
                `<div class="hint">Status: ${esc(c.status)} · duration ${ms(c.ms)}</div>` +
                `<pre class="log" style="max-height:160px">${esc(JSON.stringify(c, null, 2))}</pre>` +
                `</div>`;
              if (detail) detail.outerHTML = html;
              else host.insertAdjacentHTML('beforeend', html);
            };
          });
        }, 0);
      }
    }

    if (LIVE && LIVE.events) {
      const last = LIVE.events.slice(-1)[0];
      if (last) {
        html += `<div class="judge-meta">last event: ${esc(last.type)}` +
          `${last.id ? ' · ' + esc(last.id) : ''}` +
          `${last.status ? ' · ' + statusBadge(last.status) : ''}</div>`;
      }
    }
    host.innerHTML = html;
  }

  /* ------------------------------------------------------------------- boot */
  function bind() {
    $$('#run-tabs .run-tab').forEach((btn) => {
      btn.onclick = () => {
        MODE = btn.dataset.mode;
        $$('#run-tabs .run-tab').forEach((b) =>
          b.classList.toggle('active', b === btn));
        syncControls();
        renderJudge();
        showView(MODE === 'visual' ? 'visual' : 'envivo');
      };
    });
    $$('#views button').forEach((btn) => {
      btn.onclick = () => showView(btn.dataset.view);
    });
    $('#btn-run').onclick = startRun;
    $('#btn-stop').onclick = stopRun;
    $('#btn-theme').onclick = () => {
      const cur = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
      document.documentElement.dataset.theme = cur;
      try { localStorage.setItem('nativax-theme', cur); } catch (e) {}
    };
  }

  function init() {
    try {
      const saved = localStorage.getItem('nativax-theme');
      if (saved) document.documentElement.dataset.theme = saved;
    } catch (e) {}
    setupQtBridge();
    bind();
    renderAll();
    showView('resumen');
    poll();
    setInterval(poll, 1500);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
