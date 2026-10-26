import 'dart:math' as math;

/// A single benchmark case. [body] must return the same numeric checksum on
/// every run; the runner uses it to prove the work was actually performed.
class BenchmarkCase {
  const BenchmarkCase({
    required this.name,
    required this.category,
    required this.body,
    this.operations = 1,
    this.unit = 'ops',
    this.expected,
    this.notes = '',
    this.language = 'javascript',
    this.bytes = 0,
    this.inputSize = 0,
    this.memoryProbe,
    this.extra = const {},
  });

  final String name;
  final String category;
  final num Function() body;

  /// Number of logical operations performed by one [body] call.
  final int operations;

  /// Unit for the operations/second column (`ops`, `calls`, `nodes`, ...).
  final String unit;
  final num? expected;
  final String notes;

  /// `javascript`, `dart`, `bridge`, `dom`, `css`, ...
  final String language;
  final int bytes;
  final int inputSize;

  /// Optional heap probe (for example `engine.memoryUsed`), called before and
  /// after the last measured round.
  final int Function()? memoryProbe;
  final Map<String, Object?> extra;
}

class BenchmarkResult {
  BenchmarkResult({
    required this.name,
    required this.category,
    required this.unit,
    required this.operations,
    required this.rounds,
    required this.warmup,
    required this.samplesMs,
    required this.checksum,
    this.language = 'javascript',
    this.bytes = 0,
    this.inputSize = 0,
    this.notes = '',
    this.extra = const {},
  });

  factory BenchmarkResult.fromJson(Map<String, Object?> json) =>
      BenchmarkResult(
        name: json['name'] as String? ?? '',
        category: json['category'] as String? ?? '',
        unit: json['unit'] as String? ?? 'ops',
        operations: (json['operations'] as num?)?.toInt() ?? 0,
        rounds: (json['rounds'] as num?)?.toInt() ?? 0,
        warmup: (json['warmup'] as num?)?.toInt() ?? 0,
        samplesMs: (json['samplesMs'] as List? ?? const [])
            .map((e) => (e as num).toDouble())
            .toList(),
        checksum: json['checksum'] as num? ?? 0,
        language: json['language'] as String? ?? 'javascript',
        bytes: (json['bytes'] as num?)?.toInt() ?? 0,
        inputSize: (json['inputSize'] as num?)?.toInt() ?? 0,
        notes: json['notes'] as String? ?? '',
        extra: (json['extra'] as Map?)?.cast<String, Object?>() ?? const {},
      );

  final String name;
  final String category;
  final String unit;
  final int operations;
  final int rounds;
  final int warmup;
  final List<double> samplesMs;
  final num checksum;
  final String language;
  final int bytes;
  final int inputSize;
  final String notes;
  final Map<String, Object?> extra;

  List<double> get sorted => List.of(samplesMs)..sort();

  double get minMs => sorted.first;
  double get maxMs => sorted.last;
  double get meanMs => mean(samplesMs);
  double get medianMs => median(samplesMs);
  double get stdDevMs => stdDev(samplesMs);
  double get madMs => medianAbsoluteDeviation(samplesMs);

  /// Relative noise proxy: MAD / median. Useful when deciding whether two
  /// runs are distinguishable.
  double get relativeSpread =>
      medianMs == 0 ? 0 : (madMs / medianMs) * 100;

  double get opsPerSecond {
    if (operations <= 0 || medianMs <= 0) return 0;
    return operations / (medianMs / 1000);
  }

  double get mbPerSecond {
    if (bytes <= 0 || medianMs <= 0) return 0;
    return (bytes / (1024 * 1024)) / (medianMs / 1000);
  }

  double percentile(double p) => percentileOf(samplesMs, p);

  double get p90Ms => percentile(90);
  double get p95Ms => percentile(95);
  double get p99Ms => percentile(99);

  /// Deterministic 95 % bootstrap percentile interval for the median.
  (double, double) get medianConfidenceInterval =>
      bootstrapMedianCi(samplesMs);

  Map<String, Object?> toJson() => {
        'name': name,
        'category': category,
        'unit': unit,
        'operations': operations,
        'rounds': rounds,
        'warmup': warmup,
        'language': language,
        'bytes': bytes,
        'inputSize': inputSize,
        'samplesMs': samplesMs,
        'minMs': minMs,
        'maxMs': maxMs,
        'meanMs': meanMs,
        'medianMs': medianMs,
        'p90Ms': p90Ms,
        'p95Ms': p95Ms,
        'p99Ms': p99Ms,
        'medianCiLowMs': medianConfidenceInterval.$1,
        'medianCiHighMs': medianConfidenceInterval.$2,
        'stdDevMs': stdDevMs,
        'madMs': madMs,
        'relativeSpreadPct': relativeSpread,
        'opsPerSecond': opsPerSecond,
        'mbPerSecond': mbPerSecond,
        'checksum': checksum,
        if (notes.isNotEmpty) 'notes': notes,
        if (extra.isNotEmpty) 'extra': extra,
      };
}

class RunMetadata {
  const RunMetadata({
    required this.engine,
    required this.engineVersion,
    required this.dartVersion,
    required this.os,
    required this.osVersion,
    required this.arch,
    required this.mode,
    required this.clock,
    required this.clockFrequencyHz,
    required this.clockResolutionMs,
    required this.timestamp,
  });

  factory RunMetadata.fromJson(Map<String, Object?> json) => RunMetadata(
        engine: json['engine'] as String? ?? '',
        engineVersion: json['engineVersion'] as String? ?? '',
        dartVersion: json['dartVersion'] as String? ?? '',
        os: json['os'] as String? ?? '',
        osVersion: json['osVersion'] as String? ?? '',
        arch: json['arch'] as String? ?? '',
        mode: json['mode'] as String? ?? '',
        clock: json['clock'] as String? ?? '',
        clockFrequencyHz:
            (json['clockFrequencyHz'] as num?)?.toInt() ?? 0,
        clockResolutionMs:
            (json['clockResolutionMs'] as num?)?.toDouble() ?? 0,
        timestamp:
            DateTime.tryParse(json['timestamp'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
      );

  final String engine;
  final String engineVersion;
  final String dartVersion;
  final String os;
  final String osVersion;
  final String arch;

  /// `JIT`, `profile` or `AOT`.
  final String mode;
  final String clock;
  final int clockFrequencyHz;
  final double clockResolutionMs;
  final DateTime timestamp;

  Map<String, Object?> toJson() => {
        'engine': engine,
        'engineVersion': engineVersion,
        'dartVersion': dartVersion,
        'os': os,
        'osVersion': osVersion,
        'arch': arch,
        'mode': mode,
        'clock': clock,
        'clockFrequencyHz': clockFrequencyHz,
        'clockResolutionMs': clockResolutionMs,
        'timestamp': timestamp.toIso8601String(),
      };
}

class RunReport {
  RunReport({
    required this.metadata,
    required this.results,
    required this.command,
    this.notes = const [],
  });

  factory RunReport.fromJson(Map<String, Object?> json) => RunReport(
        metadata: RunMetadata.fromJson(
            (json['metadata'] as Map?)?.cast<String, Object?>() ?? const {}),
        results: (json['results'] as List? ?? const [])
            .map((e) => BenchmarkResult.fromJson(
                (e as Map).cast<String, Object?>()))
            .toList(),
        command: json['command'] as String? ?? '',
        notes: (json['notes'] as List?)?.cast<String>() ?? const [],
      );

  final RunMetadata metadata;
  final List<BenchmarkResult> results;
  final String command;
  final List<String> notes;

  BenchmarkResult? byName(String name) {
    for (final r in results) {
      if (r.name == name) return r;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
        'metadata': metadata.toJson(),
        'command': command,
        'notes': notes,
        'results': [for (final r in results) r.toJson()],
      };
}

double mean(List<double> values) {
  if (values.isEmpty) return 0;
  return values.fold(0.0, (a, b) => a + b) / values.length;
}

double median(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = List.of(values)..sort();
  final n = sorted.length;
  if (n.isOdd) return sorted[n ~/ 2];
  return (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
}

double stdDev(List<double> values) {
  if (values.isEmpty) return 0;
  final m = mean(values);
  final variance =
      values.fold(0.0, (a, b) => a + math.pow(b - m, 2)) / values.length;
  return math.sqrt(variance);
}

double medianAbsoluteDeviation(List<double> values) {
  if (values.isEmpty) return 0;
  final m = median(values);
  return median([for (final v in values) (v - m).abs()]);
}

double percentileOf(List<double> values, double p) {
  if (values.isEmpty) return 0;
  final sorted = List.of(values)..sort();
  if (sorted.length == 1) return sorted.first;
  final rank = (p.clamp(0, 100) / 100) * (sorted.length - 1);
  final lo = rank.floor();
  final hi = rank.ceil();
  if (lo == hi) return sorted[lo];
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (rank - lo);
}

/// Deterministic bootstrap for a robust uncertainty estimate of the median.
(double, double) bootstrapMedianCi(
  List<double> values, {
  int resamples = 1000,
  double confidence = 0.95,
}) {
  if (values.isEmpty) return (0, 0);
  final random = math.Random(0x4e585f42);
  final medians = <double>[];
  for (var i = 0; i < resamples; i++) {
    medians.add(median([
      for (var j = 0; j < values.length; j++)
        values[random.nextInt(values.length)],
    ]));
  }
  final alpha = ((1 - confidence) / 2) * 100;
  return (percentileOf(medians, alpha), percentileOf(medians, 100 - alpha));
}
