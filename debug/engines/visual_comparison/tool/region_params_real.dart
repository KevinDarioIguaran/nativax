/// Recomputes `regions.json` for every page of a judge run with the previous
/// region settings (no grouping, no strong-deltaE exception) and with the
/// current defaults, and prints the totals used in `metrics-visual.md`.
///
///   dart run tool/region_params_real.dart <judge-run-dir>
library;

import 'dart:io';

import 'package:nativa_visual/src/png.dart';
import 'package:nativa_visual/src/regions.dart';

void main(List<String> args) {
  final dirs =
      Directory(args.first)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('/nativax.png'))
          .map((f) => f.parent.path)
          .toList()
        ..sort();
  var pages = 0, before = 0, after = 0, droppedBefore = 0, droppedAfter = 0;
  var strongKept = 0, sizeRegions = 0, bigBefore = 0, bigAfter = 0;
  for (final d in dirs) {
    final chrome = File('$d/chrome.png');
    if (!chrome.existsSync()) continue;
    final map = deltaMap(
      decodePng(chrome.readAsBytesSync()),
      decodePng(File('$d/nativax.png').readAsBytesSync()),
    );
    final old = findRegions(map, mergeGap: -1, strongDeltaE: double.infinity);
    final now = findRegions(map);
    final noStrong = findRegions(map, strongDeltaE: double.infinity);
    final half = 0.5 * map.width * map.height;
    bool big(DiffRegion r) => r.bbox.width * r.bbox.height > half;
    pages++;
    before += old.regions.length;
    after += now.regions.length;
    droppedBefore += old.droppedPixels;
    droppedAfter += now.droppedPixels;
    strongKept += now.regions.length - noStrong.regions.length;
    sizeRegions += now.regions.where((r) => r.kind == 'size').length;
    bigBefore += old.regions.where(big).length;
    bigAfter += now.regions.where(big).length;
  }
  stdout.writeln(
    'pages=$pages regions $before -> $after, dropped px $droppedBefore -> '
    '$droppedAfter, strong 1-3 px regions kept $strongKept, size regions '
    '$sizeRegions, bbox over half the page $bigBefore -> $bigAfter',
  );
}
