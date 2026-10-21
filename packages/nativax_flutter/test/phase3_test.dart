import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativax_css/nativax_css.dart';
import 'package:nativax_dom/nativax_dom.dart' as dom;
import 'package:nativax_flutter/nativax_flutter.dart';
import 'package:nativax_html/nativax_html.dart';

const _media = MediaContext(width: 800, height: 600);

({dom.Document document, StyleEngine engine}) _document(
  String html, {
  String css = '',
}) {
  final parsed = HtmlParser().parseDocument(html);
  final engine = StyleEngine(document: parsed.value, media: _media);
  if (css.isNotEmpty) engine.authorSheets = [StyleSheet.parse(css)];
  return (document: parsed.value, engine: engine);
}

Widget _app(dom.Document document, StyleEngine engine) => MaterialApp(
      home: Scaffold(
        body: NativaXDocumentView(
          document: document,
          styleEngine: engine,
          padding: const EdgeInsets.all(8),
        ),
      ),
    );

Finder _key(dom.Document document, String id) =>
    find.byKey(ObjectKey(document.getElementById(id)));

void main() {
  testWidgets('absolute positioning offsets from the containing block',
      (tester) async {
    final ctx = _document('''
<!doctype html><html><body>
  <div id="parent" style="position:relative;width:200px;height:120px">
    <div id="child" style="position:absolute;left:20px;top:10px;width:50px;height:30px"></div>
  </div>
</body></html>
''');
    await tester.pumpWidget(_app(ctx.document, ctx.engine));
    await tester.pump();

    final parent = _key(ctx.document, 'parent');
    final child = _key(ctx.document, 'child');
    expect(tester.getSize(child), const Size(50, 30));
    expect(
      tester.getTopLeft(child) - tester.getTopLeft(parent),
      const Offset(20, 10),
    );
  });

  testWidgets('relative positioning keeps flow and shifts painting',
      (tester) async {
    final ctx = _document('''
<!doctype html><html><body>
  <div id="a" style="height:20px">A</div>
  <div id="b" style="position:relative;left:10px;top:5px;height:20px">B</div>
  <div id="c" style="height:20px">C</div>
</body></html>
''');
    await tester.pumpWidget(_app(ctx.document, ctx.engine));
    await tester.pump();

    final a = tester.getTopLeft(find.text('A'));
    final b = tester.getTopLeft(find.text('B'));
    final c = tester.getTopLeft(find.text('C'));
    expect(b.dx - a.dx, 10);
    expect(b.dy - a.dy, 25);
    expect(c.dy - a.dy, 40);
  });

  testWidgets('list markers support disc and decimal start', (tester) async {
    final ctx = _document('''
<!doctype html><html><body>
  <ul><li>one</li><li>two</li></ul>
  <ol start="3"><li>three</li></ol>
</body></html>
''');
    await tester.pumpWidget(_app(ctx.document, ctx.engine));
    await tester.pump();

    expect(find.text('•'), findsNWidgets(2));
    expect(find.text('3.'), findsOneWidget);
    expect(find.text('one'), findsOneWidget);
  });

  testWidgets('labels activate their associated checkbox', (tester) async {
    final ctx = _document('''
<!doctype html><html><body>
  <label for="cb" id="label">Check me</label><input id="cb" type="checkbox">
</body></html>
''');
    await tester.pumpWidget(_app(ctx.document, ctx.engine));
    await tester.pump();
    final checkbox = ctx.document.getElementById('cb')!;
    expect(checkbox.checked, isFalse);

    await tester.tapAt(const Offset(80, 30));
    await tester.pump();
    await tester.pump();
    expect(checkbox.checked, isTrue);
  });

  testWidgets('media queries and viewport units react to resize',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);

    final ctx = _document(
      '<!doctype html><html><body><p id="p">responsive</p>'
      '<div id="box" style="width:50vw;height:10px"></div></body></html>',
      css: '''
        p { margin: 0 }
        @media (max-width: 500px) { p { color: #ff0000 } }
        @media (min-width: 501px) { p { color: #0000ff } }
      ''',
    );
    await tester.pumpWidget(_app(ctx.document, ctx.engine));
    await tester.pump();

    var text = tester.widget<Text>(find.text('responsive'));
    expect(text.style?.color, const Color(0xffff0000));
    expect(tester.getSize(_key(ctx.document, 'box')).width, 200);

    tester.view.physicalSize = const Size(700, 800);
    await tester.pump();
    await tester.pump();

    text = tester.widget<Text>(find.text('responsive'));
    expect(text.style?.color, const Color(0xff0000ff));
    expect(tester.getSize(_key(ctx.document, 'box')).width, 350);
  });

  testWidgets('typography maps weight, style, line height and transform',
      (tester) async {
    final ctx = _document(
      '<!doctype html><html><body><p id="p">Hello</p></body></html>',
      css: '''
        p {
          margin: 0;
          font-size: 18px;
          font-weight: 700;
          font-style: italic;
          line-height: 1.5;
          letter-spacing: 2px;
          text-align: center;
          text-transform: uppercase;
          text-decoration: underline;
        }
      ''',
    );
    await tester.pumpWidget(_app(ctx.document, ctx.engine));
    await tester.pump();

    final text = tester.widget<Text>(find.text('HELLO'));
    expect(text.style?.fontSize, 18);
    expect(text.style?.fontWeight, FontWeight.w700);
    expect(text.style?.fontStyle, FontStyle.italic);
    expect(text.style?.height, 1.5);
    expect(text.style?.letterSpacing, 2);
    expect(text.style?.decoration, TextDecoration.underline);
    expect(text.textAlign, TextAlign.center);
  });

  testWidgets('flex wrap starts a new line', (tester) async {
    final ctx = _document('''
<!doctype html><html><body>
  <div style="display:flex;flex-wrap:wrap;width:100px">
    <div id="a" style="width:60px;height:10px"></div>
    <div id="b" style="width:60px;height:10px"></div>
  </div>
</body></html>
''');
    await tester.pumpWidget(_app(ctx.document, ctx.engine));
    await tester.pump();

    final a = _key(ctx.document, 'a');
    final b = _key(ctx.document, 'b');
    expect(tester.getTopLeft(b).dx, tester.getTopLeft(a).dx);
    expect(tester.getTopLeft(b).dy - tester.getTopLeft(a).dy, 10);
  });

  testWidgets('images use the host resolver and CSS box', (tester) async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
      '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    final ctx = _document('''
<!doctype html><html><body>
  <img id="i" src="pixel.png" alt="pixel" style="width:20px;height:20px">
</body></html>
''');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NativaXDocumentView(
          document: ctx.document,
          styleEngine: ctx.engine,
          imageResolver: (element, src) =>
              src == 'pixel.png' ? MemoryImage(png) : null,
          padding: const EdgeInsets.all(8),
        ),
      ),
    ));
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<MemoryImage>());
    expect(tester.getSize(find.byType(Image)), const Size(20, 20));
  });

  testWidgets('overflow auto creates a scrollable box', (tester) async {
    final ctx = _document('''
<!doctype html><html><body>
  <div id="scroll" style="height:50px;overflow-y:auto">
    <div style="height:200px"></div>
  </div>
</body></html>
''');
    await tester.pumpWidget(_app(ctx.document, ctx.engine));
    await tester.pump();

    final box = _key(ctx.document, 'scroll');
    expect(find.descendant(of: box, matching: find.byType(Scrollable)),
        findsOneWidget);
  });
}
