# CSS y layout soportados

NativaX implementa CSS con su propio motor (cascada + layout en
RenderObjects de Flutter). No es un motor de navegador completo: esta página
define qué se pinta como en un navegador, qué se aproxima y qué falta.

La referencia de calidad es la comparación visual contra Chrome de
`examples/web-challenge` (HTML/CSS/JS original, sin modificar) con la
herramienta `examples/web-challenge/test/screenshot_test.dart`.

## Selectores y cascada

- Tipo, `.clase`, `#id`, `*`, atributos (todos los operadores, flags `i`/`s`),
  combinadores (` `, `>`, `+`, `~`).
- Pseudoclases estructurales: `:first/last/only-child`, `:nth-child`,
  `:nth-last-child` (con `of S`), `:first/last/only-of-type`,
  `:nth-of-type`, `:nth-last-of-type`, `:empty`, `:root`, `:scope` (raíz).
- Lógicas: `:not`, `:is`, `:where`, `:has` (relativo).
- De estado (se recalculan al cambiar el estado): `:hover`, `:active`,
  `:focus`, `:focus-visible`, `:focus-within`, `:target`, `:checked`,
  `:disabled`, `:enabled`, `:required`, `:optional`, `:read-only`,
  `:read-write`, `:placeholder-shown`, `:valid`, `:invalid`, `:user-valid`,
  `:user-invalid`, `:in-range`, `:out-of-range`, `:indeterminate`,
  `:default`, `:open`, `:modal`, `:defined`, `:link`, `:any-link`.
- Otras: `:dir()`, `:lang()`, `:heading`. `:visited` nunca coincide.
- Pseudoelementos: `::before`, `::after` (con `content`: cadenas, `attr()`,
  comillas), `::placeholder`, `::backdrop`. Se aceptan (sin efecto)
  `::marker`, `::selection`, `::first-line`, `::first-letter`, `::part()`,
  `::slotted()` y prefijos `-webkit-`/`-moz-`.
- Especificidad, `!important`, capas UA/autor/inline, herencia,
  `inherit`/`initial`/`unset`, variables `--x` con `var()` y fallback.
- Atributos de presentación SVG (`fill="red"`) como reglas de autor de
  especificidad 0.

## At-rules

- `@media` (anidado): `width`, `height`, `orientation`,
  `prefers-color-scheme`, `prefers-reduced-motion`, `resolution`.
- `@supports` (`and`, `or`, `not`, `selector()`), evaluado al parsear.
- `@keyframes` (también `-webkit-`).
- `@layer` se aplana en orden de aparición (sin precedencia de capas).
- No soportados: `@font-face` (las fuentes las registra la app Flutter),
  `@import`, `@container`, `@property`, `@page`.

## Valores

- Longitudes `px`, `%`, `em`, `rem`, `vw`, `vh` y absolutas (`pt`, `cm`,
  ...). `calc()`, `min()`, `max()` y `clamp()` (los `%` se resuelven en
  layout contra el bloque contenedor).
- Colores: 148 nombres, hex (3/4/6/8), `rgb()`/`rgba()`/`hsl()`/`hsla()`
  (sintaxis con comas y moderna), `transparent`, `currentcolor`.
- `env(safe-area-inset-*)` resuelve a `0px` o al fallback.

## Modelo de caja

- `width`/`height`/`min-*`/`max-*`, `box-sizing`, `margin` (incl. `auto`),
  `padding`, `border` (ancho, color y estilo `solid`, `dashed`, `dotted`,
  `double`; `groove`/`ridge`/`inset`/`outset` se pintan sólidos).
- `border-radius` (también en %), `outline` (+ `outline-offset`).
- Fondos: color, imagen (`cover`), `linear-gradient`, `radial-gradient`,
  `conic-gradient` y `repeating-*` con la geometría de CSS. Con varias capas
  se pinta la primera imagen. `background-size/position/repeat` se aceptan
  sin efecto.
- `box-shadow` (varias sombras; `inset` no se pinta), `opacity`,
  `visibility: hidden` (conserva el espacio), `filter` (`blur`,
  `brightness`, `contrast`, `grayscale`, `invert`, `opacity`, `saturate`,
  `sepia`, `hue-rotate`, `drop-shadow`), `backdrop-filter: blur()`.
- `transform`: `translate*`, `scale*`, `rotate`, `skew*`, `matrix`; con
  origen en el centro; `%` relativo a la propia caja. Las funciones 3D se
  proyectan a 2D (`perspective` sin efecto).
- `overflow` `hidden`/`clip` recorta; `auto`/`scroll` crea scroll vertical,
  y horizontal solo para contenido intrínsecamente ancho (flex, grid,
  `white-space: pre/nowrap`).
- Colapso de márgenes entre hermanos y a través de cajas vacías. Sin colapso
  padre/hijo.

## Display y layout

- `display`: `block`, `inline`, `inline-block`, `flex`, `inline-flex`,
  `grid`, `inline-grid`, `list-item`, `contents`, `none`, `flow-root`,
  sintaxis de dos valores (`inline flex`). Las tablas se aproximan
  (`table-row` como flex).
- **Flexbox**: dirección (incl. `reverse`), `wrap`, `gap`, grow/shrink/basis
  con congelación por min-content, `justify-content`, `align-items`,
  `align-self`, márgenes `auto`, `order`. Una sola línea toma el tamaño
  transversal del contenedor (`min-height` centra/estira). Sin
  `align-content`; `baseline` se trata como `flex-start`.
- **Grid**: `grid-template-columns/rows` con `px`, `%`, `calc()`, `fr`,
  `auto`, `min-content`, `max-content`, `fit-content()`, `minmax()`,
  `repeat()` (incl. `auto-fill`/`auto-fit` con colapso), pistas implícitas
  (`grid-auto-rows/columns`), `grid-template-areas`, colocación por líneas
  (negativas, `span`, nombres de área), auto-placement por filas o columnas,
  `gap`, `justify/align-items`, `justify/align-self`,
  `justify/align-content`. Sin `subgrid` ni `dense`.
- **Posicionamiento**: `relative`, `absolute` (respecto al padre),
  `fixed` (capa del viewport), `sticky` (respecto al contenedor de scroll
  más cercano, limitado por el bloque contenedor), `z-index` (también para
  elementos posicionados en flujo).

## Texto

- `font-family` (fallbacks), `font-size`, `font-weight`, `font-style`,
  shorthand `font` (incl. `font: inherit`), `line-height`, `letter-spacing`.
- `text-align`, `white-space`, `text-transform`, `text-decoration-*`,
  `text-shadow`, `text-overflow: ellipsis` (con `nowrap` + `overflow`).
- Los elementos inline con padding/borde/fondo redondeado se pintan como
  cajas atómicas (no se parten entre líneas).
- Aceptadas sin efecto: `word-break`, `overflow-wrap`, `hyphens`,
  `text-indent`, `font-variant*`, `vertical-align`.

## Transiciones y animaciones

- `transition` (propiedades concretas o `all`) y `@keyframes` con
  `animation` (duración, retardo, `iteration-count` incl. `infinite`,
  `direction`, `fill-mode`, `play-state`, `animation-timing-function` por
  keyframe).
- Easing: `linear`, `ease*`, `cubic-bezier()`, `steps()`, `step-*`.
- Se interpolan longitudes, números, colores, `transform` y `box-shadow`;
  lo demás cambia de forma discreta a mitad de camino.
- Eventos `transitionrun/start/end` y `animationstart/iteration/end`.
- Las propiedades heredadas animadas no se propagan a los descendientes.

## SVG en línea

- `svg` con `viewBox` (`xMidYMid meet`), `width`/`height`.
- `rect` (con `rx/ry`), `circle`, `ellipse`, `line`, `polyline`, `polygon`,
  `path` (todos los comandos), `text` (con `text-anchor` y
  `dominant-baseline`), `g` con `transform`.
- `fill`, `stroke`, `stroke-width`, `stroke-dasharray`, `stroke-linecap`,
  `stroke-linejoin`, `fill-rule`, `*-opacity`, desde atributos o CSS.
- Los clics llegan a la figura bajo el puntero.
- Sin gradientes/patrones SVG (`url(#id)` usa el color de respaldo), `use`,
  `clipPath`, `mask`, `filter`, `marker` ni `foreignObject`.

## Formularios

- Texto (ancho por `size`), `password`, `email`, `number`, `tel`, `url`,
  `search`, `textarea` (`rows`/`cols`), `checkbox`, `radio`, `range`
  (slider), `color` (selector), `date`/`time`/`datetime-local`/`month`/
  `week` (selectores nativos), `file` (botón; sin selector de archivos),
  `select` simple y `multiple`/`size` (lista), `fieldset` con `legend` sobre
  el borde, `button`, `label`.
- `accent-color`, `::placeholder`. Range, checkbox y radio ignoran fondo y
  borde del autor (como con `appearance: auto`).
- Validación de restricciones completa (ver JavaScript).

## Otros elementos

- `img` mediante `NativaXImageResolver`, `object-fit`, `alt`.
- `canvas` con contexto 2D (ver JavaScript).
- `video`, `audio`, `iframe`: se reserva su espacio con un marcador; no hay
  reproducción multimedia ni documentos anidados.
- `details`/`summary` (abre y cierra), `dialog` (`show`, `showModal` en la
  capa superior con `::backdrop`, `Escape` lo cierra).

## Interacción

- Puntero: `:hover`, `:active`, cursor, clic con coordenadas (`clientX`,
  `offsetX`, ...), `dblclick`, `contextmenu` (clic derecho o pulsación larga),
  arrastrar y soltar HTML5 (`draggable`, `dataTransfer`).
- Teclado: `keydown`/`keyup` en el elemento con foco.
- Scroll: `scroll`, `scrollIntoView`, `scrollTo`, `scroll-padding-top`.

## Diagnóstico

`NativaXDocumentView.onDiagnostic` recibe aproximaciones (imagen no resuelta,
etc.), deduplicadas por montaje. Las advertencias del parser CSS se reportan
desde el runtime.
