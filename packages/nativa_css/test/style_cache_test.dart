import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_dom/nativa_dom.dart';
import 'package:nativa_html/nativa_html.dart';
import 'package:test/test.dart';

const _media = MediaContext(width: 800, height: 600);

(Document, StyleEngine) _doc(String html, String css) {
  final document = HtmlParser().parseDocument(html).value;
  final engine = StyleEngine(document: document, media: _media)
    ..authorSheets = [StyleSheet.parse(css)];
  return (document, engine);
}

void main() {
  test('identical siblings share computed style and matched declarations', () {
    final (doc, engine) = _doc(
      '<!doctype html><html><body>'
      '<div class="card"><p>one</p></div>'
      '<div class="card"><p>two</p></div>'
      '</body></html>',
      '.card { color: #ff0000; padding: 4px } .card p { margin: 0 }',
    );
    final cards = doc.querySelectorAll('.card');
    final a = engine.styleOf(cards[0]);
    final b = engine.styleOf(cards[1]);
    expect(identical(a, b), isTrue,
        reason: 'siblings with the same signature must share the style');
    expect(engine.styleCacheHits, greaterThan(0));
    expect(engine.selectorEvaluations, lessThan(200));
  });

  test('different classes or attributes do not share', () {
    final (doc, engine) = _doc(
      '<!doctype html><html><body>'
      '<div class="a" data-x="1"></div><div class="b" data-x="2"></div>'
      '</body></html>',
      '.a { color: #ff0000 } .b { color: #00ff00 } [data-x] { padding: 2px }',
    );
    final divs = doc.querySelectorAll('div');
    expect(engine.styleOf(divs[0]).color, const CssColor(0xffff0000));
    expect(engine.styleOf(divs[1]).color, const CssColor(0xff00ff00));
    expect(identical(engine.styleOf(divs[0]), engine.styleOf(divs[1])), isFalse);
  });

  test('attribute invalidation drops cached matched styles', () {
    final (doc, engine) = _doc(
      '<!doctype html><html><body><p id="p">x</p></body></html>',
      'p { color: #000000 } p.on { color: #ff0000 }',
    );
    doc.addMutationListener(engine.handleMutation);
    final p = doc.getElementById('p')!;
    expect(engine.styleOf(p).color, CssColor.black);
    p.className = 'on';
    engine.recompute();
    expect(engine.styleOf(p).color, const CssColor(0xffff0000));
  });

  test('formatting changes do not reuse an old computed style', () {
    final (doc, engine) = _doc(
      '<!doctype html><html><body><p id="p">x</p></body></html>',
      'p { color: #000000; font-size: 10px }',
    );
    doc.addMutationListener(engine.handleMutation);
    final p = doc.getElementById('p')!;
    expect(engine.styleOf(p).fontSize, 10);
    p.setAttribute('style', 'font-size: 30px');
    engine.recompute();
    expect(engine.styleOf(p).fontSize, 30);
  });

  test('structural selectors are not shared across positions', () {
    final (doc, engine) = _doc(
      '<!doctype html><html><body><ul><li>1</li><li>2</li></ul></body></html>',
      'li:first-child { color: #ff0000 } li:last-child { color: #0000ff }',
    );
    final li = doc.querySelectorAll('li');
    expect(engine.styleOf(li[0]).color, const CssColor(0xffff0000));
    expect(engine.styleOf(li[1]).color, const CssColor(0xff0000ff));
    expect(identical(engine.styleOf(li[0]), engine.styleOf(li[1])), isFalse);
  });
}
