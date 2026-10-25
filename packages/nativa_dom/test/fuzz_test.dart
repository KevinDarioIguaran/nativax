import 'package:nativa_html/nativa_html.dart';
import 'package:test/test.dart';

void main() {
  const snippets = <String>[
    '<!doctype html><html><body><div id="a">x</div></body></html>',
    '<!doctype html><html><body><ul><li>a<li>b</ul></body></html>',
    '<!doctype html><html><body><table><tr><td>x</td></tr></table></body></html>',
    '<!doctype html><html><body><div class="x y" data-v="1">text</div></body></html>',
    '<!doctype html><html><body><p>a</p><p>b</p></body></html>',
  ];
  for (var i = 0; i < 30; i++) {
    test('dom fuzz case ${i + 1}', () {
      final source = snippets[i % snippets.length];
      final doc = HtmlParser().parseDocument(source).value;
      final body = doc.body!;
      final el = doc.createElement('span');
      el.textContent = 'fuzz $i';
      body.appendChild(el);
      expect(doc.querySelector('span'), isNotNull);
      body.replaceChildren([]);
      expect(doc.querySelector('span'), isNull);
    });
  }
}
