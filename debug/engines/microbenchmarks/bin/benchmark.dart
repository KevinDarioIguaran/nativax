import 'dart:io';

import 'package:nativa_benchmark/benchmark.dart';
import 'package:nativa_run_manifest/nativa_run_manifest.dart';
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
  if (args.first == '-h' || args.first == '--help') {
    _usage();
    return;
  }
  stderr.writeln('unknown command: ${args.first}');
  _usage();
  exitCode = 64;
}

Future<void> _run(List<String> args) async {
  var rounds = 15;
  var warmup = 3;
  var includeJs = true;
  var includeDom = true;
  var includeDart = true;
  var list = false;
  String? only;
  String? outDir;
  String? jsonPath;
  String? markdownPath;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--rounds':
        rounds = int.parse(args[++i]);
      case '--warmup':
        warmup = int.parse(args[++i]);
      case '--no-js':
        includeJs = false;
      case '--no-dom':
        includeDom = false;
      case '--no-dart':
        includeDart = false;
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
  if (rounds < 3) {
    stderr.writeln('--rounds must be at least 3');
    exitCode = 64;
    return;
  }
  if (warmup < 1) {
    stderr.writeln('--warmup must be at least 1');
    exitCode = 64;
    return;
  }

  final root = findRepoRoot();
  final js = includeJs ? JsBenchmarks() : null;
  final dom = includeDom ? DomBenchmarks() : null;
  final cases = <BenchmarkCase>[
    if (js != null) ...js.cases(),
    if (dom != null) ...dom.cases(),
    if (includeDart) ...dartBenchmarks(),
  ].where((c) {
    if (only == null) return true;
    return c.name.contains(only) || c.category.contains(only);
  }).toList();

  try {
    if (list) {
      for (final c in cases) {
        stdout.writeln('${c.name} [${c.category}] ${c.operations} ${c.unit}');
      }
      return;
    }
    if (cases.isEmpty) {
      stderr.writeln('no benchmarks selected');
      exitCode = 2;
      return;
    }

    stdout.writeln('NativaX benchmark: ${cases.length} cases, '
        '$warmup warmup + $rounds rounds');
    final runner = BenchmarkRunner(
      rounds: rounds,
      warmup: warmup,
    );
    final results = runner.run(cases);
    for (final r in results) {
      stdout.writeln('  ${r.name.padRight(28)} '
          '${formatMs(r.medianMs).padLeft(12)}  '
          '${formatOps(r.opsPerSecond).padLeft(12)}  '
          'MAD ${r.relativeSpread.toStringAsFixed(1)} %');
    }

    final report = RunReport(
      metadata: collectMetadata(repoRoot: root),
      results: results,
      command: 'benchmark ${args.join(' ')}'.trim(),
      notes: const [
        'JS puro, DOM y Dart nativo están separados por categoría.',
        'Los benchmarks dart.* son una referencia del mismo proceso, no una '
            'comparación equivalente con QuickJS.',
        'dom.style_recompute mide DOM → estilos; no mide frames de GPU/UI.',
        'No se simulan resultados de V8/JavaScriptCore.',
      ],
    );
    final runDir = outDir == null
        ? createRunDirectory(root, 'microbench')
        : (Directory(outDir)..createSync(recursive: true));
    final files = writeReport(
      report,
      outputDir: runDir.path,
      jsonPath: jsonPath,
      markdownPath: markdownPath,
    );
    writeRunManifest(
      runDir,
      repoRoot: root,
      area: 'microbench',
      engine: 'nativa_benchmark',
      argv: ['run', ...args],
    );
    stdout
      ..writeln()
      ..writeln('JSON: ${files.json}')
      ..writeln('MD:   ${files.markdown}');
  } finally {
    js?.dispose();
    dom?.dispose();
  }
}

Future<void> _compare(List<String> args) async {
  String? baselinePath;
  String? currentPath;
  String? markdownPath;
  var threshold = 10.0;
  var noise = 2.0;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--baseline':
        baselinePath = args[++i];
      case '--current':
        currentPath = args[++i];
      case '--threshold':
        threshold = double.parse(args[++i]);
      case '--noise':
        noise = double.parse(args[++i]);
      case '--md':
        markdownPath = args[++i];
      case '-h' || '--help':
        _usage();
        return;
      default:
        stderr.writeln('unknown argument: ${args[i]}');
        exitCode = 64;
        return;
    }
  }
  if (baselinePath == null || currentPath == null) {
    stderr.writeln('compare requires --baseline and --current JSON files');
    exitCode = 64;
    return;
  }
  final baseline = loadReport(baselinePath);
  final current = loadReport(currentPath);
  final comparisons = compareRuns(
    baseline,
    current,
    thresholdPct: threshold,
    noiseMultiplier: noise,
  );
  final markdown = renderComparison(
    comparisons,
    baselinePath: baselinePath,
    currentPath: currentPath,
    thresholdPct: threshold,
    noiseMultiplier: noise,
  );
  stdout.write(markdown);
  if (markdownPath != null) {
    Directory(p.dirname(markdownPath)).createSync(recursive: true);
    File(markdownPath).writeAsStringSync(markdown);
  }
  final regressions =
      comparisons.where((c) => c.status == 'regression').length;
  if (regressions > 0) exitCode = 2;
}

void _usage() {
  stdout
    ..writeln('usage:')
    ..writeln('  dart run bin/benchmark.dart run [options]')
    ..writeln('    --rounds N       measured rounds (default 15, min 3)')
    ..writeln('    --warmup N       warmup rounds (default 3)')
    ..writeln('    --only TEXT      filter by name/category')
    ..writeln('    --no-js|--no-dom|--no-dart')
    ..writeln('    --out DIR        results directory')
    ..writeln('    --json FILE      explicit JSON path')
    ..writeln('    --md FILE        explicit Markdown path')
    ..writeln('    --list           list cases and exit')
    ..writeln('  dart run bin/benchmark.dart compare --baseline FILE --current FILE')
    ..writeln('    [--threshold PCT] [--noise MULT] [--md FILE]');
}
