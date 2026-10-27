import 'dart:typed_data';

import 'package:nativa_css/nativa_css.dart' show MediaContext;
import 'package:nativa_dom/nativa_dom.dart';
import 'package:nativa_dom_bindings/nativa_dom_bindings.dart';
import 'package:nativa_html/nativa_html.dart';
import 'package:nativa_js/nativa_js.dart';

import '../model.dart';

/// Ground-truth dataset: workloads whose leak status is known by
/// construction. They are not product cases and never run with `run`; use
/// `run --dataset audit` or `evaluate`. Documented in
/// `debug/datasets/memory/README.md`.
List<LeakCase> auditLeakCases() => [
  // Leaking workloads.
  _dom(
    id: 'audit.leak.listeners_retained',
    scenario:
        'Detached elements with a listener each, kept in a global '
        'array that is never cleared',
    truth: const LeakTruth(
      leaks: true,
      expected: 'proven_leak',
      rationale:
          '50 listeners and 50 node wrappers are retained per '
          'batch; the release step clears the body, not the array',
    ),
    setup: 'globalThis.__leak = [];',
    batch: (_) => '''
for (let i = 0; i < 50; i++) {
  const el = document.createElement('div');
  el.addEventListener('click', () => i);
  globalThis.__leak.push(el);
}''',
    release: 'document.body.replaceChildren();',
  ),
  _dom(
    id: 'audit.leak.wrappers_retained',
    scenario: 'Element wrappers cached in a global Map without eviction',
    truth: const LeakTruth(
      leaks: true,
      expected: 'proven_leak',
      rationale:
          '50 node wrappers are added to an unbounded cache per '
          'batch',
    ),
    setup: 'globalThis.__cache = new Map(); globalThis.__next = 0;',
    batch: (_) => '''
for (let i = 0; i < 50; i++) {
  const el = document.createElement('span');
  globalThis.__cache.set(globalThis.__next++, el);
}''',
    release: 'document.body.replaceChildren();',
  ),
  _dom(
    id: 'audit.leak.timers_unbounded',
    scenario: 'Long intervals scheduled every batch and never cleared',
    truth: const LeakTruth(
      leaks: true,
      expected: 'proven_leak',
      rationale:
          '10 one-hour intervals are scheduled per batch and no '
          'handle is kept to clear them',
    ),
    timers: true,
    batch: (_) => '''
for (let i = 0; i < 10; i++) {
  setInterval(() => {}, 3600000);
}''',
  ),
  _js(
    id: 'audit.leak.js_global_array',
    scenario: 'Objects pushed to a global array every batch',
    truth: const LeakTruth(
      leaks: true,
      expected: 'proven_leak',
      rationale:
          'iterations/4 objects (about 100 B each) are retained per '
          'batch by a global',
    ),
    setup: 'globalThis.__leak = [];',
    batch: (n) =>
        '''
for (let i = 0; i < ${n ~/ 4}; i++) {
  globalThis.__leak.push({ i: i, s: 'item-' + i });
}''',
    release: 'globalThis.__sink = null;',
  ),
  _js(
    id: 'audit.leak.js_slow',
    scenario: 'Four small objects retained per batch',
    truth: const LeakTruth(
      leaks: true,
      expected: 'proven_leak',
      rationale:
          'a real but small leak (a few hundred bytes per batch), '
          'below the 1 KiB/batch effect floor: the known hard case',
    ),
    setup: 'globalThis.__leak = [];',
    batch: (_) => '''
for (let i = 0; i < 4; i++) {
  globalThis.__leak.push({ i: i });
}''',
    release: 'globalThis.__sink = null;',
  ),
  LeakCase(
    id: 'audit.leak.rss_native',
    subsystem: 'audit/native',
    scenario: 'Dart retains an 8 MiB buffer per batch; no counter sees it',
    expectation: 'released',
    truth: const LeakTruth(
      leaks: true,
      expected: 'suspected_leak',
      rationale:
          'leaks by construction, but only RSS can see it and the '
          'policy caps RSS-only evidence at suspected_leak',
    ),
    run: (ctx) async {
      final kept = <Uint8List>[];
      await ctx.sample(0);
      for (var batch = 1; batch <= ctx.profile.batches; batch++) {
        kept.add(Uint8List(8 * 1024 * 1024)..fillRange(0, 8 * 1024 * 1024, 1));
        await ctx.sample(batch);
      }
      await ctx.sampleRelease();
      kept.clear();
    },
  ),
  _js(
    id: 'audit.leak.too_few',
    scenario: 'Global array leak observed for only 3 batches',
    truth: const LeakTruth(
      leaks: true,
      expected: 'inconclusive',
      rationale:
          'leaks, but 3 batches leave 2 post-warm-up points, fewer '
          'than the 5 the trend test needs',
    ),
    batches: 3,
    setup: 'globalThis.__leak = [];',
    batch: (n) =>
        '''
for (let i = 0; i < ${n ~/ 4}; i++) {
  globalThis.__leak.push({ i: i, s: 'item-' + i });
}''',
  ),

  // Controls.
  _js(
    id: 'audit.control.alloc_release',
    scenario: 'Allocate arrays of objects and drop them every batch',
    truth: const LeakTruth(
      leaks: false,
      expected: 'no_leak',
      rationale: 'every allocation is unreachable at the end of the batch',
    ),
    batch: (n) =>
        '''
for (let i = 0; i < $n; i++) {
  const a = new Array(64).fill({ i: i });
  globalThis.__sink = a.length;
}''',
  ),
  _dom(
    id: 'audit.control.listeners_balanced',
    scenario: 'Attach elements with listeners, remove listeners and nodes',
    truth: const LeakTruth(
      leaks: false,
      expected: 'no_leak',
      rationale:
          'every listener is removed and every node detached and '
          'dropped before the sample',
    ),
    batch: (_) => '''
for (let i = 0; i < 50; i++) {
  const el = document.createElement('div');
  const fn = () => i;
  el.addEventListener('click', fn);
  document.body.appendChild(el);
  el.removeEventListener('click', fn);
  el.remove();
}''',
  ),
  _dom(
    id: 'audit.control.timers_cleared',
    scenario: 'Schedule intervals and clear them in the same batch',
    truth: const LeakTruth(
      leaks: false,
      expected: 'no_leak',
      rationale: 'every interval handle is cleared',
    ),
    timers: true,
    batch: (_) => '''
const ids = [];
for (let i = 0; i < 10; i++) ids.push(setInterval(() => {}, 3600000));
for (const id of ids) clearInterval(id);''',
  ),
  _js(
    id: 'audit.control.bounded_cache',
    scenario: 'LRU cache capped at 2000 entries, half refilled per batch',
    truth: const LeakTruth(
      leaks: false,
      expected: 'bounded_high_usage',
      rationale:
          'the cache fills in two batches and then evicts; memory '
          'plateaus well above the baseline',
    ),
    setup: 'globalThis.__lru = new Map(); globalThis.__next = 0;',
    batch: (_) => '''
const lru = globalThis.__lru;
for (let i = 0; i < 1000; i++) {
  lru.set(globalThis.__next++, { payload: 'x'.repeat(64) + i });
  if (lru.size > 2000) lru.delete(lru.keys().next().value);
}''',
  ),
  _dom(
    id: 'audit.control.bounded_wrapper_pool',
    scenario: 'Ring buffer of the last 100 element wrappers',
    truth: const LeakTruth(
      leaks: false,
      expected: 'bounded_high_usage',
      rationale:
          'the pool holds at most 100 wrappers; it fills in two '
          'batches and then replaces entries',
    ),
    setup: 'globalThis.__pool = [];',
    batch: (_) => '''
for (let i = 0; i < 50; i++) {
  globalThis.__pool.push(document.createElement('div'));
  if (globalThis.__pool.length > 100) globalThis.__pool.shift();
}''',
  ),
  _js(
    id: 'audit.control.grow_then_release',
    scenario: 'Global array grows every batch and is cleared on release',
    truth: const LeakTruth(
      leaks: false,
      expected: 'bounded_high_usage',
      rationale:
          'the workload holds growing memory on purpose and the '
          'release step frees all of it',
    ),
    setup: 'globalThis.__held = [];',
    batch: (n) =>
        '''
for (let i = 0; i < ${n ~/ 4}; i++) {
  globalThis.__held.push({ i: i, s: 'item-' + i });
}''',
    release: 'globalThis.__held = [];',
  ),
  _dom(
    id: 'audit.control.warmup_step',
    scenario: 'One wrapper cached once in the first batch, then churn',
    truth: const LeakTruth(
      leaks: false,
      expected: 'no_leak',
      rationale:
          'a single one-time allocation (the same shape as the '
          'dom.detached_listeners false alarm) followed by released churn',
    ),
    batch: (_) => '''
if (!globalThis.__once) globalThis.__once = document.createElement('div');
for (let i = 0; i < 50; i++) {
  const el = document.createElement('div');
  document.body.appendChild(el);
  el.remove();
}''',
  ),
  _js(
    id: 'audit.control.noisy_engine',
    scenario: 'A pool resized to a pseudo-random size every batch',
    truth: const LeakTruth(
      leaks: false,
      expected: 'inconclusive',
      rationale:
          'the live set is replaced by 0-4000 objects chosen by a '
          'seeded LCG: large variation, no trend',
    ),
    setup: 'globalThis.__seed = 42;',
    batch: (_) => '''
globalThis.__seed = (globalThis.__seed * 1103515245 + 12345) % 2147483648;
const size = globalThis.__seed % 4001;
const pool = [];
for (let i = 0; i < size; i++) pool.push({ i: i, s: 'p' + i });
globalThis.__pool = pool;''',
  ),
  LeakCase(
    id: 'audit.control.noisy_rss',
    subsystem: 'audit/native',
    scenario: 'Dart allocates and drops a 0-64 MiB buffer every batch',
    expectation: 'released',
    truth: const LeakTruth(
      leaks: false,
      expected: 'inconclusive',
      rationale:
          'only RSS is observable and it moves with allocator and '
          'GC timing; nothing is retained',
    ),
    run: (ctx) async {
      var seed = 42;
      await ctx.sample(0);
      for (var batch = 1; batch <= ctx.profile.batches; batch++) {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        final size = seed % (64 * 1024 * 1024);
        var buffer = Uint8List(size)..fillRange(0, size, 1);
        buffer = Uint8List(0);
        await ctx.sample(batch, extra: {'dropped': buffer.length});
      }
    },
  ),
];

class _DomHarness {
  _DomHarness({required bool withTimers})
    : document = HtmlParser()
          .parseDocument('<!doctype html><html><body></body></html>')
          .value {
    engine = JscEngine(
      const JavaScriptEngineConfig(
        memoryLimitBytes: 128 * 1024 * 1024,
        executionBudget: Duration(seconds: 5),
      ),
    );
    bindings = DomBindings(
      engine: engine,
      document: document,
      environment: StaticEnvironment(
        media: const MediaContext(width: 1024, height: 768),
      ),
    )..install();
    if (withTimers) timers = TimerHost(engine);
  }

  final Document document;
  late final JscEngine engine;
  late final DomBindings bindings;
  TimerHost? timers;

  Future<void> sample(LeakContext ctx, int batch, {bool release = false}) {
    final timerCount = timers?.activeTimers;
    if (release) {
      return ctx.sampleRelease(
        engineBytes: engine.memoryUsed,
        nodes: document.connectedNodeCount,
        listeners: bindings.liveListeners,
        targets: bindings.registeredTargets,
        timers: timerCount,
      );
    }
    return ctx.sample(
      batch,
      engineBytes: engine.memoryUsed,
      nodes: document.connectedNodeCount,
      listeners: bindings.liveListeners,
      targets: bindings.registeredTargets,
      timers: timerCount,
    );
  }

  void dispose() {
    timers?.dispose();
    bindings.dispose();
    engine.dispose();
    document.dispose();
  }
}

LeakCase _dom({
  required String id,
  required String scenario,
  required LeakTruth truth,
  required String Function(int iterations) batch,
  String setup = '',
  String release = '',
  bool timers = false,
}) => LeakCase(
  id: id,
  subsystem: 'audit/dom',
  scenario: scenario,
  expectation: 'released',
  truth: truth,
  run: (ctx) async {
    final h = _DomHarness(withTimers: timers);
    try {
      if (setup.isNotEmpty) h.engine.evaluate(setup);
      await ctx.gc(h.engine);
      await h.sample(ctx, 0);
      for (var b = 1; b <= ctx.profile.batches; b++) {
        h.engine.evaluate(
          '{\n${batch(ctx.profile.iterations)}\n}',
          filename: '<$id>',
        );
        await ctx.gc(h.engine);
        await h.sample(ctx, b);
      }
      if (release.isNotEmpty) h.engine.evaluate(release);
      await ctx.gc(h.engine);
      await h.sample(ctx, 0, release: true);
    } finally {
      h.dispose();
    }
  },
);

LeakCase _js({
  required String id,
  required String scenario,
  required LeakTruth truth,
  required String Function(int iterations) batch,
  String setup = '',
  String release = '',
  int? batches,
}) => LeakCase(
  id: id,
  subsystem: 'audit/javascript',
  scenario: scenario,
  expectation: 'released',
  truth: truth,
  run: (ctx) async {
    final engine = JscEngine(
      const JavaScriptEngineConfig(
        memoryLimitBytes: 128 * 1024 * 1024,
        executionBudget: Duration(seconds: 5),
      ),
    );
    try {
      if (setup.isNotEmpty) engine.evaluate(setup);
      await ctx.gc(engine);
      await ctx.sample(0, engineBytes: engine.memoryUsed);
      final total = batches ?? ctx.profile.batches;
      for (var b = 1; b <= total; b++) {
        engine.evaluate(
          '{\n${batch(ctx.profile.iterations)}\n}',
          filename: '<$id>',
        );
        await ctx.gc(engine);
        await ctx.sample(b, engineBytes: engine.memoryUsed);
      }
      if (release.isNotEmpty) engine.evaluate(release);
      await ctx.gc(engine);
      await ctx.sampleRelease(engineBytes: engine.memoryUsed);
    } finally {
      engine.dispose();
    }
  },
);
