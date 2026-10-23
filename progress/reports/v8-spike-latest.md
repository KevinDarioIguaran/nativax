# V8 FFI spike — 2026-10-24

Objetivo: medir si V8 real, enlazado como librería nativa y llamado desde
Dart por FFI, elimina el cuello del JSON de 16 MB que bloquea QuickJS.

## Implementación

`tools/v8-spike`:

- Rust `cdylib` con `v8 = "152.2.0"` (`rusty_v8` actual).
- `nv8_parse_json_file(path)`: parser nativo de V8 (`v8::json::parse`).
- `nv8_eval(source)`: compila/ejecuta JS.
- Dart FFI (`dart:ffi` + `package:ffi`) carga `libnx_v8.so`.

Comandos:

```bash
cd tools/v8-spike
cargo build --release
dart pub get
dart run bin/bench.dart
```

## Medición

Máquina: Linux x86-64. JSON: `/tmp/nativa-bench/dict_es.json`,
14.380.093 bytes, 31.966 entradas (el mismo `/api/dict/ES` de la app).

| Motor | Operación | Tiempo |
|---|---|---:|
| **V8 152.2.0 (FFI)** | `JSON.parse` | **87 ms** |
| V8 (Node 22) | `JSON.parse` + `filter` + `sort` | **76 ms** |
| QuickJS en NativaX | app bloqueada procesando el diccionario | **~6.800 ms** |

`libnx_v8.so`: **62 MB**. `nv8_eval("JSON.stringify(...)")`: **1 ms**.

## Lectura

- El JSON de 16 MB no es intrínsecamente imposible: V8 lo parsea en ~0,09 s.
- QuickJS en el hilo de UI tarda ~6,8 s y deja la app a 100 % CPU; ese es el
  congelamiento medido.
- El spike demuestra que V8 se puede enlazar desde Dart y que el coste del
  parser desaparece. **No** demuestra todavía que la app completa vuele: falta
  el bridge DOM/fetch/IndexedDB y la política de hilos.

## Limitaciones

- Un isolate V8 por llamada; el motor real debe reutilizarlo.
- Sin host functions V8→Dart.
- Sin transferencia de objetos grandes (solo longitud/Eval string).
- V8 pesa 62 MB y necesita builds por plataforma; iOS sin JIT.
- El primer `cargo build` descarga el prebuilt de V8.

## Siguiente

1. Isolate/contexto persistente.
2. Host function síncrona/asíncrona y medición del cruce.
3. V8 en worker + operaciones agrupadas por frame.
4. `JavaScriptEngine` V8 y preludio DOM.
5. Validación Biblia: primer versículo y cambio de capítulo.
