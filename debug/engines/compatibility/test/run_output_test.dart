import 'dart:convert';
import 'dart:io';

import 'package:nativa_conformance/conformance.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

RunSummary _summary(String suite, DateTime at) => RunSummary(
  suite: suite,
  startedAt: at,
  durationMs: 1500,
  results: [
    TestResult(suite: suite, id: 'a', status: ResultStatus.pass),
    TestResult(suite: suite, id: 'b', status: ResultStatus.skip),
  ],
);

void main() {
  late Directory repo;
  setUp(() => repo = Directory.systemTemp.createTempSync('nx_out_'));
  tearDown(() => repo.deleteSync(recursive: true));

  test('--results-dir writes every file there and no tracked file', () {
    final out = p.join(repo.path, 'report', 'compat');
    final output = RunOutput(repo.path, resultsDirectory: out);
    final files = output.write(_summary('wpt-url', DateTime(2026, 10, 26, 9)));
    for (final f in [files.jsonl, files.summary, files.markdown]) {
      expect(p.isWithin(out, f), isTrue, reason: f);
      expect(File(f).existsSync(), isTrue);
    }
    expect(Directory(p.join(repo.path, 'progress')).existsSync(), isFalse);
    expect(
      Directory(p.join(repo.path, 'debug', 'artifacts')).existsSync(),
      isFalse,
    );
  });

  test(
    'the default keeps debug/artifacts/conformance/results and the tracked latest copy',
    () {
      final output = RunOutput(repo.path);
      final files = output.write(
        _summary('test262', DateTime(2026, 10, 26, 9)),
      );
      expect(
        p.isWithin(
          p.join(repo.path, 'debug', 'artifacts', 'conformance', 'results'),
          files.summary,
        ),
        isTrue,
      );
      expect(
        File(
          p.join(repo.path, 'progress', 'reports', 'test262-latest.md'),
        ).existsSync(),
        isTrue,
      );
    },
  );

  test('summary records runner version, revision and a zoned timestamp', () {
    final output = RunOutput(repo.path, resultsDirectory: repo.path);
    final files = output.write(_summary('wpt', DateTime(2026, 10, 26, 9, 5)));
    final json = (jsonDecode(File(files.summary).readAsStringSync()) as Map)
        .cast<String, Object?>();
    expect(json['runnerVersion'], runnerVersion);
    expect(json.containsKey('suiteCommit'), isTrue);
    expect(json['timeZone'], isA<String>());
    final started = json['startedAt'] as String;
    expect(started, matches(RegExp(r'(Z|[+-]\d{2}:\d{2})$')));
    expect(
      DateTime.parse(started).isAtSameMomentAs(DateTime(2026, 10, 26, 9, 5)),
      isTrue,
    );
    expect(
      DateTime.parse(
        json['finishedAt'] as String,
      ).difference(DateTime.parse(started)),
      const Duration(milliseconds: 1500),
    );
  });

  test('isoWithOffset keeps UTC as Z', () {
    expect(
      isoWithOffset(DateTime.utc(2026, 1, 2, 3, 4, 5)),
      '2026-01-02T03:04:05.000Z',
    );
  });

  test('the wpt baseline never picks a wpt-url or wpt-html-tree summary', () {
    final output = RunOutput(repo.path, resultsDirectory: repo.path);
    output.write(_summary('wpt', DateTime(2026, 1, 1)));
    output.write(_summary('wpt-url', DateTime(2026, 2, 1)));
    output.write(_summary('wpt-html-tree', DateTime(2026, 3, 1)));
    final baseline = output.loadBaseline('wpt');
    expect(baseline?.suite, 'wpt');
  });

  test('the fixtures inside the NativaX checkout have no suite revision', () {
    final data = ValidationDataset(ValidationDataset.inRepo(findRepoRoot()));
    expect(suiteRevision(data.wpt), isNull);
    expect(suiteRevision(repo.path), isNull);
  });

  test('runnerVersion matches the package version', () {
    final pubspec = File(
      p.join(
        findRepoRoot(),
        'debug',
        'engines',
        'compatibility',
        'pubspec.yaml',
      ),
    ).readAsStringSync();
    expect(pubspec, contains('version: $runnerVersion'));
  });
}
