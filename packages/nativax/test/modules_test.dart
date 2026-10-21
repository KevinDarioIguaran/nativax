import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nativax/nativax.dart';

class _Files extends NativaXResourceLoader {
  _Files(this.files);
  final Map<String, Object> files;
  final List<String> requests = [];

  @override
  Future<String?> load(String url) async {
    requests.add(url);
    final f = files[url];
    return f is String ? f : null;
  }

  @override
  Future<Uint8List?> loadBytes(String url) async {
    requests.add(url);
    final f = files[url];
    if (f is Uint8List) return f;
    if (f is String) return utf8.encode(f);
    return null;
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump();
  }
}

void main() {
  testWidgets('module scripts run after classic scripts with their import graph', (tester) async {
    final files = _Files({
      '/assets/main.js': "import { greet } from './lib/greet.js'; log.push('module:' + greet() + ':' + import.meta.url);",
      '/assets/lib/greet.js': "import base from '../base.js'; export const greet = () => base + '!';",
      '/assets/base.js': 'export default "hi";',
    });
    NativaXRuntime? runtime;
    await tester.runAsync(() async {
      runtime = await NativaXRuntime.create(
        source: '<script type="module" src="/assets/main.js"></script>'
            '<script>globalThis.log = ["classic"];</script>'
            '<script type="module">log.push("inline:" + import.meta.url);</script>',
        config: NativaXRuntimeConfig(resources: files),
      );
    });
    expect(runtime!.engine.evaluate('log'), [
      'classic',
      'module:hi!:app://local/assets/main.js',
      'inline:app://local/index.html',
    ]);
    runtime!.dispose();
  });

  testWidgets('same-origin fetch serves binary resources with streaming bodies', (tester) async {
    final wasm = Uint8List.fromList([0, 0x61, 0x73, 0x6d, 1, 0, 0, 0]);
    final errors = <Object>[];
    NativaXRuntime? runtime;
    await tester.runAsync(() async {
      runtime = await NativaXRuntime.create(
        source: r'''<script>
          globalThis.out = {};
          fetch('/assets/x.wasm').then(async (r) => {
            out.type = r.headers.get('content-type');
            const reader = r.body.getReader();
            let n = 0;
            for (;;) { const { value, done } = await reader.read(); if (done) break; n += value.length; }
            out.streamed = n;
          });
          fetch('assets/x.wasm').then((r) => r.arrayBuffer()).then((b) => { out.bytes = Array.from(new Uint8Array(b)); });
          fetch('/missing.bin').then((r) => { out.missing = r.status; });
          new Response(new ReadableStream({ start(c) { c.enqueue(new Uint8Array([104, 105])); c.close(); } }))
            .text().then((t) => { out.text = t; });
        </script>''',
        config: NativaXRuntimeConfig(resources: _Files({'/assets/x.wasm': wasm}), onScriptError: errors.add),
      );
    });
    await _settle(tester);
    expect(errors, isEmpty);
    expect(runtime!.engine.evaluate('out'), {
      'type': 'application/wasm',
      'streamed': 8,
      'bytes': wasm,
      'missing': 404,
      'text': 'hi',
    });
    runtime!.dispose();
  });

  testWidgets('bare specifiers fail like in browsers', (tester) async {
    final errors = <Object>[];
    await tester.runAsync(() async {
      final runtime = await NativaXRuntime.create(
        source: '<script type="module">import "three";</script>',
        config: NativaXRuntimeConfig(onScriptError: errors.add),
      );
      runtime.dispose();
    });
    expect(errors.single.toString(), contains('Failed to resolve module specifier "three"'));
  });
}
