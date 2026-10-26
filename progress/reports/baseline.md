# Baseline: QuickJS-ng vs V8 (Chrome) — perf/quickjs-match-v8

Fecha: 2026-10-26. Propósito: línea base de referencia para igualar el
rendimiento de QuickJS-ng con V8 en cada microbenchmark de NativaX.

## Entorno

| Campo | Valor |
|---|---|
| CPU | AMD EPYC 7763 (2 núcleos visibles en el contenedor), `taskset -c 1` |
| OS | Ubuntu 24.04.5 LTS (contenedor), x86-64 |
| QuickJS-ng | 0.17.0, vendorizado en `packages/nativa_js/third_party/quickjs`, `-O3` |
| Dart | 3.13.7 (JIT), Flutter 3.47.8 |
| V8 (referencia 1) | Node v24.21.0, V8 13.6.233.17 (`node/steady_bench.mjs`) |
| V8 (referencia 2) | `libnx_v8.so` de `tools/v8-spike` (crate `v8` 152.2.0) por el mismo puente Dart (`--engine v8`, `NATIVAX_V8_LIB`) |

Ambas referencias ejecutan **la misma obra** y verifican los mismos
checksums que QuickJS (el runner aborta si cambian).

## Comandos

```bash
cd debug/engines/microbenchmarks

# QuickJS (motor de producto)
taskset -c 1 dart run bin/benchmark.dart run --warmup 3 --rounds 15

# V8 por el mismo puente Dart (referencia "Chrome en NativaX")
NATIVAX_V8_LIB=../../..//tools/v8-spike/target/release/libnx_v8.so \
  taskset -c 1 dart run bin/benchmark.dart run --engine v8 --warmup 3 --rounds 15

# V8/Node puro (estado estacionario, parse excluido)
taskset -c 1 node node/steady_bench.mjs /tmp/v8-steady-baseline.json
```

## Matriz principal: mismo puente Dart, QuickJS vs V8 (medianas, ms)

| Benchmark | QuickJS antes | V8 (mismo puente) | ratio QJS/V8 |
|---|---:|---:|---:|
| `js.objects_properties` | 91.854 | 4.582 | 20.05x |
| `js.arithmetic` | 68.521 | 4.219 | 16.24x |
| `js.function_calls` | 39.191 | 2.941 | 13.32x |
| `js.object_churn` | 54.675 | 5.352 | 10.22x |
| `js.recursion` | 8.708 | 0.980 | 8.89x |
| `js.json_stringify` | 13.789 | 1.796 | 7.68x |
| `js.strings` | 29.273 | 4.251 | 6.89x |
| `js.json_parse` | 70.582 | 18.842 | 3.75x |
| `js.arrays` | 19.762 | 5.843 | 3.38x |
| `bridge.noop` | 20.208 | 13.265 | 1.52x |
| `js_steady.arithmetic` | 65.354 | 2.387 | 27.38x |
| `js_steady.function_calls` | 37.379 | 0.408 | 91.62x |
| `js_steady.objects_properties` | 99.187 | 7.993 | 12.41x |
| `js_steady.arrays` | 18.594 | 3.019 | 6.16x |
| `js_steady.strings` | 31.091 | 1.551 | 20.04x |
| `js_steady.recursion` | 9.568 | 1.547 | 6.19x |
| `js_steady.json_parse` | 72.338 | 17.376 | 4.16x |
| `js_steady.json_stringify` | 13.246 | 0.944 | 14.04x |
| `js_steady.object_churn` | 54.314 | 3.988 | 13.62x |
| `dom.create_nodes` | 240.323 | 143.858 | 1.67x |
| `dom.query_selectors` | 566.384 | 261.775 | 2.16x |
| `dom.modify` | 168.364 | 79.673 | 2.11x |
| `dom.remove_nodes` | 449.213 | 228.424 | 1.97x |
| `dom.events` | 219.457 | 117.774 | 1.86x |
| `dom.innerHTML` | 38.480 | 29.327 | 1.31x |
| `dom.style_recompute` | 4.524 | 2.553 | 1.77x |

Media geométrica QJS/V8 (sin `dart.*`): **6.25x**.

## Referencia V8/Node puro (`steady_bench.mjs`, warmup 8 + 21 rounds)

| Caso | V8 (Node) ms | QuickJS steady ms | ratio |
|---|---:|---:|---:|
| `js_steady.arithmetic` | 10.689 | 65.354 | 6.11x |
| `js_steady.function_calls` | 0.482 | 37.379 | 77.55x |
| `js_steady.objects_properties` | 9.401 | 99.187 | 10.55x |
| `js_steady.arrays` | 4.551 | 18.594 | 4.09x |
| `js_steady.strings` | 1.804 | 31.091 | 17.23x |
| `js_steady.recursion` | 0.882 | 9.568 | 10.85x |
| `js_steady.json_parse` | 32.110 | 72.338 | 2.25x |
| `js_steady.json_stringify` | 1.657 | 13.246 | 7.99x |
| `js_steady.object_churn` | 3.530 | 54.314 | 15.39x |

## Conformidad (puerta de no-regresión)

- Test262 (`language/{expressions,statements,types,literals}`), 2026-10-26,
  esta máquina: PASS 19943 / FAIL 47 / SKIP 1108 de 21098 → **99.76 %**
  (piso del proyecto: 97.93 %; referencia `progress/conformance.md`).

## Notas de medición

- Mediana de 15 rounds tras 3 calentamientos, pinneado a un núcleo; MAD en
  los JSON crudos. Este contenedor es ruidoso (hasta ~40 % MAD en casos
  pequeños); las decisiones se toman con repeticiones.
- Los `js.*` incluyen parse+compilación por ronda; los `js_steady.*` compilan
  una vez. La referencia justa de motor es `js_steady.*`; `js.*` mide además
  el parse de QuickJS vs V8.
- `bridge.noop` y `dom.*` miden el mismo puente Dart en ambos motores: la
  diferencia es solo el coste del lado JS (stringify/parse JSON + dispatch).
- V8 corre sin presupuesto de ejecución (el cdylib no lo aplica); QuickJS con
  el presupuesto por defecto (1 s). Ningún caso se acerca al límite.
