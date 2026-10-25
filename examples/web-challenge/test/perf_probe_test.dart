// Offscreen performance probe. Skipped unless NATIVAX_PERF_OUT is set.
//
// It loads a page, runs a setup script, then executes a list of operations and
// times both the JS call and the following `tester.pump()` (style + layout +
// paint work for one frame). It never opens a window.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativax/nativax.dart';

class _Loader extends NativaXResourceLoader {
  const _Loader(this.dir);
  final String? dir;

  @override
  Future<String?> load(String url) async {
    if (url.startsWith('http://') || url.startsWith('https://')) return null;
    var path = url.split('?').first.split('#').first;
    if (path.startsWith('/')) path = path.substring(1);
    if (dir != null) {
      final file = File('$dir/$path');
      return file.existsSync() ? file.readAsStringSync() : null;
    }
    if (!path.startsWith('assets/')) path = 'assets/$path';
    try {
      return await rootBundle.loadString(path);
    } catch (_) {
      return null;
    }
  }
}

Future<void> _loadFonts() async {
  const dir = '/usr/share/fonts/truetype/noto';
  final regular = File('$dir/NotoSans-Regular.ttf');
  if (!regular.existsSync()) return;
  final bold = File('$dir/NotoSans-Bold.ttf');
  final dejavu = File('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf');
  final mono = dejavu.existsSync()
      ? dejavu
      : File('$dir/NotoSansMono-Regular.ttf');
  final emoji = File('$dir/NotoColorEmoji.ttf');
  ByteData bytes(File f) => ByteData.view(f.readAsBytesSync().buffer);
  for (final family in [
    'Noto Sans',
    'Roboto',
    'ui-rounded',
    'Segoe UI',
    'sans-serif',
    'system-ui',
    'Arial',
  ]) {
    final loader = FontLoader(family)..addFont(Future.value(bytes(regular)));
    if (bold.existsSync()) loader.addFont(Future.value(bytes(bold)));
    await loader.load();
  }
  final fallback = <String>[];
  final symbols = File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
  if (symbols.existsSync()) {
    await (FontLoader(
      'DejaVu Sans',
    )..addFont(Future.value(bytes(symbols)))).load();
    fallback.add('DejaVu Sans');
  }
  if (emoji.existsSync()) {
    await (FontLoader(
      'Noto Color Emoji',
    )..addFont(Future.value(bytes(emoji)))).load();
    fallback.add('Noto Color Emoji');
  }
  nativaxFontFallback = fallback;
  nativaxDefaultFontFamily = 'Noto Sans';
  if (mono.existsSync()) {
    for (final family in [
      'monospace',
      'ui-monospace',
      'Menlo',
      'Consolas',
      'Roboto Mono',
    ]) {
      await (FontLoader(family)..addFont(Future.value(bytes(mono)))).load();
    }
  }
}

void main() {
  final outPath = Platform.environment['NATIVAX_PERF_OUT'];
  testWidgets(
    'perf probe',
    skip: outPath == null,
    timeout: const Timeout(Duration(minutes: 8)),
    (tester) async {
      final output = outPath!;
      final env = Platform.environment;
      final dir = env['NATIVAX_PERF_PAGE'];
      final width = double.tryParse(env['NATIVAX_PERF_WIDTH'] ?? '') ?? 800;
      final height = double.tryParse(env['NATIVAX_PERF_HEIGHT'] ?? '') ?? 900;
      final idleMs = int.tryParse(env['NATIVAX_PERF_IDLE_MS'] ?? '') ?? 0;
      final waitTimeoutMs =
          int.tryParse(env['NATIVAX_PERF_TIMEOUT_MS'] ?? '') ?? 60000;
      await tester.runAsync(_loadFonts);
      tester.view.physicalSize = Size(width, height);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final source = dir == null
          ? '<!doctype html><html><body></body></html>'
          : File('$dir/index.html').readAsStringSync();
      final errors = <Object>[];
      NativaXRuntime? runtime;
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: NativaXView(
              source: source,
              padding: EdgeInsets.zero,
              config: NativaXRuntimeConfig(
                resources: _Loader(dir),
                documentUrl: 'app://perf/index.html',
                onScriptError: errors.add,
              ),
              onRuntimeReady: (r) => runtime = r,
            ),
          ),
        ),
      );
      for (var i = 0; i < 40 && runtime == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2)),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }
      if (runtime == null) {
        File(output).writeAsStringSync(
          jsonEncode({
            'status': 'failed',
            'error': 'runtime did not become ready',
            'errors': errors.map((e) => '$e').toList(),
          }),
        );
        return;
      }
      final engine = runtime!.engine;
      double number(Object? value) => value is num ? value.toDouble() : 0;
      Object? eval(String js) => engine.evaluate(js, filename: '<perf>');

      Object? safeEval(String js) {
        try {
          return eval(js);
        } catch (error) {
          errors.add(error);
          return null;
        }
      }

      final loadMs = number(safeEval('performance.now()'));
      final setupJs = env['NATIVAX_PERF_SETUP'] ?? '';
      final setupStopwatch = Stopwatch()..start();
      String? setupError;
      if (setupJs.trim().isNotEmpty) {
        try {
          eval(setupJs);
        } catch (error) {
          setupError = '$error';
          errors.add(error);
        }
      }
      final setupPump = Stopwatch()..start();
      await tester.pump(const Duration(milliseconds: 16));
      setupPump.stop();
      final setupMs = setupStopwatch.elapsedMicroseconds / 1000;

      Future<bool> poll(String condition) async {
        try {
          return eval(condition) == true;
        } catch (_) {
          return false;
        }
      }

      final setupWait = env['NATIVAX_PERF_SETUP_WAIT'] ?? '';
      if (setupWait.isNotEmpty) {
        final deadline = DateTime.now().add(
          Duration(milliseconds: waitTimeoutMs),
        );
        while (DateTime.now().isBefore(deadline)) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 2)),
          );
          await tester.pump(const Duration(milliseconds: 16));
          if (await poll(setupWait)) break;
        }
      }

      final nodesBefore = number(
        safeEval("document.getElementsByTagName('*').length"),
      ).toInt();
      final opsJson = env['NATIVAX_PERF_OPS'] ?? '[]';
      final ops = (jsonDecode(opsJson) as List).cast<Map<String, dynamic>>();
      final opResults = <Map<String, Object?>>[];
      final frameTimes = <double>[];
      var scenarioMs = 0.0;
      var renderMs = 0.0;
      String? opError;
      var evalMsTotal = 0.0;

      if (setupError == null) {
        for (final op in ops) {
          final js = op['js'] as String;
          final evalStopwatch = Stopwatch()..start();
          try {
            eval(js);
          } catch (error) {
            opError = '$error';
            opResults.add({'name': op['name'], 'error': '$error'});
            continue;
          }
          final evalMs = evalStopwatch.elapsedMicroseconds / 1000;
          final pumpStopwatch = Stopwatch()..start();
          await tester.pump(const Duration(milliseconds: 16));
          final pumpMs = pumpStopwatch.elapsedMicroseconds / 1000;
          evalMsTotal += evalMs;
          scenarioMs += evalMs;
          renderMs += pumpMs;
          frameTimes.add(pumpMs);
          opResults.add({
            'name': op['name'],
            'eval_ms': evalMs,
            'pump_ms': pumpMs,
          });
          if (opError != null) break;
        }
      }

      final startJs = env['NATIVAX_PERF_START'] ?? '';
      final waitJs = env['NATIVAX_PERF_WAIT'] ?? '';
      final readJs = env['NATIVAX_PERF_READ'] ?? '';
      Map<String, Object?>? startWait;
      Object? read;
      if (setupError == null && opError == null && startJs.isNotEmpty) {
        final stopwatch = Stopwatch()..start();
        safeEval(startJs);
        final deadline = DateTime.now().add(
          Duration(milliseconds: waitTimeoutMs),
        );
        var polls = 0;
        var done = false;
        while (DateTime.now().isBefore(deadline)) {
          final pumpWatch = Stopwatch()..start();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 2)),
          );
          await tester.pump(const Duration(milliseconds: 16));
          final pumpMs = pumpWatch.elapsedMicroseconds / 1000;
          renderMs += pumpMs;
          frameTimes.add(pumpMs);
          polls++;
          if (waitJs.isEmpty || await poll(waitJs)) {
            done = true;
            break;
          }
        }
        scenarioMs = stopwatch.elapsedMicroseconds / 1000;
        startWait = {'start_ms': scenarioMs, 'polls': polls, 'done': done};
        if (readJs.isNotEmpty) {
          try {
            final value = safeEval(readJs);
            if (value is String && value.isNotEmpty) {
              read = jsonDecode(value);
            } else {
              read = value;
            }
          } catch (error) {
            read = {'error': '$error'};
          }
        }
      }

      if (idleMs > 0) {
        final deadline = DateTime.now().add(Duration(milliseconds: idleMs));
        while (DateTime.now().isBefore(deadline)) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }
      }

      final nodes = number(
        safeEval("document.getElementsByTagName('*').length"),
      ).toInt();
      final scrollY = number(safeEval('window.scrollY')).toInt();
      final docHeight = number(
        safeEval('document.documentElement.scrollHeight'),
      ).toInt();
      final title = safeEval('document.title')?.toString() ?? '';
      final result = {
        'status': setupError == null && opError == null ? 'ok' : 'failed',
        if (setupError != null) 'error': 'setup failed: $setupError',
        if (opError != null) 'error': 'operation failed: $opError',
        'load_ms': loadMs,
        'setup_ms': setupMs,
        'setup_pump_ms': setupPump.elapsedMicroseconds / 1000,
        'setup_done': true,
        'nodes_before': nodesBefore,
        'nodes': nodes,
        'scroll_y': scrollY,
        'document_height': docHeight,
        'title': title,
        'scenario_ms': scenarioMs,
        'eval_ms': evalMsTotal,
        'render_ms': renderMs,
        'frame_times': frameTimes,
        'ops': opResults,
        'start_wait': startWait,
        'read': read,
        'errors': errors.map((e) => '$e').toList(),
      };
      File(output).writeAsStringSync(jsonEncode(result));
      // A single line so the Dart runner can parse it without buffering the
      // whole Flutter test output.
      // ignore: avoid_print
      print('PERF: ${jsonEncode(result)}');
      runtime?.dispose();
    },
  );
}
