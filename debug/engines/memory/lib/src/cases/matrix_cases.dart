import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_dom_bindings/nativa_dom_bindings.dart';
import 'package:nativa_html/nativa_html.dart';
import 'package:nativa_js/nativa_js.dart';

import '../model.dart';

/// 30 additional lifecycle cases across JS, DOM and full runtime stacks.
/// They use the same profiles and controls as the hand-written cases; they are
/// not synthetic samples. Each case is intentionally small enough for the
/// quick profile.
List<LeakCase> matrixLeakCases() {
  final cases = <LeakCase>[];
  const jsScripts = <String, String>{
    'objects': '''
for (let i = 0; i < N; i++) {
  const o = { a: i, b: i + 1, c: 'x' + i, nested: { v: i } };
  globalThis.__sink = o.a + o.nested.v;
}
''',
    'arrays': '''
for (let i = 0; i < N; i++) {
  const a = new Array(128).fill(i);
  a.sort((x, y) => x - y);
  globalThis.__sink = a[127];
}
''',
    'maps': '''
for (let i = 0; i < N; i++) {
  const m = new Map();
  const s = new Set();
  for (let j = 0; j < 16; j++) { m.set('k' + j, i + j); s.add(j); }
  globalThis.__sink = m.get('k15') + s.size;
}
''',
    'strings': '''
for (let i = 0; i < N; i++) {
  const s = ('alpha-' + i + '-').repeat(8);
  globalThis.__sink = s.length + s.charCodeAt(i % s.length);
}
''',
    'closures': '''
for (let i = 0; i < N; i++) {
  const big = new Array(64).fill(i);
  const f = () => big[0] + big[63];
  globalThis.__sink = f();
}
''',
    'errors': '''
for (let i = 0; i < N; i++) {
  const e = new Error('failure ' + i);
  globalThis.__sink = e.message.length;
}
''',
    'typed': '''
for (let i = 0; i < N; i++) {
  const a = new Int32Array(256);
  for (let j = 0; j < a.length; j++) a[j] = i + j;
  globalThis.__sink = a[255];
}
''',
    'json': '''
for (let i = 0; i < N; i++) {
  const value = { id: i, tags: ['a', 'b', 'c'], nested: { v: i } };
  const text = JSON.stringify(value);
  globalThis.__sink = JSON.parse(text).nested.v;
}
''',
    'functions': '''
for (let i = 0; i < N; i++) {
  const fn = function named(a, b) { return a + b + i; };
  const proto = { get() { return i; } };
  const o = Object.create(proto);
  globalThis.__sink = fn(1, 2) + o.get();
}
''',
    'generators': '''
for (let i = 0; i < N; i++) {
  function* gen() { for (let j = 0; j < 16; j++) yield j + i; }
  let total = 0;
  for (const value of gen()) total += value;
  globalThis.__sink = total;
}
''',
  };
  for (final entry in jsScripts.entries) {
    cases.add(
      LeakCase(
        id: 'matrix.js.${entry.key}',
        subsystem: 'javascript',
        scenario: 'Matrix JS churn: ${entry.key}',
        expectation: 'released',
        run: (ctx) async {
          final engine = JscEngine(
            JavaScriptEngineConfig(
              memoryLimitBytes: 128 * 1024 * 1024,
              executionBudget: const Duration(seconds: 5),
            ),
          );
          try {
            await ctx.sample(
              0,
              engineBytes: engine.memoryUsed,
              activeRuntimes: 1,
            );
            for (var batch = 1; batch <= ctx.profile.batches; batch++) {
              final script = entry.value.replaceAll(
                RegExp(r'\bN\b'),
                '${ctx.profile.iterations}',
              );
              engine.evaluate('{ $script }', filename: '<matrix:${entry.key}>');
              await ctx.gc(engine);
              await ctx.sample(
                batch,
                engineBytes: engine.memoryUsed,
                activeRuntimes: 1,
              );
            }
          } finally {
            engine.dispose();
          }
        },
      ),
    );
  }

  final domScripts = <String, String>{
    'nodes': '''
for (let i = 0; i < N; i++) {
  const el = document.createElement('div');
  el.textContent = 'node ' + i;
  document.body.appendChild(el);
}
document.body.replaceChildren();
''',
    'text': '''
const el = document.createElement('p');
document.body.appendChild(el);
for (let i = 0; i < N; i++) el.textContent = 'text ' + i;
el.remove();
''',
    'attributes': '''
for (let i = 0; i < N; i++) {
  const el = document.createElement('div');
  el.setAttribute('data-i', String(i));
  el.setAttribute('class', 'item-' + (i % 8));
  document.body.appendChild(el);
}
document.body.replaceChildren();
''',
    'styles': '''
const el = document.createElement('div');
document.body.appendChild(el);
for (let i = 0; i < N; i++) {
  el.style.width = (10 + (i % 100)) + 'px';
  el.style.background = 'hsl(' + (i % 360) + ', 60%, 50%)';
}
el.remove();
''',
    'listeners': '''
for (let i = 0; i < N; i++) {
  const el = document.createElement('button');
  document.body.appendChild(el);
  const fn = () => i;
  el.addEventListener('click', fn);
  el.removeEventListener('click', fn);
  el.remove();
}
''',
    'queries': '''
for (let i = 0; i < N; i++) {
  const el = document.createElement('div');
  el.className = 'item-' + (i % 10);
  document.body.appendChild(el);
}
for (let i = 0; i < 32; i++) document.querySelectorAll('.item-' + i);
document.body.replaceChildren();
''',
    'inner_html': '''
for (let i = 0; i < N; i++) {
  document.body.innerHTML = '<div class="card"><span>item ' + i + '</span></div>';
}
document.body.replaceChildren();
''',
    'table': '''
const table = document.createElement('table');
document.body.appendChild(table);
for (let i = 0; i < N; i++) {
  const tr = document.createElement('tr');
  const td = document.createElement('td');
  td.textContent = String(i);
  tr.appendChild(td);
  table.appendChild(tr);
}
table.remove();
''',
    'fragments': '''
for (let i = 0; i < N / 20; i++) {
  const frag = document.createDocumentFragment();
  for (let j = 0; j < 8; j++) {
    const el = document.createElement('span');
    el.textContent = String(i + j);
    frag.appendChild(el);
  }
  document.body.appendChild(frag);
}
document.body.replaceChildren();
''',
    'forms': '''
const form = document.createElement('form');
document.body.appendChild(form);
for (let i = 0; i < N; i++) {
  const input = document.createElement('input');
  input.value = 'value ' + i;
  form.appendChild(input);
}
form.remove();
''',
  };
  for (final entry in domScripts.entries) {
    cases.add(
      LeakCase(
        id: 'matrix.dom.${entry.key}',
        subsystem: 'dom',
        scenario: 'Matrix DOM churn: ${entry.key}',
        expectation: 'released',
        run: (ctx) async {
          final doc = HtmlParser()
              .parseDocument('<!doctype html><html><body></body></html>')
              .value;
          final engine = JscEngine(
            JavaScriptEngineConfig(
              memoryLimitBytes: 128 * 1024 * 1024,
              executionBudget: const Duration(seconds: 5),
            ),
          );
          final bindings = DomBindings(
            engine: engine,
            document: doc,
            environment: StaticEnvironment(
              media: const MediaContext(width: 1024, height: 768),
              languages: const ['en-US'],
              platform: 'linux',
            ),
          )..install();
          try {
            await ctx.sample(
              0,
              nodes: doc.connectedNodeCount,
              listeners: bindings.liveListeners,
            );
            for (var batch = 1; batch <= ctx.profile.batches; batch++) {
              final script = entry.value.replaceAll(
                RegExp(r'\bN\b'),
                '${ctx.profile.iterations}',
              );
              engine.evaluate('{ $script }', filename: '<matrix:${entry.key}>');
              await ctx.gc(engine);
              await ctx.sample(
                batch,
                nodes: doc.connectedNodeCount,
                listeners: bindings.liveListeners,
              );
            }
          } finally {
            bindings.dispose();
            engine.dispose();
            doc.dispose();
          }
        },
      ),
    );
  }

  for (var i = 0; i < 10; i++) {
    cases.add(
      LeakCase(
        id: 'matrix.runtime.stack-${i + 1}',
        subsystem: 'runtime',
        scenario: 'Matrix runtime create/dispose stack ${i + 1}',
        expectation: 'released',
        run: (ctx) async {
          await ctx.sample(0);
          for (var batch = 1; batch <= ctx.profile.batches; batch++) {
            for (var j = 0; j <= i; j++) {
              final doc = HtmlParser()
                  .parseDocument('<!doctype html><html><body></body></html>')
                  .value;
              final engine = JscEngine();
              final bindings = DomBindings(
                engine: engine,
                document: doc,
                environment: StaticEnvironment(
                  media: const MediaContext(width: 800, height: 600),
                ),
              )..install();
              try {
                engine.evaluate('document.body.textContent = "alive";');
              } finally {
                bindings.dispose();
                engine.dispose();
                doc.dispose();
              }
            }
            await ctx.sample(batch, activeRuntimes: 0, nodes: 0, listeners: 0);
          }
        },
      ),
    );
  }
  return cases;
}
