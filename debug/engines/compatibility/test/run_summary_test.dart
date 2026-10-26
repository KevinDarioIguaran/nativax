import 'dart:convert';
import 'dart:io';

import 'package:nativa_conformance/conformance.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

RunSummary _summary() => RunSummary(
      suite: 'wpt',
      startedAt: DateTime.utc(2026, 10, 25, 12),
      durationMs: 42,
      command: 'run_wpt dom/nodes --limit 2',
      results: const [
        TestResult(
          suite: 'wpt',
          id: 'dom/nodes/a.html',
          status: ResultStatus.pass,
          durationMs: 3,
        ),
        TestResult(
          suite: 'wpt',
          id: 'dom/nodes/b.html',
          status: ResultStatus.fail,
          reason: 'assertion',
          detail: 'expected 1, got 2',
          durationMs: 4,
        ),
      ],
    );

void main() {
  test('compact summary points at JSONL instead of duplicating results',
      () {
    final dir = Directory.systemTemp.createTempSync('summary_compact_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final summary = _summary();
    final jsonl = File(p.join(dir.path, 'wpt-20261025T120000Z.jsonl'))
      ..writeAsStringSync(summary.results
          .map((result) => jsonEncode(result.toJson()))
          .join('\n'));
    final summaryFile =
        File(p.join(dir.path, 'wpt-20261025T120000Z.summary.json'))
          ..writeAsStringSync(summary.toJsonString(
            includeResults: false,
            resultsFile: p.basename(jsonl.path),
          ));

    final metadata =
        (jsonDecode(summaryFile.readAsStringSync()) as Map).cast<String, Object?>();
    expect(metadata.containsKey('results'), isFalse);
    expect(metadata['resultsFile'], p.basename(jsonl.path));
    expect(metadata['total'], 2);
    expect(metadata['counts'], {'PASS': 1, 'FAIL': 1, 'SKIP': 0, 'ERROR': 0});

    final loaded = RunSummary.load(summaryFile);
    expect(loaded, isNotNull);
    expect(loaded!.results, hasLength(2));
    expect(loaded.passed, 1);
    expect(loaded.failed, 1);
    expect(loaded.results.last.detail, 'expected 1, got 2');
  });

  test('legacy summaries with embedded results still load', () {
    final dir = Directory.systemTemp.createTempSync('summary_legacy_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File(p.join(dir.path, 'wpt-legacy.summary.json'))
      ..writeAsStringSync(_summary().toJsonString());

    final loaded = RunSummary.load(file);
    expect(loaded, isNotNull);
    expect(loaded!.results, hasLength(2));
    expect(loaded.passRate, 50);
  });

  test('a declared but missing results file is not an empty baseline', () {
    final dir = Directory.systemTemp.createTempSync('summary_missing_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File(p.join(dir.path, 'wpt-missing.summary.json'))
      ..writeAsStringSync(_summary().toJsonString(
        includeResults: false,
        resultsFile: 'wpt-missing.jsonl',
      ));

    expect(RunSummary.load(file), isNull);
  });
}
