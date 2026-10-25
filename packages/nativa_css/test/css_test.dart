import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_dom/nativa_dom.dart';
import 'package:nativa_html/nativa_html.dart';
import 'package:test/test.dart';

const desktop = MediaContext(width: 1024, height: 768);

(Document, StyleEngine) styled(String html, String css, {MediaContext media = desktop}) {
  final doc = HtmlParser().parseDocument(html).value;
  final engine = StyleEngine(document: doc, media: media)
    ..authorSheets = [StyleSheet.parse(css)];
  return (doc, engine);
}

ComputedStyle styleOf((Document, StyleEngine) s, String selector) =>
    s.$2.styleOf(s.$1.querySelector(selector)!);

void main() {
  group('tokenizer', () {
    test('tokens', () {
      final ts = CssTokenizer('a.b #c{w:1.5em 50% -2px url(x.png) "s\\"q"}/*c*/')
          .tokenize()
          .where((t) => t.type != CssTokenType.whitespace)
          .map((t) => '${t.type.name}:$t')
          .toList();
      expect(ts, [
        'ident:a', 'delim:.', 'ident:b', 'hash:#c', 'leftBrace:{', 'ident:w',
        'colon::', 'dimension:1.5em', 'percentage:50%', 'dimension:-2px',
        'url:url(x.png)', 'string:"s"q"', 'rightBrace:}',
      ]);
    });

    test('escapes and scientific numbers', () {
      final ts = CssTokenizer(r'\31 a 1e3 .5').tokenize()
          .where((t) => t.type != CssTokenType.whitespace).toList();
      expect(ts[0].value, '1a');
      expect(ts[1].number, 1000);
      expect(ts[2].number, 0.5);
    });
  });

  group('parser', () {
    test('rules, grouped selectors, declarations', () {
      final sheet = StyleSheet.parse('h1, .t { color: red; margin: 0 auto }');
      final rule = sheet.rules.single as StyleRule;
      expect(rule.selectors.selectors.length, 2);
      expect(rule.declarations.map((d) => d.toString()), [
        'color: #ffff0000',
        'margin-top: 0px', 'margin-right: auto', 'margin-bottom: 0px', 'margin-left: auto',
      ]);
      expect(sheet.warnings, isEmpty);
    });

    test('@font-face records family and URL sources', () {
      final sheet = StyleSheet.parse(
        '@font-face{font-family:"Font Awesome 6 Free";font-style:normal;font-weight:900;'
        'src:url(../webfonts/fa-solid-900.woff2) format("woff2"),'
        'url(../webfonts/fa-solid-900.ttf) format("truetype")}'
        '.fa::before{content:"\\f007";font-family:"Font Awesome 6 Free"}',
      );
      expect(sheet.warnings, isEmpty);
      final face = sheet.fontFaces.single;
      expect(face.family, 'Font Awesome 6 Free');
      expect(face.weight, 900);
      expect(face.sources, [
        '../webfonts/fa-solid-900.woff2',
        '../webfonts/fa-solid-900.ttf',
      ]);
    });

    test('relative url() values resolve against the stylesheet base', () {
      final sheet = StyleSheet.parse(
        '.flag { background-image: url(../flags/4x3/co.svg) }',
        baseUrl: Uri.parse(
            'http://127.0.0.1:8000/static/vendor/flag-icons/css/flags.css'),
      );
      final rule = sheet.rules.single as StyleRule;
      final image = rule.declarations.single.value as UrlValue;
      expect(image.url,
          'http://127.0.0.1:8000/static/vendor/flag-icons/flags/4x3/co.svg');
    });

    test('invalid declarations are dropped with warnings, others kept', () {
      final sheet = StyleSheet.parse(
          'p { color: nope; width: -5px; colr: red; padding: 4px; zork: left; --x: 1; width: calc(1px) }');
      final rule = sheet.rules.single as StyleRule;
      expect(rule.declarations.map((d) => d.property), [
        'padding-top',
        'padding-right',
        'padding-bottom',
        'padding-left',
        '--x',
        'width',
      ]);
      expect(rule.declarations.last.value, isA<RawValue>());
      expect(sheet.warnings.map((w) => w.message), [
        'invalid value for "color"',
        'invalid value for "width"',
        'unsupported property "colr"',
        'unsupported property "zork"',
      ]);
    });

    test('invalid selectors drop the whole rule', () {
      final sheet = StyleSheet.parse('p::bogus { color: red } a:bogus { color: blue } b { color: green }');
      expect(sheet.rules.length, 1);
      expect(sheet.warnings.length, 2);
    });

    test('unsupported at-rules are skipped; @media is nested', () {
      final sheet = StyleSheet.parse('@import "x.css"; @font-face { font-family: x }'
          '@media (min-width: 600px) { p { color: red } } div { color: blue }');
      expect(sheet.rules.length, 2);
      expect(sheet.rules.first, isA<MediaRule>());
      expect(sheet.warnings.length, 2);
    });

    test('!important', () {
      final rule = StyleSheet.parse('p { color: red ! important; width: 1px }').rules.single as StyleRule;
      expect(rule.declarations.map((d) => d.important), [true, false]);
    });

    test('recovers from unbalanced braces', () {
      final sheet = StyleSheet.parse('} p { color: red } q { color: ');
      expect(sheet.rules.length, 2);
    });
  });

  group('values', () {
    Declaration d(String css) =>
        (StyleSheet.parse('p{$css}').rules.single as StyleRule).declarations.first;

    test('colors', () {
      expect(d('color: #abc').value, const ColorValue(CssColor(0xffaabbcc)));
      expect(d('color: #11223344').value, const ColorValue(CssColor(0x44112233)));
      expect(d('color: rgb(255, 0, 0)').value, const ColorValue(CssColor(0xffff0000)));
      expect(d('color: rgba(0, 0, 255, .5)').value, const ColorValue(CssColor(0x800000ff)));
      expect(d('color: rgb(0 128 0 / 50%)').value, const ColorValue(CssColor(0x80008000)));
      expect(d('color: hsl(120, 100%, 50%)').value, const ColorValue(CssColor(0xff00ff00)));
      expect(d('color: RebeccaPurple').value, const ColorValue(CssColor(0xff663399)));
      expect(d('color: transparent').value, const ColorValue(CssColor.transparent));
    });

    test('lengths and absolute units', () {
      expect(d('width: 10px').value, const Length.px(10));
      expect(d('width: 2.5em').value, const Length(2.5, LengthUnit.em));
      expect(d('width: 50%').value, const Length(50, LengthUnit.percent));
      expect(d('width: 12pt').value, const Length.px(16));
      expect(d('width: 1in').value, const Length.px(96));
      expect(d('width: 0').value, Length.zero);
    });

    test('shorthands', () {
      List<String> all(String css) => (StyleSheet.parse('p{$css}').rules.single as StyleRule)
          .declarations
          .map((x) => x.toString())
          .toList();
      expect(all('border: 2px dashed red'), contains('border-left-style: dashed'));
      expect(all('border-radius: 1px 2px'), [
        'border-top-left-radius: 1px', 'border-top-right-radius: 2px',
        'border-bottom-right-radius: 1px', 'border-bottom-left-radius: 2px',
      ]);
      expect(all('flex: 1'), ['flex-grow: 1.0', 'flex-shrink: 1.0', 'flex-basis: 0%']);
      expect(all('flex: 2 0 100px'), ['flex-grow: 2.0', 'flex-shrink: 0.0', 'flex-basis: 100px']);
      expect(all('flex: none'), ['flex-grow: 0.0', 'flex-shrink: 0.0', 'flex-basis: auto']);
      expect(all('gap: 4px 8px'), ['row-gap: 4px', 'column-gap: 8px']);
      expect(all('background: #fff url(a.png)'), ['background-color: #ffffffff', 'background-image: url(a.png)']);
      expect(all('text-decoration: underline red'), contains('text-decoration-line: underline'));
      expect(all('margin: inherit').first, 'margin-top: inherit');
      expect(all('font-family: "Open Sans", Arial, sans-serif'), ['font-family: Open Sans, Arial, sans-serif']);
    });
  });

  group('cascade', () {
    test('specificity beats order; order breaks ties', () {
      final s = styled('<p id=x class=c>t</p>',
          '#x { color: red } p.c { color: blue } p { color: green }'
          '.c { width: 1px } .c { width: 2px }');
      expect(styleOf(s, 'p').color, const CssColor(0xffff0000));
      expect(styleOf(s, 'p').width, const ResolvedLength.px(2));
    });

    test('inline style beats selectors; !important beats inline', () {
      final s = styled('<p id=x style="color: blue; width: 5px">t</p>',
          '#x { color: red; width: 1px !important }');
      expect(styleOf(s, 'p').color, const CssColor(0xff0000ff));
      expect(styleOf(s, 'p').width, const ResolvedLength.px(1));
    });

    test('inline !important beats author !important', () {
      final s = styled('<p style="color: blue !important">t</p>', 'p { color: red !important }');
      expect(styleOf(s, 'p').color, const CssColor(0xff0000ff));
    });

    test('author styles override user-agent defaults', () {
      final s = styled('<h1>t</h1><div>d</div><span>s</span>', 'h1 { font-size: 10px }');
      expect(styleOf(s, 'h1').fontSize, 10);
      expect(styleOf(s, 'h1').fontWeight, 700);
      expect(styleOf(s, 'div').display, Display.block);
      expect(styleOf(s, 'span').display, Display.inline);
      expect(styleOf(s, 'head').display, Display.none);
    });

    test('initial font-family is the browser default serif face', () {
      // Chrome's default standard font is Times New Roman; pages without a
      // font-family render in it, not in a sans-serif face.
      final s = styled('<p>t</p>', '');
      expect(styleOf(s, 'p').fontFamily, ['Times New Roman']);
    });

    test('later declarations in a rule win with many matched declarations',
        () {
      // Dart's sort is unstable above 32 elements and declarations of one
      // rule shared the rule order, so `border` overrode a later
      // `border-bottom-color` (50projects50days/kinetic-loader).
      final s = styled(
        '<div class="k"></div>',
        '*, *::before, *::after { animation: none !important; '
            'transition: none !important; }'
            ".k::after { content: ''; position: absolute; top: 0; left: 0; "
            'width: 0; height: 0; border: 50px solid transparent; '
            'border-bottom-color: #fff; animation: spin 2s; }',
      );
      final after = s.$2.pseudoStyleOf(s.$1.querySelector('.k')!, 'after')!;
      expect(after.borderColorOf('bottom'), const CssColor(0xffffffff));
      expect(after.borderColorOf('top'), const CssColor(0x00000000));
    });

    test('inheritance of inherited properties only', () {
      final s = styled('<div><p><span>x</span></p></div>',
          'div { color: #123456; padding: 5px; font-family: Inter; text-align: center }');
      final span = styleOf(s, 'span');
      expect(span.color, const CssColor(0xff123456));
      expect(span.fontFamily, ['Inter']);
      expect(span.textAlign, 'center');
      expect(span.paddingOf('left'), ResolvedLength.zero);
    });

    test('inherit, initial and unset', () {
      final s = styled('<div><p class=a>a</p><p class=b>b</p><p class=c>c</p></div>',
          'div { padding: 7px; color: red } .a { padding: inherit } '
          '.b { color: initial } .c { color: unset; padding: unset }');
      expect(styleOf(s, '.a').paddingOf('top'), const ResolvedLength.px(7));
      expect(styleOf(s, '.b').color, CssColor.black);
      expect(styleOf(s, '.c').color, const CssColor(0xffff0000));
      expect(styleOf(s, '.c').paddingOf('top'), ResolvedLength.zero);
    });

    test('currentcolor', () {
      final s = styled('<p>t</p>', 'p { color: lime; border: 1px solid; background-color: currentcolor }');
      final p = styleOf(s, 'p');
      expect(p.borderColorOf('top'), const CssColor(0xff00ff00));
      expect(p.backgroundColor, const CssColor(0xff00ff00));
    });
  });

  group('units', () {
    test('em, rem, %, vw, vh', () {
      final s = styled('<div><p>t</p></div>',
          'html { font-size: 20px } div { font-size: 2em } '
          'p { font-size: 50%; width: 2em; height: 3rem; margin-left: 10vw; '
          'margin-top: 10vh; padding-left: 25%; line-height: 150% }',
          media: const MediaContext(width: 400, height: 800));
      final p = styleOf(s, 'p');
      expect(styleOf(s, 'div').fontSize, 40);
      expect(p.fontSize, 20);
      expect(p.width, const ResolvedLength.px(40));
      expect(p.height, const ResolvedLength.px(60));
      expect(p.marginOf('left'), const ResolvedLength.px(40));
      expect(p.marginOf('top'), const ResolvedLength.px(80));
      expect(p.paddingOf('left'), const ResolvedLength.percent(25));
      expect(p.paddingOf('left').resolve(200), 50);
      expect(p.lineHeightMultiplier, 1.5);
    });

    test('em for font-size is relative to the parent', () {
      final s = styled('<div><span>t</span></div>', 'div { font-size: 10px } span { font-size: 1.5em; padding-top: 1em }');
      expect(styleOf(s, 'span').fontSize, 15);
      expect(styleOf(s, 'span').paddingOf('top'), const ResolvedLength.px(15));
    });

    test('bolder/lighter', () {
      final s = styled('<b><span>x</span></b>', 'span { font-weight: bolder }');
      expect(styleOf(s, 'span').fontWeight, 900);
    });
  });

  group('box model and flex values', () {
    test('margin, padding, border, radius, box-sizing', () {
      final s = styled('<div>x</div>',
          'div { margin: 1px 2px 3px; padding: 4px; border: 2px solid black; '
          'border-top-style: none; border-radius: 6px; box-sizing: border-box }');
      final d = styleOf(s, 'div');
      expect([for (final x in ['top', 'right', 'bottom', 'left']) d.marginOf(x)!.value], [1, 2, 3, 2]);
      expect(d.borderWidthOf('top'), 0);
      expect(d.borderWidthOf('left'), 2);
      expect(d.radiusOf('bottom-left'), const ResolvedLength.px(6));
      expect(d.borderBox, isTrue);
    });

    test('flex container and items; items are blockified', () {
      final s = styled('<div><span>a</span></div>',
          'div { display: flex; flex-direction: column; justify-content: space-between; '
          'align-items: center; gap: 8px; flex-wrap: wrap } span { flex: 1; align-self: flex-end }');
      final d = styleOf(s, 'div');
      final span = styleOf(s, 'span');
      expect((d.flexDirection, d.justifyContent, d.alignItems, d.flexWrap),
          ('column', 'space-between', 'center', 'wrap'));
      expect(d.rowGap, const ResolvedLength.px(8));
      expect(span.display, Display.block);
      expect((span.flexGrow, span.flexBasis), (1, const ResolvedLength.percent(0)));
      expect(span.alignSelf, 'flex-end');
    });

    test('position and z-index', () {
      final s = styled('<div><b>x</b></div>',
          'div { position: relative } b { position: absolute; top: 5px; left: 10%; z-index: 3 }');
      final b = styleOf(s, 'b');
      expect((b.position, b.top, b.left, b.zIndex),
          ('absolute', const ResolvedLength.px(5), const ResolvedLength.percent(10), 3));
      expect(b.display, Display.block);
    });
  });

  group('media queries', () {
    const css = 'p { color: black } '
        '@media (max-width: 600px) { p { color: red } } '
        '@media screen and (min-width: 601px) and (orientation: landscape) { p { color: blue } } '
        '@media (prefers-color-scheme: dark) { p { background-color: black } } '
        '@media print { p { color: green } } '
        '@media not all and (min-width: 2000px) { p { width: 1px } }';

    test('width, orientation, color scheme, not, print', () {
      final phone = styled('<p>t</p>', css, media: const MediaContext(width: 360, height: 800, prefersDark: true));
      expect(styleOf(phone, 'p').color, const CssColor(0xffff0000));
      expect(styleOf(phone, 'p').backgroundColor, CssColor.black);
      expect(styleOf(phone, 'p').width, const ResolvedLength.px(1));
      final wide = styled('<p>t</p>', css);
      expect(styleOf(wide, 'p').color, const CssColor(0xff0000ff));
      expect(styleOf(wide, 'p').backgroundColor, CssColor.transparent);
    });

    test('changing media recomputes only when the active rules change', () {
      final s = styled('<p>t</p>', css);
      final engine = s.$2;
      expect(styleOf(s, 'p').color, const CssColor(0xff0000ff));
      engine.media = const MediaContext(width: 1000, height: 700);
      expect(engine.recompute(), isEmpty);
      engine.media = const MediaContext(width: 500, height: 700);
      final changed = engine.recompute();
      expect(changed, contains(s.$1.querySelector('p')));
      expect(styleOf(s, 'p').color, const CssColor(0xffff0000));
    });

    test('Tailwind escaped classes and responsive media rules apply', () {
      final s = styled(
        '<div id="x" class="w-[100px] md:flex"></div>',
        r'.w-\[100px\]{width:100px}@media (min-width:768px){.md\:flex{display:flex}}',
        media: const MediaContext(width: 900, height: 700),
      );
      expect(styleOf(s, '#x').width!.value, 100);
      expect(styleOf(s, '#x').display, Display.flex);
    });

    test(':defined tracks registered custom elements', () {
      final s = styled(
        '<my-widget id="w"></my-widget>',
        'my-widget { display: inline } my-widget:defined { color: #ff0000 }',
      );
      expect(styleOf(s, '#w').display, Display.inline);
      expect(styleOf(s, '#w').color, CssColor.black);
      s.$1.definedCustomElements.add('my-widget');
      s.$2.invalidateAll();
      expect(styleOf(s, '#w').color, const CssColor(0xffff0000));
    });

    test('unknown features are false; invalid queries do not break the list', () {
      final q = MediaQueryList.parse(CssTokenizer('(hover: hover), (min-width: 10px)').tokenize());
      expect(q.evaluate(desktop), isTrue);
      final bad = MediaQueryList.parse(CssTokenizer('(hover: hover)').tokenize());
      expect(bad.evaluate(desktop), isFalse);
    });
  });

  group('incremental invalidation', () {
    test('class change restyles only the affected subtree', () {
      final s = styled('<div id=a><p>1</p></div><div id=b><p>2</p></div>',
          '.on p { color: red }');
      final (doc, engine) = s;
      doc.addMutationListener(engine.handleMutation);
      engine.recompute();
      final before = engine.computeCount;
      doc.getElementById('a')!.className = 'on';
      final changed = engine.recompute();
      expect(changed.map((e) => e.textContent), ['1']);
      expect(engine.computeCount - before, 2); // #a and its <p>
      expect(styleOf(s, '#a p').color, const CssColor(0xffff0000));
      expect(styleOf(s, '#b p').color, CssColor.black);
    });

    test('inserted nodes get styles; structural pseudo-classes update', () {
      final s = styled('<ul><li>1</li></ul>', 'li:last-child { color: red }');
      final (doc, engine) = s;
      doc.addMutationListener(engine.handleMutation);
      expect(styleOf(s, 'li').color, const CssColor(0xffff0000));
      final li = doc.createElement('li')..textContent = '2';
      doc.querySelector('ul')!.appendChild(li);
      engine.recompute();
      expect(engine.styleOf(doc.querySelector('li')!).color, CssColor.black);
      expect(engine.styleOf(li).color, const CssColor(0xffff0000));
    });

    test('text data changes re-evaluate :empty', () {
      final s = styled('<div id=d>x</div>', 'div:empty { color: red }');
      final (doc, engine) = s;
      doc.addMutationListener(engine.handleMutation);
      engine.recompute();
      final div = doc.getElementById('d')!;
      expect(engine.styleOf(div).color, CssColor.black);
      (div.firstChild! as Text).data = '';
      engine.recompute();
      expect(engine.styleOf(div).color, const CssColor(0xffff0000));
    });

    test('inline style mutation', () {
      final s = styled('<p>x</p>', '');
      final (doc, engine) = s;
      doc.addMutationListener(engine.handleMutation);
      engine.recompute();
      doc.querySelector('p')!.setAttribute('style', 'opacity: 0.5');
      expect(engine.recompute().length, 1);
      expect(styleOf(s, 'p').opacity, 0.5);
    });
  });

  test('SVG presentation attributes keep per-element styles', () {
    final doc = HtmlParser()
        .parseDocument(
            '<!doctype html><svg><path fill="#ffe800"/><path fill="#00148e"/></svg>')
        .value;
    final engine = StyleEngine(
        document: doc, media: const MediaContext(width: 640, height: 480));
    final paths = doc.querySelectorAll('path');
    expect(engine.styleOf(paths[0]).fillColor, const CssColor(0xffffe800));
    expect(engine.styleOf(paths[1]).fillColor, const CssColor(0xff00148e));
  });

  test('custom properties are inherited and substituted', () {
    final doc = Document();
    final root = doc.createElement('html');
    final body = doc.createElement('body');
    root.appendChild(body);
    doc.appendChild(root);
    final engine = StyleEngine(
      document: doc,
      media: const MediaContext(width: 800, height: 600),
    )..authorSheets = [
        StyleSheet.parse(':root { --fg: #123456; --bg: #abcdef }'
            'body { color: var(--fg); background: var(--bg); margin: var(--unknown, 3px) }'),
      ];
    final style = engine.styleOf(body);
    expect((style['color'] as ColorValue).color, const CssColor(0xff123456));
    expect((style['background-color'] as ColorValue).color,
        const CssColor(0xffabcdef));
    expect(style['margin-top'], const Length.px(3));
  });

  group('modern CSS', () {
    test('calc(), min(), max() and clamp()', () {
      final s = styled('<div><p>x</p></div>',
          'div { font-size: 10px } p { width: calc(100% - 2em); height: calc(1rem + 4px); '
              'margin-top: max(2px, 1em); padding-left: clamp(1px, 50%, 30px); max-width: min(100%, 230px) }');
      final p = styleOf(s, 'p');
      expect(p.width!.resolve(200), 180);
      expect(p['height'], const Length.px(20));
      expect(p['margin-top'], const Length.px(10));
      expect(p.paddingOf('left').resolve(100), 30);
      expect(p.paddingOf('left').resolve(10), 5);
      expect(p.maxWidth!.resolve(100), 100);
      expect(p.maxWidth!.resolve(1000), 230);
    });

    test('::before / ::after with content and attr()', () {
      final s = styled('<a href="#x" data-tip="Hi">link</a><b>no</b>',
          'a::before { content: "→ " attr(data-tip); color: red } a { color: blue } b:after { content: none }');
      final (doc, engine) = s;
      final a = doc.querySelector('a')!;
      final before = engine.pseudoStyleOf(a, 'before')!;
      expect(before.content!.resolve(a.getAttribute), '→ Hi');
      expect(before.color, const CssColor(0xffff0000));
      expect(engine.pseudoStyleOf(a, 'after'), isNull);
      expect(engine.pseudoStyleOf(doc.querySelector('b')!, 'after')!.content, isNull);
      expect(styleOf(s, 'a').color, const CssColor(0xff0000ff));
    });

    test(':hover rules apply while hovered', () {
      final s = styled('<p>x</p>', 'p { color: red } p:hover { color: green }');
      final (doc, engine) = s;
      doc.addMutationListener(engine.handleMutation);
      final p = doc.querySelector('p')!;
      expect(engine.styleOf(p).color, const CssColor(0xffff0000));
      doc.hoverElement = p;
      expect(engine.styleOf(p).color, const CssColor(0xff008000));
    });

    test('grid properties', () {
      final s = styled('<div><i>a</i></div>',
          'div { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 230px), 1fr)) 2fr; '
              'grid-template-areas: "h h" "n m"; gap: 1rem } i { grid-column: 1 / -1; grid-area: n }');
      final div = styleOf(s, 'div');
      expect(div.isGridContainer, isTrue);
      final cols = div.gridTemplateColumns!;
      expect(cols.entries.length, 2);
      expect(cols.entries.first.auto, 'auto-fit');
      expect(cols.entries.first.tracks.single.max.kind, 'fr');
      expect(cols.entries.first.tracks.single.min.length, isA<CalcLength>());
      expect(div.gridTemplateAreas!.rows, [
        ['h', 'h'],
        ['n', 'm'],
      ]);
      final i = styleOf(s, 'i');
      expect(i.gridRowStart.name, 'n');
      expect(i.gridColumnStart.name, 'n');
      expect(i.display, Display.block, reason: 'grid items are blockified');
    });

    test('box-shadow, gradients, transform and font: inherit', () {
      final s = styled('<div><button>b</button></div>',
          'div { font: 700 20px serif; box-shadow: 0 1px 2px #0f183014, 0 8px 24px rgba(0,0,0,.5); '
              'background: linear-gradient(120deg, #3b5bff, #8a4dff); transform: translateX(24px) scale(.97) }'
              'button { font: inherit }');
      final div = styleOf(s, 'div');
      expect(div.boxShadows.length, 2);
      expect(div.boxShadows.last.blur, const Length.px(24));
      expect(div.backgroundGradient!.angle, 120);
      expect(div.backgroundGradient!.stops.length, 2);
      expect(div.transform!.functions.map((f) => f.name), ['translatex', 'scale']);
      final button = styleOf(s, 'button');
      expect(button.fontSize, 20);
      expect(button.fontWeight, 700);
    });
  });

  group('animations, transitions and at-rules', () {
    test('@keyframes, animation and transition shorthands', () {
      final s = styled('<div><i>x</i></div>',
          '@keyframes sp { from { opacity: 0 } 50% { opacity: .5 } to { transform: rotate(360deg) } }'
              'div { animation: sp 2s linear infinite; transition: transform .2s, background .15s ease-out 50ms }');
      final (doc, engine) = s;
      final div = styleOf(s, 'div');
      final a = div.animations.single;
      expect([a.name, a.duration, a.iterations, '${a.easing}'], ['sp', 2000, double.infinity, 'linear']);
      final t = div.transitions;
      expect(t.map((x) => '${x.property}:${x.duration}:${x.delay}'), ['transform:200.0:0.0', 'background:150.0:50.0']);
      final kf = engine.keyframes('sp')!;
      expect(kf.frames.map((f) => f.offsets), [[0.0], [0.5], [1.0]]);
      final mid = engine.styleWithDeclarations(doc.querySelector('div')!, kf.frames[1].declarations);
      expect(mid.opacity, 0.5);
      expect(CssEasing.ease.transform(0.5), closeTo(0.8024, 0.001));
      expect(const CssEasing.steps(4, 'jump-end').transform(0.3), 0.25);
    });

    test('@supports and @layer', () {
      final s = styled('<p>x</p>',
          '@supports (display: grid) { p { color: red } } @supports (display: bogus) { p { color: blue } }'
              '@layer base { p { margin-top: 3px } }');
      final p = styleOf(s, 'p');
      expect(p.color, const CssColor(0xffff0000));
      expect(p['margin-top'], const Length.px(3));
    });
  });
}
