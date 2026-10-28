#ifndef NATIVAX_HTML_H
#define NATIVAX_HTML_H

/*
    HTML tokenizer + tree builder (subset, honest about it).

    Supported: doctype (skipped), comments, open/close/self-closing tags,
    all attribute value forms (double/single-quoted/unquoted/boolean),
    case-insensitive tag/attr names, first-duplicate-wins, entity decoding
    (named table + numeric), raw text (script/style), RCDATA
    (textarea/title), implied end tags (li/dd/dt/p/option/optgroup/
    thead/tbody/tfoot/tr/td/th), implicit html/head/body insertion modes,
    stray-close recovery (simplified adoption agency: elements between the
    stray close and its target are closed).

    Documented deviations from HTML5: self-closing "/>" is honored on all
    elements (HTML5 ignores it on non-void HTML elements), no foster
    parenting for misnested table content, no fragment parsing.

    Limits: input <= 4 MiB, depth <= NX_MAX_DEPTH, nodes <= NX_MAX_NODES.
*/

#include "nativax/dom.h"

#include <stdbool.h>

#define NX_HTML_MAX_INPUT (4 * 1024 * 1024)

/* Parse a full document into doc (existing children are cleared first).
   Returns true on success. On failure *error_out (caller frees) holds the
   message and offset; the document keeps the partial tree (documented). */
bool nx_html_parse(NxDocument* doc, const char* html, int len, char** error_out);

#endif /* NATIVAX_HTML_H */
