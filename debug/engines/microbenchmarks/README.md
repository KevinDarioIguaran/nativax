# Benchmarks de NativaX

Suite reproducible para medir el motor JavaScript, el puente, el DOM, el
recálculo de estilos y una referencia nativa en Dart.

## Ejecutar

```bash
cd debug/engines/microbenchmarks
dart run bin/benchmark.dart run \
  --warmup 3 --rounds 15
```

Salida por defecto:

- `benchmarks/results/bench-<timestamp>.json`
- `benchmarks/results/bench-<timestamp>.md`

Opciones:

```bash
--only js.arithmetic       # filtrar por nombre o categoría
--no-js | --no-dom | --no-dart
--out DIR                  # directorio de resultados
--json FILE --md FILE      # rutas explícitas
--list                     # listar casos
```

## Comparar dos ejecuciones

```bash
dart run bin/benchmark.dart compare \
  --baseline benchmarks/results/base.json \
  --current benchmarks/results/current.json \
  --threshold 10 \
  --noise 2
```

Una diferencia solo se marca como regresión si supera **el umbral** y **el
ruido medido** (`MAD / mediana × noise`). Las diferencias dentro del ruido se
marcan `noise`, no `regression`. El comando devuelve código 2 si hay
regresiones.

## Categorías

| Categoría | Qué mide |
|---|---|
| `js` | Aritmética, funciones, objetos/prototipos, arrays, strings, recursión, JSON, creación de objetos |
| `bridge` | Ida y vuelta JS → C → Dart → JS sin DOM |
| `dom` | Crear, consultar, modificar, eliminar nodos, eventos, `innerHTML`, `StyleEngine.recompute` |
| `dart` | Referencia nativa del mismo proceso (no equivalente al motor JS) |

`dom.style_recompute` mide DOM → estilos, **no** frames de GPU ni la
actualización visible. La medición de UI requiere un harness Flutter y no se
presenta como si el CLI pudiera medirla.

## Metadatos

Cada JSON incluye:

- motor y versión (`QuickJS-ng` leída de `quickjs.h`),
- versión de Dart y modo (`JIT`, `profile`, `AOT`),
- OS, versión y arquitectura,
- reloj (`Stopwatch` monotónico), frecuencia y resolución declarada,
- fecha, comando y notas.

`Stopwatch` usa un reloj monotónico; se reporta `elapsedTicks / frequency` para
evitar perder muestras sub-microsegundo. La resolución efectiva depende del
sistema y se declara como cota (`1000 / frequency` ms), no como precisión
garantizada.

## Integridad de las mediciones

- Cada caso devuelve un **checksum** determinista.
- El runner ejecuta calentamiento y varias rondas; un checksum distinto o un
  fallo de valor esperado aborta la ejecución.
- El checksum se guarda en JSON y Markdown; no se rellenan mediciones con
  ceros.
- Los casos hacen trabajo dentro del bucle, no solo una llamada vacía.

## Interpretación

- Compara **medianas** entre ejecuciones en la misma máquina y condiciones.
- `MAD/mediana` es la dispersión robusta; úsala para juzgar si una diferencia
  es real.
- No compares números absolutos entre máquinas, modos JIT/AOT o motores
  distintos como si fueran equivalentes.
- `dart.*` es una referencia de contexto: el JIT puede optimizar agresivamente
  bucles y objetos; no es una comparación justa con QuickJS.
- No se incluyen referencias V8/JavaScriptCore: no hay una ejecución
  equivalente y documentada con el DOM de NativaX. No se inventan resultados.

## Tests del runner

```bash
dart test
```

Cubren estadísticas, checksums, formato JSON/Markdown y comparación con ruido.


## Comparación con V8 (Node.js)

La suite `js_steady.*` compila el script una vez y mide solo las llamadas
posteriores. Es la comparación correcta para estado estacionario: no mezcla
parseo/compilación con el bucle caliente.

```bash
cd debug/engines/microbenchmarks
taskset -c 4 dart run bin/benchmark.dart run \
  --only js_steady --warmup 8 --rounds 21 \
  --json /tmp/nativax-steady.json --md /tmp/nativax-steady.md

taskset -c 4 node node/steady_bench.mjs /tmp/v8-steady.json

python3 node/compare_node.py /tmp/nativax-steady.json /tmp/v8-steady.json
```

`compare_node.py` verifica los checksums y calcula la media geométrica de
`tiempo NativaX / tiempo V8`. Un valor mayor que 1 significa que NativaX es
más lento. No se ocultan casos ni se cambia el peso entre ellos.

Los benchmarks `js.*` originales siguen midiendo `engine.evaluate()` completo
(parseo + bytecode + ejecución) para conservar la línea base histórica.
