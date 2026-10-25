import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_dom/nativa_dom.dart' as dom;
import 'package:nativa_html/nativa_html.dart';
import 'package:nativa_render/nativa_render.dart';

const _media = MediaContext(width: 800, height: 600);

({dom.Document document, StyleEngine engine}) _document(String html) {
  final parsed = HtmlParser().parseDocument(html);
  final engine = StyleEngine(document: parsed.value, media: _media);
  return (document: parsed.value, engine: engine);
}

Widget _app(dom.Document document, StyleEngine engine) => MaterialApp(
      home: Scaffold(
        body: NativaXDocumentView(
          document: document,
          styleEngine: engine,
          padding: const EdgeInsets.all(8),
        ),
      ),
    );

void main() {
  testWidgets('fixed centering with percentage offsets and translate',
      (tester) async {
    final ctx = _document(
      '<!doctype html><html><body>'
      '<div id="box" style="position:fixed;top:50%;left:50%;'
      'transform:translate(-50%,-50%);width:100px;height:50px;'
      'background:#00ff00">x</div></body></html>',
    );
    await tester.pumpWidget(_app(ctx.document, ctx.engine));
    await tester.pump();
    final box = ctx.document.getElementById('box')!;
    final rect = tester.getRect(find.byKey(ObjectKey(box)));
    // The percentage offsets are resolved against the viewport; the translate
    // is applied in paint and therefore does not move the layout rect.
    expect(rect.left, closeTo(400, 8));
    expect(rect.top, closeTo(300, 8));
    expect(rect.size, const Size(100, 50));
  });
}
