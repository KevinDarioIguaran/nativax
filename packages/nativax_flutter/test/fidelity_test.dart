// Geometry checks for behaviours found by comparing against Chrome with
// tools/mirror: each expectation is the value Chrome reports for the same
// markup (getBoundingClientRect), up to text metrics.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativax_css/nativax_css.dart' hide MediaQuery;
import 'package:nativax_dom/nativax_dom.dart' as dom;
import 'package:nativax_flutter/nativax_flutter.dart';
import 'package:nativax_html/nativax_html.dart';

Future<dom.Document> _render(WidgetTester tester, String body, {String css = '', double dpr = 1}) async {
  final document = HtmlParser().parseDocument('<!doctype html><html><body>$body</body></html>').value;
  final engine = StyleEngine(
    document: document,
    media: MediaContext(width: 800, height: 600, devicePixelRatio: dpr),
  );
  engine.authorSheets = [StyleSheet.parse('body { margin: 0; font: 16px/20px sans-serif } $css')];
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(size: const Size(800, 600), devicePixelRatio: dpr),
        child: NativaXDocumentView(document: document, styleEngine: engine),
      ),
    ),
  ));
  await tester.pump();
  return document;
}

dom.ElementBox _box(dom.Document d, String id) => d.layoutHost!.boxOf(d.getElementById(id)!)!;

void main() {
  testWidgets('first/last child margins collapse through a parent without padding', (tester) async {
    final d = await _render(
      tester,
      '<div id="outer"><p id="inner">x</p></div><div id="after">y</div>',
      css: 'p { margin: 20px 0 } #after { margin-top: 10px }',
    );
    final outer = _box(d, 'outer');
    final inner = _box(d, 'inner');
    expect(outer.y, 20, reason: "the child's top margin escapes the parent");
    expect(inner.y, outer.y);
    expect(outer.height, inner.height);
    expect(_box(d, 'after').y, outer.y + outer.height + 20, reason: 'max(20, 10) below');
  });

  testWidgets('padding stops parent/child margin collapsing', (tester) async {
    final d = await _render(
      tester,
      '<div id="outer" style="padding-top:1px"><p id="inner">x</p></div>',
      css: 'p { margin: 20px 0 }',
    );
    expect(_box(d, 'outer').y, 0);
    expect(_box(d, 'inner').y, 21);
  });

  testWidgets('empty boxes sit after their collapsed top margin', (tester) async {
    final d = await _render(tester, '<p id="a">a</p><p id="empty"></p><p id="b">b</p>', css: 'p { margin: 16px 0 }');
    expect(_box(d, 'empty').y, _box(d, 'b').y);
  });

  testWidgets('border widths snap to device pixels', (tester) async {
    final d = await _render(tester, '<div id="b" style="width:100px;border:1.5px solid red"></div>');
    expect(_box(d, 'b').width, 102);
    final d2 = await _render(tester, '<div id="b" style="width:100px;border:0.5px solid red"></div>', dpr: 1);
    expect(_box(d2, 'b').width, 102, reason: 'thin borders round up to one device pixel');
  });

  testWidgets('legend is shrink-to-fit and stays on one line', (tester) async {
    final d = await _render(
      tester,
      '<fieldset id="f" style="width:300px"><legend id="l">ab cd</legend>x</fieldset>',
    );
    final legend = _box(d, 'l');
    expect(legend.height, 20, reason: 'one line');
    // The test font (Ahem) is 1em per glyph: 5 × 16px plus the UA's 2px
    // inline padding on each side.
    expect(legend.width, 84);
    expect(legend.x, greaterThan(_box(d, 'f').x));
  });

  testWidgets('absolute offsets are relative to the padding box', (tester) async {
    final d = await _render(
      tester,
      '<div id="cb" style="position:relative;padding:10px;height:100px">'
      '<span id="a" style="position:absolute;left:20px;top:5px;width:10px;height:10px"></span>'
      '<span id="s" style="position:absolute;width:10px;height:10px"></span></div>',
    );
    final cb = _box(d, 'cb');
    expect(_box(d, 'a').x - cb.x, 20);
    expect(_box(d, 'a').y - cb.y, 5);
    expect(_box(d, 's').x - cb.x, 10, reason: 'auto offsets keep the static position');
  });

  testWidgets('auto grid rows stretch to min-height', (tester) async {
    final d = await _render(
      tester,
      '<div style="display:grid;grid-template-columns:1fr 1fr;min-height:70px"><span id="a">1</span><span>2</span></div>',
    );
    expect(_box(d, 'a').height, 70);
  });

  testWidgets('replaced grid items do not stretch with normal alignment', (tester) async {
    final d = await _render(
      tester,
      '<div style="display:grid;grid-template-columns:1fr 1fr">'
      '<div style="height:200px"></div><canvas id="c" width="100" height="50"></canvas></div>',
    );
    expect(_box(d, 'c').height, lessThan(200));
  });

  testWidgets('inline elements report their own line boxes', (tester) async {
    final d = await _render(tester, '<p>Hello <b id="b">world</b><span id="e"></span></p>');
    final b = _box(d, 'b');
    expect(b.x, greaterThan(0));
    expect(b.width, greaterThan(0));
    expect(b.width, lessThan(100));
    final e = _box(d, 'e');
    expect(e.width, 0);
    expect(e.x, closeTo(b.x + b.width, 0.5));
  });

  testWidgets('a final line break opens no empty line', (tester) async {
    final d = await _render(tester, '<pre id="p" style="margin:0;font:16px/20px monospace">a\nb\n</pre>');
    expect(_box(d, 'p').height, 40);
  });

  testWidgets('host text styles do not leak tracking into the page', (tester) async {
    await _render(tester, '<p>Hello</p>');
    final paragraph = tester.widget<RichText>(find.byType(RichText).first);
    expect(paragraph.text.style?.letterSpacing ?? 0, 0);
  });

  testWidgets('button contents are centred vertically', (tester) async {
    final d = await _render(tester, '<button id="b" style="min-height:60px;padding:0;border:0"><span id="t">T</span></button>');
    final b = _box(d, 'b');
    final t = _box(d, 't');
    expect(b.height, 60);
    expect(t.y - b.y, closeTo((60 - t.height) / 2, 1));
  });

  testWidgets('getBoundingClientRect includes 3D transforms and perspective', (tester) async {
    final d = await _render(
      tester,
      '<div style="perspective:300px"><div id="t" style="width:100px;height:50px;transform:rotateY(35deg)"></div></div>'
      '<div id="flat" style="width:100px;height:50px;transform:rotateY(35deg)"></div>',
    );
    final t = _box(d, 't');
    final flat = _box(d, 'flat');
    expect(t.offsetWidth, 100, reason: 'offsetWidth ignores transforms');
    expect(flat.width, closeTo(100 * 0.8192, 0.5), reason: 'rotateY without perspective is cos(35°)');
    expect(t.height, greaterThan(50), reason: 'perspective enlarges the near edge');
  });
}
