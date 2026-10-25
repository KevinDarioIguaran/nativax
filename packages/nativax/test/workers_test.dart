import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nativax/nativax.dart';

class _Files extends NativaXResourceLoader {
  _Files(this.files);
  final Map<String, Object> files;

  @override
  Future<String?> load(String url) async {
    final f = files[url];
    return f is String ? f : null;
  }

  @override
  Future<Uint8List?> loadBytes(String url) async {
    final f = files[url];
    if (f is Uint8List) return f;
    if (f is String) return utf8.encode(f);
    return null;
  }
}

Future<Object?> _waitFor(WidgetTester tester, NativaXRuntime runtime, String expr, {int ms = 4000}) async {
  Object? v;
  for (var i = 0; i < ms ~/ 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    v = runtime.engine.evaluate(expr);
    if (v != null) return v;
  }
  return v;
}

void main() {
  testWidgets('module workers run on their own thread with shared memory and Atomics.wait', (tester) async {
    final errors = <Object>[];
    late NativaXRuntime runtime;
    await tester.runAsync(() async {
      runtime = await NativaXRuntime.create(
        source: '<script type="module" src="/assets/main.js"></script>',
        config: NativaXRuntimeConfig(
          onScriptError: errors.add,
          resources: _Files({
            '/assets/main.js': r'''
              const sab = new SharedArrayBuffer(16);
              const flags = new Int32Array(sab);
              const w = new Worker(new URL('./worker.js', import.meta.url), { type: 'module', name: 'physics' });
              globalThis.out = null;
              w.onmessage = (e) => {
                if (e.data === 'waiting') {
                  // The worker is blocked in Atomics.wait on its own thread;
                  // this thread keeps running and then wakes it up.
                  Atomics.store(flags, 1, 99);
                  Atomics.notify(flags, 0);
                  return;
                }
                globalThis.out = e.data;
                w.terminate();
              };
              w.postMessage(sab);
            ''',
            '/assets/worker.js': r'''
              import { label } from './shared/label.js';
              onmessage = async (e) => {
                const flags = new Int32Array(e.data);
                postMessage('waiting');
                const r = Atomics.wait(flags, 0, 0, 2000);
                const wasm = new Uint8Array(await (await fetch('/assets/data.bin')).arrayBuffer());
                postMessage({ r, woken: Atomics.load(flags, 1), label, name: self.name, bytes: Array.from(wasm) });
              };
            ''',
            '/assets/shared/label.js': "export const label = 'from-module';",
            '/assets/data.bin': Uint8List.fromList([9, 8, 7]),
          }),
        ),
      );
    });
    final out = await _waitFor(tester, runtime, 'globalThis.out');
    expect(errors, isEmpty);
    expect(out, {'r': 'ok', 'woken': 99, 'label': 'from-module', 'name': 'physics', 'bytes': [9, 8, 7]});
    runtime.dispose();
  });

  testWidgets('a busy worker does not block the page and can be terminated', (tester) async {
    late NativaXRuntime runtime;
    await tester.runAsync(() async {
      runtime = await NativaXRuntime.create(
        source: r'''<script>
          const src = 'postMessage("started"); for (;;) {}';
          globalThis.w = new Worker(URL.createObjectURL(new Blob([src])));
          w.onmessage = (e) => { globalThis.started = e.data; };
        </script>''',
      );
    });
    expect(await _waitFor(tester, runtime, 'globalThis.started'), 'started');
    // The page's own engine is free while the worker spins.
    expect(runtime.engine.evaluate('1 + 1'), 2);
    await tester.runAsync(() async {
      runtime.engine.evaluate('w.terminate()');
      // terminate() kills a worker that cannot read the request.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      runtime.dispose();
    });
  });

  testWidgets('disposing the runtime leaves no worker timer pending',
      (tester) async {
    // mdn web-workers/offscreen-canvas-worker: dispose() terminated live
    // workers through a 250 ms grace timer that outlived the runtime.
    late NativaXRuntime runtime;
    await tester.runAsync(() async {
      runtime = await NativaXRuntime.create(
        source: r'''<script>
          const src = 'postMessage("started"); setInterval(() => {}, 10);';
          globalThis.w = new Worker(URL.createObjectURL(new Blob([src])));
          w.onmessage = (e) => { globalThis.started = e.data; };
        </script>''',
      );
    });
    expect(await _waitFor(tester, runtime, 'globalThis.started'), 'started');
    runtime.dispose();
    // flutter_test fails the test if a Timer is still pending here.
  });
}
