import 'dart:convert';

import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_dom/nativa_dom.dart';
import 'package:nativa_dom_bindings/nativa_dom_bindings.dart';
import 'package:nativa_html/nativa_html.dart';
import 'package:nativa_js/nativa_js.dart';

import 'model.dart';
import 'matrix_cases.dart';

class _Harness {
  _Harness({KeyValueStorage? storage, bool harden = false}) {
    document = HtmlParser()
        .parseDocument('<!doctype html><html><body></body></html>')
        .value;
    engine = JscEngine();
    bindings = DomBindings(
      engine: engine,
      document: document,
      environment: StaticEnvironment(
        media: const MediaContext(width: 800, height: 600),
        languages: const ['en-US'],
        platform: 'linux',
        localStorage: storage,
      ),
    )..install();
    if (harden) bindings.harden();
  }

  late final Document document;
  late final JscEngine engine;
  late final DomBindings bindings;

  void dispose() {
    bindings.dispose();
    engine.dispose();
    document.dispose();
  }
}

SecurityCheck _pass(
  String expected,
  String observed, {
  List<String> evidence = const [],
  String remediation = '',
}) => SecurityCheck(
  status: SecurityStatus.pass,
  expected: expected,
  observed: observed,
  evidence: evidence,
  remediation: remediation,
);

SecurityCheck _fail(
  String expected,
  String observed, {
  List<String> evidence = const [],
  String remediation = '',
}) => SecurityCheck(
  status: SecurityStatus.fail,
  expected: expected,
  observed: observed,
  evidence: evidence,
  remediation: remediation,
);

List<SecurityCase> securityCases() => [
  SecurityCase(
    id: 'engine.host_globals',
    category: 'sandbox',
    severity: 'critical',
    description:
        'JS must not see OS, filesystem, process, network or Dart globals.',
    run: () async {
      final engine = JscEngine();
      try {
        final globals = [
          'process',
          'require',
          'File',
          'Directory',
          'Platform',
          'fetch',
          'XMLHttpRequest',
          'WebSocket',
          'Deno',
          'Bun',
          'dart',
          '__nx_host',
        ];
        final result = engine.evaluate(
          'JSON.stringify(${jsonEncode(globals)}.map((n) => typeof globalThis[n]))',
        );
        final types = (jsonDecode(result as String) as List).cast<String>();
        final exposed = [
          for (var i = 0; i < globals.length; i++)
            if (types[i] != 'undefined') '${globals[i]}=${types[i]}',
        ];
        return exposed.isEmpty
            ? _pass('all host globals undefined', 'none exposed')
            : _fail(
                'all host globals undefined',
                exposed.join(', '),
                evidence: exposed,
              );
      } finally {
        engine.dispose();
      }
    },
  ),
  SecurityCase(
    id: 'bridge.raw_host_hardened',
    category: 'bridge',
    severity: 'high',
    description:
        'Production runtime must not leave the raw __nx.host bridge reachable.',
    run: () async {
      final h = _Harness(harden: true);
      try {
        final type = h.engine.evaluate('typeof __nx');
        return type == 'undefined'
            ? _pass(
                '__nx undefined after harden',
                '$type',
                evidence: ['DOM/console/timer preludes keep working'],
              )
            : _fail('__nx undefined after harden', '$type');
      } finally {
        h.dispose();
      }
    },
  ),
  SecurityCase(
    id: 'events.programmatic_click_not_trusted',
    category: 'events',
    severity: 'high',
    description:
        'Script-triggered click must not be trusted as a user gesture.',
    run: () async {
      final doc = Document();
      final button = doc.createElement('button');
      doc.appendChild(button);
      bool? trusted;
      button.addEventListener(
        'click',
        CallbackListener((event) => trusted = event.isTrusted),
      );
      button.click();
      final scriptTrusted = trusted;
      button.click(trusted: true);
      final hostTrusted = trusted;
      doc.dispose();
      final ok = scriptTrusted == false && hostTrusted == true;
      return ok
          ? _pass(
              'click() false; trusted gesture true',
              'script=$scriptTrusted host=$hostTrusted',
            )
          : _fail(
              'click() false; trusted gesture true',
              'script=$scriptTrusted host=$hostTrusted',
              remediation: 'Keep host gestures separate from DOM click()',
            );
    },
  ),
  SecurityCase(
    id: 'events.programmatic_submit_not_trusted',
    category: 'events',
    severity: 'high',
    description: 'requestSubmit() from script must not be marked trusted.',
    run: () async {
      final doc = Document();
      final form = doc.createElement('form');
      doc.appendChild(form);
      bool? trusted;
      form.addEventListener(
        'submit',
        CallbackListener((event) => trusted = event.isTrusted),
      );
      form.requestSubmit();
      final scriptTrusted = trusted;
      form.requestSubmit(trusted: true);
      final hostTrusted = trusted;
      doc.dispose();
      return scriptTrusted == false && hostTrusted == true
          ? _pass(
              'submit() false; trusted gesture true',
              'script=$scriptTrusted host=$hostTrusted',
            )
          : _fail(
              'submit() false; trusted gesture true',
              'script=$scriptTrusted host=$hostTrusted',
            );
    },
  ),
  SecurityCase(
    id: 'xss.inner_html_does_not_execute',
    category: 'xss',
    severity: 'critical',
    description:
        'Scripts and event handlers inserted via innerHTML must not execute.',
    run: () async {
      final h = _Harness();
      try {
        h.engine.evaluate('''
              globalThis.pwned = 0;
              document.body.innerHTML =
                '<div id="x">safe</div>' +
                '<script>globalThis.pwned = 1<\\/script>' +
                '<img src="x" onerror="globalThis.pwned = 2">';
            ''');
        final pwned = h.engine.evaluate('globalThis.pwned');
        final text = h.engine.evaluate(
          'document.getElementById("x").textContent',
        );
        return pwned == 0 && text == 'safe'
            ? _pass('pwned=0, text=safe', 'pwned=$pwned text=$text')
            : _fail('pwned=0, text=safe', 'pwned=$pwned text=$text');
      } finally {
        h.dispose();
      }
    },
  ),
  SecurityCase(
    id: 'xss.javascript_url_not_executed',
    category: 'xss',
    severity: 'high',
    description: 'javascript: URLs must not execute inside NativaX.',
    run: () async {
      final h = _Harness();
      try {
        String? navigated;
        h.document.onNavigate = (href, anchor) => navigated = href;
        h.engine.evaluate('''
              globalThis.pwned = 0;
              const a = document.createElement('a');
              a.id = 'a';
              a.href = 'javascript:globalThis.pwned=1';
              document.body.appendChild(a);
            ''');
        h.engine.evaluate('document.getElementById("a").click()');
        final pwned = h.engine.evaluate('globalThis.pwned');
        return pwned == 0
            ? _pass(
                'pwned=0',
                'pwned=$pwned; navigate=$navigated',
                evidence: ['The host must still validate navigation URLs'],
              )
            : _fail('pwned=0', 'pwned=$pwned');
      } finally {
        h.dispose();
      }
    },
  ),
  SecurityCase(
    id: 'bridge.malformed_ids_are_contained',
    category: 'bridge',
    severity: 'high',
    description:
        'Forged host ids must fail cleanly without corrupting the runtime.',
    run: () async {
      final h = _Harness();
      try {
        final result = h.engine.evaluate('''
              let caught = false;
              try { __nx.host('node.get', 999999, 'nodeType'); }
              catch (e) { caught = true; }
              document.body.textContent = caught ? 'alive' : 'missing';
              caught;
            ''');
        final text = h.engine.evaluate('document.body.textContent');
        h.engine.evaluate('1 + 1');
        return result == true && text == 'alive'
            ? _pass('error caught, runtime alive', 'caught=$result text=$text')
            : _fail('error caught, runtime alive', 'caught=$result text=$text');
      } finally {
        h.dispose();
      }
    },
  ),
  SecurityCase(
    id: 'sandbox.engine_isolation',
    category: 'isolation',
    severity: 'critical',
    description: 'Two engines must not share JavaScript globals.',
    run: () async {
      final a = JscEngine();
      final b = JscEngine();
      try {
        a.evaluate('globalThis.leak = 42');
        final seen = b.evaluate('typeof globalThis.leak');
        return seen == 'undefined'
            ? _pass('separate globals', '$seen')
            : _fail('separate globals', '$seen');
      } finally {
        a.dispose();
        b.dispose();
      }
    },
  ),
  SecurityCase(
    id: 'limits.infinite_loop_interrupted',
    category: 'dos',
    severity: 'high',
    description:
        'An infinite JS loop must be interrupted by the execution budget.',
    run: () async {
      final engine = JscEngine(
        const JavaScriptEngineConfig(
          executionBudget: Duration(milliseconds: 50),
          memoryLimitBytes: 32 * 1024 * 1024,
        ),
      );
      final watch = Stopwatch()..start();
      try {
        engine.evaluate('while (true) {}');
        return _fail('timeout exception', 'script completed (impossible)');
      } on JavaScriptTimeoutException catch (e) {
        watch.stop();
        return _pass(
          'timeout exception',
          '${e.name} in ${watch.elapsedMilliseconds} ms',
        );
      } finally {
        engine.dispose();
      }
    },
  ),
  SecurityCase(
    id: 'limits.microtask_limit',
    category: 'dos',
    severity: 'high',
    description: 'A self-rescheduling microtask must hit a hard limit.',
    run: () async {
      final engine = JscEngine(
        const JavaScriptEngineConfig(
          maxJobsPerDrain: 100,
          executionBudget: Duration(seconds: 2),
          memoryLimitBytes: 32 * 1024 * 1024,
        ),
      );
      try {
        engine.evaluate('(function f() { Promise.resolve().then(f); })()');
        return _fail('MicrotaskLimitError', 'no exception');
      } on JavaScriptException catch (e) {
        return e.name == 'MicrotaskLimitError'
            ? _pass('MicrotaskLimitError', '${e.name}: ${e.message}')
            : _fail('MicrotaskLimitError', '${e.name}: ${e.message}');
      } finally {
        engine.dispose();
      }
    },
  ),
  SecurityCase(
    id: 'limits.parser_input_limit',
    category: 'dos',
    severity: 'medium',
    description: 'Oversized HTML must be rejected before tokenizing.',
    run: () async {
      try {
        HtmlParser(
          limits: const HtmlParserLimits(maxInputLength: 64),
        ).parseDocument('x' * 1000);
        return _fail('HtmlLimitException', 'parse completed');
      } on HtmlLimitException catch (e) {
        return _pass('HtmlLimitException', e.message);
      }
    },
  ),
  SecurityCase(
    id: 'storage.quota',
    category: 'storage',
    severity: 'medium',
    description: 'localStorage must enforce its quota and raise a typed error.',
    run: () async {
      final h = _Harness(storage: MemoryStorage(quota: 8));
      try {
        final name = h.engine.evaluate('''
              try { localStorage.setItem('key', '0123456789'); 'no-error'; }
              catch (e) { e.name; }
            ''');
        return name == 'QuotaExceededError'
            ? _pass('QuotaExceededError', '$name')
            : _fail('QuotaExceededError', '$name');
      } finally {
        h.dispose();
      }
    },
  ),
  SecurityCase(
    id: 'lifecycle.disposed_engine_rejects_calls',
    category: 'lifecycle',
    severity: 'high',
    description: 'A disposed engine must reject further evaluation.',
    run: () async {
      final engine = JscEngine();
      engine.dispose();
      try {
        engine.evaluate('1 + 1');
        return _fail('JavaScriptEngineStateException', 'call succeeded');
      } on JavaScriptEngineStateException catch (e) {
        return _pass('JavaScriptEngineStateException', e.message);
      }
    },
  ),
  SecurityCase(
    id: 'internal.callback_globals',
    category: 'hardening',
    severity: 'medium',
    description:
        'Internal JS callbacks are discoverable on globalThis and should be hardened.',
    run: () async {
      final h = _Harness(harden: true);
      try {
        final names = h.engine.evaluate(
          'JSON.stringify(Object.getOwnPropertyNames(globalThis).filter((n) => n.startsWith("__nx_")))',
        );
        final found = (jsonDecode(names as String) as List).cast<String>();
        // A script must not be able to forge host callbacks either.
        final forged = h.engine.evaluate(
          'typeof __nx_dispatch === "undefined" && typeof __nx_fireTimer === "undefined" && typeof __nx_async === "undefined"',
        );
        if (found.isEmpty && forged == true) {
          return _pass(
            'no internal __nx_* globals reachable from script',
            'none',
            evidence: [
              'Host callbacks live in a private registry inside the native runtime.',
            ],
          );
        }
        return _fail(
          'no internal __nx_* globals reachable from script',
          found.join(', '),
          evidence: [
            'These callbacks are used by the Dart bindings to invoke script listeners and fire timers.',
            'They do not grant OS access, but a script can invoke/forge its own callbacks.',
          ],
          remediation:
              'Replace global callbacks with a capability object not reachable from script globals.',
        );
      } finally {
        h.dispose();
      }
    },
  ),
  SecurityCase(
    id: 'platform.flutter_resource_policy',
    category: 'resources',
    severity: 'high',
    description:
        'Resource loading policy is Flutter-only and must be tested there.',
    run: () async => const SecurityCheck(
      status: SecurityStatus.skip,
      expected: 'default-deny resource loader verified in Flutter',
      observed: 'not runnable from the pure Dart CLI',
      evidence: [
        'NativaXRuntime defaults to NativaXDenyAllResources.',
        'Flutter tests must verify script/link denial and cancellation.',
      ],
    ),
  ),
  ...matrixSecurityCases(),
];
