import 'dart:async';
import 'dart:io';

import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_dom/nativa_dom.dart' as dom;
import 'package:nativa_dom_bindings/nativa_dom_bindings.dart';
import 'package:nativa_html/nativa_html.dart';
import 'package:nativa_js/nativa_js.dart';
import 'package:path/path.dart' as p;

import 'headless_layout.dart';
import 'result.dart';
import 'wpt_shim.dart';

class WptRunOptions {
  const WptRunOptions({
    required this.suitePath,
    required this.directories,
    this.limit,
    this.grep,
    this.timeout = const Duration(seconds: 20),
    this.verbose = false,
    this.harnessSource = wptShim,
  });

  final String suitePath;

  /// The `testharness.js` replacement evaluated before the test scripts.
  /// Only the runner validation swaps it (for a deliberately broken one).
  final String harnessSource;

  /// Directories relative to the WPT checkout, e.g. `dom/nodes`.
  final List<String> directories;
  final int? limit;
  final String? grep;
  final Duration timeout;
  final bool verbose;
}

/// A deliberately small WPT adapter.
///
/// It executes the inline scripts of a test file against NativaX's DOM
/// bindings and a `testharness.js`-compatible shim. It does not implement
/// reftests, testdriver, workers, or multi-global tests. Those cases are
/// reported as SKIP with an explicit reason so they are never mistaken for
/// passing compatibility.
class WptRunner {
  WptRunner(this.options);

  final WptRunOptions options;

  static const _excludedNameParts = [
    '-ref.html',
    '-manual.html',
    '-crash.html',
    '-notref.html',
    '.https.',
    '.window.',
    '.worker.',
  ];

  Future<RunSummary> run() async {
    final started = DateTime.now();
    final clock = Stopwatch()..start();
    final files = <File>[];
    for (final dir in options.directories) {
      final root = Directory(p.join(options.suitePath, dir));
      if (!root.existsSync()) {
        stderr.writeln('WPT: missing directory ${root.path}');
        continue;
      }
      files.addAll(
        root
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where(
              (f) =>
                  f.path.endsWith('.html') &&
                  (options.grep == null || f.path.contains(options.grep!)) &&
                  !_excludedNameParts.any((part) => f.path.contains(part)),
            ),
      );
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    final selected = options.limit == null
        ? files
        : files.take(options.limit!).toList();
    stdout.writeln(
      'WPT: ${selected.length} files '
      '(${options.directories.join(', ')})',
    );

    final results = <TestResult>[];
    for (var i = 0; i < selected.length; i++) {
      final result = await _runFile(selected[i]);
      results.add(result);
      if (options.verbose || (i + 1) % 50 == 0) {
        final pass = results.where((r) => r.status == ResultStatus.pass).length;
        stdout.writeln(
          '  ${i + 1}/${selected.length} ($pass pass) '
          '${p.relative(selected[i].path, from: options.suitePath)}',
        );
      }
    }
    clock.stop();
    return RunSummary(
      suite: 'wpt',
      startedAt: started,
      durationMs: clock.elapsedMilliseconds,
      results: results,
      suiteCommit: _gitHead(),
      command:
          'run_wpt ${options.directories.join(' ')}'
          '${options.limit == null ? '' : ' --limit ${options.limit}'}',
    );
  }

  Future<TestResult> _runFile(File file) async {
    final id = p.relative(file.path, from: options.suitePath);
    final clock = Stopwatch()..start();
    final directory = p.dirname(id).replaceAll('\\', '/');
    final features = [directory.split('/').take(2).join('/')];

    final dom.Document doc;
    try {
      doc = HtmlParser().parseDocument(file.readAsStringSync()).value;
    } catch (error) {
      return _result(
        id,
        ResultStatus.error,
        reason: 'HTML parse failed: $error',
        features: features,
        durationMs: clock.elapsedMilliseconds,
      );
    }
    final scripts = doc.querySelectorAll('script');
    final links = doc.querySelectorAll('link');
    final hasHarness = scripts.any(
      (s) => (s.getAttribute('src') ?? '').endsWith('testharness.js'),
    );
    final isReftest = links.any((l) {
      final rel = (l.getAttribute('rel') ?? '').toLowerCase().split(' ');
      return rel.contains('match') || rel.contains('mismatch');
    });
    if (isReftest && !hasHarness) {
      return _result(
        id,
        ResultStatus.skip,
        reason: 'reftest: visual comparison requires a browser renderer',
        features: features,
        durationMs: clock.elapsedMilliseconds,
      );
    }

    final sources = <({String text, String filename})>[];
    for (final script in scripts) {
      final type = (script.getAttribute('type') ?? '').toLowerCase();
      if (type == 'module') {
        return _result(
          id,
          ResultStatus.skip,
          reason: 'module scripts are not supported by the FFI bridge',
          features: features,
          durationMs: clock.elapsedMilliseconds,
        );
      }
      final src = script.getAttribute('src');
      if (src == null) {
        final text = script.textContent;
        if (text.trim().isNotEmpty) {
          sources.add((text: text, filename: '$id#script${sources.length}'));
        }
        continue;
      }
      if (src.endsWith('testharness.js') ||
          src.endsWith('testharnessreport.js')) {
        continue;
      }
      if (src.contains('testdriver')) {
        return _result(
          id,
          ResultStatus.skip,
          reason: 'requires testdriver.js (WebDriver automation)',
          features: features,
          durationMs: clock.elapsedMilliseconds,
        );
      }
      final dependency = _resolveScript(file, src);
      if (dependency == null) {
        return _result(
          id,
          ResultStatus.skip,
          reason: 'external script dependency outside the suite: $src',
          features: features,
          durationMs: clock.elapsedMilliseconds,
        );
      }
      final dependencyFile = File(dependency);
      if (!dependencyFile.existsSync()) {
        return _result(
          id,
          ResultStatus.skip,
          reason: 'external script dependency missing: $src',
          features: features,
          durationMs: clock.elapsedMilliseconds,
        );
      }
      sources.add((
        text: dependencyFile.readAsStringSync(),
        filename: '$id<script:${p.basename(dependency)}',
      ));
    }
    if (sources.isEmpty) {
      return _result(
        id,
        ResultStatus.skip,
        reason: 'no inline scripts (reftest or resource-only page)',
        features: features,
        durationMs: clock.elapsedMilliseconds,
      );
    }

    QuickJsEngine? engine;
    TimerHost? timers;
    DomBindings? bindings;
    final completed = Completer<void>();
    final subtests = <_Subtest>[];
    final scriptErrors = <String>[];
    var timedOut = false;
    try {
      engine = QuickJsEngine(
        JavaScriptEngineConfig(
          memoryLimitBytes: 256 * 1024 * 1024,
          maxStackBytes: 4 * 1024 * 1024,
          executionBudget: options.timeout,
          maxJobsPerDrain: 100000,
        ),
      );
      final e = engine;
      e.registerHostFunction('wpt.result', (args) {
        subtests.add(
          _Subtest(
            name: '${args.isNotEmpty ? args[0] : '?'}',
            status: '${args.length > 1 ? args[1] : 'FAIL'}',
            message: '${args.length > 2 ? args[2] : ''}',
          ),
        );
        return null;
      });
      e.registerHostFunction('wpt.done', (_) {
        if (!completed.isCompleted) completed.complete();
        return null;
      });
      timers = TimerHost(e);
      const media = MediaContext(width: 800, height: 600);
      final styleEngine = StyleEngine(document: doc, media: media);
      doc.layoutHost = HeadlessLayoutHost(
        document: doc,
        styleEngine: styleEngine,
        width: 800,
        height: 600,
      );
      List<StyleSheet> styleSheets() => [
        for (final style in doc.querySelectorAll('style'))
          StyleSheet.parse(style.textContent),
      ];
      styleEngine.authorSheets = styleSheets();
      bool hasStyle(dom.Node n) {
        if (n is dom.Element && n.localName == 'style') return true;
        for (final c in n.childNodes) {
          if (hasStyle(c)) return true;
        }
        return false;
      }

      void refreshStyles(dom.MutationRecord r) {
        // Use the same incremental invalidation as the renderer. Calling only
        // invalidate() leaves :has()/structural matched caches stale.
        styleEngine.handleMutation(r);
        final relevant = r.type == dom.MutationType.childList
            ? hasStyle(r.target) ||
                  r.addedNodes.any(hasStyle) ||
                  r.removedNodes.any(hasStyle)
            : r.type == dom.MutationType.characterData &&
                  r.target.parentElement?.localName == 'style';
        if (relevant) styleEngine.authorSheets = styleSheets();
      }

      doc.addMutationListener(refreshStyles);
      bindings = DomBindings(
        engine: e,
        document: doc,
        environment: StaticEnvironment(
          media: media,
          languages: const ['en-US'],
          platform: 'linux',
          localStorage: MemoryStorage(),
        ),
        styleEngine: styleEngine,
      )..install();
      e.evaluate(options.harnessSource, filename: '<wpt:testharness>');
      e.evaluate(r'''
for (const el of document.querySelectorAll('[id]')) {
  const id = el.id;
  if (!id || id in globalThis) continue;
  try { Object.defineProperty(globalThis, id, { get() { return document.getElementById(id); }, configurable: true, enumerable: false }); } catch (_) {}
}
''', filename: '<wpt:named-globals>');

      for (var i = 0; i < sources.length; i++) {
        try {
          e.evaluate(sources[i].text, filename: sources[i].filename);
        } on JavaScriptTimeoutException catch (err) {
          scriptErrors.add('script $i timed out: ${err.message}');
          break;
        } on JavaScriptException catch (err) {
          scriptErrors.add('script $i: ${err.name}: ${err.message}');
          break;
        }
      }
      // Ask the shim whether all async tests already settled.
      try {
        e.evaluate('__wptCheckDone()', filename: '<wpt:check>');
      } on JavaScriptException {
        // Ignore: completion is also driven by wpt.done.
      }
      if (!completed.isCompleted) {
        await Future.any<void>([
          completed.future,
          Future<void>.delayed(options.timeout),
        ]);
        // testharness.js reports TIMEOUT for tests that never finish; it is
        // never a pass, even when every reported subtest passed.
        timedOut = !completed.isCompleted && scriptErrors.isEmpty;
      }
    } on JavaScriptException catch (err) {
      scriptErrors.add('${err.name}: ${err.message}');
    } catch (err) {
      return _result(
        id,
        ResultStatus.error,
        reason: 'runner failure: $err',
        features: features,
        durationMs: clock.elapsedMilliseconds,
      );
    } finally {
      try {
        bindings?.dispose();
      } catch (_) {}
      try {
        timers?.dispose();
      } catch (_) {}
      try {
        engine?.dispose();
      } catch (_) {}
    }
    clock.stop();

    if (timedOut) {
      scriptErrors.add('harness timeout after '
          '${options.timeout.inMilliseconds} ms: not every test completed');
    }
    if (subtests.isEmpty && scriptErrors.isEmpty) {
      return _result(
        id,
        ResultStatus.skip,
        reason: 'no testharness tests executed',
        features: features,
        durationMs: clock.elapsedMilliseconds,
      );
    }
    final failed = subtests.where((t) => t.status == 'FAIL').toList();
    final skipped = subtests.where((t) => t.status == 'SKIP').toList();
    if (failed.isNotEmpty || scriptErrors.isNotEmpty) {
      final messages = [
        for (final f in failed.take(5))
          '${f.name}: ${f.message.split('\n').first}',
        ...scriptErrors,
      ];
      return _result(
        id,
        ResultStatus.fail,
        reason: '${failed.length} subtest(s) failed',
        detail: messages.join('\n'),
        features: features,
        durationMs: clock.elapsedMilliseconds,
      );
    }
    if (subtests.isNotEmpty && skipped.length == subtests.length) {
      return _result(
        id,
        ResultStatus.skip,
        reason: 'all subtests skipped: ${skipped.first.message}',
        features: features,
        durationMs: clock.elapsedMilliseconds,
      );
    }
    return _result(
      id,
      ResultStatus.pass,
      features: features,
      durationMs: clock.elapsedMilliseconds,
    );
  }

  /// Resolves a script path relative to the test file (or the suite root
  /// for absolute paths) without allowing traversal outside the checkout.
  String? _resolveScript(File testFile, String src) {
    var path = src.split('?').first.split('#').first;
    if (path.isEmpty || path.contains('://')) return null;
    final String resolved;
    if (path.startsWith('/')) {
      resolved = p.normalize(p.join(options.suitePath, path.substring(1)));
    } else {
      resolved = p.normalize(p.join(p.dirname(testFile.path), path));
    }
    final root = p.normalize(p.absolute(options.suitePath));
    final absolute = p.normalize(p.absolute(resolved));
    if (absolute != root && !p.isWithin(root, absolute)) return null;
    return absolute;
  }

  TestResult _result(
    String id,
    ResultStatus status, {
    String? reason,
    String? detail,
    List<String> features = const [],
    int durationMs = 0,
  }) => TestResult(
    suite: 'wpt',
    id: id,
    status: status,
    reason: reason,
    detail: detail,
    features: features.isEmpty ? const ['web-platform'] : features,
    durationMs: durationMs,
  );

  String? _gitHead() {
    try {
      final result = Process.runSync('git', [
        'rev-parse',
        'HEAD',
      ], workingDirectory: options.suitePath);
      if (result.exitCode != 0) return null;
      return (result.stdout as String).trim();
    } on ProcessException {
      return null;
    }
  }
}

class _Subtest {
  _Subtest({required this.name, required this.status, required this.message});
  final String name;
  final String status;
  final String message;
}
