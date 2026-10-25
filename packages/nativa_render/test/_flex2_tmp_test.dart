import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_dom/nativa_dom.dart' as dom;
import 'package:nativa_html/nativa_html.dart';
import 'package:nativa_render/nativa_render.dart';

const _media = MediaContext(width: 1920, height: 1080);

({dom.Document document, StyleEngine engine}) _document(String html, {String css = ''}) {
  final parsed = HtmlParser().parseDocument(html);
  final engine = StyleEngine(document: parsed.value, media: _media);
  if (css.isNotEmpty) engine.authorSheets = [StyleSheet.parse(css)];
  return (document: parsed.value, engine: engine);
}

Widget _app(dom.Document document, StyleEngine engine) => MaterialApp(
      home: Scaffold(body: NativaXDocumentView(document: document, styleEngine: engine, padding: EdgeInsets.zero)),
    );

void main() {
  testWidgets('flex-1 grows in wrap container', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ctx = _document(
      '<!doctype html><html><body>'
      '<div style="display:flex;flex-wrap:wrap;max-width:1280px;margin:0 auto;padding:0 16px;gap:12px">'
      '<div style="flex:1 1 0%;min-width:100px;display:flex;gap:8px">'
      '<input style="width:100%;height:40px" value="x" />'
      '<button style="width:40px;height:40px">B</button>'
      '</div>'
      '</div></body></html>',
    );
    await tester.pumpWidget(_app(ctx.document, ctx.engine));
    await tester.pump();
    // find the flex-1 div
    final divs = ctx.document.getElementsByTagName('div');
    for (final d in divs) {
      final r = find.byKey(ObjectKey(d));
      if (r.evaluate().isNotEmpty) print('DIV size: ${tester.getSize(r)}');
    }
  });
}
