import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_html/nativa_html.dart';
import 'package:test/test.dart';

// Computed UA values compared with Chromium 152 by the visual judge
// (debug/engines/visual_comparison).
void main() {
  final doc = HtmlParser()
      .parseDocument('<!doctype html><html><body>'
          '<audio id="a"></audio><audio id="ac" controls></audio>'
          '<button id="b">x</button><input id="t"><input id="r" type="radio"><textarea id="ta"></textarea>'
          '</body></html>')
      .value;
  final engine = StyleEngine(document: doc, media: const MediaContext(width: 800, height: 900));
  ComputedStyle s(String id) => engine.styleOf(doc.getElementById(id)!);

  test('audio without controls is not rendered', () {
    expect(s('a').display, Display.none);
    expect(s('ac').display, isNot(Display.none));
  });

  test('form controls use Chromium computed borders, radii and overflow', () {
    expect(s('b').borderStyleOf('top'), 'outset');
    expect(s('b').borderWidthOf('top'), 2);
    expect(s('b').radiusOf('top-left').value, 0);
    expect(s('t').borderStyleOf('top'), 'inset');
    expect(s('t').overflowX, 'clip');
    expect(s('ta').overflowY, 'auto');
    expect(s('r').marginOf('left')!.value, 5);
    expect(s('r').marginOf('bottom')!.value, 0);
  });
}
