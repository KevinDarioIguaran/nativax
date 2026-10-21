import 'dart:convert';
import 'dart:io';

import 'package:nativax_html/nativax_html.dart';
import 'package:path/path.dart' as p;

import 'result.dart';

class Html5libRunOptions {
  const Html5libRunOptions({
    required this.suitePath,
    this.limit,
    this.verbose = false,
  });
  final String suitePath;
  final int? limit;
  final bool verbose;
}

/// Runs the tokenizer half of html5lib-tests. Tree-construction fixtures now
/// live in WPT (`html/syntax/parsing`) and are exercised by the WPT runner.
class Html5libRunner {
  Html5libRunner(this.options);

  final Html5libRunOptions options;

  Future<RunSummary> run() async {
    final started = DateTime.now();
    final clock = Stopwatch()..start();
    final dir = Directory(p.join(options.suitePath, 'tokenizer'));
    if (!dir.existsSync()) {
      throw StateError('html5lib tokenizer tests not found at ${dir.path}');
    }
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.test'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    final results = <TestResult>[];
    for (final file in files) {
      final name = p.basename(file.path);
      Map<String, Object?> data;
      try {
        data = (jsonDecode(file.readAsStringSync()) as Map)
            .cast<String, Object?>();
      } on FormatException catch (e) {
        results.add(TestResult(
          suite: 'html5lib-tokenizer',
          id: name,
          status: ResultStatus.error,
          reason: 'invalid JSON: $e',
        ));
        continue;
      }
      for (final entry in data.entries) {
        final list = entry.value;
        if (list is! List) continue;
        final kind = entry.key;
        for (var i = 0; i < list.length; i++) {
          final test = (list[i] as Map).cast<String, Object?>();
          final description = test['description']?.toString() ?? '(sin descripción)';
          final id = '$name#$i [$kind] $description';
          if (options.limit != null && results.length >= options.limit!) {
            break;
          }
          results.add(_runOne(id, test, kind));
        }
      }
    }
    clock.stop();
    return RunSummary(
      suite: 'html5lib-tokenizer',
      startedAt: started,
      durationMs: clock.elapsedMilliseconds,
      results: results,
      suiteCommit: _gitHead(),
      command:
          'run_html5lib${options.limit == null ? '' : ' --limit ${options.limit}'}',
    );
  }

  TestResult _runOne(String id, Map<String, Object?> test, String kind) {
    if (kind == 'xmlViolationTests') {
      return TestResult(
        suite: 'html5lib-tokenizer',
        id: id,
        status: ResultStatus.skip,
        reason: 'runner does not implement xmlViolation mode',
        features: const ['html-tokenizer'],
      );
    }
    if (test['initialStates'] != null) {
      return TestResult(
        suite: 'html5lib-tokenizer',
        id: id,
        status: ResultStatus.skip,
        reason: 'tokenizer only runs from the Data state; arbitrary initial '
            'states are not exposed',
        features: const ['html-tokenizer'],
      );
    }
    var input = test['input']?.toString() ?? '';
    final doubleEscaped = test['doubleEscaped'] == true;
    if (doubleEscaped) input = _doubleUnescape(input);
    final expectedRaw = test['output'];
    if (expectedRaw is! List) {
      return TestResult(
        suite: 'html5lib-tokenizer',
        id: id,
        status: ResultStatus.error,
        reason: 'fixture has no output array',
      );
    }
    final expected = doubleEscaped
        ? expectedRaw
            .map((e) => _unescapeToken((e as List).cast<Object?>()))
            .toList()
        : expectedRaw;
    final expectedList = expected.cast<Object?>();
    if (expectedList.any((t) =>
        t is List && t.isNotEmpty && t.first.toString() == 'DOCTYPE')) {
      return TestResult(
        suite: 'html5lib-tokenizer',
        id: id,
        status: ResultStatus.skip,
        reason: 'DoctypeToken only exposes the name; public/system identifiers '
            'and the force-quirks flag are not available to the runner',
        features: const ['html-tokenizer', 'doctype'],
      );
    }

    final errors = <String>[];
    final actual = <Object?>[];
    try {
      final tokenizer = HtmlTokenizer(
        input,
        onError: (code, offset, [detail]) => errors.add('$code@$offset'),
      );
      for (final token in tokenizer.tokenize()) {
        actual.add(_tokenToJson(token));
      }
    } catch (e) {
      return TestResult(
        suite: 'html5lib-tokenizer',
        id: id,
        status: ResultStatus.error,
        reason: 'tokenizer threw: $e',
        features: const ['html-tokenizer'],
      );
    }
    final merged = _mergeCharacters(actual);
    if (_deepEquals(merged, expectedList)) {
      return TestResult(
        suite: 'html5lib-tokenizer',
        id: id,
        status: ResultStatus.pass,
        features: const ['html-tokenizer'],
      );
    }
    return TestResult(
      suite: 'html5lib-tokenizer',
      id: id,
      status: ResultStatus.fail,
      reason: 'token stream differs from the fixture',
      detail: 'input: ${jsonEncode(input)}\n'
          'expected: ${jsonEncode(expectedList)}\n'
          'actual:   ${jsonEncode(merged)}'
          '${errors.isEmpty ? '' : '\nerrors: ${errors.join(', ')}'}',
      features: const ['html-tokenizer'],
    );
  }

  String? _gitHead() {
    try {
      final result = Process.runSync(
        'git',
        ['rev-parse', 'HEAD'],
        workingDirectory: options.suitePath,
      );
      if (result.exitCode != 0) return null;
      return (result.stdout as String).trim();
    } on ProcessException {
      return null;
    }
  }
}

List<Object?> _tokenToJson(Token token) => switch (token) {
      StartTagToken(:final name, :final attributes, :final selfClosing) => [
          'StartTag',
          name,
          {for (final a in attributes) a.$1: a.$2},
          if (selfClosing) true,
        ],
      EndTagToken(:final name) => ['EndTag', name],
      TextToken(:final data) => ['Character', data],
      CommentToken(:final data) => ['Comment', data],
      DoctypeToken(:final name) => [
          'DOCTYPE',
          name,
          null,
          null,
          name.toLowerCase() == 'html',
        ],
    };

List<Object?> _mergeCharacters(List<Object?> tokens) {
  final out = <Object?>[];
  for (final token in tokens) {
    if (token is List &&
        token.length >= 2 &&
        token[0] == 'Character' &&
        out.isNotEmpty &&
        out.last is List &&
        (out.last as List)[0] == 'Character') {
      final previous = (out.removeLast() as List);
      out.add(['Character', '${previous[1]}${token[1]}']);
    } else {
      out.add(token);
    }
  }
  return out;
}

bool _deepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

List<Object?> _unescapeToken(List<Object?> token) => [
      for (final value in token)
        if (value is String) _doubleUnescape(value) else value,
    ];

/// html5lib's `doubleEscaped` fixtures store a JSON-escaped string inside a
/// JSON string. Decode the common escapes without relying on the original
/// fixture's raw quoting.
String _doubleUnescape(String value) {
  final out = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    final c = value[i];
    if (c != '\\' || i + 1 >= value.length) {
      out.write(c);
      continue;
    }
    final next = value[i + 1];
    switch (next) {
      case 'n':
        out.write('\n');
        i++;
      case 'r':
        out.write('\r');
        i++;
      case 't':
        out.write('\t');
        i++;
      case 'b':
        out.write('\b');
        i++;
      case 'f':
        out.write('\f');
        i++;
      case '\\':
        out.write('\\');
        i++;
      case '"':
        out.write('"');
        i++;
      case 'u':
        if (i + 5 < value.length) {
          final hex = value.substring(i + 2, i + 6);
          final code = int.tryParse(hex, radix: 16);
          if (code != null) {
            out.writeCharCode(code);
            i += 5;
          } else {
            out.write(c);
          }
        } else {
          out.write(c);
        }
      default:
        out.write(c);
    }
  }
  return out.toString();
}
