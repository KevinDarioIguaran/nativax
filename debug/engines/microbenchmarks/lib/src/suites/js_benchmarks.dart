import 'dart:convert';

import 'package:nativa_js/nativa_js.dart';

import '../model.dart';

/// Pure JavaScript benchmarks. These are intentionally independent from DOM
/// and renderer work so the results measure the engine, not the bridge.
class JsBenchmarks {
  /// [engineFactory] selects the engine under test. The default is QuickJS-ng;
  /// the benchmark CLI passes a V8 factory only for the documented reference
  /// run (`--engine v8`, `NATIVAX_V8_LIB`). Cases and checksums never change.
  JsBenchmarks({JavaScriptEngine Function(JavaScriptEngineConfig config)?
      engineFactory}) {
    engine = engineFactory?.call(const JavaScriptEngineConfig()) ??
        QuickJsEngine();
    engine.registerHostFunction('noop', (args) => args.isEmpty ? 0 : args[0]);
  }

  late final JavaScriptEngine engine;

  List<BenchmarkCase> cases() {
    final parseText = jsonEncode(
      List.generate(20, (i) => {'id': i, 'name': 'item$i', 'ok': true}),
    );
    return [
      _case(
        name: 'js.arithmetic',
        operations: 1000000,
        source: '''
(() => {
  let sum = 0;
  for (let i = 0; i < 1000000; i++) {
    sum = (sum + i * 3 + (i % 7)) | 0;
  }
  return sum;
})()
''',
      ),
      _case(
        name: 'js.function_calls',
        operations: 500000,
        source: '''
(() => {
  function add(a, b) { return a + b; }
  let sum = 0;
  for (let i = 0; i < 500000; i++) sum = add(sum, i);
  return sum;
})()
''',
      ),
      _case(
        name: 'js.objects_properties',
        operations: 300000,
        source: '''
(() => {
  const proto = { get() { return this.value; } };
  let sum = 0;
  for (let i = 0; i < 300000; i++) {
    const o = Object.create(proto);
    o.value = i;
    sum += o.get();
  }
  return sum;
})()
''',
      ),
      _case(
        name: 'js.arrays',
        operations: 200000,
        source: '''
(() => {
  const a = [];
  let sum = 0;
  for (let i = 0; i < 200000; i++) {
    a.push(i);
    sum += a[i];
  }
  return sum + a.length;
})()
''',
      ),
      _case(
        name: 'js.strings',
        operations: 150000,
        source: '''
(() => {
  const s = 'abcdefghij';
  let sum = 0;
  for (let i = 0; i < 150000; i++) {
    sum += s.charCodeAt(i % 10) + s.slice(1, 5).length;
  }
  return sum;
})()
''',
      ),
      _case(
        name: 'js.recursion',
        operations: 1,
        unit: 'run',
        source: '''
(() => {
  function fib(n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }
  return fib(24);
})()
''',
        expected: 46368,
      ),
      _case(
        name: 'js.json_parse',
        operations: 5000,
        source:
            '''
(() => {
  const text = ${jsonEncode(parseText)};
  let sum = 0;
  for (let i = 0; i < 5000; i++) {
    const value = JSON.parse(text);
    sum += value[0].id + value.length;
  }
  return sum;
})()
''',
      ),
      _case(
        name: 'js.json_stringify',
        operations: 5000,
        source: '''
(() => {
  const value = { id: 1, name: 'item', ok: true, nested: { a: 1, b: 2 } };
  let sum = 0;
  for (let i = 0; i < 5000; i++) {
    sum += JSON.stringify(value).length;
  }
  return sum;
})()
''',
      ),
      _case(
        name: 'js.object_churn',
        operations: 120000,
        source: '''
(() => {
  let sum = 0;
  for (let i = 0; i < 120000; i++) {
    const o = { a: i, b: i + 1, c: 'x' + i };
    sum += o.a + o.b + o.c.length;
  }
  return sum;
})()
''',
        notes: 'Allocation pressure; watch memory in the host process.',
      ),
      _case(
        name: 'bridge.noop',
        category: 'bridge',
        operations: 5000,
        source: '''
(() => {
  let sum = 0;
  for (let i = 0; i < 5000; i++) {
    sum += __nx.host('noop', i);
  }
  return sum;
})()
''',
        notes: 'JS → C → Dart → JS round-trip, excluding DOM work.',
      ),
      ..._steadyCases(parseText),
    ];
  }

  /// Warm-up compiles the script once; measured rounds call the compiled
  /// function. This separates steady-state engine execution from parsing,
  /// bytecode generation and Dart result decoding.
  List<BenchmarkCase> _steadyCases(String parseText) {
    BenchmarkCase steady(
      String name,
      String source, {
      required int operations,
      num? expected,
    }) {
      var prepared = false;
      return BenchmarkCase(
        name: name,
        category: 'js_steady',
        operations: operations,
        expected: expected,
        notes: 'Compiled once; measured rounds exclude parse/compile.',
        body: () {
          const fnName = '__nativax_steady_bench';
          if (!prepared) {
            engine.evaluate(
              'globalThis.$fnName = function(){ return ($source); };',
              filename: '<steady:$name>',
            );
            prepared = true;
          }
          final value = engine.callGlobal(fnName);
          if (value is num) return value;
          if (value is bool) return value ? 1 : 0;
          if (value == null) return 0;
          throw StateError('$name returned a non-numeric checksum: $value');
        },
      );
    }

    return [
      steady('js_steady.arithmetic', '''
(() => {
  let sum = 0;
  for (let i = 0; i < 1000000; i++) {
    sum = (sum + i * 3 + (i % 7)) | 0;
  }
  return sum;
})()
''', operations: 1000000),
      steady('js_steady.function_calls', '''
(() => {
  function add(a, b) { return a + b; }
  let sum = 0;
  for (let i = 0; i < 500000; i++) sum = add(sum, i);
  return sum;
})()
''', operations: 500000),
      steady('js_steady.objects_properties', '''
(() => {
  const proto = { get() { return this.value; } };
  let sum = 0;
  for (let i = 0; i < 300000; i++) {
    const o = Object.create(proto);
    o.value = i;
    sum += o.get();
  }
  return sum;
})()
''', operations: 300000),
      steady('js_steady.arrays', '''
(() => {
  const a = [];
  let sum = 0;
  for (let i = 0; i < 200000; i++) {
    a.push(i);
    sum += a[i];
  }
  return sum + a.length;
})()
''', operations: 200000),
      steady('js_steady.strings', '''
(() => {
  const s = 'abcdefghij';
  let sum = 0;
  for (let i = 0; i < 150000; i++) {
    sum += s.charCodeAt(i % 10) + s.slice(1, 5).length;
  }
  return sum;
})()
''', operations: 150000),
      steady(
        'js_steady.recursion',
        '''
(() => {
  function fib(n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }
  return fib(24);
})()
''',
        operations: 1,
        expected: 46368,
      ),
      steady('js_steady.json_parse', '''
(() => {
  const text = ${jsonEncode(parseText)};
  let sum = 0;
  for (let i = 0; i < 5000; i++) {
    const value = JSON.parse(text);
    sum += value[0].id + value.length;
  }
  return sum;
})()
''', operations: 5000),
      steady('js_steady.json_stringify', '''
(() => {
  const value = { id: 1, name: 'item', ok: true, nested: { a: 1, b: 2 } };
  let sum = 0;
  for (let i = 0; i < 5000; i++) {
    sum += JSON.stringify(value).length;
  }
  return sum;
})()
''', operations: 5000),
      steady('js_steady.object_churn', '''
(() => {
  let sum = 0;
  for (let i = 0; i < 120000; i++) {
    const o = { a: i, b: i + 1, c: 'x' + i };
    sum += o.a + o.b + o.c.length;
  }
  return sum;
})()
''', operations: 120000),
    ];
  }

  BenchmarkCase _case({
    required String name,
    required String source,
    required int operations,
    String category = 'js',
    String unit = 'ops',
    num? expected,
    String notes = '',
  }) => BenchmarkCase(
    name: name,
    category: category,
    operations: operations,
    unit: unit,
    expected: expected,
    notes: notes,
    body: () {
      final value = engine.evaluate(source, filename: '<bench:$name>');
      if (value is num) return value;
      if (value is bool) return value ? 1 : 0;
      if (value == null) return 0;
      throw StateError('$name returned a non-numeric checksum: $value');
    },
  );

  void dispose() => engine.dispose();
}
