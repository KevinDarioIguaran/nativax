import 'package:nativax_html/nativax_html.dart';
import 'package:test/test.dart';

List<Token> tokenize(String input) =>
    HtmlTokenizer(input, onError: (_, _, [_]) {}).tokenize().toList();

void main() {
  group('input preprocessing', () {
    test('normalizes CR and CRLF to LF', () {
      final text = tokenize('a\rb\r\nc').single as TextToken;
      expect(text.data, 'a\nb\nc');
    });
  });

  group('comments', () {
    test('bogus comments do not include the opening bang', () {
      final comment = tokenize('<!foo>').single as CommentToken;
      expect(comment.data, 'foo');
    });

    test('replaces NUL in comments', () {
      final comment = tokenize('<!--a\u0000b-->').single as CommentToken;
      expect(comment.data, 'a\uFFFDb');
    });
  });

  group('tags and attributes', () {
    test('replaces NUL in tag and attribute names', () {
      final tag = tokenize('<a\u0000 \u0000>').single as StartTagToken;
      expect(tag.name, 'a\uFFFD');
      expect(tag.attributes.single.$1, '\uFFFD');
    });

    test('replaces NUL in attribute values', () {
      final tag = tokenize('<a x="\u0000" y=\u0000>').single as StartTagToken;
      expect(tag.attributes, [('x', '\uFFFD'), ('y', '\uFFFD')]);
    });

    test('an empty end tag is discarded', () {
      final tokens = tokenize('a</>bc');
      expect(tokens.single, isA<TextToken>());
      expect((tokens.single as TextToken).data, 'abc');
    });
  });

  group('character references', () {
    test('maps Windows-1252 numeric references', () {
      final text = tokenize('&#x80;').single as TextToken;
      expect(text.data, '\u20AC');
    });

    test('ignores leading zeroes when parsing numeric references', () {
      final text = tokenize('&#00065;').single as TextToken;
      expect(text.data, 'A');
    });
  });
}
