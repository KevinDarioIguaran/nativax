# Auditoría de rendimiento del motor JavaScript (2026-10-21)

## 1. Motor y arquitectura real

| Elemento | Valor |
|---|---|
| Motor | **QuickJS-ng 0.17.0** (`third_party/quickjs`) |
| Licencia | MIT |
| Modelo | Intérprete de bytecode **sin JIT** |
| Lenguaje | C (C11/GNU11), compilado a `nativax_quickjs` |
| Integración | FFI de Dart; un `JSRuntime` + `JSContext` por motor |
| Dispatch | `DIRECT_DISPATCH=1`: computed goto en compiladores no MSVC/Emscripten |
| Build | `CBuilder.library` release, `-O3`, `NDEBUG`, `-fvisibility=hidden` |
| GC | mark-sweep + refcount, heap malloc de QuickJS |
| Valor JS | `JSValue` de 16 bytes en x86-64 (union de 8 bytes + tag de 8), sin NaN boxing |
| Propiedades | shapes/prototype chain de QuickJS; **no hay inline caches en bytecode** |
| Parsing | parser/bytecode compiler de QuickJS en cada `JS_Eval` |

No es «Q»: el motor es **QuickJS-ng**. No hay JIT, ni V8, ni JavaScriptCore
dentro de NativaX.

### Pipeline

```
fuente JS
  → parser QuickJS (quickjs.c)
  → bytecode (quickjs-opcode.h)
  → JS_CallInternal / dispatch por computed goto
  → JSValue (int32 / float64 / string / objeto / función…)
  → GC mark-sweep + refcount
```

En la frontera nativa:

```
JS __nx.host(nombre, args)
  → JSON.stringify en JS
  → nx_host_call (C)
  → Dart: jsonDecode, handler, jsonEncode
  → JS_ParseJSON en C
```

`bridge.noop` mide ese ciclo completo (≈2,6 µs/llamada).

## 2. Metodología

- CPU: Intel Core i7-8700 @ 3.20 GHz, Linux 6.12.90 x86-64.
- Dart 3.13.0 JIT para NativaX.
- Node 22.23.2, V8 12.4.254.21-node.56.
- QuickJS-ng 0.17.0 compilado con `-O3`, `NDEBUG`, sin LTO.
- Benchmarks `js_steady.*`: el script se compila **una vez**; se miden solo
  las llamadas posteriores. Calentamiento 8, 21 rondas, mediana.
- Los `js.*` históricos siguen midiendo `engine.evaluate()` completo
  (parseo + bytecode + ejecución), por compatibilidad con la línea base.
- Pin de CPU con `taskset -c 4`. El gobernador del sistema es `powersave`; por
  eso las comparaciones A/B se repitieron cerca en el tiempo y se descartan
  diferencias dentro del ruido.

Comando reproducible:

```bash
cd tools/benchmark
taskset -c 4 dart run bin/benchmark.dart run \
  --only js_steady --warmup 8 --rounds 21 \
  --json /tmp/nativax-steady.json --md /tmp/nativax-steady.md
taskset -c 4 node node/steady_bench.mjs /tmp/v8-steady.json
python3 node/compare_node.py /tmp/nativax-steady.json /tmp/v8-steady.json
```

## 3. Línea base steady-state

| Benchmark | NativaX | V8 | Ratio NativaX/V8 |
|---|---:|---:|---:|
| `js_steady.arithmetic` | 35,225 ms | 4,768 ms | 7,39× |
| `js_steady.function_calls` | 22,279 ms | 0,469 ms | 47,54× |
| `js_steady.objects_properties` | 60,316 ms | 9,528 ms | 6,33× |
| `js_steady.arrays` | 13,856 ms | 3,472 ms | 3,99× |
| `js_steady.strings` | 18,207 ms | 1,540 ms | 11,83× |
| `js_steady.recursion` | 4,838 ms | 0,885 ms | 5,47× |
| `js_steady.json_parse` | 58,213 ms | 24,654 ms | 2,36× |
| `js_steady.json_stringify` | 9,743 ms | 1,503 ms | 6,48× |
| `js_steady.object_churn` | 36,955 ms | 3,912 ms | 9,45× |
| **Media geométrica** | | | **7,58×** |

Todos los checksums coinciden. El motor está **7,58× más lento** que V8 en
estado estacionario, no 7× más rápido. Para cumplir el objetivo de ser 7×
más rápido que V8 desde esta línea base se necesitaría una mejora de
**53,1×**.

## 4. Cuellos de botella priorizados

| Prioridad | Cuello de botella | Evidencia | Impacto |
|---|---|---|---|
| P0 | Llamadas a función / frames / entornos | `function_calls` 47,5×, `recursion` 5,5× | El mayor gap individual |
| P0 | Ausencia de JIT y de especialización por tipo | aritmética 7,4×, properties 6,3× | Gap estructural del intérprete |
| P1 | Strings y Unicode | 11,8× | Concatenación/slice/charCode crean objetos y copias |
| P1 | Asignación y GC | churn 9,5× | Refcount + mark-sweep + heap malloc |
| P1 | Dispatch de bytecode | aritmética/loops 7,4× | Sin superinstructions ni type feedback |
| P2 | Property lookup/prototipos | properties 6,3× | Sin PIC/hidden-class inline cache |
| P2 | JSON nativo | parse 2,36×, stringify 6,48× | Implementación de QuickJS, no V8 |
| P2 | Frontera JS→C→Dart | 2,6 µs/llamada en `bridge.noop` | JSON y cruces de FFI |

## 5. Experimentos realizados y descartados

| ID | Cambio | Resultado | Decisión |
|---|---|---|---|
| B1 | `-flto` en QuickJS + bridge | ±0–4 %, sin mejora consistente; algunas cargas empeoraron | **descartado** |
| B2 | `-O2` | claramente peor que `-O3` | **descartado** |
| B3 | `-march=native` | peor en este host y no portable | **descartado** |
| B4 | `-fno-semantic-interposition` + LTO | peor o dentro de ruido | **descartado** |
| R1 | Subir `JS_INTERRUPT_COUNTER_INIT` 10k→100k | medición inválida por caída de frecuencia; no se retuvo | **descartado** |
| R2 | Subir `JS_SetGCThreshold` inicial a 4 MB | sin mejora medible en churn/objetos; más memoria | **descartado** |

No se cambió el trabajo, los checksums, ni se añadieron atajos específicos de
benchmark.

## 6. Roadmap de optimización

### Ruta A — Mantener QuickJS (sin JIT)

1. **PIC para propiedades** en bytecode (`get_field`/`put_field`): riesgo alto,
   ganancia potencial 1,5–3× en objetos.
2. **Inline caching de llamadas** y reducción de `JS_CallInternal`/frames:
   riesgo alto, ganancia 1,2–2× en funciones.
3. **Bytecode superinstructions** para `load_const`+`add`+`branch`: riesgo
   medio, ganancia 5–20 % en bucles.
4. **Caché de bytecode por fuente** para `evaluate` repetido: riesgo semántico
   medio; no ayuda a bucles ya compilados.
5. **Bridge binario** para operaciones calientes: elimina JSON, no acelera JS
   puro.

Incluso sumando todo, es improbable superar a V8 en JS general; el techo
realista es acercarse a 1× en algunas cargas.

### Ruta B — Adaptador V8/JavaScriptCore (la única vía a paridad/7×)

- V8 en Linux/Android/desktop con JIT; QuickJS-ng en iOS o modo compatible.
- Requiere un backend de bindings DOM distinto o una capa de compatibilidad
  (`JSValue`/host functions) sobre V8.
- En estado estacionario podría igualar a V8 (ratio 1×), no ser 7× más rápido.
  Un 7× **end-to-end** solo es defendible si el trabajo pesado se mueve a
  operaciones nativas/WAMR y se mide por escenario, no como un número global.

### Ruta C — WebAssembly/Rapier

- WAMR AOT para física; objetivo ≤46,9 ms/180 pasos frente a 328,54 ms de
  wasm3 y 30,74 ms de V8. Es la vía realista para 7× end-to-end en el juego.

## 7. Evaluación honesta del objetivo 7×

Con la evidencia actual:

- **7× más rápido que V8 en JavaScript general con QuickJS-ng no es alcanzable**
  sin un JIT. La línea base es 7,58× más lenta; el objetivo exige 53,1×.
- QuickJS-ng es un intérprete; V8 compila código caliente. Ninguna combinación
  de flags de build cierra una diferencia de 53×.
- 7× **respecto a la línea base actual** sí es alcanzable en escenarios
  nativos/WAMR/bridge, pero no en bucles JS puros.
- El único camino a paridad JS es un adaptador V8/JavaScriptCore; aun así el
  resultado sería ~1× V8, no 7× V8.
- Se necesita una decisión de producto: aceptar QuickJS-ng (compatibilidad,
  iOS, tamaño) o introducir un segundo motor con su coste de mantenimiento.

## 8. Estado de los entregables

- Auditoría: este documento.
- Harness V8: `tools/benchmark/node/steady_bench.mjs`.
- Comparador: `tools/benchmark/node/compare_node.py`.
- Benchmarks steady: `js_steady.*` en `tools/benchmark`.
- Correctitud: suite completa de NativaX y Test262/WPT existentes.
- 7×: **no demostrado**; evidencia en contra para JS puro.
