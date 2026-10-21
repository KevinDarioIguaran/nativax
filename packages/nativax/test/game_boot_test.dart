import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nativax/nativax.dart';

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
  Future<String?> load(String url) async {
    final f = _file(url);
    return f?.readAsStringSync();
  }

  @override
  Future<Uint8List?> loadBytes(String url) async {
    final f = _file(url);
    return f?.readAsBytesSync();
  }
}

void main() {
  final dist =
      '${Directory.current.path}/../../examples/threejs-multiplayer-starter/dist';
  final available = File('$dist/index.html').existsSync();

  testWidgets('the production game boots inside NativaX', skip: !available, (
    tester,
  ) async {
    final errors = <Object>[];
    final logs = <String>[];
    NativaXRuntime? runtime;
    await tester.runAsync(() async {
      runtime = await NativaXRuntime.create(
        source: File('$dist/index.html').readAsStringSync(),
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
      );
    });
    for (var i = 0; i < 200; i++) {
      final visible = runtime!.engine.evaluate(
        "!!document.querySelector('button.start-button.visible')",
      );
      if (visible == true) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    final state =
        runtime!.engine.evaluate('''(() => {
      const body = document.body;
      const button = document.querySelector('button.start-button');
      const loading = document.querySelector('loading-screen');
      return {
        button: button ? button.className : null,
        loading: loading ? loading.localName : null,
        canvases: document.querySelectorAll('canvas').length,
      };
    })()''')
            as Map;
    expect(state['button'], contains('visible'));
    expect(state['loading'], 'loading-screen');
    expect(state['canvases'], greaterThanOrEqualTo(1));
    expect(errors, isEmpty, reason: logs.join('\n'));
    runtime!.dispose();
    await tester.pump(const Duration(milliseconds: 500));
  });
}
