# Depuración CPU — app de la Biblia

Fecha: 2026-10-24. Build: Flutter Linux **profile/AOT**.
Copia de la app en `/tmp/opencode/bible-app`; original intacta.
Motor: este checkout (`nativa_render`, `nativa_dom_bindings`).

## Cómo se midió

```bash
flutter build linux --profile --dart-define=NATIVAX_TRACE_HOST=true
cd build/linux/x64/profile/bundle
DISPLAY=:1 NATIVAX_APP_ROOT=/home/k3vin/Documents/bible/app ./bible_app
```

- `NATIVAX_TRACE_HOST=true`: log `HOST_FETCH start/end` con URL, estado y bytes.
- `NATIVAX_TRACE_DRAW=1`: log `DRAW BUILD/LAYOUT/PAINT/FRAME` con ms.
- Timer Dart cada 1 s: `VISIBLE` con el texto que está en pantalla y
  `verses=N`.
- CPU externa cada 0,5 s leyendo `/proc/<pid>/stat` (utime+stime), fuera del
  isolate de UI, para que no la oculte un bloqueo.

## Línea de tiempo real

| Tiempo | CPU | Pantalla / evento |
|---:|---:|---|
| 0–0,8 s | 100 % | arranque |
| 0,8–1,2 s | 100 % | `RUNTIME_READY` (HTML+CSS+JS) |
| 1,9–2,8 s | 100 % | shell: cabecera, menú, lista de libros; `verses=0` |
| 2–3 s | 100 % | `/api/books` 7,9 KB; `/api/books/10/text` **450 KB**; `/api/session` 23 B |
| 3–5,3 s | 100 % | shell, sin versículos |
| **5,3 s** | 100 % | `FIRST_VERSE`; `verses=31`; “Cap. 1/50” |
| **6,0 s** | 100 % | **`/api/dict/ES` termina: 16.225.787 bytes** |
| **6,0–12,8 s** | **100–116 %** | **UI congelada: no hay `VISIBLE`, no hay frames** |
| 12,8 s | 100 % | vuelve a responder; frame de **1.407 ms**, `build=693 ms`, `raster=7 ms` |
| 13,6 s | 100 % | **`/api/dict/ES` otra vez: 16.225.787 bytes** |

CPU externa de una corrida equivalente:

```
cpu=104%  cpu=96%  cpu=96%  cpu=102%  cpu=106%  cpu=106%
cpu=106%  cpu=104%  cpu=100%  cpu=106%  cpu=100%  cpu=100%
... 15 s seguidos ...
```

No son picos: es CPU saturada de forma sostenida.

## Causa exacta

El frame largo no es layout ni paint:

```
BIBLE_FRAME total=1407ms build=693ms raster=7ms
```

El hueco de **6,8 s sin `VISIBLE`** empieza justo después de que termina una
respuesta de **16,2 MB** (`/api/dict/ES`) y termina antes del siguiente frame.
El hilo de UI está bloqueado fuera de Flutter; el temporizador de Dart tampoco
corre. El camino de la app es:

- `core/load.js` `apiGetJSON('/api/dict/' + L)` (diccionario completo).
- `core/load.js` `bookFull()` pide `/api/books/{bk}/text` (libro completo) y
  luego recorre todos los capítulos escribiendo en el IndexedDB en memoria.
- `prefetchNeighbor()` y la carga del diccionario se repiten; el mismo
  `/api/dict/ES` de 16,2 MB se pide dos veces en 14 s.

QuickJS parsea y procesa ese JSON en el **hilo de UI**. Con 16 MB, más el
libro completo y su caché en memoria, el resultado es 100 % CPU, UI congelada
y, en corridas largas, `InternalError: out of memory` (límite de 512 MB).

## Lo que NO es

- No es CSS: el estilo quedó en **0,34 ms/elemento**.
- No es layout: `build=693 ms` en el frame que sí llega.
- No es paint: `raster=7 ms`.
- No es GPU.
- No es falta de virtualización: la lista de libros solo materializa ~20 filas.

## Qué haría falta para arreglarlo

1. **App**: no pedir el diccionario de 16 MB completo ni el libro completo en
   cada arranque; usar `/api/books/{bk}/chapters/{ch}/verses` y cargar el
   diccionario por consulta. Esto es lo que hace la web normal en ~1 s.
2. **Motor**: si se quiere soportar JSON grande sin bloquear, el parseo y la
   caché tienen que salir del hilo de UI (streaming/binario/isolate). QuickJS
   y el IndexedDB en memoria actuales no lo hacen.
3. **UX**: mostrar “cargando capítulo” mientras llega el JSON; no deja la
   pantalla congelada sin feedback.

Mientras no se ataque el JSON de 16 MB, la app va a seguir usando 100 % CPU y
congelándose aunque el CSS y el layout estén optimizados.
