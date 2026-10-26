import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../lib/conformance.dart';

/// Runs every conformance runner on the committed validation subset in
/// `debug/datasets/compatibility` and compares each verdict with the
/// hand-verified expectation. It also checks that deliberately broken
/// adapters are caught. Exit 0 only if the real runners are 100 % correct and
/// every broken adapter is detected.
Future<void> main(List<String> args) async {
  final root = findRepoRoot();
  var dataset = ValidationDataset.inRepo(root);
  String? jsonPath;
  String? markdownPath;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--dataset':
        dataset = args[++i];
      case '--json':
        jsonPath = args[++i];
      case '--markdown':
        markdownPath = args[++i];
      case '-h' || '--help':
        stdout.writeln('usage: dart run bin/validate_runners.dart '
            '[--dataset DIR] [--json out.json] [--markdown out.md]');
        return;
      default:
        stderr.writeln('unknown argument: ${args[i]}');
        exitCode = 64;
        return;
    }
  }
  final data = ValidationDataset(dataset);
  final expected = loadExpectedOutcomes(data.expectedPath);
  final runs = await runValidationSubset(data);
  final report = validateRuns(runs, expected);

  final broken = <String, ValidationReport>{};
  for (final adapter in brokenAdapters) {
    broken[adapter.name] =
        validateRuns([for (final r in runs) adapter.apply(r)], expected);
  }
  final temp = Directory.systemTemp.createTempSync('nx_validation_');
  try {
    final suite = writeBrokenTest262(data, p.join(temp.path, 'test262'));
    broken['noop-test262-assert'] = validateRuns(
        await runValidationSubset(data, test262Suite: suite), expected);
  } finally {
    temp.deleteSync(recursive: true);
  }
  broken['always-pass-wpt-harness'] = validateRuns(
      await runValidationSubset(data, wptHarness: alwaysPassWptHarness),
      expected);

  final md = StringBuffer()
    ..write(report.renderMarkdown(title: 'Runner validation (real runners)'))
    ..writeln()
    ..writeln('## Broken adapters')
    ..writeln()
    ..writeln('| Adapter | Accuracy | Mismatches | Caught |')
    ..writeln('|---|---:|---:|---|');
  var allCaught = true;
  for (final e in broken.entries) {
    final caught = report.detects(e.value);
    allCaught &= caught;
    md.writeln('| ${e.key} | ${e.value.accuracy.toStringAsFixed(1)} % | '
        '${e.value.mismatches.length} | ${caught ? 'yes' : '**no**'} |');
  }
  stdout.write(md);
  if (markdownPath != null) File(markdownPath).writeAsStringSync(md.toString());
  if (jsonPath != null) {
    File(jsonPath).writeAsStringSync(const JsonEncoder.withIndent('  ')
        .convert({
      'runners': report.toJson(),
      'brokenAdapters': {
        for (final e in broken.entries)
          e.key: {
            'accuracy': e.value.accuracy,
            'mismatches': e.value.mismatches.length,
            'caught': report.detects(e.value),
          },
      },
    }));
  }
  if (!report.perfect || !allCaught) exitCode = 1;
}
