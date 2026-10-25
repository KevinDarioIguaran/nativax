import 'package:nativa_visual/src/color.dart';
import 'package:test/test.dart';

void main() {
  group('Lab and ΔE', () {
    test('white is L=100, black is L=0', () {
      expect(rgbToLab(255, 255, 255).l, closeTo(100, 0.01));
      expect(rgbToLab(0, 0, 0).l, closeTo(0, 0.01));
    });

    test('identical colours have zero ΔE', () {
      expect(deltaE(12, 34, 56, 12, 34, 56), 0);
    });

    test('black and white are far apart', () {
      expect(deltaE(0, 0, 0, 255, 255, 255), greaterThan(90));
    });

    test('near colours are below the imperceptible threshold', () {
      expect(deltaE(120, 120, 120, 121, 120, 120), lessThan(2));
    });

    test('ΔE score maps thresholds to 1 and 0', () {
      expect(deltaEScore(0), 1);
      expect(deltaEScore(2), 1);
      expect(deltaEScore(10), 0);
      expect(deltaEScore(20), 0);
      expect(deltaEScore(6), closeTo(0.5, 0.001));
    });
  });

  group('CSS colours', () {
    test('parses rgb and rgba', () {
      expect(parseCssColor('rgb(1, 2, 3)')!.toString(), 'rgb(1, 2, 3)');
      expect(parseCssColor('rgba(1, 2, 3, 0.5)')!.a, 128);
    });

    test('parses short and long hex', () {
      expect(parseCssColor('#0f0')!.toString(), 'rgb(0, 255, 0)');
      expect(parseCssColor('#ff000080')!.a, 128);
    });

    test('canonical form resolves currentcolor and spacing', () {
      expect(
        canonicalCssColor('currentcolor', current: 'rgb(9,8,7)'),
        'rgb(9, 8, 7)',
      );
      expect(canonicalCssColor('RGBA(1,   2,3,1)'), 'rgb(1, 2, 3)');
      expect(canonicalCssColor('transparent'), 'rgba(0, 0, 0, 0)');
    });

    test('unknown values are returned normalized', () {
      expect(canonicalCssColor('  some  value '), 'some value');
    });
  });
}
