import 'dart:io';

import 'package:path/path.dart' as p;

/// Locates the NativaX repository root by walking up from [start] until a
/// workspace `pubspec.yaml` is found.
String findRepoRoot([String? start]) {
  var dir = Directory(p.absolute(start ?? Directory.current.path));
  while (true) {
    final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('nativa_workspace')) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('could not find the NativaX repository root');
    }
    dir = parent;
  }
}

/// Root of the downloaded external suites (`<repo>/.conformance/suites`).
String suitesDir(String repoRoot) =>
    p.join(repoRoot, '.conformance', 'suites');

/// Root of raw JSONL results (`<repo>/.conformance/results`).
String resultsDir(String repoRoot) =>
    p.join(repoRoot, '.conformance', 'results');

/// Where the human-readable baselines live (`<repo>/progress/reports`).
String reportsDir(String repoRoot) => p.join(repoRoot, 'progress', 'reports');

String test262Dir(String repoRoot) =>
    p.join(suitesDir(repoRoot), 'test262');

String html5libDir(String repoRoot) =>
    p.join(suitesDir(repoRoot), 'html5lib-tests');

String wptDir(String repoRoot) => p.join(suitesDir(repoRoot), 'wpt');

String timestampForFile(DateTime time) =>
    '${time.year.toString().padLeft(4, '0')}-'
    '${time.month.toString().padLeft(2, '0')}-'
    '${time.day.toString().padLeft(2, '0')}T'
    '${time.hour.toString().padLeft(2, '0')}'
    '${time.minute.toString().padLeft(2, '0')}'
    '${time.second.toString().padLeft(2, '0')}';
