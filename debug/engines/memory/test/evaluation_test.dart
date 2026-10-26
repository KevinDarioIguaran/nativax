import 'package:nativa_leaks/leaks.dart';
import 'package:test/test.dart';

LeakResult _result(
  String id,
  String expected,
  bool leaks,
  LeakClass? cls, {
  LeakStatus status = LeakStatus.pass,
}) => LeakResult(
  id: id,
  subsystem: 'audit',
  scenario: 'synthetic',
  expectation: 'released',
  status: cls == null ? LeakStatus.error : status,
  reason: '',
  samples: const [],
  durationMs: 1,
  truth: LeakTruth(leaks: leaks, expected: expected, rationale: ''),
  classification: cls == null
      ? null
      : LeakClassification(
          leakClass: cls,
          reason: '',
          primaryChannel: null,
          criteria: const {},
          channels: const [],
          peakRssBytes: 0,
          retainedRssBytes: 0,
          explicitRelease: true,
        ),
);

LeakRun _run(List<LeakResult> results) =>
    LeakRun(metadata: LeakRunMetadata.fromJson(const {}), results: results);

void main() {
  test('dataset cases all carry a valid, unique ground truth', () {
    final cases = auditLeakCases();
    expect(cases, hasLength(16));
    expect(cases.map((c) => c.id).toSet(), hasLength(16));
    final labels = LeakClass.values.map((c) => c.label).toSet();
    for (final c in cases) {
      expect(c.id, startsWith('audit.'));
      expect(c.truth, isNotNull, reason: c.id);
      expect(labels, contains(c.truth!.expected), reason: c.id);
      expect(c.truth!.leaks, c.id.startsWith('audit.leak.'), reason: c.id);
    }
    // The dataset never leaks into the product suite.
    expect(
      cases.map((c) => c.id).toSet().intersection({
        for (final c in matrixLeakCases()) c.id,
      }),
      isEmpty,
    );
  });

  test('scores confusion, proven precision/recall, alarms and stability', () {
    final runs = [
      _run([
        _result(
          'a',
          'proven_leak',
          true,
          LeakClass.provenLeak,
          status: LeakStatus.fail,
        ),
        _result('b', 'proven_leak', true, LeakClass.suspectedLeak),
        _result(
          'c',
          'no_leak',
          false,
          LeakClass.noLeak,
          status: LeakStatus.fail,
        ),
        _result('d', 'bounded_high_usage', false, LeakClass.provenLeak),
      ]),
      _run([
        _result('a', 'proven_leak', true, LeakClass.provenLeak),
        _result('b', 'proven_leak', true, null),
        _result('c', 'no_leak', false, LeakClass.noLeak),
        _result('d', 'bounded_high_usage', false, LeakClass.boundedHighUsage),
      ]),
    ];
    final e = evaluateLeakRuns(runs);
    expect(e.observations, 8);
    expect(e.exact, 5);
    expect(e.confusion['proven_leak'], {
      'proven_leak': 2,
      'suspected_leak': 1,
      'error': 1,
    });
    expect(e.confusion['bounded_high_usage'], {
      'proven_leak': 1,
      'bounded_high_usage': 1,
    });
    expect(e.proven.tp, 2);
    expect(e.proven.fp, 1);
    expect(e.proven.fn, 2);
    expect(e.proven.precision, closeTo(2 / 3, 1e-12));
    expect(e.proven.recall, 0.5);
    // Alarms vs construction truth: a, a, b(suspected) hit; d false alarm.
    expect(e.alarm.tp, 3);
    expect(e.alarm.fn, 1);
    expect(e.alarm.fp, 1);
    expect(e.alarm.tn, 3);
    expect(e.legacyFail.fp, 1);
    expect(e.legacyFail.tp, 1);
    expect(e.stableCases, 2);
    expect(e.cases['b']!.classes, ['suspected_leak', 'error']);
    final md = renderLeakEvaluation(e);
    expect(md, contains('| proven_leak | 2 | 1 |'));
    expect(md, contains('Cases with the same class in every run: 2/4'));
  });

  test(
    'real engine: counter leaks are proven and balanced churn is not',
    () async {
      const profile = LeakProfile(
        name: 'test',
        batches: 5,
        iterations: 200,
        settle: Duration.zero,
      );
      final wanted = {
        'audit.leak.listeners_retained': LeakClass.provenLeak,
        'audit.leak.timers_unbounded': LeakClass.provenLeak,
        'audit.leak.js_global_array': LeakClass.provenLeak,
        'audit.control.listeners_balanced': LeakClass.noLeak,
        'audit.control.alloc_release': LeakClass.noLeak,
        'audit.control.bounded_wrapper_pool': LeakClass.boundedHighUsage,
        'audit.control.grow_then_release': LeakClass.boundedHighUsage,
        'audit.leak.too_few': LeakClass.inconclusive,
      };
      final cases = auditLeakCases()
          .where((c) => wanted.containsKey(c.id))
          .toList();
      final results = await LeakRunner(profile).run(cases);
      for (final r in results) {
        expect(
          r.classification?.leakClass,
          wanted[r.id],
          reason: '${r.id}: ${r.classification?.reason ?? r.reason}',
        );
        expect(r.samples.last.release, isTrue, reason: r.id);
      }
    },
  );
}
