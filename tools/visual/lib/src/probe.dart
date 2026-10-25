/// JavaScript probe injected into both engines. Kept as a single source so
/// Chromium and NativaX cannot drift.
library;

const String probeSource = r'''
globalThis.__visualProbe = function () {
  var PROPS = [
    'display', 'position', 'visibility', 'opacity',
    'background-color', 'color',
    'font-family', 'font-size', 'font-weight', 'font-style',
    'line-height', 'letter-spacing', 'text-align',
    'border-top-width', 'border-right-width', 'border-bottom-width', 'border-left-width',
    'border-top-style', 'border-top-color',
    'border-top-left-radius', 'border-top-right-radius',
    'border-bottom-left-radius', 'border-bottom-right-radius',
    'box-shadow', 'text-decoration-line', 'overflow-x', 'overflow-y'
  ];
  var SKIP = { script: 1, style: 1, head: 1, title: 1, meta: 1, link: 1, noscript: 1, template: 1, option: 1 };
  var pathOf = function (el) {
    var parts = [];
    for (var n = el; n && n.nodeType === 1; n = n.parentElement) {
      if (n.id) { parts.unshift('#' + n.id); break; }
      var tag = n.tagName.toLowerCase();
      var i = 1;
      for (var s = n.previousElementSibling; s; s = s.previousElementSibling) {
        if (s.tagName === n.tagName) i++;
      }
      parts.unshift(tag + ':' + i);
    }
    return parts.join('>');
  };
  var r1 = function (v) { return Math.round(v * 10) / 10; };
  var isExternal = function (v) {
    return typeof v === 'string' && (v.indexOf('http://') === 0 || v.indexOf('https://') === 0 || v.indexOf('//') === 0);
  };
  var styles = function (el) {
    var cs = getComputedStyle(el);
    var out = {};
    for (var i = 0; i < PROPS.length; i++) {
      var v = cs.getPropertyValue(PROPS[i]);
      if (v !== null && v !== undefined && v !== '') out[PROPS[i]] = String(v).trim();
    }
    return out;
  };
  var sx = (typeof window.scrollX === 'number' ? window.scrollX : 0) || 0;
  var sy = (typeof window.scrollY === 'number' ? window.scrollY : 0) || 0;
  var elements = [];
  var external = 0;
  var walk = function (el) {
    for (var i = 0; i < el.children.length; i++) {
      var c = el.children[i];
      var tag = c.tagName.toLowerCase();
      if (isExternal(c.getAttribute && c.getAttribute('src'))) external++;
      if (isExternal(c.getAttribute && c.getAttribute('href'))) external++;
      if (SKIP[tag]) continue;
      var r = c.getBoundingClientRect();
      if (r.width > 0 || r.height > 0) {
        var item = {
          path: pathOf(c),
          tag: tag,
          rect: [r1(r.x + sx), r1(r.y + sy), r1(r.width), r1(r.height)],
          styles: styles(c)
        };
        if (c.children.length === 0) {
          var t = (c.textContent || '').replace(/\s+/g, ' ').trim();
          if (t) item.text = t.slice(0, 48);
        }
        elements.push(item);
      }
      if (tag !== 'svg' && tag !== 'select') walk(c);
    }
  };
  var de = document.documentElement;
  var body = document.body;
  if (body) walk(body);
  // A body with only text (or nothing visible) has no child element to
  // measure; report the body itself so the page stays comparable.
  if (body && elements.length === 0) {
    var br = body.getBoundingClientRect();
    elements.push({
      path: pathOf(body),
      tag: 'body',
      rect: [r1(br.x + sx), r1(br.y + sy), r1(br.width), r1(br.height)],
      styles: styles(body)
    });
  }
  return JSON.stringify({
    title: document.title || '',
    externalResources: external,
    viewport: {
      width: window.innerWidth,
      height: window.innerHeight,
      dpr: window.devicePixelRatio || 1
    },
    document: {
      width: Math.max(de ? de.scrollWidth : 0, body ? body.scrollWidth : 0),
      height: Math.max(de ? de.scrollHeight : 0, body ? body.scrollHeight : 0)
    },
    elements: elements
  });
};
''';

/// Appended to the staged reference page. The hidden `<pre>` keeps the
/// measurement out of the rendered pixels while `--dump-dom` still sees it.
String chromeHarness({String setupJs = ''}) {
  final setup = setupJs.trim().isEmpty ? '' : 'try { $setupJs } catch (e) {}';
  return '''
addEventListener('load', function () {
  setTimeout(function () {
    $setup
    setTimeout(function () {
      var p = document.createElement('pre');
      p.id = '__visual';
      p.style.display = 'none';
      p.textContent = __visualProbe();
      document.documentElement.appendChild(p);
    }, 300);
  }, 200);
});
''';
}
