import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_dom/nativa_dom.dart';
import 'package:nativa_html/nativa_html.dart';
import 'package:nativa_render/nativa_render.dart';

/// Regressions found by the Chromium visual judge
/// (`debug/engines/visual_comparison`); each case names its page.
Future<Document> pumpPage(WidgetTester tester, String body, String css) async {
  final doc = HtmlParser()
      .parseDocument('<!doctype html><html><body>$body</body></html>')
      .value;
  final engine = StyleEngine(
    document: doc,
    media: const MediaContext(width: 800, height: 900),
  )..authorSheets = [StyleSheet.parse(css)];
  tester.view.physicalSize = const Size(800, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: NativaXDocumentView(document: doc, styleEngine: engine, padding: EdgeInsets.zero),
  ));
  await tester.pump();
  return doc;
}

Rect rectOf(Document doc, String selector) {
  final box = elementRenderBoxes[doc.querySelector(selector)!]!;
  return box.localToGlobal(Offset.zero) & box.size;
}

void main() {
  // 50projects50days/drag-n-drop: a 145px child of a 144px content box
  // overflows in Chromium instead of being clamped.
  testWidgets('definite width overflows a narrower containing block', (tester) async {
    final doc = await pumpPage(
      tester,
      '<div class="o"><div class="i"></div><div class="c"></div></div>',
      'body { margin: 0 } .o { width: 100px; border: 3px solid black } '
          '.i { width: 145px; height: 10px } '
          '.c { width: 120px; height: 10px; margin: 0 auto }',
    );
    expect(rectOf(doc, '.i'), const Rect.fromLTWH(3, 3, 145, 10));
    // Over-constrained auto margins resolve to 0: no negative centring.
    expect(rectOf(doc, '.c'), const Rect.fromLTWH(3, 13, 120, 10));
  });

  // 50projects50days/pokedex: body's gradient paints the whole canvas, not
  // only body's 80px box.
  testWidgets('body background gradient propagates to the canvas', (tester) async {
    await pumpPage(
      tester,
      '<h1>x</h1>',
      'body { margin: 0; background: linear-gradient(to right, #ff0000, #0000ff) }',
    );
    final pixel = await pixelAt(tester, 2, 800);
    expect(pixel.r, greaterThan(240));
    expect(pixel.b, lessThan(15));
  });

  // 50projects50days/pokedex: SkParagraph puts letter-spacing / 2 before
  // the first glyph; CSS puts it all after.
  testWidgets('letter-spacing does not shift the first glyph', (tester) async {
    final doc = await pumpPage(
      tester,
      '<p>III</p>',
      'body { margin: 0 } p { margin: 0; font: 30px Ahem; letter-spacing: 10px }',
    );
    expect(rectOf(doc, 'p').left, 0);
    final first = await pixelAt(tester, 1, 15);
    expect(first.r, lessThan(128), reason: 'first glyph starts at x = 0');
  });

  // 50projects50days/hoverboard: `box-shadow: 0 0 2px #000` on 16px
  // squares with `transition: 2s` must paint from the first frame.
  for (final transition in ['', 'transition: 2s ease;']) {
    testWidgets('box-shadow paints ($transition)', (tester) async {
      // flutter_test paints shadows without blur unless told otherwise.
      debugDisableShadows = false;
      await pumpPage(
        tester,
        '<div class="s"></div>',
        'body { margin: 0; background: #ffffff } '
            '.s { margin: 10px; width: 16px; height: 16px; background: #1d1d1d; '
            'box-shadow: 0 0 2px #000; $transition }',
      );
      final edge = await pixelAt(tester, 9, 18);
      debugDisableShadows = true;
      // CSS blur 2px = Gaussian sigma 1: about 31 % ink half a pixel out.
      expect(edge.r, inInclusiveRange(160, 200));
    });
  }

  // 50projects50days/incrementing-counter: a column flex item of a centred
  // row is as tall as its content, not the viewport.
  testWidgets('indefinite column flex is content-sized', (tester) async {
    final doc = await pumpPage(
      tester,
      '<div class="c"><div class="n"></div></div>',
      'body { margin: 0; display: flex; align-items: center; height: 100vh } '
          '.c { display: flex; flex-direction: column; justify-content: center } '
          '.n { width: 10px; height: 40px }',
    );
    expect(rectOf(doc, '.c').height, 40);
    expect(rectOf(doc, '.c').top, 430);
  });

  testWidgets('column flex items grow to the min-height', (tester) async {
    final doc = await pumpPage(
      tester,
      '<div class="c"><div class="g"></div></div>',
      'body { margin: 0 } .c { display: flex; flex-direction: column; min-height: 300px } '
          '.g { flex: 1 }',
    );
    expect(rectOf(doc, '.g').height, 300);
  });

  // 50projects50days/quiz-app: inline replaced elements keep their margins
  // (radio: 3px 3px 0 5px) and are 13px wide.
  testWidgets('inline radio keeps its UA margins', (tester) async {
    final doc = await pumpPage(
      tester,
      '<div><input type="radio" id="a"><input type="checkbox" id="b"></div>',
      'body { margin: 0 }',
    );
    final a = rectOf(doc, '#a');
    final b = rectOf(doc, '#b');
    expect(a.left, 5);
    expect(a.size, const Size(13, 13));
    expect(b.left, 5 + 13 + 3 + 4);
  });

  // 50projects50days/verify-account-ui: spaces around <br> and at the end
  // of a block collapse away, so centred lines are not shifted.
  testWidgets('collapsible spaces around br are removed', (tester) async {
    final doc = await pumpPage(
      tester,
      '<p>ab <br> cd </p><div class="w"><span class="ib"></span> </div>',
      'body { margin: 0 } p { margin: 0; font: 10px Ahem; width: 40px; text-align: right } '
          '.w { text-align: center; width: 100px } .ib { display: inline-block; width: 20px; height: 10px }',
    );
    expect(rectOf(doc, 'p').height, 20);
    expect(rectOf(doc, '.ib').left, 40);
  });

  // Labels are inline text: tapping their text activates the control.
  testWidgets('tapping label text toggles its checkbox', (tester) async {
    final doc = await pumpPage(
      tester,
      '<label for="cb">Check me</label><input id="cb" type="checkbox">',
      'body { margin: 0; font: 20px Ahem }',
    );
    await tester.tapAt(const Offset(30, 10));
    await tester.pump();
    expect(doc.getElementById('cb')!.checked, isTrue);
  });

  // 50projects50days/movie-app, feedback-ui-design: an inline text input
  // inside a row flex item is measured intrinsically (dry baseline) without
  // a framework assertion.
  testWidgets('inline controls survive intrinsic measurement', (tester) async {
    final doc = await pumpPage(
      tester,
      '<header><form><input type="text" id="s" placeholder="Search"></form></header>'
          '<div class="r"><span class="ib"><input type="radio"> a</span></div>',
      'body { margin: 0 } header { display: flex; justify-content: flex-end } '
          '.r { display: flex } .ib { display: inline-block }',
    );
    expect(tester.takeException(), isNull);
    expect(rectOf(doc, '#s').right, 800);
  });

  // 50projects50days/password-strength-background: column items that do not
  // stretch are fit-content wide.
  testWidgets('centred column items are fit-content', (tester) async {
    final doc = await pumpPage(
      tester,
      '<div class="c"><div class="w"></div></div>',
      'body { margin: 0; display: flex; flex-direction: column; align-items: center } '
          '.w { width: 100px; height: 10px }',
    );
    expect(rectOf(doc, '.c'), const Rect.fromLTWH(350, 0, 100, 10));
  });

  // 50projects50days/netflix-mobile-navigation: a fixed box inside a
  // transformed ancestor is positioned in that ancestor, and rendered.
  testWidgets('fixed inside a transformed ancestor is contained', (tester) async {
    final doc = await pumpPage(
      tester,
      '<div class="t"><div class="f"></div></div>',
      'body { margin: 0 } .t { position: fixed; left: 100px; top: 50px; width: 200px; height: 100px; '
          'transform: translateX(10px) } .f { position: fixed; left: 5px; top: 5px; width: 20px; height: 20px }',
    );
    expect(rectOf(doc, '.f'), const Rect.fromLTWH(115, 55, 20, 20));
  });

  // A line with only empty inline elements has no height (an icon font
  // that did not load leaves `<button><i></i></button>` 2px tall).
  testWidgets('a line of empty inline elements has no height', (tester) async {
    final doc = await pumpPage(tester, '<button><i></i></button>', 'body { margin: 0 }');
    expect(rectOf(doc, 'button').height, 2 + 2 + 2);
  });

  // 50projects50days/image-carousel: an outer box-shadow is not painted
  // under a box without a background.
  testWidgets('box-shadow does not show through the box', (tester) async {
    await pumpPage(
      tester,
      '<div class="c"></div>',
      'body { margin: 0; background: #ffffff } .c { margin: 20px; width: 100px; height: 100px; '
          'box-shadow: 2px 2px 5px rgba(0, 0, 0, 0.3) }',
    );
    expect((await pixelAt(tester, 70, 70)).r, 255);
    expect((await pixelAt(tester, 121, 70)).r, lessThan(255));
  });

  // 50projects50days/expanding-cards: an absolute box with only `left`
  // shrinks to fit its flex-sized containing block (wraps to min-content).
  testWidgets('absolute auto width shrinks to fit the containing block', (tester) async {
    final doc = await pumpPage(
      tester,
      '<div class="row"><div class="p"><h3>ab cd</h3></div><div class="q"></div></div>',
      'body { margin: 0 } .row { display: flex; width: 300px } .p { position: relative; flex: 1; height: 200px } '
          '.q { width: 260px } h3 { font: 20px Ahem; position: absolute; left: 10px; bottom: 0; margin: 0 }',
    );
    final r = rectOf(doc, 'h3');
    expect([r.left, r.top, r.width, r.height].map((v) => v.roundToDouble()), [10, 160, 40, 40]);
  });

  // 50projects50days/image-carousel vs verify-account-ui: `min-width: auto`
  // lets a fixed-width box shrink to its content, but a text input's
  // min-content is its size-based width, so it does not shrink.
  testWidgets('flex automatic minimum: boxes shrink, inputs do not', (tester) async {
    final doc = await pumpPage(
      tester,
      '<div class="r"><div class="b"></div><div class="b"></div></div>'
          '<div class="r"><input class="i"><input class="i"></div>',
      'body { margin: 0 } .r { display: flex; width: 200px } .b { width: 150px; height: 10px } '
          '.i { width: 150px; padding: 0; border: 0; font-size: 20px }',
    );
    expect(rectOf(doc, '.b').width, 100);
    expect(rectOf(doc, '.i').width, 150);
  });

  // 50projects50days/movie-app: a text input without a CSS width is
  // `size × avg + (max − avg)` wide (Chromium: 207px content at 16px
  // Liberation Sans, 177px at 13.33px).
  testWidgets('default text input width follows Chromium', (tester) async {
    final doc = await pumpPage(
      tester,
      '<input class="a"><input class="b" size="10">',
      'body { margin: 0 } input { padding: 0; border: 0; font: 16px sans-serif } .b { display: block }',
    );
    // A fit, not Skia's hinted metrics: within 2px of the reference.
    expect(rectOf(doc, '.a').width, closeTo(207, 2));
    expect(rectOf(doc, '.b').width, closeTo((9 * 0.5796 + 2.016) * 16, 0.5));
  });

  // 50projects50days/custom-range-slider, theme-clock: an absolute child of
  // a centring flex container without left/right is centred (static
  // position of a sole flex item).
  testWidgets('absolute child of a flex container uses its static position', (tester) async {
    final doc = await pumpPage(
      tester,
      '<h2>x</h2><div class="f"></div>',
      'body { margin: 0; display: flex; flex-direction: column; align-items: center; '
          'justify-content: center; height: 100vh } h2 { position: absolute; top: 10px; margin: 0; '
          'width: 100px; height: 20px } .f { width: 10px; height: 10px }',
    );
    expect(rectOf(doc, 'h2'), const Rect.fromLTWH(350, 10, 100, 20));
  });
}

Future<({int r, int g, int b})> pixelAt(WidgetTester tester, int x, int y) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).first);
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final i = (y * image.width + x) * 4;
    return (r: data.getUint8(i), g: data.getUint8(i + 1), b: data.getUint8(i + 2));
  }))!;
}
