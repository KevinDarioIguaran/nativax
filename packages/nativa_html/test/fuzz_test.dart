import 'package:nativa_html/nativa_html.dart';
import 'package:test/test.dart';

void main() {
  const fragments = <String>[
    '<!doctype html><html><body><div id="a" class="x y" data-v="1">text</div></body></html>',
    '<!doctype html><html><body><p>one</p><p>two</p></body></html>',
    '<!doctype html><html><body><ul><li>a<li>b</ul></body></html>',
    '<!doctype html><html><body><table><tr><td>x</td></tr></table></body></html>',
    '<!doctype html><html><body><svg><rect width="10" height="10"/></svg></body></html>',
    '<!doctype html><html><body><math><mi>x</mi></math></body></html>',
    '<!doctype html><html><body><script>var x = 1 < 2 && 3 > 1;</script></body></html>',
    '<!doctype html><html><body><style>p{color:red}</style><p>x</p></body></html>',
    '<!doctype html><html><body><template><div>t</div></template></body></html>',
    '<!doctype html><html><body><details><summary>x</summary>y</details></body></html>',
    '<!doctype html><html><body><form><input><button>x</button></form></body></html>',
    '<!doctype html><html><body><a href="x" target="_blank">x</a></body></html>',
    '<!doctype html><html><body><img src="x.png" alt="x"></body></html>',
    '<!doctype html><html><body><iframe src="x.html"></iframe></body></html>',
    '<!doctype html><html><body><video controls></video></body></html>',
    '<!doctype html><html><body><audio controls></audio></body></html>',
    '<!doctype html><html><body><canvas width="10" height="10"></canvas></body></html>',
    '<!doctype html><html><body><svg><circle cx="5" cy="5" r="4"/></svg></body></html>',
    '<!doctype html><html><body><table><tr><td>a</td><td>b</td></tr><tr><td>c</td><td>d</td></tr></table></body></html>',
    '<!doctype html><html><body><div style="color:red"><span>x</span></div></body></html>',
    '<!doctype html><html><body><p><b>bold</b> text</p></body></html>',
    '<!doctype html><html><body><ul><li>1<li>2<li>3</ul></body></html>',
    '<!doctype html><html><body><div><!-- comment --></div></body></html>',
    '<!doctype html><html><body><pre>  spaced  text  </pre></body></html>',
    '<!doctype html><html><body><blockquote>x</blockquote></body></html>',
    '<!doctype html><html><body><hr><br><wbr></body></html>',
    '<!doctype html><html><body><abbr title="x">x</abbr></body></html>',
    '<!doctype html><html><body><code>x</code><kbd>y</kbd></body></html>',
    '<!doctype html><html><body><details open><summary>x</summary>y</details></body></html>',
    '<!doctype html><html><body><dialog open>x</dialog></body></html>',
  ];

  for (var i = 0; i < fragments.length; i++) {
    test('html fuzz case ${i + 1}', () {
      final result = HtmlParser().parseDocument(fragments[i]);
      expect(result.value, isNotNull);
      expect(result.value.querySelector('body'), isNotNull);
    });
  }
}
