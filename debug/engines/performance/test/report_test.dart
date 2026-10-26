import 'dart:convert';
import 'dart:io';

import 'package:nativa_perf/src/externals.dart';
import 'package:nativa_perf/src/model.dart';
import 'package:nativa_perf/src/report.dart';
import 'package:nativa_perf/src/scenarios.dart';
import 'package:test/test.dart';

EngineRun run(EngineKind engine, ScenarioResult? _) => EngineRun(
  engine: engine,
  status: RunStatus.ok,
  scenarioMs: engine == EngineKind.chromium ? 10 : 20,
  renderMs: 5,
  nodes: 100,
  frameTimes: const [5, 6],
  samples: [
    ProcSample(elapsedMs: 0, rssMb: 120, cpuPct: 1, processes: 1),
    ProcSample(elapsedMs: 250, rssMb: 130, cpuPct: 2, processes: 1),
  ],
  extra: const {
    'read': {'score': 42},
  },
);

void main() {
  test('report writes JSON, CSV, Markdown, timeline and SVG charts', () {
    final directory = Directory.systemTemp.createTempSync(
      'nativa-perf-report-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    const scenario = PerfScenario(
      id: 'unit.scenario',
      title: 'Unit scenario',
      kind: ScenarioKind.dom,
      source: 'unit',
      description: 'unit',
    );
    final result = ScenarioResult(
      scenarioId: scenario.id,
      title: scenario.title,
      kind: scenario.kind.name,
      source: scenario.source,
      chromium: run(EngineKind.chromium, null),
      nativa: run(EngineKind.nativa, null),
      verdict: Verdict.pass,
      reasons: const [],
    );
    final perfRun = PerfRun(
      startedAt: DateTime.utc(2026, 10, 24),
      duration: const Duration(seconds: 3),
      command: 'perf test',
      chromeVersion: 'Chromium test',
      viewportWidth: 800,
      viewportHeight: 900,
      outDir: directory.path,
      targets: const PerfTargets(),
      results: [result],
      idle: null,
      notes: const ['note'],
    );
    writePerfReports(perfRun, directory.path);
    for (final name in [
      'results.json',
      'results.csv',
      'report.md',
      'timeline.csv',
      'charts/work-ratio.svg',
      'charts/frame-p95.svg',
      'charts/rss.svg',
    ]) {
      expect(
        File('${directory.path}/$name').existsSync(),
        isTrue,
        reason: name,
      );
    }
    final markdown = File('${directory.path}/report.md').readAsStringSync();
    expect(markdown, contains('NativaX performance suite'));
    expect(markdown, contains('unit.scenario'));
    expect(markdown, contains('PASS'));
    final csv = File('${directory.path}/results.csv').readAsStringSync();
    expect(csv.split('\n').first, startsWith('scenario,kind,verdict'));
    expect(csv, contains('unit.scenario'));
    final svg = File(
      '${directory.path}/charts/work-ratio.svg',
    ).readAsStringSync();
    expect(svg, contains('<svg'));
    expect(svg, contains('unit.scenario'));
  });

  test('external registry resolves vendored fixtures', () {
    final root = Directory.current.parent.parent.path;
    final browser = externalSuiteById('browserbench');
    final cerious = externalSuiteById('cerious');
    final jsfb = externalSuiteById('jsfb');
    expect(browser, isNotNull);
    expect(cerious!.license, 'MIT');
    expect(jsfb!.license, 'Apache-2.0');
    expect(resolveExternalPage(root, browser!), isNotNull);
    expect(resolveExternalPage(root, cerious), isNotNull);
    expect(resolveExternalPage(root, jsfb), isNotNull);
    expect(externalSuiteById('millionrows')!.fetchHint, contains('npm'));
  });

  test('scenario catalog exposes exactly 245 unique scenarios', () {
    final file = File('${Directory.current.path}/scenarios.json');
    expect(file.existsSync(), isTrue);
    final rows = jsonDecode(file.readAsStringSync()) as List;
    expect(rows, hasLength(245));
    expect(rows.map((row) => row['id']).toSet(), hasLength(245));
    expect(builtInScenarios, hasLength(239));
    expect(rows.first['id'], 'idle.blank');
    expect(
      rows.map((row) => row['id']),
      containsAll([
        'js.typed-arrays',
        'layout.flex-create-100',
        'form.validation-1k',
        'animation.canvas-1k',
        'game.quality-640x360-p100',
      ]),
    );
  });

  test('every built-in scenario builds non-empty HTML', () {
    for (final scenario in builtInScenarios) {
      if (scenario.pageBuilder == null) continue;
      final html = scenario.pageBuilder!();
      expect(html, isNotEmpty, reason: scenario.id);
      expect(html, contains('<html'), reason: scenario.id);
    }
  });

  test('built-in scenarios cover DOM, scroll, JS and idle', () {
    final ids = builtInScenarios.map((s) => s.id).toList();
    expect(ids, contains('dom.rows-create-10k'));
    expect(ids, contains('scroll.rows-10k'));
    expect(ids, contains('scroll.2d-tiles'));
    expect(ids, contains('js.arrays'));
    expect(ids, contains('idle.blank'));
    expect(
      builtInScenarios
          .firstWhere((s) => s.id == 'scroll.2d-tiles')
          .notes
          .join(' '),
      contains('PassMark'),
    );
  });
}
