# perf/quickjs-jit

## Prerrequisito: puente sin JSON

El puente QuickJS **no** cumple el prerrequisito: cada llamada hace
`JSON.stringify([name, args])` en JS y `jsonDecode` + `jsonEncode` en Dart
(`quickjs_engine.dart`, `nativaxHostPrelude` / `_dispatchHost`).

Medición release con `NATIVAX_ENGINE=quickjs`, 12 s:

- 11.000 llamadas host; las más caras:
  - `q.all`: 43 llamadas, 339 ms total, 23,9 ms máximo, 62 KB
  - `doc.byId`: 433 llamadas, 206 ms total, 3,4 ms máximo, 23 KB
  - `layout.box`: 100 llamadas, 71 ms total, 16,4 ms máximo, 26 KB
  - `node.get`: 5.493 llamadas, 13 ms total, 1,4 ms máximo, 560 KB
  - `node.set`: 320 llamadas, 26 ms total, 1,0 ms máximo, 115 KB
- JS acumulado: **558 ms**; máximo de una entrada JS: **77 ms**.
- Frame largo reproducido:
  `BIBLE_FRAME at=11003ms total=7241ms build=296ms raster=3ms`.
  No hay llamada JS >77 ms ni host >24 ms: los ~6,9 s restantes están
  fuera de build/raster y del puente, en la espera del compositor/GL.
  El JIT no puede eliminar ese frame.

## Decisión

No se integra `longbridge/quickjs-jit` todavía. El JIT no acelera
`JSON.stringify/parse`, y el frame de 6,7 s no es tiempo de JS. Primero hay
que sustituir el puente JSON por llamadas nativas con ids/buffers; después
se puede medir si el JS puro justifica JIT.

No se borra V8 en esta rama porque QuickJS actual no cumple fluidez
(54-61 frames/6 s frente a 155-309 de V8).
