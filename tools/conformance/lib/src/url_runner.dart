import 'dart:convert';
import 'dart:io';

import 'package:nativa_css/nativa_css.dart' show MediaContext;
import 'package:nativa_dom/nativa_dom.dart' as dom;
import 'package:nativa_dom_bindings/nativa_dom_bindings.dart';
import 'package:nativa_js/nativa_js.dart';
import 'package:path/path.dart' as p;

import 'result.dart';

class UrlRunOptions {
  const UrlRunOptions({required this.suitePath, this.limit});
  final String suitePath;
  final int? limit;
}

/// Runs the WHATWG URL fixture from WPT (`url/resources/urltestdata.json`).
///
/// The fixture is data-only, so it can be executed without a browser. If
/// `URL` is not exposed to scripts yet, every case is reported as FAIL with
/// that reason: a missing feature is not a runner limitation.
class UrlRunner {
  UrlRunner(this.options);

  final UrlRunOptions options;

  Future<RunSummary> run() async {
    final started = DateTime.now();
    final clock = Stopwatch()..start();
    final file = File(p.join(
      options.suitePath,
      'url',
      'resources',
      'urltestdata.json',
    ));
    if (!file.existsSync()) {
      throw StateError('URL fixture not found at ${file.path}');
    }
    final raw = jsonDecode(file.readAsStringSync()) as List;
    final cases = raw.whereType<Map>().cast<Map>().toList();
    final selected = options.limit == null
        ? cases
        : cases.take(options.limit!).toList();

    final engine = QuickJsEngine();
    final document = dom.Document();
    final bindings = DomBindings(
      engine: engine,
      document: document,
      environment: StaticEnvironment(
        media: const MediaContext(width: 800, height: 600),
        platform: 'linux',
      ),
    )..install();
    String? missingApi;
    final results = <TestResult>[];
    try {
      final type = engine.evaluate('typeof URL');
      if (type != 'function') {
        missingApi = 'URL is not exposed to scripts';
      } else {
        engine.evaluate(_urlHelper);
      }

      for (var i = 0; i < selected.length; i++) {
        final data = selected[i];
        final input = data['input']?.toString() ?? '';
        final base = data['base']?.toString();
        final id = '#$i ${jsonEncode(input)}'
            '${base == null ? '' : ' base=${jsonEncode(base)}'}';
        if (missingApi != null) {
          results.add(TestResult(
            suite: 'wpt-url',
            id: id,
            status: ResultStatus.fail,
            reason: missingApi,
            features: const ['url'],
          ));
          continue;
        }
        results.add(_runCase(engine, id, data, input, base));
      }
    } finally {
      bindings.dispose();
      engine.dispose();
    }
    clock.stop();
    return RunSummary(
      suite: 'wpt-url',
      startedAt: started,
      durationMs: clock.elapsedMilliseconds,
      results: results,
      command: 'run_url${options.limit == null ? '' : ' --limit ${options.limit}'}',
    );
  }

  TestResult _runCase(
    QuickJsEngine engine,
    String id,
    Map data,
    String input,
    String? base,
  ) {
    try {
      final actual = engine.callGlobal('__nx_url', [input, base]);
      if (data['failure'] == true) {
        return TestResult(
          suite: 'wpt-url',
          id: id,
          status: actual == null ? ResultStatus.pass : ResultStatus.fail,
          reason: actual == null
              ? null
              : 'expected URL parsing to fail, got $actual',
          features: const ['url'],
        );
      }
      if (actual is! Map) {
        return TestResult(
          suite: 'wpt-url',
          id: id,
          status: ResultStatus.fail,
          reason: 'URL parsing failed',
          features: const ['url'],
        );
      }
      const fields = [
        'href',
        'origin',
        'protocol',
        'username',
        'password',
        'host',
        'hostname',
        'port',
        'pathname',
        'search',
        'hash',
      ];
      final mismatches = <String>[];
      for (final field in fields) {
        if (data.containsKey(field) && '${actual[field]}' != '${data[field]}') {
          mismatches.add('$field: expected ${data[field]}, got ${actual[field]}');
        }
      }
      return TestResult(
        suite: 'wpt-url',
        id: id,
        status:
            mismatches.isEmpty ? ResultStatus.pass : ResultStatus.fail,
        reason: mismatches.isEmpty ? null : mismatches.first,
        detail: mismatches.length > 1 ? mismatches.join('\n') : null,
        features: const ['url'],
      );
    } catch (error) {
      return TestResult(
        suite: 'wpt-url',
        id: id,
        status: ResultStatus.error,
        reason: 'runner failure: $error',
        features: const ['url'],
      );
    }
  }
}

const _urlHelper = r'''
globalThis.__nx_url = (arg) => {
  const input = arg[0];
  const base = arg[1];
  try {
    const u = new URL(String(input), base === null || base === undefined ? undefined : String(base));
    return {
      href: u.href, origin: u.origin, protocol: u.protocol,
      username: u.username, password: u.password,
      host: u.host, hostname: u.hostname, port: u.port,
      pathname: u.pathname, search: u.search, hash: u.hash,
    };
  } catch (e) {
    return null;
  }
};
''';
