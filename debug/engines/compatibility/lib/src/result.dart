import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Outcome of one conformance test.
///
/// The four states are deliberately strict:
/// * [pass]: the test ran and its assertions passed.
/// * [fail]: the test ran and its assertions failed, or NativaX does not
///   implement the behavior under test.
/// * [skip]: the test was not executed because either the suite feature is
///   explicitly out of scope or the runner cannot execute it (for example a
///   Test262 module test, because the FFI bridge only evaluates global
///   scripts). A skip is never evidence of compatibility.
/// * [error]: the runner broke while executing the test (I/O, harness bug,
///   native crash).
enum ResultStatus {
  pass('PASS'),
  fail('FAIL'),
  skip('SKIP'),
  error('ERROR');

  const ResultStatus(this.label);
  final String label;

  static ResultStatus parse(String value) => ResultStatus.values.firstWhere(
        (s) => s.name == value.toLowerCase(),
        orElse: () => ResultStatus.error,
      );
}

class TestResult {
  const TestResult({
    required this.suite,
    required this.id,
    required this.status,
    this.reason,
    this.detail,
    this.features = const [],
    this.durationMs = 0,
    this.extra = const {},
  });

  factory TestResult.fromJson(Map<String, Object?> json) => TestResult(
        suite: json['suite'] as String? ?? '',
        id: json['id'] as String? ?? '',
        status: ResultStatus.parse(json['status'] as String? ?? 'error'),
        reason: json['reason'] as String?,
        detail: json['detail'] as String?,
        features:
            (json['features'] as List?)?.cast<String>() ?? const <String>[],
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        extra: (json['extra'] as Map?)?.cast<String, Object?>() ?? const {},
      );

  final String suite;
  final String id;
  final ResultStatus status;

  /// Short explanation for SKIP/FAIL/ERROR.
  final String? reason;

  /// Longer diagnostic (stack, expected vs actual).
  final String? detail;

  /// Test262 `features` metadata, or an inferred feature label.
  final List<String> features;
  final int durationMs;
  final Map<String, Object?> extra;

  Map<String, Object?> toJson() => {
        'suite': suite,
        'id': id,
        'status': status.name,
        if (reason != null) 'reason': reason,
        if (detail != null) 'detail': detail,
        'features': features,
        'durationMs': durationMs,
        if (extra.isNotEmpty) 'extra': extra,
      };

  @override
  String toString() => '[${status.label}] $suite/$id'
      '${reason == null ? '' : ' — $reason'}';
}

/// Aggregated view of a run. Counts are per test, not per assertion.
class RunSummary {
  RunSummary({
    required this.suite,
    required this.startedAt,
    required this.durationMs,
    required this.results,
    this.suiteCommit,
    this.suiteVersion,
    this.command,
  });

  factory RunSummary.fromJson(Map<String, Object?> json) => RunSummary(
        suite: json['suite'] as String? ?? '',
        startedAt:
            DateTime.tryParse(json['startedAt'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        results: (json['results'] as List? ?? const [])
            .map((e) => TestResult.fromJson((e as Map).cast<String, Object?>()))
            .toList(),
        suiteCommit: json['suiteCommit'] as String?,
        suiteVersion: json['suiteVersion'] as String?,
        command: json['command'] as String?,
      );

  /// Loads a run from a summary file.
  ///
  /// Current summaries are metadata-only and point at a sibling JSONL through
  /// `resultsFile`; historical summaries embed the full `results` array. Both
  /// forms load into the same [RunSummary], so baselines keep working across
  /// the format change. If a summary declares `resultsFile` but the file is
  /// missing or broken, this returns null instead of fabricating an empty
  /// baseline that would report every test as new.
  static RunSummary? load(File summaryFile) {
    try {
      final raw = jsonDecode(summaryFile.readAsStringSync());
      if (raw is! Map) return null;
      final json = raw.cast<String, Object?>();
      final inline = json['results'];
      if (inline is List && inline.isNotEmpty) {
        return RunSummary.fromJson(json);
      }
      final declared = json['resultsFile'] as String?;
      final name = declared ??
          p.basename(summaryFile.path).replaceFirst(
              RegExp(r'\.summary\.json$'), '.jsonl');
      final resultsFile =
          File(p.join(summaryFile.parent.path, p.basename(name)));
      if (!resultsFile.existsSync()) {
        return declared == null ? RunSummary.fromJson(json) : null;
      }
      final results = <Map<String, Object?>>[];
      for (final line in resultsFile.readAsLinesSync()) {
        if (line.trim().isEmpty) continue;
        results.add((jsonDecode(line) as Map).cast<String, Object?>());
      }
      return RunSummary.fromJson({...json, 'results': results});
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    } on TypeError {
      return null;
    }
  }

  final String suite;
  final DateTime startedAt;
  final int durationMs;

  /// Commit/revision of the external suite checkout.
  final String? suiteCommit;

  /// Human-readable version (for example Test262 `version.txt`).
  final String? suiteVersion;
  final String? command;
  final List<TestResult> results;

  int count(ResultStatus status) =>
      results.where((r) => r.status == status).length;

  int get total => results.length;
  int get passed => count(ResultStatus.pass);
  int get failed => count(ResultStatus.fail);
  int get skipped => count(ResultStatus.skip);
  int get errors => count(ResultStatus.error);

  /// Percentage of executed tests that passed (skips excluded).
  double get passRate {
    final executed = total - skipped;
    return executed == 0 ? 0 : passed * 100 / executed;
  }

  Map<String, int> get byStatus => {
        for (final s in ResultStatus.values) s.label: count(s),
      };

  /// Feature coverage: each feature counts every test that declares it.
  Map<String, FeatureStats> get byFeature {
    final out = <String, FeatureStats>{};
    for (final r in results) {
      final names = r.features.isEmpty ? const ['core'] : r.features;
      for (final f in names) {
        out.putIfAbsent(f, FeatureStats.new).add(r.status);
      }
    }
    return out;
  }

  Map<String, FeatureStats> get byDirectory {
    final out = <String, FeatureStats>{};
    for (final r in results) {
      final parts = r.id.split('/');
      final key = parts.length <= 2
          ? parts.join('/')
          : parts.take(3).join('/');
      out.putIfAbsent(key.isEmpty ? '(root)' : key, FeatureStats.new)
          .add(r.status);
    }
    return out;
  }

  /// Run-level metadata.
  ///
  /// `includeResults: false` is the canonical summary on disk: per-test rows
  /// live once in the JSONL named by `resultsFile`, not duplicated here.
  Map<String, Object?> toJson({
    bool includeResults = true,
    String? resultsFile,
  }) =>
      {
        'suite': suite,
        'startedAt': startedAt.toIso8601String(),
        'durationMs': durationMs,
        if (suiteCommit != null) 'suiteCommit': suiteCommit,
        if (suiteVersion != null) 'suiteVersion': suiteVersion,
        if (command != null) 'command': command,
        'counts': byStatus,
        'total': total,
        'passRate': passRate,
        if (resultsFile != null) 'resultsFile': resultsFile,
        if (includeResults) 'results': [for (final r in results) r.toJson()],
      };

  String toJsonString({
    bool includeResults = true,
    String? resultsFile,
  }) =>
      const JsonEncoder.withIndent('  ').convert(
          toJson(includeResults: includeResults, resultsFile: resultsFile));
}

class FeatureStats {
  int passed = 0;
  int failed = 0;
  int skipped = 0;
  int errored = 0;

  int get total => passed + failed + skipped + errored;

  void add(ResultStatus status) {
    switch (status) {
      case ResultStatus.pass:
        passed++;
      case ResultStatus.fail:
        failed++;
      case ResultStatus.skip:
        skipped++;
      case ResultStatus.error:
        errored++;
    }
  }

  double get passRate {
    final executed = total - skipped;
    return executed == 0 ? 0 : passed * 100 / executed;
  }
}
