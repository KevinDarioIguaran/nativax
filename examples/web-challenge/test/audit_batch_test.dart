// Batch executor for the JSON interface audit (tools/audit). Skipped unless
// NATIVAX_AUDIT_MANIFEST points at a manifest written by `nxaudit`:
//
//   {
//     "out": "/abs/results.jsonl",
//     "probe_js": "globalThis.__nxProbe = function () { ... }",
//     "scenarios": [
//       {"id": "...", "html": "/abs/page.html", "width": 360, "height": 640,
//        "wait_ms": 300, "actions": [{"op": "click", "target": "btn_1"}]}
//     ]
//   }
//
// Every scenario mounts a fresh NativaXView in the same flutter_tester
// process, so thousands of screens share one process start. Each scenario
// writes a `begin` line before it runs and a `result` line after it; a
// scenario that hangs the process is identified by the last unmatched
// `begin` and the caller resumes from the next one.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativax/nativax.dart';

import 'support/fonts.dart';

const _keys = <String, LogicalKeyboardKey>{
  'Tab': LogicalKeyboardKey.tab,
  'Enter': LogicalKeyboardKey.enter,
  'Space': LogicalKeyboardKey.space,
  'Escape': LogicalKeyboardKey.escape,
  'ArrowDown': LogicalKeyboardKey.arrowDown,
  'ArrowUp': LogicalKeyboardKey.arrowUp,
  'ArrowLeft': LogicalKeyboardKey.arrowLeft,
  'ArrowRight': LogicalKeyboardKey.arrowRight,
  'Backspace': LogicalKeyboardKey.backspace,
};

class _Recorder {
  final flutterErrors = <Map<String, Object?>>[];
  final scriptErrors = <String>[];
  final diagnostics = <String>[];
  final console = <String>[];

  void clear() {
    flutterErrors.clear();
    scriptErrors.clear();
    diagnostics.clear();
    console.clear();
  }

  void onFlutterError(FlutterErrorDetails details) {
    final stack = (details.stack?.toString().split('\n') ?? const <String>[])
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    // The top frames name the throwing symbol (usually Flutter); the first
    // repository frames name the NativaX code that built the failing tree.
    final repo = stack
        .where((l) => l.contains('package:nativa') || l.contains('package:nativax'))
        .take(6);
    flutterErrors.add({
      'library': details.library,
      'summary': details.exceptionAsString().split('\n').first,
      'context': details.context?.toDescription(),
      'stack': [...stack.take(6), ...repo.where((l) => !stack.take(6).contains(l))],
    });
  }
}

void main() {
  final manifestPath = Platform.environment['NATIVAX_AUDIT_MANIFEST'];
  testWidgets('audit batch', skip: manifestPath == null, (tester) async {
    final manifest =
        jsonDecode(File(manifestPath!).readAsStringSync())
            as Map<String, dynamic>;
    final out = File(manifest['out'] as String);
    final probeJs = manifest['probe_js'] as String;
    final scenarios = (manifest['scenarios'] as List).cast<Map>();
    await tester.runAsync(loadHarnessFonts);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final recorder = _Recorder();
    final previousOnError = FlutterError.onError;
    FlutterError.onError = recorder.onFlutterError;

    void emit(Map<String, Object?> line) {
      out.writeAsStringSync(
        '${jsonEncode(line)}\n',
        mode: FileMode.append,
        flush: true,
      );
    }

    try {
      for (final raw in scenarios) {
        final scenario = raw.cast<String, dynamic>();
        final id = scenario['id'] as String;
        emit({'kind': 'begin', 'id': id});
        recorder.clear();
        final result = await _runScenario(tester, scenario, probeJs, recorder);
        // Exceptions the binding caught outside FlutterError.onError.
        final pending = tester.takeException();
        if (pending != null) {
          recorder.flutterErrors.add({
            'library': 'flutter_test',
            'summary': '$pending'.split('\n').first,
            'context': 'pending exception',
            'stack': const <String>[],
          });
        }
        emit({
          'kind': 'result',
          'id': id,
          ...result,
          'flutter_errors': List.of(recorder.flutterErrors),
          'script_errors': List.of(recorder.scriptErrors),
          'diagnostics': recorder.diagnostics.take(40).toList(),
          'console': recorder.console.take(40).toList(),
        });
      }
    } finally {
      FlutterError.onError = previousOnError;
    }
  });
}

Future<Map<String, Object?>> _runScenario(
  WidgetTester tester,
  Map<String, dynamic> scenario,
  String probeJs,
  _Recorder recorder,
) async {
  final watch = Stopwatch()..start();
  final timings = <String, int>{};
  final width = (scenario['width'] as num?)?.toDouble() ?? 360;
  final height = (scenario['height'] as num?)?.toDouble() ?? 640;
  final waitMs = (scenario['wait_ms'] as num?)?.toInt() ?? 300;
  final source = File(scenario['html'] as String).readAsStringSync();
  final actions = ((scenario['actions'] as List?) ?? const []).cast<Map>();
  final rssBefore = ProcessInfo.currentRss;
  tester.view.physicalSize = Size(width, height);

  NativaXRuntime? runtime;
  var generation = 0;

  Future<bool> mount() async {
    runtime = null;
    generation++;
    await tester.pumpWidget(
      MaterialApp(
        key: ValueKey('audit-$generation'),
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: NativaXView(
            source: source,
            padding: EdgeInsets.zero,
            config: NativaXRuntimeConfig(
              onScriptError: (e) => recorder.scriptErrors.add('$e'),
              onConsole: (m) => recorder.console.add(
                '${m.level.name}: ${m.text}',
              ),
              onDiagnostic: recorder.diagnostics.add,
            ),
            onRuntimeReady: (r) => runtime = r,
          ),
        ),
      ),
    );
    for (var i = 0; i < 40 && runtime == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    return runtime != null;
  }

  Future<void> settle([int? ms]) async {
    final total = ms ?? waitMs;
    for (var i = 0; i < (total ~/ 100).clamp(1, 100); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Map<String, Object?>? probe() {
    final r = runtime;
    if (r == null) return null;
    try {
      final text = r.engine.evaluate('__nxProbe()', filename: '<probe>');
      return (jsonDecode('$text') as Map).cast<String, Object?>();
    } catch (e) {
      recorder.scriptErrors.add('probe: $e');
      return null;
    }
  }

  Object? evaluate(String js) {
    final r = runtime;
    if (r == null) return null;
    try {
      return r.engine.evaluate(js, filename: '<action>');
    } catch (e) {
      recorder.scriptErrors.add('action: $e');
      return null;
    }
  }

  List<double>? rectOf(Map<String, Object?>? snapshot, String target) {
    final elements = (snapshot?['elements'] as List?) ?? const [];
    for (final e in elements.cast<Map>()) {
      if (e['id'] == target) {
        return (e['rect'] as List).map((v) => (v as num).toDouble()).toList();
      }
    }
    return null;
  }

  if (!await mount()) {
    return {
      'status': 'error',
      'stage': 'runtime_create',
      'error': 'NativaXRuntime was not ready after 40 pumps',
      'engine': null,
      'states': const [],
      'timings': {'total_ms': watch.elapsedMilliseconds},
    };
  }
  timings['mount_ms'] = watch.elapsedMilliseconds;
  final r = runtime!;
  try {
    r.engine.evaluate(probeJs, filename: '<nx-probe>');
  } catch (e) {
    recorder.scriptErrors.add('probe install: $e');
  }
  await settle();
  timings['settle_ms'] = watch.elapsedMilliseconds - timings['mount_ms']!;

  final states = <Map<String, Object?>>[];
  var current = probe();
  states.add({'after': 'initial', 'probe': current});
  final actionResults = <Map<String, Object?>>[];

  for (var index = 0; index < actions.length; index++) {
    final action = actions[index].cast<String, dynamic>();
    final op = action['op'] as String;
    final target = action['target'] as String?;
    var ok = true;
    String? note;
    switch (op) {
      case 'click':
        final rect = target == null ? null : rectOf(current, target);
        if (rect == null) {
          ok = false;
          note = 'target not measured';
        } else {
          await tester.tapAt(
            Offset(rect[0] + rect[2] / 2, rect[1] + rect[3] / 2),
          );
        }
      case 'type':
        final rect = target == null ? null : rectOf(current, target);
        if (rect == null) {
          ok = false;
          note = 'target not measured';
        } else {
          await tester.tapAt(
            Offset(rect[0] + rect[2] / 2, rect[1] + rect[3] / 2),
          );
          await tester.pump();
          if (tester.testTextInput.hasAnyClients) {
            tester.testTextInput.enterText(action['text'] as String? ?? '');
          } else {
            ok = false;
            note = 'no text input client after tapping the target';
          }
        }
      case 'key':
        final key = _keys[action['key']];
        if (key == null) {
          ok = false;
          note = 'unsupported key ${action['key']}';
        } else {
          await tester.sendKeyEvent(key);
        }
      case 'resize':
        tester.view.physicalSize = Size(
          (action['width'] as num).toDouble(),
          (action['height'] as num).toDouble(),
        );
      case 'rebuild':
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        if (!await mount()) {
          ok = false;
          note = 'runtime not ready after rebuild';
        } else {
          try {
            runtime!.engine.evaluate(probeJs, filename: '<nx-probe>');
          } catch (e) {
            recorder.scriptErrors.add('probe install: $e');
          }
        }
      case 'script':
        evaluate(action['js'] as String? ?? '');
      case 'wait':
        break;
      default:
        ok = false;
        note = 'unknown op $op';
    }
    await settle((action['wait_ms'] as num?)?.toInt());
    current = probe();
    states.add({'after': 'action:$index:$op', 'probe': current});
    actionResults.add({'index': index, 'op': op, 'ok': ok, 'note': ?note});
  }
  timings['actions_ms'] =
      watch.elapsedMilliseconds -
      timings['mount_ms']! -
      timings['settle_ms']!;
  final engine = runtime?.engineName;
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  timings['total_ms'] = watch.elapsedMilliseconds;
  return {
    'status': 'ok',
    'engine': engine,
    'states': states,
    'action_results': actionResults,
    'timings': timings,
    'rss_kb': {
      'before': rssBefore ~/ 1024,
      'after': ProcessInfo.currentRss ~/ 1024,
    },
  };
}
