/// Accuracy audit of `compareRuns` (regression / improvement / noise) on
/// synthetic samples with a known true change, and writes
/// `debug/datasets/microbenchmarks/audit.json`.
///
///   dart run tool/audit_comparator.dart [out.json]
///
/// Ground truth: a true change larger than the threshold (10 %) must be
/// reported with its sign; a true change of at most 5 % must be `noise`.
/// Changes in (5, 10] % are reported but not scored (inside the threshold's
/// grey zone). Samples are deterministic: base 10 ms, multiplicative noise
/// with the given coefficient of variation from a fixed LCG, 15 rounds.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:nativa_benchmark/benchmark.dart';

const shifts = [
  -50.0,
  -30.0,
  -20.0,
  -15.0,
  -10.0,
  -5.0,
  0.0,
  5.0,
  10.0,
  15.0,
  20.0,
  30.0,
  50.0,
];
const noiseCvs = [1.0, 3.0, 5.0, 10.0, 20.0];
const repeats = 200;
const rounds = 15;

class _Lcg {
  _Lcg(this.state);
  int state;
  double next() {
    state =
        (state * 6364136223846793005 + 1442695040888963407) &
        0x7fffffffffffffff;
    return (state >> 11) / (1 << 52);
  }

  /// Standard normal (Box–Muller).
  double gauss() {
    final u = math.max(next(), 1e-12), v = next();
    return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
  }
}

List<double> _samples(_Lcg rng, double median, double cv) => [
  for (var i = 0; i < rounds; i++) median * math.exp(cv / 100 * rng.gauss()),
];

RunReport _run(List<double> samples) => RunReport(
  metadata: RunMetadata.fromJson(const {}),
  command: 'synthetic',
  results: [
    BenchmarkResult(
      name: 'synthetic',
      category: 'audit',
      unit: 'ops',
      operations: 1,
      rounds: rounds,
      warmup: 0,
      samplesMs: samples,
      checksum: 0,
    ),
  ],
);

String? _truth(double shift) => shift.abs() > 10
    ? (shift > 0 ? 'regression' : 'improvement')
    : shift.abs() <= 5
    ? 'noise'
    : null;

void main(List<String> args) {
  final out = args.isNotEmpty
      ? args.first
      : '${Directory.current.path}/../../datasets/microbenchmarks/audit.json';
  final rng = _Lcg(20261026);
  final cells = <Map<String, Object?>>[];
  var falseAlarms = 0,
      nullTrials = 0,
      detected = 0,
      realTrials = 0,
      signErrors = 0;
  for (final cv in noiseCvs) {
    for (final shift in shifts) {
      final counts = <String, int>{};
      for (var r = 0; r < repeats; r++) {
        final before = _run(_samples(rng, 10, cv));
        final after = _run(_samples(rng, 10 * (1 + shift / 100), cv));
        final status = compareRuns(before, after).single.status;
        counts[status] = (counts[status] ?? 0) + 1;
      }
      final truth = _truth(shift);
      final correct = truth == null ? null : (counts[truth] ?? 0);
      if (truth == 'noise') {
        nullTrials += repeats;
        falseAlarms += repeats - correct!;
      } else if (truth != null) {
        realTrials += repeats;
        detected += correct!;
        signErrors +=
            counts[truth == 'regression' ? 'improvement' : 'regression'] ?? 0;
      }
      cells.add({
        'noiseCvPct': cv,
        'trueChangePct': shift,
        'truth': truth,
        'counts': counts,
        'correctRate': correct == null ? null : correct / repeats,
      });
    }
  }
  final audit = {
    'schema': 'nativa_benchmark.comparator_audit/1',
    'defaults': {'thresholdPct': 10, 'noiseMultiplier': 2},
    'rounds': rounds,
    'repeatsPerCell': repeats,
    'seed': 20261026,
    'falseAlarmRate': falseAlarms / nullTrials,
    'detectionRate': detected / realTrials,
    'signErrors': signErrors,
    'cells': cells,
  };
  File(out)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(audit)}\n',
    );
  stdout.writeln(
    'false alarms ${(100 * falseAlarms / nullTrials).toStringAsFixed(2)} % '
    '($falseAlarms/$nullTrials), detection ${(100 * detected / realTrials).toStringAsFixed(2)} % '
    '($detected/$realTrials), sign errors $signErrors -> $out',
  );
  for (final cv in noiseCvs) {
    final row = cells.where((c) => c['noiseCvPct'] == cv).map((c) {
      final r = c['correctRate'] as double?;
      return '${c['trueChangePct']}:${r == null ? '-' : (r * 100).round()}';
    });
    stdout.writeln('cv $cv%: ${row.join(' ')}');
  }
}
