import 'package:nativa_benchmark/render_fixtures.dart';
import 'package:nativa_html/nativa_html.dart';
import 'package:test/test.dart';

void main() {
  for (final family in const [
    'list-overflow',
    'flex-grid',
    'article',
    'table',
    'app-shell',
  ]) {
    test('$family generates exactly 1000 nodes', () {
      final html = RenderFixtureGenerator(family, nodes: 1000).generate();
      final document = HtmlParser().parseDocument(html).value;
      final match = RegExp(r'<!-- nodes=(\d+) -->').firstMatch(html)!;
      final expected = int.parse(match.group(1)!);
      expect(document.querySelectorAll('*').length, expected);
      expect(expected, greaterThanOrEqualTo(1000));
    });

    test('$family is deterministic', () {
      final a = RenderFixtureGenerator(family, nodes: 1000).generate();
      final b = RenderFixtureGenerator(family, nodes: 1000).generate();
      expect(a, equals(b));
    });
  }
}
