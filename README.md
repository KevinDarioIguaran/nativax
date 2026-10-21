# NativaX

Runtime experimental de interfaz escrito en Dart que interpreta un subconjunto
documentado de HTML, CSS y JavaScript y lo renderiza con widgets Flutter
nativos. **No usa WebView, Chromium ni un navegador incrustado.**

## Estado

El flujo `HTML → DOM → CSS → Flutter` y `JS → DOM → Flutter` funciona con
páginas reales: `examples/web-challenge` ejecuta su HTML/CSS/JS original
(grid, animaciones, SVG, canvas, formularios, Workers, IndexedDB, fetch por
política de red...) y se ve como en Chrome salvo vídeo/audio. Estado vivo,
números y pendientes:

- [`docs/javascript-supported.md`](docs/javascript-supported.md) (APIs y event loop)
- [`docs/css-supported.md`](docs/css-supported.md) (CSS y layout soportados)
- [`docs/hot-reload.md`](docs/hot-reload.md) (recarga de documentos en desarrollo)
- [`docs/benchmarks.md`](docs/benchmarks.md) (rendimiento y comparación)
- [`tools/leaks/README.md`](tools/leaks/README.md) (fugas, retención y ciclo de vida)
- [`SECURITY_AUDIT.md`](SECURITY_AUDIT.md) (auditoría y hallazgos)
- [`SECURITY_THREAT_MODEL.md`](SECURITY_THREAT_MODEL.md) (modelo de amenazas)
- [`progress/status.md`](progress/status.md)
- [`progress/conformance.md`](progress/conformance.md)
- [`.agents/`](.agents/README.md) (contexto, arquitectura, estándares)

## Paquetes

| Paquete | Responsabilidad |
|---|---|
| `nativax_js` | QuickJS-ng, puente C/FFI, WebGL 2 (EGL), WebAssembly (wasm3), timers y límites |
| `nativax_dom` | Árbol DOM, eventos, selectores, mutaciones |
| `nativax_html` | Tokenizer y tree builder HTML |
| `nativax_css` | Parser, cascada, media queries, estilos computados |
| `nativax_dom_bindings` | DOM y APIs de navegador expuestas a JavaScript |
| `nativax_flutter` | Layout CSS y renderer Flutter |
| `nativax` | Runtime público y `NativaXView` |

## Uso mínimo

```dart
import 'package:flutter/material.dart';
import 'package:nativax/nativax.dart';

void main() => runApp(const MaterialApp(
      home: Scaffold(
        body: NativaXView(source: '''
          <style>h1 { color: #2563eb }</style>
          <h1>Hola NativaX</h1>
          <button id="b">0</button>
          <script>
            let n = 0;
            document.getElementById('b').addEventListener('click', () => {
              n += 1;
              document.getElementById('b').textContent = String(n);
            });
          </script>
        '''),
      ),
    ));
```

## Ejemplos

- [`examples/web-challenge`](examples/web-challenge): el reto web HTML/CSS/JS
  original, sin adaptaciones, con red habilitada solo para sus hosts; incluye
  build Linux y una herramienta de captura para comparar con Chrome
  (`test/screenshot_test.dart`).

## Tests

```bash
./tools/test_all.sh
```

## Conformidad

Las suites oficiales se descargan (no se versionan) y se ejecutan contra
NativaX:

```bash
cd tools/conformance
dart run bin/fetch_suites.dart --suite test262 --suite html5lib --suite wpt
dart run bin/run_all.dart
```

Resultados actuales: Test262 **97,93 %**, html5lib **96,95 %**, URL
**70,98 %**; WPT `dom/nodes` 19,11 %, `css/selectors` 4,92 % y tree
construction 39,75 %. El objetivo de 70 % en todas no se ha alcanzado todavía
en DOM/CSS/parser; ver [`progress/conformance.md`](progress/conformance.md).
