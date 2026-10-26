# Fidelidad visual 50projects50days — última ejecución

- Fecha: 2026-10-24
- Comando: `dart run debug/engines/visual_comparison/bin/visual_check.dart --suite 50projects50days --out .visual/runs/50projects50days` (evaluación final regenerada con `--resume`)
- Referencia: Google Chrome 152.0.7977.82 headless; viewport 800x900, DPR 1, animaciones congeladas
- Fixtures: `debug/engines/visual_comparison/fixtures/50projects50days` @ `c92b0bc3a87fc95d44b89552b7b6a2eeb36ca481` (MIT)
- Páginas: **51** — PASS **6**, WARN **5**, FAIL **40**, INVALID **0**
- Overall: media **52.59 %**, mediana **48.54 %**
- Medias por categoría: posición **36.20 %**, layout **53.04 %**, color **45.24 %**, diseño **96.72 %**
- Píxeles: **36,720,000** comparados, **6,569,980** con ΔE > 2 (media 17.89 %); tinta no coincidente media 62.82 %

Calibración del juicio: `--self-check` (Chromium contra una segunda captura de Chromium) da **100 % / PASS** en las 5 categorías. Sin esa calibración el juicio no se considera válido.

## Tabla de resultados

| Página | Veredicto | Overall | Posición | Layout | Color | Diseño | Píxeles | Tinta | ΔE medio |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `3d-boxes-background` | FAIL | 71.56 % | 27.78 % | 85.07 % | 90.83 % | 100.00 % | 9.97 % | 100.00 % | 6.46 |
| `animated-countdown` | FAIL | 52.56 % | 0.00 % | 42.18 % | 99.63 % | 100.00 % | 0.16 % | 100.00 % | 0.09 |
| `animated-navigation` | FAIL | 39.01 % | 28.52 % | 47.20 % | 6.29 % | 98.17 % | 1.13 % | 1.96 % | 0.67 |
| `auto-text-effect` | FAIL | 48.54 % | 0.00 % | 41.17 % | 87.26 % | 95.84 % | 2.11 % | 100.00 % | 0.34 |
| `background-slider` | FAIL | 37.33 % | 0.00 % | 76.03 % | 0.00 % | 96.79 % | 100.00 % | 100.00 % | 51.81 |
| `blurry-loading` | WARN | 70.70 % | 50.00 % | 52.85 % | 100.00 % | 98.98 % | 0.00 % | 0.00 % | 0.00 |
| `button-ripple-effect` | PASS | 94.95 % | 100.00 % | 91.33 % | 100.00 % | 83.67 % | 0.19 % | 15.03 % | 0.10 |
| `content-placeholder` | FAIL | 56.78 % | 10.48 % | 68.45 % | 72.42 % | 100.00 % | 6.91 % | 39.30 % | 0.33 |
| `custom-range-slider` | FAIL | 23.11 % | 0.00 % | 28.99 % | 3.06 % | 90.94 % | 2.87 % | 14.37 % | 1.98 |
| `dad-jokes` | PASS | 93.02 % | 94.64 % | 88.96 % | 92.96 % | 97.96 % | 3.75 % | 9.30 % | 1.24 |
| `double-click-heart` | FAIL | 67.78 % | 85.03 % | 90.89 % | 0.00 % | 100.00 % | 23.85 % | 99.66 % | 8.79 |
| `double-vertical-slider` | FAIL | 24.17 % | 15.98 % | 15.03 % | 0.00 % | 99.12 % | 34.55 % | 100.00 % | 19.85 |
| `drag-n-drop` | PASS | 98.77 % | 100.00 % | 99.97 % | 100.00 % | 91.84 % | 0.00 % | 0.00 % | 0.00 |
| `drawing-app` | PASS | 92.18 % | 100.00 % | 94.39 % | 81.10 % | 90.57 % | 2.22 % | 21.58 % | 1.12 |
| `drink-water` | FAIL | 58.02 % | 53.06 % | 77.56 % | 15.32 % | 100.00 % | 6.83 % | 41.61 % | 4.40 |
| `event-keycodes` | FAIL | 91.91 % | 100.00 % | 86.09 % | 89.21 % | 91.84 % | 0.27 % | 99.21 % | 0.13 |
| `expanding-cards` | WARN | 77.22 % | 62.34 % | 62.09 % | 100.00 % | 99.26 % | 0.00 % | 0.00 % | 0.00 |
| `faq-collapse` | FAIL | 24.17 % | 2.93 % | 20.48 % | 10.00 % | 97.63 % | 24.88 % | 80.30 % | 14.53 |
| `feedback-ui-design` | FAIL | 26.37 % | 0.00 % | 17.90 % | 24.98 % | 98.39 % | 40.81 % | 95.66 % | 4.38 |
| `form-input-wave` | FAIL | 33.75 % | 0.00 % | 38.08 % | 30.89 % | 97.34 % | 31.39 % | 63.06 % | 9.49 |
| `github-profiles` | WARN | 70.91 % | 92.86 % | 79.63 % | 17.25 % | 98.98 % | 2.59 % | 37.34 % | 0.63 |
| `good-cheap-fast` | FAIL | 71.16 % | 31.49 % | 77.59 % | 94.35 % | 98.99 % | 1.72 % | 79.80 % | 0.65 |
| `hidden-search` | PASS | 96.05 % | 98.63 % | 93.99 % | 100.00 % | 88.44 % | 0.04 % | 0.16 % | 0.13 |
| `hoverboard` | PASS | 98.76 % | 100.00 % | 100.00 % | 99.92 % | 91.84 % | 3.89 % | 0.00 % | 0.14 |
| `image-carousel` | FAIL | 58.69 % | 66.67 % | 58.46 % | 27.32 % | 95.47 % | 35.67 % | 94.61 % | 9.58 |
| `incrementing-counter` | FAIL | 47.36 % | 39.30 % | 36.90 % | 38.00 % | 100.00 % | 1.48 % | 79.80 % | 0.82 |
| `insect-catch-game` | FAIL | 39.13 % | 16.98 % | 35.87 % | 34.61 % | 97.49 % | 2.61 % | 81.53 % | 2.36 |
| `kinetic-loader` | WARN | 79.77 % | 100.00 % | 100.00 % | 23.97 % | 91.84 % | 0.35 % | 50.49 % | 0.26 |
| `live-user-filter` | WARN | 81.11 % | 73.54 % | 72.47 % | 90.09 % | 98.52 % | 2.66 % | 32.37 % | 0.97 |
| `mobile-tab-navigation` | FAIL | 28.47 % | 29.43 % | 15.78 % | 0.00 % | 99.37 % | 99.24 % | 99.24 % | 33.91 |
| `movie-app` | FAIL | 56.09 % | 35.91 % | 49.18 % | 62.67 % | 99.32 % | 1.08 % | 12.90 % | 0.16 |
| `netflix-mobile-navigation` | FAIL | 21.12 % | 5.08 % | 15.56 % | 0.00 % | 99.56 % | 0.70 % | 96.20 % | 0.63 |
| `notes-app` | FAIL | 26.11 % | 0.00 % | 24.41 % | 20.04 % | 91.84 % | 0.45 % | 64.64 % | 0.26 |
| `password-generator` | FAIL | 26.15 % | 4.46 % | 22.03 % | 15.04 % | 96.29 % | 15.00 % | 61.33 % | 7.12 |
| `password-strength-background` | FAIL | 43.73 % | 10.43 % | 28.60 % | 76.35 % | 86.22 % | 2.40 % | 98.30 % | 1.26 |
| `pokedex` | FAIL | 22.60 % | 0.00 % | 25.33 % | 0.00 % | 100.00 % | 92.72 % | 94.87 % | 16.90 |
| `progress-steps` | FAIL | 57.53 % | 57.35 % | 64.89 % | 23.45 % | 100.00 % | 1.11 % | 66.35 % | 0.58 |
| `quiz-app` | FAIL | 55.09 % | 49.60 % | 64.71 % | 24.33 % | 98.13 % | 5.39 % | 7.66 % | 4.11 |
| `random-choice-picker` | FAIL | 37.09 % | 0.00 % | 48.51 % | 32.17 % | 96.64 % | 7.12 % | 59.14 % | 4.87 |
| `random-image-generator` | FAIL | 88.35 % | 67.23 % | 94.83 % | 100.00 % | 98.20 % | 1.77 % | 97.07 % | 0.77 |
| `rotating-nav-animation` | FAIL | 40.38 % | 36.73 % | 27.76 % | 25.00 % | 98.56 % | 38.11 % | 95.08 % | 26.98 |
| `scroll-animation` | FAIL | 54.86 % | 10.56 % | 45.87 % | 91.72 % | 100.00 % | 15.12 % | 32.49 % | 8.03 |
| `simple-timer` | FAIL | 50.63 % | 0.00 % | 41.47 % | 98.50 % | 90.47 % | 0.65 % | 100.00 % | 0.28 |
| `sound-board` | FAIL | 19.45 % | 0.00 % | 10.00 % | 5.81 % | 100.00 % | 20.48 % | 100.00 % | 5.94 |
| `split-landing-page` | FAIL | 31.70 % | 28.57 % | 27.11 % | 0.00 % | 100.00 % | 99.29 % | 99.29 % | 79.09 |
| `sticky-navigation` | FAIL | 32.75 % | 30.56 % | 22.25 % | 7.81 % | 99.69 % | 93.10 % | 93.10 % | 44.28 |
| `testimonial-box-switcher` | FAIL | 30.75 % | 0.00 % | 38.66 % | 16.79 % | 99.72 % | 34.85 % | 58.35 % | 27.29 |
| `theme-clock` | FAIL | 37.76 % | 0.00 % | 35.40 % | 49.16 % | 99.03 % | 4.40 % | 95.69 % | 3.92 |
| `toast-notification` | FAIL | 22.42 % | 0.00 % | 24.72 % | 0.00 % | 100.00 % | 0.91 % | 60.39 % | 0.74 |
| `todo-list` | FAIL | 31.01 % | 2.11 % | 37.02 % | 19.81 % | 95.45 % | 19.30 % | 86.55 % | 4.31 |
| `verify-account-ui` | FAIL | 43.32 % | 28.14 % | 61.42 % | 9.12 % | 94.44 % | 16.38 % | 87.97 % | 9.91 |

## Mejores y peores

| Página | Veredicto | Overall | Por qué |
|---|---|---:|---|
| `drag-n-drop` | PASS | 98.77 % | pos 100.0, layout 100.0, color 100.0, tinta 0.0 % |
| `hoverboard` | PASS | 98.76 % | pos 100.0, layout 100.0, color 99.925, tinta 0.0 % |
| `hidden-search` | PASS | 96.05 % | pos 98.6, layout 94.0, color 100.0, tinta 0.2 % |
| `button-ripple-effect` | PASS | 94.95 % | pos 100.0, layout 91.3, color 100.0, tinta 15.0 % |
| `dad-jokes` | PASS | 93.02 % | pos 94.6, layout 89.0, color 92.963, tinta 9.3 % |
| `sound-board` | FAIL | 19.45 % | pos 0.0, layout 10.0, color 5.812, tinta 100.0 % |
| `netflix-mobile-navigation` | FAIL | 21.12 % | pos 5.1, layout 15.6, color 0.0, tinta 96.2 % |
| `toast-notification` | FAIL | 22.42 % | pos 0.0, layout 24.7, color 0.0, tinta 60.4 % |
| `pokedex` | FAIL | 22.60 % | pos 0.0, layout 25.3, color 0.0, tinta 94.9 % |
| `custom-range-slider` | FAIL | 23.11 % | pos 0.0, layout 29.0, color 3.064, tinta 14.4 % |

## Casos concretos verificados a mano

- `animated-countdown`: el contenedor `position: fixed` centrado con `transform: translate(-50%, -50%)` queda fuera de pantalla en NativaX (cajas en `-400, -378`); la captura de NativaX está en blanco. Posición **0 %**, tinta **100 %**. Es un fallo real del runtime, no del juicio.
- `background-slider`: contenedor de 560x630 centrado en Chromium (`x=120`) y en `x=0` en NativaX; los slides quedan desplazados 120 px y los píxeles coinciden al **0 %**.
- `hidden-search`: tras corregir el viewport de Chromium, posición **98,63 %**, color **100 %**, solo **0,04 %** de píxeles distintos y **0,16 %** de tinta. PASS.
- `event-keycodes`: geometría **100 %** pero el **99,21 %** de la tinta visible difiere; el veredicto baja a FAIL por la regla de tinta. El overall (91,9 %) por sí solo habría mentido.

## Lectura

- La categoría **diseño** (estilos computados) es alta (media 96,72 %); el problema dominante es **posicionamiento/layout**, no la cascada de estilos.
- **40 de 51** páginas fallan; no es una regresión: es la primera línea base medida con un juez calibrado. Las páginas con recursos externos (imágenes de Unsplash, Font Awesome, Google Fonts) se comparan sin red, así que parte del contenido remoto está ausente en ambos motores.
- `INVALID = 0`: las 51 comparaciones cumplieron viewport, DPR, tamaño de captura y cobertura del documento.

## Limitaciones

- Solo se compara el viewport capturado (800x900); el documento más alto se recorta y se reporta en `document-coverage`.
- Animaciones/transiciones congeladas; estados que dependen del tiempo no se juzgan.
- Sin red en ninguno de los dos motores: fuentes web, CDN e imágenes remotas no se cargan.
- No se juzgan vídeo, audio, canvas animado ni WebGL.
- El reporte crudo (`report.json`, `results.json`, capturas, `diff.png`, CSV por página) está en `.visual/runs/50projects50days/`, ignorado por git; se regenera con el comando de arriba.
