import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativax/nativax.dart';
import 'package:nativax_dom/nativax_dom.dart' show canvasSurfaces;
import 'package:nativax_js/nativax_js.dart' show GlSurfaces;

/// Serves the game's production `dist/` exactly as Vite emitted it.
class _DistLoader extends NativaXResourceLoader {
  _DistLoader(this.root);
  final String root;

  File? _file(String url) {
    final path = url.split('?').first;
    final rel = path.startsWith('/') ? path.substring(1) : path;
    final f = File('$root/$rel');
    return f.existsSync() ? f : null;
  }

  @override
  Future<String?> load(String url) async => _file(url)?.readAsStringSync();

  @override
  Future<Uint8List?> loadBytes(String url) async =>
      _file(url)?.readAsBytesSync();
}

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() condition, {
  int ms = 15000,
}) async {
  for (var i = 0; i < ms ~/ 20; i++) {
    if (i < 3 || i % 100 == 0) {}
    bool ok;
    try {
      ok = condition();
    } catch (e) {
      rethrow;
    }
    if (i < 3) {}
    if (ok) return;
    if (i < 3) {}
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    if (i < 3) {}
    await tester.pump(const Duration(milliseconds: 16));
    if (i < 3) {}
  }
}

void main() {
  final dist =
      '${Directory.current.path}/../../examples/threejs-multiplayer-starter/dist';
  testWidgets('the production game is playable in NativaXView', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final errors = <Object>[];
    final logs = <String>[];
    NativaXRuntime? runtime;
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: NativaXView(
            source: File('$dist/index.html').readAsStringSync(),
            padding: EdgeInsets.zero,
            config: NativaXRuntimeConfig(
              engine: const JavaScriptEngineConfig(
                memoryLimitBytes: 512 << 20,
                executionBudget: Duration(seconds: 30),
                maxJobsPerDrain: 1000000,
              ),
              resources: _DistLoader(dist),
              onScriptError: errors.add,
              onConsole: (m) => logs.add('${m.level.name}: ${m.text}'),
              onDiagnostic: (m) => logs.add('diag: $m'),
            ),
            onRuntimeReady: (r) => runtime = r,
          ),
        ),
      ),
    );
    await _waitFor(
      tester,
      () =>
          runtime != null &&
          runtime!.engine.evaluate(
                "!!document.querySelector('button.start-button.visible')",
              ) ==
              true,
    );
    expect(runtime, isNotNull);
    expect(errors, isEmpty, reason: logs.join('\n'));
    expect(
      runtime!.engine.evaluate(
        "!!document.querySelector('button.start-button.visible')",
      ),
      isTrue,
      reason: 'start button never appeared\n${logs.join('\n')}',
    );

    // Use the real DOM box and a Flutter tap, not element.click().
    final box =
        runtime!.engine.evaluate('''
      (() => { const b = document.querySelector('button.start-button');
        const r = b.getBoundingClientRect();
        return { x: r.left + r.width / 2, y: r.top + r.height / 2,
                 w: r.width, h: r.height }; })()
    ''')
            as Map;
    expect((box['w'] as num).toDouble(), greaterThan(10));
    await tester.tapAt(
      Offset((box['x'] as num).toDouble(), (box['y'] as num).toDouble()),
    );
    await tester.pump();

    await _waitFor(
      tester,
      () =>
          runtime!.engine.evaluate(
            "!document.querySelector('loading-screen')",
          ) ==
          true,
      ms: 5000,
    );
    // Let the render worker present a few frames and physics move the world.
    for (var i = 0; i < 120; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(errors, isEmpty, reason: logs.join('\n'));
    final canvas = runtime!.document.querySelector('#webgl');
    expect(canvas, isNotNull);
    final surface = canvasSurfaces[canvas!];
    expect(surface, isNotNull);
    expect(
      GlSurfaces.frame(surface!),
      greaterThan(0),
      reason: 'the render worker never presented a frame',
    );

    late ByteData pixels;
    late int width;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      width = image.width;
      pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final out = Platform.environment['NATIVAX_GAME_SHOT'];
      if (out != null) {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File(out).writeAsBytesSync(png!.buffer.asUint8List());
      }
    });

    // The scene must not be a flat clear colour: the fox, terrain and UI
    // produce several distinct luminance levels in the frame.
    final seen = <int>{};
    for (var y = 0; y < 100; y += 4) {
      for (var x = 0; x < width; x += 4) {
        final i = (y * width + x) * 4;
        final l =
            (pixels.getUint8(i) +
                pixels.getUint8(i + 1) +
                pixels.getUint8(i + 2)) ~/
            3;
        seen.add(l ~/ 8);
      }
    }
    expect(
      seen.length,
      greaterThan(6),
      reason: 'render looks flat; captured ${seen.length} luminance bands',
    );

    runtime!.dispose();
    await tester.pump(const Duration(milliseconds: 500));
  });
}
