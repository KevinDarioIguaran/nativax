(() => {
  const API = ''; // same origin when served by dashboard_server
  let DATA = window.DASHBOARD_DATA || {};
  let SECTIONS = DATA.sections || [];
  let REPOS = DATA.repos || [];
  let GAPS = DATA.gaps || [];
  let TREE = DATA.tree || '';
  let CLI = DATA.cli || [];
  let REPORT = DATA.report || { available: false };
  let VISUAL = DATA.visual || {};
  let cases = DATA.cases || [];

  const $ = (s) => document.querySelector(s);
  const state = { q: '', section: '', status: '', page: 0, size: 12 };

  function toast(msg) {
    const t = $('#toast');
    if (!t) return;
    t.textContent = msg;
    t.classList.add('show');
    clearTimeout(toast._t);
    toast._t = setTimeout(() => t.classList.remove('show'), 2200);
  }

  async function api(path, options) {
    try {
      const res = await fetch(API + path, options);
      if (!res.ok) throw new Error(res.status + ' ' + res.statusText);
      const ct = res.headers.get('content-type') || '';
      if (ct.includes('application/json')) return await res.json();
      return await res.text();
    } catch (e) {
      return null;
    }
  }

  async function loadData() {
    let fresh = null;
    if (window.pywebview && window.pywebview.api && window.pywebview.api.reload_data) {
      fresh = await window.pywebview.api.reload_data();
    }
    if (fresh && fresh.cases) {
      DATA = fresh;
      SECTIONS = DATA.sections || [];
      REPOS = DATA.repos || [];
      GAPS = DATA.gaps || [];
      TREE = DATA.tree || '';
      CLI = DATA.cli || [];
      REPORT = DATA.report || { available: false };
      VISUAL = DATA.visual || {};
      cases = DATA.cases || [];
      window.DASHBOARD_DATA = DATA;
    }
  }

  function counts(list) {
    return list.reduce((a, c) => ((a[c.status] = (a[c.status] || 0) + 1), a), {});
  }

  function renderKpis() {
    const c = counts(cases);
    const total = cases.length;
    const reported = cases.filter((x) => x.ms && x.ms > 0);
    const avg = reported.length
      ? Math.round(reported.reduce((s, x) => s + x.ms, 0) / reported.length)
      : '—';
    const items = [
      ['Casos reales', total, ''],
      ['Secciones', SECTIONS.length, ''],
      ['Pass', c.pass || 0, 'pass'],
      ['Fail', c.fail || 0, 'fail'],
      ['Blocked', c.blocked || 0, 'skip'],
      ['Unrun', c.unrun || 0, ''],
      ['Gaps documentados', GAPS.length, ''],
      ['Tiempo medio', (typeof avg === 'number' ? avg + ' ms' : avg), ''],
    ];
    if (!REPORT.available) {
      items.push(['Informe lab', 'no ejecutado', 'fail']);
    } else {
      items.push(['Informe lab', REPORT.label || 'latest', 'pass']);
    }
    $('#kpis').innerHTML = items
      .map(([l, v, k]) => `<div class="kpi ${k}"><div class="v">${v}</div><div class="l">${l}</div></div>`)
      .join('');
  }

  function renderSections() {
    $('#sections').innerHTML = SECTIONS.map(([sid, name]) => {
      const list = cases.filter((c) => c.sid === sid);
      const c = counts(list);
      const pct = (n) => (list.length ? ((n || 0) / list.length) * 100 : 0);
      return `<div class="sec ${state.section === sid ? 'active' : ''}" data-sid="${sid}">
        <div class="row"><b>${sid} · ${name}</b><small>${c.pass || 0}/${list.length}</small></div>
        <div class="bar">
          <i class="p" style="width:${pct(c.pass)}%"></i>
          <i class="f" style="width:${pct(c.fail)}%"></i>
          <i class="s" style="width:${pct((c.skip || 0) + (c.blocked || 0))}%"></i>
        </div></div>`;
    }).join('');
  }

  function filtered() {
    const q = state.q.toLowerCase();
    return cases.filter((c) =>
      (!state.section || c.sid === state.section) &&
      (!state.status || c.status === state.status) &&
      (!q || `${c.id} ${c.name} ${c.repo} ${c.path}`.toLowerCase().includes(q)));
  }

  function renderTable() {
    const list = filtered();
    const pages = Math.max(1, Math.ceil(list.length / state.size));
    state.page = Math.min(state.page, pages - 1);
    const slice = list.slice(state.page * state.size, (state.page + 1) * state.size);
    $('#cases tbody').innerHTML = slice.map((c) => `
      <tr data-id="${c.id}">
        <td class="mono">${c.id}</td>
        <td>${c.name}</td>
        <td class="mono">${c.repo}@${c.commit}</td>
        <td>${c.facts}</td>
        <td>${c.ms}</td>
        <td><span class="badge ${c.status}">${c.status}</span></td>
      </tr>`).join('') || '<tr><td colspan="6">Sin resultados</td></tr>';
    $('#count').textContent = `${list.length} casos · página ${state.page + 1}/${pages}`;
    $('#prev').disabled = state.page === 0;
    $('#next').disabled = state.page >= pages - 1;
  }

  function renderStatic() {
    $('#gaps').innerHTML = GAPS.map((g, i) =>
      `<li><span class="n">${String(i + 1).padStart(2, '0')}</span>${g}<em>bloqueada</em></li>`).join('');
    $('#gaps-count').textContent = `${GAPS.length} capacidades`;
    $('#tree').textContent = TREE;
    $('#cli').innerHTML = CLI.map((c) => `<code>$ ${c}</code>`).join('');
    $('#f-section').innerHTML = '<option value="">Todas las secciones</option>' +
      SECTIONS.map(([s, n]) => `<option value="${s}">${s} · ${n}</option>`).join('');
    // run section select
    const rs = $('#run-section');
    if (rs) {
      rs.innerHTML = SECTIONS.map(([s, n]) => `<option value="${s.replace('s','')}">${s} · ${n}</option>`).join('');
    }
  }

  function drawCharts() {
    const cSec = $('#chart-sections');
    if (cSec) {
      const ctx = cSec.getContext('2d');
      ctx.clearRect(0, 0, cSec.width, cSec.height);
      const w = cSec.width, h = cSec.height;
      const pad = 30;
      const bw = (w - pad * 2) / Math.max(SECTIONS.length, 1);
      SECTIONS.forEach(([sid], i) => {
        const list = cases.filter((c) => c.sid === sid);
        const pass = list.filter((c) => c.status === 'pass').length;
        const pct = list.length ? pass / list.length : 0;
        const bh = (h - pad * 2) * pct;
        const x = pad + i * bw + bw * 0.15;
        const y = h - pad - bh;
        ctx.fillStyle = '#16a34a';
        ctx.fillRect(x, y, bw * 0.7, bh);
        ctx.fillStyle = '#6b7385';
        ctx.font = '10px monospace';
        ctx.fillText(sid, x, h - 12);
      });
    }
    const cSt = $('#chart-status');
    if (cSt) {
      const ctx = cSt.getContext('2d');
      ctx.clearRect(0, 0, cSt.width, cSt.height);
      const c = counts(cases);
      const entries = Object.entries(c);
      const total = cases.length || 1;
      let angle = -Math.PI / 2;
      const colors = { pass: '#16a34a', fail: '#dc2626', blocked: '#d97706', skip: '#d97706', error: '#dc2626', unrun: '#6b7385' };
      const cx = cSt.width / 2, cy = cSt.height / 2, r = Math.min(cx, cy) - 20;
      entries.forEach(([k, v]) => {
        const a = (v / total) * Math.PI * 2;
        ctx.beginPath();
        ctx.moveTo(cx, cy);
        ctx.arc(cx, cy, r, angle, angle + a);
        ctx.closePath();
        ctx.fillStyle = colors[k] || '#4f46e5';
        ctx.fill();
        angle += a;
      });
      // legend
      let ly = 10;
      entries.forEach(([k, v]) => {
        ctx.fillStyle = colors[k] || '#4f46e5';
        ctx.fillRect(10, ly, 12, 12);
        ctx.fillStyle = '#1c2230';
        ctx.font = '12px sans-serif';
        ctx.fillText(`${k}: ${v}`, 28, ly + 10);
        ly += 16;
      });
    }
  }

  function openCase(id) {
    const c = cases.find((x) => x.id === id);
    $('#dlg-title').textContent = `case ${c.id}`;
    $('#dlg-body').innerHTML = `
      <dt>Sección</dt><dd>${c.name}</dd>
      <dt>Repo</dt><dd>${c.repo}</dd>
      <dt>Commit</dt><dd>${c.commit}</dd>
      <dt>Ruta original</dt><dd>${c.path}</dd>
      <dt>Facts</dt><dd>${c.facts} verificaciones independientes</dd>
      <dt>Duración</dt><dd>${c.ms} ms</dd>
      <dt>Estado</dt><dd><span class="badge ${c.status}">${c.status}</span></dd>`;
    $('#dlg').showModal();
  }

  function refresh() { renderKpis(); renderSections(); renderTable(); drawCharts(); }

  async function runTests() {
    const btn = $('#btn-run');
    if (!window.pywebview || !window.pywebview.api || !window.pywebview.api.run_tests) {
      toast('Ejecución disponible solo en la app nativa (pywebview)');
      return;
    }
    btn.disabled = true;
    const scope = $('#run-scope').value;
    const section = parseInt($('#run-section').value, 10) || 1;
    const responsive = $('#run-responsive').checked;
    const res = await window.pywebview.api.run_tests(scope, section, responsive);
    if (!res || !res.started) {
      toast('No se pudo iniciar: ' + (res && res.error ? res.error : 'error'));
      btn.disabled = false;
      return;
    }
    toast('Ejecución iniciada');
    pollRun();
  }

  async function pollRun() {
    const logEl = $('#run-log');
    const statusEl = $('#run-status');
    const btn = $('#btn-run');
    const timer = setInterval(async () => {
      if (!window.pywebview || !window.pywebview.api) return;
      const st = await window.pywebview.api.get_status();
      if (!st) return;
      if (statusEl) statusEl.textContent = st.running ? 'Ejecutando…' : `Finalizado (exit ${st.exit_code})`;
      if (logEl) {
        logEl.textContent = (st.log || []).join('\n');
        logEl.scrollTop = logEl.scrollHeight;
      }
      if (!st.running) {
        clearInterval(timer);
        btn.disabled = false;
        await loadData();
        renderStatic();
        refresh();
        await loadArtifacts();
        toast('Datos recargados');
      }
    }, 1000);
  }

  async function loadArtifacts() {
    // Static data keeps the tab useful when the HTML is opened directly.
    let list = DATA.artifacts || [];
    if (window.pywebview && window.pywebview.api && window.pywebview.api.get_artifacts) {
      const live = await window.pywebview.api.get_artifacts();
      if (live && live.length) list = live;
    }
    const el = $('#artifacts');
    const count = $('#artifacts-count');
    if (!list || !el) return;
    if (count) count.textContent = `${list.length} archivos`;
    el.innerHTML = list.map((a) => {
      if (a.path.match(/\.(png|jpg|jpeg)$/i)) {
        return `<div class="artifact"><img src="${a.url}" alt="${a.path}" onerror="this.style.display='none'"><div>${a.path}</div></div>`;
      }
      return `<div class="artifact"><div>${a.path}</div><div>${a.size} bytes</div></div>`;
    }).join('');
  }

  // ---------------------------------------------------------------- visual
  function visualRows() {
    return Object.values(VISUAL.cases || {});
  }

  function fillVisualCases() {
    const sel = $('#visual-case');
    if (!sel) return;
    const current = sel.value;
    sel.innerHTML = cases.map((c) =>
      `<option value="${c.id}">${c.id} · ${c.repo} · ${c.path}</option>`).join('');
    const known = new Set(cases.map((c) => c.id));
    if (current && known.has(current)) {
      sel.value = current;
      return;
    }
    // Open on a case that already has a comparison, so the images are visible.
    const reported = Object.keys(VISUAL.cases || {}).find((id) => known.has(id));
    if (reported) sel.value = reported;
  }

  function renderVisualKpis() {
    const el = $('#visual-kpis');
    if (!el) return;
    const s = VISUAL.summary || {};
    const items = [
      ['Casos comparados', s.cases || 0, ''],
      ['Capturas', s.comparisons || 0, ''],
      ['Pass', s.pass || 0, 'pass'],
      ['Warn', s.warn || 0, 'skip'],
      ['Fail', s.fail || 0, 'fail'],
      ['Error', s.error || 0, 'fail'],
      ['% distinto medio', s.mean_changed_percent == null ? '—' : s.mean_changed_percent + '%', ''],
      ['SSIM medio', s.mean_ssim == null ? '—' : s.mean_ssim, ''],
    ];
    el.innerHTML = items.map(([l, v, k]) =>
      `<div class="kpi ${k}"><div class="v">${v}</div><div class="l">${l}</div></div>`).join('');
    const meta = $('#visual-meta');
    if (meta) {
      meta.textContent = VISUAL.generated_at
        ? `informe ${VISUAL.generated_at} · ${s.comparisons || 0} capturas`
        : 'Sin comparaciones todavía';
    }
    const th = VISUAL.thresholds || {};
    const tel = $('#visual-thresholds');
    if (tel) {
      tel.textContent = th.tolerance == null ? '' :
        `pass ≤ ${th.max_changed_percent}% · warn ≤ ${th.warn_changed_percent}% · MAE ≤ ${th.max_mae} · SSIM ≥ ${th.min_ssim}`;
    }
  }

  function renderVisualTable() {
    const tbody = document.querySelector('#visual-cases tbody');
    const count = $('#visual-count');
    if (!tbody) return;
    const rows = visualRows().sort((a, b) =>
      (b.mean_changed_percent || 0) - (a.mean_changed_percent || 0));
    if (count) count.textContent = `${rows.length} caso(s)`;
    tbody.innerHTML = rows.map((c) => {
      const widths = c.results.map((r) => r.width).join(', ');
      return `<tr data-cid="${c.id}">
        <td class="mono">${c.id}</td>
        <td>${c.section}</td>
        <td><span class="badge ${c.status}">${c.status}</span></td>
        <td>${c.mean_changed_percent == null ? '—' : c.mean_changed_percent + '%'}</td>
        <td>${c.mean_ssim == null ? '—' : c.mean_ssim}</td>
        <td>${widths}</td>
      </tr>`;
    }).join('') || '<tr><td colspan="6">Sin comparaciones. Usa «Comparar caso».</td></tr>';
  }

  function renderVisualResult() {
    const cid = $('#visual-case') ? $('#visual-case').value : '';
    const sel = $('#visual-result');
    const row = (VISUAL.cases || {})[cid];
    const imgs = {
      chrome: $('#visual-chrome'), nativax: $('#visual-nativax'), diff: $('#visual-diff'),
      chromeLink: $('#visual-chrome-link'), nativaxLink: $('#visual-nativax-link'),
      diffLink: $('#visual-diff-link'),
      chromeSize: $('#visual-chrome-size'), nativaxSize: $('#visual-nativax-size'),
      diffSize: $('#visual-diff-size'),
    };
    const clear = () => {
      ['chrome', 'nativax', 'diff'].forEach((k) => {
        if (imgs[k]) imgs[k].removeAttribute('src');
        if (imgs[k + 'Link']) imgs[k + 'Link'].removeAttribute('href');
        if (imgs[k + 'Size']) imgs[k + 'Size'].textContent = '';
      });
      $('#visual-metrics').innerHTML = '';
    };
    if (!row || !sel) { if (sel) sel.innerHTML = '<option value="">Sin comparación</option>'; clear(); return; }
    sel.innerHTML = row.results.map((r, i) => {
      const pct = r.metrics ? ` · ${r.metrics.changed_percent}%` : '';
      return `<option value="${i}">${r.width}x${r.height} · ${r.status}${pct}</option>`;
    }).join('');
    showVisualResult(0);
  }

  function showVisualResult(index) {
    const cid = $('#visual-case') ? $('#visual-case').value : '';
    const row = (VISUAL.cases || {})[cid];
    if (!row) return;
    const r = row.results[Number(index)] || row.results[0];
    if (!r) return;
    const m = r.metrics || {};
    const chrome = r.chrome || {};
    const nativax = r.nativax || {};
    const setImg = (id, link, src, sizeEl, w, h) => {
      const img = $(id);
      if (!img) return;
      if (src) {
        img.src = src;
        if (link) link.href = src;
        if (sizeEl) sizeEl.textContent = `${w}×${h}`;
      } else {
        img.removeAttribute('src');
        if (link) link.removeAttribute('href');
        if (sizeEl) sizeEl.textContent = '';
      }
    };
    setImg('#visual-chrome', '#visual-chrome-link', chrome.url,
      '#visual-chrome-size', r.width, r.height);
    setImg('#visual-nativax', '#visual-nativax-link', nativax.url,
      '#visual-nativax-size', r.width, r.height);
    setImg('#visual-diff', '#visual-diff-link', m.diff_url,
      '#visual-diff-size', m.width, m.height);

    const metrics = [
      ['Estado', r.status, r.status],
      ['% distinto', m.changed_percent == null ? '—' : m.changed_percent, ''],
      ['MAE', m.mae == null ? '—' : m.mae, ''],
      ['RMSE', m.rmse == null ? '—' : m.rmse, ''],
      ['SSIM', m.ssim == null ? '—' : m.ssim, ''],
      ['Píxeles', m.total_pixels == null ? '—' :
        `${m.changed_pixels} / ${m.total_pixels}`, ''],
    ];
    $('#visual-metrics').innerHTML = metrics.map(([l, v, k]) =>
      `<div class="metric ${k || ''}"><div class="v">${v}</div><div class="l">${l}</div></div>`).join('');
    const statusEl = $('#visual-status');
    if (statusEl) {
      const bits = [`${r.width}×${r.height}`, `Chrome ${chrome.ok === false ? 'error' : 'ok'}`,
        `NativaX ${nativax.ok ? 'ok' : 'error'}`];
      if (r.error) bits.push(r.error);
      statusEl.textContent = bits.join(' · ');
    }
  }

  async function pollVisual(btn) {
    const logEl = $('#visual-log');
    const statusEl = $('#visual-status');
    const btns = ['#btn-visual-case', '#btn-visual-section', '#btn-visual-all']
      .map((s) => $(s)).filter(Boolean);
    btns.forEach((b) => { b.disabled = true; });
    const timer = setInterval(async () => {
      if (!window.pywebview || !window.pywebview.api) return;
      const st = await window.pywebview.api.get_status();
      if (!st) return;
      if (statusEl) statusEl.textContent = st.running ? 'Comparando…' : `Finalizado (exit ${st.exit_code})`;
      if (logEl) {
        logEl.textContent = (st.log || []).join('\n');
        logEl.scrollTop = logEl.scrollHeight;
      }
      if (!st.running) {
        clearInterval(timer);
        btns.forEach((b) => { b.disabled = false; });
        await loadData();
        renderVisualKpis();
        renderVisualTable();
        fillVisualCases();
        renderVisualResult();
        await loadArtifacts();
        toast('Comparación terminada');
      }
    }, 1000);
  }

  async function startVisual(scope) {
    if (!window.pywebview || !window.pywebview.api || !window.pywebview.api.run_visual) {
      toast('La comparación con Chrome requiere la app nativa (pywebview)');
      return;
    }
    const cid = $('#visual-case').value;
    const c = cases.find((x) => x.id === cid);
    const section = c ? parseInt(String(c.sid).replace('s', ''), 10) : 1;
    const widths = $('#visual-widths').value;
    const res = await window.pywebview.api.run_visual(scope, cid, section, widths);
    if (!res || !res.started) {
      toast('No se pudo iniciar: ' + (res && res.error ? res.error : 'error'));
      return;
    }
    toast('Comparación iniciada');
    pollVisual();
  }

  function renderVisual() {
    renderVisualKpis();
    fillVisualCases();
    renderVisualTable();
    renderVisualResult();
  }

  // events
  $('#sections').addEventListener('click', (e) => {
    const el = e.target.closest('.sec');
    if (!el) return;
    state.section = state.section === el.dataset.sid ? '' : el.dataset.sid;
    $('#f-section').value = state.section;
    state.page = 0;
    renderSections(); renderTable();
  });
  $('#q').addEventListener('input', (e) => { state.q = e.target.value; state.page = 0; renderTable(); });
  $('#f-section').addEventListener('change', (e) => { state.section = e.target.value; state.page = 0; renderSections(); renderTable(); });
  $('#f-status').addEventListener('change', (e) => { state.status = e.target.value; state.page = 0; renderTable(); });
  $('#prev').addEventListener('click', () => { state.page--; renderTable(); });
  $('#next').addEventListener('click', () => { state.page++; renderTable(); });
  $('#cases tbody').addEventListener('click', (e) => {
    const tr = e.target.closest('tr[data-id]');
    if (tr) openCase(tr.dataset.id);
  });
  $('#btn-theme').addEventListener('click', () => {
    const root = document.documentElement;
    root.dataset.theme = root.dataset.theme === 'dark' ? 'light' : 'dark';
  });
  $('#cli').addEventListener('click', (e) => {
    if (e.target.tagName === 'CODE') {
      navigator.clipboard?.writeText(e.target.textContent.replace(/^\$ /, ''));
      toast('Comando copiado');
    }
  });
  const runBtn = $('#btn-run');
  if (runBtn) {
    runBtn.addEventListener('click', runTests);
    if (!window.pywebview || !window.pywebview.api) {
      runBtn.disabled = true;
      runBtn.title = 'Disponible solo en la app nativa (pywebview)';
    }
  }
  const refreshBtn = $('#btn-refresh');
  if (refreshBtn) refreshBtn.addEventListener('click', async () => {
    await loadData();
    renderStatic();
    refresh();
    await loadArtifacts();
    toast('Datos recargados');
  });
  const scopeSel = $('#run-scope');
  if (scopeSel) scopeSel.addEventListener('change', () => {
    const sec = $('#run-section');
    if (sec) sec.disabled = scopeSel.value !== 'section';
  });

  const visualCaseSel = $('#visual-case');
  if (visualCaseSel) visualCaseSel.addEventListener('change', renderVisualResult);
  const visualResultSel = $('#visual-result');
  if (visualResultSel) visualResultSel.addEventListener('change', (e) => showVisualResult(e.target.value));
  const visualCaseBtn = $('#btn-visual-case');
  if (visualCaseBtn) visualCaseBtn.addEventListener('click', () => startVisual('case'));
  const visualSectionBtn = $('#btn-visual-section');
  if (visualSectionBtn) visualSectionBtn.addEventListener('click', () => startVisual('section'));
  const visualAllBtn = $('#btn-visual-all');
  if (visualAllBtn) visualAllBtn.addEventListener('click', () => startVisual('all'));
  const visualTable = document.querySelector('#visual-cases tbody');
  if (visualTable) visualTable.addEventListener('click', (e) => {
    const tr = e.target.closest('tr[data-cid]');
    if (!tr) return;
    const sel = $('#visual-case');
    if (sel) { sel.value = tr.dataset.cid; renderVisualResult(); }
  });

  function setupTabs() {
    const tabs = document.querySelectorAll('.tab');
    const panels = document.querySelectorAll('.tab-panel');
    function show(name) {
      tabs.forEach((t) => t.classList.toggle('active', t.dataset.tab === name));
      panels.forEach((p) => p.classList.toggle('active', p.dataset.tab === name));
    }
    tabs.forEach((t) => t.addEventListener('click', () => show(t.dataset.tab)));
    show('resumen');
  }

  async function renderReports() {
    let report = null;
    if (window.pywebview && window.pywebview.api && window.pywebview.api.get_latest_report) {
      report = await window.pywebview.api.get_latest_report();
    }
    if (!report && REPORT.available) {
      report = { summary: REPORT.summary || {},
                 generated_at: REPORT.generated_at, label: REPORT.label };
    }
    const meta = $('#report-meta');
    const summary = $('#report-summary');
    const tbody = document.querySelector('#report-sections tbody');
    if (report && summary) {
      const s = report.summary || {};
      if (meta) meta.textContent = report.generated_at ? `generado ${report.generated_at}` : '';
      summary.innerHTML = `<div class="kpis" style="margin:10px 0">
        <div class="kpi"><div class="v">${s.total || 0}</div><div class="l">Total</div></div>
        <div class="kpi pass"><div class="v">${s.pass || 0}</div><div class="l">Pass</div></div>
        <div class="kpi fail"><div class="v">${s.fail || 0}</div><div class="l">Fail</div></div>
        <div class="kpi skip"><div class="v">${s.blocked || 0}</div><div class="l">Blocked</div></div>
      </div>`;
    }
    let sections = DATA.report_sections || [];
    if (window.pywebview && window.pywebview.api && window.pywebview.api.get_section_reports) {
      const live = await window.pywebview.api.get_section_reports();
      if (live && live.length) sections = live;
    }
    if (tbody) {
      tbody.innerHTML = sections.map((r) => {
        const s = r.summary || {};
        return `<tr><td>${r.label || r.file}</td><td>${s.total || 0}</td><td>${s.pass || 0}</td><td>${s.fail || 0}</td><td>${s.blocked || 0}</td><td>${s.error || 0}</td></tr>`;
      }).join('') || '<tr><td colspan="6">Sin informes</td></tr>';
    }
    let smoke = null;
    if (window.pywebview && window.pywebview.api && window.pywebview.api.get_smoke_summary) {
      smoke = await window.pywebview.api.get_smoke_summary();
    }
    if (smoke && summary) {
      summary.innerHTML += `<h3>Smoke test</h3><pre class="tree">${JSON.stringify(smoke, null, 2)}</pre>`;
    }
  }

  async function renderHistory() {
    const tbody = document.querySelector('#history-table tbody');
    const detail = $('#history-detail');
    let idx = DATA.history || [];
    if (window.pywebview && window.pywebview.api && window.pywebview.api.get_history_index) {
      const live = await window.pywebview.api.get_history_index();
      if (live && live.length) idx = live;
    }
    if (tbody) {
      tbody.innerHTML = (idx || []).map((r) => {
        const t = r.totals || {};
        return `<tr data-path="${r.path || ''}"><td>${r.run_id}</td><td>${r.timestamp || ''}</td><td>${t.total || 0}</td><td>${t.pass || 0}</td><td>${t.blocked || 0}</td></tr>`;
      }).join('') || '<tr><td colspan="5">Sin historial</td></tr>';
    }
    if (tbody && !tbody.dataset.wired) {
      tbody.dataset.wired = '1';
      tbody.addEventListener('click', async (e) => {
        const tr = e.target.closest('tr[data-path]');
        if (!tr || !detail) return;
        const path = tr.dataset.path;
        let run = (idx || []).find((r) => r.path === path) || null;
        if (window.pywebview && window.pywebview.api && window.pywebview.api.get_history_run) {
          const live = await window.pywebview.api.get_history_run(path);
          if (live) run = live;
        }
        detail.textContent = run ? JSON.stringify(run, null, 2) : 'Sin detalle disponible.';
      });
    }
  }

  function onApiReady(cb) {
    if (window.pywebview && window.pywebview.api) { cb(); return; }
    window.addEventListener('pywebviewready', cb, { once: true });
    // fallback poll
    const t = setInterval(() => {
      if (window.pywebview && window.pywebview.api) { clearInterval(t); cb(); }
    }, 200);
  }

  // init
  (async () => {
    await loadData();
    renderStatic();
    refresh();
    setupTabs();
    renderVisual();
    await renderReports();
    await renderHistory();
    await loadArtifacts();
    const sec = $('#run-section');
    if (sec) sec.disabled = true;
    const runBtn = $('#btn-run');
    onApiReady(async () => {
      if (runBtn) runBtn.disabled = false;
      await renderReports();
      await renderHistory();
    });
    // if no api after 2s, keep disabled
    setTimeout(() => {
      if (!(window.pywebview && window.pywebview.api) && runBtn) {
        runBtn.disabled = true;
        runBtn.title = 'Disponible solo en la app nativa (pywebview)';
      }
    }, 2000);
  })();
})();
