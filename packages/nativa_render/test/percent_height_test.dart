import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_html/nativa_html.dart';
import 'package:nativa_render/nativa_render.dart';

void main() {
  // 50projects50days/split-landing-page: `.container { height: 100% }` in a
  // `body { height: 100vh }` measured its content (16px) and painted nothing.
  for (final body in ['height: 100vh', 'height: 900px']) {
    testWidgets('height:100% resolves against a definite parent ($body)',
        (tester) async {
      final doc = HtmlParser()
          .parseDocument('<!doctype html><html><body>'
              '<div class="c"><div class="half">x</div></div></body></html>')
          .value;
      final engine = StyleEngine(
        document: doc,
        media: const MediaContext(width: 800, height: 900),
      )..authorSheets = [
          StyleSheet.parse('body { margin: 0; $body } '
              '.c { height: 100%; } .half { height: 50%; }'),
        ];
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: NativaXDocumentView(
          document: doc,
          styleEngine: engine,
          padding: EdgeInsets.zero,
        ),
      ));
      await tester.pump();
      expect(elementRenderBoxes[doc.querySelector('.c')!]!.size.height, 900);
      expect(elementRenderBoxes[doc.querySelector('.half')!]!.size.height, 450);
    });
  }

  testWidgets('absolute children resolve % against a %-height container',
      (tester) async {
    final doc = HtmlParser()
        .parseDocument('<!doctype html><html><body><div class="c">'
            '<div class="split"></div></div></body></html>')
        .value;
    final engine = StyleEngine(
      document: doc,
      media: const MediaContext(width: 800, height: 900),
    )..authorSheets = [
        StyleSheet.parse('body { margin: 0; height: 100vh } '
            '.c { position: relative; height: 100%; } '
            '.split { position: absolute; width: 50%; height: 100%; }'),
      ];
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: NativaXDocumentView(
        document: doc,
        styleEngine: engine,
        padding: EdgeInsets.zero,
      ),
    ));
    await tester.pump();
    final split = doc.querySelector('.split')!;
    expect(tester.getSize(find.byKey(ObjectKey(split))), const Size(400, 900));
  });
}
