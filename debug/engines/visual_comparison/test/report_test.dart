import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nativa_visual/src/model.dart';
import 'package:nativa_visual/src/png.dart';
import 'package:nativa_visual/src/report.dart';
import 'package:nativa_visual/src/score.dart';
import 'package:test/test.dart';

RasterImage solid(int width, int height, int r, int g, int b) {
  final rgba = Uint8List(width * height * 4);
  for (var i = 0; i < width * height; i++) {
    rgba[i * 4] = r;
    rgba[i * 4 + 1] = g;
    rgba[i * 4 + 2] = b;
    rgba[i * 4 + 3] = 255;
  }
  return RasterImage(width, height, rgba);
}

ElementSnapshot element() => ElementSnapshot(
  path: 'html:1>body:1>div:1',
  tag: 'div',
  rect: const BoxRect(0, 0, 20, 20),
  styles: const {
    'display': 'block',
    'color': 'rgb(0, 0, 0)',
    'background-color': 'rgb(255, 255, 255)',
    'font-size': '16px',
    'font-weight': '400',
    'font-family': 'sans-serif',
    'line-height': 'normal',
    'border-top-style': 'none',
    'border-top-width': '0px',
    'opacity': '1',
    'position': 'static',
    'visibility': 'visible',
    'overflow-x': 'visible',
    'overflow-y': 'visible',
  },
);

ProbeSnapshot probe() => ProbeSnapshot(
  viewportWidth: 20,
  viewportHeight: 20,
  dpr: 1,
  documentWidth: 20,
  documentHeight: 20,
  elements: [element()],
);

void main() {
  test('page report serialises scores, elements, pixels and CSS', () {
    final evaluation = evaluate(
      chromeProbe: probe(),
      chromeImage: solid(20, 20, 255, 255, 255),
      nativaProbe: probe(),
      nativaImage: solid(20, 20, 240, 240, 240),
      checks: const [
        EnvCheck(name: 'chromium', ok: true, hard: true, detail: 'ok'),
      ],
    );
    final report = PageReport(
      page: const PageSource(
        id: 'suite/page',
        suite: 'suite',
        entry: '/tmp/index.html',
        directory: '/tmp',
      ),
      viewportWidth: 20,
      viewportHeight: 20,
      scheme: 'light',
      artifactsDir: '/tmp/none',
      checks: const [
        EnvCheck(name: 'chromium', ok: true, hard: true, detail: 'ok'),
      ],
      chromeProbe: probe(),
      nativaProbe: probe(),
      evaluation: evaluation,
    );
    final json = report.toJson();
    expect(json['page'], 'suite/page');
    expect((json['scores'] as Map)['overall'], lessThan(100));
    expect(json['elements'], hasLength(1));
    expect((json['pixels'] as Map)['pixels'], 400);
    expect(json['environment'], hasLength(1));
  });

  test('artifacts include diff, pixel JSON, positions and colours', () {
    final directory = Directory.systemTemp.createTempSync(
      'nativa-visual-report-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final evaluation = evaluate(
      chromeProbe: probe(),
      chromeImage: solid(20, 20, 255, 255, 255),
      nativaProbe: probe(),
      nativaImage: solid(20, 20, 255, 0, 0),
      checks: const [],
    );
    final report = PageReport(
      page: const PageSource(
        id: 'suite/page',
        suite: 'suite',
        entry: '/tmp/index.html',
        directory: '/tmp',
      ),
      viewportWidth: 20,
      viewportHeight: 20,
      scheme: 'light',
      artifactsDir: directory.path,
      checks: const [],
      chromeProbe: probe(),
      nativaProbe: probe(),
      evaluation: evaluation,
    );
    report.writeArtifacts(
      chromeImage: solid(20, 20, 255, 255, 255),
      nativaImage: solid(20, 20, 255, 0, 0),
      writePixelCsv: true,
    );
    for (final name in [
      'report.json',
      'diff.png',
      'pixels.json',
      'elements.csv',
      'positions.csv',
      'colors.csv',
      'pixels.csv',
      'elements.json',
    ]) {
      expect(
        File('${directory.path}/$name').existsSync(),
        isTrue,
        reason: name,
      );
    }
    final elementTable =
        jsonDecode(File('${directory.path}/elements.json').readAsStringSync())
            as Map;
    expect(elementTable['columns'], contains('position_delta'));
    expect(elementTable['rows'], hasLength(1));
    final diff = decodePng(
      File('${directory.path}/diff.png').readAsBytesSync(),
    );
    expect(diff.width, 20);
    final elements = File('${directory.path}/elements.csv').readAsStringSync();
    expect(elements.split('\n').first, startsWith('path,tag,chrome_x'));
    expect(elements, contains('html:1>body:1>div:1'));
    final positions = File(
      '${directory.path}/positions.csv',
    ).readAsStringSync();
    expect(positions.split('\n').first, contains('dx,dy,dw,dh'));
    final colors = File('${directory.path}/colors.csv').readAsStringSync();
    expect(colors.split('\n').first, contains('sampled_chrome'));
    final pixels =
        jsonDecode(File('${directory.path}/pixels.json').readAsStringSync())
            as Map;
    expect(pixels['totals']['pixels'], 400);
    final csv = File('${directory.path}/pixels.csv').readAsStringSync();
    expect(csv.split('\n').length, greaterThan(1));
  });

  test('artifacts add overlay.png, regions.json and environment.json', () {
    final directory = Directory.systemTemp.createTempSync(
      'nativa-visual-evidence-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final reference = solid(20, 20, 255, 255, 255);
    final actual = solid(20, 20, 255, 255, 255);
    for (var y = 4; y < 8; y++) {
      for (var x = 4; x < 10; x++) {
        actual.rgba[(y * 20 + x) * 4 + 1] = 0;
      }
    }
    final report = PageReport(
      page: const PageSource(
        id: 'suite/page',
        suite: 'suite',
        entry: '/tmp/index.html',
        directory: '/tmp',
      ),
      viewportWidth: 20,
      viewportHeight: 20,
      scheme: 'light',
      artifactsDir: directory.path,
      checks: const [],
      chromeProbe: probe(),
      nativaProbe: probe(),
      evaluation: evaluate(
        chromeProbe: probe(),
        chromeImage: reference,
        nativaProbe: probe(),
        nativaImage: actual,
        checks: const [],
      ),
      environment: const {'schema': 'nativa_visual.environment/1'},
    );
    report.writeArtifacts(chromeImage: reference, nativaImage: actual);
    final overlay = decodePng(
      File('${directory.path}/overlay.png').readAsBytesSync(),
    );
    expect([overlay.width, overlay.height], [20, 20]);
    final regions =
        jsonDecode(File('${directory.path}/regions.json').readAsStringSync())
            as Map;
    expect(regions['page'], 'suite/page');
    expect(regions['connectivity'], 8);
    expect(regions['minArea'], 4);
    final region = (regions['regions'] as List).single as Map;
    expect(region['bbox'], [4, 4, 6, 4]);
    expect(region['pixels'], 24);
    expect((region['elements'] as List).single['path'], 'html:1>body:1>div:1');
    final environment =
        jsonDecode(
              File('${directory.path}/environment.json').readAsStringSync(),
            )
            as Map;
    expect(environment['schema'], 'nativa_visual.environment/1');
  });

  test('run report writes Markdown, JSON and summary CSV', () {
    final directory = Directory.systemTemp.createTempSync('nativa-visual-run-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final evaluation = evaluate(
      chromeProbe: probe(),
      chromeImage: solid(20, 20, 255, 255, 255),
      nativaProbe: probe(),
      nativaImage: solid(20, 20, 255, 255, 255),
      checks: const [],
    );
    final page = PageReport(
      page: const PageSource(
        id: 'suite/page',
        suite: 'suite',
        entry: '/tmp/index.html',
        directory: '/tmp',
      ),
      viewportWidth: 20,
      viewportHeight: 20,
      scheme: 'light',
      artifactsDir: '/tmp/none',
      checks: const [],
      chromeProbe: probe(),
      nativaProbe: probe(),
      evaluation: evaluation,
    );
    final run = RunReport(
      startedAt: DateTime.utc(2026, 10, 24),
      duration: const Duration(seconds: 2),
      chromeVersion: 'Chromium test',
      viewportWidth: 800,
      viewportHeight: 900,
      scheme: 'light',
      frozenAnimations: true,
      outputDir: directory.path,
      pages: [page],
      command: 'visual_check test',
    );
    run.write(directory.path);
    final markdown = File('${directory.path}/report.md').readAsStringSync();
    expect(markdown, contains('NativaX visual fidelity'));
    expect(markdown, contains('`suite/page`'));
    expect(markdown, contains('PASS'));
    expect(markdown, contains('Pixel report'));
    final json =
        jsonDecode(File('${directory.path}/report.json').readAsStringSync())
            as Map;
    expect(json['summary']['pages'], 1);
    expect(json['pages'], hasLength(1));
    final csv = File('${directory.path}/summary.csv').readAsStringSync();
    expect(csv.split('\n').first, startsWith('page,suite,verdict'));
    expect(csv, contains('suite/page,suite,PASS'));

    final results =
        jsonDecode(File('${directory.path}/results.json').readAsStringSync())
            as Map;
    expect(results['columns'], contains('position'));
    expect(results['columns'], contains('mean_delta_e'));
    expect(results['columns'], contains('ink_mismatch_pct'));
    expect(results['columns'], contains('diff_png'));
    // Existing columns keep their order; evidence columns are appended.
    final columns = (results['columns'] as List).cast<String>();
    expect(columns.indexOf('failure'), 29);
    expect(columns.sublist(30), [
      'overlay_png',
      'regions_json',
      'environment_json',
    ]);
    expect(results['rows'], hasLength(1));
    final row = (results['rows'] as List).single as Map;
    expect(row['page'], 'suite/page');
    expect(row['verdict'], 'PASS');
    expect(row['position'], 100);
    expect(row['pixels'], 400);
    expect(row['regions_json'], '/tmp/none/regions.json');
  });
}
