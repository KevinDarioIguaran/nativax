import 'package:nativa_leaks/leaks.dart';
import 'package:test/test.dart';

const _mib = 1024 * 1024;

List<LeakSample> _samples({
  List<int>? counter,
  List<int>? engine,
  List<int>? rss,
  int? releaseCounter,
  int? releaseEngine,
}) {
  final n = (counter ?? engine ?? rss)!.length;
  return [
    for (var i = 0; i < n; i++)
      LeakSample(
        batch: i,
        rssBytes: rss?[i] ?? 100 * _mib,
        maxRssBytes: rss?[i] ?? 100 * _mib,
        listeners: counter?[i],
        engineBytes: engine?[i],
      ),
    if (releaseCounter != null || releaseEngine != null)
      LeakSample(
        batch: n,
        rssBytes: 100 * _mib,
        maxRssBytes: 100 * _mib,
        listeners: releaseCounter,
        engineBytes: releaseEngine,
        release: true,
      ),
  ];
}

LeakClass _classOf(List<LeakSample> samples) => classifyLeak(samples).leakClass;

void main() {
  group('Mann-Kendall', () {
    test('strictly increasing n=5 has exact p = 1/120', () {
      final mk = mannKendall([1, 2, 3, 4, 5]);
      expect(mk.s, 10);
      expect(mk.pValue, closeTo(1 / 120, 1e-12));
      expect(mk.method, 'exact-permutation');
    });

    test('a constant series has no trend', () {
      final mk = mannKendall([3, 3, 3, 3, 3]);
      expect(mk.s, 0);
      expect(mk.pValue, 1);
    });

    test('ties are kept in the exact null distribution', () {
      // Only the position of the single low value matters: 5 orderings,
      // one of them reaches S = 4.
      final mk = mannKendall([1, 2, 2, 2, 2]);
      expect(mk.s, 4);
      expect(mk.pValue, closeTo(0.2, 1e-12));
    });

    test('long series use the tie-corrected normal approximation', () {
      final mk = mannKendall([for (var i = 0; i < 20; i++) i.toDouble()]);
      expect(mk.method, 'normal-tie-corrected');
      expect(mk.pValue, lessThan(1e-6));
      final flat = mannKendall([for (var i = 0; i < 20; i++) (i % 2) * 1.0]);
      expect(flat.pValue, greaterThan(0.1));
    });

    test('Theil-Sen slope and normal CDF', () {
      expect(senSlope([0, 2, 4, 6, 100]), 2);
      expect(normalCdf(0), closeTo(0.5, 1e-7));
      expect(normalCdf(1.959964), closeTo(0.975, 1e-6));
    });
  });

  group('classification', () {
    test('monotonic counter growth retained after release is proven', () {
      final c = classifyLeak(
        _samples(counter: [0, 50, 100, 150, 200, 250], releaseCounter: 250),
      );
      expect(c.leakClass, LeakClass.provenLeak);
      expect(c.primaryChannel, 'listeners');
      expect(c.explicitRelease, isTrue);
      final channel = c.channels.firstWhere((ch) => ch['name'] == 'listeners');
      expect((channel['trend'] as Map)['pValue'], closeTo(1 / 120, 1e-12));
      expect(channel['deltas'], [50, 50, 50, 50, 50]);
      expect(channel['peak'], 250);
      expect(channel['retained'], 250);
      expect(c.criteria['alpha'], 0.01);
    });

    test('growth that returns on explicit release is bounded usage', () {
      expect(
        _classOf(
          _samples(counter: [0, 50, 100, 150, 200, 250], releaseCounter: 0),
        ),
        LeakClass.boundedHighUsage,
      );
    });

    test('a fall from an earlier peak is not a return on release', () {
      // Regression (audit.control.noisy_engine): no release step ran, the
      // release sample equals the last batch, and the series had peaked
      // earlier. Comparing the release to the peak called it "returned".
      expect(
        _classOf(
          _samples(
            engine: [154265, 731536, 663974, 667294, 357704, 379616],
            releaseEngine: 379616,
          ),
        ),
        LeakClass.inconclusive,
      );
    });

    test('growth below the effect-size floor is only suspected', () {
      expect(
        _classOf(
          _samples(engine: [100000, 100300, 100600, 100900, 101200, 101500]),
        ),
        LeakClass.suspectedLeak,
      );
    });

    test('a plateau above the baseline is bounded usage', () {
      expect(
        _classOf(_samples(counter: [2, 52, 102, 102, 102, 102])),
        LeakClass.boundedHighUsage,
      );
    });

    test('a curve that saturated is bounded, not a leak', () {
      expect(
        _classOf(_samples(counter: [0, 40, 70, 90, 90, 90])),
        LeakClass.boundedHighUsage,
      );
    });

    test('a one-time warm-up step is not a leak', () {
      expect(_classOf(_samples(counter: [2, 3, 3, 3, 3, 3])), LeakClass.noLeak);
    });

    test('a flat engine heap is no leak', () {
      expect(
        _classOf(
          _samples(engine: [154218, 154265, 154265, 154265, 154265, 154265]),
        ),
        LeakClass.noLeak,
      );
    });

    test('too few batches is inconclusive', () {
      expect(
        _classOf(_samples(counter: [0, 50, 100, 150])),
        LeakClass.inconclusive,
      );
    });

    test('large variation without a trend is inconclusive', () {
      expect(
        _classOf(
          _samples(engine: [100000, 109000, 101000, 108000, 102000, 107000]),
        ),
        LeakClass.inconclusive,
      );
    });

    test('RSS alone can never prove a leak', () {
      final c = classifyLeak(
        _samples(rss: [for (var i = 0; i < 6; i++) (100 + 8 * i) * _mib]),
      );
      expect(c.leakClass, LeakClass.suspectedLeak);
      expect(c.primaryChannel, 'rss');
      expect(c.reason, contains('capped'));
    });

    test('RSS growth never overrides clean precise channels', () {
      // Regression: a fresh process grows RSS ~1.3 MiB/batch during warm-up;
      // audit.control.listeners_balanced was raised to suspected_leak in
      // 2 of 3 separate-process runs.
      final samples = [
        for (var i = 0; i < 6; i++)
          LeakSample(
            batch: i,
            rssBytes: (100 + 8 * i) * _mib,
            maxRssBytes: (100 + 8 * i) * _mib,
            listeners: 0,
          ),
      ];
      final c = classifyLeak(samples);
      expect(c.leakClass, LeakClass.noLeak);
      expect(c.reason, contains('advisory: RSS proven_leak'));
    });

    test('noisy RSS beside a flat counter stays no leak', () {
      final rss = [495, 294, 305, 315, 289, 294];
      final samples = [
        for (var i = 0; i < 6; i++)
          LeakSample(
            batch: i,
            rssBytes: rss[i] * _mib,
            maxRssBytes: 505 * _mib,
            activeRuntimes: 0,
          ),
      ];
      expect(_classOf(samples), LeakClass.noLeak);
    });

    test('the release sample is ignored by the legacy status', () {
      final ctx = LeakContext(LeakProfile.quick);
      ctx.samples.addAll(
        _samples(counter: [0, 0, 0, 0, 0, 0], releaseCounter: 500),
      );
      final result = analyzeLeak(
        LeakCase(
          id: 't',
          subsystem: 't',
          scenario: 't',
          expectation: 'released',
          run: (_) async {},
        ),
        ctx,
        1,
      );
      expect(result.status, LeakStatus.pass);
      expect(result.classification!.explicitRelease, isTrue);
    });

    test('classification and truth survive a JSON round trip', () {
      final ctx = LeakContext(LeakProfile.quick);
      ctx.samples.addAll(
        _samples(counter: [0, 50, 100, 150, 200, 250], releaseCounter: 250),
      );
      final result = analyzeLeak(
        LeakCase(
          id: 'audit.x',
          subsystem: 't',
          scenario: 't',
          expectation: 'retained',
          run: (_) async {},
          truth: const LeakTruth(
            leaks: true,
            expected: 'proven_leak',
            rationale: 'synthetic',
          ),
        ),
        ctx,
        1,
      );
      final run = LeakRun.fromJson(
        LeakRun(
          metadata: LeakRunMetadata.fromJson(const {}),
          results: [result],
        ).toJson(),
      );
      final loaded = run.results.single;
      expect(loaded.classification!.leakClass, LeakClass.provenLeak);
      expect(loaded.truth!.expected, 'proven_leak');
      expect(loaded.samples.last.release, isTrue);
    });
  });
}
