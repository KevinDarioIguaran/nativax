import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativax/nativax.dart';
import 'package:nativa_css/nativa_css.dart' show CssColor;

class _FontLoader extends NativaXResourceLoader {
  final List<String> bytes = [];
  final Map<String, String> files;

  _FontLoader({this.files = const {}});

  @override
  Future<String?> load(String url) async => files[url];

  @override
  Future<Uint8List?> loadBytes(String url) async {
    bytes.add(url);
    return Uint8List.fromList([0, 1, 0, 0]);
  }
}

Finder _richTextContaining(String value) => find.byWidgetPredicate(
  (widget) =>
      widget is Text &&
      (widget.textSpan?.toPlainText().contains(value) ?? false),
);

void main() {
  test('runtime parses CSS and executes inline scripts in order', () async {
    final runtime = await NativaXRuntime.create(
      source: '''
<!doctype html>
<html>
  <head><style>p { color: #ff0000 }</style></head>
  <body>
    <p id="x">before</p>
    <script>document.getElementById('x').textContent = 'after';</script>
  </body>
</html>
''',
    );
    expect(runtime.document.getElementById('x')!.textContent, 'after');
    expect(
      runtime.styleEngine.styleOf(runtime.document.getElementById('x')!).color,
      const CssColor(0xffff0000),
    );
    runtime.dispose();
  });

  test('loads icon fonts and only referenced families', () async {
    final loader = _FontLoader();
    final runtime = await NativaXRuntime.create(
      source: '''
<!doctype html><html><head><style>
@font-face { font-family: 'Font Awesome 6 Free'; src: url('/fa.ttf'); }
@font-face { font-family: Unused; src: url('/unused.ttf'); }
body { font-family: 'Font Awesome 6 Free', sans-serif; }
</style></head><body><p>x</p></body></html>
''',
      config: NativaXRuntimeConfig(resources: loader),
    );
    expect(loader.bytes.any((u) => u.endsWith('/fa.ttf')), isTrue);
    expect(loader.bytes.any((u) => u.endsWith('/unused.ttf')), isFalse);
    runtime.dispose();
  });

  test('resolves linked font URLs against the stylesheet', () async {
    final loader = _FontLoader(
      files: {
        '/static/css/app.css':
            "@font-face { font-family: Used; src: url('../fonts/used.ttf'); }"
            'body { font-family: Used; }',
      },
    );
    final runtime = await NativaXRuntime.create(
      source: '''
<!doctype html><html><head>
<link rel="stylesheet" href="/static/css/app.css">
</head><body><p>x</p></body></html>
''',
      documentUrl: 'http://test/',
      config: NativaXRuntimeConfig(resources: loader),
    );
    expect(
      loader.bytes.any((u) => u.endsWith('/static/fonts/used.ttf')),
      isTrue,
    );
    runtime.dispose();
  });

  test('alternate and non-preferred titled stylesheets stay disabled', () async {
    final loader = _FontLoader(
      files: {
        '/default.css': 'p { color: #010101 } .persist { width: 7px }',
        '/simple.css': 'p { color: #020202 }',
        '/other-set.css': 'p { color: #030303 }',
        '/always.css': '.persist { height: 9px }',
      },
    );
    final runtime = await NativaXRuntime.create(
      source: '''
<!doctype html><html><head>
<link href="/default.css" rel="stylesheet" title="Default">
<link href="/simple.css" rel="alternate stylesheet" title="Simple">
<link href="/other-set.css" rel="stylesheet" title="Other">
<link href="/always.css" rel="stylesheet">
<style title="Other">p { font-size: 33px }</style>
</head><body><p class="persist">x</p></body></html>
''',
      documentUrl: 'http://test/',
      config: NativaXRuntimeConfig(resources: loader),
    );
    final p = runtime.document.querySelector('p')!;
    final style = runtime.styleEngine.styleOf(p);
    expect(style.color, const CssColor(0xff010101));
    expect(style.fontSize, isNot(33));
    expect(style.height?.value, 9);
    runtime.dispose();
  });

  group('V8 default engine', () {
    final library = Platform.environment['NATIVAX_V8_LIB'];
    final skip = library != null && File(library).existsSync()
        ? false
        : 'set NATIVAX_V8_LIB to run V8 runtime tests';
    const small = NativaXRuntimeConfig(
      engine: JavaScriptEngineConfig(memoryLimitBytes: 32 * 1024 * 1024),
    );
    const exhaust =
        'const keep = []; for (;;) keep.push(new Array(1e5).fill(1));';

    test('pages run on V8 by default on desktop', () async {
      final runtime = await NativaXRuntime.create(
        source: '<p>x</p><script>globalThis.v = 1 + 1</script>',
      );
      addTearDown(runtime.dispose);
      expect(runtime.engineName, 'v8');
      expect(runtime.engine.evaluate('v'), 2);
    }, skip: skip);

    test('a startup over the V8 heap reloads the page on QuickJS', () async {
      final diagnostics = <String>[];
      final runtime = await NativaXRuntime.create(
        source: '<p id="x">ok</p><script>$exhaust</script>',
        config: NativaXRuntimeConfig(
          engine: small.engine,
          onDiagnostic: diagnostics.add,
        ),
      );
      addTearDown(runtime.dispose);
      expect(runtime.engineName, 'quickjs');
      expect(runtime.document.getElementById('x'), isNotNull);
      expect(diagnostics.any((d) => d.contains('QuickJS')), isTrue);
    }, skip: skip);

    test('an over-budget page after startup is reported once', () async {
      final runtime = await NativaXRuntime.create(
        source: '<button id="b">b</button><script>'
            'document.getElementById("b").addEventListener("click", () => { $exhaust });</script>',
        config: small,
      );
      addTearDown(runtime.dispose);
      expect(runtime.engineName, 'v8');
      var reports = 0;
      runtime.onEngineOverBudget = () => reports++;
      final button = runtime.document.getElementById('b')!;
      button.dispatchEvent(Event('click'));
      button.dispatchEvent(Event('click'));
      await Future<void>.delayed(Duration.zero);
      expect(reports, 1);
    }, skip: skip);

    test('pages with ES modules stay on QuickJS (V8 has no modules yet)',
        () async {
      final runtime = await NativaXRuntime.create(
        source: '<script type="module">globalThis.m = 1</script>',
      );
      addTearDown(runtime.dispose);
      expect(runtime.engineName, 'quickjs');
      expect(runtime.engine.evaluate('m'), 1);
    }, skip: skip);

    test('forceQuickJs keeps QuickJS on desktop', () async {
      final runtime = await NativaXRuntime.create(
        source: '<p>x</p>',
        forceQuickJs: true,
      );
      addTearDown(runtime.dispose);
      expect(runtime.engineName, 'quickjs');
    });
  });

  testWidgets('NativaXView loads and renders a document', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NativaXView(
            source: '<!doctype html><html><body><p>Hello</p></body></html>',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Hello'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('counter: JS state updates through the public view', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NativaXView(
            source: '''
<!doctype html>
<html>
  <style>button { padding: 4px 8px }</style>
  <body>
    <button id="inc">+</button>
    <span id="count">0</span>
    <script>
      let n = 0;
      document.getElementById('inc').addEventListener('click', () => {
        n += 1;
        document.getElementById('count').textContent = String(n);
      });
    </script>
  </body>
</html>
''',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_richTextContaining('0'), findsOneWidget);

    await tester.tapAt(tester.getTopLeft(find.text('+')) + const Offset(4, 6));
    await tester.pumpAndSettle();
    expect(_richTextContaining('1'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
