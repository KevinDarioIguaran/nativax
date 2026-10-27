import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_dom/nativa_dom.dart';
import 'package:nativa_dom_bindings/nativa_dom_bindings.dart';
import 'package:nativa_html/nativa_html.dart';
import 'package:nativa_js/nativa_js.dart';

import '../model.dart';

class _Harness {
  _Harness({bool withTimers = false})
      : document =
            HtmlParser().parseDocument('<!doctype html><html><body></body></html>')
                .value {
    engine = JscEngine(const JavaScriptEngineConfig(
      memoryLimitBytes: 128 * 1024 * 1024,
      executionBudget: Duration(seconds: 5),
    ));
    bindings = DomBindings(
      engine: engine,
      document: document,
      environment: StaticEnvironment(
        media: const MediaContext(width: 1024, height: 768),
        languages: const ['en-US'],
        platform: 'linux',
      ),
    )..install();
    if (withTimers) {
      timers = TimerHost(engine);
    }
  }

  final Document document;
  late final JscEngine engine;
  late final DomBindings bindings;
  TimerHost? timers;

  Future<void> dispose() async {
    timers?.dispose();
    bindings.dispose();
    engine.dispose();
    document.dispose();
  }
}

List<LeakCase> domLeakCases() => [
      LeakCase(
        id: 'dom.node_churn',
        subsystem: 'dom',
        scenario: 'Create, attach, detach and discard thousands of elements',
        expectation: 'released',
        run: (ctx) async {
          final doc = HtmlParser()
              .parseDocument('<!doctype html><html><body></body></html>')
              .value;
          final body = doc.body!;
          try {
            await ctx.sample(0, nodes: doc.connectedNodeCount);
            for (var batch = 1; batch <= ctx.profile.batches; batch++) {
              for (var i = 0; i < ctx.profile.iterations; i++) {
                final el = doc.createElement('div')
                  ..className = 'item'
                  ..textContent = 'node $i';
                body.appendChild(el);
              }
              body.replaceChildren([]);
              await ctx.sample(batch, nodes: doc.connectedNodeCount);
            }
          } finally {
            doc.dispose();
          }
        },
      ),
      LeakCase(
        id: 'dom.listener_churn',
        subsystem: 'dom/events',
        scenario: 'Add and remove listeners repeatedly',
        expectation: 'released',
        run: (ctx) async {
          final h = _Harness();
          try {
            h.engine.evaluate('''
              globalThis.__targets = [];
              for (let i = 0; i < 200; i++) {
                const el = document.createElement('div');
                document.body.appendChild(el);
                globalThis.__targets.push(el);
              }
            ''');
            await ctx.sample(0,
                nodes: h.document.connectedNodeCount,
                listeners: h.bindings.liveListeners,
                targets: h.bindings.registeredTargets);
            for (var batch = 1; batch <= ctx.profile.batches; batch++) {
              h.engine.evaluate('''
                for (const el of globalThis.__targets) {
                  for (let i = 0; i < 20; i++) {
                    const fn = () => i;
                    el.addEventListener('click', fn);
                    el.removeEventListener('click', fn);
                  }
                }
              ''');
              await ctx.gc(h.engine);
              await ctx.sample(batch,
                  nodes: h.document.connectedNodeCount,
                  listeners: h.bindings.liveListeners,
                  targets: h.bindings.registeredTargets);
            }
          } finally {
            await h.dispose();
          }
        },
      ),
      LeakCase(
        id: 'dom.detached_listeners',
        subsystem: 'dom/events',
        scenario: 'Detach nodes that still hold listeners and drop JS refs',
        expectation: 'released',
        run: (ctx) async {
          final h = _Harness();
          try {
            await ctx.sample(0,
                nodes: h.document.connectedNodeCount,
                listeners: h.bindings.liveListeners,
                targets: h.bindings.registeredTargets);
            for (var batch = 1; batch <= ctx.profile.batches; batch++) {
              h.engine.evaluate('''
                for (let i = 0; i < ${ctx.profile.iterations}; i++) {
                  const el = document.createElement('div');
                  el.addEventListener('click', () => i);
                  document.body.appendChild(el);
                  el.remove();
                }
              ''');
              await ctx.gc(h.engine);
              await ctx.sample(batch,
                  nodes: h.document.connectedNodeCount,
                  listeners: h.bindings.liveListeners,
                  targets: h.bindings.registeredTargets);
            }
          } finally {
            await h.dispose();
          }
        },
      ),
      LeakCase(
        id: 'timers.cancel',
        subsystem: 'timers',
        scenario: 'Schedule many timeouts and dispose the timer host',
        expectation: 'released',
        run: (ctx) async {
          await ctx.sample(0, timers: 0, activeRuntimes: 0);
          for (var batch = 1; batch <= ctx.profile.batches; batch++) {
            final engine = JscEngine();
            final timers = TimerHost(engine);
            try {
              engine.evaluate('''
                for (let i = 0; i < 200; i++) {
                  setTimeout(() => {}, 60000);
                }
              ''');
            } finally {
              timers.dispose();
              engine.dispose();
            }
            await ctx.sample(batch, timers: timers.activeTimers, activeRuntimes: 0);
          }
        },
      ),
      LeakCase(
        id: 'bindings.lifecycle',
        subsystem: 'bindings',
        scenario: 'Create and destroy full DOM/JS/timer bindings repeatedly',
        expectation: 'released',
        run: (ctx) async {
          await ctx.sample(0, activeRuntimes: 0, listeners: 0, timers: 0);
          for (var batch = 1; batch <= ctx.profile.batches; batch++) {
            final h = _Harness(withTimers: true);
            try {
              h.engine.evaluate('''
                const el = document.createElement('div');
                document.body.appendChild(el);
                el.addEventListener('click', () => 1);
                setTimeout(() => {}, 60000);
              ''');
            } finally {
              await h.dispose();
            }
            await ctx.sample(batch,
                activeRuntimes: 0, listeners: 0, timers: 0);
          }
        },
      ),
    ];
