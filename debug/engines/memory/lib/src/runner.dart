import 'analysis.dart';
import 'model.dart';

class LeakRunner {
  LeakRunner(this.profile, {this.onProgress});

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
        );
      }
      results.add(result);
    }
    return results;
  }
}
