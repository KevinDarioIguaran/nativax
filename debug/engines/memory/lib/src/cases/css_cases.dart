import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_dom/nativa_dom.dart';

import '../model.dart';

List<LeakCase> cssLeakCases() => [
      LeakCase(
        id: 'css.style_churn',
        subsystem: 'css',
        scenario: 'Toggle classes and recompute styles on a large tree',
        expectation: 'released',
        run: (ctx) async {
          final doc = Document();
          final body = doc.createElement('body');
          doc.appendChild(body);
          final elements = <Element>[];
          for (var i = 0; i < 800; i++) {
            final el = doc.createElement('div')
              ..className = 'item'
              ..textContent = 'row $i';
            body.appendChild(el);
            elements.add(el);
          }
          final style = StyleEngine(
            document: doc,
            media: const MediaContext(width: 1024, height: 768),
          )..authorSheets = [
              StyleSheet.parse(
                  '.item { display: block; color: #000 }\n.hot { color: #f00 }'),
            ];
          style.recompute();
          try {
            await ctx.sample(0, nodes: doc.connectedNodeCount);
            for (var batch = 1; batch <= ctx.profile.batches; batch++) {
              for (final el in elements) {
                el.classList.toggle('hot');
              }
              style.recompute();
              await ctx.sample(batch, nodes: doc.connectedNodeCount);
            }
          } finally {
            doc.dispose();
          }
        },
      ),
    ];
