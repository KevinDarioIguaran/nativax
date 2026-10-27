import 'dart:typed_data';

import 'package:nativa_js/nativa_js.dart';
import 'package:test/test.dart';

/// Needs the host JavaScriptCore (libjavascriptcoregtk on Linux, the system
/// framework on Apple platforms, or NATIVAX_JSC_LIB elsewhere).
void main() {
  final available = JscEngine.isAvailable();
  final skip = available ? false : 'JavaScriptCore is not available on this host';

  late JscEngine engine;
  setUp(() {
    if (!available) return;
    engine = JscEngine(
      const JavaScriptEngineConfig(executionBudget: Duration(milliseconds: 300)),
    );
  });
  tearDown(() {
    if (available) engine.dispose();
  });

  test('evaluates scalars and JSON values', () {
    expect(engine.evaluate('1 + 2'), 3);
    expect(engine.evaluate('"a" + "b"'), 'ab');
    expect(engine.evaluate('({a: [1, true, null]})'), {
      'a': [1, true, null],
    });
    expect(engine.evaluate('undefined'), isNull);
  }, skip: skip);

  test('NUL characters survive in source and arguments', () {
    expect(engine.evaluate("'a\u0000b'.length"), 3);
    engine.evaluate('globalThis.len = (s) => s.length;');
    expect(engine.callGlobal('len', 'x\u0000y'), 3);
  }, skip: skip);

  test('script errors keep their name and message', () {
    expect(
      () => engine.evaluate('null.x'),
      throwsA(isA<JavaScriptException>().having((e) => e.name, 'name', 'TypeError')),
    );
    expect(
      () => engine.evaluate('throw new RangeError("boom")'),
      throwsA(
        isA<JavaScriptException>()
            .having((e) => e.name, 'name', 'RangeError')
            .having((e) => e.message, 'message', 'boom'),
      ),
    );
  }, skip: skip);

  test('host functions round-trip JSON and raise typed errors', () {
    engine.registerHostFunction('add', (a) => (a[0] as num) + (a[1] as num));
    engine.registerHostFunction(
      'fail',
      (_) => throw JavaScriptHostError('TypeError', 'nope'),
    );
    expect(engine.evaluate('__nx.host("add", 2, 3)'), 5);
    expect(
      engine.evaluate(
        'try { __nx.host("fail"); } catch (e) { e instanceof TypeError && e.message }',
      ),
      'nope',
    );
  }, skip: skip);

  test('script -> host -> script re-entry works', () {
    engine.registerHostFunction('inner', (_) => engine.evaluate('40 + 2'));
    expect(engine.evaluate('__nx.host("inner") + 1'), 43);
  }, skip: skip);

  test('an infinite loop is interrupted and the engine stays usable', () {
    final watch = Stopwatch()..start();
    expect(
      () => engine.evaluate('while (true) {}'),
      throwsA(isA<JavaScriptTimeoutException>()),
    );
    expect(watch.elapsedMilliseconds, lessThan(3000));
    expect(engine.evaluate('1 + 1'), 2);
  }, skip: skip, timeout: const Timeout(Duration(seconds: 10)));

  test('try/catch cannot swallow the interruption', () {
    expect(
      () => engine.evaluate('for (;;) { try { while (true) {} } catch (e) {} }'),
      throwsA(isA<JavaScriptTimeoutException>()),
    );
  }, skip: skip, timeout: const Timeout(Duration(seconds: 10)));

  test('a nested timeout cannot be caught by the outer script', () {
    engine.registerHostFunction('spin', (_) => engine.evaluate('while (true) {}'));
    expect(
      () => engine.evaluate('try { __nx.host("spin"); } catch (e) {} 42'),
      throwsA(isA<JavaScriptTimeoutException>()),
    );
    expect(engine.evaluate('1 + 1'), 2);
  }, skip: skip, timeout: const Timeout(Duration(seconds: 10)));

  test('callGlobal reaches the private registry, not script globals', () {
    engine.evaluate('__nx.register("secret", (x) => x * 2);');
    expect(engine.callGlobal('secret', 21), 42);
    expect(engine.evaluate('typeof globalThis.__nx_register'), 'undefined');
    expect(engine.evaluate('typeof globalThis.secret'), 'undefined');
  }, skip: skip);

  test('promise jobs run before the entry returns', () {
    engine.evaluate('globalThis.r = 0; Promise.resolve().then(() => { r = 1; });');
    engine.drainMicrotasks();
    expect(engine.evaluate('r'), 1);
  }, skip: skip);

  test('byte buffers move both ways', () {
    final id = NativeBuffers.put(Uint8List.fromList([1, 2, 3]));
    expect(
      engine.evaluate('Array.from(new Uint8Array(__nx.takeBuffer($id)))'),
      [1, 2, 3],
    );
    final back = engine.evaluate('__nx.putBuffer(new Uint8Array([9, 8]))') as int;
    expect(NativeBuffers.take(back), [9, 8]);
  }, skip: skip);

  test('modules are rejected explicitly', () {
    expect(
      () => engine.evaluateModule('export const x = 1;', url: 'm.js'),
      throwsA(isA<JavaScriptEngineStateException>()),
    );
  }, skip: skip);

  test('reports heap usage and disposes idempotently', () {
    expect(engine.memoryUsed, greaterThan(0));
    final other = JscEngine();
    other.dispose();
    other.dispose();
    expect(other.isDisposed, isTrue);
    expect(() => other.evaluate('1'), throwsA(isA<JavaScriptEngineStateException>()));
  }, skip: skip);

  test('a heap over the memory limit is reported after the entry', () {
    final small = JscEngine(
      const JavaScriptEngineConfig(memoryLimitBytes: 8 * 1024 * 1024),
    );
    addTearDown(small.dispose);
    expect(
      () => small.evaluate(
        'globalThis.keep = []; for (let i = 0; i < 64; i++) keep.push(new Uint8Array(1 << 20)); 1',
      ),
      throwsA(isA<JavaScriptMemoryLimitException>()),
    );
    expect(small.memoryExhausted, isTrue);
    expect(small.evaluate('1 + 1'), 2);
  }, skip: skip);

  test('NATIVAX_ENGINE=jsc selects JavaScriptCore by default', () {
    final picked = createDefaultJavaScriptEngine(
      const JavaScriptEngineConfig(),
      environment: const {'NATIVAX_ENGINE': 'jsc'},
    );
    addTearDown(picked.dispose);
    expect(picked, isA<JscEngine>());
    final named = createJavaScriptEngineNamed('quickjs');
    addTearDown(named.dispose);
    expect(named, isA<QuickJsEngine>());
  }, skip: skip);
}
