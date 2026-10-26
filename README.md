# Nativa

**Nativa** es la familia de tecnologías. **NativaX** es la plataforma
principal: un runtime experimental de interfaz escrito en Dart que interpreta
un subconjunto documentado de HTML, CSS y JavaScript y lo renderiza con
widgets Flutter nativos. **No usa WebView, Chromium ni un navegador
incrustado.**

## Familia Nativa

```
NATIVA
├── NativaX       Plataforma multiplataforma
├── NativaJS      Motor JavaScript
├── NativaWeb     HTML, CSS, DOM y APIs web
├── NativaRender  Layout y renderizado Flutter
├── NativaFlow    Workers, concurrencia y mensajería
├── NativaForge   Toolchain, tests y conformidad
├── NativaShield  Seguridad, permisos y límites
└── NativaBench   Benchmarks y rendimiento
```

Cada nombre identifica una responsabilidad. No todos son paquetes separados
todavía: los que aún no tienen API y ciclo propios viven dentro del proyecto
que los contiene y se extraerán solo cuando aporte valor. El detalle y los
criterios de extracción están en
[`docs/nativa-family.md`](docs/nativa-family.md).

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
- [`docs/performance-suite.md`](docs/performance-suite.md) (UI, scroll, memoria y panel Tkinter)
- [`progress/reports/nativa-quality-latest.md`](progress/reports/nativa-quality-latest.md) (informe consolidado de capacidad y evidencia)
- [`debug/engines/memory/README.md`](debug/engines/memory/README.md) (fugas, retención y ciclo de vida)
- [`docs/security/audit.md`](docs/security/audit.md) (auditoría y hallazgos)
- [`docs/security/threat-model.md`](docs/security/threat-model.md) (modelo de amenazas)
- [`progress/status.md`](progress/status.md)
- [`progress/conformance.md`](progress/conformance.md)
- [`.agents/`](.agents/README.md) (contexto, arquitectura, estándares)

## Paquetes

| Proyecto | Paquete(s) / ubicación | Responsabilidad |
|---|---|---|
| **NativaX** | `nativax` | Runtime público, `NativaXView`, carga de documentos y workers |
| **NativaJS** | `nativa_js` | QuickJS-ng, puente C/FFI, timers, WebAssembly (wasm3) y límites |
| **NativaWeb** | `nativa_html`, `nativa_dom`, `nativa_css`, `nativa_dom_bindings` | HTML, DOM, CSS y APIs de navegador expuestas a JavaScript |
| **NativaRender** | `nativa_render` | Layout CSS y renderizado Flutter |
| **NativaFlow** | `nativax/lib/src/workers.dart` (embebido) | Workers, mensajería y concurrencia |
| **NativaForge** | `tools/` | Tests, conformidad, empaquetado y herramientas de desarrollo |
| **NativaShield** | `debug/engines/security`, `SECURITY_*` | Aislamiento, permisos, límites y auditoría |
| **NativaBench** | `benchmarks/`, `debug/engines/microbenchmarks`, `debug/engines/performance`, `debug/engines/memory` | Benchmarks reproducibles de rendimiento y conformidad |

NativaWeb **no** es un paquete monolítico: es la familia de cuatro módulos
independientes que pueden usarse por separado.

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
- [`examples/game-player`](examples/game-player): reproductor del juego real
  con workers, WebAssembly y presentación WebGL.

## Tests

```bash
./tools/test_all.sh
```

## Calidad visual y rendimiento

```bash
tools/quality_report.sh          # 51 páginas visuales + 270 escenarios + app idle
tools/quality_report.sh --all-visual  # 300 páginas visuales
tools/quality_report.sh --gui    # y abre el panel Tkinter

# Compuerta sin UI para IA/CI (visual + rendimiento + compatibilidad)
python3 tools/quality_gate.py --run
python3 tools/quality_gate.py --json

# Aislamiento por contenedor con CPU/RAM limitadas
debug/engines/performance/container/matrix.sh

# Vista previa renderizada del informe (no código fuente)
tools/preview_report.sh
```

Informe consolidado:
[`progress/reports/nativa-quality-latest.md`](progress/reports/nativa-quality-latest.md).

## Conformidad

Las suites oficiales se descargan (no se versionan) y se ejecutan contra
NativaX:

```bash
cd debug/engines/compatibility
dart run bin/fetch_suites.dart --suite test262 --suite html5lib --suite wpt
dart run bin/run_all.dart
```

Resultados actuales: Test262 **97,93 %**, html5lib tokenizer **99,26 %**, URL
**70,98 %**; WPT `dom/nodes` **59,36 %**, `css/selectors` **10,38 %** y tree
construction **48,72 %**. El objetivo de 70 % en todas no se ha alcanzado
todavía en DOM/CSS/parser; ver
[`progress/conformance.md`](progress/conformance.md).
