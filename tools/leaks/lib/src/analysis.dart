import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import 'model.dart';

class LeakResult {
  LeakResult({
    required this.id,
    required this.subsystem,
    required this.scenario,
    required this.expectation,
    required this.status,
    required this.reason,
    required this.samples,
    required this.durationMs,
    this.thresholdBytes = 0,
    this.evidence = const [],
    this.reproduce = '',
    this.extra = const {},
  });

  final String id;
  final String subsystem;
  final String scenario;
  final String expectation;
  final LeakStatus status;
  final String reason;
  final List<LeakSample> samples;
  final int durationMs;
  final int thresholdBytes;
  final List<String> evidence;
  final String reproduce;
  final Map<String, Object?> extra;

  Map<String, Object?> toJson() => {
        'id': id,
        'subsystem': subsystem,
        'scenario': scenario,
        'expectation': expectation,
        'status': status.name,
        'reason': reason,
        'durationMs': durationMs,
        'thresholdBytes': thresholdBytes,
        'evidence': evidence,
        'reproduce': reproduce,
        'samples': [for (final s in samples) s.toJson()],
        if (extra.isNotEmpty) 'extra': extra,
      };
}

class LeakRunMetadata {
  LeakRunMetadata({
    required this.engine,
    required this.engineVersion,
    required this.dartVersion,
    required this.mode,
    required this.os,
    required this.osVersion,
    required this.arch,
    required this.profile,
    required this.timestamp,
    required this.command,
  });

  final String engine;
  final String engineVersion;
  final String dartVersion;
  final String mode;
  final String os;
  final String osVersion;
  final String arch;
  final String profile;
  final DateTime timestamp;
  final String command;

  Map<String, Object?> toJson() => {
        'engine': engine,
        'engineVersion': engineVersion,
        'dartVersion': dartVersion,
        'mode': mode,
        'os': os,
        'osVersion': osVersion,
        'arch': arch,
        'profile': profile,
        'timestamp': timestamp.toIso8601String(),
        'command': command,
      };

  factory LeakRunMetadata.fromJson(Map<String, Object?> json) => LeakRunMetadata(
        engine: json['engine'] as String? ?? '',
        engineVersion: json['engineVersion'] as String? ?? '',
        dartVersion: json['dartVersion'] as String? ?? '',
        mode: json['mode'] as String? ?? '',
        os: json['os'] as String? ?? '',
        osVersion: json['osVersion'] as String? ?? '',
        arch: json['arch'] as String? ?? '',
        profile: json['profile'] as String? ?? '',
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        command: json['command'] as String? ?? '',
      );
}

class LeakRun {
  LeakRun({required this.metadata, required this.results});
  final LeakRunMetadata metadata;
  final List<LeakResult> results;

  LeakResult? byId(String id) {
    for (final r in results) {
      if (r.id == id) return r;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
        'metadata': metadata.toJson(),
        'results': [for (final r in results) r.toJson()],
      };

  factory LeakRun.fromJson(Map<String, Object?> json) => LeakRun(
        metadata: LeakRunMetadata.fromJson(
            (json['metadata'] as Map?)?.cast<String, Object?>() ?? const {}),
        results: (json['results'] as List? ?? const []).map((e) {
          final map = (e as Map).cast<String, Object?>();
          return LeakResult(
            id: map['id'] as String? ?? '',
            subsystem: map['subsystem'] as String? ?? '',
            scenario: map['scenario'] as String? ?? '',
            expectation: map['expectation'] as String? ?? 'released',
            status: LeakStatus.values.firstWhere(
              (s) => s.name == map['status'],
              orElse: () => LeakStatus.error,
            ),
            reason: map['reason'] as String? ?? '',
            samples: (map['samples'] as List? ?? const [])
                .map((s) {
                  final m = (s as Map).cast<String, Object?>();
                  return LeakSample(
                    batch: (m['batch'] as num?)?.toInt() ?? 0,
                    rssBytes: (m['rssBytes'] as num?)?.toInt() ?? 0,
                    maxRssBytes: (m['maxRssBytes'] as num?)?.toInt() ?? 0,
                    engineBytes: (m['engineBytes'] as num?)?.toInt(),
                    nodes: (m['nodes'] as num?)?.toInt(),
                    listeners: (m['listeners'] as num?)?.toInt(),
                    timers: (m['timers'] as num?)?.toInt(),
                    targets: (m['targets'] as num?)?.toInt(),
                    activeRuntimes: (m['activeRuntimes'] as num?)?.toInt(),
                    extra: (m['extra'] as Map?)?.cast<String, Object?>() ??
                        const {},
                  );
                })
                .toList(),
            durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
            thresholdBytes: (map['thresholdBytes'] as num?)?.toInt() ?? 0,
            evidence: (map['evidence'] as List?)?.cast<String>() ?? const [],
            reproduce: map['reproduce'] as String? ?? '',
            extra: (map['extra'] as Map?)?.cast<String, Object?>() ?? const {},
          );
        }).toList(),
      );
}

/// Analyzes the batch series. It never uses a single OS RSS sample as proof:
/// resource counters and a sustained trend are required for FAIL.
LeakResult analyzeLeak(LeakCase test, LeakContext context, int durationMs) {
  final samples = context.samples;
  if (samples.length < 3) {
    return LeakResult(
      id: test.id,
      subsystem: test.subsystem,
      scenario: test.scenario,
      expectation: test.expectation,
      status: LeakStatus.inconclusive,
      reason: 'not enough samples (${samples.length})',
      samples: samples,
      durationMs: durationMs,
    );
  }
  final usesEngine = samples.any((s) => (s.engineBytes ?? 0) > 0);
  final series = [
    for (final s in samples)
      (usesEngine ? (s.engineBytes ?? 0) : s.rssBytes).toDouble(),
  ];
  final threshold = usesEngine
      ? context.profile.engineGrowthBytesPerBatch * context.profile.batches
      : context.profile.rssGrowthBytesPerBatch * context.profile.batches;
  final growth = series.last - series.first;
  final slope = _slope(series);
  final increases = _monotonicIncreases(series);
  final resourceDeltas = <String, int>{};
  void delta(String name, int? Function(LeakSample) read) {
    final values = samples.map(read).whereType<int>().toList();
    if (values.length == samples.length) {
      resourceDeltas[name] = values.last - values.first;
    }
  }

  delta('nodes', (s) => s.nodes);
  delta('listeners', (s) => s.listeners);
  delta('timers', (s) => s.timers);
  delta('targets', (s) => s.targets);
  delta('activeRuntimes', (s) => s.activeRuntimes);

  final resourceLeak = resourceDeltas.values
      .any((d) => d > context.profile.resourceGrowthThreshold);
  final resourceEvidence = resourceDeltas.isNotEmpty && !resourceLeak;
  final sustainedMemory =
      usesEngine &&
      growth > threshold &&
      increases >= context.profile.minMonotonicRun;
  final rssGrowth = !usesEngine &&
      growth > threshold &&
      increases >= context.profile.minMonotonicRun;
  final trend = 'growth=${_bytes(growth.round())}, slope=${_bytes(slope.round())}/batch, '
      'increases=$increases, threshold=${_bytes(threshold)}';

  String reason;
  LeakStatus status;
  if (test.expectation == 'retained') {
    // Positive control: it must demonstrate that retention is observable.
    if (growth > threshold || resourceLeak) {
      status = LeakStatus.pass;
      reason = 'positive control retained resources as expected';
    } else {
      status = LeakStatus.fail;
      reason = 'positive control did not retain measurable resources; '
          'the detector may be blind';
    }
  } else if (test.expectation == 'bounded') {
    if (sustainedMemory || resourceLeak) {
      status = LeakStatus.fail;
      reason = 'bounded cache/resource did not plateau';
    } else if (resourceEvidence) {
      status = LeakStatus.pass;
      reason = 'resource counters plateaued within the threshold';
    } else if (rssGrowth && resourceDeltas.isEmpty) {
      status = LeakStatus.inconclusive;
      reason = 'RSS rose but there is no resource counter to confirm a leak';
    } else {
      status = LeakStatus.pass;
      reason = 'memory/resources plateaued within the threshold';
    }
  } else {
    if (sustainedMemory || resourceLeak) {
      status = LeakStatus.fail;
      reason = 'sustained growth detected after release';
    } else if (resourceEvidence) {
      status = LeakStatus.pass;
      reason = 'resource counters returned to baseline after release';
    } else if (rssGrowth && resourceDeltas.isEmpty) {
      status = LeakStatus.inconclusive;
      reason = 'RSS rose but there is no heap/resource evidence to confirm '
          'a leak';
    } else if (growth > threshold || slope > threshold / samples.length) {
      status = LeakStatus.inconclusive;
      reason = 'memory increased but the trend is not stable enough to '
          'confirm a leak';
    } else {
      status = LeakStatus.pass;
      reason = 'no sustained growth after release';
    }
  }

  return LeakResult(
    id: test.id,
    subsystem: test.subsystem,
    scenario: test.scenario,
    expectation: test.expectation,
    status: status,
    reason: reason,
    samples: samples,
    durationMs: durationMs,
    thresholdBytes: threshold,
    evidence: [
      if (usesEngine) 'heap QuickJS (JS_ComputeMemoryUsage)'
      else 'RSS del proceso (Dart ProcessInfo.currentRss)',
      trend,
      if (resourceDeltas.isNotEmpty)
        'resource deltas: ${resourceDeltas.entries.map((e) => '${e.key}=${e.value}').join(', ')}',
    ],
    reproduce: 'dart run bin/leaks.dart run --only ${test.id} '
        '--profile ${context.profile.name}',
    extra: {
      'usesEngineMemory': usesEngine,
      'resourceDeltas': resourceDeltas,
    },
  );
}

double _slope(List<double> values) {
  if (values.length < 2) return 0;
  final n = values.length;
  final meanX = (n - 1) / 2;
  final meanY = values.reduce((a, b) => a + b) / n;
  var num = 0.0;
  var den = 0.0;
  for (var i = 0; i < n; i++) {
    final dx = i - meanX;
    num += dx * (values[i] - meanY);
    den += dx * dx;
  }
  return den == 0 ? 0 : num / den;
}

int _monotonicIncreases(List<double> values) {
  var count = 0;
  for (var i = 1; i < values.length; i++) {
    if (values[i] > values[i - 1]) count++;
  }
  return count;
}

String _bytes(int value) {
  final sign = value < 0 ? '-' : '';
  final v = value.abs();
  if (v >= 1024 * 1024) {
    return '$sign${(v / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
  if (v >= 1024) return '$sign${(v / 1024).toStringAsFixed(1)} KiB';
  return '$sign$v B';
}

LeakRunMetadata collectLeakMetadata({
  required String repoRoot,
  required String profile,
  required String command,
}) {
  String arch = 'unknown';
  try {
    if (!Platform.isWindows) {
      final r = Process.runSync('uname', ['-m']);
      if (r.exitCode == 0) arch = (r.stdout as String).trim();
    } else {
      arch = Platform.environment['PROCESSOR_ARCHITECTURE']?.toLowerCase() ??
          'unknown';
    }
  } on ProcessException {
    // Keep unknown.
  }
  return LeakRunMetadata(
    engine: 'QuickJS-ng',
    engineVersion: _quickJsVersion(repoRoot),
    dartVersion: Platform.version.split(' ').first,
    mode: _mode(),
    os: Platform.operatingSystem,
    osVersion: Platform.operatingSystemVersion,
    arch: arch,
    profile: profile,
    timestamp: DateTime.now(),
    command: command,
  );
}

String _mode() {
  const product = bool.fromEnvironment('dart.vm.product');
  if (product) return 'AOT';
  const profile = bool.fromEnvironment('dart.vm.profile');
  if (profile) return 'profile';
  return 'JIT';
}

String _quickJsVersion(String root) {
  final f = File(p.join(root, 'packages', 'nativa_js', 'third_party',
      'quickjs', 'quickjs.h'));
  if (!f.existsSync()) return 'unknown';
  final text = f.readAsStringSync();
  String v(String name, String fallback) =>
      RegExp('#define\\s+$name\\s+(\\d+)').firstMatch(text)?.group(1) ??
      fallback;
  return '${v('QJS_VERSION_MAJOR', '0')}.${v('QJS_VERSION_MINOR', '0')}.'
      '${v('QJS_VERSION_PATCH', '0')}';
}

String findLeakRepoRoot([String? start]) {
  var dir = Directory(p.absolute(start ?? Directory.current.path));
  while (true) {
    final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('nativa_workspace')) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('could not locate the NativaX repository root');
    }
    dir = parent;
  }
}

double maxOrZero(Iterable<num> values) =>
    values.isEmpty ? 0 : values.reduce(math.max).toDouble();
