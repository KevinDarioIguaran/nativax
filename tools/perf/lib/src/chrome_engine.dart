import 'dart:convert';
import 'dart:io';

import 'cdp.dart';
import 'model.dart';
import 'proc_sampler.dart';
import 'scenarios.dart';

Future<EngineRun> runChromeScenario({
  required PerfScenario scenario,
  required String pageDirectory,
  required String artifacts,
  required int width,
  required int height,
  required String executable,
  double cpuRate = 1,
  int? cpuCores,
  int? cpuQuotaPct,
  int? memoryLimitMb,
}) async {
  Directory(artifacts).createSync(recursive: true);
  CdpChrome? chrome;
  ProcTreeSampler? sampler;
  try {
    chrome = await CdpChrome.launch(
    executable: executable,
    width: width,
    height: height,
  );
  await chrome.setCpuThrottlingRate(cpuRate);
    sampler = ProcTreeSampler(chrome.pid);
    await sampler.start();
    await chrome.setViewport(width, height);
    await chrome.navigate(Uri.file('$pageDirectory/index.html').toString());
    final loadMs =
        (await chrome.evaluate('performance.now()') as num?)?.toDouble() ?? 0;

    if (scenario.setupJs.trim().isNotEmpty) {
      await chrome.evaluate(scenario.setupJs, awaitPromise: false);
    }
    if (scenario.setupWaitJs != null && scenario.setupWaitJs!.isNotEmpty) {
      await _poll(chrome, scenario.setupWaitJs!, scenario.timeoutMs);
    }

    final nodesBefore =
        (await chrome.evaluate("document.getElementsByTagName('*').length")
                    as num? ??
                0)
            .toInt();
    final before = await chrome.metrics();

    final opResults = <Map<String, Object?>>[];
    final frameTimes = <double>[];
    var scenarioMs = 0.0;
    for (final op in scenario.ops) {
      final expression =
          '(()=>{const t=performance.now(); ${op.js}; return performance.now()-t;})()';
      final value = await chrome.evaluate(expression, awaitPromise: false);
      final ms = (value as num?)?.toDouble() ?? 0;
      scenarioMs += ms;
      frameTimes.add(ms);
      opResults.add({'name': op.name, 'ms': ms, 'scroll': op.scroll});
    }

    Map<String, Object?>? startWait;
    Object? read;
    if (scenario.startJs != null && scenario.startJs!.isNotEmpty) {
      final stopwatch = Stopwatch()..start();
      await chrome.evaluate(scenario.startJs!, awaitPromise: false);
      var done = scenario.waitJs == null || scenario.waitJs!.isEmpty;
      var polls = 0;
      var lastError = '';
      while (!done && stopwatch.elapsedMilliseconds < scenario.timeoutMs) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        polls++;
        try {
          done =
              await chrome.evaluate(scenario.waitJs!, awaitPromise: false) ==
              true;
        } catch (error) {
          lastError = '$error';
        }
      }
      scenarioMs = stopwatch.elapsedMicroseconds / 1000;
      startWait = {
        'start_ms': scenarioMs,
        'polls': polls,
        'done': done,
        if (lastError.isNotEmpty) 'last_error': lastError,
      };
      if (!done) {
        throw StateError('timed out waiting for the page benchmark to finish');
      }
      if (scenario.readJs != null && scenario.readJs!.isNotEmpty) {
        try {
          final value = await chrome.evaluate(
            scenario.readJs!,
            awaitPromise: false,
          );
          read = value is String && value.isNotEmpty
              ? jsonDecode(value)
              : value;
        } catch (error) {
          read = {'error': '$error'};
        }
      }
    }

    if (scenario.idleMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: scenario.idleMs));
    }

    final after = await chrome.metrics();
    final nodes =
        (await chrome.evaluate("document.getElementsByTagName('*').length")
                    as num? ??
                0)
            .toInt();
    final scrollY = (await chrome.evaluate('window.scrollY') as num? ?? 0)
        .toInt();
    final documentHeight =
        (await chrome.evaluate('document.documentElement.scrollHeight')
                    as num? ??
                0)
            .toInt();
    final title = await chrome.evaluate('document.title') ?? '';

    final layoutMs = _delta(before, after, 'LayoutDuration') * 1000;
    final styleMs = _delta(before, after, 'RecalcStyleDuration') * 1000;
    final scriptMs = _delta(before, after, 'ScriptDuration') * 1000;
    final heapMb = (after['JSHeapUsedSize'] ?? 0) / (1024 * 1024);
    if (scenario.ops.isEmpty && scenario.startJs == null) {
      // No workload: nothing was measured inside the page.
      scenarioMs = 0;
    }
    if (scenario.startJs != null) {
      // Layout/style work during an async scenario happened while polling.
    }
    await sampler.stop();
    final samples = [...sampler.samples];
    return EngineRun(
      engine: EngineKind.chromium,
      status: RunStatus.ok,
      loadMs: loadMs,
      scenarioMs: scenarioMs,
      renderMs: layoutMs + styleMs,
      frameTimes: frameTimes,
      nodes: nodes,
      nodesBefore: nodesBefore,
      scrollY: scrollY,
      documentHeight: documentHeight,
      heapMb: heapMb,
      layoutCount: _delta(before, after, 'LayoutCount').round(),
      styleCount: _delta(before, after, 'RecalcStyleCount').round(),
      layoutMs: layoutMs,
      styleMs: styleMs,
      scriptMs: scriptMs,
      samples: samples,
      extra: {
        'title': title,
        'ops': opResults,
        'start_wait': startWait,
        'read': read,
        'gpu_busy_pct': readGpuBusyPercent(),
        'task_ms': _delta(before, after, 'TaskDuration') * 1000,
        'script_ms': scriptMs,
        'heap_mb': heapMb,
        'harness': 'Chromium DevTools Protocol',
      },
    );
  } catch (error) {
    try {
      await sampler?.stop();
    } catch (_) {}
    return EngineRun(
      engine: EngineKind.chromium,
      status: RunStatus.failed,
      error: '$error',
      samples: sampler?.samples ?? const [],
      extra: {'gpu_busy_pct': readGpuBusyPercent()},
    );
  } finally {
    try {
      await chrome?.close();
    } catch (_) {}
  }
}

Future<bool> _poll(CdpChrome chrome, String condition, int timeoutMs) async {
  final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
  while (DateTime.now().isBefore(deadline)) {
    try {
      if (await chrome.evaluate(condition, awaitPromise: false) == true)
        return true;
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return false;
}

double _delta(
  Map<String, double> before,
  Map<String, double> after,
  String key,
) => (after[key] ?? 0) - (before[key] ?? 0);



