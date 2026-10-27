import 'dart:convert';

import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_dom/nativa_dom.dart';
import 'package:nativa_dom_bindings/nativa_dom_bindings.dart';
import 'package:nativa_html/nativa_html.dart';
import 'package:nativa_js/nativa_js.dart';

import 'model.dart';

class _Harness {
  _Harness() {
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
      ),
    )..install();
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

SecurityCheck _pass(String expected, String observed) => SecurityCheck(
  status: SecurityStatus.pass,
  expected: expected,
  observed: observed,
);

SecurityCheck _fail(String expected, String observed) => SecurityCheck(
  status: SecurityStatus.fail,
  expected: expected,
  observed: observed,
);

/// Additional adversarial cases used by the broad matrix. They are separate
/// from the hand-written cases so a new payload or global does not require a
/// second copy of the harness.
List<SecurityCase> matrixSecurityCases() {
  const globals = [
    'process',
    'require',
    'fetch',
    'XMLHttpRequest',
    'WebSocket',
    'Deno',
    'Bun',
    'dart',
    'File',
    'Directory',
  ];
  const schemes = [
    'javascript:globalThis.pwned=1',
    'data:text/html,<script>globalThis.pwned=2</script>',
    'vbscript:msgbox(1)',
    'file:///etc/passwd',
    'mailto:test@example.com',
    'tel:+1000000',
    'blob:https://example.test/0000',
    'about:blank',
    'chrome://settings',
    'resource://gre/',
  ];
  const payloads = [
    '<script>globalThis.pwned=1</script>',
    '<img src="x" onerror="globalThis.pwned=2">',
    '<svg onload="globalThis.pwned=3"></svg>',
    '<iframe srcdoc="<script>parent.pwned=4</script>"></iframe>',
    '<details open ontoggle="globalThis.pwned=5"></details>',
    '<input autofocus onfocus="globalThis.pwned=6">',
    '<body onpageshow="globalThis.pwned=7">',
    '<a href="javascript:globalThis.pwned=8">x</a>',
    '<math><mtext><script>globalThis.pwned=9</script></mtext></math>',
    '<object data="javascript:globalThis.pwned=10"></object>',
  ];

  return [
    for (final name in globals)
      SecurityCase(
        id: 'matrix.global.$name',
        category: 'sandbox',
        severity: 'critical',
        description: 'Generated sandbox check: $name must be undefined.',
        run: () async {
          final engine = JscEngine();
          try {
            final type = engine.evaluate(
              'typeof globalThis[${jsonEncode(name)}]',
            );
            return type == 'undefined'
                ? _pass('$name undefined', '$type')
                : _fail('$name undefined', '$type');
          } finally {
            engine.dispose();
          }
        },
      ),
    for (var i = 0; i < schemes.length; i++)
      SecurityCase(
        id: 'matrix.url.${i + 1}',
        category: 'navigation',
        severity: 'high',
        description:
            'Generated navigation containment ${i + 1}: ${schemes[i]} must not execute script.',
        run: () async {
          final h = _Harness();
          try {
            h.engine.evaluate('''
              globalThis.pwned = 0;
              const a = document.createElement('a');
              a.id = 'matrix-link';
              a.href = ${jsonEncode(schemes[i])};
              document.body.appendChild(a);
            ''');
            h.engine.evaluate('document.getElementById("matrix-link").click()');
            await Future<void>.delayed(const Duration(milliseconds: 10));
            final pwned = h.engine.evaluate('globalThis.pwned');
            final alive = h.engine.evaluate('1 + 2');
            return pwned == 0 && alive == 3
                ? _pass(
                    'pwned=0 and runtime alive',
                    'pwned=$pwned alive=$alive',
                  )
                : _fail(
                    'pwned=0 and runtime alive',
                    'pwned=$pwned alive=$alive',
                  );
          } finally {
            h.dispose();
          }
        },
      ),
    for (var i = 0; i < payloads.length; i++)
      SecurityCase(
        id: 'matrix.inner_html.${i + 1}',
        category: 'xss',
        severity: 'critical',
        description: 'Generated inert innerHTML payload ${i + 1}.',
        run: () async {
          final h = _Harness();
          try {
            h.engine.evaluate('globalThis.pwned = 0;');
            h.engine.evaluate(
              'document.body.innerHTML = ${jsonEncode(payloads[i])};',
            );
            await Future<void>.delayed(const Duration(milliseconds: 10));
            final pwned = h.engine.evaluate('globalThis.pwned');
            final alive = h.engine.evaluate('1 + 2');
            return pwned == 0 && alive == 3
                ? _pass('pwned=0 and runtime alive', 'pwned=$pwned payload=$i')
                : _fail('pwned=0 and runtime alive', 'pwned=$pwned payload=$i');
          } finally {
            h.dispose();
          }
        },
      ),
  ];
}
