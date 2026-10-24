import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_dom/nativa_dom.dart' as dom;
import 'package:nativa_render/nativa_render.dart';
import 'package:nativa_html/nativa_html.dart';

const _media = MediaContext(width: 800, height: 600);

({dom.Document document, StyleEngine engine}) _document(
  String html, {
  String css = '',
}) {
  final parsed = HtmlParser().parseDocument(html);
  final engine = StyleEngine(document: parsed.value, media: _media);
  if (css.isNotEmpty) {
    engine.authorSheets = [StyleSheet.parse(css)];
  }
  return (document: parsed.value, engine: engine);
}

Widget _app(dom.Document document, StyleEngine engine) =>
    MaterialApp(
      home: Scaffold(
        body: NativaXDocumentView(
          document: document,
          styleEngine: engine,
          padding: const EdgeInsets.all(8),
        ),
      ),
    );

void main() {
  testWidgets('renders text with computed style', (tester) async {
    final ctx = _document(
      '<!doctype html><html><body><p id="msg">Hello</p></body></html>',
      css: 'p { color: #ff0000; font-size: 20px; margin: 0 }',
    );
    await tester.pumpWidget(_app(ctx.document, ctx.engine));
    await tester.pump();

    expect(find.text('Hello'), findsOneWidget);
    final text = tester.widget<Text>(find.text('Hello'));
    expect(text.style?.color, const Color(0xffff0000));
    expect(text.style?.fontSize, 20);
  });

  testWidgets('applies box model to a block', (tester) async {
    final ctx = _document(
      '<!doctype html><html><body>'
      '<div id="box" style="width:100px;height:50px;padding:10px;'
      'background:#00ff00"></div></body></html>',
    );
    await tester.pumpWidget(_app(ctx.document, ctx.engine));
    await tester.pump();

    final item = find.byKey(ObjectKey(ctx.document.getElementById('box')));
    expect(item, findsOneWidget);
    expect(tester.getSize(item), const Size(120, 70));
  });

  testWidgets('display:none blocks and closed dialogs draw no box',
      (tester) async {
    final ctx = _document(
      '<!doctype html><html><body>'
      '<section id="a" hidden>A</section>'
      '<div style="display:flex"><div id="b" hidden>B</div></div>'
      '<dialog id="c">C</dialog><dialog id="d" open>D</dialog>'
      '</body></html>',
      css: 'section, div, dialog { padding: 10px; background: #00ff00 }',
    );
    await tester.pumpWidget(_app(ctx.document, ctx.engine));
    await tester.pump();

    for (final id in ['a', 'b', 'c']) {
      expect(find.byKey(ObjectKey(ctx.document.getElementById(id))),
          findsNothing,
          reason: '#$id is display:none');
    }
    expect(find.byKey(ObjectKey(ctx.document.getElementById('d'))),
        findsOneWidget);
  });

  testWidgets('CSS transitions interpolate and fire transitionend', (tester) async {
    final ctx = _document(
      '<!doctype html><html><body><div id="b" style="width:10px;height:10px"></div></body></html>',
      css: 'div { opacity: 1; transition: opacity 100ms linear; background: #000 } div.off { opacity: 0 }',
    );
    ctx.document.addMutationListener(ctx.engine.handleMutation);
    final ended = <String>[];
    final el = ctx.document.getElementById('b')!;
    el.addEventListener('transitionend', dom.CallbackListener((e) => ended.add('${e.detail['propertyName']}')));
    await tester.pumpWidget(_app(ctx.document, ctx.engine));
    double opacity() => tester.widget<Opacity>(find.descendant(of: find.byKey(ObjectKey(el)), matching: find.byType(Opacity))).opacity;
    el.classList.add(['off']);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(opacity(), closeTo(0.5, 0.1));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();
    expect(find.descendant(of: find.byKey(ObjectKey(el)), matching: find.byType(Opacity)), findsOneWidget);
    expect(opacity(), 0);
    expect(ended, ['opacity']);
  });

  testWidgets('@keyframes animations run and end', (tester) async {
    final ctx = _document(
      '<!doctype html><html><body><p id="p">x</p></body></html>',
      css: '@keyframes fade { from { opacity: 0 } to { opacity: 1 } } p { animation: fade 100ms linear }',
    );
    final events = <String>[];
    final el = ctx.document.getElementById('p')!;
    for (final t in ['animationstart', 'animationend']) {
      el.addEventListener(t, dom.CallbackListener((e) => events.add(e.type)));
    }
    await tester.pumpWidget(_app(ctx.document, ctx.engine));
    await tester.pump(const Duration(milliseconds: 50));
    final o = tester.widget<Opacity>(find.descendant(of: find.byKey(ObjectKey(el)), matching: find.byType(Opacity)));
    expect(o.opacity, closeTo(0.5, 0.15));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump();
    expect(find.descendant(of: find.byKey(ObjectKey(el)), matching: find.byType(Opacity)), findsNothing);
    expect(events, ['animationstart', 'animationend']);
  });

  testWidgets('inline SVG paints shapes and routes clicks to them', (tester) async {
    final ctx = _document(
      '<!doctype html><html><body><svg id="s" viewBox="0 0 200 100" style="display:block;width:200px">'
      '<rect width="200" height="100" fill="#eee"/><circle id="c" cx="50" cy="50" r="28" fill="red"/>'
      '<path id="p" d="M105 22h56v56h-56z" class="sq"/></svg></body></html>',
      css: '.sq { fill: blue }',
    );
    final clicks = <String>[];
    for (final id in ['c', 'p', 's']) {
      ctx.document.getElementById(id)!.addEventListener('click', dom.CallbackListener((e) => clicks.add('$id:${(e.target as dom.Element).id}')));
    }
    await tester.pumpWidget(_app(ctx.document, ctx.engine));
    await tester.pump();
    final svg = find.byKey(ObjectKey(ctx.document.getElementById('s')));
    expect(tester.getSize(svg), const Size(200, 100));
    final origin = tester.getTopLeft(svg);
    await tester.tapAt(origin + const Offset(50, 50));
    await tester.tapAt(origin + const Offset(130, 50));
    expect(clicks, ['c:c', 's:c', 'p:p', 's:p']);
    expect(ctx.engine.styleOf(ctx.document.getElementById('p')!).fillColor, const CssColor(0xff0000ff));
    expect(ctx.engine.styleOf(ctx.document.getElementById('c')!).fillColor, const CssColor(0xffff0000));
  });

  testWidgets('position: sticky stays in the viewport within its container', (tester) async {
    final ctx = _document(
      '<!doctype html><html><body style="margin:0"><div id="pre" style="height:100px"></div>'
      '<nav id="n" style="position:sticky;top:0;height:40px;z-index:2;background:#00f"></nav>'
      '<div style="height:2000px;background:#eee"></div></body></html>',
    );
    var navTaps = 0;
    ctx.document.getElementById('n')!.addEventListener('click', dom.CallbackListener((_) => navTaps++));
    await tester.pumpWidget(_app(ctx.document, ctx.engine));
    await tester.pump();
    final view = find.byType(NativaXDocumentView);
    final viewTop = tester.getTopLeft(view).dy;
    final nav = find.byKey(ObjectKey(ctx.document.getElementById('n')));
    expect(tester.getTopLeft(nav).dy - viewTop, closeTo(108, 0.5)); // 8px padding + 100px
    await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -300));
    await tester.pump();
    // The layout position scrolled away; the painted/hit-tested box did not.
    await tester.tapAt(Offset(tester.getCenter(view).dx, viewTop + 20));
    expect(navTaps, 1);
  });

  testWidgets('flex row distributes free space with gap', (tester) async {
    final ctx = _document(
      '<!doctype html><html><body>'
      '<div style="display:flex;width:300px;gap:10px">'
      '<div id="a" style="flex:1;height:20px"></div>'
      '<div id="b" style="flex:2;height:20px"></div>'
      '</div></body></html>',
    );
    await tester.pumpWidget(_app(ctx.document, ctx.engine));
    await tester.pump();

    final a = find.byKey(ObjectKey(ctx.document.getElementById('a')));
    final b = find.byKey(ObjectKey(ctx.document.getElementById('b')));
    expect(tester.getSize(a).width, closeTo(290 * 1 / 3, 0.5));
    expect(tester.getSize(b).width, closeTo(290 * 2 / 3, 0.5));
    expect(
      tester.getTopLeft(b).dx - tester.getTopRight(a).dx,
      closeTo(10, 0.5),
    );
  });

  testWidgets('taps reach DOM listeners', (tester) async {
    final ctx = _document(
      '<!doctype html><html><body><button id="b">Go</button></body></html>',
    );
    var clicks = 0;
    ctx.document.getElementById('b')!.addEventListener(
          'click',
          dom.CallbackListener((_) => clicks++),
        );
    await tester.pumpWidget(_app(ctx.document, ctx.engine));
    await tester.pump();

    await tester.tapAt(tester.getTopLeft(find.text('Go')) + const Offset(4, 8));
    await tester.pump();
    expect(clicks, 1);
  });

  testWidgets('mutations rebuild text and styles', (tester) async {
    final ctx = _document(
      '<!doctype html><html><body><p id="msg">Hello</p></body></html>',
      css: 'p { margin: 0 } .hot { color: #0000ff }',
    );
    await tester.pumpWidget(_app(ctx.document, ctx.engine));
    await tester.pump();
    expect(find.text('Hello'), findsOneWidget);

    final p = ctx.document.getElementById('msg')!;
    p.firstChild!.textContent = 'Changed';
    await tester.pump();
    await tester.pump();
    expect(find.text('Changed'), findsOneWidget);

    p.classList.add(['hot']);
    await tester.pump();
    await tester.pump();
    final text = tester.widget<Text>(find.text('Changed'));
    expect(text.style?.color, const Color(0xff0000ff));
  });

  testWidgets('text input updates value and fires input', (tester) async {
    final ctx = _document(
      '<!doctype html><html><body><input id="name" value="a"></body></html>',
    );
    final input = ctx.document.getElementById('name')!;
    var inputs = 0;
    input.addEventListener('input', dom.CallbackListener((_) => inputs++));
    await tester.pumpWidget(_app(ctx.document, ctx.engine));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump();
    expect(input.value, 'abc');
    expect(inputs, 1);
  });
  testWidgets('text mutation rebuilds only the affected subtree', (tester) async {
    final html = StringBuffer('<!doctype html><html><body>');
    for (var i = 0; i < 80; i++) {
      html.write('<div id="r$i" style="height:10px"><p>row $i</p></div>');
    }
    html.write('</body></html>');
    final ctx = _document(html.toString(), css: 'p { margin: 0 } div { margin: 0 }');
    await tester.pumpWidget(_app(ctx.document, ctx.engine));
    await tester.pump();
    NativeXBuildStats.reset();
    final text = ctx.document.getElementById('r40')!.querySelector('p')!.firstChild! as dom.Text;
    text.data = 'changed';
    await tester.pump();
    await tester.pump();
    expect(NativeXBuildStats.elementBuilds, lessThan(20),
        reason: 'only the changed text path should build');
    expect(find.text('changed'), findsOneWidget);
  });

}
