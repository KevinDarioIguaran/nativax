import 'dart:math' as math;

import 'model.dart';
import 'stats.dart';

/// Evidence class of one case. Ordered from strongest leak evidence to none;
/// see `debug/architecture/metrics-memory.md` for the formulas.
enum LeakClass {
  provenLeak('proven_leak'),
  suspectedLeak('suspected_leak'),
  inconclusive('inconclusive'),
  boundedHighUsage('bounded_high_usage'),
  noLeak('no_leak');

  const LeakClass(this.label);
  final String label;

  /// Lower is more severe. Used to combine channels (worst wins).
  int get severity => index;

  static LeakClass? parse(String? label) {
    for (final c in values) {
      if (c.label == label) return c;
    }
    return null;
  }
}

/// Decision parameters. They are recorded in every classification so a
/// result can be re-checked by hand.
class LeakCriteria {
  const LeakCriteria({
    this.warmupBatches = 1,
    this.minPoints = 5,
    this.alpha = 0.01,
    this.suspectAlpha = 0.10,
    this.plateauRatio = 0.5,
    this.releaseRetainFraction = 0.5,
    this.minSlopeEngineBytes = 1024,
    this.minSlopeRssBytes = 1024 * 1024,
    this.minSlopeCount = 1,
  });

  /// Batch samples discarded before the trend test (one-time setup).
  final int warmupBatches;

  /// Minimum post-warm-up batch samples. With fewer the case is
  /// `inconclusive`. At [alpha] = 0.01 the exact Mann-Kendall test needs at
  /// least 5 strictly increasing points (p = 1/120).
  final int minPoints;

  /// Significance level of the one-sided Mann-Kendall test for proof.
  final double alpha;

  /// Significance level for a suspicion.
  final double suspectAlpha;

  /// The Theil-Sen slope of the second half must be at least this fraction
  /// of the whole-series slope for the growth to count as "still growing".
  final double plateauRatio;

  /// With an explicit release sample, growth "returned" when the release
  /// value is below this fraction of the last batch's growth over the
  /// baseline (what the release step itself freed).
  final double releaseRetainFraction;

  /// Minimum Theil-Sen slope per batch (effect size) for each channel kind.
  final int minSlopeEngineBytes;
  final int minSlopeRssBytes;
  final int minSlopeCount;

  double minSlopeFor(String kind) => switch (kind) {
    'engineBytes' => minSlopeEngineBytes.toDouble(),
    'rssBytes' => minSlopeRssBytes.toDouble(),
    _ => minSlopeCount.toDouble(),
  };

  Map<String, Object?> toJson() => {
    'warmupBatches': warmupBatches,
    'minPoints': minPoints,
    'alpha': alpha,
    'suspectAlpha': suspectAlpha,
    'plateauRatio': plateauRatio,
    'releaseRetainFraction': releaseRetainFraction,
    'minSlopeEngineBytes': minSlopeEngineBytes,
    'minSlopeRssBytes': minSlopeRssBytes,
    'minSlopeCount': minSlopeCount,
    'rssOnlyCap': LeakClass.suspectedLeak.label,
  };
}

/// Analysis of one measured series (a counter, the engine heap or RSS).
class ChannelAnalysis {
  ChannelAnalysis({
    required this.name,
    required this.kind,
    required this.leakClass,
    required this.reason,
    required this.baseline,
    required this.peak,
    required this.last,
    required this.release,
    required this.retained,
    required this.deltas,
    required this.points,
    this.trend,
    this.senSlope = 0,
    this.tailSenSlope = 0,
    this.minSlope = 0,
    this.floor = 0,
    this.spread = 0,
    this.tailSpread = 0,
  });

  final String name;

  /// `counter`, `engineBytes` or `rssBytes`.
  final String kind;
  final LeakClass leakClass;
  final String reason;
  final double baseline;
  final double peak;
  final double last;

  /// Value after the explicit release step, if the case has one.
  final double? release;

  /// `release` (or the last batch sample) minus the baseline.
  final double retained;

  /// Per-batch deltas `x[i] - x[i-1]`, batch 1 first.
  final List<double> deltas;

  /// Post-warm-up batch samples used by the trend test.
  final int points;
  final MannKendall? trend;
  final double senSlope;
  final double tailSenSlope;
  final double minSlope;

  /// `minSlope * points`: the growth a minimal leak would accumulate.
  final double floor;
  final double spread;
  final double tailSpread;

  Map<String, Object?> toJson() => {
    'name': name,
    'kind': kind,
    'class': leakClass.label,
    'reason': reason,
    'baseline': baseline,
    'peak': peak,
    'last': last,
    if (release != null) 'release': release,
    'retained': retained,
    'deltas': deltas,
    'points': points,
    if (trend != null) 'trend': trend!.toJson(),
    'senSlope': senSlope,
    'tailSenSlope': tailSenSlope,
    'minSlope': minSlope,
    'floor': floor,
    'spread': spread,
    'tailSpread': tailSpread,
  };
}

class LeakClassification {
  LeakClassification({
    required this.leakClass,
    required this.reason,
    required this.primaryChannel,
    required this.criteria,
    required this.channels,
    required this.peakRssBytes,
    required this.retainedRssBytes,
    required this.explicitRelease,
  });

  final LeakClass leakClass;
  final String reason;

  /// Channel that decided the class, or null when there is none.
  final String? primaryChannel;
  final Map<String, Object?> criteria;
  final List<Map<String, Object?>> channels;
  final int peakRssBytes;
  final int retainedRssBytes;
  final bool explicitRelease;

  Map<String, Object?> toJson() => {
    'class': leakClass.label,
    'reason': reason,
    'primaryChannel': primaryChannel,
    'explicitRelease': explicitRelease,
    'peakRssBytes': peakRssBytes,
    'retainedRssBytes': retainedRssBytes,
    'criteria': criteria,
    'channels': channels,
  };

  static LeakClassification? fromJson(Object? json) {
    if (json is! Map) return null;
    final map = json.cast<String, Object?>();
    final leakClass = LeakClass.parse(map['class'] as String?);
    if (leakClass == null) return null;
    return LeakClassification(
      leakClass: leakClass,
      reason: map['reason'] as String? ?? '',
      primaryChannel: map['primaryChannel'] as String?,
      criteria: (map['criteria'] as Map?)?.cast<String, Object?>() ?? const {},
      channels: [
        for (final c in map['channels'] as List? ?? const [])
          (c as Map).cast<String, Object?>(),
      ],
      peakRssBytes: (map['peakRssBytes'] as num?)?.toInt() ?? 0,
      retainedRssBytes: (map['retainedRssBytes'] as num?)?.toInt() ?? 0,
      explicitRelease: map['explicitRelease'] as bool? ?? false,
    );
  }
}

const _counterReaders = <String, int? Function(LeakSample)>{
  'nodes': _nodes,
  'listeners': _listeners,
  'timers': _timers,
  'targets': _targets,
  'activeRuntimes': _activeRuntimes,
};
int? _nodes(LeakSample s) => s.nodes;
int? _listeners(LeakSample s) => s.listeners;
int? _timers(LeakSample s) => s.timers;
int? _targets(LeakSample s) => s.targets;
int? _activeRuntimes(LeakSample s) => s.activeRuntimes;

/// Classifies a case from its samples. Counters and the engine heap are
/// precise channels; process RSS is advisory and can never prove a leak.
LeakClassification classifyLeak(
  List<LeakSample> samples, {
  LeakCriteria criteria = const LeakCriteria(),
}) {
  final batches = samples.where((s) => !s.release).toList();
  final releaseSample = samples.where((s) => s.release).isEmpty
      ? null
      : samples.lastWhere((s) => s.release);
  final precise = <ChannelAnalysis>[];
  for (final entry in _counterReaders.entries) {
    final values = batches.map(entry.value).toList();
    if (values.isEmpty || values.any((v) => v == null)) continue;
    precise.add(
      classifyChannel(
        entry.key,
        'counter',
        [for (final v in values) v!.toDouble()],
        release: releaseSample == null
            ? null
            : entry.value(releaseSample)?.toDouble(),
        criteria: criteria,
      ),
    );
  }
  if (batches.isNotEmpty && batches.every((s) => (s.engineBytes ?? 0) > 0)) {
    precise.add(
      classifyChannel(
        'engineHeap',
        'engineBytes',
        [for (final s in batches) s.engineBytes!.toDouble()],
        release: releaseSample?.engineBytes?.toDouble(),
        criteria: criteria,
      ),
    );
  }
  final rss = classifyChannel(
    'rss',
    'rssBytes',
    [for (final s in batches) s.rssBytes.toDouble()],
    release: releaseSample?.rssBytes.toDouble(),
    criteria: criteria,
  );

  final peakRss = samples.isEmpty
      ? 0
      : samples.map((s) => s.rssBytes).reduce(math.max);
  final retainedRss = samples.isEmpty
      ? 0
      : (releaseSample ?? batches.last).rssBytes - samples.first.rssBytes;

  LeakClass leakClass;
  String reason;
  String? primary;
  if (precise.isEmpty) {
    // RSS-only: allocator and GC retention make it unable to prove a leak.
    leakClass = rss.leakClass == LeakClass.provenLeak
        ? LeakClass.suspectedLeak
        : rss.leakClass;
    reason = rss.leakClass == LeakClass.provenLeak
        ? 'RSS-only evidence meets the proof criteria but RSS cannot prove a '
              'leak (capped): ${rss.reason}'
        : 'RSS only: ${rss.reason}';
    primary = rss.name;
  } else {
    final worst = precise.reduce(
      (a, b) => b.leakClass.severity < a.leakClass.severity ? b : a,
    );
    leakClass = worst.leakClass;
    reason = '${worst.name}: ${worst.reason}';
    primary = worst.name;
    if (rss.leakClass == LeakClass.provenLeak ||
        rss.leakClass == LeakClass.suspectedLeak) {
      // RSS is advisory when a precise channel exists: in a fresh process it
      // climbs monotonically during allocator/Dart-heap warm-up, so it is
      // noted but never changes the class.
      reason =
          '$reason (advisory: RSS ${rss.leakClass.label}, Sen slope '
          '${(rss.senSlope / (1024 * 1024)).toStringAsFixed(1)} MiB/batch)';
    }
  }

  return LeakClassification(
    leakClass: leakClass,
    reason: reason,
    primaryChannel: primary,
    criteria: criteria.toJson(),
    channels: [
      for (final c in [...precise, rss]) c.toJson(),
    ],
    peakRssBytes: peakRss,
    retainedRssBytes: retainedRss,
    explicitRelease: releaseSample != null,
  );
}

/// Classifies one series. `values[0]` is the baseline (batch 0) and
/// `values[i]` the sample after batch `i`, taken after that batch released
/// its references and ran GC.
ChannelAnalysis classifyChannel(
  String name,
  String kind,
  List<double> values, {
  double? release,
  LeakCriteria criteria = const LeakCriteria(),
}) {
  final baseline = values.isEmpty ? 0.0 : values.first;
  final all = [...values, ?release];
  final peak = all.isEmpty ? 0.0 : all.reduce(math.max);
  final last = values.isEmpty ? 0.0 : values.last;
  final retained = (release ?? last) - baseline;
  final deltas = [
    for (var i = 1; i < values.length; i++) values[i] - values[i - 1],
  ];
  // `values[w]` is the first sample after the w warm-up batches ran, so with
  // warmupBatches = 1 the trend series is values[1..N].
  final trendSeries = values.length > criteria.warmupBatches
      ? values.sublist(criteria.warmupBatches)
      : <double>[];
  final minSlope = criteria.minSlopeFor(kind);
  final n = trendSeries.length;
  final floor = minSlope * n;

  ChannelAnalysis result(
    LeakClass c,
    String reason, {
    MannKendall? trend,
    double sen = 0,
    double tailSen = 0,
    double spread = 0,
    double tailSpread = 0,
  }) => ChannelAnalysis(
    name: name,
    kind: kind,
    leakClass: c,
    reason: reason,
    baseline: baseline,
    peak: peak,
    last: last,
    release: release,
    retained: retained,
    deltas: deltas,
    points: n,
    trend: trend,
    senSlope: sen,
    tailSenSlope: tailSen,
    minSlope: minSlope,
    floor: floor,
    spread: spread,
    tailSpread: tailSpread,
  );

  if (n < criteria.minPoints) {
    return result(
      LeakClass.inconclusive,
      'too few samples ($n post-warm-up batches < ${criteria.minPoints})',
    );
  }

  final trend = mannKendall(trendSeries);
  final sen = senSlope(trendSeries);
  final tail = trendSeries.sublist((n - 1) ~/ 2);
  final tailSen = senSlope(tail);
  final spread = trendSeries.reduce(math.max) - trendSeries.reduce(math.min);
  final tailSpread = tail.reduce(math.max) - tail.reduce(math.min);
  final growth = trendSeries.last - trendSeries.first;
  // The release step is judged against the level just before it (the last
  // batch), not the peak: a series that merely fell back from an earlier
  // peak did not return anything on release.
  final heldBeforeRelease = last - baseline;
  final returned =
      release != null &&
      heldBeforeRelease > 0 &&
      release - baseline < criteria.releaseRetainFraction * heldBeforeRelease;
  final stillGrowing =
      tailSen >= criteria.plateauRatio * sen && tailSen >= minSlope;
  final p = trend.pValue.toStringAsPrecision(3);
  final stats =
      'MK S=${trend.s} p=$p n=$n, Sen slope=${_fmt(sen, kind)}/batch '
      '(tail ${_fmt(tailSen, kind)}), min slope ${_fmt(minSlope, kind)}';
  ChannelAnalysis classified(LeakClass c, String why) => result(
    c,
    '$why; $stats',
    trend: trend,
    sen: sen,
    tailSen: tailSen,
    spread: spread,
    tailSpread: tailSpread,
  );

  if (trend.pValue < criteria.alpha &&
      sen >= minSlope &&
      stillGrowing &&
      !returned) {
    return classified(
      LeakClass.provenLeak,
      'monotonic growth that is still rising and is retained '
      '${release == null ? 'after every per-batch release' : 'after the explicit release'}',
    );
  }
  if (returned && heldBeforeRelease >= floor) {
    return classified(
      LeakClass.boundedHighUsage,
      'held ${_fmt(heldBeforeRelease, kind)} before release and returned it',
    );
  }
  if (trend.pValue < criteria.suspectAlpha &&
      sen > 0 &&
      tailSen > 0 &&
      growth > 0 &&
      !returned) {
    return classified(
      LeakClass.suspectedLeak,
      'increasing trend below the proof criteria',
    );
  }
  if (retained >= floor && tailSpread < floor) {
    return classified(
      LeakClass.boundedHighUsage,
      'retains ${_fmt(retained, kind)} over baseline but the second half is '
      'flat (spread ${_fmt(tailSpread, kind)} < floor ${_fmt(floor, kind)})',
    );
  }
  if (spread >= floor) {
    return classified(
      LeakClass.inconclusive,
      'variation ${_fmt(spread, kind)} >= floor ${_fmt(floor, kind)} '
      'without a monotonic trend (noise)',
    );
  }
  return classified(
    LeakClass.noLeak,
    'retained ${_fmt(retained, kind)} and variation ${_fmt(spread, kind)} '
    'below floor ${_fmt(floor, kind)}',
  );
}

String _fmt(double value, String kind) {
  if (kind == 'counter') {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(2);
  }
  final v = value.abs();
  final sign = value < 0 ? '-' : '';
  if (v >= 1024 * 1024)
    return '$sign${(v / (1024 * 1024)).toStringAsFixed(1)} MiB';
  if (v >= 1024) return '$sign${(v / 1024).toStringAsFixed(1)} KiB';
  return '$sign${v.round()} B';
}
