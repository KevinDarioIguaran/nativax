import 'dart:async';

import 'package:nativa_js/nativa_js.dart';

/// ES module graph of one document or worker: resolves specifiers against
/// the importing module and serves sources that [prefetch] loaded through
/// [load], because modules are linked synchronously.
class ModuleGraph implements ModuleHost {
  ModuleGraph({required this.load, this.onModuleError, Map<String, String>? sources})
      : _sources = sources ?? {};

  /// Fetches a module's source by absolute URL (null when unavailable).
  final Future<String?> Function(String url) load;
  final void Function(JavaScriptException error)? onModuleError;

  final Map<String, String> _sources;

  /// Every source loaded so far, by URL (to hand a worker its graph).
  Map<String, String> get sources => Map.unmodifiable(_sources);
  final Map<String, Future<void>> _loading = {};

  static final _static = RegExp(
    r'''(?:^|[^.\w$])(?:import|export)\s*(?:[\w*{}\s,$]*?\s*from\s*)?(["'])([^"'\n]+)\1''',
  );
  static final _dynamic = RegExp(r'''(?:^|[^.\w$])import\s*\(\s*(["'])([^"'\n]+)\1\s*\)''');

  static bool _isBare(String specifier) =>
      !(specifier.startsWith('./') ||
          specifier.startsWith('../') ||
          specifier.startsWith('/') ||
          RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(specifier));

  /// Specifiers imported by [source] (static imports, re-exports and
  /// literal dynamic imports). A lexical scan: false positives only cost a
  /// failed prefetch.
  static Iterable<String> importsOf(String source) sync* {
    for (final m in _static.allMatches(source)) {
      yield m.group(2)!;
    }
    for (final m in _dynamic.allMatches(source)) {
      yield m.group(2)!;
    }
  }

  /// Loads [url] and, transitively, everything it imports. Pass [source] for
  /// inline module scripts. Missing modules are skipped here and reported by
  /// the engine when linking.
  Future<void> prefetch(String url, {String? source}) {
    if (source != null) {
      _sources[url] = source;
      return _prefetchImports(url, source);
    }
    return _loading.putIfAbsent(url, () async {
      final text = await load(url);
      if (text == null) return;
      _sources[url] = text;
      await _prefetchImports(url, text);
    });
  }

  Future<void> _prefetchImports(String url, String source) {
    final pending = <Future<void>>[];
    for (final spec in importsOf(source).toSet()) {
      if (_isBare(spec)) continue;
      final String target;
      try {
        target = Uri.parse(url).resolve(spec).toString();
      } on FormatException {
        continue;
      }
      pending.add(prefetch(target));
    }
    return Future.wait(pending);
  }

  @override
  String resolve(String base, String specifier) {
    if (_isBare(specifier)) {
      throw JavaScriptHostError(
          'TypeError', 'Failed to resolve module specifier "$specifier". Relative references must start with "/", "./" or "../".');
    }
    try {
      return Uri.parse(base).resolve(specifier).toString();
    } on FormatException {
      throw JavaScriptHostError('TypeError', 'Invalid module specifier "$specifier"');
    }
  }

  @override
  String? source(String url) => _sources[url];

  @override
  void onError(JavaScriptException error) => onModuleError?.call(error);
}

