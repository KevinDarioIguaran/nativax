import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_html/nativa_html.dart';
import 'package:nativa_render/nativa_render.dart';

const _media = MediaContext(width: 800, height: 600);

Future<Rect> _imageRect(WidgetTester tester, String html) async {
  final document = HtmlParser().parseDocument(html).value;
  final engine = StyleEngine(document: document, media: _media);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: NativaXDocumentView(
        document: document,
        styleEngine: engine,
        padding: EdgeInsets.zero,
      ),
    ),
  ));
  await tester.pump();
  final box = elementRenderBoxes[document.querySelector('img')!]!;
  return box.localToGlobal(Offset.zero) & box.size;
}

void main() {
  testWidgets('an image that cannot load keeps its CSS size', (tester) async {
    // 50projects50days/mobile-tab-navigation: blocked unsplash images kept
    // the alt text size (64x0) instead of width:100%/height:calc().
    final rect = await _imageRect(
      tester,
      '<!doctype html><html><body style="margin:0">'
      '<div style="position:relative;width:200px;height:100px">'
      '<img src="https://blocked.example/a.jpg" alt="home" style="'
      'position:absolute;top:0;left:0;width:100%;height:calc(100% - 60px)">'
      '</div></body></html>',
    );
    expect(rect.size, const Size(200, 40));
  });

  testWidgets('an in-flow image that cannot load keeps its CSS size',
      (tester) async {
    final rect = await _imageRect(
      tester,
      '<!doctype html><html><body style="margin:0">'
      '<img src="https://blocked.example/a.jpg" alt="x" '
      'style="width:120px;height:30px"></body></html>',
    );
    expect(rect.size, const Size(120, 30));
  });
}
