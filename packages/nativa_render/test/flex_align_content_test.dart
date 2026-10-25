import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_html/nativa_html.dart';
import 'package:nativa_render/nativa_render.dart';

Future<List<double>> _rowTops(WidgetTester tester, String alignContent) async {
  final boxes = List.filled(8, '<div class="box"></div>').join();
  final doc = HtmlParser()
      .parseDocument('<!doctype html><html><body style="margin:0">'
          '<div class="boxes">$boxes</div></body></html>')
      .value;
  final engine = StyleEngine(
    document: doc,
    media: const MediaContext(width: 800, height: 900),
  )..authorSheets = [
      StyleSheet.parse('.boxes { display: flex; flex-wrap: wrap; '
          'width: 400px; height: 400px; $alignContent } '
          '.box { width: 100px; height: 100px; }'),
    ];
  await tester.pumpWidget(MaterialApp(
    home: NativaXDocumentView(
      document: doc,
      styleEngine: engine,
      padding: EdgeInsets.zero,
    ),
  ));
  await tester.pump();
  final els = doc.querySelectorAll('.box');
  double top(int i) => elementRenderBoxes[els[i]]!.localToGlobal(Offset.zero).dy;
  return [top(0), top(4)];
}

void main() {
  // 50projects50days/3d-boxes-background: two lines of 100px in a 400px
  // tall wrapping container. Chrome distributes the 200px of free space.
  testWidgets('align-content normal stretches the flex lines', (tester) async {
    expect(await _rowTops(tester, ''), [0, 200]);
  });

  testWidgets('align-content positions the flex lines', (tester) async {
    expect(await _rowTops(tester, 'align-content: flex-start;'), [0, 100]);
    expect(await _rowTops(tester, 'align-content: center;'), [100, 200]);
    expect(await _rowTops(tester, 'align-content: flex-end;'), [200, 300]);
    expect(await _rowTops(tester, 'align-content: space-between;'), [0, 300]);
    expect(await _rowTops(tester, 'align-content: space-around;'), [50, 250]);
    final evenly = await _rowTops(tester, 'align-content: space-evenly;');
    expect(evenly[0], closeTo(200 / 3, 1e-6));
    expect(evenly[1], closeTo(100 + 400 / 3, 1e-6));
  });
}
