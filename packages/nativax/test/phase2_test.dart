
import 'package:flutter_test/flutter_test.dart';
import 'package:nativax/nativax.dart';
import 'package:nativa_css/nativa_css.dart' show CssColor;

class _MapLoader extends NativaXResourceLoader {
  _MapLoader(this.files);
  final Map<String, String> files;

  @override
  Future<String?> load(String url) async => files[url];
}

void main() {
  test('promises, async/await and timers run on the Dart event loop',
      () async {
    final runtime = await NativaXRuntime.create(
      source: r'''
<div id="out">pending</div>
<script>
  async function run() {
    await new Promise((resolve) => setTimeout(resolve, 5));
    document.getElementById('out').textContent = 'async-ok';
  }
  run();
</script>
''',
    );
    final out = runtime.document.getElementById('out')!;
    expect(out.textContent, 'pending');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(out.textContent, 'async-ok');
    runtime.dispose();
  });

  test('microtasks are drained after the script entry', () async {
    final runtime = await NativaXRuntime.create(
      source: r'''
<div id="out"></div>
<script>
  const order = [];
  Promise.resolve().then(() => order.push('promise'));
  queueMicrotask(() => order.push('microtask'));
  order.push('sync');
  queueMicrotask(() => {
    document.getElementById('out').textContent = order.join(',');
  });
</script>
''',
    );
    expect(
      runtime.document.getElementById('out')!.textContent,
      'sync,promise,microtask',
    );
    runtime.dispose();
  });

  test('DOMContentLoaded and load fire after scripts', () async {
    final runtime = await NativaXRuntime.create(
      source: r'''
<body>
<script>
  document.addEventListener('DOMContentLoaded', () => {
    document.body.setAttribute('data-dom', '1');
  });
  window.addEventListener('load', () => {
    document.body.setAttribute('data-load', '1');
  });
</script>
</body>
''',
    );
    final body = runtime.document.body!;
    expect(body.getAttribute('data-dom'), '1');
    expect(body.getAttribute('data-load'), '1');
    expect(runtime.bindings.readyState, 'complete');
    runtime.dispose();
  });

  test('external stylesheets and scripts use the host loader', () async {
    final runtime = await NativaXRuntime.create(
      source: '''
<link rel="stylesheet" href="app.css">
<p id="x">before</p>
<script src="app.js"></script>
''',
      config: NativaXRuntimeConfig(
        resources: _MapLoader({
          'app.css': 'p { color: #00ff00 }',
          'app.js': "document.getElementById('x').textContent = 'external';",
        }),
      ),
    );
    final x = runtime.document.getElementById('x')!;
    expect(x.textContent, 'external');
    expect(runtime.styleEngine.styleOf(x).color, const CssColor(0xff00ff00));
    runtime.dispose();
  });

  test('a failing script does not cancel later scripts', () async {
    final errors = <Object>[];
    final runtime = await NativaXRuntime.create(
      source: r'''
<div id="x">before</div>
<script>throw new Error('boom')</script>
<script>document.getElementById('x').textContent = 'continued'</script>
''',
      config: NativaXRuntimeConfig(onScriptError: errors.add),
    );
    expect(errors, hasLength(1));
    expect(runtime.document.getElementById('x')!.textContent, 'continued');
    runtime.dispose();
  });

  test('console levels reach the host sink', () async {
    final messages = <ConsoleMessage>[];
    final runtime = await NativaXRuntime.create(
      source: r'''
<script>
  console.log('log');
  console.warn('warn');
  console.error('error');
</script>
''',
      config: NativaXRuntimeConfig(onConsole: messages.add),
    );
    expect(messages.map((m) => m.level.name), ['log', 'warn', 'error']);
    expect(messages.map((m) => m.text), ['log', 'warn', 'error']);
    runtime.dispose();
  });

  test('dispose cancels timers and repeated lifecycles do not leak', () async {
    final runtime = await NativaXRuntime.create(
      source: r'''
<div id="out">0</div>
<script>
  let n = 0;
  setInterval(() => {
    n += 1;
    document.getElementById('out').textContent = String(n);
  }, 5);
</script>
''',
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(runtime.document.getElementById('out')!.textContent, isNot('0'));
    runtime.dispose();
    expect(runtime.isDisposed, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    for (var i = 0; i < 10; i++) {
      final r = await NativaXRuntime.create(source: '<p>run $i</p>');
      expect(r.document.body!.textContent.trim(), 'run $i');
      r.dispose();
    }
  });
}
