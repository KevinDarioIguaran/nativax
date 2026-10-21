# Ejemplo: NativaX Web Challenge

Port del ZIP `files.zip` a un ejemplo Flutter + NativaX. El HTML, el CSS y el
JavaScript se cargan desde `assets/` y se renderizan con el runtime propio de
NativaX (sin WebView).

## Estructura

- `assets/index.html`: página del reto.
- `assets/styles.css`: estilos originales.
- `assets/app.js`: lógica original, con pequeñas adaptaciones de degradación.
- `assets/compat.js`: shims mínimos para APIs de diagnóstico que NativaX no
  implementa todavía (`performance`, `requestAnimationFrame`,
  `getComputedStyle`, `Intl`, `screen`).
- `lib/main.dart`: host Flutter y `NativaXResourceLoader` que lee los assets.

## Ejecutar

```bash
cd examples/web-challenge
flutter run -d linux
```

Compilar:

```bash
flutter build linux
./build/linux/x64/release/bundle/nativax_web_challenge_example
```

Tests:

```bash
cd examples/web-challenge
flutter test
```

## Qué funciona

- Render HTML/CSS y layout básico, navegación por secciones, estadísticas,
  formularios, eventos, listas, tabs y el contador.
- Cambio de idioma/tema, `localStorage`, `matchMedia`, timers y URLs.
- El panel de APIs marca como `unsupported` lo que el runtime no expone.

## Limitaciones conocidas

El runtime todavía no implementa `fetch`, `WebSocket`, Canvas 2D, `<dialog>`,
`FormData`, `MutationObserver` ni reproducción real de audio/vídeo. El ejemplo
los detecta y muestra un estado de no soportado o un fallback, en lugar de
fingir que funcionan. Las imágenes/vídeo remotos también dependen de la política
del host y del `NativaXImageResolver`.

No se ha añadido ninguna API de red al runtime para este ejemplo.
