import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativax/nativax.dart';
import 'package:nativax_js/nativax_js.dart' show GlSurfaces;

/// Serves the fixture and the real three.js build installed by the
/// threejs-multiplayer-starter example (`npm install`).
class _Loader extends NativaXResourceLoader {
  _Loader(this.fixture, this.three);
  final String fixture;
  final String three;

  File? _file(String url) {
    final path = url.split('?').first;
    if (path.startsWith('/three/')) return File('$three/${path.substring(7)}');
    return File('$fixture/${path.startsWith('/') ? path.substring(1) : path}');
  }

  @override
  Future<String?> load(String url) async {
    final f = _file(url);
    return f != null && f.existsSync() ? f.readAsStringSync() : null;
  }

  @override
  Future<Uint8List?> loadBytes(String url) async {
    final f = _file(url);
    return f != null && f.existsSync() ? f.readAsBytesSync() : null;
  }
}

void main() {
  final three = '${Directory.current.path}/../../examples/threejs-multiplayer-starter/node_modules/three';
  final available = Directory(three).existsSync() && GlSurfaces.available;

  testWidgets('three.js r182 renders a lit, shadowed scene through NativaX WebGL', skip: !available, (tester) async {
    tester.view.physicalSize = const Size(320, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final errors = <Object>[];
    final logs = <String>[];
    NativaXRuntime? runtime;
    final key = GlobalKey();
    final source = File('test/fixtures/three/index.html').readAsStringSync();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: NativaXView(
          source: source,
          padding: EdgeInsets.zero,
          config: NativaXRuntimeConfig(
            engine: const JavaScriptEngineConfig(memoryLimitBytes: 512 << 20, executionBudget: Duration(seconds: 30), maxJobsPerDrain: 1000000),
            resources: _Loader('${Directory.current.path}/test/fixtures/three', three),
            onScriptError: errors.add,
            onConsole: (m) => logs.add('${m.level.name}: ${m.text}'),
          ),
          onRuntimeReady: (r) => runtime = r,
        ),
      ),
    ));
    for (var i = 0; i < 100 && runtime == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(errors, isEmpty, reason: logs.join('\n'));
    final result = runtime!.engine.evaluate('globalThis.result') as Map;
    expect(result['error'], 0);
    expect(result['triangles'], greaterThan(10));

    late ByteData pixels;
    late int width;
    await tester.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
      width = image.width;
      pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final out = Platform.environment['NATIVAX_THREE_SHOT'];
      if (out != null) {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File(out).writeAsBytesSync(png!.buffer.asUint8List());
      }
    });
    List<int> at(int x, int y) => [for (var c = 0; c < 3; c++) pixels.getUint8((y * width + x) * 4 + c)];
    // Reference values from Chrome (ANGLE/SwiftShader) rendering the same
    // fixture: background, lit top face, shaded side face, floor.
    const reference = {
      (4, 4): [32, 48, 64],
      (150, 100): [181, 70, 2],
      (160, 120): [134, 50, 1],
      (60, 200): [113, 141, 113],
    };
    for (final MapEntry(key: (x, y), value: rgb) in reference.entries) {
      final got = at(x, y);
      for (var c = 0; c < 3; c++) {
        expect((got[c] - rgb[c]).abs(), lessThanOrEqualTo(3), reason: 'pixel ($x,$y): $got vs Chrome $rgb');
      }
    }
  });
}
