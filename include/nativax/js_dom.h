#ifndef NATIVAX_JS_DOM_H
#define NATIVAX_JS_DOM_H

/*
    JavaScript ↔ DOM bindings.

    The boundary stays narrow: script never receives a C pointer. Elements are
    JS wrapper objects carrying an int32 node handle; every operation calls a
    native primitive that validates the handle against the document pool.

    The DOM API surface (`document`, element methods, `style`, `classList`,
    events) is implemented by a small JavaScript prelude over those primitives,
    because that keeps JSValueRef ownership inside this module and the engine
    layer while still giving scripts idiomatic objects.

    Documented v1 limits: `element.style` writes the style="" attribute (so
    they re-enter the normal cascade); listeners fire on the target and bubble
    up the ancestor chain; innerHTML reparses a fragment through the HTML
    parser; there is no layout-box API (offsetWidth/Height) yet.
*/

#include <stdbool.h>

#include "nativax/dom.h"
#include "nativax/js_engine.h"

typedef struct NxDomBindings NxDomBindings;

/* Install `document`, `window` and `console` on the global object and bind
   every native primitive. `doc` must outlive the bindings. */
NxDomBindings* nx_dom_bind_new(NxJs* js, NxDocument* doc);

/* Drop listeners and the JS-side wrapper cache (the JS context itself stays
   owned by the caller). Safe on NULL. */
void nx_dom_bind_free(NxDomBindings* b);

/* Mutation hook: fired after every script write that can affect rendering. */
void nx_dom_bind_set_mutation_cb(NxDomBindings* b, void (*cb)(void* user), void* user);

/* Route an event through script listeners: target first, then ancestors.
   Returns true when default was not prevented. */
bool nx_dom_dispatch_js(NxDomBindings* b, NxNodeRef target, const char* type);

/* Number of listeners currently registered (diagnostics/tests). */
int nx_dom_listener_count(const NxDomBindings* b);

#endif /* NATIVAX_JS_DOM_H */
