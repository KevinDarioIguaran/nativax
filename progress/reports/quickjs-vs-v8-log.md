# QuickJS vs V8: log de mejoras (rama `perf/quickjs-match-v8`)

Protocolo: por benchmark, gap QJS/V8 ordenado de mayor a menor; cada cambio
se mide pareado (pinneado a un núcleo, medianas), se verifica con
`./tools/test_all.sh` y Test262 (piso 97.93 %, baseline local 99.76 %) y se
commitea con sus cifras antes/después. Referencias en `baseline.md`.

## N=1 — fix `ENABLE_DUMPS` (global, primer commit de mejoras)

**Problema**: el vendorizado añadía `#define ENABLE_DUMPS` incondicional que
anulaba el guard `#ifndef NDEBUG` de upstream. Con dumps activos, cada
alloc/free de string hace `list_add/list_del` sobre `rt->string_list` en
**todos** los builds (incluidos release).

**Cambio**: `ENABLE_DUMPS` pasa a opt-in (`NATIVAX_QJS_DUMPS`). Producto y
tests corren con el camino limpio de upstream-release; nadie en el repo usa
los dump flags (verificado por grep).

### Evidencia 1: harness aislado (gcc -O3 -DNDEBUG, taskset -c 1, medianas de 5)

| caso | antes (ms) | después (ms) | Δ |
|---|---:|---:|---:|
| function_calls | 43.5 | 39.1 | −10.1 % |
| strings | 33.7 | 30.5 | −9.5 % |
| json_parse | 85.0 | 79.2 | −6.8 % |
| object_churn | 57.6 | 53.8 | −6.6 % |
| arithmetic | 64.0 | 61.0 | −4.7 % |
| json_stringify | 16.1 | 15.5 | −3.7 % |
| arrays | 26.1 | 25.2 | −3.4 % |
| recursion | 9.54 | 9.11 | −4.5 % |
| objects_properties | ~sin cambio | ~sin cambio | ~0 % |

### Evidencia 2: harness Dart intercalado A/B/A/B (mismo puente, `--only`)

| caso | A1 (después) | B1 (antes) | A2 (después) | B2 (antes) |
|---|---:|---:|---:|---:|
| `js.arithmetic` | 60.237 | 72.927 | 57.750 | 71.946 |
| `js_steady.arithmetic` | 58.263 | 78.329 | 59.135 | 70.991 |
| `js.json_parse` | 76.141 | 104.109 | 90.482 | 92.754 |
| `js_steady.json_parse` | 86.171 | 75.997 | 90.188 | 87.726 |
| `bridge.noop` | 30.538 | 23.636 | 26.467 | 24.511 |
| `dart.arithmetic` (control, sin QuickJS) | 3.321 | 3.234 | 7.128 | 2.648 |
| `dart.json_parse` (control) | 42.227 | 50.969 | 61.265 | 52.531 |

- Aritmética: las dos corridas A ganan a las dos B (−16…−22 %) → mejora real.
- Los controles `dart.*` (que no tocan QuickJS) oscilan hasta ±150 %: el
  contenedor tiene carga de fondo; los deltas pequeños del harness Dart no
  son fiables por sí solos.
- `bridge.noop` salió más lento en A sin mecanismo causal (el fix solo
  quita trabajo). Sospecha: efecto de layout de código por el tamaño
  cambiante de `quickjs.c`. Pendiente de re-medir con el harness de puente
  dedicado (`main_bridge.c`, sin Dart en el medio).

### Verificación

- Test262: 99.76 % (PASS 19943 / FAIL 47 / SKIP 1108) — idéntico a la
  baseline.
- `./tools/test_all.sh`: nativa_js (55), nativa_dom (74), nativa_html (81),
  nativa_css (113) — todos verdes. `nativa_dom_bindings` falla solo en
  `webgl_test` (3 casos) y `nativax` en `game_play_test` (1 caso): ambos
  **pre-existentes y del entorno** (no hay EGL/OpenGL ES 3 en el
  contenedor); verificado idéntico con el cambio stashado en la config base.

## Pendiente

- N=2 `js.objects_properties` (20.05x): shape por objeto sin compartir
  (fix de canonalización medido peor; upstream tampoco lo resuelve). En
  marcha el tier-0 JIT (ver N=3).
- `bridge.noop` / `dom.*`: optimización del puente C (fast paths de
  escalares) pendiente.
- Re-medir `bridge.noop` con harness de puente dedicado.
