# Conformidad: línea base 2026-10-24 (actualizada en la sesión V8/CSS)

Los runners viven en `tools/conformance` y reutilizan suites oficiales. Los
checkouts están pinneados y no se versionan (`.conformance/` está ignorado).

## Resultados

| Suite | Alcance ejecutado | PASS | FAIL | SKIP | ERROR | Tasa | Commit |
|---|---|---:|---:|---:|---:|---:|---|
| Test262 | `language/{expressions,statements,types,literals}` | 19.577 | 413 | 1.108 | 0 | **97,93 %** | `d53ebc8` |
| html5lib tokenizer | todos los `.test` | 5.759 | 43 | 1.025 | 0 | **99,26 %** | `e7d77cd` |
| WPT `dom/nodes` | 327 archivos | 174 | 107 | 46 | 0 | **61,92 %** | `e7d77cd` |
| WPT `css/selectors` | 528 archivos | 126 | 54 | 348 | 0 | **70,00 %** | `e7d77cd` |
| WPT URL | 896 casos del fixture | 665 | 231 | 0 | 0 | **74,22 %** | `e7d77cd` |
| WPT `dom/events` | 176 archivos | 52 | 21 | 103 | 0 | **71,23 %** | `e7d77cd` |
| WPT tree construction | 1.973 casos `.dat` | 944 | 930 | 99 | 0 | **50,37 %** | `e7d77cd` |

La tasa excluye `SKIP`. Un `SKIP` **no** cuenta como compatibilidad.

Comandos de esta corrida: `run_test262`, `run_html5lib`, `run_url`,
`run_html_tree`, `run_wpt --dirs dom/nodes --limit 2000`, `dom/events` y
`css/selectors` (suites fijadas arriba). La base de la rama `c428bbc` daba
82 PASS en `css/selectors`; esta corrida da 84, y `dom/nodes` vuelve a 168 tras
corregir la caché de `classList`.

## Objetivo 70 % (fase 4)

| Suite | Objetivo | Actual | Estado |
|---|---:|---:|---|
| Test262 | 70 % | 97,93 % | ✅ |
| html5lib tokenizer | 70 % | 99,26 % | ✅ |
| WPT URL | 70 % | 74,22 % | ✅ |
| WPT `dom/nodes` | 70 % | 61,92 % | ❌ |
| WPT `css/selectors` | 70 % | 70,00 % | ✅ |
| WPT tree construction | 70 % | 50,37 % | ❌ |

Para DOM/CSS/parser, el 70 % exige CSSOM, `DOMParser`, Shadow DOM,
`customElements`, selectores `:has`/`:dir`/`:focus-visible` y adopción de
formato/foster parenting/template/foreign content. No se maquilla con SKIP.

## Informes

- `reports/test262-latest.md`
- `reports/html5lib-tokenizer-latest.md`
- `reports/wpt-dom-nodes-2026-10-20.md`
- `reports/wpt-css-selectors-2026-10-20.md`
- `reports/wpt-url-latest.md`
- `reports/wpt-html-tree-latest.md`

Los JSONL completos quedan en `.conformance/results/` (ignorado por git). Los
informes legibles versionados son solo `progress/reports/<suite>-latest.md`;
las corridas con timestamp también quedan en `.conformance/results/`.

## Corrida de eventos y selectores (2026-10-24)

Comandos:

```bash
cd tools/conformance
dart run bin/run_wpt.dart --dirs dom/events --limit 2000
dart run bin/run_wpt.dart --dirs css/selectors --limit 2000
dart run bin/run_wpt.dart --dirs dom/nodes --limit 2000
```

| Suite | PASS | FAIL | SKIP | Tasa (sin SKIP) |
|---|---:|---:|---:|---:|
| `dom/events` | 52 | 21 | 103 | **71,23 %** |
| `css/selectors` | 126 | 54 | 348 | **70,00 %** |
| `dom/nodes` | 174 | 107 | 46 | **61,92 %** |

`dom/events` alcanza 52/73 (71,23 %) y `css/selectors` 126/180 (70,00 %).
No se redondea ni se reclasifica. Los cambios reales de esta corrida son `Event` legacy
(`cancelBubble`, `returnValue`, constantes, `initEvent`/`initUIEvent`/
`initMouseEvent`/`initKeyboardEvent`), `createEvent` sin inicializar,
`window.event` reemplazable, `passive` por defecto, captura booleana,
`offsetX`/`offsetY`, handlers de `body`/`frameset`, aliases prefijados y
`HTMLFrameSetElement`.

El runner WPT también se corrigió para llamar a `StyleEngine.handleMutation`
en vez de sólo `invalidate()` y para completar `testharness` (`step_func`,
`promise_test` con `t`, asserts). **Eso es infraestructura de medición, no una
ganancia de compatibilidad del motor**: la línea base anterior subestimaba
`css/selectors` y `dom/events`. Las cifras de arriba ya reflejan el motor real,
pero no deben presentarse como si todo el delta fuera producto.

Quedan fuera de 70 % `dom/nodes` (61,92 %) y tree construction (50,37 %).
En selectores aún fallan `:focus-visible`, Shadow DOM, quirks mode,
namespaced y partes de `:dir`; en el parser HTML adoption agency, foster
parenting, `template`, foreign content y estados de script.

## Brechas principales

### Test262 (413 fallos)

- Errores tempranos de modo estricto que QuickJS-ng no rechaza (palabras
  reservadas futuras en identificadores).
- Decoradores (propuesta no implementada).
- Orden de evaluación en destructuring/assignment.
- Diferencias de `RegExp`/`Symbol` en casos límite.
- 1.108 SKIP: módulos, `dynamic-import`, `import-defer`, source-phase
  imports, TCO y APIs de host de Test262.

### html5lib (177 fallos)

- Comentarios bogus (`<!`, `<!-`) que incluyen el `!` en el dato.
- Entidades con ambigüedad de prefijo y casos de atributos.
- Detalles de `test4`/`domjs` sobre atributos y NUL.
- 1.025 SKIP: estados iniciales distintos de Data y doctypes con
  identificadores público/sistema (el `DoctypeToken` solo expone el nombre).

### Límite del runner CSS

La mayoría de los 164 FAIL de `css/selectors` comprueban `offsetWidth`,
`offsetHeight` o `getBoundingClientRect`. El runner de WPT sólo tiene DOM y
`StyleEngine`, **no layout/renderer**, así que no puede alcanzar el 70 % de
CSS selectors sin integrar el motor de layout de `nativa_render`. Los tests
reftest (345) están SKIP y no cuentan.

### WPT DOM/CSS (127 y 19 PASS)

Implementado en esta iteración:

- `Attr` real, `createAttribute`/`createAttributeNS`, `getAttributeNode(N S)`,
  `setAttributeNode(N S)`, `removeAttributeNode` y `attributes` tipo
  `NamedNodeMap` con `getNamedItem`/`setNamedItem`.
- `DOMImplementation` por documento, `new Document()`, `XMLDocument`,
  `createDocument`, `createDocumentType` y `createHTMLDocument`.
- Adopción automática al insertar entre documentos, `Document.cloneNode`,
  orden correcto de comentarios/doctype y `ownerDocument` real por nodo.
- `DOMException` de host con `name`, `code` y `constructor` correctos;
  `createProcessingInstruction` valida el `Name` XML y `CharacterData`
  convierte offsets a `unsigned long`.
- `classList` completo: tokens únicos, acceso indexado, `supports()`,
  `replace()` con mutación, normalización y `toString()`.
- `ChildNode.after/replaceWith` y `ParentNode.append/prepend` con el orden de
  hermanos y validación de ancestros; restricciones de hijos de `Document`.

En la segunda pasada se completaron además:

- `MutationObserver` completo: todos los archivos de `MutationObserver-*.html`
  pasan (atributos, characterData, childList, takeRecords, disconnect,
  overlapping, inner/outerHTML, textContent y callbacks).
- Colecciones vivas `HTMLCollection` con índices y propiedades nombradas;
  `NodeList` itera con `Array.prototype` y refleja inserciones.
- Atributos con namespace/prefix reales (`setAttributeNS`,
  `getAttributeNodeNS`, `removeAttributeNS`, `attributeEntries`).
- `Document.importNode`, constantes de `Node`, `isEqualNode`, `isSameNode`,
  `classList` vivo, `outerHTML`, `createTreeWalker` y validación de doctypes.
- El runner WPT ahora soporta `async_test(name)`, `this.add_cleanup`,
  `step_func(_done)` con argumentos y `unreached_func`, como el testharness real.
- `iframe.contentDocument`/`contentWindow` y `window.frames` con documentos
  aislados, tipo MIME inferido y evento `load`; `Node-isConnected` pasa al 100 %.

Pendiente para el 70 %: realms/iframes, `Range`/`TreeWalker` completos,
`DOMParser`/CDATA, `moveBefore`, adoption agency del parser y el layout para
CSS selectors. Los 345 SKIP de CSS son reftests visuales.

### WPT URL (665/896, 74,22 %)

`URL` y `URLSearchParams` ya se exponen a scripts. Los fallos restantes son
IDN, IPv6 canónico, file URLs y detalles de normalización de WHATWG. Ver
`docs/javascript-supported.md`.

### WPT tree construction (39,75 %)

- Sin adoption agency → HTML mal anidado difiere.
- Sin foster parenting → tablas.
- Sin `<template>` ni foreign content (SVG/MathML).
- Doctype, PI, template básico y una adopción/foster parcial; faltan adoption agency completa, tablas, template content real y foreign content.

## Cómo mejorar la línea base

1. `nativa_dom_bindings`: `createElementNS`, CSSOM, `DOMParser`.
2. `nativa_html`: adoption agency, foster parenting, doctype, template,
   foreign content.
3. `nativa_dom_bindings`: `URL` sobre `Uri` o un parser WHATWG propio.
4. Repetir `dart run bin/run_all.dart` y comparar el delta.
