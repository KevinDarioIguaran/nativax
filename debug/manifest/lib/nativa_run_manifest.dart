/// Immutable per-run directories for the NativaX benchmark engines.
///
/// Every execution gets its own directory:
///
///     debug/benchmarks/<area>/<run_id>/
///         bench-<stamp>.json     engine output
///         bench-<stamp>.md       human-readable report
///         manifest.json          versioned, schema-validated record
///
/// `<run_id>` is `<UTC ISO basic>Z[-<git short sha>][-N]`, so lexicographic
/// order is chronological order. `manifest.json` follows
/// `debug/logic/schemas/run-manifest.schema.json` (schema 1.0), the same
/// contract used by `debug/logic/storage.py` for archived panel runs.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

const schemaVersion = '1.0';
const _statuses = {'completed', 'failed', 'aborted'};
const _areaPattern = r'^[a-z0-9][a-z0-9_-]{0,31}$';

/// Short commit of the checkout that contains [repoRoot], or an empty string
/// when git is unavailable or the directory is not a checkout.
String repoRevision(String repoRoot) {
  try {
    final result = Process.runSync(
      'git',
      ['rev-parse', '--short', 'HEAD'],
      workingDirectory: repoRoot,
    );
    if (result.exitCode == 0) return (result.stdout as String).trim();
  } on ProcessException {
    // Not a checkout, or git is not installed: the manifest records null.
  }
  return '';
}

/// Creates a new, unique run directory under
/// `<repoRoot>/debug/benchmarks/<area>/`.
///
/// The id uses the UTC time in basic ISO format, the repository revision when
/// available and a numeric suffix on collision, so two runs never share a
/// directory and every run is preserved.
Directory createRunDirectory(
  String repoRoot,
  String area, {
  DateTime? now,
  String? revision,
}) {
  if (!RegExp(_areaPattern).hasMatch(area)) {
    throw ArgumentError.value(area, 'area', 'invalid benchmark area');
  }
  final utc = (now ?? DateTime.now()).toUtc();
  final stamp = '${utc.year.toString().padLeft(4, '0')}'
      '${utc.month.toString().padLeft(2, '0')}'
      '${utc.day.toString().padLeft(2, '0')}T'
      '${utc.hour.toString().padLeft(2, '0')}'
      '${utc.minute.toString().padLeft(2, '0')}'
      '${utc.second.toString().padLeft(2, '0')}Z';
  final rev = (revision ?? repoRevision(repoRoot)).trim();
  final base = rev.isEmpty ? stamp : '$stamp-$rev';
  final areaRoot = Directory(p.join(repoRoot, 'debug', 'benchmarks', area));
  var run = Directory(p.join(areaRoot.path, base));
  var counter = 2;
  while (run.existsSync()) {
    run = Directory(p.join(areaRoot.path, '$base-$counter'));
    counter++;
  }
  run.createSync(recursive: true);
  return run;
}

/// Writes `manifest.json` into [runDir] after the engine finished writing its
/// evidence.
///
/// The manifest is validated by `debug/logic/storage.py` (same JSON Schema) and
/// replaces any previous temporary file atomically. Counting excludes the
/// manifest itself, so `evidence` describes only the engine output.
void writeRunManifest(
  Directory runDir, {
  required String repoRoot,
  required String area,
  required String engine,
  required List<String> argv,
  String status = 'completed',
  String? notes,
}) {
  if (!_statuses.contains(status)) {
    throw ArgumentError.value(status, 'status', 'unknown status');
  }
  if (!runDir.existsSync()) {
    throw ArgumentError.value(runDir.path, 'runDir', 'does not exist');
  }

  var files = 0;
  var bytes = 0;
  final reports = <String>[];
  for (final entity in runDir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final name = p.basename(entity.path);
    if (name == 'manifest.json' || name == '.manifest.json.tmp') continue;
    files++;
    bytes += entity.lengthSync();
    if (name.endsWith('.md')) reports.add(name);
  }
  reports.sort();

  final revision = repoRevision(repoRoot);
  final manifest = <String, Object?>{
    'schema_version': schemaVersion,
    'run_id': p.basename(runDir.path),
    'area': area,
    'engine': engine,
    'status': status,
    'archived_at': _utcSeconds(DateTime.now()),
    'git_revision': revision.isEmpty ? null : revision,
    'argv': argv,
    'source': p.relative(runDir.path, from: repoRoot),
    'evidence': {'files': files, 'bytes': bytes},
    'reports': reports,
    'notes': notes,
  };
  final tmp = File(p.join(runDir.path, '.manifest.json.tmp'));
  tmp.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
  );
  tmp.renameSync(p.join(runDir.path, 'manifest.json'));
}

String _utcSeconds(DateTime time) =>
    '${time.toUtc().toIso8601String().substring(0, 19)}Z';
