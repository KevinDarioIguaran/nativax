# NativaX V8 FFI spike

Prueba mínima de **V8 real en Dart** con `rusty_v8` (`v8` crate) y `dart:ffi`.
No está integrado en el motor todavía: sirve para medir el cuello de botella
del JSON antes de portar el bridge.

## Qué contiene

- `Cargo.toml`: crate `cdylib` con `v8 = "152.2.0"` (`rusty_v8` actual).
- `src/lib.rs`:
  - `nv8_parse_json_file(path) -> u32`: parsea JSON con el parser nativo de
    V8 y devuelve la longitud del array.
  - `nv8_eval(source) -> char*`: compila y ejecuta JS; devuelve el resultado.
  - `nv8_free(ptr)`: libera la cadena devuelta.
- `bin/bench.dart`: carga `libnx_v8.so` por `dart:ffi`, mide `JSON.parse` del
  diccionario real de 16 MB y una evaluación trivial.

## Comando

```bash
cd tools/v8-spike
cargo build --release
dart pub get
dart run bin/bench.dart
```

## Resultado medido (Linux x86-64, release)

```
V8_JSON_PARSE file=/tmp/nativa-bench/dict_es.json length=31966 ms=87 us=87580
V8_EVAL result={"ok":2,"len":3} ms=1
```

- Diccionario: **14.380.093 bytes**, 31.966 entradas.
- V8 JSON parse: **87 ms**.
- V8 eval trivial: **1 ms**.
- `libnx_v8.so`: **62 MB**.
- Referencia Node 22 / V8 sobre el mismo JSON (parse + filter + sort):
  **76 ms**.
- QuickJS en la app de la Biblia: **~6.800 ms bloqueando la UI**.

## Por qué importa

El coste del JSON deja de ser el cuello. La diferencia no es CSS, layout ni
GPU: es el motor JS. V8 con JIT parsea el diccionario en ~0,09 s; QuickJS en
el hilo de UI tarda ~6,8 s y congela Flutter.

## Limitaciones de este spike

- Crea un isolate V8 por llamada; el motor real debe reutilizar uno.
- No registra host functions todavía: el puente DOM/fetch/IndexedDB no está.
- No mide el coste de devolver el objeto a Dart; el motor real debe enviar
  operaciones en lote (ids/escalares/JSON), no objetos V8.
- El binario V8 pesa 62 MB; hay que decidir empaquetado por plataforma.
- En iOS no hay JIT para apps de terceros; QuickJS seguiría de fallback.
- `rusty_v8` descarga el binario prebuilt de V8 en el primer build.

## Siguiente paso

1. Reutilizar un isolate/contexto V8 por documento.
2. Registrar una host function V8→Dart y medir el coste síncrono/asíncrono.
3. Probar el patrón de hilo: V8 en worker, host calls agrupadas por frame.
4. Portar `JavaScriptEngine` y el preludio DOM sobre V8.
5. Medir la app de la Biblia: primer versículo y cambio de capítulo.
