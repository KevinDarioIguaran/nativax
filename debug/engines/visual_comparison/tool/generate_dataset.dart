/// Writes the synthetic accuracy dataset to `debug/datasets/visual_comparison`.
///
///   dart run tool/generate_dataset.dart [output-dir]
///
/// Output is byte-for-byte deterministic; `test/dataset_test.dart` fails when
/// the committed files drift from the generator.
library;

import 'dart:convert';
import 'dart:io';

import 'package:nativa_visual/src/audit/dataset.dart';
import 'package:nativa_visual/src/png.dart';

import 'paths.dart';

void main(List<String> args) {
  final out = Directory(args.isEmpty ? defaultDatasetDir() : args.first)
    ..createSync(recursive: true);
  final cases = buildDataset();
  for (final c in cases) {
    final dir = Directory('${out.path}/${c.id}')..createSync(recursive: true);
    File('${dir.path}/reference.png').writeAsBytesSync(encodePng(c.reference));
    File('${dir.path}/actual.png').writeAsBytesSync(encodePng(c.actual));
  }
  File('${out.path}/manifest.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({
      'schema': 'nativa_visual.dataset/1',
      'generator': 'debug/engines/visual_comparison/tool/generate_dataset.dart',
      'boxFormat': '[x, y, w, h] in pixels',
      'cases': [for (final c in cases) c.toJson()],
    })}\n',
  );
  stdout.writeln('wrote ${cases.length} cases to ${out.path}');
}
