import 'dart:io';

import 'package:nativa_conformance/conformance.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final data = ValidationDataset(ValidationDataset.inRepo(findRepoRoot()));
  final expected = loadExpectedOutcomes(data.expectedPath);
  late List<RunSummary> runs;
  late ValidationReport report;

  setUpAll(() async {
    runs = await runValidationSubset(data);
    report = validateRuns(runs, expected);
  });

  test('every runner matches the hand-verified expectations', () {
    expect(report.mismatches.map((r) => '${r.expectation.id}: '
        'expected ${r.expectation.expected.label}, got ${r.actual?.label} '
        '(${r.reason})'), isEmpty);
    expect(report.perfect, isTrue, reason: report.renderMarkdown());
    expect(report.total, expected.length);
  });

  test('the subset covers PASS, FAIL, SKIP and ERROR', () {
    final statuses = expected.map((e) => e.expected).toSet();
    expect(statuses, containsAll(ResultStatus.values));
  });

  for (final adapter in brokenAdapters) {
    test('broken adapter "${adapter.name}" is detected', () {
      final broken =
          validateRuns([for (final r in runs) adapter.apply(r)], expected);
      expect(report.detects(broken), isTrue, reason: adapter.description);
    });
  }

  test('a no-op Test262 assert.js is detected', () async {
    final temp = Directory.systemTemp.createTempSync('nx_validation_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final suite = writeBrokenTest262(data, p.join(temp.path, 'test262'));
    final broken = validateRuns(
        await runValidationSubset(data, test262Suite: suite), expected);
    expect(report.detects(broken), isTrue);
    expect(broken.mismatches.map((r) => r.expectation.id),
        contains('validation/fail-float-sum.js'));
  });

  test('an always-pass WPT harness is detected', () async {
    final broken = validateRuns(
        await runValidationSubset(data, wptHarness: alwaysPassWptHarness),
        expected);
    expect(report.detects(broken), isTrue);
    expect(broken.mismatches.map((r) => r.expectation.id),
        contains('validation/fail-wrong-assert.html'));
  });

  test('missing results count as wrong, unexpected ones are listed', () {
    final first = expected.first;
    final partial = validateRuns([
      RunSummary(
        suite: first.suite,
        startedAt: DateTime(2026),
        durationMs: 0,
        results: [
          TestResult(suite: first.suite, id: 'not-in-dataset', status: ResultStatus.pass),
        ],
      ),
    ], expected);
    expect(partial.suites[first.suite]!.missing,
        expected.where((e) => e.suite == first.suite).length);
    expect(partial.suites[first.suite]!.unexpected.single.id, 'not-in-dataset');
    expect(partial.perfect, isFalse);
  });
}
