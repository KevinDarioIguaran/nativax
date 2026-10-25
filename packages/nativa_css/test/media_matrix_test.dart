import 'package:nativa_css/nativa_css.dart';
import 'package:test/test.dart';

bool _matches(String query, MediaContext context) =>
    MediaQueryList.parse(CssTokenizer(query).tokenize()).evaluate(context);

void main() {
  const desktop = MediaContext(width: 1024, height: 768);
  const portrait = MediaContext(width: 600, height: 800);
  const dark = MediaContext(width: 1024, height: 768, prefersDark: true);
  const reduced = MediaContext(
    width: 1024,
    height: 768,
    prefersReducedMotion: true,
  );
  const retina = MediaContext(width: 1024, height: 768, devicePixelRatio: 2);
  const mobile = MediaContext(width: 375, height: 812);

  test('media matrix 01: min-width met', () {
    expect(_matches('(min-width: 800px)', desktop), isTrue);
  });
  test('media matrix 02: min-width not met', () {
    expect(_matches('(min-width: 1200px)', desktop), isFalse);
  });
  test('media matrix 03: max-width met', () {
    expect(_matches('(max-width: 1200px)', desktop), isTrue);
  });
  test('media matrix 04: portrait orientation', () {
    expect(_matches('(orientation: portrait)', portrait), isTrue);
  });
  test('media matrix 05: landscape orientation', () {
    expect(_matches('(orientation: landscape)', desktop), isTrue);
  });
  test('media matrix 06: dark preference', () {
    expect(_matches('(prefers-color-scheme: dark)', dark), isTrue);
  });
  test('media matrix 07: light preference', () {
    expect(_matches('(prefers-color-scheme: light)', desktop), isTrue);
  });
  test('media matrix 08: reduced motion', () {
    expect(_matches('(prefers-reduced-motion: reduce)', reduced), isTrue);
  });
  test('media matrix 09: no-preference motion', () {
    expect(
      _matches('(prefers-reduced-motion: no-preference)', desktop),
      isTrue,
    );
  });
  test('media matrix 10: min resolution in dppx', () {
    expect(_matches('(min-resolution: 2dppx)', retina), isTrue);
  });
  test('media matrix 11: max resolution rejects retina', () {
    expect(_matches('(max-resolution: 1dppx)', retina), isFalse);
  });
  test('media matrix 12: screen type', () {
    expect(_matches('screen and (min-width: 800px)', desktop), isTrue);
  });
  test('media matrix 13: print type rejected', () {
    expect(_matches('print', desktop), isFalse);
  });
  test('media matrix 14: negated screen rejected', () {
    expect(_matches('not screen', desktop), isFalse);
  });
  test('media matrix 15: comma list uses any match', () {
    expect(
      _matches('(min-width: 1200px), (max-width: 1200px)', desktop),
      isTrue,
    );
  });
  test('media matrix 16: unknown feature is false', () {
    expect(_matches('(hover: hover)', desktop), isFalse);
  });
  test('media matrix 17: invalid media type is false', () {
    expect(_matches('projector and (min-width: 1px)', desktop), isFalse);
  });
  test('media matrix 18: min-height met', () {
    expect(_matches('(min-height: 700px)', desktop), isTrue);
  });
  test('media matrix 19: max-height rejects taller viewport', () {
    expect(_matches('(max-height: 700px)', desktop), isFalse);
  });
  test('media matrix 20: mobile portrait profile', () {
    expect(
      _matches(
        'screen and (max-width: 480px) and (orientation: portrait)',
        mobile,
      ),
      isTrue,
    );
  });
}
