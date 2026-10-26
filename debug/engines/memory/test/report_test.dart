import 'dart:io';

import 'package:nativa_leaks/leaks.dart';
import 'package:test/test.dart';

LeakRun _run(List<LeakResult> results) => LeakRun(
  metadata: LeakRunMetadata(
    engine: 'QuickJS-ng',
    engineVersion: '0.17.0',
    dartVersion: 'test',
    mode: 'JIT',
    os: 'linux',
    osVersion: 'test',
    arch: 'x64',
    profile: 'quick',
    timestamp: DateTime.utc(2026, 1, 1),
    command: 'leaks run',
  ),
  results: results,
);

LeakResult _result(String id, LeakStatus status) => LeakResult(
  id: id,
  subsystem: 'test',
  scenario: 'synthetic',
  expectation: 'released',
  status: status,
  reason: status.label,
  samples: const [],
  durationMs: 1,
);

void main() {
  test('writes JSON, JSONL and Markdown', () {
    final dir = Directory.systemTemp.createTempSync('nativa_leaks_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final run = _run([
      LeakResult(
        id: 'case',
        subsystem: 'js',
        scenario: 'synthetic',
        expectation: 'released',
        status: LeakStatus.pass,
        reason: 'ok',
        durationMs: 1,
        samples: [
          LeakSample(
            batch: 0,
            rssBytes: 1000,
            maxRssBytes: 1000,
            engineBytes: 500,
          ),
          LeakSample(
            batch: 1,
            rssBytes: 1100,
            maxRssBytes: 1100,
            engineBytes: 500,
          ),
        ],
      ),
    ]);
    final files = writeLeakReport(run, outputDir: dir.path);
    expect(File(files.json).existsSync(), isTrue);
    expect(File(files.jsonl).existsSync(), isTrue);
    expect(File(files.markdown).existsSync(), isTrue);
    final loaded = loadLeakRun(files.json);
    expect(loaded.results.single.id, 'case');
    expect(loaded.results.single.samples.length, 2);
    expect(File(files.markdown).readAsStringSync(), contains('case'));
    final markdown = File(files.markdown).readAsStringSync();
    expect(markdown, contains('| Case | Subsystem | Status | Class |'));
    expect(markdown, contains('| no_leak |'));
    expect(loaded.results.single.classification, isNull);
    final lines = File(
      files.jsonl,
    ).readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();
    expect(lines.length, 2);
  });

  test('compares statuses without inventing results', () {
    final baseline = _run([_result('case', LeakStatus.pass)]);
    final current = _run([_result('case', LeakStatus.fail)]);
    final changes = compareLeakRuns(baseline, current);
    expect(changes.single.status, 'regression');
    expect(changes.single.before, LeakStatus.pass);
    expect(changes.single.after, LeakStatus.fail);
  });
}
