import 'dart:io';

import 'package:nativa_security/security.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first == 'run') {
    await _run(args.isEmpty ? args : args.sublist(1));
    return;
  }
  _usage();
  exitCode = 64;
}

Future<void> _run(List<String> args) async {
  String? only;
  String? outDir;
  String? jsonPath;
  String? markdownPath;
  var list = false;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--only':
        only = args[++i];
      case '--out':
        outDir = args[++i];
      case '--json':
        jsonPath = args[++i];
      case '--md':
        markdownPath = args[++i];
      case '--list':
        list = true;
      case '-h' || '--help':
        _usage();
        return;
      default:
        stderr.writeln('unknown argument: ${args[i]}');
        exitCode = 64;
        return;
    }
  }
  final cases = securityCases().where((c) {
    if (only == null) return true;
    return c.id.contains(only) || c.category.contains(only);
  }).toList();
  if (list) {
    for (final c in cases) {
      stdout.writeln('${c.id} [${c.category}/${c.severity}] ${c.description}');
    }
    return;
  }
  if (cases.isEmpty) {
    stderr.writeln('no security cases selected');
    exitCode = 2;
    return;
  }

  stdout.writeln('NativaX security: ${cases.length} cases');
  final results =
      await SecurityRunner(onProgress: (id, i, total) {
    stdout.writeln('  [$i/$total] $id');
  }).run(cases);
  final root = findSecurityRepoRoot();
  final run = SecurityRun(
    metadata: collectSecurityMetadata(
      repoRoot: root,
      command: 'security ${args.join(' ')}'.trim(),
    ),
    results: results,
  );
  final output = outDir ?? p.join(root, 'benchmarks', 'security');
  final files = writeSecurityReport(
    run,
    outputDir: output,
    jsonPath: jsonPath,
    markdownPath: markdownPath,
  );
  for (final r in results) {
    stdout.writeln('  ${r.status.label.padRight(13)} ${r.id.padRight(38)} '
        '${r.observed}');
  }
  final failures =
      results.where((r) => r.status == SecurityStatus.fail).length;
  final errors =
      results.where((r) => r.status == SecurityStatus.error).length;
  final skips =
      results.where((r) => r.status == SecurityStatus.skip).length;
  stdout
    ..writeln()
    ..writeln('PASS ${results.where((r) => r.status == SecurityStatus.pass).length}'
        '  FAIL $failures  SKIP $skips  ERROR $errors')
    ..writeln('JSON: ${files.json}')
    ..writeln('MD:   ${files.markdown}');
  if (failures > 0 || errors > 0) exitCode = 2;
}

void _usage() {
  stdout
    ..writeln('usage: dart run bin/security.dart run [--only TEXT] [--list]')
    ..writeln('  [--out DIR] [--json FILE] [--md FILE]');
}
