import 'package:nativa_css/nativa_css.dart' show MediaContext;
import 'package:nativa_dom_bindings/nativa_dom_bindings.dart';
import 'package:nativa_html/nativa_html.dart';
import 'package:nativa_js/nativa_js.dart';

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
