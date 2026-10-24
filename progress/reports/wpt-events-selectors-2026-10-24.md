# WPT events/selectors/dom-nodes — 2026-10-24

Runners y suites pinneadas en `tools/conformance` / `.conformance/suites`.

| Suite | PASS | FAIL | SKIP | ERROR | Tasa sin SKIP |
|---|---:|---:|---:|---:|---:|
| `dom/events` | 51 | 22 | 103 | 0 | 69,86 % |
| `css/selectors` | 106 | 74 | 348 | 0 | 58,89 % |
| `dom/nodes` | 175 | 106 | 46 | 0 | 62,28 % |
| WPT URL | 665 | 231 | 0 | 0 | 74,22 % |
| WPT tree construction | 944 | 930 | 99 | 0 | 50,37 % |

Comandos:

```bash
cd tools/conformance
dart run bin/run_wpt.dart --dirs dom/events --limit 2000
dart run bin/run_wpt.dart --dirs css/selectors --limit 2000
dart run bin/run_wpt.dart --dirs dom/nodes --limit 2000
dart run bin/run_url.dart
dart run bin/run_html_tree.dart
```

## Nota de medición

El runner corregido usa `StyleEngine.handleMutation` y un shim de testharness
más completo. Esa corrección **no cuenta como compatibilidad de producto**;
elimina falsos fallos del arnés. Los deltas de motor de esta sesión incluyen
invalidación de sujetos `:has()` y la API legacy de eventos.

`dom/events` queda en 69,86 % (51/73 no-SKIP), a un archivo de 70 %. No se
redondea ni se cambia el denominador.

## Pendiente para 70 %

- `dom/events`: activación de `input`/`form`, propagación con listeners
  mutados, errores de listeners, iframes/realm, `scroll`/`scrollend`.
- `css/selectors`: `:dir`, `:focus-visible`, Shadow DOM, `:has()` relativo
  complejo, quirks mode y selectores namespaced.
- `dom/nodes`: registros de `createElement`, namespaces, `Range`,
  `MutationObserver` restante, `moveBefore` y realms.
- tree construction: adoption agency, foster parenting, `template`, foreign
  content y estados de script.
