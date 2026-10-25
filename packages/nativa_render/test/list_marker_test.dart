import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_html/nativa_html.dart';
import 'package:nativa_render/nativa_render.dart';

void main() {
  testWidgets('outside list markers hang outside the content box',
      (tester) async {
    // Chrome places the marker in the ul's padding; the li content starts at
    // the ul content edge (40px). NativaX reserved 24px inside the li.
    final document = HtmlParser().parseDocument(
      '<!doctype html><html><body style="margin:0">'
      '<ul style="margin:0;padding-left:40px">'
      '<li><div id="a">first</div></li><li><div id="b">second</div></li>'
      '</ul></body></html>',
    ).value;
    final engine = StyleEngine(
      document: document,
      media: const MediaContext(width: 800, height: 600),
    );
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
    Rect rect(String id) {
      final box = elementRenderBoxes[document.getElementById(id)!]!;
      return box.localToGlobal(Offset.zero) & box.size;
    }

    expect(rect('a').left, 40);
    expect(rect('a').width, 760);
    expect(rect('b').left, 40);
    final marker = tester.getRect(find.text('• ').first);
    expect(marker.right, closeTo(40, 0.5));
  });
}
