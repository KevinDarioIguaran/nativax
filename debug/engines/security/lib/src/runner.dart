import 'model.dart';

class SecurityRunner {
  SecurityRunner({this.onProgress});
  final void Function(String id, int index, int total)? onProgress;

  Future<List<SecurityResult>> run(List<SecurityCase> cases) async {
    final results = <SecurityResult>[];
    for (var i = 0; i < cases.length; i++) {
      final test = cases[i];
      onProgress?.call(test.id, i + 1, cases.length);
      final watch = Stopwatch()..start();
      try {
        final check = await test.run();
        watch.stop();
        results.add(
          SecurityResult(
            id: test.id,
            category: test.category,
            severity: test.severity,
            description: test.description,
            status: check.status,
            expected: check.expected,
            observed: check.observed,
            durationMs: watch.elapsedMilliseconds,
            evidence: check.evidence,
            remediation: check.remediation,
          ),
        );
      } catch (error, stack) {
        watch.stop();
        results.add(
          SecurityResult(
            id: test.id,
            category: test.category,
            severity: test.severity,
            description: test.description,
            status: SecurityStatus.error,
            expected: 'controlled result',
            observed: 'runner error: $error',
            durationMs: watch.elapsedMilliseconds,
            evidence: ['$stack'],
          ),
        );
      }
    }
    return results;
  }
}
