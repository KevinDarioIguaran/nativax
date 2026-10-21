import 'package:nativax_benchmark/benchmark.dart';
import 'package:test/test.dart';

void main() {
  test('runner performs warmup + rounds and keeps the checksum', () {
    var calls = 0;
    final result = BenchmarkRunner(rounds: 4, warmup: 2).runOne(
      BenchmarkCase(
        name: 'fake',
        category: 'test',
        operations: 10,
        body: () {
          calls++;
          return 1;
        },
      ),
    );
    expect(calls, 6);
    expect(result.rounds, 4);
    expect(result.samplesMs.length, 4);
    expect(result.medianMs, greaterThan(0));
    expect(result.checksum, 1);
  });

  test('runner rejects a checksum mismatch', () {
    expect(
      () => BenchmarkRunner(rounds: 2, warmup: 1).runOne(
        BenchmarkCase(
          name: 'bad',
          category: 'test',
          body: () => DateTime.now().microsecondsSinceEpoch,
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('runner rejects a wrong expected checksum', () {
    expect(
      () => BenchmarkRunner(rounds: 2, warmup: 1).runOne(
        BenchmarkCase(
          name: 'bad',
          category: 'test',
          expected: 2,
          body: () => 1,
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('steady-state JavaScript cases compile once and preserve checksums', () {
    final suite = JsBenchmarks();
    addTearDown(suite.dispose);
    final steady = suite
        .cases()
        .where((c) => c.category == 'js_steady')
        .toList();
    expect(steady, hasLength(9));
    expect(steady.map((c) => c.name), contains('js_steady.recursion'));
    final recursion = steady.firstWhere((c) => c.name == 'js_steady.recursion');
    expect(recursion.body(), 46368);
    expect(recursion.body(), 46368);
  });

  test('median, MAD and stddev are computed from real samples', () {
    final result = BenchmarkResult(
      name: 'stats',
      category: 'test',
      unit: 'ops',
      operations: 1,
      rounds: 5,
      warmup: 1,
      samplesMs: [1, 2, 3, 4, 100],
      checksum: 1,
    );
    expect(result.medianMs, 3);
    expect(result.minMs, 1);
    expect(result.maxMs, 100);
    expect(result.madMs, 1);
    expect(result.stdDevMs, greaterThan(0));
  });
}
