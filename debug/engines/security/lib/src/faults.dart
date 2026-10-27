/// Deliberate vulnerabilities (mutants) for the security suite's own
/// accuracy audit.
///
/// Every case builds its engine, bindings, parser and storage through the
/// helpers below. With no fault active they return the real production
/// objects unchanged. Under [withFault] they return a weakened version that
/// has one known vulnerability, so `evaluate` can measure which faults the
/// suite detects. Faults never run outside `bin/security.dart evaluate` and
/// the tests.
library;

import 'dart:async';
import 'dart:io';

import 'package:nativa_dom_bindings/nativa_dom_bindings.dart';
import 'package:nativa_html/nativa_html.dart';
import 'package:nativa_js/nativa_js.dart';

enum SecurityFault {
  hostGlobal('A host object (`process`) is exposed on globalThis', [
    'engine.host_globals',
    'matrix.global.process',
  ]),
  // internal.callback_globals checks the __nx_* callbacks, which are private
  // with or without harden(); it is not a detector of this fault.
  rawBridge('harden() is skipped: the raw __nx bridge stays reachable', [
    'bridge.raw_host_hardened',
  ]),
  innerHtmlExecutes(
    'innerHTML runs <script> bodies and on* handler attributes',
    // Matrix payloads 8 and 10 use javascript: URLs in href/data, a vector
    // this fault does not open.
    [
      'xss.inner_html_does_not_execute',
      'matrix.inner_html.1',
      'matrix.inner_html.2',
      'matrix.inner_html.3',
      'matrix.inner_html.4',
      'matrix.inner_html.5',
      'matrix.inner_html.6',
      'matrix.inner_html.7',
      'matrix.inner_html.9',
    ],
  ),
  javascriptUrl('Clicking an <a href="javascript:…"> evaluates the URL', [
    'xss.javascript_url_not_executed',
    'matrix.url.1',
  ]),
  sharedGlobals(
    'Every new engine is the same runtime (globals shared across pages)',
    ['sandbox.engine_isolation'],
  ),
  microtaskUnbounded('The per-drain microtask limit is disabled', [
    'limits.microtask_limit',
  ]),
  parserLimitIgnored('HTML parser input limits are ignored', [
    'limits.parser_input_limit',
  ]),
  quotaIgnored('localStorage quota is not enforced', ['storage.quota']),
  disposeIgnored('dispose() leaves the engine usable', [
    'lifecycle.disposed_engine_rejects_calls',
  ]);

  const SecurityFault(this.description, this.detectors);

  final String description;

  /// Case ids whose contract this fault violates (`*` matches a suffix).
  /// The fault counts as detected when at least one of them fails.
  final List<String> detectors;

  bool expects(String caseId) => detectors.any(
    (d) => d.endsWith('*')
        ? caseId.startsWith(d.substring(0, d.length - 1))
        : caseId == d,
  );
}

const Object _key = #nxSecurityFault;
const Object _sharedKey = #nxSecurityFaultShared;

SecurityFault? get activeFault => Zone.current[_key] as SecurityFault?;

const Object _keptKey = #nxSecurityFaultKept;

/// Runs [body] with [fault] active for every helper call inside it, then
/// disposes the engines a fault kept alive (shared or dispose-ignored).
Future<T> withFault<T>(SecurityFault? fault, Future<T> Function() body) async {
  final shared = <JavaScriptEngine>[];
  final kept = <JavaScriptEngine>[];
  try {
    return await runZoned(
      body,
      zoneValues: {_key: fault, _sharedKey: shared, _keptKey: kept},
    );
  } finally {
    for (final engine in [...shared, ...kept]) {
      if (!engine.isDisposed) engine.dispose();
    }
  }
}

JavaScriptEngine newEngine([
  JavaScriptEngineConfig config = const JavaScriptEngineConfig(),
]) {
  switch (activeFault) {
    case SecurityFault.microtaskUnbounded:
      return JscEngine(
        JavaScriptEngineConfig(
          memoryLimitBytes: config.memoryLimitBytes,
          maxStackBytes: config.maxStackBytes,
          executionBudget: config.executionBudget,
          maxJobsPerDrain: 1 << 30,
          microtaskSlice: config.microtaskSlice,
        ),
      );
    case SecurityFault.sharedGlobals:
      final shared = Zone.current[_sharedKey] as List<JavaScriptEngine>;
      if (shared.isEmpty || shared.first.isDisposed) {
        shared
          ..clear()
          ..add(JscEngine(config));
      }
      return _Forward(shared.first, refCounted: true);
    case SecurityFault.disposeIgnored:
      final engine = JscEngine(config);
      (Zone.current[_keptKey] as List<JavaScriptEngine>).add(engine);
      return _Forward(engine, ignoreDispose: true);
    case SecurityFault.hostGlobal:
      return JscEngine(config)
        ..evaluate('globalThis.process = { env: {}, exit() {} };');
    default:
      // NATIVAX_ENGINE picks the engine (jsc, the only engine).
      return createJavaScriptEngineNamed(
        Platform.environment['NATIVAX_ENGINE'] ?? 'jsc',
        config,
      );
  }
}

/// Called after `DomBindings.install()`; patches the page under DOM faults.
void applyDomFault(JavaScriptEngine engine) {
  switch (activeFault) {
    case SecurityFault.innerHtmlExecutes:
      engine.evaluate(r'''
        (() => {
          let p = Object.getPrototypeOf(document.body), d;
          while (p && !(d = Object.getOwnPropertyDescriptor(p, 'innerHTML'))) p = Object.getPrototypeOf(p);
          Object.defineProperty(p, 'innerHTML', { configurable: true, get: d.get, set(html) {
            d.set.call(this, html);
            const run = (code) => { try { (0, eval)(code); } catch (e) {} };
            for (const m of String(html).matchAll(/<script[^>]*>([\s\S]*?)<\/script>/gi)) run(m[1]);
            for (const m of String(html).matchAll(/\son\w+="([^"]*)"/gi)) run(m[1]);
          }});
        })();
      ''');
    case SecurityFault.javascriptUrl:
      engine.evaluate(r'''
        (() => {
          let p = Object.getPrototypeOf(document.createElement('a'));
          while (p && !Object.getOwnPropertyDescriptor(p, 'click')) p = Object.getPrototypeOf(p);
          const click = p.click;
          p.click = function () {
            const href = this.getAttribute && this.getAttribute('href');
            if (href && /^javascript:/i.test(href)) {
              try { (0, eval)(decodeURIComponent(href.slice(11))); } catch (e) {}
            }
            return click.call(this);
          };
        })();
      ''');
    default:
      break;
  }
}

/// `bindings.harden()`, skipped under [SecurityFault.rawBridge].
void hardenBindings(DomBindings bindings) {
  if (activeFault != SecurityFault.rawBridge) bindings.harden();
}

HtmlParser newParser({HtmlParserLimits? limits}) =>
    activeFault == SecurityFault.parserLimitIgnored || limits == null
    ? HtmlParser()
    : HtmlParser(limits: limits);

MemoryStorage newStorage({required int quota}) =>
    activeFault == SecurityFault.quotaIgnored
    ? MemoryStorage()
    : MemoryStorage(quota: quota);

class _Forward implements JavaScriptEngine {
  _Forward(this._inner, {this.refCounted = false, this.ignoreDispose = false}) {
    if (refCounted) _refs[_inner] = (_refs[_inner] ?? 0) + 1;
  }

  static final Map<JavaScriptEngine, int> _refs = {};
  final JavaScriptEngine _inner;
  final bool refCounted;
  final bool ignoreDispose;
  bool _released = false;

  @override
  bool get isDisposed => !ignoreDispose && (_released || _inner.isDisposed);

  @override
  Object? evaluate(String source, {String filename = '<nativax>'}) =>
      _inner.evaluate(source, filename: filename);

  @override
  void evaluateModule(String source, {required String url}) =>
      _inner.evaluateModule(source, url: url);

  @override
  ModuleHost? get moduleHost => _inner.moduleHost;

  @override
  set moduleHost(ModuleHost? host) => _inner.moduleHost = host;

  @override
  Object? callGlobal(String functionName, [Object? argument]) =>
      _inner.callGlobal(functionName, argument);

  @override
  void registerHostFunction(String name, HostFunction function) =>
      _inner.registerHostFunction(name, function);

  @override
  int drainMicrotasks() => _inner.drainMicrotasks();

  @override
  bool get hasPendingMicrotasks => _inner.hasPendingMicrotasks;

  @override
  int get memoryUsed => _inner.memoryUsed;

  @override
  void collectGarbage() => _inner.collectGarbage();

  @override
  void dispose() {
    if (ignoreDispose || _released) return;
    _released = true;
    if (!refCounted) return _inner.dispose();
    final left = (_refs[_inner] ?? 1) - 1;
    if (left <= 0) {
      _refs.remove(_inner);
      _inner.dispose();
    } else {
      _refs[_inner] = left;
    }
  }
}
