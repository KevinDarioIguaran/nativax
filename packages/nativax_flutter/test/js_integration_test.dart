import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativax_css/nativax_css.dart';
import 'package:nativax_dom_bindings/nativax_dom_bindings.dart';
import 'package:nativax_flutter/nativax_flutter.dart';
import 'package:nativax_html/nativax_html.dart';
import 'package:nativax_js/nativax_js.dart';

void main() {
  testWidgets('a JS listener can mutate the DOM and update Flutter',
      (tester) async {
    final parsed = HtmlParser().parseDocument(
      '<!doctype html><html><body>'
      '<button id="b">Go</button><p id="out">idle</p>'
      '</body></html>',
    );
    final document = parsed.value;
    final engine = QuickJsEngine();
    final bindings = DomBindings(
      engine: engine,
      document: document,
      environment: StaticEnvironment(
        media: const MediaContext(width: 800, height: 600),
        languages: const ['en-US'],
        platform: 'linux',
      ),
    )..install();
    engine.evaluate('''
      document.getElementById('b').addEventListener('click', () => {
        document.getElementById('out').textContent = 'clicked';
      });
    ''');
    final styleEngine = StyleEngine(
      document: document,
      media: const MediaContext(width: 800, height: 600),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NativaXDocumentView(
          document: document,
          styleEngine: styleEngine,
          padding: const EdgeInsets.all(8),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('idle'), findsOneWidget);

    await tester.tapAt(tester.getTopLeft(find.text('Go')) + const Offset(4, 8));
    await tester.pump();
    await tester.pump();
    expect(find.text('clicked'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    bindings.dispose();
    engine.dispose();
    document.dispose();
  });
}
