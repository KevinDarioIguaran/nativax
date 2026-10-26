import 'dart:math' as math;

import 'model.dart';

/// Runs synchronous benchmark cases with warmup and several measured rounds.
class BenchmarkRunner {
  BenchmarkRunner({
    this.rounds = 15,
    this.warmup = 3,
    this.onProgress,
  }) {
    if (rounds < 1) throw ArgumentError.value(rounds, 'rounds', 'must be >= 1');
    if (warmup < 1) throw ArgumentError.value(warmup, 'warmup', 'must be >= 1');
  }

  final int rounds;
  final int warmup;
  final void Function(String name, int round, int total)? onProgress;

  List<BenchmarkResult> run(Iterable<BenchmarkCase> cases) {
    final results = <BenchmarkResult>[];
    for (final benchmark in cases) {
      results.add(runOne(benchmark));
    }
    return results;
  }

  BenchmarkResult runOne(BenchmarkCase benchmark) {
    num? checksum;
    for (var i = 0; i < warmup; i++) {
      checksum = benchmark.body();
      _verify(benchmark, checksum);
    }

    final samples = <double>[];
    int? memoryBefore;
    int? memoryAfter;
    for (var i = 0; i < rounds; i++) {
      if (i == 0) memoryBefore = benchmark.memoryProbe?.call();
      if (i == rounds - 1) memoryAfter = benchmark.memoryProbe?.call();
      final watch = Stopwatch()..start();
      final value = benchmark.body();
      watch.stop();
      _verify(benchmark, value);
      if (checksum != null && value != checksum) {
        throw StateError(
            '${benchmark.name}: checksum changed from $checksum to $value');
      }
      checksum ??= value;
      samples.add(watch.elapsedTicks / watch.frequency * 1000);
      if (i == rounds - 1) memoryAfter = benchmark.memoryProbe?.call();
      onProgress?.call(benchmark.name, i + 1, rounds);
    }
    // A benchmark that returns without doing measurable work is a bug in the
    // case, not a result to report as zero.
    if (samples.every((s) => s <= 0)) {
      throw StateError('${benchmark.name}: all samples are zero/negative');
    }
    final extra = <String, Object?>{...benchmark.extra};
    if (memoryBefore != null && memoryAfter != null) {
      extra['memoryBeforeBytes'] = memoryBefore;
      extra['memoryAfterBytes'] = memoryAfter;
      extra['memoryDeltaBytes'] = memoryAfter - memoryBefore;
    }
    return BenchmarkResult(
      name: benchmark.name,
      category: benchmark.category,
      unit: benchmark.unit,
      operations: benchmark.operations,
      rounds: rounds,
      warmup: warmup,
      samplesMs: samples,
      checksum: checksum ?? 0,
      language: benchmark.language,
      bytes: benchmark.bytes,
      inputSize: benchmark.inputSize,
      notes: benchmark.notes,
      extra: extra,
    );
  }

  void _verify(BenchmarkCase benchmark, num value) {
    if (benchmark.expected != null && value != benchmark.expected) {
      throw StateError(
          '${benchmark.name}: expected checksum ${benchmark.expected}, got $value');
    }
    if (value is double && (!value.isFinite || value.isNaN)) {
      throw StateError('${benchmark.name}: non-finite checksum');
    }
  }
}

/// Formats a duration in milliseconds with unit-aware precision.
String formatMs(double ms) {
  if (ms < 0.001) return '${(ms * 1e6).toStringAsFixed(0)} ns';
  if (ms < 1) return '${(ms * 1000).toStringAsFixed(1)} µs';
  if (ms < 1000) return '${ms.toStringAsFixed(3)} ms';
  return '${(ms / 1000).toStringAsFixed(3)} s';
}

String formatOps(double ops) {
  if (ops <= 0) return '—';
  if (ops >= 1e9) return '${(ops / 1e9).toStringAsFixed(2)} G/s';
  if (ops >= 1e6) return '${(ops / 1e6).toStringAsFixed(2)} M/s';
  if (ops >= 1e3) return '${(ops / 1e3).toStringAsFixed(2)} k/s';
  return '${ops.toStringAsFixed(0)} /s';
}

double percentChange(double baseline, double current) {
  if (baseline == 0) return current == 0 ? 0 : double.infinity;
  return ((current - baseline) / baseline) * 100;
}

/// Compares two runs. A change is only a regression when it exceeds both the
/// configured threshold and the baseline's measured noise (MAD/median × noise).
class Comparison {
  Comparison({
    required this.name,
    required this.baselineMedianMs,
    required this.currentMedianMs,
    required this.changePct,
    required this.noisePct,
    required this.status,
  });

  final String name;
  final double baselineMedianMs;
  final double currentMedianMs;
  final double changePct;
  final double noisePct;

  /// `regression`, `improvement`, `stable`, `noise`, `missing`.
  final String status;
}

List<Comparison> compareRuns(
  RunReport baseline,
  RunReport current, {
  double thresholdPct = 10,
  double noiseMultiplier = 2,
}) {
  final results = <Comparison>[];
  for (final before in baseline.results) {
    final after = current.byName(before.name);
    if (after == null) {
      results.add(Comparison(
        name: before.name,
        baselineMedianMs: before.medianMs,
        currentMedianMs: 0,
        changePct: 0,
        noisePct: before.relativeSpread,
        status: 'missing',
      ));
      continue;
    }
    final change = percentChange(before.medianMs, after.medianMs);
    final noise = math.max(before.relativeSpread, after.relativeSpread);
    final limit = math.max(thresholdPct, noise * noiseMultiplier);
    String status;
    if (change.abs() <= limit) {
      status = 'noise';
    } else if (change > 0) {
      status = 'regression';
    } else {
      status = 'improvement';
    }
    results.add(Comparison(
      name: before.name,
      baselineMedianMs: before.medianMs,
      currentMedianMs: after.medianMs,
      changePct: change,
      noisePct: noise,
      status: status,
    ));
  }
  return results;
}
