import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_dom/nativa_dom.dart' as dom;
import 'package:nativa_html/nativa_html.dart';
import 'package:nativa_render/nativa_render.dart';

const _media = MediaContext(width: 800, height: 600);

({dom.Document document, StyleEngine engine}) _document(String html, {String css = ''}) {
  final parsed = HtmlParser().parseDocument(html);
  final engine = StyleEngine(document: parsed.value, media: _media);
  if (css.isNotEmpty) engine.authorSheets = [StyleSheet.parse(css)];
  return (document: parsed.value, engine: engine);
}

Widget _app(dom.Document document, StyleEngine engine) => MaterialApp(
      home: Scaffold(
        body: NativaXDocumentView(document: document, styleEngine: engine, padding: EdgeInsets.zero),
      ),
    );

void main() {
  testWidgets('absolute percent centering', (tester) async {
    final ctx = _document(
      '<!doctype html><html><body><div id="parent" style="position:relative;width:200px;height:100px;background:#eee">'
      '<div id="child" style="position:absolute;top:50%;left:50%;width:40px;height:20px;background:#f00">x</div>'
      '</div></body></html>',
    );
    await tester.pumpWidget(_app(ctx.document, ctx.engine));
    await tester.pump();
    final child = ctx.document.getElementById('child')!;
    final rect = tester.getRect(find.byKey(ObjectKey(child)));
    // top-left should be at (100,50) if 50% resolved
    expect(rect.left, closeTo(108, 2));
    expect(rect.top, closeTo(58, 2));
  });
}
