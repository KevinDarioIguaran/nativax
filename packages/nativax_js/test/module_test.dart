import 'dart:typed_data';

import 'package:nativax_js/nativax_js.dart';
import 'package:test/test.dart';

class _Modules implements ModuleHost {
  _Modules(this.files);
  final Map<String, String> files;
  final List<JavaScriptException> errors = [];
  final List<String> requested = [];

  @override
  String resolve(String base, String specifier) => Uri.parse(base).resolve(specifier).toString();

  @override
  String? source(String url) {
    requested.add(url);
    return files[url];
  }

  @override
  void onError(JavaScriptException error) => errors.add(error);
}

void main() {
  late QuickJsEngine engine;
  setUp(() => engine = QuickJsEngine());
  tearDown(() => engine.dispose());

  test('evaluates a module graph with relative imports and import.meta.url', () {
    final host = _Modules({
      'app://local/lib/math.js': 'export const twice = (x) => x * 2; export default 40;',
      'app://local/lib/util.js': "import base, { twice } from './math.js'; export const answer = base + twice(1);",
    });
    engine.moduleHost = host;
    engine.evaluateModule(
      "import { answer } from './lib/util.js'; globalThis.result = [answer, import.meta.url];",
      url: 'app://local/main.js',
    );
    expect(engine.evaluate('result'), [42, 'app://local/main.js']);
    expect(host.requested, ['app://local/lib/util.js', 'app://local/lib/math.js']);
  });

  test('modules are loaded once and share state', () {
    final host = _Modules({
      'app://local/counter.js': 'export let n = 0; export const inc = () => ++n;',
      'app://local/a.js': "import { inc } from './counter.js'; inc();",
      'app://local/b.js': "import { inc } from './counter.js'; inc();",
    });
    engine.moduleHost = host;
    engine.evaluateModule(
      "import './a.js'; import './b.js'; import { n } from './counter.js'; globalThis.n = n;",
      url: 'app://local/main.js',
    );
    expect(engine.evaluate('n'), 2);
    expect(host.requested.where((u) => u.endsWith('counter.js')), hasLength(1));
  });

  test('top-level await settles through microtasks and errors are reported', () {
    final host = _Modules({});
    engine.moduleHost = host;
    engine.evaluateModule('globalThis.v = await Promise.resolve(7);', url: 'app://local/tla.js');
    expect(engine.evaluate('v'), 7);
    engine.evaluateModule("await null; throw new RangeError('late');", url: 'app://local/bad.js');
    expect(host.errors.single.name, 'RangeError');
    expect(host.errors.single.message, 'late');
  });

  test('a missing import is a ReferenceError at link time', () {
    engine.moduleHost = _Modules({});
    expect(
      () => engine.evaluateModule("import './nope.js';", url: 'app://local/m.js'),
      throwsA(isA<JavaScriptException>().having((e) => e.message, 'message', contains('nope.js'))),
    );
  });

  test('syntax errors in modules throw', () {
    engine.moduleHost = _Modules({});
    expect(() => engine.evaluateModule('export const = 1;', url: 'app://local/s.js'), throwsA(isA<JavaScriptException>()));
  });

  test('dynamic import of a prefetched module resolves', () {
    engine.moduleHost = _Modules({'app://local/lazy.js': 'export const x = 5;'});
    engine.evaluateModule("globalThis.p = import('./lazy.js').then((m) => { globalThis.x = m.x; });", url: 'app://local/m.js');
    expect(engine.evaluate('x'), 5);
  });

  test('native buffers move bytes between Dart and script without JSON', () {
    final id = NativeBuffers.put(Uint8List.fromList([1, 2, 3, 250]));
    expect(engine.evaluate('Array.from(new Uint8Array(__nx.takeBuffer($id)))'), [1, 2, 3, 250]);
    expect(() => engine.evaluate('__nx.takeBuffer($id)'), throwsA(isA<JavaScriptException>()), reason: 'taken once');
    final back = engine.evaluate('__nx.putBuffer(new Uint16Array([0x0201, 0x0403]).subarray(1))') as int;
    expect(NativeBuffers.take(back), [3, 4]);
    expect(NativeBuffers.take(back), isNull);
  });

  test('SharedArrayBuffer memory is shared between runtimes and Atomics work across them', () {
    final other = QuickJsEngine();
    addTearDown(other.dispose);
    final id = engine.evaluate('globalThis.sab = new SharedArrayBuffer(16); globalThis.view = new Int32Array(sab); view[0] = 41; __nx.shareSab(sab)') as int;
    other.evaluate('globalThis.view = new Int32Array(__nx.openSab($id)); Atomics.add(view, 0, 1);');
    expect(engine.evaluate('Atomics.load(view, 0)'), 42);
    // Memory outlives the creating runtime.
    engine.evaluate('globalThis.sab = null; globalThis.view = null;');
    engine.collectGarbage();
    expect(other.evaluate('view[0]'), 42);
    expect(() => other.evaluate('__nx.openSab($id)'), throwsA(isA<JavaScriptException>()), reason: 'ids open once');
  });

  test('Atomics.wait throws on the UI thread unless blocking is allowed', () {
    expect(
      () => engine.evaluate('Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 0)'),
      throwsA(isA<JavaScriptException>()),
    );
    engine.canBlock = true;
    expect(engine.evaluate('Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 0)'), 'timed-out');
  });
}
