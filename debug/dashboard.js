(() => {
  const DATA = window.DASHBOARD_DATA || {};
  const SECTIONS = DATA.sections || [];
  const REPOS = DATA.repos || [];
  const GAPS = DATA.gaps || [];
  const TREE = DATA.tree || '';
  const CLI = DATA.cli || [];
  const REPORT = DATA.report || { available: false };

  const cases = DATA.cases || [];

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
          <i class="s" style="width:${pct(c.skip || 0) + pct(c.blocked || 0)}%"></i>
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

  function refresh() { renderKpis(); renderSections(); renderTable(); }

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

  renderStatic();
  refresh();
})();
