import 'dart:io';
import 'dart:typed_data';

import 'package:nativa_js/nativa_js.dart';
import 'package:nativa_js/src/module_source.dart';
import 'package:test/test.dart';

class _Modules implements ModuleHost {
  _Modules([this.files = const {}]);
  final Map<String, String> files;
  final List<JavaScriptException> errors = [];
  final List<String> requested = [];

  @override
  String resolve(String base, String specifier) =>
      Uri.parse(base).resolve(specifier).toString();

  @override
  String? source(String url) {
    requested.add(url);
    return files[url];
  }

  @override
  void onError(JavaScriptException error) => errors.add(error);
}

void main() {
  group('module source scan', () {
    test('finds declarations, dynamic imports and import.meta', () {
      expect(ModuleSourceScan.of("import a from './a.js';").linksModules, isTrue);
      expect(ModuleSourceScan.of("import './a.js';").linksModules, isTrue);
      expect(ModuleSourceScan.of('export const x = 1;').linksModules, isTrue);
      expect(ModuleSourceScan.of("f(); import('./lazy.js')").linksModules, isTrue);
      final scan = ModuleSourceScan.of('const u = import.meta.url; import . meta;');
      expect(scan.linksModules, isFalse);
      expect(scan.importMetaRanges, hasLength(2));
      expect(
        scan.replaceImportMeta('const u = import.meta.url; import . meta;', 'M'),
        'const u = M.url; M;',
      );
    });

    test('ignores the words in strings, comments, templates and regexes', () {
      const source = r'''
        const a = "import x from 'y'"; const b = 'export default 1';
        // import z from 'w'
        /* export const q = 1; */
        const t = `export ${ "import" } ${ {a: `import.meta`}.a } done`;
        const r = /import\/export [/]/g.test(s), d = n / 2 / k;
        o.import(1); o?.export; ({ import: 1, export: 2 });
        if (x) {} /export/.test(y);
        const n = `{${a.map((e) => `${e}: ${f(e)}`).join(`, `)}}`; g(`import`);
      ''';
      final scan = ModuleSourceScan.of(source);
      expect(scan.declarations, isEmpty);
      expect(scan.importMetaRanges, isEmpty);
      final after = ModuleSourceScan.of('$source\nconst m = import.meta;');
      expect(after.importMetaRanges, hasLength(1), reason: 'scanner in sync');
    });

    test('the game bundle needs only import.meta', () {
      final bundle = File(
        '../../examples/game-player/assets/game/assets/index-BaA7Ac5X.js',
      );
      if (!bundle.existsSync()) {
        markTestSkipped('game bundle not present');
        return;
      }
      final scan = ModuleSourceScan.of(bundle.readAsStringSync());
      expect(scan.declarations, isEmpty);
      expect(scan.importMetaRanges, hasLength(2));
    });
  });

  group('evaluateModule on JavaScriptCore', () {
    late JscEngine engine;
    late _Modules host;
    setUp(() {
      engine = JscEngine();
      host = _Modules();
      engine.moduleHost = host;
    });
    tearDown(() => engine.dispose());

    test('runs a bundle with module semantics and import.meta.url', () {
      engine.evaluateModule(
        'var hidden = 1; globalThis.r = [import.meta.url, this === undefined,'
        ' (function () { return this === undefined; })()];',
        url: 'app://local/main.js',
      );
      expect(engine.evaluate('r'), ['app://local/main.js', true, true]);
      expect(engine.evaluate('typeof hidden'), 'undefined');
    });

    test('top-level await settles and late errors reach the host', () {
      engine.evaluateModule(
        'globalThis.v = await Promise.resolve(7);',
        url: 'app://local/tla.js',
      );
      expect(engine.evaluate('v'), 7);
      engine.evaluateModule(
        "await null; throw new RangeError('late');",
        url: 'app://local/bad.js',
      );
      expect(host.errors.single.name, 'RangeError');
      expect(host.errors.single.message, 'late');
    });

    test('synchronous errors are reported too', () {
      engine.evaluateModule('null.x;', url: 'app://local/sync.js');
      expect(host.errors.single.name, 'TypeError');
    });

    test('syntax errors throw', () {
      expect(
        () => engine.evaluateModule('const = 1;', url: 'app://local/s.js'),
        throwsA(isA<JavaScriptException>()),
      );
    });

    test('evaluates a module graph with relative imports and import.meta.url', () {
      final modules = _Modules({
        'app://local/lib/math.js': 'export const twice = (x) => x * 2; export default 40;',
        'app://local/lib/util.js': "import base, { twice } from './math.js'; export const answer = base + twice(1);",
      });
      engine.moduleHost = modules;
      engine.evaluateModule(
        "import { answer } from './lib/util.js'; globalThis.result = [answer, import.meta.url];",
        url: 'app://local/main.js',
      );
      expect(engine.evaluate('result'), [42, 'app://local/main.js']);
      expect(modules.requested, ['app://local/lib/util.js', 'app://local/lib/math.js']);
      expect(modules.errors, isEmpty);
    });

    test('modules are loaded once, share state and export live bindings', () {
      final modules = _Modules({
        'app://local/counter.js': 'export let n = 0; export const inc = () => ++n;',
        'app://local/a.js': "import { inc } from './counter.js'; inc();",
        'app://local/b.js': "import * as c from './counter.js'; c.inc(); globalThis.live = c.n;",
      });
      engine.moduleHost = modules;
      engine.evaluateModule(
        "import './a.js'; import './b.js'; import { n } from './counter.js'; globalThis.n = n;",
        url: 'app://local/main.js',
      );
      expect(engine.evaluate('[n, live]'), [2, 2]);
      expect(modules.requested.where((u) => u.endsWith('counter.js')), hasLength(1));
    });

    test('export forms: default, re-exports, star, renamed and destructured', () {
      final modules = _Modules({
        'app://local/m.js': '''
          export default function named() { return 'd'; }
          export function* gen() { yield 1; }
          export class K {}
          const hidden = 3, shown = 4;
          export { shown as visible, hidden as "quoted name" };
          export const { a, b: [c, d = 9] } = { a: 1, b: [2] };
          export async function later() { return 5; }
        ''',
        'app://local/re.js': "export * from './m.js'; export { default as def } from './m.js'; export * as all from './m.js';",
        'app://local/anon.js': 'export default class { v() { return 7; } }\n(function () {})();',
      });
      engine.moduleHost = modules;
      engine.evaluateModule('''
        import def, { visible, "quoted name" as q, a, c, d, gen, K, later } from './m.js';
        import * as re from './re.js';
        import Anon from './anon.js';
        globalThis.out = [def(), visible, q, a, c, d, [...gen()][0], typeof K,
          await later(), re.def(), re.visible, 'default' in re, re.all.a, new Anon().v(),
          Object.prototype.toString.call(re)];
      ''', url: 'app://local/main.js');
      expect(modules.errors, isEmpty);
      expect(engine.evaluate('out'), [
        'd', 4, 3, 1, 2, 9, 1, 'function', 5, 'd', 4, false, 1, 7, '[object Module]',
      ]);
    });

    test('cyclic imports resolve like ES module cycles', () {
      final modules = _Modules({
        'app://local/a.js': "import { b } from './b.js'; export function a() { return 'a' + b(); }",
        'app://local/b.js': "import { a } from './a.js'; export function b() { return 'b'; } export const viaA = () => a();",
      });
      engine.moduleHost = modules;
      engine.evaluateModule(
        "import { a } from './a.js'; import { viaA } from './b.js'; globalThis.r = [a(), viaA()];",
        url: 'app://local/main.js',
      );
      expect(modules.errors, isEmpty);
      expect(engine.evaluate('r'), ['ab', 'ab']);
    });

    test('a missing module or export is reported with its name', () {
      engine.evaluateModule("import './nope.js';", url: 'app://local/m.js');
      expect(host.errors.single.message, contains('nope.js'));
      final modules = _Modules({'app://local/x.js': 'export const y = 1;'});
      engine.moduleHost = modules;
      engine.evaluateModule("import { z } from './x.js';", url: 'app://local/m2.js');
      expect(modules.errors.single.name, 'SyntaxError');
      expect(modules.errors.single.message, contains("export named 'z'"));
    });

    test('dynamic import of a prefetched module resolves', () {
      engine.moduleHost = _Modules({'app://local/lazy.js': 'export const x = 5;'});
      engine.evaluateModule(
        "globalThis.p = import('./lazy.js').then((m) => { globalThis.x = m.x; });",
        url: 'app://local/m.js',
      );
      expect(engine.evaluate('x'), 5);
    });
  });

  test('native buffers move bytes between Dart and script without JSON', () {
    final engine = JscEngine();
    addTearDown(engine.dispose);
    final id = NativeBuffers.put(Uint8List.fromList([1, 2, 3, 250]));
    expect(
      engine.evaluate('Array.from(new Uint8Array(__nx.takeBuffer($id)))'),
      [1, 2, 3, 250],
    );
    expect(
      () => engine.evaluate('__nx.takeBuffer($id)'),
      throwsA(isA<JavaScriptException>()),
      reason: 'taken once',
    );
    final back = engine.evaluate(
      '__nx.putBuffer(new Uint16Array([0x0201, 0x0403]).subarray(1))',
    ) as int;
    expect(NativeBuffers.take(back), [3, 4]);
    expect(NativeBuffers.take(back), isNull);
  });

  test('SharedArrayBuffer memory is shared between runtimes', () {
    final a = JscEngine();
    final other = JscEngine();
    addTearDown(a.dispose);
    addTearDown(other.dispose);
    final id = a.evaluate(
      'globalThis.sab = new SharedArrayBuffer(16); globalThis.view = new Int32Array(sab);'
      ' view[0] = 41; __nx.shareSab(sab)',
    ) as int;
    expect(
      a.evaluate(
        '[sab instanceof SharedArrayBuffer, sab.byteLength,'
        ' Object.prototype.toString.call(sab), sab.slice(0, 4).byteLength]',
      ),
      [true, 16, '[object SharedArrayBuffer]', 4],
    );
    other.evaluate(
      'globalThis.view = new Int32Array(__nx.openSab($id)); Atomics.add(view, 0, 1);',
    );
    expect(a.evaluate('Atomics.load(view, 0)'), 42);
    // The memory outlives the creating runtime.
    a.evaluate('globalThis.sab = null; globalThis.view = null;');
    a.collectGarbage();
    expect(other.evaluate('view[0]'), 42);
    expect(
      () => other.evaluate('__nx.openSab($id)'),
      throwsA(isA<JavaScriptException>()),
      reason: 'ids open once',
    );
    expect(
      () => other.evaluate('__nx.shareSab(new ArrayBuffer(4))'),
      throwsA(isA<JavaScriptException>()),
      reason: 'only shared blocks can be shared',
    );
  });

  test('Atomics.wait throws on the UI thread unless blocking is allowed', () {
    final engine = JscEngine();
    addTearDown(engine.dispose);
    expect(
      () => engine.evaluate(
        'Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 0)',
      ),
      throwsA(isA<JavaScriptException>()),
    );
    engine.canBlock = true;
    expect(
      engine.evaluate(
        'const v = new Int32Array(new SharedArrayBuffer(8));'
        '[Atomics.wait(v, 0, 0, 0), Atomics.wait(v, 0, 1, 0), Atomics.notify(v, 0)]',
      ),
      ['timed-out', 'not-equal', 0],
    );
  });
}
