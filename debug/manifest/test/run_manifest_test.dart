import 'dart:convert';
import 'dart:io';

import 'package:nativa_run_manifest/nativa_run_manifest.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nativa-run-manifest-');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  test('creates a unique UTC run directory under debug/benchmarks', () {
    final dir = createRunDirectory(
      tmp.path,
      'leaks',
      now: DateTime.utc(2026, 10, 25, 21, 44, 37),
      revision: 'f47240e',
    );
    expect(p.basename(dir.path), '20261025T214437Z-f47240e');
    expect(p.dirname(dir.path),
        p.join(tmp.path, 'debug', 'benchmarks', 'leaks'));
    expect(dir.existsSync(), isTrue);
  });

  test('a second run in the same second gets a numeric suffix', () {
    final first = createRunDirectory(
      tmp.path,
      'microbench',
      now: DateTime.utc(2026, 10, 25, 21, 44, 37),
      revision: 'f47240e',
    );
    final second = createRunDirectory(
      tmp.path,
      'microbench',
      now: DateTime.utc(2026, 10, 25, 21, 44, 37),
      revision: 'f47240e',
    );
    expect(p.basename(first.path), '20261025T214437Z-f47240e');
    expect(p.basename(second.path), '20261025T214437Z-f47240e-2');
  });

  test('manifest follows the shared schema and counts only engine evidence',
      () {
    final dir = createRunDirectory(
      tmp.path,
      'security',
      now: DateTime.utc(2026, 10, 25, 21, 44, 37),
      revision: 'f47240e',
    );
    File(p.join(dir.path, 'security-x.json')).writeAsStringSync('{"a":1}');
    File(p.join(dir.path, 'security-x.md')).writeAsStringSync('# ok');
    File(p.join(dir.path, '.manifest.json.tmp')).writeAsStringSync('ignored');

    writeRunManifest(
      dir,
      repoRoot: tmp.path,
      area: 'security',
      engine: 'nativa_security',
      argv: const ['run', '--only', 'bridge'],
    );

    final manifest = jsonDecode(
      File(p.join(dir.path, 'manifest.json')).readAsStringSync(),
    ) as Map<String, dynamic>;

    expect(manifest['schema_version'], '1.0');
    expect(manifest['run_id'], p.basename(dir.path));
    expect(manifest['area'], 'security');
    expect(manifest['engine'], 'nativa_security');
    expect(manifest['status'], 'completed');
    expect(manifest['argv'], ['run', '--only', 'bridge']);
    expect(manifest['git_revision'],
        isNull); // tmp is not a checkout and gets no revision.
    expect(manifest['source'],
        p.join('debug', 'benchmarks', 'security', p.basename(dir.path)));
    expect(manifest['evidence'], {'files': 2, 'bytes': 11});
    expect(manifest['reports'], ['security-x.md']);
    expect(File(p.join(dir.path, '.manifest.json.tmp')).existsSync(), isFalse);
    expect(
      RegExp(r'^\d{8}T\d{6}Z(-[0-9a-f]{7,40})?(-[0-9]{1,3})?$')
          .hasMatch(manifest['run_id'] as String),
      isTrue,
    );
    expect(
      RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}([+-]\d{2}:\d{2}|Z)$')
          .hasMatch(manifest['archived_at'] as String),
      isTrue,
    );
  });

  test('rejects an unknown status', () {
    final dir = createRunDirectory(tmp.path, 'microbench');
    expect(
      () => writeRunManifest(
        dir,
        repoRoot: tmp.path,
        area: 'microbench',
        engine: 'nativa_benchmark',
        argv: const [],
        status: 'nope',
      ),
      throwsArgumentError,
    );
  });

  test('rejects an invalid area name', () {
    expect(
      () => createRunDirectory(tmp.path, 'Micro Bench'),
      throwsArgumentError,
    );
  });
}
