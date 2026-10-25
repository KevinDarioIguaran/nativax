import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_html/nativa_html.dart';
import 'package:nativa_render/nativa_render.dart';

const _media = MediaContext(width: 800, height: 600);

void main() {
  testWidgets('aspect-ratio on div', (tester) async {
    final parsed = HtmlParser().parseDocument('<!doctype html><html><body><div id="box" style="width:200px;aspect-ratio:16/9;background:#f00"></div></body></html>');
    final engine = StyleEngine(document: parsed.value, media: _media);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: NativaXDocumentView(document: parsed.value, styleEngine: engine, padding: const EdgeInsets.all(8)))));
    await tester.pump();
    final box = parsed.value.getElementById('box')!;
    print('ASPECT ${tester.getRect(find.byKey(ObjectKey(box)))}');
  });
}
