import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_html/nativa_html.dart';
import 'package:nativa_render/nativa_render.dart';

const _media = MediaContext(width: 800, height: 600);

void main() {
  testWidgets('absolute box with a negative margin renders and shifts',
      (tester) async {
    // 50projects50days/mobile-tab-navigation: `nav { position: absolute;
    // bottom: 0; margin-top: -5px }` threw a negative-padding assertion and
    // Flutter painted its error widget over the whole phone.
    final document = HtmlParser().parseDocument(
      '<!doctype html><html><body style="margin:0">'
      '<div style="position:relative;width:200px;height:100px">'
      '<nav id="a" style="position:absolute;bottom:0;left:0;margin-top:-5px;'
      'width:100%;height:20px">a</nav>'
      '<div id="b" style="position:absolute;top:30px;left:40px;'
      'margin:-10px 0 0 -15px;width:10px;height:10px">b</div>'
      '</div></body></html>',
    ).value;
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
    expect(tester.takeException(), isNull);
    Rect rect(String id) =>
        tester.getRect(find.byKey(ObjectKey(document.getElementById(id)!)));
    // margin-top does not move a bottom-anchored box.
    expect(rect('a').top, closeTo(80, 0.5));
    expect(rect('a').height, closeTo(20, 0.5));
    // Negative margins move a top/left-anchored box.
    expect(rect('b').topLeft, const Offset(25, 20));
  });
}
