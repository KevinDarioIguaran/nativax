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

- style medio **343 → 239 µs/elemento**
- selectores/elemento **17 → 9,8**
- `FIRST_VERSE` **3.081–3.777 ms**
- el pico de estilo baja de **3,8 s a 1,4 s**; queda un frame de layout de
  **1,33 s** (build, no estilo) y frames de ~1,1 s que en su mayoría son
  espera de compositor (build 58–170 ms)
- RSS ~795 MB (V8)

## IndexedDB: el coste real de CPU (2026-10-24)

Las trazas de timers (`NATIVAX_TRACE_TIMERS=1`) mostraron cientos de callbacks
de `IDBTransaction._maybeFinish` de **200–330 ms**. La causa estaba en el
polyfill: cada transacción `readwrite` hacía `cloneStore()` de **todo** el
object store (`structuredClone` de cada registro) para poder abortar. La app
cachea el libro completo capítulo a capítulo, así que el coste crecía de forma
cuadrática.

Cambios:

- Snapshot de deshacer perezoso: al primer write se guarda la **referencia** al
  array de registros, `next` e índices; el write copia el array y reemplaza el
  registro (no muta el objeto antiguo). `abort()` restaura el snapshot.
- Las tareas de IndexedDB se agrupan en una cola con presupuesto de 4 ms por
  macrotarea, en vez de un `setTimeout` por request.
- Test de abort añadido (`IndexedDB abort restores...`).
- `getAttribute`/`className` ya no compilan regex por llamada; `ClassList`
  cachea tokens por valor de `class`.
- `processWhiteSpace` tiene fast-path sin regex.

Medido en la Biblia con V8:

| Métrica | Antes | Después |
|---|---:|---:|
| timers IDB | 200–330 ms cada uno | 0–22 ms (pico aislado 99 ms) |
| hilo UI | ~98 % | 28–51 % |
| hilo V8 GC | ~35 % | ~1,5 % |
| RSS | ~788 MB | 612–615 MB |
| `FIRST_VERSE` | 2,1–2,3 s | 1,99–2,22 s |
| peor frame | 1,5–3,8 s | 824 ms al arrancar; 350–467 ms después |

## Comparación final tras IndexedDB (2026-10-24)

Misma copia y mismas hojas, 25 s de ejecución:

| | V8 | QuickJS |
|---|---:|---:|
| CPU del hilo UI en reposo (muestra de 3 s) | **5,7 %** | 97,3 % |
| RSS | 500–620 MB | 290–368 MB |
| `FIRST_VERSE` | ~2,0–2,2 s | **~1,7 s** |
| peor frame | 824 ms al arrancar; 350–467 ms después | **229 ms** |

Con `low_memory_notification` cada 15 s, V8 bajó de ~600 MB a **497 MB** a los
20 s (el heap útil era ~129–155 MB; el resto es Flutter/IDB nativo). QuickJS
sigue consumiendo menos memoria, pero en esta carga se queda al 97 % de CPU y
una corrida de 55 s terminó sin proceso. El backend V8 sigue siendo opt-in;
QuickJS es el default.

## Rebuild incremental (2026-10-24)

`NativaXWidgetCache` reutiliza el `Widget` ya construido por elemento. Una
mutación invalida el camino hasta la raíz; los hijos no afectados se devuelven
como la **misma instancia**, así Flutter omite su build. Los cambios de
atributos/clase invalidan el subárbol; los de texto solo el camino.

Medido en la Biblia (V8, 20 s):

- frames de texto/timers: **0–100 builds** (antes 300–500).
- frame de reemplazo de capítulo: 378–628 builds; sigue costando **~300–400 ms**
  porque el layout de los 31 versículos se recalcula aunque los widgets se
  reutilicen.
- `FIRST_VERSE` ~1,84 s.
- Test de regresión: 80 filas, cambiar un texto construye **<20** elementos.

El siguiente cuello sigue siendo **layout**, no build.

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
