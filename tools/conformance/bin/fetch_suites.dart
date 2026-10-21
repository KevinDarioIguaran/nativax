import 'dart:io';

import 'package:path/path.dart' as p;

import '../lib/src/suite_paths.dart';

/// Pinned revisions keep conformance numbers reproducible. Update these
/// deliberately (and record the change in progress/log.md).
const _suites = <String, _Suite>{
  'test262': _Suite(
    url: 'https://github.com/tc39/test262.git',
    commit: 'd53ebc8b1931d9f1541e43d59650776e4b766248',
    sparse: [
      'harness',
      'test/language/expressions',
      'test/language/statements',
      'test/language/types',
      'test/language/literals',
      'test/built-ins/Object',
      'test/built-ins/Array',
      'test/built-ins/String',
    ],
    shallow: true,
    filterBlobs: true,
  ),
  'html5lib': _Suite(
    url: 'https://github.com/html5lib/html5lib-tests.git',
    commit: 'c777c408b61078ea2eb4acefc2535f54dbc8b28a',
    sparse: [],
    shallow: true,
    filterBlobs: false,
  ),
  'wpt': _Suite(
    url: 'https://github.com/web-platform-tests/wpt.git',
    commit: 'e7d77cd1e0353d7b37ce35eb912b6992df8dfab0',
    sparse: [
      'resources',
      'dom/nodes',
      'dom/events',
      'css/selectors',
      'html/syntax/parsing',
      'url/resources',
    ],
    shallow: true,
    filterBlobs: true,
  ),
};

class _Suite {
  const _Suite({
    required this.url,
    required this.commit,
    required this.sparse,
    required this.shallow,
    required this.filterBlobs,
  });
  final String url;
  final String commit;
  final List<String> sparse;
  final bool shallow;
  final bool filterBlobs;
}

Future<void> main(List<String> args) async {
  final root = findRepoRoot();
  final suites = suitesDir(root);
  Directory(suites).createSync(recursive: true);

  final requested = <String>[];
  var force = false;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--suite':
        requested.add(args[++i]);
      case '--all':
        requested.addAll(_suites.keys);
      case '--force':
        force = true;
      case '-h' || '--help':
        stdout.writeln('usage: dart run bin/fetch_suites.dart '
            '[--suite test262|html5lib|wpt|all] [--force]');
        return;
      default:
        stderr.writeln('unknown argument: ${args[i]}');
        exitCode = 64;
        return;
    }
  }
  if (requested.isEmpty) requested.addAll(_suites.keys);

  for (final name in requested) {
    final spec = _suites[name];
    if (spec == null) {
      stderr.writeln('unknown suite: $name');
      exitCode = 64;
      return;
    }
    final dirName = name == 'html5lib' ? 'html5lib-tests' : name;
    await _fetch(name, spec, p.join(suites, dirName), force: force);
  }
}

Future<void> _fetch(
  String name,
  _Suite spec,
  String dest, {
  required bool force,
}) async {
  final dir = Directory(dest);
  if (force && dir.existsSync()) {
    stdout.writeln('removing $dest');
    dir.deleteSync(recursive: true);
  }
  if (!dir.existsSync()) {
    stdout.writeln('cloning $name into $dest ...');
    final cloneArgs = <String>[
      'clone',
      if (spec.shallow) '--depth',
      if (spec.shallow) '1',
      if (spec.filterBlobs) '--filter=blob:none',
      if (spec.sparse.isNotEmpty) '--sparse',
      spec.url,
      dest,
    ];
    await _run('git', cloneArgs);
  }

  await _run('git', ['fetch', '--depth', '1', 'origin', spec.commit],
      workingDirectory: dest);
  await _run('git', ['checkout', '--detach', spec.commit],
      workingDirectory: dest);
  if (spec.sparse.isNotEmpty) {
    await _run('git', ['sparse-checkout', 'set', ...spec.sparse],
        workingDirectory: dest);
  }
  final head = await _run('git', ['rev-parse', 'HEAD'],
      workingDirectory: dest, capture: true);
  final lines = (head.stdout as String).trim();
  if (!lines.startsWith(spec.commit)) {
    stderr.writeln('warning: $name is at $lines, expected ${spec.commit}');
  }
  stdout.writeln('$name ready at $dest (${lines.substring(0, 12)})');
}

Future<ProcessResult> _run(
  String executable,
  List<String> args, {
  String? workingDirectory,
  bool capture = false,
}) async {
  final result = await Process.run(
    executable,
    args,
    workingDirectory: workingDirectory,
    runInShell: false,
    stdoutEncoding: capture ? systemEncoding : systemEncoding,
  );
  if (result.exitCode != 0) {
    stderr
      ..writeln('command failed: $executable ${args.join(' ')}')
      ..writeln(result.stdout)
      ..writeln(result.stderr);
    throw ProcessException(executable, args, 'exit ${result.exitCode}');
  }
  if (!capture && args.isNotEmpty && args.first != 'rev-parse') {
    final out = '${result.stdout}'.trim();
    if (out.isNotEmpty) stdout.writeln(out);
  }
  return result;
}
