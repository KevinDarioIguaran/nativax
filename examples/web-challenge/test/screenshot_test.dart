// Visual comparison helper. Skipped unless NATIVAX_SHOT is set:
//
//   NATIVAX_SHOT=/tmp/out.png \
//   NATIVAX_SHOT_DIR=~/Desktop          # optional: load index.html etc. from here
//   NATIVAX_SHOT_WIDTH=800 NATIVAX_SHOT_HEIGHT=3000 \
//   NATIVAX_SHOT_JS="showSec('ui')"     # optional: script run after boot
//   NATIVAX_SHOT_SCHEME=dark             # optional: platform brightness
//   flutter test test/screenshot_test.dart
//
// System fonts (Noto Sans) replace the test font so text is readable.
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

Future<void> _loadFonts() async {
  const dir = '/usr/share/fonts/truetype/noto';
  final regular = File('$dir/NotoSans-Regular.ttf');
  if (!regular.existsSync()) return;
  final bold = File('$dir/NotoSans-Bold.ttf');
  // Chrome resolves `monospace` to DejaVu Sans Mono through fontconfig here;
  // use the same face so the comparison measures layout, not fonts.
  final dejavu = File('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf');
  final mono = dejavu.existsSync() ? dejavu : File('$dir/NotoSansMono-Regular.ttf');
  final emoji = File('$dir/NotoColorEmoji.ttf');
  ByteData bytes(File f) => ByteData.view(f.readAsBytesSync().buffer);
  for (final family in ['Noto Sans', 'Roboto', 'ui-rounded', 'Segoe UI', 'sans-serif', 'system-ui', 'Arial']) {
    final loader = FontLoader(family)..addFont(Future.value(bytes(regular)));
    if (bold.existsSync()) loader.addFont(Future.value(bytes(bold)));
    await loader.load();
  }
  // Same fallback order fontconfig gives Chrome: text symbols from DejaVu
  // Sans before the colour emoji font.
  final fallback = <String>[];
  final symbols = File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
  if (symbols.existsSync()) {
    await (FontLoader('DejaVu Sans')..addFont(Future.value(bytes(symbols)))).load();
    fallback.add('DejaVu Sans');
  }
  if (emoji.existsSync()) {
    await (FontLoader('Noto Color Emoji')..addFont(Future.value(bytes(emoji)))).load();
    fallback.add('Noto Color Emoji');
  }
  nativaxFontFallback = fallback;
  // fontconfig resolves sans-serif/system-ui to Noto Sans for Chrome here.
  nativaxDefaultFontFamily = 'Noto Sans';
  if (mono.existsSync()) {
    for (final family in ['monospace', 'ui-monospace', 'Menlo', 'Consolas', 'Roboto Mono']) {
      await (FontLoader(family)..addFont(Future.value(bytes(mono)))).load();
    }
  }
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
