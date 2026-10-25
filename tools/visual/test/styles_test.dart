import 'package:nativa_visual/src/model.dart';
import 'package:nativa_visual/src/styles.dart';
import 'package:test/test.dart';

ElementSnapshot snapshot(Map<String, String> styles) => ElementSnapshot(
  path: 'div:1',
  tag: 'div',
  rect: const BoxRect(0, 0, 100, 100),
  styles: styles,
);

void main() {
  group('style normalization', () {
    test('canonicalises font weight keywords', () {
      expect(normalizeStyles({'font-weight': 'bold'})['font-weight'], '700');
      expect(normalizeStyles({'font-weight': 'normal'})['font-weight'], '400');
    });

    test('zeroes border widths when the border style is none', () {
      final normalized = normalizeStyles({
        'border-top-style': 'none',
        'border-top-width': '3px',
        'border-bottom-width': 'medium',
      });
      expect(normalized['border-top-width'], '0px');
      expect(normalized['border-bottom-width'], '0px');
    });

    test('resolves currentcolor against the text colour', () {
      final normalized = normalizeStyles({
        'color': 'rgb(10, 20, 30)',
        'border-top-color': 'currentcolor',
      });
      expect(normalized['border-top-color'], 'rgb(10, 20, 30)');
    });

    test('normalizes font family quoting and colour spacing', () {
      final normalized = normalizeStyles({
        'font-family': '"Noto Sans",  Arial',
        'background-color': 'rgba(0,0,0,0.5)',
      });
      expect(normalized['font-family'], 'noto sans, arial');
      expect(normalized['background-color'], 'rgba(0, 0, 0, 0.5)');
    });

    test('opacity is compared at 1 % resolution', () {
      expect(normalizeStyles({'opacity': '0.5'})['opacity'], '50');
      expect(normalizeStyles({'opacity': '0.50'})['opacity'], '50');
    });
  });

  group('style comparison', () {
    test('identical computed styles score 100 %', () {
      final styles = {
        'display': 'block',
        'color': 'rgb(0, 0, 0)',
        'background-color': 'rgba(0, 0, 0, 0)',
        'font-size': '16px',
        'font-weight': '400',
        'font-family': 'sans-serif',
        'line-height': 'normal',
        'border-top-style': 'none',
      };
      final comparison = compareStyles(snapshot(styles), snapshot(styles));
      expect(comparison.score, 1);
      expect(comparison.mismatches, isEmpty);
    });

    test('a different font size lowers the score and is reported', () {
      final comparison = compareStyles(
        snapshot({'font-size': '16px', 'font-family': 'sans-serif'}),
        snapshot({'font-size': '14px', 'font-family': 'sans-serif'}),
      );
      expect(comparison.score, lessThan(1));
      expect(comparison.mismatches.first.property, 'font-size');
    });

    test('unitless line-height equals the resolved pixel value', () {
      final comparison = compareStyles(
        snapshot({'font-size': '16px', 'line-height': '1.5'}),
        snapshot({'font-size': '16px', 'line-height': '24px'}),
      );
      expect(
        comparison.mismatches.where((m) => m.property == 'line-height'),
        isEmpty,
      );
    });

    test('border radius differences are detected', () {
      final comparison = compareStyles(
        snapshot({'border-top-left-radius': '4px'}),
        snapshot({'border-top-left-radius': '0px'}),
      );
      expect(
        comparison.mismatches.map((m) => m.property),
        contains('border-top-left-radius'),
      );
    });
  });
}
