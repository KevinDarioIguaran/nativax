// Visual comparison helper. Skipped unless NATIVAX_SHOT is set:
//
//   NATIVAX_SHOT=/tmp/out.png \
//   NATIVAX_SHOT_DIR=~/Desktop          # optional: load index.html etc. from here
//   NATIVAX_SHOT_WIDTH=800 NATIVAX_SHOT_HEIGHT=3000 \
//   NATIVAX_SHOT_JS="showSec('ui')"     # optional: script run after boot
//   NATIVAX_SHOT_SCHEME=dark             # optional: platform brightness
//   flutter test test/screenshot_test.dart
//
// Installed system fonts replace the test font so text is readable.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativax/nativax.dart';

class _Loader extends NativaXResourceLoader {
  const _Loader(this.dir);
  final String? dir;

  @override
  Future<String?> load(String url) async {
    if (url.startsWith('http://') || url.startsWith('https://')) return null;
    var path = url.split('?').first.split('#').first;
    if (path.startsWith('/')) path = path.substring(1);
    if (dir != null) {
      final f = File('$dir/$path');
      return f.existsSync() ? f.readAsStringSync() : null;
    }
    if (!path.startsWith('assets/')) path = 'assets/$path';
    try {
      return await rootBundle.loadString(path);
    } catch (_) {
      return null;
    }
  }
}

/// Same-origin images from the page directory, as Chrome loads them from
/// `file://`. Remote images stay blocked, like Chrome's host resolver rules.
/// Sources arrive resolved against the document URL (`app://local/...`).
NativaXImageResolver _images(String? dir) => (element, src) {
      final uri = Uri.tryParse(src);
      if (dir == null || uri == null) return null;
      if (uri.hasScheme && uri.scheme != 'app' && uri.scheme != 'file') {
        return null;
      }
      var path = Uri.decodeComponent(uri.path);
      if (path.startsWith('/')) path = path.substring(1);
      if (path.split('/').contains('..')) return null;
      final file = File('$dir/$path');
      if (!file.existsSync()) return null;
      return MemoryImage(file.readAsBytesSync());
    };

Future<void> _loadFonts() async {
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

void main() {
  final out = Platform.environment['NATIVAX_SHOT'];
  testWidgets('screenshot', skip: out == null, (tester) async {
    final env = Platform.environment;
    final dir = env['NATIVAX_SHOT_DIR'];
    final width = double.tryParse(env['NATIVAX_SHOT_WIDTH'] ?? '') ?? 800;
    final height = double.tryParse(env['NATIVAX_SHOT_HEIGHT'] ?? '') ?? 3000;
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (env['NATIVAX_SHOT_SCHEME'] == 'dark') {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    }

    final source = dir != null
        ? File('$dir/index.html').readAsStringSync()
        : await rootBundle.loadString('assets/index.html');
    final errors = <Object>[];
    final logs = <String>[];
    NativaXRuntime? runtime;
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: NativaXView(
            source: source,
            padding: EdgeInsets.zero,
            imageResolver: _images(dir),
            config: NativaXRuntimeConfig(
              resources: _Loader(dir),
              onScriptError: errors.add,
              onConsole: (m) => logs.add('${m.level.name}: ${m.text}'),
            ),
            onRuntimeReady: (r) => runtime = r,
          ),
        ),
      ),
    ));
    for (var i = 0; i < 20 && runtime == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    if (runtime != null) {
      // ignore: avoid_print
      print('ENGINE: ${runtime!.engineName}');
    }
    final js = env['NATIVAX_SHOT_JS'];
    if (js != null && runtime != null) {
      try {
        runtime!.engine.evaluate(js, filename: '<shot>');
      } catch (e) {
        errors.add(e);
      }
    }
    final waitMs = int.tryParse(env['NATIVAX_SHOT_WAIT'] ?? '') ?? 1000;
    for (var i = 0; i < waitMs ~/ 100; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    final dump = env['NATIVAX_SHOT_DUMP'];
    if (dump != null && runtime != null) {
      // ignore: avoid_print
      print('DUMP: ${runtime!.engine.evaluate(dump, filename: '<dump>')}');
    }
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File(out!).writeAsBytesSync(png!.buffer.asUint8List());
    });
    for (final e in errors) {
      // ignore: avoid_print
      print('SCRIPT ERROR: $e');
    }
    for (final l in logs.where((l) => !l.startsWith('log'))) {
      // ignore: avoid_print
      print(l);
    }
    // Stop QuickJS timers/isolates so the test process exits promptly and does
    // not leave a stuck `flutter_tester` behind.
    runtime?.dispose();
  });
}
