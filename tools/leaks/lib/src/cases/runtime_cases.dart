import 'package:nativax_css/nativax_css.dart' show MediaContext;
import 'package:nativax_dom_bindings/nativax_dom_bindings.dart';
import 'package:nativax_html/nativax_html.dart';
import 'package:nativax_js/nativax_js.dart';

import '../model.dart';

List<LeakCase> runtimeLeakCases() => [
      LeakCase(
        id: 'runtime.engine_cycles',
        subsystem: 'runtime',
        scenario: 'Create and dispose many QuickJS runtimes',
        expectation: 'released',
        run: (ctx) async {
          await ctx.sample(0, activeRuntimes: 0);
          for (var batch = 1; batch <= ctx.profile.batches; batch++) {
            for (var i = 0; i < 5; i++) {
              final engine = QuickJsEngine();
              engine.evaluate('globalThis.__n = 1;');
              engine.dispose();
            }
            await ctx.sample(batch, activeRuntimes: 0);
          }
        },
      ),
      LeakCase(
        id: 'runtime.bindings_cycles',
        subsystem: 'runtime',
        scenario: 'Create and dispose full document/JS/bindings stacks',
        expectation: 'released',
        run: (ctx) async {
          await ctx.sample(0,
              activeRuntimes: 0, nodes: 0, listeners: 0, targets: 0);
          for (var batch = 1; batch <= ctx.profile.batches; batch++) {
            final doc = HtmlParser()
                .parseDocument('<!doctype html><html><body></body></html>')
                .value;
            final engine = QuickJsEngine();
            final bindings = DomBindings(
              engine: engine,
              document: doc,
              environment: StaticEnvironment(
                media: const MediaContext(width: 800, height: 600),
              ),
            )..install();
            try {
              engine.evaluate('''
                const el = document.createElement('div');
                document.body.appendChild(el);
                el.addEventListener('click', () => 1);
              ''');
            } finally {
              bindings.dispose();
              engine.dispose();
              doc.dispose();
            }
            await ctx.sample(batch,
                activeRuntimes: 0, nodes: 0, listeners: 0, targets: 0);
          }
        },
      ),
    ];
