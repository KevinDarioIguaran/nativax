import 'package:nativa_js/nativa_js.dart' show JscEngine;

import 'analysis.dart';
import 'model.dart';

class LeakRunner {
  /// Leak runs measure the engine heap with JavaScriptCore's JIT off:
  /// compiled code and its metadata grow over the first batches as the JIT
  /// tiers up, which reads as heap growth (measured: +80 KB over four
  /// batches with the JIT, flat without). It only applies when no engine
  /// exists yet in this process.
  LeakRunner(this.profile, {this.onProgress}) {
    JscEngine.configure(const {'useJIT': 'false'});
  }

  final LeakProfile profile;
  final void Function(String id, int index, int total)? onProgress;

  Future<List<LeakResult>> run(List<LeakCase> cases) async {
    final results = <LeakResult>[];
    for (var i = 0; i < cases.length; i++) {
      final test = cases[i];
      onProgress?.call(test.id, i + 1, cases.length);
      final context = LeakContext(profile);
      final watch = Stopwatch()..start();
      LeakResult result;
      try {
        await test.run(context);
        watch.stop();
        result = analyzeLeak(test, context, watch.elapsedMilliseconds);
      } on LeakLimitException catch (error) {
        watch.stop();
        result = LeakResult(
          id: test.id,
          subsystem: test.subsystem,
          scenario: test.scenario,
          expectation: test.expectation,
          status: LeakStatus.skip,
          reason: 'safety limit: ${error.message}',
          samples: context.samples,
          durationMs: watch.elapsedMilliseconds,
          truth: test.truth,
        );
      } catch (error, stack) {
        watch.stop();
        result = LeakResult(
          id: test.id,
          subsystem: test.subsystem,
          scenario: test.scenario,
          expectation: test.expectation,
          status: LeakStatus.error,
          reason: 'runner error: $error',
          samples: context.samples,
          durationMs: watch.elapsedMilliseconds,
          evidence: ['$stack'],
          truth: test.truth,
        );
      }
      results.add(result);
    }
    return results;
  }
}
