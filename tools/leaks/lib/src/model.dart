import 'dart:io';

import 'package:nativax_js/nativax_js.dart';

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
  final Map<String, Object?> extra;

  Map<String, Object?> toJson() => {
        'batch': batch,
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

class LeakCase {
  const LeakCase({
    required this.id,
    required this.subsystem,
    required this.scenario,
    required this.expectation,
    required this.run,
  });

  final String id;
  final String subsystem;
  final String scenario;

  /// `released`, `retained` (positive control) or `bounded` (cache).
  final String expectation;
  final Future<void> Function(LeakContext context) run;
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
      extra: extra,
    ));
  }

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
