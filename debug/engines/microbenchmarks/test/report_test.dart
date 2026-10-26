import 'dart:io';

import 'package:nativa_benchmark/benchmark.dart';
import 'package:test/test.dart';

RunMetadata _metadata() => RunMetadata(
      engine: 'QuickJS-ng',
      engineVersion: '0.17.0',
      dartVersion: 'test',
      os: 'linux',
      osVersion: 'test',
      arch: 'x64',
      mode: 'JIT',
      clock: 'Stopwatch',
      clockFrequencyHz: 1000000,
      clockResolutionMs: 0.001,
      timestamp: DateTime.utc(2026, 1, 1),
    );

BenchmarkResult _result(String name, double medianMs, {double madMs = 1}) {
  return BenchmarkResult(
    name: name,
    category: 'js',
    unit: 'ops',
    operations: 1000,
    rounds: 3,
    warmup: 1,
    samplesMs: [medianMs - madMs, medianMs, medianMs + madMs],
    checksum: 42,
  );
}

void main() {
  test('writes and reads a JSON/Markdown report', () {
    final dir = Directory.systemTemp.createTempSync('nativax_bench_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final report = RunReport(
      metadata: _metadata(),
      results: [_result('js.arithmetic', 10)],
      command: 'benchmark run',
      notes: const ['test note'],
    );
    final files = writeReport(report, outputDir: dir.path);
    expect(File(files.json).existsSync(), isTrue);
    expect(File(files.markdown).existsSync(), isTrue);
    final loaded = loadReport(files.json);
    expect(loaded.metadata.engine, 'QuickJS-ng');
    expect(loaded.results.single.name, 'js.arithmetic');
    expect(loaded.results.single.medianMs, 10);
    final markdown = File(files.markdown).readAsStringSync();
    expect(markdown, contains('js.arithmetic'));
    expect(markdown, contains('Limitaciones'));
    expect(markdown, contains('test note'));
  });

  test('comparison detects regressions, improvements and noise', () {
    final baseline = RunReport(
      metadata: _metadata(),
      results: [
        _result('js.regression', 100),
        _result('js.improvement', 100),
        _result('js.noise', 100),
      ],
      command: 'base',
    );
    final current = RunReport(
      metadata: _metadata(),
      results: [
        _result('js.regression', 120),
        _result('js.improvement', 80),
        _result('js.noise', 104),
      ],
      command: 'current',
    );
    final comparisons = compareRuns(
      baseline,
      current,
      thresholdPct: 10,
      noiseMultiplier: 2,
    );
    final status = {
      for (final c in comparisons) c.name: c.status,
    };
    expect(status['js.regression'], 'regression');
    expect(status['js.improvement'], 'improvement');
    expect(status['js.noise'], 'noise');
  });

  test('missing benchmarks are reported without inventing numbers', () {
    final baseline = RunReport(
      metadata: _metadata(),
      results: [_result('missing', 100)],
      command: 'base',
    );
    final current = RunReport(
      metadata: _metadata(),
      results: [],
      command: 'current',
    );
    final comparison = compareRuns(baseline, current).single;
    expect(comparison.status, 'missing');
    expect(comparison.currentMedianMs, 0);
  });
}
