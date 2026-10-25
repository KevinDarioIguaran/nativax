import 'package:flutter_test/flutter_test.dart';
import 'package:nativa_render/nativa_render.dart';

void main() {
  tearDown(() {
    nativaxDefaultFontFamily = null;
    nativaxFontFallback = const [];
  });

  test('sans-serif maps to the Arial-metric faces Chrome uses', () {
    nativaxDefaultFontFamily = 'Noto Sans';
    final (family, fallback) = mapFontFamily(['sans-serif']);
    expect(family, 'Arial');
    expect(fallback, ['Helvetica', 'Liberation Sans', 'Noto Sans']);
  });

  test('system-ui keeps the platform default font', () {
    nativaxDefaultFontFamily = 'Noto Sans';
    expect(mapFontFamily(['system-ui']).$1, 'Noto Sans');
  });

  test('serif and the initial family prefer Times New Roman', () {
    expect(mapFontFamily(['serif']).$1, 'Times New Roman');
    final (family, fallback) = mapFontFamily(['Times New Roman']);
    expect(family, 'Times New Roman');
    expect(fallback, contains('Liberation Serif'));
  });

  test('page families come before the generic expansion', () {
    final (family, fallback) = mapFontFamily(['Open Sans', 'sans-serif']);
    expect(family, 'Open Sans');
    expect(fallback!.first, 'Arial');
  });
}
