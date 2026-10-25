import 'dart:io';

import 'package:nativa_visual/src/fixtures.dart';
import 'package:test/test.dart';

void main() {
  group('fixture discovery', () {
    test('finds page directories and skips hidden and starter folders', () {
      final root = Directory.systemTemp.createTempSync(
        'nativa-visual-fixtures-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      Directory('${root.path}/alpha').createSync();
      File('${root.path}/alpha/index.html').writeAsStringSync('<html></html>');
      Directory('${root.path}/beta').createSync();
      File('${root.path}/beta/index.html').writeAsStringSync('<html></html>');
      Directory('${root.path}/_starter').createSync();
      File(
        '${root.path}/_starter/index.html',
      ).writeAsStringSync('<html></html>');
      Directory('${root.path}/.cache').createSync();
      File('${root.path}/.cache/index.html').writeAsStringSync('<html></html>');
      File('${root.path}/README.md').writeAsStringSync('# x');

      final pages = discoverPages(root.path, suite: 'demo');
      expect(pages.map((p) => p.id), ['demo/alpha', 'demo/beta']);
      expect(pages.every((p) => p.entry.endsWith('index.html')), isTrue);
    });

    test('a single HTML file becomes a local page', () {
      final root = Directory.systemTemp.createTempSync('nativa-visual-page-');
      addTearDown(() => root.deleteSync(recursive: true));
      final file = File('${root.path}/My Page.html')
        ..writeAsStringSync('<html></html>');
      final page = pageFromPath(file.path);
      expect(page.suite, 'local');
      expect(page.id, 'my-page');
      expect(page.directory, root.path);
    });

    test('recursive discovery skips internal dirs and honours maxPages', () {
      final root = Directory.systemTemp.createTempSync('nativa-visual-rec-');
      addTearDown(() => root.deleteSync(recursive: true));
      for (final name in ['a', 'b', 'c', 'node_modules/d', '_starter']) {
        Directory('${root.path}/$name').createSync(recursive: true);
        File(
          '${root.path}/$name/index.html',
        ).writeAsStringSync('<html></html>');
      }
      final suite = FixtureSuite(
        id: 'demo',
        url: 'demo/demo',
        commit: 'x',
        license: 'MIT',
        recursive: true,
        maxPages: 2,
      );
      final pages = discoverSuitePages(root.path, suite);
      expect(pages.map((p) => p.id), ['demo/a', 'demo/b']);
    });

    test('include lists select exact nested pages', () {
      final root = Directory.systemTemp.createTempSync('nativa-visual-inc-');
      addTearDown(() => root.deleteSync(recursive: true));
      Directory('${root.path}/one/two').createSync(recursive: true);
      File(
        '${root.path}/one/two/index.html',
      ).writeAsStringSync('<html></html>');
      final suite = FixtureSuite(
        id: 'demo',
        url: 'demo/demo',
        commit: 'x',
        license: 'CC0-1.0',
        includes: const ['one/two'],
      );
      final pages = discoverSuitePages(root.path, suite);
      expect(pages.single.id, 'demo/one/two');
    });

    test('catalog covers the requested visual suites', () {
      expect(knownSuites.length, greaterThanOrEqualTo(5));
      expect(
        knownSuites.map((s) => s.id),
        containsAll([
          '50projects50days',
          'mdn-css-examples',
          'mdn-learning-area',
          'odin-css-exercises',
          'mdn-dom-examples',
        ]),
      );
      expect(knownSuites.every((s) => s.commit.length >= 40), isTrue);
    });

    test('options resolve the pinned suite', () {
      expect(suiteById('50projects50days')?.license, 'MIT');
      expect(suiteById('missing'), isNull);
      expect(knownSuites.first.archiveUrl, contains('codeload.github.com'));
    });

    test('vendored 50projects50days suite has at least 50 pages', () {
      final root = Directory.current;
      final vendor = Directory('${root.path}/fixtures/50projects50days');
      if (!vendor.existsSync()) {
        markTestSkipped('vendored suite not present');
        return;
      }
      final pages = discoverPages(vendor.path, suite: '50projects50days');
      expect(pages.length, greaterThanOrEqualTo(50));
      expect(pages.any((p) => p.id.endsWith('_project_starter_')), isFalse);
      expect(
        File('${vendor.path}/NOTICE.md').existsSync(),
        isTrue,
        reason: 'provenance must ship with the fixtures',
      );
    });
  });
}
