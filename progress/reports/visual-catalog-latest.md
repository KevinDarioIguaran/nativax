# Catálogo visual ampliado — 300 páginas

Fecha: 2026-10-24. Se añadieron **246 páginas** a las 54 existentes (51 de
50projects50days + 3 de `examples/test-pages`), hasta un catálogo de **300
páginas** en `--all` (303 si se añaden las 3 locales).

## Fuentes

| Suite | Licencia | Páginas | Commit | Tipo |
|---|---|---:|---|---|
| `50projects50days` | MIT | 51 | `c92b0bc3a87fc95d44b89552b7b6a2eeb36ca481` | mini-apps HTML/CSS/JS |
| `mdn-css-examples` | CC0-1.0 | 27 | `65b08d2236b304d50d28a807a48c35f6889d902d` | flex, grid, clamp, shapes, generadores |
| `mdn-learning-area` | CC0-1.0 | 67 | `21973263ba859ff3477919087b488157f9d618a6` | HTML, formularios, accesibilidad, CSS |
| `odin-css-exercises` | MIT | 21 | `eae53f9c9030b9be41c2a6d07bb19e262c98a13e` | cascada, flex, grid, animación |
| `mdn-dom-examples` | CC0-1.0 | 134 | `03ae1ffb325a9202d3a64f26ab5b8361392a5368` | popovers, diálogos, canvas, WebGL, scroll, workers |
| **Total** | | **300** | | |

Las suites externas se descargan en `.visual/suites/` (ignorado por git) con
commit pinneado; no se redistribuyen. `50projects50days` sigue vendorizado en
`tools/visual/fixtures/` con su LICENSE.

## Categorías cubiertas

- Layout: flexbox, grid, holy grail, posicionamiento, responsive.
- Componentes: popovers, diálogos, toasts, carruseles, menús, formularios,
  switches, tablas.
- CSS moderno: `min/max/clamp`, `:is/:where`, `object-fit`, `shapes`,
  `backdrop`, contadores, `@property`, typed arithmetic, view transitions.
- Pintura y canvas: CSS painting, gradients, WebGL tutorial 1–8, chroma keying.
- Scroll: scroll-driven, scroll promises, scroll-to, viewport segments.
- DOM/API: storage, history, workers, streams, fullscreen, matchMedia, PiP.
- Animación: keyframes, transiciones, view transitions, skeletons.

## Comandos

```bash
# Ver el catálogo
dart run tools/visual/bin/visual_check.dart --all --list

# Ejecutar las 300
dart run tools/visual/bin/visual_check.dart --all

# Una suite concreta
dart run tools/visual/bin/visual_check.dart --suite mdn-dom-examples

# 50projects50days + test-pages (línea base de 51)
dart run tools/visual/bin/visual_check.dart --suite 50projects50days
```

En el panel Tkinter: botón **Visual 300** (o **Solo visual** para las 51).

## Prueba de humo (4 páginas)

Se ejecutaron una página de cada suite nueva para validar el pipeline y los
assets. **No es la tasa de las 300**:

| Página | Veredicto | Overall | Posición | Layout | Color | Diseño |
|---|---|---:|---:|---:|---:|---:|
| `mdn-css-examples/flexbox` | FAIL | 39,65 % | 0,57 % | 29,86 % | 66,99 % | 91,84 % |
| `mdn-dom-examples/popover-api/basic-declarative` | FAIL | 47,99 % | 31,27 % | 39,21 % | 65,74 % | 69,39 % |
| `mdn-learning-area/html/forms/toggle-switch-example` | FAIL | 65,56 % | 57,14 % | 87,02 % | 34,12 % | 91,84 % |
| `odin-css-exercises/foundations/flex/02-flex-header` | FAIL | 51,16 % | 8,34 % | 36,09 % | 94,48 % | 94,76 % |

Conclusión de la muestra: el pipeline carga y compara las páginas nuevas; hay
diferencias reales de layout/posición que el juicio detecta. La tasa completa
de las 300 queda pendiente de una corrida larga.

## Límites

- Descargar las cuatro suites externas supone ~270 MB; se guardan en
  `.visual/suites/` y no se versionan.
- Cada página se copia a un staging con su propio directorio; si una página
  referencia un asset en un directorio padre, ese asset no se copia. Se ve en
  la comparación como contenido ausente.
- La red está bloqueada en ambos motores: fuentes/imágenes remotas no cargan.
- Las 300 comparten el mismo juez: `results.json`, `report.md`, capturas y
  `diff.png` por página.
