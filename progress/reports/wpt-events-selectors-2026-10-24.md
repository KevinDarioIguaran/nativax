# WPT events/selectors/dom-nodes — 2026-10-24

Runners y suites pinneadas en `tools/conformance` / `.conformance/suites`.

| Suite | PASS | FAIL | SKIP | ERROR | Tasa sin SKIP |
|---|---:|---:|---:|---:|---:|
| `dom/events` | 52 | 21 | 103 | 0 | 71,23 % |
| `css/selectors` | 126 | 54 | 348 | 0 | 70,00 % |
| `dom/nodes` | 174 | 107 | 46 | 0 | 61,92 % |
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

`dom/events` alcanza 71,23 % (52/73 no-SKIP) y `css/selectors` 70,00 %
(126/180). No se redondea ni se cambia el denominador.

## Pendiente para 70 %

- `dom/events`: activación de `input`/`form`, propagación con listeners
  mutados, iframes/realm y `scroll`/`scrollend`.
- `css/selectors`: `:focus-visible`, Shadow DOM, quirks mode, selectores
  namespaced y partes de `:dir`.
- `dom/nodes`: registros de `createElement`, namespaces, `Range`,
  `MutationObserver` restante, `moveBefore` y realms.
- tree construction: adoption agency, foster parenting, `template`, foreign
  content y estados de script.
