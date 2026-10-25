import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_html/nativa_html.dart';
import 'package:nativa_render/nativa_render.dart';

void main() {
  // expanding-cards, hidden-search, color-picker...: a positioned container
  // in a shrink-to-fit box asked a LayoutBuilder for its intrinsic width and
  // the page failed with an assertion (8 INVALID visual pages).
  for (final wrapper in [
    'display: inline-block',
    'display: flex; flex-direction: column; align-items: center',
    'float: left',
    'display: flex; width: 600px; --item: flex',
  ]) {
    testWidgets('positioned container inside a shrink-to-fit box ($wrapper)',
        (tester) async {
      final doc = HtmlParser()
          .parseDocument('<!doctype html><html><body style="margin:0">'
              '<div style="$wrapper"><div class="p">text'
              '<span class="a">abs</span></div></div></body></html>')
          .value;
      final engine = StyleEngine(
        document: doc,
        media: const MediaContext(width: 800, height: 600),
      )..authorSheets = [
          StyleSheet.parse('.p { position: relative; height: 50px; '
              '${wrapper.contains('--item') ? 'flex: 0.5;' : ''} } '
              '.a { position: absolute; top: 0; left: 0; width: 100%; '
              'height: 100% }'),
        ];
      await tester.pumpWidget(MaterialApp(
        home: NativaXDocumentView(
          document: doc,
          styleEngine: engine,
          padding: EdgeInsets.zero,
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final p = elementRenderBoxes[doc.querySelector('.p')!]!;
      final a = doc.querySelector('.a')!;
      expect(tester.getSize(find.byKey(ObjectKey(a))), p.size);
    });
  }
}
