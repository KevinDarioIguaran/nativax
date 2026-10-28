/*
    JavaScript ↔ DOM bindings.

    Native primitives take and return ids, scalars and strings only; the JS
    prelude builds the ergonomic DOM objects on top. Every write primitive
    notifies the mutation hook so the host can invalidate style/layout/paint.
*/
#include "nativax/js_dom.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "nativax/css.h"
#include "nativax/html.h"
#include "nativax/log.h"
#include "nativax/style.h"

typedef struct NxJsListener {
    NxNodeRef node;
    char* type;
    JSObjectRef fn;
} NxJsListener;

struct NxDomBindings {
    NxJs* js;
    NxDocument* doc;
    NxJsListener* listeners;
    int listener_count, listener_cap;
    void (*mutation_cb)(void* user);
    void* mutation_user;
    bool stop;
    bool prevented;
};

/* ---- small JS helpers ---------------------------------------------------- */

static JSContextRef ctx_of(NxDomBindings* b) { return nx_js_ctx(b->js); }

static double num_arg(JSContextRef ctx, const JSValueRef argv[], size_t argc, size_t i) {
    if (i >= argc) return 0;
    return JSValueToNumber(ctx, argv[i], NULL);
}

static char* str_arg(JSContextRef ctx, const JSValueRef argv[], size_t argc, size_t i) {
    if (i >= argc) return NULL;
    JSStringRef s = JSValueToStringCopy(ctx, argv[i], NULL);
    if (!s) return NULL;
    size_t max = JSStringGetMaximumUTF8CStringSize(s);
    char* out = (char*)malloc(max ? max : 1);
    if (out) JSStringGetUTF8CString(s, out, max);
    JSStringRelease(s);
    return out;
}

static JSValueRef ret_id(JSContextRef ctx, NxNodeRef id) {
    return id ? JSValueMakeNumber(ctx, (double)id) : JSValueMakeNull(ctx);
}

static void mutated(NxDomBindings* b) {
    if (b->mutation_cb) b->mutation_cb(b->mutation_user);
}

static NxDocument* doc_of(NxDomBindings* b) { return b->doc; }

/* ---- primitives ---------------------------------------------------------- */

static JSValueRef p_doc_id(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                           const JSValueRef argv[], void* user) {
    (void)fn; (void)self; (void)argc; (void)argv;
    return ret_id(ctx, nx_doc_root(doc_of(user)));
}

static JSValueRef p_doc_element(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                                const JSValueRef argv[], void* user) {
    (void)fn; (void)self; (void)argc; (void)argv;
    NxDocument* doc = doc_of(user);
    for (NxNodeRef c = nx_node_first_child(doc, nx_doc_root(doc)); c;
         c = nx_node_next_sibling(doc, c)) {
        if (nx_node_type(doc, c) == NX_NODE_ELEMENT) return ret_id(ctx, c);
    }
    return JSValueMakeNull(ctx);
}

static JSValueRef p_get_by_id(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                              const JSValueRef argv[], void* user) {
    (void)fn; (void)self;
    NxDomBindings* b = (NxDomBindings*)user;
    char* id = str_arg(ctx, argv, argc, 0);
    if (!id) return JSValueMakeNull(ctx);
    NxNodeRef r = nx_doc_get_element_by_id(b->doc, id);
    free(id);
    return ret_id(ctx, r);
}

/* Scoped selector search: parse once, walk the subtree in document order. */
static NxNodeRef find_match(NxDocument* doc, NxNodeRef scope, const CsGroup* g) {
    for (NxNodeRef c = nx_node_first_child(doc, scope); c; c = nx_node_next_sibling(doc, c)) {
        if (nx_node_type(doc, c) != NX_NODE_ELEMENT) continue;
        if (nx_selector_matches(doc, c, g)) return c;
        NxNodeRef deeper = find_match(doc, c, g);
        if (deeper) return deeper;
    }
    return 0;
}

static CsGroup* parse_selector(const char* sel, int len) {
    CsGroup* g = (CsGroup*)calloc(1, sizeof(CsGroup));
    if (!g) return NULL;
    if (!cs_parse_selector(sel, len, g)) {
        free(g);
        return NULL;
    }
    return g;
}

static JSValueRef p_query(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                          const JSValueRef argv[], void* user) {
    (void)fn; (void)self;
    NxDomBindings* b = (NxDomBindings*)user;
    char* sel = str_arg(ctx, argv, argc, 1);
    if (!sel) return JSValueMakeNull(ctx);
    NxNodeRef scope = (NxNodeRef)num_arg(ctx, argv, argc, 0);
    if (!scope || nx_node_type(b->doc, scope) == 0) {
        free(sel);
        return JSValueMakeNull(ctx);
    }
    CsGroup* g = parse_selector(sel, (int)strlen(sel));
    if (!g) {
        free(sel);
        return JSValueMakeNull(ctx);
    }
    /* selector slices point into `sel`: keep it alive while matching */
    NxNodeRef r = find_match(b->doc, scope, g);
    free(g);
    free(sel);
    return ret_id(ctx, r);
}

static JSValueRef p_query_all(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                              const JSValueRef argv[], void* user) {
    (void)fn; (void)self;
    NxDomBindings* b = (NxDomBindings*)user;
    char* sel = str_arg(ctx, argv, argc, 1);
    NxNodeRef scope = (NxNodeRef)num_arg(ctx, argv, argc, 0);
    if (!sel || !scope || nx_node_type(b->doc, scope) == 0) {
        free(sel);
        return JSObjectMakeArray(ctx, 0, NULL, NULL);
    }
    CsGroup* g = parse_selector(sel, (int)strlen(sel));
    if (!g) {
        free(sel);
        return JSObjectMakeArray(ctx, 0, NULL, NULL);
    }

    NxNodeRef stack[NX_MAX_NODES > 4096 ? 4096 : NX_MAX_NODES];
    int sp = 0;
    for (NxNodeRef c = nx_node_first_child(b->doc, scope); c;
         c = nx_node_next_sibling(b->doc, c))
        if (sp < 4096) stack[sp++] = c;
    JSValueRef values[4096];
    size_t n = 0;
    while (sp > 0) {
        NxNodeRef cur = stack[--sp];
        if (nx_node_type(b->doc, cur) != NX_NODE_ELEMENT) continue;
        if (nx_selector_matches(b->doc, cur, g) && n < 4096)
            values[n++] = JSValueMakeNumber(ctx, (double)cur);
        NxNodeRef kids[256];
        int kc = 0;
        for (NxNodeRef c = nx_node_first_child(b->doc, cur); c && kc < 256;
             c = nx_node_next_sibling(b->doc, c))
            kids[kc++] = c;
        for (int i = kc - 1; i >= 0; i--)
            if (sp < 4096) stack[sp++] = kids[i];
    }
    free(g);
    free(sel);
    return JSObjectMakeArray(ctx, n, values, NULL);
}

static JSValueRef p_create(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                           const JSValueRef argv[], void* user) {
    (void)fn; (void)self; (void)argc;
    NxDomBindings* b = (NxDomBindings*)user;
    char* tag = str_arg(ctx, argv, argc, 0);
    if (!tag) return JSValueMakeNull(ctx);
    NxNodeRef r = nx_node_create_element(b->doc, tag);
    free(tag);
    mutated(b);
    return ret_id(ctx, r);
}

static JSValueRef p_create_text(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                                const JSValueRef argv[], void* user) {
    (void)fn; (void)self;
    NxDomBindings* b = (NxDomBindings*)user;
    char* text = str_arg(ctx, argv, argc, 0);
    if (!text) return JSValueMakeNull(ctx);
    NxNodeRef r = nx_node_create_text(b->doc, text, (int)strlen(text));
    free(text);
    mutated(b);
    return ret_id(ctx, r);
}

static JSValueRef p_append(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                           const JSValueRef argv[], void* user) {
    (void)fn; (void)self;
    NxDomBindings* b = (NxDomBindings*)user;
    NxNodeRef parent = (NxNodeRef)num_arg(ctx, argv, argc, 0);
    NxNodeRef child = (NxNodeRef)num_arg(ctx, argv, argc, 1);
    bool ok = parent && child && nx_node_append_child(b->doc, parent, child);
    if (ok) mutated(b);
    return JSValueMakeBoolean(ctx, ok);
}

static JSValueRef p_insert_before(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                                  const JSValueRef argv[], void* user) {
    (void)fn; (void)self;
    NxDomBindings* b = (NxDomBindings*)user;
    NxNodeRef parent = (NxNodeRef)num_arg(ctx, argv, argc, 0);
    NxNodeRef child = (NxNodeRef)num_arg(ctx, argv, argc, 1);
    NxNodeRef ref = (NxNodeRef)num_arg(ctx, argv, argc, 2);
    bool ok = parent && child && (ref ? nx_node_insert_before(b->doc, parent, child, ref)
                                      : nx_node_append_child(b->doc, parent, child));
    if (ok) mutated(b);
    return JSValueMakeBoolean(ctx, ok);
}

static JSValueRef p_remove(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                           const JSValueRef argv[], void* user) {
    (void)fn; (void)self;
    NxDomBindings* b = (NxDomBindings*)user;
    NxNodeRef parent = (NxNodeRef)num_arg(ctx, argv, argc, 0);
    NxNodeRef child = (NxNodeRef)num_arg(ctx, argv, argc, 1);
    bool ok = parent && child && nx_node_remove_child(b->doc, parent, child);
    if (ok) mutated(b);
    return JSValueMakeBoolean(ctx, ok);
}

static JSValueRef p_destroy(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                            const JSValueRef argv[], void* user) {
    (void)fn; (void)self;
    NxDomBindings* b = (NxDomBindings*)user;
    NxNodeRef n = (NxNodeRef)num_arg(ctx, argv, argc, 0);
    bool ok = n && nx_node_destroy(b->doc, n);
    if (ok) mutated(b);
    return JSValueMakeBoolean(ctx, ok);
}

static JSValueRef p_type(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                         const JSValueRef argv[], void* user) {
    (void)fn; (void)self;
    NxDomBindings* b = (NxDomBindings*)user;
    NxNodeRef n = (NxNodeRef)num_arg(ctx, argv, argc, 0);
    return JSValueMakeNumber(ctx, (double)nx_node_type(b->doc, n));
}

static JSValueRef p_name(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                         const JSValueRef argv[], void* user) {
    (void)fn; (void)self;
    NxDomBindings* b = (NxDomBindings*)user;
    NxNodeRef n = (NxNodeRef)num_arg(ctx, argv, argc, 0);
    const char* name = nx_node_name(b->doc, n);
    return nx_js_string(ctx, name ? name : "");
}

static JSValueRef p_parent(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                           const JSValueRef argv[], void* user) {
    (void)fn; (void)self;
    NxDomBindings* b = (NxDomBindings*)user;
    return ret_id(ctx, nx_node_parent(b->doc, (NxNodeRef)num_arg(ctx, argv, argc, 0)));
}

static JSValueRef p_children(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                             const JSValueRef argv[], void* user) {
    (void)fn; (void)self;
    NxDomBindings* b = (NxDomBindings*)user;
    NxNodeRef n = (NxNodeRef)num_arg(ctx, argv, argc, 0);
    JSValueRef vals[512];
    size_t count = 0;
    for (NxNodeRef c = nx_node_first_child(b->doc, n); c && count < 512;
         c = nx_node_next_sibling(b->doc, c))
        vals[count++] = JSValueMakeNumber(ctx, (double)c);
    return JSObjectMakeArray(ctx, count, vals, NULL);
}

static JSValueRef p_next(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                         const JSValueRef argv[], void* user) {
    (void)fn; (void)self;
    NxDomBindings* b = (NxDomBindings*)user;
    return ret_id(ctx, nx_node_next_sibling(b->doc, (NxNodeRef)num_arg(ctx, argv, argc, 0)));
}

static JSValueRef p_prev(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                         const JSValueRef argv[], void* user) {
    (void)fn; (void)self;
    NxDomBindings* b = (NxDomBindings*)user;
    return ret_id(ctx, nx_node_prev_sibling(b->doc, (NxNodeRef)num_arg(ctx, argv, argc, 0)));
}

static JSValueRef p_attr_get(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                             const JSValueRef argv[], void* user) {
    (void)fn; (void)self;
    NxDomBindings* b = (NxDomBindings*)user;
    NxNodeRef n = (NxNodeRef)num_arg(ctx, argv, argc, 0);
    char* name = str_arg(ctx, argv, argc, 1);
    if (!name) return JSValueMakeNull(ctx);
    const char* v = nx_node_get_attr(b->doc, n, name);
    free(name);
    return v ? nx_js_string(ctx, v) : JSValueMakeNull(ctx);
}

static JSValueRef p_attr_set(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                             const JSValueRef argv[], void* user) {
    (void)fn; (void)self;
    NxDomBindings* b = (NxDomBindings*)user;
    NxNodeRef n = (NxNodeRef)num_arg(ctx, argv, argc, 0);
    char* name = str_arg(ctx, argv, argc, 1);
    char* value = str_arg(ctx, argv, argc, 2);
    bool ok = false;
    if (name && value) ok = nx_node_set_attr(b->doc, n, name, value);
    free(name);
    free(value);
    if (ok) mutated(b);
    return JSValueMakeBoolean(ctx, ok);
}

static JSValueRef p_attr_remove(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                                const JSValueRef argv[], void* user) {
    (void)fn; (void)self;
    NxDomBindings* b = (NxDomBindings*)user;
    NxNodeRef n = (NxNodeRef)num_arg(ctx, argv, argc, 0);
    char* name = str_arg(ctx, argv, argc, 1);
    bool ok = false;
    if (name) ok = nx_node_remove_attr(b->doc, n, name);
    free(name);
    if (ok) mutated(b);
    return JSValueMakeBoolean(ctx, ok);
}

static JSValueRef p_text_get(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                             const JSValueRef argv[], void* user) {
    (void)fn; (void)self;
    NxDomBindings* b = (NxDomBindings*)user;
    NxNodeRef n = (NxNodeRef)num_arg(ctx, argv, argc, 0);
    char* text = nx_node_text_content(b->doc, n);
    if (!text) return nx_js_string(ctx, "");
    JSValueRef v = nx_js_string(ctx, text);
    free(text);
    return v;
}

static JSValueRef p_text_set(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                             const JSValueRef argv[], void* user) {
    (void)fn; (void)self;
    NxDomBindings* b = (NxDomBindings*)user;
    NxNodeRef n = (NxNodeRef)num_arg(ctx, argv, argc, 0);
    char* text = str_arg(ctx, argv, argc, 1);
    if (!text) return JSValueMakeBoolean(ctx, false);
    bool ok = false;
    NxNodeType t = nx_node_type(b->doc, n);
    if (t == NX_NODE_TEXT) {
        ok = nx_node_replace_text(b->doc, n, text, (int)strlen(text));
    } else if (t == NX_NODE_ELEMENT || t == NX_NODE_DOCUMENT) {
        /* replace all children with a single text node */
        NxNodeRef c = nx_node_first_child(b->doc, n);
        while (c) {
            NxNodeRef next = nx_node_next_sibling(b->doc, c);
            nx_node_remove_child(b->doc, n, c);
            nx_node_destroy(b->doc, c);
            c = next;
        }
        NxNodeRef tn = nx_node_create_text(b->doc, text, (int)strlen(text));
        ok = tn && nx_node_append_child(b->doc, n, tn);
    }
    free(text);
    if (ok) mutated(b);
    return JSValueMakeBoolean(ctx, ok);
}

/* Deep-copy a subtree between documents (fragments are parsed into a scratch
   document, then copied because nodes belong to one pool). */
static void copy_subtree(NxDocument* dst, NxDocument* src, NxNodeRef node, NxNodeRef parent) {
    NxNodeType t = nx_node_type(src, node);
    if (t == NX_NODE_TEXT) {
        int len = 0;
        const char* text = nx_node_text(src, node, &len);
        NxNodeRef n = nx_node_create_text(dst, text ? text : "", text ? len : 0);
        if (n) nx_node_append_child(dst, parent, n);
        return;
    }
    if (t == NX_NODE_COMMENT) {
        int len = 0;
        const char* text = nx_node_text(src, node, &len);
        NxNodeRef n = nx_node_create_comment(dst, text ? text : "", text ? len : 0);
        if (n) nx_node_append_child(dst, parent, n);
        return;
    }
    if (t != NX_NODE_ELEMENT) return;
    NxNodeRef el = nx_node_create_element(dst, nx_node_name(src, node));
    if (!el) return;
    int ac = nx_node_attr_count(src, node);
    for (int i = 0; i < ac; i++) {
        const char* name = nx_node_attr_name(src, node, i);
        const char* value = nx_node_attr_value(src, node, i);
        if (name && value) nx_node_set_attr(dst, el, name, value);
    }
    nx_node_append_child(dst, parent, el);
    for (NxNodeRef c = nx_node_first_child(src, node); c; c = nx_node_next_sibling(src, c))
        copy_subtree(dst, src, c, el);
}

static JSValueRef p_html_set(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                             const JSValueRef argv[], void* user) {
    (void)fn; (void)self;
    NxDomBindings* b = (NxDomBindings*)user;
    NxNodeRef n = (NxNodeRef)num_arg(ctx, argv, argc, 0);
    char* html = str_arg(ctx, argv, argc, 1);
    if (!html || !n) {
        free(html);
        return JSValueMakeBoolean(ctx, false);
    }
    int len = (int)strlen(html);
    NxDocument* scratch = nx_doc_new();
    bool ok = false;
    if (scratch && nx_html_parse(scratch, html, len, NULL)) {
        NxNodeRef body = nx_doc_query_selector(scratch, "body");
        NxNodeRef source = body ? body : nx_doc_root(scratch);
        NxNodeRef c = nx_node_first_child(b->doc, n);
        while (c) {
            NxNodeRef next = nx_node_next_sibling(b->doc, c);
            nx_node_remove_child(b->doc, n, c);
            nx_node_destroy(b->doc, c);
            c = next;
        }
        for (NxNodeRef ch = nx_node_first_child(scratch, source); ch;
             ch = nx_node_next_sibling(scratch, ch))
            copy_subtree(b->doc, scratch, ch, n);
        ok = true;
    }
    nx_doc_free(scratch);
    free(html);
    if (ok) mutated(b);
    return JSValueMakeBoolean(ctx, ok);
}

static JSValueRef p_listen(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                           const JSValueRef argv[], void* user) {
    (void)fn; (void)self;
    NxDomBindings* b = (NxDomBindings*)user;
    NxNodeRef n = (NxNodeRef)num_arg(ctx, argv, argc, 0);
    char* type = str_arg(ctx, argv, argc, 1);
    if (!n || !type || argc < 3) {
        free(type);
        return JSValueMakeBoolean(ctx, false);
    }
    if (!JSValueIsObject(ctx, argv[2]) || !JSObjectIsFunction(ctx, (JSObjectRef)argv[2])) {
        free(type);
        return JSValueMakeBoolean(ctx, false);
    }
    JSObjectRef target = (JSObjectRef)argv[2];
    for (int i = 0; i < b->listener_count; i++) {
        if (b->listeners[i].node == n && b->listeners[i].fn == target &&
            strcmp(b->listeners[i].type, type) == 0) {
            free(type);
            return JSValueMakeBoolean(ctx, true);
        }
    }
    if (b->listener_count == b->listener_cap) {
        int nc = b->listener_cap ? b->listener_cap * 2 : 8;
        NxJsListener* arr = (NxJsListener*)realloc(b->listeners, (size_t)nc * sizeof(*arr));
        if (!arr) {
            free(type);
            return JSValueMakeBoolean(ctx, false);
        }
        b->listeners = arr;
        b->listener_cap = nc;
    }
    b->listeners[b->listener_count].node = n;
    b->listeners[b->listener_count].type = type;
    b->listeners[b->listener_count].fn = target;
    b->listener_count++;
    JSValueProtect(ctx, target);
    return JSValueMakeBoolean(ctx, true);
}

static JSValueRef p_unlisten(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                             const JSValueRef argv[], void* user) {
    (void)fn; (void)self;
    NxDomBindings* b = (NxDomBindings*)user;
    NxNodeRef n = (NxNodeRef)num_arg(ctx, argv, argc, 0);
    char* type = str_arg(ctx, argv, argc, 1);
    int removed = 0;
    for (int i = b->listener_count - 1; i >= 0; i--) {
        bool match = b->listeners[i].node == n &&
                     (!type || strcmp(b->listeners[i].type, type) == 0);
        if (!match) continue;
        JSValueUnprotect(ctx, b->listeners[i].fn);
        free(b->listeners[i].type);
        b->listeners[i] = b->listeners[b->listener_count - 1];
        b->listener_count--;
        removed++;
    }
    free(type);
    return JSValueMakeNumber(ctx, removed);
}

static JSValueRef p_stop(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                         const JSValueRef argv[], void* user) {
    (void)ctx; (void)fn; (void)self; (void)argc; (void)argv;
    ((NxDomBindings*)user)->stop = true;
    return JSValueMakeUndefined(ctx);
}

static JSValueRef p_prevent(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                            const JSValueRef argv[], void* user) {
    (void)fn; (void)self; (void)argc; (void)argv;
    ((NxDomBindings*)user)->prevented = true;
    return JSValueMakeUndefined(ctx);
}

static JSValueRef p_now(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                        const JSValueRef argv[], void* user) {
    (void)fn; (void)self; (void)argc; (void)argv; (void)user;
    return JSValueMakeNumber(ctx, 0); /* host clock is injected by the loop */
}

static JSValueRef p_log(JSContextRef ctx, JSObjectRef fn, JSObjectRef self, size_t argc,
                        const JSValueRef argv[], void* user) {
    (void)fn; (void)self; (void)user;
    char* text = str_arg(ctx, argv, argc, 0);
    if (text) {
        NX_INFO("[script] %s", text);
        free(text);
    }
    return JSValueMakeUndefined(ctx);
}

typedef struct Prim {
    const char* name;
    NxJsNativeFn fn;
} Prim;

static const Prim PRIMS[] = {
    {"__nx_doc_id", p_doc_id},
    {"__nx_doc_element", p_doc_element},
    {"__nx_get_by_id", p_get_by_id},
    {"__nx_query", p_query},
    {"__nx_query_all", p_query_all},
    {"__nx_create", p_create},
    {"__nx_create_text", p_create_text},
    {"__nx_append", p_append},
    {"__nx_insert_before", p_insert_before},
    {"__nx_remove", p_remove},
    {"__nx_destroy", p_destroy},
    {"__nx_type", p_type},
    {"__nx_name", p_name},
    {"__nx_parent", p_parent},
    {"__nx_children", p_children},
    {"__nx_next", p_next},
    {"__nx_prev", p_prev},
    {"__nx_attr_get", p_attr_get},
    {"__nx_attr_set", p_attr_set},
    {"__nx_attr_remove", p_attr_remove},
    {"__nx_text_get", p_text_get},
    {"__nx_text_set", p_text_set},
    {"__nx_html_set", p_html_set},
    {"__nx_listen", p_listen},
    {"__nx_unlisten", p_unlisten},
    {"__nx_stop", p_stop},
    {"__nx_prevent", p_prevent},
    {"__nx_now", p_now},
    {"__nx_log", p_log},
};

/* ---- JS prelude ---------------------------------------------------------- */

static const char* PRELUDE =
    "(function(){\n"
    "  'use strict';\n"
    "  var N = globalThis;\n"
    "  var wrappers = new Map();\n"
    "  function Node(id){ this.__nxid = id; }\n"
    "  function Document(id){ Node.call(this, id); }\n"
    "  Document.prototype = Object.create(Node.prototype);\n"
    "  Document.prototype.constructor = Document;\n"
    "  function wrap(id){\n"
    "    if (!id) return null;\n"
    "    var key = Number(id);\n"
    "    var w = wrappers.get(key);\n"
    "    if (w) return w;\n"
    "    w = (key === N.__nx_doc_id()) ? new Document(key) : new Node(key);\n"
    "    wrappers.set(key, w);\n"
    "    return w;\n"
    "  }\n"
    "  globalThis.__nxWrap = wrap;\n"
    "  function prop(name, getter, setter){\n"
    "    Object.defineProperty(Node.prototype, name,\n"
    "      {get: getter, set: setter, configurable: true});\n"
    "  }\n"
    "  prop('nodeType', function(){ return N.__nx_type(this.__nxid); });\n"
    "  prop('nodeName', function(){ return N.__nx_name(this.__nxid); });\n"
    "  prop('tagName', function(){ return N.__nx_name(this.__nxid); });\n"
    "  prop('id', function(){ return N.__nx_attr_get(this.__nxid, 'id') || ''; },\n"
    "       function(v){ N.__nx_attr_set(this.__nxid, 'id', String(v)); });\n"
    "  prop('className', function(){ return N.__nx_attr_get(this.__nxid, 'class') || ''; },\n"
    "       function(v){ N.__nx_attr_set(this.__nxid, 'class', String(v)); });\n"
    "  prop('textContent', function(){ return N.__nx_text_get(this.__nxid); },\n"
    "       function(v){ N.__nx_text_set(this.__nxid, String(v)); });\n"
    "  prop('innerText', function(){ return N.__nx_text_get(this.__nxid); },\n"
    "       function(v){ N.__nx_text_set(this.__nxid, String(v)); });\n"
    "  prop('innerHTML', function(){ return ''; },\n"
    "       function(v){ N.__nx_html_set(this.__nxid, String(v)); });\n"
    "  prop('parentNode', function(){ return wrap(N.__nx_parent(this.__nxid)); });\n"
    "  prop('parentElement', function(){ return wrap(N.__nx_parent(this.__nxid)); });\n"
    "  prop('firstChild', function(){\n"
    "    var c = N.__nx_children(this.__nxid);\n"
    "    return c.length ? wrap(c[0]) : null;\n"
    "  });\n"
    "  prop('lastChild', function(){\n"
    "    var c = N.__nx_children(this.__nxid);\n"
    "    return c.length ? wrap(c[c.length - 1]) : null;\n"
    "  });\n"
    "  prop('nextSibling', function(){ return wrap(N.__nx_next(this.__nxid)); });\n"
    "  prop('previousSibling', function(){ return wrap(N.__nx_prev(this.__nxid)); });\n"
    "  prop('childNodes', function(){ return N.__nx_children(this.__nxid).map(wrap); });\n"
    "  prop('children', function(){ return N.__nx_children(this.__nxid).map(wrap); });\n"
    "  prop('childElementCount', function(){ return N.__nx_children(this.__nxid).length; });\n"
    "  Node.prototype.appendChild = function(child){\n"
    "    if (!child) return child;\n"
    "    N.__nx_append(this.__nxid, child.__nxid);\n"
    "    return child;\n"
    "  };\n"
    "  Node.prototype.append = function(){\n"
    "    for (var i = 0; i < arguments.length; i++) this.appendChild(arguments[i]);\n"
    "  };\n"
    "  Node.prototype.insertBefore = function(child, ref){\n"
    "    N.__nx_insert_before(this.__nxid, child.__nxid, ref ? ref.__nxid : 0);\n"
    "    return child;\n"
    "  };\n"
    "  Node.prototype.removeChild = function(child){\n"
    "    N.__nx_remove(this.__nxid, child.__nxid);\n"
    "    return child;\n"
    "  };\n"
    "  Node.prototype.remove = function(){\n"
    "    var p = N.__nx_parent(this.__nxid);\n"
    "    if (p) N.__nx_remove(p, this.__nxid);\n"
    "  };\n"
    "  Node.prototype.setAttribute = function(k, v){\n"
    "    N.__nx_attr_set(this.__nxid, String(k), String(v));\n"
    "  };\n"
    "  Node.prototype.getAttribute = function(k){\n"
    "    var v = N.__nx_attr_get(this.__nxid, String(k));\n"
    "    return v === null ? null : v;\n"
    "  };\n"
    "  Node.prototype.hasAttribute = function(k){\n"
    "    return N.__nx_attr_get(this.__nxid, String(k)) !== null;\n"
    "  };\n"
    "  Node.prototype.removeAttribute = function(k){\n"
    "    N.__nx_attr_remove(this.__nxid, String(k));\n"
    "  };\n"
    "  Node.prototype.addEventListener = function(t, fn){\n"
    "    if (typeof fn === 'function') N.__nx_listen(this.__nxid, String(t), fn);\n"
    "  };\n"
    "  Node.prototype.removeEventListener = function(t){\n"
    "    N.__nx_unlisten(this.__nxid, String(t));\n"
    "  };\n"
    "  Node.prototype.querySelector = function(sel){\n"
    "    return wrap(N.__nx_query(this.__nxid, String(sel)));\n"
    "  };\n"
    "  Node.prototype.querySelectorAll = function(sel){\n"
    "    return N.__nx_query_all(this.__nxid, String(sel)).map(wrap);\n"
    "  };\n"
    "  Node.prototype.getElementsByTagName = function(tag){\n"
    "    return this.querySelectorAll(String(tag));\n"
    "  };\n"
    "  function styleGet(id, prop){\n"
    "    var text = N.__nx_attr_get(id, 'style') || '';\n"
    "    var parts = text.split(';');\n"
    "    for (var i = 0; i < parts.length; i++) {\n"
    "      var idx = parts[i].indexOf(':');\n"
    "      if (idx < 0) continue;\n"
    "      if (parts[i].slice(0, idx).trim().toLowerCase() === prop) {\n"
    "        return parts[i].slice(idx + 1).trim();\n"
    "      }\n"
    "    }\n"
    "    return '';\n"
    "  }\n"
    "  function styleSet(id, prop, value){\n"
    "    var text = N.__nx_attr_get(id, 'style') || '';\n"
    "    var kept = [];\n"
    "    text.split(';').forEach(function (p) {\n"
    "      var part = p.trim();\n"
    "      if (!part) return;\n"
    "      var idx = part.indexOf(':');\n"
    "      if (idx >= 0 && part.slice(0, idx).trim().toLowerCase() === prop) return;\n"
    "      kept.push(part);\n"
    "    });\n"
    "    if (value !== null && value !== undefined && String(value).length)\n"
    "      kept.push(prop + ': ' + String(value));\n"
    "    if (kept.length) N.__nx_attr_set(id, 'style', kept.join('; '));\n"
    "    else N.__nx_attr_remove(id, 'style');\n"
    "  }\n"
    "  function Style(id){ this.__nxid = id; }\n"
    "  Style.prototype.setProperty = function(p, v){\n"
    "    styleSet(this.__nxid, String(p).toLowerCase(), v);\n"
    "  };\n"
    "  Style.prototype.getPropertyValue = function(p){\n"
    "    return styleGet(this.__nxid, String(p).toLowerCase());\n"
    "  };\n"
    "  Style.prototype.removeProperty = function(p){\n"
    "    styleSet(this.__nxid, String(p).toLowerCase(), null);\n"
    "  };\n"
    "  ['color', 'background', 'backgroundColor', 'fontSize', 'fontWeight', 'width',\n"
    "   'height', 'display', 'textAlign', 'lineHeight', 'margin', 'padding',\n"
    "   'borderWidth', 'borderColor', 'opacity', 'marginTop', 'marginBottom',\n"
    "   'marginLeft', 'marginRight', 'paddingTop', 'paddingBottom', 'paddingLeft',\n"
    "   'paddingRight', 'borderRadius', 'textDecoration'].forEach(function (p) {\n"
    "    var css = p.replace(/[A-Z]/g, function (m) { return '-' + m.toLowerCase(); });\n"
    "    Object.defineProperty(Style.prototype, p, {\n"
    "      get: function () { return styleGet(this.__nxid, css); },\n"
    "      set: function (v) { styleSet(this.__nxid, css, v); },\n"
    "      configurable: true\n"
    "    });\n"
    "  });\n"
    "  prop('style', function(){\n"
    "    if (!this.__nxstyle) this.__nxstyle = new Style(this.__nxid);\n"
    "    return this.__nxstyle;\n"
    "  });\n"
    "  function ClassList(id){ this.__nxid = id; }\n"
    "  ClassList.prototype._get = function(){\n"
    "    var c = N.__nx_attr_get(this.__nxid, 'class') || '';\n"
    "    return c.split(/\\s+/).filter(function (s) { return s.length > 0; });\n"
    "  };\n"
    "  ClassList.prototype._set = function(list){\n"
    "    N.__nx_attr_set(this.__nxid, 'class', list.join(' '));\n"
    "  };\n"
    "  ClassList.prototype.add = function(){\n"
    "    var list = this._get();\n"
    "    for (var i = 0; i < arguments.length; i++)\n"
    "      if (list.indexOf(String(arguments[i])) < 0) list.push(String(arguments[i]));\n"
    "    this._set(list);\n"
    "  };\n"
    "  ClassList.prototype.remove = function(){\n"
    "    var list = this._get();\n"
    "    for (var i = 0; i < arguments.length; i++) {\n"
    "      var idx = list.indexOf(String(arguments[i]));\n"
    "      if (idx >= 0) list.splice(idx, 1);\n"
    "    }\n"
    "    this._set(list);\n"
    "  };\n"
    "  ClassList.prototype.contains = function(c){\n"
    "    return this._get().indexOf(String(c)) >= 0;\n"
    "  };\n"
    "  ClassList.prototype.toggle = function(c){\n"
    "    if (this.contains(c)) { this.remove(c); return false; }\n"
    "    this.add(c);\n"
    "    return true;\n"
    "  };\n"
    "  prop('classList', function(){\n"
    "    if (!this.__nxclasslist) this.__nxclasslist = new ClassList(this.__nxid);\n"
    "    return this.__nxclasslist;\n"
    "  });\n"
    "  prop('value', function(){ return N.__nx_attr_get(this.__nxid, 'value') || ''; },\n"
    "       function(v){ N.__nx_attr_set(this.__nxid, 'value', String(v)); });\n"
    "  Document.prototype.createElement = function(tag){\n"
    "    return wrap(N.__nx_create(String(tag)));\n"
    "  };\n"
    "  Document.prototype.createTextNode = function(text){\n"
    "    return wrap(N.__nx_create_text(String(text)));\n"
    "  };\n"
    "  Document.prototype.getElementById = function(id){\n"
    "    return wrap(N.__nx_get_by_id(String(id)));\n"
    "  };\n"
    "  prop('body', function(){ return wrap(N.__nx_query(N.__nx_doc_id(), 'body')); });\n"
    "  prop('documentElement', function(){ return wrap(N.__nx_doc_element()); });\n"
    "  prop('title', function(){\n"
    "    var t = wrap(N.__nx_query(N.__nx_doc_id(), 'title'));\n"
    "    return t ? t.textContent : '';\n"
    "  }, function(v){\n"
    "    var t = wrap(N.__nx_query(N.__nx_doc_id(), 'title'));\n"
    "    if (t) t.textContent = String(v);\n"
    "  });\n"
    "  globalThis.__nxMakeEvent = function(type, targetId, currentId, key, x, y){\n"
    "    return {\n"
    "      type: type,\n"
    "      target: wrap(targetId),\n"
    "      currentTarget: wrap(currentId),\n"
    "      key: (typeof key === 'number') ? key : undefined,\n"
    "      keyCode: (typeof key === 'number') ? key : 0,\n"
    "      clientX: (typeof x === 'number') ? x : 0,\n"
    "      clientY: (typeof y === 'number') ? y : 0,\n"
    "      defaultPrevented: false,\n"
    "      stopPropagation: function(){ N.__nx_stop(); },\n"
    "      preventDefault: function(){ N.__nx_prevent(); this.defaultPrevented = true; }\n"
    "    };\n"
    "  };\n"
    "  globalThis.console = {\n"
    "    log: function(){\n"
    "      var a = [];\n"
    "      for (var i = 0; i < arguments.length; i++) a.push(String(arguments[i]));\n"
    "      N.__nx_log(a.join(' '));\n"
    "    },\n"
    "    warn: function(){\n"
    "      var a = [];\n"
    "      for (var i = 0; i < arguments.length; i++) a.push(String(arguments[i]));\n"
    "      N.__nx_log('warn: ' + a.join(' '));\n"
    "    },\n"
    "    error: function(){\n"
    "      var a = [];\n"
    "      for (var i = 0; i < arguments.length; i++) a.push(String(arguments[i]));\n"
    "      N.__nx_log('error: ' + a.join(' '));\n"
    "    }\n"
    "  };\n"
    "  globalThis.window = globalThis;\n"
    "  globalThis.document = wrap(N.__nx_doc_id());\n"
    "})();\n";

/* ---- public API ---------------------------------------------------------- */

static JSValueRef make_event(NxDomBindings* b, NxNodeRef target, NxNodeRef current,
                             const char* type, const NxEventPayload* payload) {
    JSContextRef ctx = ctx_of(b);
    JSStringRef key = JSStringCreateWithUTF8CString("__nxMakeEvent");
    JSValueRef fnv =
        JSObjectGetProperty(ctx, JSContextGetGlobalObject(ctx), key, NULL);
    JSStringRelease(key);
    if (!fnv || !JSValueIsObject(ctx, fnv)) return NULL;
    JSValueRef args[6];
    args[0] = nx_js_string(ctx, type);
    args[1] = JSValueMakeNumber(ctx, (double)target);
    args[2] = JSValueMakeNumber(ctx, (double)current);
    args[3] = payload ? JSValueMakeNumber(ctx, (double)payload->key) : JSValueMakeUndefined(ctx);
    args[4] = payload ? JSValueMakeNumber(ctx, (double)payload->x) : JSValueMakeUndefined(ctx);
    args[5] = payload ? JSValueMakeNumber(ctx, (double)payload->y) : JSValueMakeUndefined(ctx);
    return JSObjectCallAsFunction(ctx, (JSObjectRef)fnv, NULL, 6, args, NULL);
}

NxDomBindings* nx_dom_bind_new(NxJs* js, NxDocument* doc) {
    if (!js || !doc) return NULL;
    NxDomBindings* b = (NxDomBindings*)calloc(1, sizeof(*b));
    if (!b) return NULL;
    b->js = js;
    b->doc = doc;

    bool ok = true;
    for (size_t i = 0; i < sizeof(PRIMS) / sizeof(PRIMS[0]); i++)
        if (!nx_js_set_function(js, PRIMS[i].name, PRIMS[i].fn, b)) ok = false;
    if (!ok) NX_WARN("dom bindings: some primitives could not be installed");

    char* err = NULL;
    if (!nx_js_eval(js, PRELUDE, "<nativax-prelude>", &err)) {
        NX_ERROR("dom bindings prelude failed: %s", err ? err : "unknown");
        free(err);
        nx_dom_bind_free(b);
        return NULL;
    }
    return b;
}

void nx_dom_bind_set_mutation_cb(NxDomBindings* b, void (*cb)(void* user), void* user) {
    if (!b) return;
    b->mutation_cb = cb;
    b->mutation_user = user;
}

void nx_dom_bind_free(NxDomBindings* b) {
    if (!b) return;
    JSContextRef ctx = nx_js_ctx(b->js);
    for (int i = 0; i < b->listener_count; i++) {
        JSValueUnprotect(ctx, b->listeners[i].fn);
        free(b->listeners[i].type);
    }
    free(b->listeners);
    free(b);
}

int nx_dom_listener_count(const NxDomBindings* b) { return b ? b->listener_count : 0; }

bool nx_dom_dispatch_js(NxDomBindings* b, NxNodeRef target, const char* type) {
    return nx_dom_dispatch_js_event(b, target, type, NULL);
}

bool nx_dom_dispatch_js_event(NxDomBindings* b, NxNodeRef target, const char* type,
                              const NxEventPayload* payload) {
    if (!b || !target || !type) return false;
    NxDocument* doc = b->doc;
    NxNodeRef path[NX_MAX_DEPTH];
    int depth = 0;
    for (NxNodeRef n = target; n && depth < NX_MAX_DEPTH; n = nx_node_parent(doc, n))
        path[depth++] = n;

    b->stop = false;
    b->prevented = false;
    JSContextRef ctx = nx_js_ctx(b->js);
    for (int i = 0; i < depth && !b->stop; i++) {
        for (int j = 0; j < b->listener_count && !b->stop; j++) {
            if (b->listeners[j].node != path[i] || strcmp(b->listeners[j].type, type) != 0)
                continue;
            JSValueRef ev = make_event(b, target, path[i], type, payload);
            if (!ev) continue;
            JSValueRef exc = NULL;
            JSObjectCallAsFunction(ctx, b->listeners[j].fn, NULL, 1, &ev, &exc);
            if (exc) NX_WARN("script listener for '%s' threw an exception", type);
        }
    }
    return !b->prevented;
}
