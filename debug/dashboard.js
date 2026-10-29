(() => {
  const API = ''; // same origin when served by dashboard_server
  let DATA = window.DASHBOARD_DATA || {};
  let SECTIONS = DATA.sections || [];
  let REPOS = DATA.repos || [];
  let GAPS = DATA.gaps || [];
  let TREE = DATA.tree || '';
  let CLI = DATA.cli || [];
  let REPORT = DATA.report || { available: false };
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
    let list = null;
    if (window.pywebview && window.pywebview.api && window.pywebview.api.get_artifacts) {
      list = await window.pywebview.api.get_artifacts();
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

  // init
  (async () => {
    await loadData();
    renderStatic();
    refresh();
    await loadArtifacts();
    const sec = $('#run-section');
    if (sec) sec.disabled = true;
  })();
})();
