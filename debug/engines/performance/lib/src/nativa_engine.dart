import 'dart:convert';
import 'dart:io';

import 'model.dart';
import 'proc_sampled.dart';
import 'proc_sampler.dart';
import 'scenarios.dart';

const String _freezeCss = '''
*, *::before, *::after {
  animation: none !important;
  transition: none !important;
  scroll-behavior: auto !important;
  caret-color: transparent !important;
}
''';

/// Copies a scenario page into a private directory and injects the shared
/// determinism stylesheet.
Directory stageScenarioPage(String sourceDirectory, Directory target) {
  if (target.existsSync()) target.deleteSync(recursive: true);
  target.createSync(recursive: true);
  _copy(Directory(sourceDirectory), target);
  final index = File('${target.path}/index.html');
  if (!index.existsSync())
    throw StateError('no index.html in $sourceDirectory');
  final text = index.readAsStringSync();
  final close = text.toLowerCase().lastIndexOf('</head>');
  final injected = '<style id="__perf_freeze">$_freezeCss</style>';
  index.writeAsStringSync(
    close < 0
        ? '$injected$text'
        : '${text.substring(0, close)}$injected${text.substring(close)}',
  );
  return target;
}

void _copy(Directory source, Directory target) {
  for (final entity in source.listSync(followLinks: false)) {
    final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (name == '.git' || name == 'node_modules' || name == '.nativa-perf')
      continue;
    if (entity is File) {
      entity.copySync('${target.path}/$name');
    } else if (entity is Directory) {
      final child = Directory('${target.path}/$name')..createSync();
      _copy(entity, child);
    }
  }
}

/// Runs a scenario in NativaX through the offscreen `flutter test` harness.
Future<EngineRun> runNativaScenario({
  required PerfScenario scenario,
  required String repoRoot,
  required String pageDirectory,
  required String artifacts,
  required int width,
  required int height,
  double cpuRate = 1,
  int? cpuCores,
  int? cpuQuotaPct,
  int? memoryLimitMb,
}) async {
  final dir = Directory(artifacts)..createSync(recursive: true);
  final outFile = File('${dir.path}/nativax.json');
  if (outFile.existsSync()) outFile.deleteSync();
  final ops = [
    for (final op in scenario.ops)
      {'name': op.name, 'js': op.js, 'scroll': op.scroll},
  ];
  final result = await runWithSampling(
    'flutter',
    ['test', 'test/perf_probe_test.dart', '--reporter=compact', '--no-pub'],
    workingDirectory: '$repoRoot/debug/harness',
    timeout: Duration(milliseconds: scenario.timeoutMs + 90000),
    environment: {
      'NATIVAX_PERF_OUT': outFile.path,
      'NATIVAX_PERF_PAGE': pageDirectory,
      'NATIVAX_PERF_WIDTH': '$width',
      'NATIVAX_PERF_HEIGHT': '$height',
      'NATIVAX_PERF_SETUP': scenario.setupJs,
      'NATIVAX_PERF_SETUP_WAIT': scenario.setupWaitJs ?? '',
      'NATIVAX_PERF_OPS': jsonEncode(ops),
      'NATIVAX_PERF_START': scenario.startJs ?? '',
      'NATIVAX_PERF_WAIT': scenario.waitJs ?? '',
      'NATIVAX_PERF_READ': scenario.readJs ?? '',
      'NATIVAX_PERF_IDLE_MS': '${scenario.idleMs}',
      'NATIVAX_PERF_TIMEOUT_MS': '${scenario.timeoutMs}',
    },
    samplerFactory: (pid) => ProcTreeSampler(pid),
  );
  final samples = result.samples;
  Map<String, dynamic>? data;
  try {
    final matches = RegExp(
      r'^PERF: (.+)$',
      multiLine: true,
    ).allMatches(result.stdout).toList();
    if (matches.isNotEmpty) {
      data = jsonDecode(matches.last.group(1)!) as Map<String, dynamic>;
    } else if (outFile.existsSync()) {
      data = jsonDecode(outFile.readAsStringSync()) as Map<String, dynamic>;
    }
  } catch (_) {}
  if (data == null) {
    return EngineRun(
      engine: EngineKind.nativa,
      status: RunStatus.failed,
      error:
          'NativaX probe failed (exit ${result.exitCode}): '
          'stdout: ${_tail(result.stdout)} stderr: ${_tail(result.stderr)}',
      samples: samples,
      extra: {'gpu_busy_pct': readGpuBusyPercent()},
    );
  }
  final frameTimes = (data['frame_times'] as List? ?? const [])
      .map((v) => (v as num).toDouble())
      .toList(growable: false);
  var status = data['status'] == 'ok' ? RunStatus.ok : RunStatus.failed;
  String? error = status == RunStatus.ok ? null : data['error']?.toString();
  final startWait = data['start_wait'];
  if (startWait is Map && startWait['done'] == false) {
    status = RunStatus.failed;
    error = 'timed out waiting for the page benchmark to finish';
  }
  return EngineRun(
    engine: EngineKind.nativa,
    status: status,
    error: error,
    loadMs: (data['load_ms'] as num?)?.toDouble() ?? 0,
    scenarioMs: (data['scenario_ms'] as num?)?.toDouble() ?? 0,
    evalMs: (data['eval_ms'] as num?)?.toDouble() ?? 0,
    renderMs: (data['render_ms'] as num?)?.toDouble() ?? 0,
    frameTimes: frameTimes,
    nodes: (data['nodes'] as num?)?.toInt() ?? 0,
    nodesBefore: (data['nodes_before'] as num?)?.toInt() ?? 0,
    scrollY: (data['scroll_y'] as num?)?.toInt() ?? 0,
    documentHeight: (data['document_height'] as num?)?.toInt() ?? 0,
    samples: samples,
    extra: {
      'title': data['title'],
      'ops': data['ops'],
      'start_wait': data['start_wait'],
      'read': data['read'],
      'errors': data['errors'],
      'gpu_busy_pct': readGpuBusyPercent(),
      'harness': 'flutter test + RenderRepaintBoundary',
      'exit_code': result.exitCode,
      'timed_out': result.timedOut,
    },
  );
}

String _tail(String value, {int lines = 8}) {
  final text = value.trim();
  if (text.isEmpty) return '';
  final parts = text.split('\n');
  return parts.length <= lines
      ? text
      : parts.sublist(parts.length - lines).join('\n');
}


