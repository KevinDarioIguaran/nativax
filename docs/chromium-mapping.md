# Mapa de Chromium para la virtualización de NativaX

Este documento fija la referencia técnica que se usó para diseñar la
virtualización del renderer de NativaX. No se copia código de Chromium ni se
introduce Blink: se trasladan los mecanismos y sus invariantes al renderer
propio (`nativa_render`).

Chromium consultado: `chromium/src` en `refs/heads/main`, 2026-10-23.
Rutas relativas a `third_party/blink/renderer/`.

## 1. Bloquear estilo, layout, prepaint y paint de un subárbol

**Problema NativaX.** El documento tiene 10.000 filas, pero el viewport solo
muestra ~20. Hoy cada fila tiene estilo computado, un `RenderObject`, layout y
paint aunque esté a 2.000.000 px de distancia.

**Chromium.** `core/display_lock/display_lock_context.h` define
`DisplayLockContext` y cuatro decisiones por fase:

- `ShouldStyleChildren()`
- `ShouldLayoutChildren()`
- `ShouldPrePaintChildren()`
- `ShouldPaintChildren()`

Las cuatro devuelven `true` cuando el lock no está activo. `Lock()` /
`Unlock()` en `core/display_lock/display_lock_context.cc` cambian el estado, y
`SetRequestedState(EContentVisibility)` lo origina desde el estilo
(`content-visibility: hidden|auto|visible`). `DisplayLockUtilities`
(`core/display_lock/display_lock_utilities.h`) responde
`LockedAncestorPreventingStyle/Layout/Paint` para no forzar un ancestro
bloqueado.

**Adaptación Dart.** `CssVirtualBlock` es el equivalente al lock por
contenedor:

- No construye widgets para hijos fuera de la ventana. Sin widget no hay
  `Element`, ni `RenderObject`, ni estilo (`styleOf` no se llama).
- El contenedor expone una ventana `[start, end]` calculada con el rect de
  culling. Solo esa ventana se materializa.
- El bloque sigue existiendo como caja CSS; su altura total se compone de
  estimaciones y de las alturas reales medidas.
- La decisión se toma en el mismo punto que Chromium toma
  `ShouldStyleChildren`: antes de recorrer los hijos.

## 2. Rect de culling y margen de overscan

**Problema NativaX.** Hay que decidir qué filas caen en el viewport sin
recorrer y estilar 10.000 nodos.

**Chromium.** `platform/graphics/paint/cull_rect.h` define `CullRect` con
`Intersects`, `IntersectsTransformed`, `IntersectsHorizontalRange` e
`IntersectsVerticalRange`. `core/paint/cull_rect_updater.cc` lo propaga:

- `CullRectUpdater::UpdateRecursively`
- `CullRectUpdater::UpdateForSelf`
- `CullRectUpdater::ComputeFragmentCullRect`
- `CullRectUpdater::ComputeFragmentContentsCullRect`

El rect se expande para scroll compuesto (`CullRect::ApplyScrollTranslation`,
`CullRect::CanExpandForScroll`) y se recorta con clips y transforms.

**Adaptación Dart.** La ventana usa un intervalo vertical, no un rect 2D:
`viewportTop - overscan <= y < viewportTop + viewportHeight + overscan`.
`overscan` es configurable (por defecto un viewport, como el margen de
`content-visibility: auto`). Las filas se localizan por suma de alturas, con
una búsqueda lineal O(n) sobre aritmética (sin construir widgets). La ventana
se recalcula una vez por frame tras el scroll; no por mutación.

## 3. Tamaño estimado y corrección al entrar en vista

**Problema NativaX.** Una fila no materializada no tiene altura real, pero el
scroll necesita una altura total y una posición para cada fila.

**Chromium.** `content-visibility: auto` usa `contain-intrinsic-size` para dar
un tamaño de reemplazo al subárbol bloqueado; el layout real se ejecuta al
desbloquear. `DisplayLockContext::DidLayoutChildren()` y
`ShouldLayoutChildren()` gobiernan esa transición.

**Adaptación Dart.** Cada bloque mantiene:

- `_heights[i]` para alturas medidas;
- una altura media móvil para las no medidas;
- una estimación estructural inicial (altura declarada, o
  `line-height`/padding/tag) para la primera pasada;
- `total = n * media + suma(medida - media)`.

Cuando una fila entra en la ventana se mide su `RenderBox` y se sustituye la
estimación. El delta se aplica al `ScrollController` en el mismo post-frame
para que el ancla visible no se mueva (ver §4).

## 4. Scroll anchoring

**Problema NativaX.** Al corregir la altura de una fila estimada, todo el
contenido posterior salta.

**Chromium.** `core/layout/scroll_anchor.h/.cc`:
`ScrollAnchor::FindAnchor`, `ScrollAnchor::ComputeAdjustment`,
`ScrollAnchor::Adjust`, `ScrollAnchor::RestoreAnchor`, y
`DisplayLockContext::StashScrollOffsetIfAvailable()` /
`RestoreScrollOffsetIfStashed()` para no perder el offset al bloquear un
scroller.

**Adaptación Dart.** Antes de corregir alturas se elige como ancla la primera
fila materializada cuyo borde superior está en o por encima del viewport. Se
calcula `aboveDelta` (cambio de altura de todo lo anterior) y se hace
`jumpTo(offset + aboveDelta)` en el mismo post-frame en que se aplican las
nuevas alturas. El ancla conserva su posición en pantalla. Si el scroller está
en el máximo, se respeta el clamp y se vuelve a anclar en el siguiente frame.

## 5. Activación por navegación, foco, selección y find

**Problema NativaX.** Un `#hash`, `element.focus()`, `scrollIntoView()` o una
búsqueda pueden apuntar a una fila que no existe como `RenderObject`.

**Chromium.** `DisplayLockActivationReason` en
`core/display_lock/display_lock_context.h` incluye `kAccessibility`,
`kFindInPage`, `kFragmentNavigation`, `kScriptFocus`, `kScrollIntoView` y
`kSelection`. `CommitForActivation(reason)` y
`ShouldCommitForActivation(reason)` desbloquean el subárbol; para
navegación/foco/scroll mantiene el desbloqueo dos frames
(`SetKeepUnlockedUntilLifecycleCount(2)`) porque la visibilidad se decide al
final del frame.

**Adaptación Dart.** `CssVirtualBlockState.ensureBuilt(element)` fija el
elemento en la ventana (`_pinned`), fuerza un `setState` y el siguiente frame
ya tiene su `RenderObject` real. Se usa desde:

- `LayoutHost.boxOf` cuando el elemento está virtualizado (devuelve caja
  estimada si aún no se materializó, real si ya está);
- `LayoutHost.scrollIntoView`, que materializa, espera el frame y luego
  desplaza;
- navegación `#hash` (el binding ya llama a `scrollIntoView`);
- `focus()`/Tab: el foco que entra en un elemento virtualizado lo fija.

## 6. Reciclaje acotado

**Problema NativaX.** Al salir de la ventana, los `RenderObject` deben
liberarse; no pueden acumularse con el número de filas.

**Chromium.** `DisplayLockContext::Lock()` desconecta el layout tree del
subárbol (`DetachLayoutTree`) y `Unlock()` lo reconstruye. El culling evita
crear fragmentos de paint fuera del cull rect.

**Adaptación Dart.** La ventana materializada está acotada por
`viewport + 2 * overscan`; al desplazarse, los widgets que salen se eliminan
del árbol y sus `RenderObject` se liberan. El bloque conserva solo datos
ligeros (alturas, índices, elementos DOM), no árboles de render. La cola de
reciclaje conserva como máximo una ventana de widgets ya construidos; no crece
con N. El test `virtualization_test.dart` cuenta `RenderObject` vivos para
100, 1.000 y 10.000 filas y exige que la diferencia sea ~constante.

## 7. Diferencias deliberadas

- Chromium mantiene el `LayoutObject` y bloquea sus fases; NativaX no crea el
  `RenderObject` fuera de la ventana. Es más agresivo y encaja con el
  renderer Flutter.
- Chromium calcula `contain-intrinsic-size` desde CSS; NativaX empieza con una
  estimación estructural y la corrige con medidas reales.
- Chromium tiene scroll anchoring nativo por `ScrollAnchor`; NativaX lo
  implementa en el bloque virtual porque el scroll lo controla Flutter.
- `selection` y `find` siguen siendo APIs limitadas en NativaX; la
  virtualización garantiza que un nodo materializado por esas rutas conserva
  su geometría, pero no se declara compatibilidad completa con Blink.

## 8. CSS: RuleSet, SelectorFilter y MatchedPropertiesCache

**Problema NativaX.** Cada elemento visible recorría las reglas candidatas y
volvía a construir sus declaraciones; con Tailwind/Font Awesome (~3.600
reglas) eso domina el arranque.

**Chromium.**

- `core/css/rule_set.h`: `RuleSet::AddRule`, `RuleSet::AddRulesFromSheet` y
  los buckets por id, clase, tag, universal y pseudo. La cascada solo mira el
  bucket que puede casar con el sujeto.
- `core/css/selector_filter.h`: `SelectorFilter::CollectElementIdentifierHashes`
  y `SelectorFilter::FastRejectSelector`; el filtro de ancestros (Bloom de
  ids/clases/tags) descarta selectores descendientes antes de evaluarlos.
- `core/css/resolver/matched_properties_cache.h`: `MatchedPropertiesCache::Find`
  y `MatchedPropertiesCache::Add`; reutiliza las declaraciones casadas y el
  estilo resultante para elementos con la misma firma.
- `core/css/resolver/style_resolver.cc` y `style_cascade.cc`: comparten estilo
  entre hermanos cuando la firma y el estilo heredado coinciden, y mantienen la
  herencia por referencia.

**Adaptación Dart.**

- `StyleEngine` ya indexa por `id`/`class`/`tag`/universal; se añadieron
  buckets específicos de `:hover` para no crear `MouseRegion` en nodos que no
  pueden casar con una regla de hover.
- `_elementSignature` + `_matchedCache`: declaraciones casadas compartidas por
  firma (tag, id, clases, atributos, pseudo, estado de puntero/foco/target).
- `_computedCache`: `ComputedStyle` compartido por firma + identidad del estilo
  heredado + contexto estructural (posición, número de hermanos, `:empty`).
- Las estructuras con selectores estructurales se detectan al indexar
  (`:first-*`, `:nth-*`, `:empty`, `:has()`, `+`, `~`) y solo esos sujetos
  incluyen el contexto estructural en la clave.
- `useStyleCaches` permite medir el camino sin caché; producción lo deja activo.
- Diferencia: Chromium usa un Bloom de ancestros; NativaX todavía usa la firma
  del elemento y el índice de sujeto. El Bloom queda como siguiente paso.

## 9. LayoutNG: ConstraintSpace y LayoutResult

**Problema NativaX.** El primer frame hacía varias pasadas por caja
(`layout`, `dry`, intrínsecos) y cada pasada podía volver a medir texto.

**Chromium.**

- `core/layout/constraint_space.h`: `ConstraintSpace`,
  `ConstraintSpaceBuilder` y `ConstraintSpace::AvailableSize()`; el espacio de
  restricciones es un valor inmutable que se reutiliza.
- `core/layout/layout_result.h`: `LayoutResult` guarda el fragmento, tamaño,
  baseline y datos de ruptura; un resultado se reutiliza mientras las
  restricciones y el estilo no cambien.
- `core/layout/flex/flex_layout_algorithm.cc`: `FlexLayoutAlgorithm::Layout`,
  `LayoutInternal`, `ConstructAndAppendFlexItems`,
  `BuildSpaceForFlexBasis` y `BuildSpaceForLayout`; los hijos se miden con un
  `ConstraintSpace` explícito una vez por fase.
- `core/layout/layout_box.cc`: `LayoutBox::Layout` y los puntos de invalidación
  de layout (`SetNeedsLayout`, `SetChildNeedsLayout`) limitan el relayout.

**Adaptación Dart.**

- `RenderCssFlex` ya reutiliza el layout real de los hijos en columnas cuando
  la longitud flexible no cambia el tamaño principal; evita la pasada dry
  duplicada.
- `LayoutProfile` mide `box.layout`, `box.dry`, `box.paint`, `flex.layout`,
  `flex.dry`, `text.layout`, `text.dry` y `text.intrinsic` por frame.
- Pendiente: cachear `LayoutResult` por `(constraints, estilo)` en
  `RenderCssBox`/`RenderCssFlex` y limitar el relayout a un boundary. El
  primer frame del fixture genérico sigue dominado por layout; los intentos de
  cachear intrínsecos en `RenderCssBox` no movieron la métrica y se
  revirtieron.

## 10. Texto y mutación

- Chromium cachea el shaping por `(texto, estilo, ancho)` en
  `platform/text` y evita re-shaping entre pasadas; NativaX mide con
  `RenderParagraph` de Flutter y `LayoutTimed` atribuye sus pasadas.
- Chromium agrupa invalidaciones en el lifecycle del documento
  (`core/dom/style_engine.cc`, `document_lifecycle.cc`); NativaX mantiene una
  sola pasada por frame en `NativaXDocumentView._flush` y difiere estilos de
  nodos virtualizados fuera de vista (`invalidateDeferred`).
