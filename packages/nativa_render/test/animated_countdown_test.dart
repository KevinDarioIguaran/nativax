import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_html/nativa_html.dart';
import 'package:nativa_render/nativa_render.dart';

void main() {
  testWidgets('animated countdown center', (tester) async {
    final html = File('/home/k3vin/Documents/nativax/tools/visual/fixtures/50projects50days/animated-countdown/index.html').readAsStringSync();
    final css = File('/home/k3vin/Documents/nativax/tools/visual/fixtures/50projects50days/animated-countdown/style.css').readAsStringSync().replaceAll("@import url('https://fonts.googleapis.com/css2?family=Roboto:wght@400;700&display=swap');", '');
    final parsed = HtmlParser().parseDocument(html);
    final engine = StyleEngine(document: parsed.value, media: const MediaContext(width: 800, height: 900));
    engine.authorSheets = [StyleSheet.parse(css)];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: NativaXDocumentView(document: parsed.value, styleEngine: engine, padding: const EdgeInsets.all(8))),
    ));
    await tester.pump();
    for (final sel in ['.counter', '.nums', '.nums span.in', 'h4']) {
      final el = parsed.value.querySelector(sel);
      if (el != null) print('$sel ${tester.getRect(find.byKey(ObjectKey(el)))}');
    }
  });
}
