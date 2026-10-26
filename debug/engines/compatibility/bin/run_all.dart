import 'dart:io';

import 'package:path/path.dart' as p;

import '../lib/src/suite_paths.dart';

/// Runs the available suites sequentially and stops on a runner failure.
///
/// The external checkouts must exist first:
/// `dart run bin/fetch_suites.dart --suite test262 --suite html5lib --suite wpt`
Future<void> main(List<String> args) async {
  final root = findRepoRoot();
  final dir = p.join(root, 'debug', 'engines', 'compatibility');
  var failed = false;
  Future<void> run(String bin, List<String> extra) async {
    stdout.writeln('\n=== $bin ===');
    final result = await Process.run(
      Platform.resolvedExecutable,
      ['run', p.join('bin', bin), ...extra],
      workingDirectory: dir,
      runInShell: false,
    );
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    if (result.exitCode != 0) {
      failed = true;
      stderr.writeln('$bin failed with exit ${result.exitCode}');
    }
  }

  if (args.isNotEmpty) {
    stderr.writeln('run_all takes no arguments; use the individual runners '
        'to pass options.');
    exitCode = 64;
    return;
  }
  await run('run_html5lib.dart', const []);
  await run('run_html_tree.dart', const []);
  await run('run_url.dart', const []);
  await run('run_test262.dart', const []);
  await run('run_wpt.dart', const []);
  if (failed) exitCode = 1;
}
