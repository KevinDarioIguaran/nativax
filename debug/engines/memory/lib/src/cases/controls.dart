import 'package:nativa_js/nativa_js.dart';

import '../model.dart';

/// Negative control: engines are created, used and disposed every batch.
LeakCase releaseControl() => LeakCase(
      id: 'control.release',
      subsystem: 'lifecycle',
      scenario: 'Create and dispose one QuickJS runtime per batch',
      expectation: 'released',
      run: (ctx) async {
        await ctx.sample(0, activeRuntimes: 0);
        for (var batch = 1; batch <= ctx.profile.batches; batch++) {
          final engine = JscEngine();
          engine.evaluate('let n = 0; for (let i = 0; i < 1000; i++) n += i;');
          engine.dispose();
          await ctx.sample(batch, activeRuntimes: 0);
        }
      },
    );

/// Positive control: runtimes are intentionally retained. A leak detector that
/// cannot see this is blind.
LeakCase retainedControl() => LeakCase(
      id: 'control.retained',
      subsystem: 'lifecycle',
      scenario: 'Create QuickJS runtimes and retain them on purpose',
      expectation: 'retained',
      run: (ctx) async {
        final kept = <JscEngine>[];
        await ctx.sample(0, activeRuntimes: 0);
        try {
          for (var batch = 1; batch <= ctx.profile.batches; batch++) {
            kept.add(JscEngine()
              ..evaluate('globalThis.__retained = { value: 42 };'));
            await ctx.sample(batch, activeRuntimes: kept.length);
          }
        } finally {
          for (final engine in kept) {
            engine.dispose();
          }
        }
      },
    );
