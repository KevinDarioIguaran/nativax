import 'dart:io';

import 'package:nativa_visual/src/staging.dart';
import 'package:test/test.dart';

void main() {
  test('modal dialogs are stubbed before any page script runs', () {
    // mdn functions/conflict.html calls alert(); a modal dialog blocks
    // headless Chrome until the 120 s timeout and the page was INVALID.
    final root = Directory.systemTemp.createTempSync('nativa-visual-stage-');
    addTearDown(() => root.deleteSync(recursive: true));
    final source = Directory('${root.path}/src')..createSync();
    File('${source.path}/index.html').writeAsStringSync(
      '<!doctype html><html><head><script>alert(1)</script></head>'
      '<body></body></html>',
    );
    final staged = stagePage(source.path, Directory('${root.path}/out'));
    final html = File('${staged.path}/index.html').readAsStringSync();
    final stub = html.indexOf('window.alert = function');
    expect(stub, greaterThan(0));
    expect(stub, lessThan(html.indexOf('alert(1)')));
  });
}
