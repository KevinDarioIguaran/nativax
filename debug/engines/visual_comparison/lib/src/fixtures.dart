import 'dart:io';

import 'model.dart';

/// Fixture suites understood by the CLI. Each entry is a pinned external
/// checkout so runs are reproducible and the repository does not vendor
/// third-party pages.
class FixtureSuite {
  const FixtureSuite({
    required this.id,
    required this.url,
    required this.commit,
    required this.license,
    this.description = '',
    this.recursive = false,
    this.maxPages = 0,
    this.includes = const [],
    this.htmlPages = false,
  });

  final String id;
  final String url;
  final String commit;
  final String license;
  final String description;
  final bool recursive;
  final int maxPages;
  final List<String> includes;

  /// Include any `.html` file, not only directories with `index.html`.
  final bool htmlPages;

  String get archiveUrl => 'https://codeload.github.com/$url/tar.gz/$commit';
}

const List<FixtureSuite> knownSuites = [
  FixtureSuite(
    id: '50projects50days',
    url: 'bradtraversy/50projects50days',
    commit: 'c92b0bc3a87fc95d44b89552b7b6a2eeb36ca481',
    license: 'MIT',
    description: 'Brad Traversy, 50 HTML/CSS/JS mini projects (no framework).',
  ),
  FixtureSuite(
    id: 'mdn-css-examples',
    url: 'mdn/css-examples',
    commit: '65b08d2236b304d50d28a807a48c35f6889d902d',
    license: 'CC0-1.0',
    recursive: true,
    maxPages: 27,
    description: 'MDN CSS examples: flexbox, grid, clamp, shapes, generators.',
  ),
  FixtureSuite(
    id: 'mdn-learning-area',
    url: 'mdn/learning-area',
    commit: '21973263ba859ff3477919087b488157f9d618a6',
    license: 'CC0-1.0',
    recursive: true,
    maxPages: 139,
    htmlPages: true,
    description: 'MDN learning area examples: HTML, forms, accessibility, CSS.',
  ),
  FixtureSuite(
    id: 'odin-css-exercises',
    url: 'TheOdinProject/css-exercises',
    commit: 'eae53f9c9030b9be41c2a6d07bb19e262c98a13e',
    license: 'MIT',
    recursive: true,
    maxPages: 21,
    description: 'The Odin Project CSS exercises: cascade, flex, grid, animation.',
  ),
  FixtureSuite(
    id: 'mdn-dom-examples',
    url: 'mdn/dom-examples',
    commit: '03ae1ffb325a9202d3a64f26ab5b8361392a5368',
    license: 'CC0-1.0',
    includes: _domSelection,
    description: 'MDN DOM/UI examples: popovers, dialogs, canvas, WebGL, scroll.',
  ),
];

const List<String> _domSelection = [
  'css-carousels/scroll-button-scroll-marker-with-columns',
  'css-carousels/scroll-button-scroll-marker',
  'css-custom-functions/color-adjust-functions',
  'css-custom-functions/gradient-function',
  'css-custom-functions/responsive-narrow-wide',
  'css-painting/custom-properties',
  'css-painting/fancy-header-highlight',
  'css-painting/half-highlight-fixed-size',
  'css-painting/half-highlight-paintsize',
  'css-painting/hollow-highlight',
  'css-painting/index',
  'css-progress/index',
  'css-typed-arithmetic/animated-story-circle',
  'css-typed-arithmetic/different-type-variations',
  'css-typed-arithmetic/index',
  'css-typed-arithmetic/responsive-background-opacity',
  'htmldialogelement-basic',
  'interest-invokers/popover-examples',
  'interest-invokers/stock-moving',
  'interest-invokers/style-preview',
  'popover-api/basic-declarative',
  'popover-api/blur-background',
  'popover-api/multiple-auto',
  'popover-api/multiple-manual',
  'popover-api/nested-popovers',
  'popover-api/popover-hint',
  'popover-api/popover-positioning',
  'popover-api/toast-popovers',
  'popover-api/toggle-help-ui',
  'view-transitions/match-element',
  'view-transitions/mpa',
  'view-transitions/mpa-homepage',
  'view-transitions/spa',
  'view-transitions/spa-gallery-transition-types',
  'webgl-examples/tutorial/sample1',
  'webgl-examples/tutorial/sample2',
  'webgl-examples/tutorial/sample3',
  'webgl-examples/tutorial/sample4',
  'webgl-examples/tutorial/sample5',
  'webgl-examples/tutorial/sample6',
  'webgl-examples/tutorial/sample7',
  'webgl-examples/tutorial/sample8',
  'canvas/chroma-keying',
  'streams/grayscale-png',
  'streams/simple-pump',
  'streams/simple-writer',
  'streams/simple-tee-example',
  'web-workers/offscreen-canvas-worker',
  'fullscreen-api',
  'matchmedia',
  'mediaquerylist',
  'responsive-iframe-sizing/basic',
  'responsive-iframe-sizing/js-request-resize',
  'scroll-promises/element-methods',
  'scroll-promises/window-methods',
  'scrolltooptions',
  'web-storage',
  'history-api',
  'visual-viewport-api',
  'viewport-segments-api',
  'document-picture-in-picture',
  'picture-in-picture',
  'dynamic-range-limit',
  'to-do-notifications',
  'edit-context/html-editor',
  'abort-api',
  'audiocontext-setsinkid',
  'auxclick',
  'channel-messaging-basic',
  'channel-messaging-multimessage',
  'contact-picker',
  'css-painting',
  'css-progress',
  'css-typed-arithmetic',
  'device-posture-api',
  'execcommand',
  'fetch/basic-fetch',
  'fetch/fetch-array-buffer',
  'fetch/fetch-json',
  'fetch/fetch-request',
  'fetch/fetch-request-with-init',
  'fetch/fetch-response',
  'fetch/fetch-response-clone',
  'fetch/fetch-text',
  'fetch/object-fit-gallery-fetch',
  'file-system-api/createsyncaccesshandle-mode',
  'file-system-api/createwritable-mode',
  'file-system-api/filesystemhandle-remove',
  'file-system-api/filesystemobserver',
  'geolocation-element/basic-example',
  'geolocation-element/basic-watch-example',
  'geolocation-element/embedded-map',
  'geolocation-element/exploring-invalid-reasons',
  'geolocation-element/initial-permission-status',
  'indexeddb-api',
  'indexeddb-examples/idbcursor',
  'indexeddb-examples/idbindex',
  'indexeddb-examples/idbkeyrange',
  'launch-handler',
  'local-font-access',
  'media-session',
  'media-source-extensions/managed-media-source',
  'media/getstartdate',
  'media/mediaerror',
  'media/web-dictaphone',
  'navigation-api',
  'notifications/non-persistent',
  'notifications/persistent',
  'pointer-lock',
  'prompt-api-web-storage',
  'resize-event',
  'screen-capture-api/basic-screen-capture',
  'screen-capture-api/element-capture',
  'screen-capture-api/element-screenshot',
  'screen-capture-api/region-capture',
  'screen-wake-lock-api',
  'screenleft-screentop',
  'server-sent-events',
  'service-worker/simple-service-worker',
  'sourcebuffer',
  'streams/png-transform-stream',
  'streams/simple-random-stream',
  'streams/strings-transform-stream',
  'url-params',
  'view-transitions/mpa-chapter-nav-multiple-transition-types',
  'view-transitions/mpa-chapter-nav-transition-types',
  'web-crypto/derive-bits',
  'web-crypto/derive-key',
  'web-crypto/encrypt-decrypt',
  'web-crypto/export-key',
  'web-crypto/import-key',
  'web-crypto/sign-verify',
  'web-crypto/unwrap-key',
  'web-crypto/wrap-key',
  'web-share',
  'web-speech-api',
  'web-speech-api/audio-track-recognition',];

FixtureSuite? suiteById(String id) {
  for (final suite in knownSuites) {
    if (suite.id == id) return suite;
  }
  return null;
}

/// Root used for downloaded suites: `<repo>/.visual/suites/<id>`.
String suiteRoot(String repoRoot, String id) => '$repoRoot/.visual/suites/$id';

/// Downloads and extracts a pinned suite if it is not present yet.
///
/// Uses `curl` + `tar`, both already required by the repository tooling. A
/// partial download is extracted into a temporary directory and only then
/// renamed, so an interrupted run cannot leave a half suite behind.
Future<String> ensureSuite(
  String repoRoot,
  FixtureSuite suite, {
  bool force = false,
}) async {
  // Prefer the vendored fixtures: runs stay offline and reproducible.
  final vendored = '$repoRoot/debug/engines/visual_comparison/fixtures/${suite.id}';
  if (!force && File('$vendored/.nativa-suite').existsSync()) return vendored;

  final target = suiteRoot(repoRoot, suite.id);
  final marker = File('$target/.nativa-suite');
  if (!force && marker.existsSync()) return target;

  final parent = Directory('$repoRoot/.visual/suites')
    ..createSync(recursive: true);
  final temp = Directory(
    '${parent.path}/.${suite.id}.tmp-${DateTime.now().microsecondsSinceEpoch}',
  )..createSync(recursive: true);
  final archive = File('$target.tar.gz');

  stderr.writeln('fetching ${suite.url}@${suite.commit.substring(0, 8)} ...');
  final curl = await Process.run('curl', [
    '-sSL',
    '--fail',
    '--max-time',
    '180',
    '-o',
    archive.path,
    suite.archiveUrl,
  ]);
  if (curl.exitCode != 0) {
    temp.deleteSync(recursive: true);
    throw StateError('curl failed (${curl.exitCode}): ${curl.stderr}');
  }
  try {
    final tar = await Process.run('tar', [
      '-xzf',
      archive.path,
      '-C',
      temp.path,
      '--strip-components=1',
    ]);
    if (tar.exitCode != 0) {
      throw StateError('tar failed (${tar.exitCode}): ${tar.stderr}');
    }
  } finally {
    if (archive.existsSync()) archive.deleteSync();
  }

  final old = Directory(target);
  if (old.existsSync()) old.deleteSync(recursive: true);
  Directory(temp.path).renameSync(target);
  File(
    '$target/.nativa-suite',
  ).writeAsStringSync('${suite.url}\n${suite.commit}\n${suite.license}\n');
  return target;
}

/// Finds every immediate subdirectory that has an `index.html` entry point.
/// `_project_starter_` is skipped unless [includeStarter] is set.
List<PageSource> discoverPages(
  String suiteRootPath, {
  required String suite,
  bool includeStarter = false,
}) {
  final root = Directory(suiteRootPath);
  if (!root.existsSync()) return const [];
  final pages = <PageSource>[];
  for (final entity in root.listSync(followLinks: false)) {
    if (entity is! Directory) continue;
    final index = File('${entity.path}/index.html');
    if (!index.existsSync()) continue;
    final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (name.startsWith('.') || name == 'node_modules') continue;
    if (!includeStarter && name.startsWith('_')) continue;
    pages.add(
      PageSource(
        id: '$suite/$name',
        suite: suite,
        entry: index.path,
        directory: entity.path,
      ),
    );
  }
  pages.sort((a, b) => a.id.compareTo(b.id));
  return pages;
}

/// Wraps a single HTML file (or a page directory) as a fixture. The judge
/// copies the directory anyway, so the source tree is never modified.
PageSource pageFromPath(String path) {
  final absolute = File(path).absolute.path;
  if (Directory(absolute).existsSync()) {
    final entry = File('$absolute/index.html');
    if (!entry.existsSync()) {
      throw ArgumentError('directory has no index.html: $absolute');
    }
    return PageSource(
      id: _slug(absolute.split(Platform.pathSeparator).last),
      suite: 'local',
      entry: entry.path,
      directory: absolute,
    );
  }
  final file = File(absolute);
  if (!file.existsSync()) throw ArgumentError('not found: $path');
  if (!absolute.toLowerCase().endsWith('.html')) {
    throw ArgumentError('not an .html page: $path');
  }
  return PageSource(
    id: _slug(file.uri.pathSegments.last.replaceAll('.html', '')),
    suite: 'local',
    entry: absolute,
    directory: file.parent.path,
  );
}

/// Discovers pages for a suite using its recursive/include configuration.
List<PageSource> discoverSuitePages(String rootPath, FixtureSuite suite) {
  if (suite.includes.isNotEmpty) {
    final pages = <PageSource>[];
    for (final relative in suite.includes) {
      final dir = '$rootPath/$relative';
      final index = File('$dir/index.html');
      if (!index.existsSync()) continue;
      pages.add(PageSource(
        id: '${suite.id}/$relative',
        suite: suite.id,
        entry: index.path,
        directory: dir,
      ));
    }
    pages.sort((a, b) => a.id.compareTo(b.id));
    return pages;
  }
  if (!suite.recursive) return discoverPages(rootPath, suite: suite.id);
  final root = Directory(rootPath);
  if (!root.existsSync()) return const [];
  final pages = <PageSource>[];
  const skip = {'.git', 'node_modules', 'build', '.dart_tool', '.github'};
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final isIndex = entity.path.endsWith('${Platform.pathSeparator}index.html') ||
        entity.path.endsWith('/index.html');
    if (!isIndex && !(suite.htmlPages && entity.path.endsWith('.html'))) {
      continue;
    }
    final relative = entity.parent.path
        .substring(rootPath.length)
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'^/+'), '');
    if (relative.isEmpty) continue;
    if (relative.split('/').any(skip.contains)) continue;
    if (relative.split('/').any((part) => part.startsWith('_'))) continue;
    final idPath = isIndex
        ? relative
        : relative.replaceFirst(RegExp(r'\.html$'), '');
    pages.add(PageSource(
      id: '${suite.id}/$idPath',
      suite: suite.id,
      entry: entity.path,
      directory: entity.parent.path,
    ));
  }
  pages.sort((a, b) => a.id.compareTo(b.id));
  if (suite.maxPages > 0 && pages.length > suite.maxPages) {
    return pages.take(suite.maxPages).toList(growable: false);
  }
  return pages;
}

String _slug(String value) {
  final cleaned = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9._-]+'), '-');
  return cleaned.isEmpty ? 'page' : cleaned;
}
