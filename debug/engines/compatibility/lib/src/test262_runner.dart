import 'dart:async';
import 'dart:io';

import 'package:nativa_js/nativa_js.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'result.dart';
import 'run_output.dart';

/// Minimal, dependency-free parser for Test262's `/*--- ... ---*/`
/// frontmatter. YAML is parsed with `package:yaml`; the metadata is copied to
/// plain Dart collections so callers never see `YamlMap`.
class Test262Metadata {
  Test262Metadata(this.data, this.body);

  final Map<String, Object?> data;
  final String body;

  List<String> get features => _strings('features');
  List<String> get flags => _strings('flags');
  List<String> get includes => _strings('includes');

  String? get description => data['description']?.toString();

  Map<String, Object?>? get negative {
    final n = data['negative'];
    return n is Map ? n.cast<String, Object?>() : null;
  }

  List<String> _strings(String key) {
    final value = data[key];
    if (value is List) return value.map((e) => e.toString()).toList();
    return const [];
  }
}

Test262Metadata parseTest262Metadata(String source) {
  final start = source.indexOf('/*---');
  if (start < 0) return Test262Metadata(const {}, source);
  final end = source.indexOf('---*/', start + 5);
  if (end < 0) return Test262Metadata(const {}, source);
  final yamlSource = source.substring(start + 5, end);
  Object? parsed;
  try {
    parsed = loadYaml(yamlSource);
  } on YamlException {
    parsed = null;
  }
  final data = parsed is Map
      ? _plainMap(parsed)
      : const <String, Object?>{};
  final body = source.substring(0, start) + source.substring(end + 5);
  return Test262Metadata(data, body);
}

Map<String, Object?> _plainMap(Map<dynamic, dynamic> source) => {
      for (final e in source.entries)
        e.key.toString(): _plainValue(e.value),
    };

Object? _plainValue(Object? value) {
  if (value is Map) return _plainMap(value);
  if (value is List) return value.map(_plainValue).toList();
  return value;
}

class Test262RunOptions {
  const Test262RunOptions({
    required this.suitePath,
    required this.directories,
    this.limit,
    this.skipFeatures = const {},
    this.timeout = const Duration(seconds: 2),
    this.verbose = false,
  });

  /// Path to the Test262 checkout.
  final String suitePath;

  /// Directories relative to the checkout, for example
  /// `test/language/expressions`.
  final List<String> directories;
  final int? limit;

  /// Feature names that NativaX deliberately excludes from this run. They are
  /// reported as SKIP, never as PASS.
  final Set<String> skipFeatures;
  final Duration timeout;
  final bool verbose;
}

class Test262Runner {
  Test262Runner(this.options);

  final Test262RunOptions options;

  /// Features that require a module loader or host import hooks, which the
  /// current FFI bridge does not provide. They are reported as SKIP so they
  /// are not confused with language incompatibilities.
  static const runnerLimitedFeatures = {
    'dynamic-import',
    'import-defer',
    'source-phase-imports',
    'source-phase-imports-module-source',
    'import-attributes',
  };

  final Map<String, String> _harnessCache = {};

  Future<RunSummary> run({void Function(TestResult result)? onResult}) async {
    final started = DateTime.now();
    final clock = Stopwatch()..start();
    final files = <File>[];
    for (final dir in options.directories) {
      final root = Directory(p.join(options.suitePath, dir));
      if (!root.existsSync()) {
        stderr.writeln('Test262: missing directory ${root.path}');
        continue;
      }
      final found = root
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((f) =>
              f.path.endsWith('.js') &&
              !f.path.endsWith('_FIXTURE.js'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      files.addAll(found);
    }
    final selected =
        options.limit == null ? files : files.take(options.limit!).toList();

    stdout.writeln('Test262: ${selected.length} tests '
        '(${options.directories.join(', ')})');

    final results = <TestResult>[];
    for (var i = 0; i < selected.length; i++) {
      final file = selected[i];
      final result = await _runFile(file);
      results.add(result);
      onResult?.call(result);
      if (options.verbose || (i + 1) % 250 == 0) {
        final passed = results.where((r) => r.status == ResultStatus.pass).length;
        stdout.writeln('  ${i + 1}/${selected.length} '
            '($passed pass) ${p.relative(file.path, from: options.suitePath)}');
      }
    }
    clock.stop();
    return RunSummary(
      suite: 'test262',
      startedAt: started,
      durationMs: clock.elapsedMilliseconds,
      results: results,
      suiteCommit: suiteRevision(options.suitePath),
      command: 'run_test262 ${options.directories.join(' ')}'
          '${options.limit == null ? '' : ' --limit ${options.limit}'}',
    );
  }


  Future<TestResult> _runFile(File file) async {
    final id = p.relative(file.path, from: p.join(options.suitePath, 'test'));
    final clock = Stopwatch()..start();
    String source;
    try {
      source = file.readAsStringSync();
    } on FileSystemException catch (e) {
      return _result(id, ResultStatus.error, reason: 'read failure: $e');
    }
    final meta = parseTest262Metadata(source);
    final flags = meta.flags;

    if (flags.contains('module')) {
      return _result(
        id,
        ResultStatus.skip,
        reason: 'module tests need JS_EVAL_TYPE_MODULE; the FFI bridge only '
            'evaluates global scripts',
        features: meta.features,
      );
    }
    if (flags.contains('onlyStrict') && flags.contains('noStrict')) {
      return _result(id, ResultStatus.skip,
          reason: 'contradictory onlyStrict + noStrict flags',
          features: meta.features);
    }
    const runnerUnsupported = [
      r'$262.createRealm',
      r'$262.detachArrayBuffer',
      r'$262.agent',
      r'$262.IsHTMLDDA',
    ];
    for (final marker in runnerUnsupported) {
      if (source.contains(marker)) {
        return _result(
          id,
          ResultStatus.skip,
          reason: 'runner limitation: $marker is a host-only Test262 API',
          features: meta.features,
        );
      }
    }
    final runnerLimited =
        meta.features.where(runnerLimitedFeatures.contains).toList();
    if (runnerLimited.isNotEmpty) {
      return _result(
        id,
        ResultStatus.skip,
        reason: 'runner limitation: no module loader/import hooks '
            '(${runnerLimited.join(', ')})',
        features: meta.features,
      );
    }

    // QuickJS-ng does not implement proper tail calls. Running these tests
    // can exhaust the native stack before the engine's stack check fires, so
    // they are an explicit engine gap rather than a runner bug.
    final engineGaps = meta.features
        .where((f) => f == 'tail-call-optimization')
        .toList();
    final excluded = [
      ...engineGaps,
      ...meta.features.where(options.skipFeatures.contains),
    ];
    if (excluded.isNotEmpty) {
      return _result(
        id,
        ResultStatus.skip,
        reason: excluded.contains('tail-call-optimization')
            ? 'engine gap: QuickJS-ng does not implement tail-call optimization'
            : 'feature policy: ${excluded.join(', ')}',
        features: meta.features,
      );
    }

    final onlyStrict = flags.contains('onlyStrict');
    final raw = flags.contains('raw');
    // Test262 INTERPRETING.md: `raw` implies `noStrict`; the source runs
    // verbatim, without harness files or a "use strict" prefix.
    final noStrict = flags.contains('noStrict') || raw;
    final modes = onlyStrict
        ? const [true]
        : noStrict
            ? const [false]
            : const [false, true];
    final async = flags.contains('async');

    final failures = <String>[];
    for (final strict in modes) {
      final mode = strict ? 'strict' : 'sloppy';
      final outcome = await _runInFreshEngine(
        source: source,
        meta: meta,
        strict: strict,
        raw: raw,
        async: async,
      );
      if (outcome.harnessError) {
        return _result(id, ResultStatus.error,
            reason: '[$mode] ${outcome.message}',
            features: meta.features,
            durationMs: clock.elapsedMilliseconds);
      }
      if (!outcome.ok) {
        failures.add('[$mode] ${outcome.message}');
        if (!options.verbose) break;
      }
    }
    clock.stop();

    if (failures.isEmpty) {
      return _result(id, ResultStatus.pass,
          features: meta.features, durationMs: clock.elapsedMilliseconds);
    }
    return _result(
      id,
      ResultStatus.fail,
      reason: failures.first,
      detail: failures.length > 1 ? failures.join('\n') : null,
      features: meta.features,
      durationMs: clock.elapsedMilliseconds,
    );
  }

  TestResult _result(
    String id,
    ResultStatus status, {
    String? reason,
    String? detail,
    List<String> features = const [],
    int durationMs = 0,
  }) =>
      TestResult(
        suite: 'test262',
        id: id,
        status: status,
        reason: reason,
        detail: detail,
        features: features.isEmpty ? const ['core'] : features,
        durationMs: durationMs,
      );

  Future<_Outcome> _runInFreshEngine({
    required String source,
    required Test262Metadata meta,
    required bool strict,
    required bool raw,
    required bool async,
  }) async {
    JscEngine? engine;
    TimerHost? timers;
    final done = Completer<String?>();
    String? doneError;
    var doneCalls = 0;
    var evaluating = false;
    try {
      engine = JscEngine(JavaScriptEngineConfig(
        memoryLimitBytes: 256 * 1024 * 1024,
        maxStackBytes: 512 * 1024,
        executionBudget: options.timeout,
        maxJobsPerDrain: 100000,
      ));
      final e = engine;
      e.registerHostFunction('test262.done', (args) {
        doneCalls++;
        if (doneCalls > 1) {
          doneError ??= 'Test262Error: \$DONE called more than once';
          return null;
        }
        final value = args.isEmpty ? null : args.first;
        doneError = value == null || '$value'.isEmpty
            ? null
            : 'Test262Error: $value';
        if (!done.isCompleted) done.complete(doneError);
        return null;
      });
      e.registerHostFunction('test262.evaluating', (_) {
        evaluating = true;
        return null;
      });
      e.registerHostFunction('test262.gc', (_) {
        e.collectGarbage();
        return null;
      });
      timers = TimerHost(e);

      // The host prelude runs as its own script so that a parse error in the
      // test never hides it, and so that the test script can start with a
      // real "use strict" directive. A directive is only a directive at the
      // start of the script: placed after other statements it is a plain
      // string expression and the code stays sloppy.
      final prefix = StringBuffer();
      if (raw) {
        e.evaluate(_hostPrelude, filename: '<test262:host>');
        prefix.write(source);
      } else {
        if (strict) prefix.writeln('"use strict";');
        // Runs only if the whole script parsed. A parse-phase negative test
        // passes only when this marker never fires.
        prefix.writeln("__nx.host('test262.evaluating');");
        for (final include in ['sta.js', 'assert.js', ...meta.includes]) {
          // Test262 includes are harness file names. Reject traversal.
          if (include.contains('/') || include.contains('..')) {
            return _Outcome.harness('invalid include: $include');
          }
          final harness = _harness(include);
          if (harness == null) {
            return _Outcome.harness('missing Test262 harness file: $include');
          }
          prefix.writeln(harness);
        }
        e.evaluate(_hostPrelude, filename: '<test262:host>');
        prefix.writeln(source);
      }

      final negative = meta.negative;
      if (negative != null) {
        final phase = negative['phase']?.toString() ?? 'runtime';
        final type = negative['type']?.toString() ?? 'Error';
        try {
          e.evaluate(prefix.toString(),
              filename: p.basename('/test262/$phase'));
          return _Outcome(false,
              'expected $type during $phase, but the test completed normally');
        } on JavaScriptTimeoutException catch (err) {
          return _Outcome(false, 'timeout: ${err.message}');
        } on JavaScriptException catch (err) {
          final early = phase == 'parse' || phase == 'resolution';
          // A raw test cannot carry the marker, so the phase is not checked.
          if (err.name == type && early && evaluating && !raw) {
            return _Outcome(false,
                'expected $type during $phase, but it was thrown at runtime');
          }
          if (err.name == type) return const _Outcome(true, '');
          return _Outcome(false,
              'expected $type during $phase, got ${err.name}: ${err.message}');
        }
      }

      try {
        e.evaluate(prefix.toString(), filename: p.basename(meta.data['esid']?.toString() ?? 'test.js'));
      } on JavaScriptTimeoutException catch (err) {
        return _Outcome(false, 'timeout: ${err.message}');
      } on JavaScriptException catch (err) {
        final where = err.stack == null ? '' : '\n${err.stack}';
        return _Outcome(false, '${err.name}: ${err.message}$where');
      }

      if (async || doneCalls > 0) {
        final value = await Future.any<String?>([
          done.future,
          Future<String?>.delayed(options.timeout, () => _asyncSentinel),
        ]);
        if (identical(value, _asyncSentinel)) {
          return _Outcome(false,
              '\$DONE was not called within ${options.timeout.inMilliseconds} ms');
        }
        if (value != null) return _Outcome(false, value);
      } else if (doneCalls > 0 && doneError != null) {
        return _Outcome(false, doneError!);
      }
      return const _Outcome(true, '');
    } on JavaScriptEngineStateException catch (err) {
      return _Outcome(false, 'engine failure: ${err.message}');
    } catch (err) {
      return _Outcome.harness('runner error: $err');
    } finally {
      try {
        timers?.dispose();
      } catch (_) {}
      try {
        engine?.dispose();
      } catch (_) {}
    }
  }

  String? _harness(String name) {
    final cached = _harnessCache[name];
    if (cached != null) return cached;
    final file = File(p.join(options.suitePath, 'harness', name));
    if (!file.existsSync()) return null;
    return _harnessCache[name] = file.readAsStringSync();
  }

  static const _asyncSentinel = '<__nativax_async_timeout__>';
}

class _Outcome {
  const _Outcome(this.ok, this.message) : harnessError = false;
  const _Outcome.harness(this.message)
      : ok = false,
        harnessError = true;
  final bool ok;
  final String message;

  /// The harness, not the engine, failed: reported as ERROR, never FAIL.
  final bool harnessError;
}

const _hostPrelude = r'''
globalThis.$262 = Object.freeze({
  global: globalThis,
  evalScript(source) { return (0, eval)(String(source)); },
  gc() { __nx.host('test262.gc'); },
});
globalThis.$DONE = function (error) {
  __nx.host('test262.done', error === undefined ? null : String(error));
};
''';
