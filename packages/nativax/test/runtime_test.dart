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
body { font-family: Inter, sans-serif; }
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
