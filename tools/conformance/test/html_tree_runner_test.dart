import 'dart:io';

import 'package:nativa_conformance/conformance.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<RunSummary> _run(String dat) async {
  final root = Directory.systemTemp.createTempSync('html_tree_');
  addTearDown(() => root.deleteSync(recursive: true));
  final dir = Directory(p.join(root.path, 'html', 'syntax', 'parsing', 'resources'))
    ..createSync(recursive: true);
  File(p.join(dir.path, 'case.dat')).writeAsStringSync(dat);
  return HtmlTreeRunner(HtmlTreeRunOptions(suitePath: root.path)).run();
}

void main() {
  test('attribute lines in the expected tree are compared', () async {
    final summary = await _run('''
#data
<p id="a" class="b">x
#errors
#document
| <html>
|   <head>
|   <body>
|     <p>
|       class="b"
|       id="a"
|       "x"
''');
    expect(summary.passed, 1, reason: summary.results.first.detail);
  });

  test('a wrong expected attribute value fails', () async {
    final summary = await _run('''
#data
<p id="a">x
#errors
#document
| <html>
|   <head>
|   <body>
|     <p>
|       id="other"
|       "x"
''');
    expect(summary.failed, 1);
  });
}
