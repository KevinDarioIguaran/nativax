import 'package:nativax_dom/nativax_dom.dart';
import 'package:nativax_html/nativax_html.dart';
import 'package:test/test.dart';

Document parse(String s) => HtmlParser().parseDocument(s).value;
String bodyHtml(String s) => parse(s).body!.innerHtml;

void main() {
  group('document structure', () {
    test('empty document gets html/head/body', () {
      final r = HtmlParser().parseDocument('');
      expect(r.value.documentElement!.outerHtml,
          '<html><head></head><body></body></html>');
      expect(r.errors, isEmpty);
    });

    test('explicit structure with doctype', () {
      final d = parse('<!DOCTYPE html><html lang="es"><head><title>T</title>'
          '</head><body class="b"><p>x</p></body></html>');
      expect(d.documentElement!.getAttribute('lang'), 'es');
      expect(d.title, 'T');
      expect(d.body!.className, 'b');
      expect(d.body!.innerHtml, '<p>x</p>');
    });

    test('head elements before content go to head; content starts body', () {
      final d = parse('<style>p{}</style><meta charset=utf-8>Hola<div>a</div>');
      expect(d.head!.children.map((e) => e.localName), ['style', 'meta']);
      expect(d.body!.innerHtml, 'Hola<div>a</div>');
    });

    test('content after </body> stays in body', () {
      expect(bodyHtml('<body><p>a</p></body><p>b</p>'), '<p>a</p><p>b</p>');
    });
  });

  group('elements and attributes', () {
    test('nesting', () {
      expect(bodyHtml('<div><section><span>a<b>b</b></span></section></div>'),
          '<div><section><span>a<b>b</b></span></section></div>');
    });

    test('quoted, unquoted, empty and boolean attributes', () {
      final d = parse('<input type=text value="a b" data-x=\'q"\' disabled>');
      final input = d.querySelector('input')!;
      expect(input.attributes, {
        'type': 'text',
        'value': 'a b',
        'data-x': 'q"',
        'disabled': '',
      });
    });

    test('attribute names are lower-cased; duplicates keep the first', () {
      final r = HtmlParser().parseDocument('<div ID="a" id="b" Class=c></div>');
      final div = r.value.querySelector('div')!;
      expect(div.attributes, {'id': 'a', 'class': 'c'});
      expect(r.errors.map((e) => e.code), contains('duplicate-attribute'));
    });

    test('void elements never take children', () {
      expect(bodyHtml('<p>a<br>b<img src=x.png>c<hr></p>'),
          // <hr> closes the <p>, so the later </p> creates an empty one.
          '<p>a<br>b<img src="x.png">c</p><hr><p></p>');
      expect(bodyHtml('<input/><span>x</span>'), '<input><span>x</span>');
    });

    test('unknown elements are kept as generic elements', () {
      expect(bodyHtml('<my-widget foo=1><x-y>t</x-y></my-widget>'),
          '<my-widget foo="1"><x-y>t</x-y></my-widget>');
    });

    test('tag names are case-insensitive', () {
      expect(bodyHtml('<DIV><SpAn>x</span></div>'), '<div><span>x</span></div>');
    });
  });

  group('text and character references', () {
    test('named and numeric references', () {
      final d = parse('<p>&lt;b&gt; &amp; &copy; &#169; &#xA9; &ntilde; &nbsp;</p>');
      expect(d.querySelector('p')!.textContent, '<b> & © © © ñ  ');
    });

    test('unknown and bare ampersands stay literal', () {
      final r = HtmlParser().parseDocument('<p>a & b &zz; &#;</p>');
      expect(r.value.querySelector('p')!.textContent, 'a & b &zz; &#;');
      expect(r.errors.map((e) => e.code),
          containsAll(['unknown-named-character-reference',
              'absence-of-digits-in-numeric-character-reference']));
    });

    test('references in attributes', () {
      final d = parse('<a href="?a=1&amp;b=2&copy=3" title="&quot;x&quot;">l</a>');
      final a = d.querySelector('a')!;
      expect(a.getAttribute('href'), '?a=1&b=2&copy=3');
      expect(a.getAttribute('title'), '"x"');
    });

    test('invalid numeric references become U+FFFD', () {
      expect(parse('<p>&#0;&#xD800;&#99999999;</p>').querySelector('p')!.textContent,
          '���');
    });

    test('a lone < is text', () {
      expect(parse('<p>1 < 2 and 3 <= 4</p>').querySelector('p')!.textContent,
          '1 < 2 and 3 <= 4');
    });

    test('non-ASCII text is preserved', () {
      expect(parse('<p>שלום 漢字 🎉</p>').querySelector('p')!.textContent,
          'שלום 漢字 🎉');
    });
  });

  group('comments', () {
    test('comments become nodes', () {
      final d = parse('<div><!-- hi --><span></span></div>');
      final div = d.querySelector('div')!;
      expect(div.firstChild, isA<Comment>());
      expect((div.firstChild as Comment).data, ' hi ');
    });

    test('unterminated comment runs to end of input', () {
      final r = HtmlParser().parseDocument('<p>a</p><!-- open');
      expect(r.errors.map((e) => e.code), contains('eof-in-comment'));
    });

    test('bogus comments', () {
      final r = HtmlParser().parseDocument('<?xml version="1.0"?><p>x</p>');
      expect(r.value.body!.innerHtml, '<p>x</p>');
    });
  });

  group('raw text elements', () {
    test('script content is not parsed as markup', () {
      final d = parse('<script>if (a < b && c > d) { x = "</div>"; }</script><p>after</p>');
      final script = d.querySelector('script')!;
      expect(script.textContent, 'if (a < b && c > d) { x = "</div>"; }');
      expect(d.querySelector('p')!.textContent, 'after');
    });

    test('style content is raw; end tag is case-insensitive', () {
      final d = parse('<style>a > b { color: red }</STYLE><p>x</p>');
      expect(d.querySelector('style')!.textContent, 'a > b { color: red }');
      expect(d.querySelector('p'), isNotNull);
    });

    test('textarea is RCDATA: references decoded, tags not', () {
      final d = parse('<textarea>&lt;b&gt;<i>x</i></textarea>');
      expect(d.querySelector('textarea')!.textContent, '<b><i>x</i>');
      expect(d.querySelector('i'), isNull);
    });

    test('unterminated script consumes the rest and reports', () {
      final r = HtmlParser().parseDocument('<script>let a = 1;<p>');
      expect(r.value.querySelector('script')!.textContent, 'let a = 1;<p>');
      expect(r.errors.map((e) => e.code), contains('eof-in-script'));
    });
  });

  group('implicit closing and recovery', () {
    test('p closed by block elements', () {
      expect(bodyHtml('<p>a<div>b</div>'), '<p>a</p><div>b</div>');
      expect(bodyHtml('<p>a<p>b'), '<p>a</p><p>b</p>');
    });

    test('li, dt/dd and option close their siblings', () {
      expect(bodyHtml('<ul><li>a<li>b</ul>'), '<ul><li>a</li><li>b</li></ul>');
      expect(bodyHtml('<ul><li>a<ul><li>b</ul><li>c</ul>'),
          '<ul><li>a<ul><li>b</li></ul></li><li>c</li></ul>');
      expect(bodyHtml('<dl><dt>a<dd>b<dt>c</dl>'),
          '<dl><dt>a</dt><dd>b</dd><dt>c</dt></dl>');
      expect(bodyHtml('<select><option>a<option>b</select>'),
          '<select><option>a</option><option>b</option></select>');
    });

    test('unmatched end tags are ignored and reported', () {
      final r = HtmlParser().parseDocument('<div>a</span>b</div>');
      expect(r.value.body!.innerHtml, '<div>ab</div>');
      final e = r.errors.firstWhere((e) => e.code == 'unexpected-end-tag');
      expect((e.line, e.column, e.detail), (1, 7, 'span'));
    });

    test('end tag closes intervening unclosed elements', () {
      final r = HtmlParser().parseDocument('<div><span><b>x</div>y');
      expect(r.value.body!.innerHtml, '<div><span><b>x</b></span></div>y');
      expect(r.errors.map((e) => e.code), contains('unclosed-elements'));
    });

    test('unclosed elements are closed at end of input', () {
      expect(bodyHtml('<div><span>x'), '<div><span>x</span></div>');
    });

    test('</br> is a <br>; </p> without <p> inserts one', () {
      expect(bodyHtml('a</br>b</p>'), 'a<br>b<p></p>');
    });

    test('self-closing non-void elements stay open (HTML semantics)', () {
      final r = HtmlParser().parseDocument('<div/><span>x</span>');
      expect(r.value.body!.innerHtml, '<div><span>x</span></div>');
      expect(r.errors.single.code,
          'non-void-html-element-start-tag-with-trailing-solidus');
    });

    test('truncated tags at EOF are dropped', () {
      expect(bodyHtml('<p>x</p><div class="a'), '<p>x</p>');
      expect(bodyHtml('<p>x</p></div'), '<p>x</p>');
    });

    test('line and column of errors', () {
      final r = HtmlParser().parseDocument('<p>\n  </x>');
      expect((r.errors.single.line, r.errors.single.column), (2, 3));
    });
  });

  group('limits', () {
    test('input length limit', () {
      expect(
        () => HtmlParser(limits: const HtmlParserLimits(maxInputLength: 10))
            .parseDocument('<p>more than ten</p>'),
        throwsA(isA<HtmlLimitException>()),
      );
    });

    test('node limit', () {
      expect(
        () => HtmlParser(limits: const HtmlParserLimits(maxNodes: 50))
            .parseDocument('<p>x</p>' * 100),
        throwsA(isA<HtmlLimitException>()),
      );
    });

    test('deep nesting is flattened at the limit, without recursion', () {
      final r = HtmlParser(limits: const HtmlParserLimits(maxDepth: 20))
          .parseDocument('<div>' * 5000);
      var depth = 0;
      for (Node? n = r.value.body; n != null; n = n.firstChild) {
        depth++;
      }
      expect(depth, lessThanOrEqualTo(20));
      expect(r.errors.first.code, 'nesting-too-deep');
      expect(r.droppedErrors, greaterThan(0));
    });

    test('large documents parse in linear time', () {
      final big = '<div class="row"><span>item &amp; text</span><b>x</b></div>' * 15000;
      final sw = Stopwatch()..start();
      final d = HtmlParser(limits: const HtmlParserLimits(maxNodes: 200000))
          .parseDocument(big, documentLimits: const DocumentLimits(maxNodes: 200000))
          .value;
      sw.stop();
      expect(d.body!.children.length, 15000);
      expect(sw.elapsedMilliseconds, lessThan(3000));
    });
  });

  group('fragments', () {
    test('parseFragment creates nodes owned by the context document', () {
      final d = parse('<div id=host></div>');
      final host = d.getElementById('host')!;
      final f = HtmlParser().parseFragment('<b>x</b> <i>y</i>', host).value;
      expect(f.childNodes.length, 3);
      host.appendChild(f);
      expect(host.innerHtml, '<b>x</b> <i>y</i>');
    });

    test('html/head/body tags are ignored in fragments', () {
      final d = parse('');
      final f = HtmlParser()
          .parseFragment('<html><body><p>x</p></body></html>', d.body!)
          .value;
      expect(f.childNodes.single.nodeName, 'P');
    });
  });
}
