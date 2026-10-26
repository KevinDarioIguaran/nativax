# HTML support

NativaX parses HTML into `nativa_dom`, then the renderer maps a subset of
elements to boxes, text, controls, images, canvas, and SVG. Parsing an unknown
element does not mean it is visually implemented. This page separates those
contracts.

Conformance baseline: html5lib tokenizer **99.26 %** (5,759 PASS / 43 FAIL /
1,025 SKIP) and tree construction **83.03 %** (1,556 PASS / 316 FAIL / 99 SKIP /
2 ERROR), recorded 2026-10-24/25. SKIP is excluded. See
[`../progress/conformance.md`](../progress/conformance.md).

## Parser architecture

`HtmlParser.parseDocument` has two paths:

- **Default** (`maxDepth == 200`): the in-house tokenizer runs to collect parse
  errors, then tree construction is delegated to `package:html` (html5 parser).
  The resulting tree is converted to `nativa_dom`.
- **Custom depth** (`maxDepth != 200`): a simplified in-house tree builder is
  used. It implements implicit structure, void/raw-text elements, common
  implicit closes, a simplified adoption-agency path for misnested formatting,
  basic table insertion (implicit `tbody`/`tr`), and foreign-content breakout.
  It is not the full WHATWG algorithm.

`parseFragment` is used by `innerHTML`. It ignores `html`/`head`/`body` tags and
builds children owned by the context document; the default path delegates to
`package:html`'s fragment parser.

## Supported parsing behavior

- Elements and attributes; single/double/unquoted/empty/boolean attributes;
  case-insensitive tag names; duplicate attributes keep the first.
- HTML named/numeric references from a generated WHATWG entity table; unknown
  references stay literal; invalid numeric references become U+FFFD.
- Implicit `html`/`head`/`body`; head elements before content; content after
  `</body>` remains in the body.
- Void elements, raw text (`script`, `style`), RCDATA (`textarea`, `title`),
  comments, bogus comments, `DOCTYPE`, and `<?...>` as a comment.
- Implicit closing of `p`, `li`, `dd`/`dt`, `option`, headings, and common
  table sections; unmatched end tags are recovered and reported.
- Foreign content (SVG/MathML) self-closing tags, HTML integration points, and
  breakout tags.
- Unknown tags are retained as generic elements and can be styled.

## Limits

| Limit | Default | Effect |
|---|---:|---|
| Input | 4 MiB chars | Rejected before tokenizing |
| Parse nodes | 100,000 | `HtmlLimitException` |
| Parse depth | 200 | Deeper start tags become siblings; diagnostic |
| Stored errors | 1,000 | Later errors counted as `droppedErrors` |
| DOM nodes | 100,000 | Connected-tree limit |
| DOM depth | 256 | Bounds recursive style/render traversal |

## Rendered element behavior

| Element family | Current behavior |
|---|---|
| `div`, `span`, `p`, headings, lists, `blockquote`, `pre`, `hr`, sections | Block/inline layout and text; CSS applies |
| `a` | Styled/clickable; navigation is a host callback, not an internal browser |
| `img` | Painted only through `NativaXImageResolver`; otherwise broken placeholder |
| `table`/rows/cells | Approximate CSS table layout (not a full table formatting context) |
| `details`/`summary` | Basic disclosure behavior; style/layout may differ |
| `dialog` | DOM top layer, backdrop, Escape, focus handling |
| `input`, `textarea`, `select`, `option`, `button`, `label` | Native Flutter controls with a documented subset; no file picker |
| `canvas` | Real 2D canvas subset; not WebGL |
| inline `svg` | Limited SVG renderer; not a full SVG implementation |
| `video`, `audio`, `iframe` | Space placeholder only; no playback/nested document |
| `script`, `style`, `link`, `meta`, `base`, `title` | Runtime metadata/resources; not painted |
| `template` | Parsed as a generic element; do not rely on a separate content fragment |
| `noscript` | No scripting-on/off tree behavior |

An unknown element is still a valid DOM node and can be styled, but it has no
special semantics. ``HTMLUnknownElement`` behavior is not a browser promise.

## Not supported

- Full WHATWG adoption agency/foster-parenting/quirks-mode behavior in the
  custom-depth builder.
- `<template>` content-fragment semantics.
- Frames/framesets and embedded documents.
- Media playback, file inputs, and real iframe content.
- A full SVG/MathML implementation.
- Browser navigation or form HTTP submission (both are host callbacks).
- HTML sanitization. Parsing is not sanitizing; treat untrusted markup as
  untrusted.

## Diagnostics

`HtmlParseResult.errors` contains `code`, offset, 1-based line/column, and detail.
`HtmlLimitException` is fatal; recoverable errors are not. The runtime exposes
`parseErrors` and can forward diagnostics through `onDiagnostic`.

## Tests

- `packages/nativa_html/test/tokenizer_test.dart`
- `packages/nativa_html/test/parser_test.dart`
- `packages/nativa_html/test/fuzz_test.dart`

## Related

- [`internals/html-dom-css.md`](internals/html-dom-css.md)
- [`css-supported.md`](css-supported.md)
- [`javascript-supported.md`](javascript-supported.md)
- [`architecture/rendering.md`](architecture/rendering.md)
