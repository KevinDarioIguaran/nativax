import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_dom/nativa_dom.dart' as dom;
import 'package:nativa_html/nativa_html.dart';
import 'package:nativa_render/nativa_render.dart';

/// Repo file resolved by walking up, so the test works from any CWD
/// (`flutter test` runs inside packages/nativa_render).
String _repoFile(String relative) {
  var dir = Directory.current.absolute;
  while (true) {
    final candidate = File('${dir.path}/$relative');
    if (candidate.existsSync()) return candidate.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError('repo file not found: $relative');
}

void main() {
  testWidgets('animated countdown spans', (tester) async {
    const fixture =
        'debug/engines/visual_comparison/fixtures/50projects50days/animated-countdown';
    final html = File(_repoFile('$fixture/index.html')).readAsStringSync();
    final css = File(_repoFile('$fixture/style.css')).readAsStringSync().replaceAll("@import url('https://fonts.googleapis.com/css2?family=Roboto:wght@400;700&display=swap');", '');
    final parsed = HtmlParser().parseDocument(html);
    final engine = StyleEngine(document: parsed.value, media: const MediaContext(width: 800, height: 900));
    engine.authorSheets = [StyleSheet.parse(css)];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: NativaXDocumentView(document: parsed.value, styleEngine: engine, padding: const EdgeInsets.all(8)))));
    await tester.pump();
    for (final sel in ['.counter', '.nums', '.nums span.in', '.nums span', 'h4']) {
      final els = parsed.value.querySelectorAll(sel);
      for (final el in els) {
        try { print('$sel ${tester.getRect(find.byKey(ObjectKey(el)))}'); } catch (e) { print('$sel ERR $e'); }
      }
    }
  });
}
