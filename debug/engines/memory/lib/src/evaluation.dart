import 'analysis.dart';
import 'classification.dart';
import 'model.dart';

/// Predicted label of a result: its class, or `error`/`skip` when the case
/// produced no classification.
String predictedLabel(LeakResult r) =>
    r.classification?.leakClass.label ?? r.status.name;

const _alarmClasses = {'proven_leak', 'suspected_leak'};

class BinaryCounts {
  BinaryCounts();
  int tp = 0;
  int fp = 0;
  int fn = 0;
  int tn = 0;

  double? get precision => tp + fp == 0 ? null : tp / (tp + fp);
  double? get recall => tp + fn == 0 ? null : tp / (tp + fn);

  /// False positives over all negatives.
  double? get falseAlarmRate => fp + tn == 0 ? null : fp / (fp + tn);

  void add({required bool truth, required bool predicted}) {
    if (truth && predicted) {
      tp++;
    } else if (truth) {
      fn++;
    } else if (predicted) {
      fp++;
    } else {
      tn++;
    }
  }

  Map<String, Object?> toJson() => {
    'tp': tp,
    'fp': fp,
    'fn': fn,
    'tn': tn,
    'precision': precision,
    'recall': recall,
    'falseAlarmRate': falseAlarmRate,
  };
}

class CaseStability {
  CaseStability(this.id, this.expected, this.leaks);
  final String id;
  final String expected;
  final bool leaks;
  final List<String> classes = [];
  final List<String> legacy = [];

  bool get stable => classes.toSet().length <= 1;
  int get correct => classes.where((c) => c == expected).length;

  Map<String, Object?> toJson() => {
    'id': id,
    'expected': expected,
    'leaks': leaks,
    'classes': classes,
    'legacyStatuses': legacy,
    'stable': stable,
    'correct': correct,
  };
}

class LeakEvaluation {
  LeakEvaluation({required this.runs});

  final int runs;
  int observations = 0;
  int exact = 0;

  /// expected class -> predicted label -> count.
  final Map<String, Map<String, int>> confusion = {};

  /// Positive class `proven_leak`, against the expected class.
  final BinaryCounts proven = BinaryCounts();

  /// Alarm (`proven_leak` or `suspected_leak`) against construction truth.
  final BinaryCounts alarm = BinaryCounts();

  /// `proven_leak` against construction truth.
  final BinaryCounts provenVsTruth = BinaryCounts();

  /// Legacy `FAIL` against construction truth.
  final BinaryCounts legacyFail = BinaryCounts();
  final Map<String, CaseStability> cases = {};

  double get accuracy => observations == 0 ? 0 : exact / observations;
  int get stableCases => cases.values.where((c) => c.stable).length;

  Map<String, Object?> toJson() => {
    'runs': runs,
    'observations': observations,
    'exactMatches': exact,
    'accuracy': accuracy,
    'labels': classLabels,
    'confusion': confusion,
    'provenLeakVsExpected': proven.toJson(),
    'alarmVsConstructionTruth': alarm.toJson(),
    'provenLeakVsConstructionTruth': provenVsTruth.toJson(),
    'legacyFailVsConstructionTruth': legacyFail.toJson(),
    'stableCases': stableCases,
    'cases': [for (final c in cases.values) c.toJson()],
  };
}

final classLabels = [
  for (final c in LeakClass.values) c.label,
  'error',
  'skip',
];

/// Scores every result that carries a ground truth. Results without truth
/// (product cases) are ignored.
LeakEvaluation evaluateLeakRuns(List<LeakRun> runs) {
  final e = LeakEvaluation(runs: runs.length);
  for (final run in runs) {
    for (final r in run.results) {
      final truth = r.truth;
      if (truth == null) continue;
      final predicted = predictedLabel(r);
      e.observations++;
      if (predicted == truth.expected) e.exact++;
      final row = e.confusion.putIfAbsent(truth.expected, () => {});
      row[predicted] = (row[predicted] ?? 0) + 1;
      e.proven.add(
        truth: truth.expected == 'proven_leak',
        predicted: predicted == 'proven_leak',
      );
      e.alarm.add(
        truth: truth.leaks,
        predicted: _alarmClasses.contains(predicted),
      );
      e.provenVsTruth.add(
        truth: truth.leaks,
        predicted: predicted == 'proven_leak',
      );
      e.legacyFail.add(
        truth: truth.leaks,
        predicted: r.status == LeakStatus.fail,
      );
      e.cases.putIfAbsent(
          r.id,
          () => CaseStability(r.id, truth.expected, truth.leaks),
        )
        ..classes.add(predicted)
        ..legacy.add(r.status.label);
    }
  }
  return e;
}

String renderLeakEvaluation(LeakEvaluation e, {String title = ''}) {
  String pct(double? v) =>
      v == null ? 'n/a' : '${(v * 100).toStringAsFixed(1)} %';
  String counts(BinaryCounts c) =>
      'TP ${c.tp}, FP ${c.fp}, FN ${c.fn}, TN ${c.tn}; precision '
      '${pct(c.precision)}, recall ${pct(c.recall)}, false-alarm rate '
      '${pct(c.falseAlarmRate)}';
  final used = classLabels
      .where(
        (l) =>
            e.confusion.containsKey(l) ||
            e.confusion.values.any((row) => (row[l] ?? 0) > 0),
      )
      .toList();
  final b = StringBuffer()
    ..writeln(
      '# Memory classifier evaluation${title.isEmpty ? '' : ' — $title'}',
    )
    ..writeln()
    ..writeln('- Runs: ${e.runs}; observations: ${e.observations}')
    ..writeln(
      '- Exact class matches: ${e.exact}/${e.observations} '
      '(${pct(e.accuracy)})',
    )
    ..writeln('- `proven_leak` vs expected class: ${counts(e.proven)}')
    ..writeln(
      '- Alarm (`proven_leak` or `suspected_leak`) vs construction '
      'truth: ${counts(e.alarm)}',
    )
    ..writeln(
      '- `proven_leak` vs construction truth: '
      '${counts(e.provenVsTruth)}',
    )
    ..writeln(
      '- Legacy `FAIL` vs construction truth: '
      '${counts(e.legacyFail)}',
    )
    ..writeln(
      '- Cases with the same class in every run: '
      '${e.stableCases}/${e.cases.length}',
    )
    ..writeln()
    ..writeln('## Confusion matrix (rows: expected, columns: predicted)')
    ..writeln()
    ..writeln('| expected \\ predicted | ${used.join(' | ')} |')
    ..writeln('|---|${used.map((_) => '---:').join('|')}|');
  for (final row in used.where(e.confusion.containsKey)) {
    b.writeln(
      '| $row | '
      '${used.map((c) => e.confusion[row]![c] ?? 0).join(' | ')} |',
    );
  }
  b
    ..writeln()
    ..writeln('## Per case')
    ..writeln()
    ..writeln('| Case | Leaks | Expected | Classes per run | Legacy | Stable |')
    ..writeln('|---|---|---|---|---|---|');
  for (final c in e.cases.values) {
    b.writeln(
      '| `${c.id}` | ${c.leaks ? 'yes' : 'no'} | ${c.expected} | '
      '${c.classes.join(', ')} | ${c.legacy.join(', ')} | '
      '${c.stable ? 'yes' : 'no'} |',
    );
  }
  return b.toString();
}
