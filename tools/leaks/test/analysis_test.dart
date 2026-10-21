import 'package:nativax_leaks/leaks.dart';
import 'package:test/test.dart';

LeakCase _case(String expectation) => LeakCase(
      id: 'test',
      subsystem: 'test',
      scenario: 'synthetic',
      expectation: expectation,
      run: (_) async {},
    );

LeakContext _context(LeakProfile profile) => LeakContext(profile);

void _add(LeakContext c, int batch,
    {int rss = 1000000, int? engine, int? nodes, int? listeners,
    int? activeRuntimes}) {
  c.samples.add(LeakSample(
    batch: batch,
    rssBytes: rss,
    maxRssBytes: rss,
    engineBytes: engine,
    nodes: nodes,
    listeners: listeners,
    activeRuntimes: activeRuntimes,
  ));
}

void main() {
  test('released with stable resource counters passes', () {
    final ctx = _context(LeakProfile.quick);
    for (var i = 0; i <= 5; i++) {
      _add(ctx, i, nodes: 10, listeners: 0);
    }
    final result = analyzeLeak(_case('released'), ctx, 1);
    expect(result.status, LeakStatus.pass);
  });

  test('released with growing listeners fails', () {
    final ctx = _context(LeakProfile.quick);
    for (var i = 0; i <= 5; i++) {
      _add(ctx, i, nodes: 10, listeners: i * 100);
    }
    final result = analyzeLeak(_case('released'), ctx, 1);
    expect(result.status, LeakStatus.fail);
  });

  test('retained control with growth passes', () {
    final ctx = _context(LeakProfile.quick);
    for (var i = 0; i <= 5; i++) {
      _add(ctx, i, activeRuntimes: i);
    }
    final result = analyzeLeak(_case('retained'), ctx, 1);
    expect(result.status, LeakStatus.pass);
  });

  test('retained control without growth fails (detector blind)', () {
    final ctx = _context(LeakProfile.quick);
    for (var i = 0; i <= 5; i++) {
      _add(ctx, i, activeRuntimes: 0);
    }
    final result = analyzeLeak(_case('retained'), ctx, 1);
    expect(result.status, LeakStatus.fail);
  });

  test('RSS growth without resource counters is inconclusive', () {
    final ctx = _context(LeakProfile.quick);
    for (var i = 0; i <= 5; i++) {
      _add(ctx, i, rss: 1000000 + i * 10000000);
    }
    final result = analyzeLeak(_case('released'), ctx, 1);
    expect(result.status, LeakStatus.inconclusive);
  });

  test('bounded cache with stable counters passes', () {
    final ctx = _context(LeakProfile.quick);
    for (var i = 0; i <= 5; i++) {
      _add(ctx, i, nodes: 500);
    }
    final result = analyzeLeak(_case('bounded'), ctx, 1);
    expect(result.status, LeakStatus.pass);
  });

  test('engine heap sustained growth fails', () {
    final ctx = _context(LeakProfile.quick);
    for (var i = 0; i <= 5; i++) {
      _add(ctx, i, engine: 1000000 + i * 2000000);
    }
    final result = analyzeLeak(_case('released'), ctx, 1);
    expect(result.status, LeakStatus.fail);
    expect(result.evidence.any((e) => e.contains('QuickJS')), isTrue);
  });
}
