# Estado actual

Última actualización: 2026-10-21 (sesión 21: checkpoint estable y Fase 0 de
presentación). Tests: **301** en total (`./tools/test_all.sh`), incluido el
probe de juego real y el test de estadísticas de presentación.

## Resumen

| Área | Estado | Evidencia |
|---|---|---|
| Núcleo JS (QuickJS-ng + FFI) | 🟢 estable | 52 tests; registro privado de callbacks en el puente C |
| WebAssembly (wasm3) | 🟢 B4 | 11 unitarios + 3 E2E; Rapier 0.19.3 y worker real (103 cuerpos ~45 Hz) |
| DOM | 🟢 estable | 37 tests; pseudoelementos, `:hover`/`:active`/`:target`, validación, dialog/details |
| HTML | 🟢 estable | 39 tests; foreign content (SVG/MathML) |
| CSS | 🟢 estable | 39 tests; grid, `calc()`, `::before/::after`, keyframes, transiciones, `@supports` |
| Bindings JS↔DOM | 🟢 amplio | 49 tests; ~3.800 líneas de plataforma web (ver docs/javascript-supported.md) |
| Renderer Flutter | 🟢 amplio | 34 tests; grid, sticky, SVG, canvas 2D, animaciones, filtros, DnD |
| Runtime público (`nativax`) | 🟢 | 27 tests; red por política, servicios de plataforma, errores no fatales |
| Juego real (B5) | 🟢 jugable | bundle Vite sin modificar, 3 workers, Rapier, Start real, frames GL y captura no plana |
| Presentación WebGL | 🟡 línea base | 1280×720 DPR 1.0: shown 26,3–29,1 fps; present p95 67–74 ms; objetivo 45 fps no alcanzado |
| Rendimiento 7× | 🔴 registrado | Rapier 180 pasos: 328,5 ms (wasm3) vs 30,7 ms (V8); gap 10,7× |
| Ejemplo web-challenge | ✅ original | HTML/CSS/JS **sin modificar**: 46/52 comprobaciones propias en verde |
| Seguridad | 🟢 | `tools/security`: 14 PASS / 0 FAIL / 1 SKIP |
| Conformidad | 🟡 | Test262 97,93 %; html5lib 96,95 %; URL 70,98 %; DOM 58,30 %; CSS 10,38 %; tree 39,97 % |
| Plataformas | 🟡 solo Linux | build Linux verificado; resto sin probar |

## Checkpoint estable — Fase 0 de presentación

- **Versión por defecto:** DPR nativo 1.0, `backdrop-filter` activo y
  `GlSurfaceView`/`RawImage` como camino de presentación. No se bajó resolución
  y no se cambió el juego.
- **Métricas opt-in:** el HUD y el JSONL solo se activan con
  `NATIVAX_METRICS=1` o `NATIVAX_METRICS_FILE`. `NATIVAX_GAME_DPR`,
  `NATIVAX_NO_BACKDROP`, `NATIVAX_AUTOSTART` y `NATIVAX_FIXED_WINDOW` son flags
  de medición.
- **Medición preliminar a 1280×720:** render 34,7–42,6 fps, shown 26,3–29,1,
  UI 32–34, present p95 67–74 ms, decode p95 35–37 ms, build p95 2,9 ms,
  raster p95 15,1 ms, jank 1,2 %. El criterio de 45 fps/p95 ≤ 25 ms **no se
  alcanza**. Datos y advertencias en `progress/phase0-presentation.md` y
  `benchmarks/game-player-phase0/`.
- **A/B de backdrop:** no concluyente; la corrida exploratoria cambió de tamaño
  de ventana. Pendiente repetir 3×30 s con ventana fija.
- **Fase 1 (textura nativa):** no iniciada. Se dejó el checkpoint estable a
  petición del usuario; el siguiente paso documentado es
  `FlPixelBufferTexture`/`FlTextureRegistrar` detrás de una interfaz genérica,
  verificando antes el soporte de texturas externas en Impeller Linux.
- **Tests:** `./tools/test_all.sh` en verde con el juego cerrado; se añadió
  `gl_stats_test.dart` y se omiten ejemplos sin directorio `test/`.

## Comparación con Chrome (web-challenge)

`examples/web-challenge/test/screenshot_test.dart` renderiza la página con
fuentes del sistema; con `NATIVAX_SHOT_DIR` carga los archivos originales.
Formularios, UI, Media (canvas, SVG), CSS & render y Diagnóstico coinciden
visualmente con Chrome salvo:

- vídeo/audio (sin pipeline multimedia: se reportan bloqueados);
- emojis en capturas de test (en la app real las pone la fuente del sistema).

"Run all" con el `app.js` original: **46 ok, 4 blocked, 2 unsupported**.
Bloqueados: vídeo y audio (multimedia) y fetch/WebSocket cuando la red está
denegada (el ejemplo real habilita sus hosts con `IoNetwork`). No
soportados: `share` y `geolocation`.

## Fase 4 — en curso

- [x] Test262 (97,93 %), html5lib (96,95 %) y URL (70,98 %) por encima del 70 %.
- [ ] WPT `dom/nodes`: **58,30 %** (objetivo 70 %).
- [ ] WPT `css/selectors`: **10,38 %** (objetivo 70 %).
- [ ] WPT tree construction: **39,97 %** (objetivo 70 %).
- [x] Reparse de `<style>` al insertar/editar hojas (prerrequisito de CSSOM y
  de la UI de frameworks).
- [x] CSSOM básico: `document.styleSheets`, `insertRule`, `deleteRule`,
  `cssRules`, `selectorText`, `rule.style` y reparse dinámico.
- [ ] CSSOM completo: `@media` anidado, reglas huérfanas, enlaces externos y
  `getComputedStyle` con todos los longhands.
- [ ] Adoption agency/foster parenting/tabla/template/foreign content.
- [x] `Attr`, `createAttribute`, `DOMImplementation`, `Document` multi-documento y `classList` vivo.
- [ ] Namespaces completos en selectores/atributos, `Range`, `DOMParser` e iframes.

## Estado del juego real (B5)

- El HTML/CSS/JS de producción de `examples/threejs-multiplayer-starter/dist`
  se carga sin modificarlo.
- Arrancan el hilo principal, el render worker y el physics worker.
- Se cargan texturas, cubemap y GLTF con `fetch` + `createImageBitmap`.
- Rapier crea el heightfield, el jugador y 100 esferas; el worker mantiene
  ~45 Hz con 103 cuerpos.
- La pantalla de carga llega a "Ready!" y el botón de inicio queda visible.
- **Resuelto:** `RenderCssBox` aplicaba `constraints.enforce(wanted)` en el
  sentido contrario; ahora `wanted.enforce(constraints)`. El canvas fijo
  full-screen respeta el viewport.
- `packages/nativax/test/game_play_test.dart` ya no está saltado: pulsa Start
  con un tap real, espera a que desaparezca el loading-screen, comprueba que
  el render worker presenta frames y valida que la captura no es un color
  plano (fox, terreno y UI).

## Lo que falta para un navegador "completo"

1. Multimedia (`video`/`audio`) y Web Audio real: hoy `AudioContext` es un
   grafo silencioso y `decodeAudioData` rechaza; requiere un plugin por
   plataforma (no existe uno oficial para Linux).
2. Canvas: `drawImage` de `<img>`, `getImageData`/`putImageData`,
   `toDataURL`.
3. Shadow DOM completo (hoy es una fachada sobre light DOM), CSSOM
   (`document.styleSheets`), `createElementNS` completo.
4. WebAssembly: memoria/tabla/global importadas, exportaciones de tabla/global,
   SIMD y hilos/atomics.
5. Layout: tablas reales, `float`, columnas, `writing-mode`, colapso de
   márgenes padre/hijo, `align-content` en flex, subgrid.
6. Fuentes web (`@font-face`), selección de texto, `contenteditable`.
7. Workers: `importScripts` síncrono desde URL, WebSocket en workers e
   interrupción nativa de un worker ocupado; `dynamic import`/módulos ES
   completos.
8. Parser HTML: adoption agency completa, foster parenting, quirks.
9. Plataformas: Android/iOS/Windows/macOS sin compilar.

## Comandos de verificación

```bash
./tools/test_all.sh
(cd tools/security && dart run bin/security.dart run)
(cd tools/conformance && dart run bin/run_wpt.dart --dirs dom/nodes --limit 100000)
(cd examples/web-challenge && NATIVAX_SHOT=/tmp/shot.png NATIVAX_SHOT_DIR=<dir> flutter test test/screenshot_test.dart)
```
