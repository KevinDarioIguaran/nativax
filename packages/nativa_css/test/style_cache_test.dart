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
    expect(
      identical(a, b),
      isTrue,
      reason: 'siblings with the same signature must share the style',
    );
    expect(engine.styleCacheHits, greaterThan(0));
    expect(engine.selectorEvaluations, lessThan(200));
  });

  test('identical subtrees under different parents share computed styles', () {
    final (doc, engine) = _doc(
      '<!doctype html><html><body>'
          '<div class="row"><p class="v">one</p></div>'
          '<div class="row"><p class="v">two</p></div>'
          '</body></html>',
      '.row { display: flex } .v { color: #ff0000; padding: 2px }',
    );
    final ps = doc.querySelectorAll('.v');
    final a = engine.styleOf(ps[0]);
    final b = engine.styleOf(ps[1]);
    expect(
      identical(a, b),
      isTrue,
      reason: 'equal parent styles must not fragment the computed cache',
    );
  });

  // 50projects50days/expanding-cards: `.panel.active h3` matched the h3 of
  // every panel because both panels have equal styles and the cache key
  // ignored the ancestors' classes.
  test('ancestor-dependent rules do not leak through the style cache', () {
    final (doc, engine) = _doc(
      '<!doctype html><html><body><div class="c">'
          '<div class="panel active"><h3>a</h3></div>'
          '<div class="panel"><h3>b</h3></div>'
          '</div></body></html>',
      '.panel h3 { opacity: 0 } .panel.active h3 { opacity: 1 }',
    );
    final h = doc.querySelectorAll('h3');
    expect(engine.styleOf(h[0]).opacity, 1);
    expect(engine.styleOf(h[1]).opacity, 0);
  });

  test(':has() subject is invalidated by descendant changes', () {
    final (doc, engine) = _doc(
      '<!doctype html><html><body>'
          '<div class="card" id="card"><span id="child"></span></div>'
          '</body></html>',
      '.card { color: #000000 } .card:has(.active) { color: #ff0000 }',
    );
    doc.addMutationListener(engine.handleMutation);
    final card = doc.getElementById('card')!;
    final child = doc.getElementById('child')!;
    expect(engine.styleOf(card).color, CssColor.black);
    child.className = 'active';
    expect(engine.styleOf(card).color, const CssColor(0xffff0000));
    child.className = '';
    expect(engine.styleOf(card).color, CssColor.black);
  });

  test(
    'a later state change does not clear a pending structural invalidation',
    () {
      final (doc, engine) = _doc(
        '<!doctype html><html><body><div id="a"><p>x</p></div></body></html>',
        'p { color: #000000 } .open p { color: #ff0000 }',
      );
      engine.lazySubtrees = true;
      doc.addMutationListener(engine.handleMutation);
      final div = doc.getElementById('a')!;
      final p = div.querySelector('p')!;
      expect(engine.styleOf(p).color, CssColor.black);
      div.className = 'open';
      // A state notification after the class change must not erase the pending
      // "descendants may change" flag.
      doc.notifyStateChanged(div);
      engine.recompute();
      expect(engine.styleOf(p).color, const CssColor(0xffff0000));
    },
  );

  test('state changes on an unrelated ancestor keep descendants cached', () {
    final (doc, engine) = _doc(
      '<!doctype html><html><body><div id="a"><p><b>x</b></p></div></body></html>',
      'p { color: #ff0000 } b { font-weight: 700 }',
    );
    engine.lazySubtrees = true;
    doc.addMutationListener(engine.handleMutation);
    final div = doc.getElementById('a')!;
    final p = div.querySelector('p')!;
    final b = p.querySelector('b')!;
    final beforeB = engine.styleOf(b);
    final before = engine.computeCount;
    doc.notifyStateChanged(div);
    expect(engine.recompute(), isEmpty);
    expect(
      engine.computeCount - before,
      1,
      reason: 'only the state target is re-evaluated',
    );
    expect(identical(engine.styleOf(b), beforeB), isTrue);
  });

  test('attributes not read by selectors do not fragment the cache', () {
    final (doc, engine) = _doc(
      '<!doctype html><html><body>'
          '<p class="v" title="one" data-note="a">x</p>'
          '<p class="v" title="two" data-note="b">y</p>'
          '</body></html>',
      '.v { color: #ff0000 }',
    );
    final ps = doc.querySelectorAll('p');
    final a = engine.styleOf(ps[0]);
    final b = engine.styleOf(ps[1]);
    expect(identical(a, b), isTrue);
    expect(engine.styleCacheHits, greaterThan(0));
  });

  test('attributes read by a selector keep styles distinct', () {
    final (doc, engine) = _doc(
      '<!doctype html><html><body>'
          '<p class="v" title="one">x</p><p class="v" title="two">y</p>'
          '</body></html>',
      '.v { color: #ff0000 } [title=two] { color: #00ff00 }',
    );
    final ps = doc.querySelectorAll('p');
    expect(engine.styleOf(ps[0]).color, const CssColor(0xffff0000));
    expect(engine.styleOf(ps[1]).color, const CssColor(0xff00ff00));
    expect(identical(engine.styleOf(ps[0]), engine.styleOf(ps[1])), isFalse);
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
    expect(
      identical(engine.styleOf(divs[0]), engine.styleOf(divs[1])),
      isFalse,
    );
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

  test('plain text updates keep cached descendant styles', () {
    final (doc, engine) = _doc(
      '<!doctype html><html><body><div id="d"><p><b>x<span>one</span></b></p></div></body></html>',
      'p { color: #ff0000; padding: 2px } span { font-weight: 700 }',
    );
    engine.lazySubtrees = true;
    doc.addMutationListener(engine.handleMutation);
    final div = doc.getElementById('d')!;
    final p = div.querySelector('p')!;
    final b = p.querySelector('b')!;
    final span = b.querySelector('span')!;
    final beforeSpan = engine.styleOf(span);
    final before = engine.computeCount;
    (b.firstChild! as Text).data = 'two';
    final changed = engine.recompute();
    expect(changed, isEmpty);
    expect(
      engine.computeCount - before,
      1,
      reason: 'only the text parent <b> is re-evaluated',
    );
    expect(
      identical(engine.styleOf(span), beforeSpan),
      isTrue,
      reason: 'the descendant keeps its cached computed style',
    );
  });

  test('attributes no selector reads do not invalidate styles', () {
    final (doc, engine) = _doc(
      '<!doctype html><html><body><p id="p" title="a">x</p></body></html>',
      'p { color: #ff0000 }',
    );
    engine.lazySubtrees = true;
    doc.addMutationListener(engine.handleMutation);
    final p = doc.getElementById('p')!;
    engine.styleOf(p);
    final before = engine.computeCount;
    p.setAttribute('title', 'b');
    final changed = engine.recompute();
    expect(changed, isEmpty);
    expect(
      engine.computeCount - before,
      0,
      reason: 'title is not read by any selector',
    );
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

  test('pseudo rules are indexed by their subject class', () {
    final b = StringBuffer('<!doctype html><html><body>');
    for (var i = 0; i < 120; i++) {
      b.write('<div class="p$i"></div>');
    }
    b.write('</body></html>');
    final css = StringBuffer();
    for (var i = 0; i < 120; i++) {
      css.write('.p$i:before{content:"icon-$i"}');
    }
    final (doc, engine) = _doc(b.toString(), css.toString());
    final el = doc.querySelector('.p77')!;
    expect(
      engine.pseudoStyleOf(el, 'before')!.content!.resolve((_) => null),
      'icon-77',
    );
    expect(
      engine
          .pseudoStyleOf(doc.querySelector('.p78')!, 'before')!
          .content!
          .resolve((_) => null),
      'icon-78',
    );
    expect(
      engine.selectorEvaluations,
      lessThan(500),
      reason: 'pseudo matching must use the subject index, not all 120 rules',
    );
  });
}
