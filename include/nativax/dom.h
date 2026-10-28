#ifndef NATIVAX_DOM_H
#define NATIVAX_DOM_H

/*
    DOM: node pool with generation-checked handles (the only node currency
    crossing module boundaries — scripts and bindings see int32 handles,
    scalars and JSON, never pointers), attributes, traversal, mutation,
    id index and event dispatch (capture + bubble, once, preventDefault,
    stopPropagation).

    Limits (documented, mirrors the Dart runtime): 100 000 nodes, depth 200.
*/

#include <stdbool.h>
#include <stdint.h>

typedef struct NxDocument NxDocument;
typedef int32_t NxNodeRef; /* generation-checked handle; 0 = invalid */

typedef enum NxNodeType {
    NX_NODE_DOCUMENT = 1,
    NX_NODE_ELEMENT = 2,
    NX_NODE_TEXT = 3,
    NX_NODE_COMMENT = 4,
} NxNodeType;

#define NX_MAX_NODES 100000
#define NX_MAX_DEPTH 200

/* ---- document lifecycle ---- */
NxDocument* nx_doc_new(void);
void nx_doc_free(NxDocument* doc);
NxNodeRef nx_doc_root(NxDocument* doc); /* the document node */

/* ---- node accessors (NULL/0-safe) ---- */
NxNodeType nx_node_type(NxDocument* doc, NxNodeRef node);
const char* nx_node_name(NxDocument* doc, NxNodeRef node); /* interned; "#text"/"#comment" */
const char* nx_node_text(NxDocument* doc, NxNodeRef node, int* len_out); /* text nodes */
NxNodeRef nx_node_parent(NxDocument* doc, NxNodeRef node);
NxNodeRef nx_node_first_child(NxDocument* doc, NxNodeRef node);
NxNodeRef nx_node_last_child(NxDocument* doc, NxNodeRef node);
NxNodeRef nx_node_next_sibling(NxDocument* doc, NxNodeRef node);
NxNodeRef nx_node_prev_sibling(NxDocument* doc, NxNodeRef node);
int nx_node_depth(NxDocument* doc, NxNodeRef node);

/* ---- attributes ---- */
int nx_node_attr_count(NxDocument* doc, NxNodeRef node);
const char* nx_node_attr_name(NxDocument* doc, NxNodeRef node, int i);
const char* nx_node_attr_value(NxDocument* doc, NxNodeRef node, int i);
const char* nx_node_get_attr(NxDocument* doc, NxNodeRef node, const char* name);
bool nx_node_set_attr(NxDocument* doc, NxNodeRef node, const char* name, const char* value);
bool nx_node_remove_attr(NxDocument* doc, NxNodeRef node, const char* name);

/* ---- construction & mutation ---- */
NxNodeRef nx_node_create_element(NxDocument* doc, const char* tag);
NxNodeRef nx_node_create_text(NxDocument* doc, const char* text, int len);
NxNodeRef nx_node_create_comment(NxDocument* doc, const char* text, int len);
bool nx_node_append_child(NxDocument* doc, NxNodeRef parent, NxNodeRef child);
bool nx_node_insert_before(NxDocument* doc, NxNodeRef parent, NxNodeRef child, NxNodeRef before);
bool nx_node_remove_child(NxDocument* doc, NxNodeRef parent, NxNodeRef child);
bool nx_node_replace_text(NxDocument* doc, NxNodeRef text_node, const char* text, int len);
bool nx_node_is_ancestor(NxDocument* doc, NxNodeRef ancestor, NxNodeRef node);
/* Destroy a node and its subtree: detached, slots freed, handles to it and
   its descendants become invalid. Document node cannot be destroyed. */
bool nx_node_destroy(NxDocument* doc, NxNodeRef node);

/* Destroy every subtree that is detached from the document root (nodes
   removed with remove()/removeChild but never destroyed). There is no GC for
   native nodes, so detached subtrees otherwise occupy their slots forever:
   repeated create+remove churn grew the pool until NX_MAX_NODES. Call only
   when no live reference to detached nodes can exist — e.g. right after the
   JS context was reset (all wrappers died with it). Returns nodes destroyed. */
int nx_doc_reap_detached(NxDocument* doc);

/* ---- ids & queries ---- */
NxNodeRef nx_doc_get_element_by_id(NxDocument* doc, const char* id);
/* very small querySelector subset: "tag", "#id", ".class", "tag.class",
   "tag#id", descendant chain "a b"; NULL when no match (documented) */
NxNodeRef nx_doc_query_selector(NxDocument* doc, const char* selector);
int nx_doc_query_selector_all(NxDocument* doc, const char* selector, NxNodeRef* out, int max);

/* ---- text & serialization ---- */
char* nx_node_text_content(NxDocument* doc, NxNodeRef node); /* deep, caller frees */
char* nx_node_serialize(NxDocument* doc, NxNodeRef node);    /* HTML, caller frees */
char* nx_html_escape(const char* s, int len);                /* attr/text escaping */
char* nx_html_unescape(const char* s, int len, int* out_len); /* entity decoding */

/* ---- events ---- */
typedef struct NxEvent {
    const char* type;      /* interned */
    NxNodeRef target;
    NxNodeRef current_target;
    int event_phase;       /* 1 capture, 2 target, 3 bubble */
    bool bubbles;
    bool cancelable;
    bool default_prevented;
    bool propagation_stopped;
    bool immediate_stopped;
    int32_t detail;        /* scalar payload (click count etc.) */
    const char* str_data;  /* scalar payload (input value etc.), optional */
} NxEvent;

typedef void (*NxEventCallback)(NxDocument* doc, NxEvent* ev, void* user);

typedef struct NxListenerSpec {
    const char* type;
    NxEventCallback cb;
    void* user;
    bool capture;
    bool once;
} NxListenerSpec;

bool nx_event_make(NxEvent* ev, const char* type, bool bubbles, bool cancelable);
bool nx_node_add_listener(NxDocument* doc, NxNodeRef node, const NxListenerSpec* spec);
bool nx_node_remove_listener(NxDocument* doc, NxNodeRef node, const char* type, bool capture,
                             NxEventCallback cb, void* user);
/* Full capture/bubble dispatch; returns true when default was NOT prevented. */
bool nx_event_dispatch(NxDocument* doc, NxNodeRef target, NxEvent* ev);

/* string interning used by parser + dom (case-sensitive canonical pointers) */
const char* nx_intern(NxDocument* doc, const char* s, int len);

/* Slot index behind a handle (0 for the invalid handle): lets callers index
   dense per-node arrays sized NX_MAX_NODES with a handle. */
int32_t nx_node_index(NxNodeRef ref);

/* Highest allocated slot + 1: the smallest dense array that can be indexed by
   any live handle. Bounds per-node arrays to the document's real size instead
   of the 100k hard limit. */
int nx_node_slot_bound(NxDocument* doc);

#endif /* NATIVAX_DOM_H */
