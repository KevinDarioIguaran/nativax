# HTML, DOM, and CSS internals

This page documents the left half of the pipeline. It deliberately separates
“parsed” from “rendered” and “conformant”: each layer has its own limits.

## HTML tokenizer and tree builder

`HtmlParser` has two tree-construction paths:

1. **Default path** (`maxDepth` equal to the default 200): the in-house tokenizer
   still runs to collect parse errors, but the final tree comes from
   `package:html`'s `html5_parser`. The tree is then converted into a
   `nativa_dom.Document`.
2. **Custom-depth path** (any non-default `maxDepth`): the simplified in-house
   `_TreeBuilder` produces the tree. It implements implicit
   `html`/`head`/`body`, void elements, raw-text elements, implicit closing of
   `p`, `li`, `dd`, `dt`, `option`, minimal table insertion (implicit
   `tbody`/`tr`), a bounded simplified adoption-agency path for misnested
   formatting, foster-parenting when a formatting clone escapes a table, and
   unmatched-end-tag recovery.

The in-house builder is **not** the complete WHATWG tree-construction algorithm.
It does not implement `<template>` contents or quirks mode, and its adoption
agency/foster-parenting/table modes are intentionally reduced. Foreign content
(SVG/MathML) honors self-closing tags and HTML breakout tags. The default path
inherits `package:html`'s broader tree behavior. This is why the tree-conformance
baseline is meaningful but not complete.

### Limits

`HtmlParserLimits`:

| Limit | Default | Behavior |
|---|---:|---|
| `maxInputLength` | 4 MiB (4,194,304 chars) | Rejected before tokenizing |
| `maxNodes` | 100,000 | `HtmlLimitException` when exceeded |
| `maxDepth` | 200 | Deeper tags become siblings at the limit; reported as `nesting-too-deep` |
| `maxErrors` | 1,000 | Stored; later errors counted as `droppedErrors` |

`DocumentLimits` adds a second boundary for the connected DOM tree:

| Limit | Default | Behavior |
|---|---:|---|
| `maxNodes` | 100,000 | Insertion fails/throws at the limit |
| `maxDepth` | 256 | Bounds recursive style/render traversal |

The parser and the DOM are separate: a tree can be parsed within parser limits
and still hit a DOM insertion limit.

### Fragment parsing

`parseFragment(source, context)` is used by `innerHTML`. It does not create
implicit `html`/`head`/`body`; it builds children for the given context. The
default path uses `package:html`'s fragment parser; the custom-depth path uses
the simplified builder. Context-sensitive parsing rules are therefore also
approximate.

### Parse errors

`HtmlParseError` has a stable `code`, offset, 1-based line/column, and optional
detail. `HtmlParseResult` returns the value plus stored errors and a count of
dropped errors. Recoverable errors never abort a page. Hard limits throw
`HtmlLimitException`.

## DOM

`nativa_dom` is pure Dart and has no Flutter dependency. It implements:

- `Document`, `DocumentFragment`, `Element`, `Text`, `Comment`, `DocumentType`;
- attributes, `classList`, datasets, `style` serialization hooks;
- `Node` tree operations, cloning, text content, insertion and removal;
- events with capture/bubble phases, `preventDefault`, `stopPropagation`,
  trusted flags, and listener error reporting;
- selectors (`querySelector`, `querySelectorAll`, `matches`, `closest`);
- `MutationObserver` and mutation records;
- `Range`, `Selection`, `TreeWalker`, `NodeIterator` subsets;
- form validation state and `ValidityState`;
- custom-element registry metadata (the runtime/bindings provide the actual
  lifecycle behavior);
- `Document.baseURI`, active element, visibility, and lifecycle hooks.

The DOM does not perform layout or fetching. `getBoundingClientRect`,
`offsetWidth`, `scrollIntoView`, and observer geometry are implemented by the
renderer through callbacks/registries installed by `nativa_render`.

### DOM insertion limits

`Document` tracks connected nodes and rejects a mutation that would exceed
`limits.maxNodes` or `limits.maxDepth`. `subtreeSize` and clone operations also
enforce the limit. The exact exception type is documented by the DOM source; do
not assume a browser `HierarchyRequestError` for every limit case.

### Serialization

`innerHTML`/`outerHTML` serialize a subset of the DOM. The serializer escapes
text and attributes and handles raw-text elements, but it is not a byte-for-byte
browser serializer for every namespace/edge case. Round-tripping unusual markup
is not a guarantee.

## CSS parser and cascade

`nativa_css` is a CSS tokenizer/parser/cascade, not a stylesheet implementation
of every CSS module.

### Parsing

- selectors: type, class, id, universal, attributes with all common operators
  and `i`/`s` flags, combinators, structural/state/logical pseudo-classes,
  `::before`/`::after`/`::placeholder`/`::backdrop`, plus accepted-but-inert
  pseudo-elements;
- declarations with `!important`, `var()` and fallback, `inherit`/`initial`/
  `unset`;
- `@media` with nested conditions;
- `@supports` with `not`/`and`/`or`, declarations, and `selector()`;
- `@keyframes` (including `-webkit-`);
- `@layer` flattened in source order;
- `@font-face` with `font-family`, `src`, `font-weight`, `font-style`,
  `font-display`, and related descriptors;
- warnings for unsupported at-rules.

Unsupported/ignored at-rules include `@import`, `@container`, `@property`,
`@page`, and unknown vendor at-rules. They produce a `CssWarning` where the
parser can recognize them; they do not become styles.

### Cascade

`StyleEngine` applies:

- user-agent sheet, author sheets, and inline styles;
- origin/importance and specificity;
- inheritance;
- CSS-wide keywords;
- CSS variables;
- media/supports evaluation;
- presentation attributes for SVG;
- pseudo-element style resolution;
- a computed-style cache keyed by element/style inputs.

`@layer` is flattened; it is not a full cascade-layer implementation with layer
ordering and reversal. Inline styles and `!important` still follow the cascade
rules implemented by the engine, but do not assume full CSS Cascade 5 behavior.

### Properties

`properties.dart` defines supported longhands, shorthands, expansion, and
validation. `isSupportedProperty`/`expandDeclaration` are also used by
`CSS.supports()` and `@supports`. A property may be:

- parsed and mapped to a computed value but ignored by the renderer;
- parsed and painted with approximations;
- accepted but inert (for example some text properties).

[`../css-supported.md`](../css-supported.md) is the user-facing list. When
changing one, update the property spec, computed style, renderer, and tests
together.

### Style invalidation

Mutations notify the `StyleEngine` and `NativaXDocumentView`. The view batches
work in a microtask. The cache reduces repeated style computation, but a
mutation may still cause a larger recomputation/rebuild than a browser's
incremental style graph. `NATIVAX_NO_STYLE_CACHE=1` disables the cache for
diagnosis.

## Where the layers meet

- The runtime creates the DOM, parses styles, then creates the engine and
  bindings.
- `nativa_dom_bindings` exposes DOM operations to JavaScript; it calls into
  `nativa_dom` and `nativa_css` and returns JSON-compatible results.
- `nativa_render` reads `ComputedStyle` and DOM structure; it never independently
  parses CSS.
- The renderer installs geometry/focus/scroll callbacks that bindings use for
  `getBoundingClientRect`, `scrollIntoView`, and observers.

## Tests and evidence

| Area | Tests |
|---|---|
| Tokenizer | `packages/nativa_html/test/tokenizer_test.dart` |
| Parser | `packages/nativa_html/test/parser_test.dart` |
| Parser fuzz | `packages/nativa_html/test/fuzz_test.dart` |
| DOM | `packages/nativa_dom/test/dom_test.dart`, `fuzz_test.dart` |
| CSS | `packages/nativa_css/test/css_test.dart`, `media_matrix_test.dart`, `fuzz_test.dart` |
| Selectors/style cache | `packages/nativa_css/test/style_cache_test.dart` |
| Bindings | `packages/nativa_dom_bindings/test/bindings_test.dart` |

Conformance: `progress/conformance.md` (html5lib, WPT DOM/events/selectors/tree).
The WPT adapter is a lite harness; see [`../debugging.md`](../debugging.md).

## Related

- [`../html-supported.md`](../html-supported.md)
- [`../css-supported.md`](../css-supported.md)
- [`renderer.md`](renderer.md)
- [`javascript-bridge.md`](javascript-bridge.md)
