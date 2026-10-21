// Mirror probe: the same code runs in Chrome (reference) and in NativaX, and
// returns the border box of every rendered element keyed by a stable path.
// Only geometry is compared; colours are checked from the screenshots.
globalThis.__mirrorMeasure = function () {
  const out = {};
  const pathOf = (el) => {
    const parts = [];
    for (let n = el; n && n.nodeType === 1; n = n.parentElement) {
      if (n.id) { parts.unshift('#' + n.id); break; }
      const tag = n.tagName.toLowerCase();
      let i = 1;
      for (let s = n.previousElementSibling; s; s = s.previousElementSibling) {
        if (s.tagName === n.tagName) i++;
      }
      parts.unshift(tag + ':' + i);
    }
    return parts.join('>');
  };
  const sx = window.scrollX || 0;
  const sy = window.scrollY || 0;
  const walk = (el) => {
    for (const c of el.children) {
      const tag = c.tagName.toLowerCase();
      if (tag === 'script' || tag === 'style' || tag === 'option') continue;
      const r = c.getBoundingClientRect();
      if (r.width > 0 || r.height > 0) {
        out[pathOf(c)] = [r.x + sx, r.y + sy, r.width, r.height].map((v) => Math.round(v * 10) / 10);
      }
      if (tag !== 'svg' && tag !== 'select') walk(c);
    }
  };
  walk(document.body);
  return JSON.stringify(out);
};
