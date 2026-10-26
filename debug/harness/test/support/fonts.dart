// Installed system fonts shared by the offscreen harnesses (screenshot and
// audit batch).
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:nativax/nativax.dart';

Future<void> loadHarnessFonts() async {
  // flutter_tester has no fontconfig, so load the installed faces under the
  // names fontconfig resolves for the reference Chrome on this machine
  // (verified pixel-identical with headless Chrome screenshots):
  //   serif, Times New Roman, Times -> Liberation Serif (also the default)
  //   sans-serif, Arial, Helvetica   -> Liberation Sans
  //   system-ui                      -> Noto Sans
  //   monospace                      -> DejaVu Sans Mono
  //   Courier New, Courier           -> Liberation Mono
  // Families that are not installed are not aliased: Chrome skips them.
  const noto = '/usr/share/fonts/truetype/noto';
  const liberation = '/usr/share/fonts/truetype/liberation';
  const dejavu = '/usr/share/fonts/truetype/dejavu';
  ByteData bytes(File f) => ByteData.view(f.readAsBytesSync().buffer);
  final available = <String>{};
  Future<void> load(List<String> families, List<String> files) async {
    final faces = files.map(File.new).where((f) => f.existsSync()).toList();
    if (faces.isEmpty) return;
    for (final family in families) {
      available.add(family.toLowerCase());
      final loader = FontLoader(family);
      for (final face in faces) {
        loader.addFont(Future.value(bytes(face)));
      }
      await loader.load();
    }
  }

  List<String> styles(String dir, String stem) => [
        for (final style in ['Regular', 'Bold', 'Italic', 'BoldItalic'])
          '$dir/$stem-$style.ttf',
      ];
  await load(['Noto Sans', 'system-ui'], styles(noto, 'NotoSans'));
  await load(['Noto Serif'], styles(noto, 'NotoSerif'));
  await load(['Liberation Sans', 'Arial', 'Helvetica'],
      styles(liberation, 'LiberationSans'));
  await load(['Liberation Serif', 'Times New Roman', 'Times'],
      styles(liberation, 'LiberationSerif'));
  await load(['Liberation Mono', 'Courier New', 'Courier'],
      styles(liberation, 'LiberationMono'));
  await load(['DejaVu Sans Mono', 'monospace'], [
    '$dejavu/DejaVuSansMono.ttf',
    '$dejavu/DejaVuSansMono-Bold.ttf',
  ]);
  // Same fallback order fontconfig gives Chrome: text symbols from DejaVu
  // Sans before the colour emoji font.
  final fallback = <String>[];
  if (File('$dejavu/DejaVuSans.ttf').existsSync()) {
    await load(['DejaVu Sans'], ['$dejavu/DejaVuSans.ttf']);
    fallback.add('DejaVu Sans');
  }
  if (File('$noto/NotoColorEmoji.ttf').existsSync()) {
    await load(['Noto Color Emoji'], ['$noto/NotoColorEmoji.ttf']);
    fallback.add('Noto Color Emoji');
  }
  nativaxFontFallback = fallback;
  // system-ui (the platform default in mapFontFamily) is Noto Sans here.
  nativaxDefaultFontFamily = 'Noto Sans';
  // flutter_tester renders unknown families in its block test font; skip
  // them instead, as Chrome skips fonts that are not installed.
  nativaxFontAvailable = (family) => available.contains(family.toLowerCase());
}
