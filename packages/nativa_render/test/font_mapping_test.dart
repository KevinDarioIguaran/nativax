import 'package:flutter_test/flutter_test.dart';
import 'package:nativa_render/nativa_render.dart';

void main() {
  tearDown(() {
    nativaxDefaultFontFamily = null;
    nativaxFontFallback = const [];
    nativaxFontAvailable = null;
    nativaxLoadedFontFamilies.clear();
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

  test('unavailable families are skipped like a browser does', () {
    nativaxFontAvailable = (family) => family == 'Arial';
    final (family, _) = mapFontFamily(['Open Sans', 'sans-serif']);
    expect(family, 'Arial');
  });

  test('families loaded through @font-face count as available', () {
    nativaxFontAvailable = (family) => false;
    nativaxLoadedFontFamilies.add('open sans');
    expect(mapFontFamily(['Open Sans', 'sans-serif']).$1, 'Open Sans');
  });

  test('a list without any available family uses the standard serif font', () {
    nativaxFontAvailable = (family) => family == 'Times New Roman';
    expect(mapFontFamily(['Muli']).$1, 'Times New Roman');
  });
}
