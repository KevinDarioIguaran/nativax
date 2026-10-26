import 'package:nativa_js/nativa_js.dart';

import '../model.dart';

/// Pure JavaScript leak cases. Every batch creates garbage, drops references
/// and asks QuickJS to collect cycles before sampling its heap.
List<LeakCase> jsLeakCases() => [
      _case(
        id: 'js.object_churn',
        scenario: 'Create and drop many short-lived objects',
        script: (n) => '''
for (let i = 0; i < $n; i++) {
  const o = { a: i, b: i + 1, c: 'x' + i };
  globalThis.__sink = o.a + o.b;
}
''',
      ),
      _case(
        id: 'js.cycles',
        scenario: 'Create and drop cyclic object graphs',
        script: (n) => '''
for (let i = 0; i < $n; i++) {
  const a = { i: i };
  const b = { i: i };
  a.next = b;
  b.prev = a;
  globalThis.__sink = a.next.i;
}
''',
      ),
      _case(
        id: 'js.closures',
        scenario: 'Closures capture large arrays and are dropped',
        script: (n) => '''
for (let i = 0; i < $n; i++) {
  const big = new Array(200).fill(i);
  const fn = () => big[0] + big[199];
  globalThis.__sink = fn();
}
''',
      ),
      _case(
        id: 'js.arrays',
        scenario: 'Replace large arrays repeatedly',
        script: (n) => '''
for (let i = 0; i < $n; i++) {
  const a = new Array(500);
  for (let j = 0; j < a.length; j++) a[j] = j;
  globalThis.__sink = a[a.length - 1];
}
''',
      ),
      _case(
        id: 'js.maps_sets',
        scenario: 'Create Map/Set/WeakMap entries and drop them',
        script: (n) => '''
for (let i = 0; i < $n; i++) {
  const m = new Map();
  const s = new Set();
  const w = new WeakMap();
  const key = { i: i };
  m.set(key, i);
  s.add(key);
  w.set(key, i);
  globalThis.__sink = m.get(key) + s.size + (w.get(key) || 0);
}
''',
      ),
      _case(
        id: 'js.shape_changes',
        scenario: 'Objects with changing dynamic shapes',
        script: (n) => '''
for (let i = 0; i < $n; i++) {
  const o = {};
  o['a' + (i % 8)] = i;
  delete o['a' + ((i + 3) % 8)];
  globalThis.__sink = i;
}
''',
      ),
      _case(
        id: 'js.errors',
        scenario: 'Create errors with stack traces and drop them',
        script: (n) => '''
for (let i = 0; i < $n; i++) {
  const e = new Error('failure ' + i);
  globalThis.__sink = e.message.length;
}
''',
      ),
      _case(
        id: 'js.functions',
        scenario: 'Create functions and prototypes dynamically',
        script: (n) => '''
for (let i = 0; i < $n; i++) {
  const fn = function named(a, b) { return a + b + i; };
  const proto = { value: i, get() { return this.value; } };
  const o = Object.create(proto);
  globalThis.__sink = fn(1, 2) + o.get();
}
''',
      ),
    ];

LeakCase _case({
  required String id,
  required String scenario,
  required String Function(int iterations) script,
}) =>
    LeakCase(
      id: id,
      subsystem: 'javascript',
      scenario: scenario,
      expectation: 'released',
      run: (ctx) async {
        final engine = QuickJsEngine(JavaScriptEngineConfig(
          memoryLimitBytes: 128 * 1024 * 1024,
          executionBudget: const Duration(seconds: 5),
        ));
        try {
          await ctx.sample(0, engineBytes: engine.memoryUsed, activeRuntimes: 1);
          for (var batch = 1; batch <= ctx.profile.batches; batch++) {
            engine.evaluate(script(ctx.profile.iterations),
                filename: '<leak:$id>');
            await ctx.gc(engine);
            await ctx.sample(batch,
                engineBytes: engine.memoryUsed, activeRuntimes: 1);
          }
        } finally {
          engine.dispose();
        }
      },
    );
