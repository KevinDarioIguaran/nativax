# Fidelidad visual contra un navegador

NativaX se compara visualmente contra Chromium sin abrir ninguna ventana y sin
usar WebView, Chromium embebido ni un servidor local. Chromium es solo el
instrumento de referencia: `google-chrome --headless=new` produce la captura
patrón y NativaX produce la suya con `flutter test` +
`RenderRepaintBoundary.toImage()`.

La herramienta vive en `tools/visual` y su contrato completo (fórmulas,
umbrales y formato de salida) está en
[`tools/visual/README.md`](../tools/visual/README.md).

## Qué mide

| Categoría | Qué responde | Cómo se mide |
|---|---|---|
| **Posición** | ¿Cada caja está donde debe? | `getBoundingClientRect` en ambos motores; tolerancia 2 px con caída lineal hasta 16 px; peso `sqrt(área)`. |
| **Layout** | ¿Cada caja mide lo que debe y fluye igual? | Diferencias de ancho/alto, IoU y error de altura del documento. |
| **Color** | ¿Se usan los mismos colores? | Media y paleta dominante (top 5) por elemento, ΔE76 en Lab D65. Se muestrea la caja propia de cada motor, así un desplazamiento no se cuenta dos veces. |
| **Diseño** | ¿El estilo computado coincide? | 27 propiedades normalizadas: tipografía, color, fondo, bordes, radios, sombra, display, posición, opacidad y overflow. |
| **Entorno** | ¿La comparación es válida? | Viewport, DPR, tamaño de captura, cobertura del documento, errores JS y recursos externos bloqueados. |
| **Píxeles** | ¿Qué cambia píxel a píxel? | ΔE76 por píxel, cubos 2/5/10/20, filas, teselas 16×16, imagen de diferencias y porcentaje de tinta no coincidente. |

El resultado global pondera posición 30 %, layout 30 %, color 25 % y diseño
15 %, renormalizando si el color no es medible. Un fallo de entorno duro deja
la página en `INVALID` en vez de inventar una nota.

## Por qué no basta el porcentaje de píxeles

Una página casi vacía puede coincidir en el 99,8 % de los píxeles y aun así
estar completamente en blanco. Por eso el reporte incluye
`ink_mismatch_pct`: calcula el fondo dominante, considera "tinta" todo píxel
que se separa de él en cualquiera de las dos capturas y mide qué fracción de
esa tinta difiere. Una captura en blanco con texto en Chromium da 100 % de
tinta no coincidente aunque el total de píxeles sea 0,2 %.

## Suites de ejemplo

El catálogo completo tiene **300 páginas** con `--all`: 51 de
50projects50days, 27 de MDN CSS, 67 de MDN learning-area, 21 de Odin Project y
134 de MDN DOM/UI. Las cuatro suites externas son CC0/MIT, se descargan con
commit pinneado en `.visual/suites/` y no se redistribuyen. Catálogo y fuentes:
[`progress/reports/visual-catalog-latest.md`](../progress/reports/visual-catalog-latest.md).

`tools/visual/fixtures/50projects50days` contiene una copia íntegra y sin
modificar de los 51 proyectos HTML/CSS/JS de
[bradtraversy/50projects50days](https://github.com/bradtraversy/50projects50days)
en el commit `c92b0bc3a87fc95d44b89552b7b6a2eeb36ca481` (licencia MIT y aviso
de procedencia incluidos). Son fixtures de prueba: NativaX no los carga desde
el runtime público.

```bash
dart run tools/visual/bin/visual_check.dart --suite 50projects50days
dart run tools/visual/bin/visual_check.dart examples/test-pages/form.html
dart run tools/visual/bin/visual_check.dart --self-check --limit 1
```

## Salidas

Cada ejecución deja en `.visual/latest/` (ignorado por git):

- `report.md`: resumen legible y peores causas raíz.
- `report.json`: informe completo.
- `results.json`: **tabla de resultados**, una fila por página con una lista
  `columns` estable y todas las métricas.
- `summary.csv`: la misma tabla en CSV.
- `pages/<suite>/<página>/`: capturas `chrome.png`/`nativax.png`,
  `diff.png`, sondas JSON, `elements.json`/`.csv`, `positions.csv`,
  `colors.csv` y `pixels.json` (más `pixels.csv` con `--pixel-csv`).

## Línea base (2026-10-24)

Las 51 páginas vendorizadas, a 800x900 y sin red, dieron **6 PASS, 5 WARN,
40 FAIL y 0 INVALID**. Overall medio **52,59 %** (mediana 48,54 %); medias de
posición **36,20 %**, layout **53,04 %**, color **45,24 %** y diseño
**96,72 %**. Se compararon 36.720.000 píxeles; 6.569.980 superaron ΔE 2
(17,89 % de media) y la tinta no coincidente promedió 62,82 %. El fallo
dominante es layout/posicionamiento, no la cascada de estilos.

No es una tasa de compatibilidad ni una regresión: es la primera línea base
medida con el juez calibrado. El detalle por página, comandos y casos
concretos están en
[`progress/reports/visual-50projects50days-latest.md`](../progress/reports/visual-50projects50days-latest.md).

## Calibración del viewport de Chromium

En Chromium headless, `--dump-dom` y `--screenshot` no coinciden en el
viewport de layout: el volcado informa `innerHeight = ventana − 87 px` y la
captura pinta a la altura completa de la ventana. El juicio calibra ese
desfase al arrancar, mide con `alto + desfase` y captura con `alto`, de modo
que las cajas del sondeo y los píxeles pertenecen al mismo viewport. Sin esa
corrección, páginas con `100vh`, centrado con `fixed` o alturas porcentuales
se medían contra un viewport y se pintaban contra otro. El test
`tools/visual/test/chrome_e2e_test.dart` lo verifica con una caja centrada.

## Limitaciones declaradas

- Se compara el viewport capturado; `--height` controla su alto y
  `document-coverage` avisa si la página es más larga.
- Las animaciones y transiciones se congelan en ambos motores.
- La red está bloqueada en ambos lados: las fuentes de Google, CDN e imágenes
  remotas no se cargan. Cada página lo reporta como `external-resources`.
- No se juzgan vídeo, audio, animación de canvas ni el resultado de WebGL.
- Las fuentes son del sistema; otra máquina puede cambiar las métricas de
  texto.
- `INVALID` no es compatibilidad: significa que la medición no es fiable.
