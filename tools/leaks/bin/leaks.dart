import 'dart:io';

import 'package:nativax_leaks/leaks.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first == 'run') {
    await _run(args.isEmpty ? args : args.sublist(1));
    return;
  }
  if (args.first == 'compare') {
    await _compare(args.sublist(1));
    return;
  }
  _usage();
  exitCode = 64;
}

Future<void> _run(List<String> args) async {
  var profileName = 'quick';
  int? batches;
  int? iterations;
  int? settleMs;
  String? only;
  String? outDir;
  String? jsonPath;
  String? jsonlPath;
  String? markdownPath;
  var list = false;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--profile':
        profileName = args[++i];
      case '--batches':
        batches = int.parse(args[++i]);
      case '--iterations':
        iterations = int.parse(args[++i]);
      case '--settle-ms':
        settleMs = int.parse(args[++i]);
      case '--only':
        only = args[++i];
      case '--out':
        outDir = args[++i];
      case '--json':
        jsonPath = args[++i];
      case '--jsonl':
        jsonlPath = args[++i];
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

  final base = switch (profileName) {
    'quick' => LeakProfile.quick,
    'full' => LeakProfile.full,
    'stress' => LeakProfile.stress,
    _ => null,
  };
  if (base == null) {
    stderr.writeln('unknown profile: $profileName (quick|full|stress)');
    exitCode = 64;
    return;
  }
  final profile = LeakProfile(
    name: base.name,
    batches: batches ?? base.batches,
    iterations: iterations ?? base.iterations,
    settle: settleMs == null
        ? base.settle
        : Duration(milliseconds: settleMs),
    maxDuration: base.maxDuration,
    rssGrowthBytesPerBatch: base.rssGrowthBytesPerBatch,
    engineGrowthBytesPerBatch: base.engineGrowthBytesPerBatch,
    resourceGrowthThreshold: base.resourceGrowthThreshold,
    minMonotonicRun: base.minMonotonicRun,
  );

  final cases = allLeakCases().where((c) {
    if (only == null) return true;
    return c.id.contains(only) || c.subsystem.contains(only);
  }).toList();

  if (list) {
    for (final c in cases) {
      stdout.writeln('${c.id} [${c.subsystem}] ${c.scenario}');
    }
    return;
  }
  if (cases.isEmpty) {
    stderr.writeln('no leak cases selected');
    exitCode = 2;
    return;
  }

  stdout.writeln('NativaX leaks: ${cases.length} cases, '
      'profile=${profile.name} batches=${profile.batches} '
      'iterations=${profile.iterations}');
  final runner = LeakRunner(
    profile,
    onProgress: (id, i, total) => stdout.writeln('  [$i/$total] $id'),
  );
  final results = await runner.run(cases);
  final root = findLeakRepoRoot();
  final run = LeakRun(
    metadata: collectLeakMetadata(
      repoRoot: root,
      profile: profile.name,
      command: 'leaks ${args.join(' ')}'.trim(),
    ),
    results: results,
  );
  final output = outDir ?? p.join(root, 'benchmarks', 'leaks');
  final files = writeLeakReport(
    run,
    outputDir: output,
    jsonPath: jsonPath,
    jsonlPath: jsonlPath,
    markdownPath: markdownPath,
  );

  for (final r in results) {
    stdout.writeln('  ${r.status.label.padRight(13)} ${r.id.padRight(26)} '
        '${r.reason}');
  }
  final fail = results.where((r) => r.status == LeakStatus.fail).length;
  final error = results.where((r) => r.status == LeakStatus.error).length;
  final inconclusive =
      results.where((r) => r.status == LeakStatus.inconclusive).length;
  stdout
    ..writeln()
    ..writeln('PASS ${results.where((r) => r.status == LeakStatus.pass).length}'
        '  FAIL $fail  SKIP '
        '${results.where((r) => r.status == LeakStatus.skip).length}'
        '  ERROR $error  INCONCLUSIVE $inconclusive')
    ..writeln('JSON:  ${files.json}')
    ..writeln('JSONL: ${files.jsonl}')
    ..writeln('MD:    ${files.markdown}');
  if (fail > 0 || error > 0) exitCode = 2;
}

Future<void> _compare(List<String> args) async {
  String? baseline;
  String? current;
  String? markdown;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--baseline':
        baseline = args[++i];
      case '--current':
        current = args[++i];
      case '--md':
        markdown = args[++i];
      case '-h' || '--help':
        _usage();
        return;
      default:
        stderr.writeln('unknown argument: ${args[i]}');
        exitCode = 64;
        return;
    }
  }
  if (baseline == null || current == null) {
    stderr.writeln('compare requires --baseline and --current');
    exitCode = 64;
    return;
  }
  final changes = compareLeakRuns(loadLeakRun(baseline), loadLeakRun(current));
  final text = renderLeakComparison(changes,
      baseline: baseline, current: current);
  stdout.write(text);
  if (markdown != null) {
    Directory(p.dirname(markdown)).createSync(recursive: true);
    File(markdown).writeAsStringSync(text);
  }
  if (changes.any((c) => c.status == 'regression')) exitCode = 2;
}

List<LeakCase> allLeakCases() => [
      releaseControl(),
      retainedControl(),
      ...jsLeakCases(),
      ...domLeakCases(),
      ...cssLeakCases(),
      ...runtimeLeakCases(),
    ];

void _usage() {
  stdout
    ..writeln('usage:')
    ..writeln('  dart run bin/leaks.dart run [--profile quick|full|stress]')
    ..writeln('    [--batches N] [--iterations N] [--settle-ms N]')
    ..writeln('    [--only TEXT] [--list] [--out DIR]')
    ..writeln('    [--json FILE] [--jsonl FILE] [--md FILE]')
    ..writeln('  dart run bin/leaks.dart compare --baseline JSON --current JSON')
    ..writeln('    [--md FILE]');
}
