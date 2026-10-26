import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'html5lib_runner.dart';
import 'html_tree_runner.dart';
import 'result.dart';
import 'test262_runner.dart';
import 'url_runner.dart';
import 'wpt_runner.dart';
import 'wpt_shim.dart';

/// One hand-verified expectation from
/// `debug/datasets/compatibility/expected.json`.
class ExpectedOutcome {
  const ExpectedOutcome({
    required this.suite,
    required this.id,
    required this.expected,
    required this.why,
  });

  final String suite;
  final String id;
  final ResultStatus expected;
  final String why;
}

List<ExpectedOutcome> loadExpectedOutcomes(String path) {
  final data = (jsonDecode(File(path).readAsStringSync()) as Map)
      .cast<String, Object?>();
  return [
    for (final raw in (data['cases'] as List).cast<Map>())
      ExpectedOutcome(
        suite: raw['suite'] as String,
        id: raw['id'] as String,
        expected: _strictStatus(raw['expected'] as String),
        why: raw['why'] as String? ?? '',
      ),
  ];
}

ResultStatus _strictStatus(String label) {
  for (final s in ResultStatus.values) {
    if (s.label == label) return s;
  }
  throw FormatException('unknown expected status: $label');
}

class ValidationRow {
  const ValidationRow(this.expectation, this.actual, this.reason);
  final ExpectedOutcome expectation;

  /// `null` when the runner produced no result for this id.
  final ResultStatus? actual;
  final String? reason;
  bool get correct => actual == expectation.expected;
}

class SuiteValidation {
  SuiteValidation(this.suite);
  final String suite;
  final rows = <ValidationRow>[];

  /// Results that have no expectation (an id typo or a new fixture case).
  final unexpected = <TestResult>[];

  int get total => rows.length;
  int get correct => rows.where((r) => r.correct).length;
  int get missing => rows.where((r) => r.actual == null).length;

  /// Correct verdicts over expectations. Results without an expectation do
  /// not raise the score; they are listed and make [perfect] false.
  double get accuracy => total == 0 ? 0 : correct * 100 / total;
  bool get perfect => correct == total && unexpected.isEmpty;
}

class ValidationReport {
  ValidationReport(this.suites);
  final Map<String, SuiteValidation> suites;

  int get total => suites.values.fold(0, (a, s) => a + s.total);
  int get correct => suites.values.fold(0, (a, s) => a + s.correct);
  double get accuracy => total == 0 ? 0 : correct * 100 / total;
  bool get perfect => suites.values.every((s) => s.perfect);
  List<ValidationRow> get mismatches => [
        for (final s in suites.values) ...s.rows.where((r) => !r.correct),
      ];

  /// True when [broken] gets wrong at least one case that this report gets
  /// right, i.e. the damage is visible against the real runners.
  bool detects(ValidationReport broken) {
    final right = {
      for (final r in suites.values.expand((s) => s.rows))
        if (r.correct) '${r.expectation.suite}\u0000${r.expectation.id}',
    };
    return broken.mismatches.any(
        (r) => right.contains('${r.expectation.suite}\u0000${r.expectation.id}'));
  }

  /// Confusion counts `expected -> actual` over every expectation.
  Map<String, int> get confusion {
    final out = <String, int>{};
    for (final s in suites.values) {
      for (final r in s.rows) {
        final key = '${r.expectation.expected.label}->${r.actual?.label ?? 'MISSING'}';
        out[key] = (out[key] ?? 0) + 1;
      }
    }
    return out;
  }

  String renderMarkdown({String title = 'Runner validation'}) {
    final b = StringBuffer()
      ..writeln('# $title')
      ..writeln()
      ..writeln('| Suite | Cases | Correct | Missing | Unexpected | Accuracy |')
      ..writeln('|---|---:|---:|---:|---:|---:|');
    for (final s in suites.values) {
      b.writeln('| ${s.suite} | ${s.total} | ${s.correct} | ${s.missing} | '
          '${s.unexpected.length} | ${s.accuracy.toStringAsFixed(1)} % |');
    }
    b
      ..writeln('| **all** | $total | $correct | | | '
          '${accuracy.toStringAsFixed(1)} % |')
      ..writeln();
    final wrong = mismatches;
    if (wrong.isNotEmpty) {
      b
        ..writeln('| Suite | Case | Expected | Actual | Runner reason |')
        ..writeln('|---|---|---|---|---|');
      for (final r in wrong) {
        b.writeln('| ${r.expectation.suite} | `${_cell(r.expectation.id)}` | '
            '${r.expectation.expected.label} | ${r.actual?.label ?? 'MISSING'} | '
            '${_cell(r.reason ?? '')} |');
      }
      b.writeln();
    }
    for (final s in suites.values) {
      for (final u in s.unexpected) {
        b.writeln('- unexpected result `${_cell(u.id)}` in ${s.suite}: '
            '${u.status.label}');
      }
    }
    return b.toString();
  }

  Map<String, Object?> toJson() => {
        'total': total,
        'correct': correct,
        'accuracy': accuracy,
        'confusion': confusion,
        'suites': {
          for (final s in suites.values)
            s.suite: {
              'total': s.total,
              'correct': s.correct,
              'missing': s.missing,
              'unexpected': [for (final u in s.unexpected) u.id],
              'accuracy': s.accuracy,
            },
        },
        'mismatches': [
          for (final r in mismatches)
            {
              'suite': r.expectation.suite,
              'id': r.expectation.id,
              'expected': r.expectation.expected.label,
              'actual': r.actual?.label,
              'reason': r.reason,
            },
        ],
      };

  static String _cell(String v) =>
      v.replaceAll('|', '\\|').replaceAll('\n', ' ').replaceAll('\r', ' ');
}

/// Compares runner output with the hand-verified expectations. Only suites
/// that have expectations are scored.
ValidationReport validateRuns(
  List<RunSummary> runs,
  List<ExpectedOutcome> expectations,
) {
  final suites = <String, SuiteValidation>{};
  for (final e in expectations) {
    suites.putIfAbsent(e.suite, () => SuiteValidation(e.suite));
  }
  final actual = <String, TestResult>{};
  for (final run in runs) {
    for (final r in run.results) {
      actual['${run.suite}\u0000${r.id}'] = r;
    }
  }
  final expectedKeys = <String>{};
  for (final e in expectations) {
    final key = '${e.suite}\u0000${e.id}';
    expectedKeys.add(key);
    final r = actual[key];
    suites[e.suite]!.rows.add(ValidationRow(e, r?.status, r?.reason));
  }
  for (final run in runs) {
    final s = suites[run.suite];
    if (s == null) continue;
    for (final r in run.results) {
      if (!expectedKeys.contains('${run.suite}\u0000${r.id}')) {
        s.unexpected.add(r);
      }
    }
  }
  return ValidationReport(suites);
}

/// Layout of the committed validation subset.
class ValidationDataset {
  ValidationDataset(this.root);

  /// `debug/datasets/compatibility`.
  final String root;

  String get expectedPath => p.join(root, 'expected.json');
  String get test262 => p.join(root, 'suites', 'test262');
  String get html5lib => p.join(root, 'suites', 'html5lib-tests');
  String get wpt => p.join(root, 'suites', 'wpt');

  static String inRepo(String repoRoot) =>
      p.join(repoRoot, 'debug', 'datasets', 'compatibility');
}

/// Runs every runner on the validation subset. [test262Suite] and
/// [wptHarness] let the broken-adapter checks swap in a damaged harness.
Future<List<RunSummary>> runValidationSubset(
  ValidationDataset data, {
  String? test262Suite,
  String wptHarness = wptShim,
  Duration timeout = const Duration(milliseconds: 1500),
}) async {
  return [
    await Test262Runner(Test262RunOptions(
      suitePath: test262Suite ?? data.test262,
      directories: const ['test/validation'],
      timeout: timeout,
    )).run(),
    await Html5libRunner(Html5libRunOptions(suitePath: data.html5lib)).run(),
    await UrlRunner(UrlRunOptions(suitePath: data.wpt)).run(),
    await HtmlTreeRunner(HtmlTreeRunOptions(suitePath: data.wpt)).run(),
    await WptRunner(WptRunOptions(
      suitePath: data.wpt,
      directories: const ['validation'],
      timeout: timeout,
      harnessSource: wptHarness,
    )).run(),
  ];
}

/// A deliberately broken adapter: it rewrites what a runner reported.
class BrokenAdapter {
  const BrokenAdapter(this.name, this.description, this.apply);
  final String name;
  final String description;
  final RunSummary Function(RunSummary) apply;
}

RunSummary _map(RunSummary s, TestResult? Function(TestResult) f) => RunSummary(
      suite: s.suite,
      startedAt: s.startedAt,
      durationMs: s.durationMs,
      results: [
        for (final r in s.results)
          if (f(r) case final mapped?) mapped,
      ],
      suiteCommit: s.suiteCommit,
      suiteVersion: s.suiteVersion,
      command: s.command,
    );

TestResult _as(TestResult r, ResultStatus status) => TestResult(
      suite: r.suite,
      id: r.id,
      status: status,
      reason: r.reason,
      detail: r.detail,
      features: r.features,
      durationMs: r.durationMs,
    );

ResultStatus Function(ResultStatus) _remap(ResultStatus from, ResultStatus to) =>
    (s) => s == from ? to : s;

final brokenAdapters = <BrokenAdapter>[
  BrokenAdapter('always-pass', 'every result is reported as PASS',
      (s) => _map(s, (r) => _as(r, ResultStatus.pass))),
  BrokenAdapter('skip-as-pass', 'SKIP is counted as PASS', (s) {
    final f = _remap(ResultStatus.skip, ResultStatus.pass);
    return _map(s, (r) => _as(r, f(r.status)));
  }),
  BrokenAdapter('fail-as-skip', 'FAIL is hidden as SKIP', (s) {
    final f = _remap(ResultStatus.fail, ResultStatus.skip);
    return _map(s, (r) => _as(r, f(r.status)));
  }),
  BrokenAdapter('error-as-fail', 'harness ERROR is reported as FAIL', (s) {
    final f = _remap(ResultStatus.error, ResultStatus.fail);
    return _map(s, (r) => _as(r, f(r.status)));
  }),
  BrokenAdapter('drop-failures', 'FAIL results are silently dropped',
      (s) => _map(s, (r) => r.status == ResultStatus.fail ? null : r)),
];

/// A Test262 harness whose assertions never throw. Every assertion-based
/// FAIL must turn into a PASS, which the validation has to catch.
const noopTest262Assert = '''
function assert() {}
assert._isSameValue = function () { return true; };
assert.sameValue = function () {};
assert.notSameValue = function () {};
assert.throws = function () {};
''';

/// A WPT harness whose `test()` reports PASS without running the body.
const alwaysPassWptHarness = '''
$wptShim
globalThis.test = (a, b) => {
  const name = typeof a === 'string' ? a : (typeof b === 'string' ? b : '');
  __nx.host('wpt.result', name, 'PASS', '');
};
''';

/// Copies the validation Test262 tree into [target] with [noopTest262Assert]
/// as `harness/assert.js`.
String writeBrokenTest262(ValidationDataset data, String target) {
  void copy(Directory from, Directory to) {
    to.createSync(recursive: true);
    for (final e in from.listSync()) {
      final dest = p.join(to.path, p.basename(e.path));
      if (e is Directory) {
        copy(e, Directory(dest));
      } else if (e is File) {
        e.copySync(dest);
      }
    }
  }

  copy(Directory(data.test262), Directory(target));
  File(p.join(target, 'harness', 'assert.js'))
      .writeAsStringSync(noopTest262Assert);
  return target;
}
