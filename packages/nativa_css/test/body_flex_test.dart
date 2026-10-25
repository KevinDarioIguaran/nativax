import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_dom/nativa_dom.dart' as dom;
import 'package:nativa_html/nativa_html.dart';
import 'package:test/test.dart';

void main() {
  test('body flex', () {
    final doc = HtmlParser().parseDocument(
      '<!doctype html><html><body style="display:flex;align-items:center;height:100vh"></body></html>'
    ).value;
    final engine = StyleEngine(document: doc, media: const MediaContext(width: 800, height: 600));
    engine.authorSheets = [StyleSheet.parse('body{display:flex;align-items:center;height:100vh}')];
    final body = doc.body!;
    final style = engine.styleOf(body);
    print('display=${style.display} isFlex=${style.isFlexContainer} alignItems=${style.alignItems} height=${style.height}');
  });
}
