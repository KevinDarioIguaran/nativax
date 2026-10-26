/// Runs the real pixel and region detectors on the committed dataset and
/// writes `audit.json` next to it.
///
///   dart run tool/audit_dataset.dart [dataset-dir]
library;

import 'dart:convert';
import 'dart:io';

import 'package:nativa_visual/src/audit/dataset.dart';
import 'package:nativa_visual/src/audit/evaluate.dart';
import 'package:nativa_visual/src/model.dart';
import 'package:nativa_visual/src/png.dart';

import 'paths.dart';

void main(List<String> args) {
  final dir = args.isEmpty ? defaultDatasetDir() : args.first;
  final manifest =
      jsonDecode(File('$dir/manifest.json').readAsStringSync()) as Map;
  final cases = <DatasetCase>[
    for (final c in (manifest['cases'] as List).cast<Map>())
      DatasetCase(
        id: c['id'] as String,
        kind: c['kind'] as String,
        description: c['description'] as String,
        expectation: c['expectation'] as String,
        reference: decodePng(
          File('$dir/${c['id']}/reference.png').readAsBytesSync(),
        ),
        actual: decodePng(File('$dir/${c['id']}/actual.png').readAsBytesSync()),
        truth: [
          for (final t in (c['truth'] as List).cast<List>())
            BoxRect.fromJson(t),
        ],
      ),
  ];
  final audit = auditDataset(cases);
  File(
    '$dir/audit.json',
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(audit)}\n');
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(audit));
}
