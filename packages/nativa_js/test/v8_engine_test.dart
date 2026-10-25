import 'dart:io';

import 'package:nativa_js/nativa_js.dart';
import 'package:test/test.dart';

/// Needs the V8 cdylib: NATIVAX_V8_LIB=tools/v8-spike/target/release/libnx_v8.so
void main() {
  final library = Platform.environment['NATIVAX_V8_LIB'];
  final available = library != null && File(library).existsSync();
  final skip = available ? false : 'set NATIVAX_V8_LIB to run V8 tests';

  test('a script that exhausts the heap is stopped, not the process', () {
    final engine = V8Engine(
      const JavaScriptEngineConfig(memoryLimitBytes: 32 * 1024 * 1024),
    );
    addTearDown(engine.dispose);
    expect(engine.memoryExhausted, isFalse);
    expect(
      () => engine.evaluate(
        'const keep = []; for (;;) keep.push(new Array(1e5).fill(1));',
      ),
      throwsA(isA<JavaScriptMemoryLimitException>()),
    );
    expect(engine.memoryExhausted, isTrue);
    // The isolate is still usable after the termination.
    expect(engine.evaluate('1 + 1'), 2);
  }, skip: skip);

  group('default engine', () {
    test('is V8 on desktop when the library is available', () {
      final engine = createDefaultJavaScriptEngine(
        const JavaScriptEngineConfig(),
        environment: {'NATIVAX_V8_LIB': library ?? ''},
      );
      addTearDown(engine.dispose);
      expect(engine, isA<V8Engine>());
    }, skip: skip);

    test('a second live page engine on the same thread is QuickJS', () {
      final env = {'NATIVAX_V8_LIB': library ?? ''};
      final first = createDefaultJavaScriptEngine(
        const JavaScriptEngineConfig(),
        environment: env,
      );
      addTearDown(first.dispose);
      final second = createDefaultJavaScriptEngine(
        const JavaScriptEngineConfig(),
        environment: env,
      );
      addTearDown(second.dispose);
      expect(second, isA<QuickJsEngine>());
    }, skip: skip);

    test('NATIVAX_ENGINE=quickjs forces QuickJS', () {
      final engine = createDefaultJavaScriptEngine(
        const JavaScriptEngineConfig(),
        environment: {'NATIVAX_ENGINE': 'quickjs', 'NATIVAX_V8_LIB': library ?? ''},
      );
      addTearDown(engine.dispose);
      expect(engine, isA<QuickJsEngine>());
    });

    test('a missing V8 library falls back to QuickJS', () {
      final engine = createDefaultJavaScriptEngine(
        const JavaScriptEngineConfig(),
        environment: {'NATIVAX_V8_LIB': '/nonexistent/libnx_v8.so'},
      );
      addTearDown(engine.dispose);
      expect(engine, isA<QuickJsEngine>());
    });
  });
}
