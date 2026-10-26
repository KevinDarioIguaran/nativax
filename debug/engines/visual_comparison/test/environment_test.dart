import 'package:nativa_visual/src/environment.dart';
import 'package:test/test.dart';

final _iso = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}[+-]\d{2}:\d{2}$',
);

void main() {
  test('timestamps are ISO-8601 with an explicit offset', () {
    final value = isoWithOffset(DateTime.utc(2026, 10, 26, 12, 30, 5, 7, 9));
    expect(value, matches(_iso));
    // Re-parsing the string yields the same instant.
    expect(
      DateTime.parse(value).toUtc(),
      DateTime.utc(2026, 10, 26, 12, 30, 5, 7),
    );
  });

  test('a time without milliseconds still has three fraction digits', () {
    expect(isoWithOffset(DateTime(2026, 1, 2, 3, 4, 5)), matches(_iso));
  });

  test('capture window records start, finish and duration', () {
    final json = CaptureWindow(
      DateTime.utc(2026, 10, 26, 12),
      DateTime.utc(2026, 10, 26, 12, 0, 1, 250),
    ).toJson();
    expect(json['startedAt'], matches(_iso));
    expect(json['finishedAt'], matches(_iso));
    expect(json['durationMs'], 1250);
  });

  test('page environment carries every documented field', () {
    final env = pageEnvironment(
      page: 'suite/page',
      mode: 'judge',
      viewportWidth: 800,
      viewportHeight: 900,
      referenceDpr: 1,
      actualDpr: 1,
      scheme: 'dark',
      reference: const {'engine': 'chromium', 'version': 'Chrome 1'},
      actual: const {'engine': 'nativax', 'jsEngine': 'v8'},
      git: const GitRevision('abc123', false),
      generatedAt: DateTime.utc(2026),
    );
    expect(env['schema'], 'nativa_visual.environment/1');
    expect(env['viewport'], {'width': 800, 'height': 900});
    expect(env['devicePixelRatio'], {'reference': 1.0, 'actual': 1.0});
    expect(env['scheme'], 'dark');
    expect((env['actual'] as Map)['jsEngine'], 'v8');
    expect(env['git'], {'revision': 'abc123', 'dirty': false});
    expect(env['fonts'], contains('Noto Sans'));
    expect(env['generatedAt'], matches(_iso));
  });

  test(
    'git revision of this checkout is readable or reported unknown',
    () async {
      final git = await readGitRevision('.');
      if (git.revision != null) {
        expect(git.revision, matches(RegExp(r'^[0-9a-f]{40}$')));
      } else {
        expect(git.dirty, isNull);
      }
    },
  );
}
