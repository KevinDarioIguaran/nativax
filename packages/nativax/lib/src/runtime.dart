import 'package:flutter/services.dart';
import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_dom/nativa_dom.dart' as dom;
import 'package:nativa_dom_bindings/nativa_dom_bindings.dart';
import 'package:nativa_html/nativa_html.dart';
import 'package:nativa_js/nativa_js.dart';

import 'modules.dart';
import 'resources.dart';
import 'workers.dart';

export 'package:nativa_dom_bindings/nativa_dom_bindings.dart'
    show
        DeniedNetwork,
        IoNetwork,
        NativaXNetwork,
        NetworkRequest,
        NetworkResponse,
        NetworkSocket,
        PlatformServices;

int _fontSourceRank(String url) {
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
  if (path.endsWith('.ttf') || path.endsWith('.otf')) return 0;
  if (path.endsWith('.woff2') || path.endsWith('.woff')) return 2;
  return 1;
}

class NativaXRuntimeConfig {
  const NativaXRuntimeConfig({
    this.engine = defaultEngineConfig,
    this.timers = const TimerLimits(),
    this.resources = const NativaXDenyAllResources(),
    this.storage,
    this.appHandlers = const {},
    this.onScriptError,
    this.onConsole,
    this.onDiagnostic,
    this.onNavigate,
    this.onSubmit,
    this.onThemeMode,
    this.documentUrl = 'app://local/index.html',
    this.devicePixelRatio,
    this.network = const DeniedNetwork(),
    this.services,
    this.threadedWorkers = true,
    this.engineFactory,
  });

  /// Runs dedicated workers on their own isolates (threads), as browsers do.
  /// When false they share the UI isolate (simpler to debug, no parallelism).
  final bool threadedWorkers;

  /// Like browsers' slow-script threshold: one task (including its
  /// microtasks) may run for up to 10 s before it is interrupted.
  static const defaultEngineConfig = JavaScriptEngineConfig(
    executionBudget: Duration(seconds: 10),
    maxJobsPerDrain: 1000000,
  );

  /// The document's URL (`location.href`); relative URLs and same-document
  /// `#fragment` navigation resolve against it.
  final String documentUrl;

  /// Value returned by `window.devicePixelRatio`; when null, the Flutter
  /// [MediaQuery] ratio is used. Capping it is useful for heavy canvases on
  /// HiDPI screens because it reduces the backing-store size.
  final double? devicePixelRatio;

  /// Network policy for `fetch`, `XMLHttpRequest` and `WebSocket`. Denied by
  /// default; pass an [IoNetwork] with an allowlist to enable requests.
  final NativaXNetwork network;

  /// Clipboard, vibration, alerts and external navigation. When null the
  /// view supplies Flutter-backed defaults.
  final PlatformServices? services;

  final JavaScriptEngineConfig engine;

  /// Optional backend factory. Defaults to QuickJS-ng; `V8Engine` can be
  /// injected for the native V8 prototype.
  final JavaScriptEngine Function(JavaScriptEngineConfig config)? engineFactory;
  final TimerLimits timers;
  final NativaXResourceLoader resources;
  final KeyValueStorage? storage;
  final Map<String, AppHandler> appHandlers;
  final void Function(Object error)? onScriptError;
  final void Function(ConsoleMessage message)? onConsole;
  final void Function(String message)? onDiagnostic;
  final void Function(String href, dom.Element anchor)? onNavigate;
  final void Function(dom.Element form)? onSubmit;

  /// Allows scripts to request a theme mode (`nativax.theme.setMode`).
  final bool Function(ThemeModeRequest mode)? onThemeMode;
}

/// Owns the parsed document, the style engine and the JavaScript engine for
/// one document. Create it with [NativaXRuntime.create] and dispose it when
/// the view is unmounted.
class NativaXRuntime {
  NativaXRuntime._({
    required this.document,
    required this.styleEngine,
    required this.engine,
    required this.bindings,
    required this.timers,
    required this.config,
    required this.parseErrors,
    required Map<dom.Element, StyleSheet> styleSheets,
    required List<StyleSheet> linkedSheets,
  }) : _styleSheets = styleSheets,
       _linkedSheets = linkedSheets {
    document.addMutationListener(_onStyleMutation);
  }

  final dom.Document document;
  final StyleEngine styleEngine;
  final JavaScriptEngine engine;
  final DomBindings bindings;
  final TimerHost timers;
  final NativaXRuntimeConfig config;
  final List<HtmlParseError> parseErrors;
  final Map<dom.Element, StyleSheet> _styleSheets;
  final List<StyleSheet> _linkedSheets;
  final List<Object> scriptErrors = [];
  bool _disposed = false;

  bool get isDisposed => _disposed;

  /// Parses [source], applies `<style>`/`<link rel=stylesheet>` sheets and
  /// runs `<script>` elements in document order.
  static Future<NativaXRuntime> create({
    required String source,
    NativaXRuntimeConfig config = const NativaXRuntimeConfig(),
    HostEnvironment? environment,
    String? documentUrl,
    PlatformServices? platformServices,
  }) async {
    final parsed = HtmlParser().parseDocument(source);
    final document = parsed.value;
    final env =
        environment ??
        StaticEnvironment(
          media: const MediaContext(width: 800, height: 600),
          localStorage: config.storage,
        );
    final styleEngine = StyleEngine(document: document, media: env.media);
    final styleSheets = <dom.Element, StyleSheet>{};
    final linkedSheets = <StyleSheet>[];
    final linkedBases = <StyleSheet, Uri>{};
    final loadedFonts = <String>{};
    final documentBase = Uri.parse(documentUrl ?? config.documentUrl);

    Future<void> loadFontFaces(
      StyleSheet sheet,
      Uri base, {
      Set<String>? only,
    }) async {
      final faceSources = <FontFaceRule, List<String>>{};
      final requests = <String>[];
      for (final face in sheet.fontFaces) {
        final iconFamily =
            face.family.toLowerCase().contains('font awesome') ||
            face.family.toLowerCase().contains('fontawesome') ||
            face.family.toLowerCase().contains('material icons');
        if (!iconFamily && only != null && !only.contains(face.family)) {
          continue;
        }
        final urls = <String>[];
        for (final source in face.sources) {
          final resolved = base.resolve(source).toString();
          if (loadedFonts.add(resolved)) requests.add(resolved);
          urls.add(resolved);
          // Flutter cannot load WOFF/WOFF2. Some sites ship only the WOFF2
          // URL in CSS but keep an SFNT fallback next to it; probe for it
          // without changing the stylesheet.
          final lower = resolved.toLowerCase();
          if (lower.endsWith('.woff2') || lower.endsWith('.woff')) {
            final stem = resolved.substring(0, resolved.lastIndexOf('.'));
            for (final ext in const ['.ttf', '.otf']) {
              final fallback = '$stem$ext';
              if (loadedFonts.add(fallback)) requests.add(fallback);
              urls.add(fallback);
            }
          }
        }
        if (urls.isNotEmpty) faceSources[face] = urls;
      }
      final loaded = <String, Uint8List?>{};
      final data = await Future.wait([
        for (final url in requests) config.resources.loadBytes(url),
      ]);
      for (var i = 0; i < requests.length; i++) {
        loaded[requests[i]] = data[i];
      }
      final families = <String, FontLoader>{};
      for (final entry in faceSources.entries) {
        // Flutter's FontLoader accepts SFNT (TTF/OTF), not WOFF2. Prefer the
        // uncompressed fallback when a stylesheet provides both.
        final candidates = entry.value.toList()
          ..sort((a, b) => _fontSourceRank(a).compareTo(_fontSourceRank(b)));
        Uint8List? bytes;
        String? usedUrl;
        for (final url in candidates) {
          final candidate = loaded[url];
          if (candidate != null && candidate.isNotEmpty) {
            bytes = candidate;
            usedUrl = url;
            break;
          }
        }
        if (bytes == null) continue;
        final face = entry.key;
        if (usedUrl != null && usedUrl.toLowerCase().contains('.woff')) {
          config.onDiagnostic?.call(
            'font "${face.family}" ($usedUrl): WOFF/WOFF2 is not supported '
            'by Flutter FontLoader; provide TTF/OTF',
          );
          continue;
        }
        try {
          families
              .putIfAbsent(face.family, () => FontLoader(face.family))
              .addFont(
                Future<ByteData>.value(
                  ByteData.sublistView(Uint8List.fromList(bytes)),
                ),
              );
        } catch (error) {
          config.onDiagnostic?.call(
            'font "${face.family}" ($usedUrl) failed: $error',
          );
        }
      }
      for (final entry in families.entries) {
        try {
          await entry.value.load();
        } catch (error) {
          config.onDiagnostic?.call('font "${entry.key}" failed: $error');
        }
      }
    }

    StyleSheet addSheet(String text, String origin, {Uri? base}) {
      final sheet = StyleSheet.parse(text, baseUrl: base ?? documentBase);
      for (final warning in sheet.warnings) {
        config.onDiagnostic?.call('$origin: ${warning.message}');
      }
      return sheet;
    }

    for (final style in document.querySelectorAll('style')) {
      styleSheets[style] = addSheet(style.textContent, '<style>');
    }
    for (final link in document.querySelectorAll('link')) {
      final rel = (link.getAttribute('rel') ?? '').toLowerCase().split(' ');
      if (!rel.contains('stylesheet')) continue;
      final href = link.getAttribute('href');
      if (href == null || href.isEmpty) continue;
      try {
        final css = await config.resources.load(href);
        if (css == null) {
          config.onDiagnostic?.call(
            'stylesheet "$href" was not loaded (resource denied)',
          );
        } else {
          final base = documentBase.resolve(href);
          final sheet = addSheet(css, href, base: base);
          linkedSheets.add(sheet);
          linkedBases[sheet] = base;
        }
      } catch (error) {
        config.onDiagnostic?.call('stylesheet "$href" failed: $error');
      }
    }
    styleEngine.authorSheets = [...styleSheets.values, ...linkedSheets];

    final usedFontFamilies = <String>{};
    for (final sheet in [...styleSheets.values, ...linkedSheets]) {
      _collectFontFamilies(sheet.rules, usedFontFamilies);
    }
    for (final entry in styleSheets.entries) {
      await loadFontFaces(entry.value, documentBase, only: usedFontFamilies);
    }
    for (final sheet in linkedSheets) {
      await loadFontFaces(
        sheet,
        linkedBases[sheet] ?? documentBase,
        only: usedFontFamilies,
      );
    }

    final engine =
        config.engineFactory?.call(config.engine) ??
        QuickJsEngine(config.engine);
    final services =
        platformServices ?? config.services ?? const PlatformServices();
    // Preludes that need the raw host bridge must be installed before the
    // bridge is removed from script globals.
    final timers = TimerHost(
      engine,
      limits: config.timers,
      onError: config.onScriptError,
    );
    if (config.onConsole != null) {
      installConsole(engine, config.onConsole!);
    } else {
      // `console` exists in every browser context, even when the host does not
      // care about its output. Library code (wasm-bindgen, for one) calls
      // console.warn on recoverable paths and must not fail there.
      installConsole(engine, (_) {});
    }
    // Listener exceptions are reported, never fatal (as in a browser).
    document.onListenerError = (error, _) => config.onScriptError?.call(error);
    document.onNavigate = config.onNavigate;
    document.onSubmit = config.onSubmit;
    final pageUrl = Uri.parse(documentUrl ?? config.documentUrl);
    // Same-origin requests are the app's own files (wasm, audio, models).
    final network = LocalResourceNetwork(
      resources: config.resources,
      documentUrl: pageUrl,
      network: config.network,
    );
    final WorkerLauncher launcher = config.threadedWorkers
        ? IsolateWorkerLauncher(
            loadScript: (url) =>
                config.resources.load(resourceKey(Uri.parse(url), pageUrl)),
            network: network,
          )
        : InProcessWorkerLauncher(network: network);
    final bindings = DomBindings(
      messaging: RouterMessaging.local(launcher: launcher),
      engine: engine,
      document: document,
      environment: env,
      appHandlers: config.appHandlers,
      onScriptError: config.onScriptError,
      styleEngine: styleEngine,
      documentUrl: documentUrl ?? config.documentUrl,
      network: network,
      services: services,
    )..install();
    bindings.harden();

    final modules = DocumentModules(
      resources: config.resources,
      baseUrl: pageUrl,
      onModuleError: (e) => config.onScriptError?.call(e),
    );
    engine.moduleHost = modules;
    // Module scripts are deferred: they run after the classic scripts, in
    // document order (HTML §4.12.1).
    final moduleScripts = <dom.Element>[];
    for (final script in document.querySelectorAll('script')) {
      final type = (script.getAttribute('type') ?? '').toLowerCase();
      if (type == 'module') {
        moduleScripts.add(script);
        continue;
      }
      if (type.isNotEmpty &&
          type != 'text/javascript' &&
          type != 'application/javascript' &&
          type != 'text/ecmascript') {
        continue;
      }
      final src = script.getAttribute('src');
      try {
        if (src != null && src.isNotEmpty) {
          final code = await config.resources.load(src);
          if (code == null) {
            config.onDiagnostic?.call(
              'script "$src" was not loaded (resource denied)',
            );
            continue;
          }
          engine.evaluate(code, filename: src);
        } else {
          final code = script.textContent;
          if (code.trim().isNotEmpty) {
            engine.evaluate(code, filename: '<script>');
          }
        }
      } catch (error) {
        // A browser stops at the failing script but keeps the document alive.
        config.onScriptError?.call(error);
      }
    }

    for (final script in moduleScripts) {
      final src = script.getAttribute('src');
      try {
        if (src != null && src.isNotEmpty) {
          final url = pageUrl.resolve(src).toString();
          await modules.prefetch(url);
          final code = modules.source(url);
          if (code == null) {
            config.onDiagnostic?.call(
              'module "$src" was not loaded (resource denied)',
            );
            continue;
          }
          engine.evaluateModule(code, url: url);
        } else {
          final code = script.textContent;
          if (code.trim().isEmpty) continue;
          // Inline modules take the document's URL as import.meta.url.
          final url = pageUrl.toString();
          await modules.prefetch(url, source: code);
          engine.evaluateModule(code, url: url);
        }
      } catch (error) {
        config.onScriptError?.call(error);
      }
    }

    bindings.documentReady();
    bindings.readyState = 'interactive';
    document.dispatchEvent(dom.Event('readystatechange')..isTrusted = true);
    document.dispatchEvent(
      dom.Event('DOMContentLoaded', bubbles: true)..isTrusted = true,
    );
    bindings.readyState = 'complete';
    document.dispatchEvent(dom.Event('readystatechange')..isTrusted = true);
    bindings.window.dispatchEvent(dom.Event('load')..isTrusted = true);
    bindings.window.dispatchEvent(dom.Event('pageshow')..isTrusted = true);

    return NativaXRuntime._(
      document: document,
      styleEngine: styleEngine,
      engine: engine,
      bindings: bindings,
      timers: timers,
      config: config,
      parseErrors: parsed.errors,
      styleSheets: styleSheets,
      linkedSheets: linkedSheets,
    );
  }

  bool _containsStyle(dom.Node node) {
    if (node is dom.Element && node.localName == 'style') return true;
    for (final child in node.childNodes) {
      if (_containsStyle(child)) return true;
    }
    return false;
  }

  void _onStyleMutation(dom.MutationRecord record) {
    if (_disposed) return;
    var relevant = false;
    if (record.type == dom.MutationType.childList) {
      relevant =
          _containsStyle(record.target) ||
          record.addedNodes.any(_containsStyle) ||
          record.removedNodes.any(_containsStyle);
    } else if (record.type == dom.MutationType.characterData) {
      relevant = record.target.parentElement?.localName == 'style';
    }
    if (!relevant) return;
    _refreshStyleSheets();
  }

  /// Reparses `<style>` elements after script/Shadow-DOM UI injects or edits
  /// them. Without this, CSSOM-like manipulations and framework UI would be
  /// parsed once at document creation and never take effect.
  void _refreshStyleSheets() {
    final current = document.querySelectorAll('style');
    final live = current.toSet();
    _styleSheets.removeWhere((element, _) => !live.contains(element));
    for (final style in current) {
      _styleSheets[style] = StyleSheet.parse(style.textContent);
    }
    styleEngine.authorSheets = [..._styleSheets.values, ..._linkedSheets];
  }

  /// Marks the bindings environment as changed (resize/theme/locale).
  void environmentChanged() => bindings.environmentChanged();

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    document.removeMutationListener(_onStyleMutation);
    timers.dispose();
    bindings.dispose();
    engine.dispose();
    document.dispose();
  }
}

void _collectFontFamilies(List<CssRule> rules, Set<String> out) {
  for (final rule in rules) {
    switch (rule) {
      case StyleRule():
        for (final declaration in rule.declarations) {
          if (declaration.property == 'font-family' &&
              declaration.value is FontFamilyValue) {
            for (final family
                in (declaration.value as FontFamilyValue).families) {
              final name = family.trim().replaceAll(
                RegExp(r'''^["']|["']$'''),
                '',
              );
              if (name.isEmpty) continue;
              final generic = const {
                'serif',
                'sans-serif',
                'monospace',
                'cursive',
                'fantasy',
                'system-ui',
                'ui-serif',
                'ui-sans-serif',
                'ui-monospace',
                'inherit',
                'initial',
                'unset',
                'revert',
                'revert-layer',
              }.contains(name.toLowerCase());
              if (!generic) out.add(name);
            }
          }
        }
      case MediaRule():
        _collectFontFamilies(rule.rules, out);
      case KeyframesRule():
        for (final frame in rule.frames) {
          for (final declaration in frame.declarations) {
            if (declaration.property == 'font-family' &&
                declaration.value is FontFamilyValue) {
              for (final family
                  in (declaration.value as FontFamilyValue).families) {
                final name = family.trim().replaceAll(
                  RegExp(r'''^["']|["']$'''),
                  '',
                );
                if (name.isNotEmpty) out.add(name);
              }
            }
          }
        }
      case FontFaceRule():
        break;
    }
  }
}
