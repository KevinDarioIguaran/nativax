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

  // Only --results-dir is forwarded; use the individual runners for other
  // options.
  final extra = <String>[];
  if (args.length == 2 && args[0] == '--results-dir') {
    extra.addAll(['--results-dir', p.absolute(args[1])]);
  } else if (args.isNotEmpty) {
    stderr.writeln('usage: dart run bin/run_all.dart [--results-dir DIR]');
    exitCode = 64;
    return;
  }
  await run('run_html5lib.dart', extra);
  await run('run_html_tree.dart', extra);
  await run('run_url.dart', extra);
  await run('run_test262.dart', extra);
  await run('run_wpt.dart', extra);
  if (failed) exitCode = 1;
}
