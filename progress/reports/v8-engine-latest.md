# V8 backend + UI bottleneck (2026-10-24)

Rama: `feat/v8-engine`. Copia de validación: `/tmp/opencode/bible-app`.
Motor nativo cargado con `NATIVAX_V8_LIB=/home/k3vin/Documents/nativax/tools/v8-spike/target/release/libnx_v8.so`.

## Qué se integró

- `V8Engine` en `packages/nativa_js` implementa `JavaScriptEngine` sobre un
  isolate V8 persistente en Rust.
- Puente de host: `__nx_host` nativo → dispatch JSON en Dart; se reutiliza el
  preludio `__nx.host` de QuickJS.
- Buffers binarios: `__nx.takeBuffer`/`putBuffer` copian entre V8 y el registro
  nativo de `NativeBuffers` (fetch/respuestas).
- Decodificación UTF-8 nativa (`__nx_decode_utf8`) con `simdutf` de V8. Antes
  `TextDecoder` era un bucle JS byte a byte.
- Selección opt-in:
  `NativaXRuntimeConfig(engineFactory: V8Engine.new)`. QuickJS sigue siendo el
  motor por defecto.
- `WebAssembly`, módulos ES, SAB y WebGL aún no están implementados en este
  backend; los scripts clásicos y el DOM sí funcionan.

## Medidas (Biblia, Linux profile/AOT)

| Métrica | QuickJS | V8 |
|---|---:|---:|
| `FIRST_VERSE` | 5.411 ms | 3.306–4.100 ms |
| RSS tras diccionario | ~250–300 MB | 600–780 MB |
| `/api/dict/ES` decode UTF-8 | bucle JS | nativo |
| Frames de carga de capítulo | 1,4–7,6 s | 1,8–3,0 s |

`FIRST_VERSE` mejora, pero el pico de RSS de V8 es mayor por el grafo de
objetos del diccionario de 16 MB. Con límite de heap de 512 MB V8 aborta; el
prototipo usa un suelo de 1 GB.

## Dónde está el coste de UI ahora

Trazas con `NATIVAX_TRACE_DRAW=1`:

```
FRAME total=2672ms build=1881ms raster=6ms builds=620 computes=9092
STYLE_METRICS samples=3483 ownMs=1140.7 avgUs=328 selectorsPer=15.7 hits=197
```

- El hilo principal (`bible_app`) está al **97–100 %**.
- Los hilos `V8 DefaultWorke` son GC/compilación (~13 %), no el JS de la app.
- El JS medido (`evaluate`/`callGlobal`) está en **50–150 ms** y los timers en
  **250–320 ms**.
- Los frames de **1,8–3,0 s** son `build` de Flutter: cascada/estilos y layout
  de miles de nodos al reconstruir `#verses`, no parseo JSON.
- `STYLE_SECTIONS` muestra `cascade` de **2–4,5 ms** en elementos del shell
  (botones/span) con ~16 selectores candidatos.
- El renderer reconstruye el árbol completo en cada batch de mutaciones
  (`document_view.dart`), y el capítulo inserta 31 versículos (~3.627 nodos).

## Arreglo de la cascada CSS (2026-10-24)

El HTML carga seis hojas (Font Awesome, flag-icons, Tailwind, app, knowledge,
qm-text) sin enlaces duplicados. El coste no era "copiar CSS": era que cada
elemento pagaba una clave estructural global y el caché de estilos no se
compartía entre subárboles equivalentes.

Cambios:

- Cada regla indexada sabe si depende de posición (`:first-*`, `:nth-*`,
  `:empty`, `:has`, ...) o de hermanos (`+`, `~`). Solo los elementos con
  candidatos estructurales pagan clave posicional.
- El caché de estilos calculados usa el **valor** del estilo del padre
  (`hashCode`), no su identidad, y las propiedades custom participan en
  `==`/`hashCode`.
- Los cambios de estado (`:hover`, `:focus`, ...) solo invalidan descendientes
  si el elemento puede ser el ancestro de una regla con estado.
- Los atributos que ningún selector lee (`title`, `data-strong`, ...) ya no
  fragmentan la firma.

Benchmark reproducible con las hojas reales de la app y un DOM de 5.924 nodos
(31 versículos densos):

| Métrica | Antes | Después |
|---|---:|---:|
| `STYLE total` | 9.417 ms | **1.362 ms (6,9×)** |
| candidatos/elemento | 39,3 | **6,8** |
| `styleCacheHits` | 94 | **4.982** |

Biblia real, V8, 20 s:

- style medio **343 → 206 µs/elemento**
- selectores/elemento **17 → 9,7**
- `FIRST_VERSE` **3.081 ms**
- ningún frame > 500 ms (antes: 1,5–3,8 s)
- RSS ~795 MB (V8)

## Hilos

Ahora mismo **no están separados**: V8 corre en el isolate de UI de Dart, igual
que QuickJS. Los hilos V8 visibles son el pool de GC/compilación. Separar el JS
en otro hilo exige que la API DOM deje de ser síncrona (o un puente nativo
síncrono con el hilo de UI), porque cada `getElementById`/`textContent`
devuelve un valor inmediato al script. Mover solo V8 sin cambiar eso bloquea la
UI esperando la respuesta y no mejora los frames.

## Próximo trabajo medible

1. Reducir la cascada por elemento (matching/`cascadedDeclarations`) o
   virtualizar los versículos fuera del viewport.
2. Evitar el rebuild global en cada mutación (dueño por subárbol /
   `ValueNotifier`).
3. Solo después, valorar el motor JS en un isolate con API DOM asíncrona.

## Comandos

```bash
cd /tmp/opencode/bible-app
flutter build linux --profile
NATIVAX_APP_ROOT=/tmp/opencode/bible-app \
NATIVAX_ENGINE=v8 \
NATIVAX_V8_LIB=/home/k3vin/Documents/nativax/tools/v8-spike/target/release/libnx_v8.so \
./build/linux/x64/profile/bundle/bible_app
```
