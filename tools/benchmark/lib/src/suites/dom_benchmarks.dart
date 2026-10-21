import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_dom/nativa_dom.dart';
import 'package:nativa_dom_bindings/nativa_dom_bindings.dart';
import 'package:nativa_html/nativa_html.dart';
import 'package:nativa_js/nativa_js.dart';

import '../model.dart';

/// DOM and style benchmarks. Setup is included in each sample on purpose, so
/// the result includes the real cost of creating/resetting the working set.
class DomBenchmarks {
  DomBenchmarks() {
    final parsed = HtmlParser().parseDocument(
      '<!doctype html><html><head><style>.hot { color: #ff0000 } '
      '.item { display: block; }</style></head><body></body></html>',
    );
    document = parsed.value;
    engine = QuickJsEngine(const JavaScriptEngineConfig(
      maxJobsPerDrain: 1000000,
      memoryLimitBytes: 256 * 1024 * 1024,
      executionBudget: Duration(seconds: 10),
    ));
    bindings = DomBindings(
      engine: engine,
      document: document,
      environment: StaticEnvironment(
        media: const MediaContext(width: 1024, height: 768),
        languages: const ['en-US'],
        platform: 'linux',
      ),
    )..install();
    styleEngine = StyleEngine(
      document: document,
      media: const MediaContext(width: 1024, height: 768),
    )..authorSheets = [
        StyleSheet.parse('.hot { color: #ff0000 } .item { display: block }'),
      ];
    _prepareStyleTree();
  }

  late final Document document;
  late final QuickJsEngine engine;
  late final DomBindings bindings;
  late final StyleEngine styleEngine;
  final List<Element> _styled = [];

  void _prepareStyleTree() {
    final body = document.body!;
    for (var i = 0; i < 500; i++) {
      final el = document.createElement('div')
        ..className = 'item'
        ..textContent = 'row $i';
      body.appendChild(el);
      _styled.add(el);
    }
    styleEngine.recompute();
  }

  List<BenchmarkCase> cases() => [
        _jsCase(
          name: 'dom.create_nodes',
          operations: 3000,
          source: '''
(() => {
  document.body.replaceChildren();
  for (let i = 0; i < 3000; i++) {
    const el = document.createElement('div');
    el.className = 'item';
    el.textContent = 'node ' + i;
    document.body.appendChild(el);
  }
  return document.body.children.length;
})()
''',
        ),
        _jsCase(
          name: 'dom.query_selectors',
          operations: 100,
          source: '''
(() => {
  document.body.replaceChildren();
  for (let i = 0; i < 1000; i++) {
    const el = document.createElement('div');
    el.className = 'item';
    el.id = 'n' + i;
    document.body.appendChild(el);
  }
  let total = 0;
  for (let i = 0; i < 100; i++) total += document.querySelectorAll('.item').length;
  return total;
})()
''',
        ),
        _jsCase(
          name: 'dom.modify',
          operations: 5000,
          source: '''
(() => {
  document.body.replaceChildren();
  const el = document.createElement('div');
  document.body.appendChild(el);
  for (let i = 0; i < 5000; i++) {
    el.setAttribute('data-i', String(i));
    el.textContent = 'value ' + i;
    el.classList.toggle('hot');
  }
  return el.getAttribute('data-i').length;
})()
''',
        ),
        _jsCase(
          name: 'dom.remove_nodes',
          operations: 3000,
          source: '''
(() => {
  document.body.replaceChildren();
  for (let i = 0; i < 3000; i++) {
    document.body.appendChild(document.createElement('div'));
  }
  let removed = 0;
  while (document.body.firstChild) {
    document.body.removeChild(document.body.firstChild);
    removed++;
  }
  return removed;
})()
''',
        ),
        _jsCase(
          name: 'dom.events',
          operations: 5000,
          source: '''
(() => {
  document.body.replaceChildren();
  const el = document.createElement('button');
  document.body.appendChild(el);
  let count = 0;
  const listener = () => { count += 1; };
  el.addEventListener('click', listener);
  for (let i = 0; i < 5000; i++) el.dispatchEvent(new Event('click'));
  el.removeEventListener('click', listener);
  return count;
})()
''',
        ),
        _jsCase(
          name: 'dom.innerHTML',
          operations: 200,
          source: '''
(() => {
  const markup = '<div class="item">a</div><div class="item">b</div>' +
    '<div class="item">c</div><div class="item">d</div>';
  let total = 0;
  for (let i = 0; i < 200; i++) {
    document.body.innerHTML = markup;
    total += document.body.children.length;
  }
  return total;
})()
''',
        ),
        BenchmarkCase(
          name: 'dom.style_recompute',
          category: 'dom',
          operations: 500,
          unit: 'elements',
          notes: 'Class mutation + StyleEngine.recompute(); excludes rendering.',
          body: () {
            for (final el in _styled) {
              el.classList.toggle('hot');
            }
            final changed = styleEngine.recompute();
            return changed.length;
          },
        ),
      ];

  BenchmarkCase _jsCase({
    required String name,
    required String source,
    required int operations,
  }) =>
      BenchmarkCase(
        name: name,
        category: 'dom',
        operations: operations,
        body: () {
          final value = engine.evaluate(source, filename: '<bench:$name>');
          if (value is num) return value;
          throw StateError('$name returned a non-numeric checksum: $value');
        },
      );

  void dispose() {
    bindings.dispose();
    engine.dispose();
  }
}
