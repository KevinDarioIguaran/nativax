import 'dart:io';

import 'package:nativa_js/nativa_js.dart';

enum LeakStatus {
  pass('PASS'),
  fail('FAIL'),
  skip('SKIP'),
  error('ERROR'),
  inconclusive('INCONCLUSIVE');

  const LeakStatus(this.label);
  final String label;
}

class LeakProfile {
  const LeakProfile({
    required this.name,
    required this.batches,
    required this.iterations,
    this.settle = const Duration(milliseconds: 5),
    this.maxDuration = const Duration(seconds: 60),
    this.rssGrowthBytesPerBatch = 4 * 1024 * 1024,
    this.engineGrowthBytesPerBatch = 512 * 1024,
    this.resourceGrowthThreshold = 0,
    this.minMonotonicRun = 3,
  });

  final String name;
  final int batches;
  final int iterations;
  final Duration settle;
  final Duration maxDuration;
  final int rssGrowthBytesPerBatch;
  final int engineGrowthBytesPerBatch;
  final int resourceGrowthThreshold;
  final int minMonotonicRun;

  static const quick = LeakProfile(
    name: 'quick',
    batches: 5,
    iterations: 2000,
  );

  static const full = LeakProfile(
    name: 'full',
    batches: 20,
    iterations: 10000,
    maxDuration: Duration(minutes: 3),
  );

  static const stress = LeakProfile(
    name: 'stress',
    batches: 60,
    iterations: 50000,
    maxDuration: Duration(minutes: 15),
    rssGrowthBytesPerBatch: 8 * 1024 * 1024,
  );
}

class LeakSample {
  const LeakSample({
    required this.batch,
    required this.rssBytes,
    required this.maxRssBytes,
    this.engineBytes,
    this.nodes,
    this.listeners,
    this.timers,
    this.targets,
    this.activeRuntimes,
    this.release = false,
    this.extra = const {},
  });

  final int batch;
  final int rssBytes;
  final int maxRssBytes;
  final int? engineBytes;
  final int? nodes;
  final int? listeners;
  final int? timers;
  final int? targets;
  final int? activeRuntimes;

  /// True for the sample taken after the explicit release step that follows
  /// the last batch ([LeakContext.sampleRelease]). It is not a batch sample.
  final bool release;
  final Map<String, Object?> extra;

  Map<String, Object?> toJson() => {
        'batch': batch,
        if (release) 'phase': 'release',
        'rssBytes': rssBytes,
        'maxRssBytes': maxRssBytes,
        if (engineBytes != null) 'engineBytes': engineBytes,
        if (nodes != null) 'nodes': nodes,
        if (listeners != null) 'listeners': listeners,
        if (timers != null) 'timers': timers,
        if (targets != null) 'targets': targets,
        if (activeRuntimes != null) 'activeRuntimes': activeRuntimes,
        if (extra.isNotEmpty) 'extra': extra,
      };
}

/// Ground truth of a dataset case, known by construction.
class LeakTruth {
  const LeakTruth({
    required this.leaks,
    required this.expected,
    required this.rationale,
  });

  /// True when the workload retains memory or resources by construction.
  final bool leaks;

  /// Class a correct detector should report, given the evidence the case
  /// exposes (`proven_leak`, `suspected_leak`, `bounded_high_usage`,
  /// `no_leak`, `inconclusive`).
  final String expected;
  final String rationale;

  Map<String, Object?> toJson() => {
        'leaks': leaks,
        'expected': expected,
        'rationale': rationale,
      };
}

class LeakCase {
  const LeakCase({
    required this.id,
    required this.subsystem,
    required this.scenario,
    required this.expectation,
    required this.run,
    this.truth,
  });

  final String id;
  final String subsystem;
  final String scenario;

  /// `released`, `retained` (positive control) or `bounded` (cache).
  final String expectation;
  final Future<void> Function(LeakContext context) run;

  /// Set only for ground-truth dataset cases (`audit.*`).
  final LeakTruth? truth;
}

class LeakContext {
  LeakContext(this.profile);

  final LeakProfile profile;
  final List<LeakSample> samples = [];
  final Stopwatch clock = Stopwatch()..start();

  void checkBudget() {
    if (clock.elapsed > profile.maxDuration) {
      throw LeakLimitException(
          '${profile.name} profile exceeded ${profile.maxDuration}');
    }
  }

  Future<void> sample(
    int batch, {
    int? engineBytes,
    int? nodes,
    int? listeners,
    int? timers,
    int? targets,
    int? activeRuntimes,
    Map<String, Object?> extra = const {},
    bool release = false,
  }) async {
    checkBudget();
    if (profile.settle > Duration.zero) {
      await Future<void>.delayed(profile.settle);
    }
    samples.add(LeakSample(
      batch: batch,
      rssBytes: ProcessInfo.currentRss,
      maxRssBytes: ProcessInfo.maxRss,
      engineBytes: engineBytes,
      nodes: nodes,
      listeners: listeners,
      timers: timers,
      targets: targets,
      activeRuntimes: activeRuntimes,
      release: release,
      extra: extra,
    ));
  }

  /// Records the sample taken after the case's release step (drop the
  /// references a correct program would drop, then GC). A leak survives it.
  Future<void> sampleRelease({
    int? engineBytes,
    int? nodes,
    int? listeners,
    int? timers,
    int? targets,
    int? activeRuntimes,
  }) =>
      sample(
        samples.isEmpty ? 0 : samples.last.batch + 1,
        engineBytes: engineBytes,
        nodes: nodes,
        listeners: listeners,
        timers: timers,
        targets: targets,
        activeRuntimes: activeRuntimes,
        release: true,
      );

  Future<void> gc([QuickJsEngine? engine]) async {
    engine?.collectGarbage();
    // Give Dart's event loop a chance to run finalizers/GC bookkeeping.
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

class LeakLimitException implements Exception {
  LeakLimitException(this.message);
  final String message;
  @override
  String toString() => 'LeakLimitException: $message';
}
