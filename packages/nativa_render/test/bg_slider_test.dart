import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_html/nativa_html.dart';
import 'package:nativa_render/nativa_render.dart';

void main() {
  testWidgets('background slider container', (tester) async {
    final html = File('/home/k3vin/Documents/nativax/debug/engines/visual_comparison/fixtures/50projects50days/background-slider/index.html').readAsStringSync();
    final css = File('/home/k3vin/Documents/nativax/debug/engines/visual_comparison/fixtures/50projects50days/background-slider/style.css').readAsStringSync();
    final parsed = HtmlParser().parseDocument(html);
    final engine = StyleEngine(document: parsed.value, media: const MediaContext(width: 800, height: 900));
    engine.authorSheets = [StyleSheet.parse(css)];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NativaXDocumentView(document: parsed.value, styleEngine: engine, padding: const EdgeInsets.all(8)),
      ),
    ));
    await tester.pump();
    final body = parsed.value.querySelector('body')!;
    final container = parsed.value.querySelector('.slider-container')!;
    print('BODY ${tester.getRect(find.byKey(ObjectKey(body)))}');
    print('CONTAINER ${tester.getRect(find.byKey(ObjectKey(container)))}');
    print('body display ${parsed.value.querySelector('body')!.getAttribute('style')}');
    final slide = parsed.value.querySelector('.slide.active')!;
    print('SLIDE ${tester.getRect(find.byKey(ObjectKey(slide)))}');
    final before = parsed.value.querySelector('body::before');
    print('before found? ${before != null}');
  });
}
