#include "nativax/dom.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ------------------------------------------------------------------ */
/* handles                                                            */
/* ------------------------------------------------------------------ */
/* handle layout: [gen:12][idx:20] — idx 0..0xFFFFF (>= NX_MAX_NODES) */
#define NX_HANDLE_IDX_MASK 0xFFFFFu
#define NX_HANDLE_GEN_SHIFT 20

typedef struct NxAttr {
    const char* name; /* interned, lowercased */
    char* value;      /* owned */
} NxAttr;

typedef struct NxListener {
    const char* type; /* interned */
    NxEventCallback cb;
    void* user;
    bool capture;
    bool once;
} NxListener;

typedef struct NxNode {
    uint16_t type; /* NxNodeType; 0 = free slot */
    uint16_t gen;
    const char* tag; /* interned, lowercased; NULL for text/comment/document */
    char* text;      /* owned; text/comment content */
    int text_len;
    NxAttr* attrs;
    int attr_count, attr_cap;
    int32_t parent, first_child, last_child, prev, next; /* raw slot indices, -1 none */
    NxListener* listeners;
    int listener_count, listener_cap;
} NxNode;

/* small string -> slot hash map (open addressing, FNV-1a) */
typedef struct IdEntry {
    char* key;   /* owned; NULL = empty; (char*)1 = tombstone */
    int32_t idx; /* slot index */
} IdEntry;

struct NxDocument {
    NxNode* nodes;
    int count, cap;
    int free_head; /* singly linked free list through nodes[i].next */
    /* string interning */
    const char** strings;
    int str_count, str_cap;
    uint32_t* str_hash; /* indices into strings */
    int hash_cap;
    /* id index */
    IdEntry* ids;
    int id_count, id_cap;
};

static uint32_t fnv1a(const char* s, int len) {
    uint32_t h = 2166136261u;
    for (int i = 0; i < len; i++) {
        h ^= (unsigned char)s[i];
        h *= 16777619u;
    }
    return h;
}

/* ---- interning ---- */
static void intern_rehash(NxDocument* doc) {
    int new_cap = doc->hash_cap * 2;
    uint32_t* nh = calloc((size_t)new_cap, sizeof(uint32_t));
    for (int i = 0; i < doc->str_count; i++) {
        const char* s = doc->strings[i];
        uint32_t h = fnv1a(s, (int)strlen(s)) & (uint32_t)(new_cap - 1);
        while (nh[h]) h = (h + 1) & (uint32_t)(new_cap - 1);
        nh[h] = (uint32_t)(i + 1);
    }
    free(doc->str_hash);
    doc->str_hash = nh;
    doc->hash_cap = new_cap;
}

const char* nx_intern(NxDocument* doc, const char* s, int len) {
    if (!s) return NULL;
    if (len < 0) len = (int)strlen(s);
    if (doc->hash_cap == 0) {
        doc->hash_cap = 64;
        doc->str_hash = calloc((size_t)doc->hash_cap, sizeof(uint32_t));
    }
    uint32_t h = fnv1a(s, len) & (uint32_t)(doc->hash_cap - 1);
    while (doc->str_hash[h]) {
        const char* c = doc->strings[doc->str_hash[h] - 1];
        if ((int)strlen(c) == len && memcmp(c, s, (size_t)len) == 0) return c;
        h = (h + 1) & (uint32_t)(doc->hash_cap - 1);
    }
    char* copy = malloc((size_t)len + 1);
    memcpy(copy, s, (size_t)len);
    copy[len] = '\0';
    if (doc->str_count == doc->str_cap) {
        doc->str_cap = doc->str_cap ? doc->str_cap * 2 : 64;
        doc->strings = realloc(doc->strings, (size_t)doc->str_cap * sizeof(char*));
    }
    doc->strings[doc->str_count] = copy;
    doc->str_hash[h] = (uint32_t)(doc->str_count + 1);
    doc->str_count++;
    if (doc->str_count * 4 >= doc->hash_cap * 3) intern_rehash(doc);
    return copy;
}

/* ---- id index ---- */
static void idmap_rehash(NxDocument* doc) {
    int new_cap = doc->id_cap * 2;
    IdEntry* ne = calloc((size_t)new_cap, sizeof(IdEntry));
    for (int i = 0; i < doc->id_cap; i++) {
        if (doc->ids[i].key && doc->ids[i].key != (char*)1) {
            uint32_t h = fnv1a(doc->ids[i].key, (int)strlen(doc->ids[i].key)) &
                         (uint32_t)(new_cap - 1);
            while (ne[h].key) h = (h + 1) & (uint32_t)(new_cap - 1);
            ne[h] = doc->ids[i];
        } else if (doc->ids[i].key == (char*)1) {
            /* tombstone: re-insert as empty (probe continues past it) */
        }
    }
    free(doc->ids);
    doc->ids = ne;
    doc->id_cap = new_cap;
}

static void idmap_set(NxDocument* doc, const char* key, int32_t idx) {
    if (doc->id_cap == 0) {
        doc->id_cap = 32;
        doc->ids = calloc((size_t)doc->id_cap, sizeof(IdEntry));
    }
    if ((doc->id_count + 1) * 4 >= doc->id_cap * 3) idmap_rehash(doc);
    uint32_t h = fnv1a(key, (int)strlen(key)) & (uint32_t)(doc->id_cap - 1);
    for (;;) {
        if (!doc->ids[h].key || doc->ids[h].key == (char*)1) {
            if (!doc->ids[h].key) doc->id_count++;
            doc->ids[h].key = strdup(key);
            doc->ids[h].idx = idx;
            return;
        }
        if (strcmp(doc->ids[h].key, key) == 0) {
            doc->ids[h].idx = idx;
            return;
        }
        h = (h + 1) & (uint32_t)(doc->id_cap - 1);
    }
}

static int32_t idmap_get(NxDocument* doc, const char* key) {
    if (!doc->id_cap) return -1;
    uint32_t h = fnv1a(key, (int)strlen(key)) & (uint32_t)(doc->id_cap - 1);
    for (int probe = 0; probe < doc->id_cap; probe++) {
        if (!doc->ids[h].key) return -1;
        if (doc->ids[h].key != (char*)1 && strcmp(doc->ids[h].key, key) == 0) {
            return doc->ids[h].idx;
        }
        h = (h + 1) & (uint32_t)(doc->id_cap - 1);
    }
    return -1;
}

static void idmap_remove(NxDocument* doc, const char* key) {
    if (!doc->id_cap) return;
    uint32_t h = fnv1a(key, (int)strlen(key)) & (uint32_t)(doc->id_cap - 1);
    for (int probe = 0; probe < doc->id_cap; probe++) {
        if (!doc->ids[h].key) return;
        if (doc->ids[h].key != (char*)1 && strcmp(doc->ids[h].key, key) == 0) {
            free(doc->ids[h].key);
            doc->ids[h].key = (char*)1; /* tombstone */
            doc->ids[h].idx = -1;
            doc->id_count--;
            return;
        }
        h = (h + 1) & (uint32_t)(doc->id_cap - 1);
    }
}

/* ---- slots & handles ---- */
static NxNode* slot(NxDocument* doc, NxNodeRef ref) {
    if (!doc || !ref) return NULL;
    uint32_t idx = (uint32_t)ref & NX_HANDLE_IDX_MASK;
    uint32_t gen = (uint32_t)ref >> NX_HANDLE_GEN_SHIFT;
    if (idx >= (uint32_t)doc->count) return NULL;
    NxNode* n = &doc->nodes[idx];
    if (n->type == 0 || n->gen != (uint16_t)gen) return NULL;
    return n;
}

static NxNodeRef handle_of(NxDocument* doc, int32_t idx) {
    NxNode* n = &doc->nodes[idx];
    return (NxNodeRef)(((uint32_t)n->gen << NX_HANDLE_GEN_SHIFT) | (uint32_t)idx);
}

static int32_t alloc_slot2(NxDocument* doc, uint16_t keep_gen) {
    int32_t idx;
    if (doc->free_head >= 0) {
        idx = doc->free_head;
        doc->free_head = doc->nodes[idx].next;
    } else {
        if (doc->count >= NX_MAX_NODES) return -1;
        if (doc->count == doc->cap) {
            doc->cap = doc->cap ? doc->cap * 2 : 256;
            doc->nodes = realloc(doc->nodes, (size_t)doc->cap * sizeof(NxNode));
        }
        idx = doc->count++;
        keep_gen = 0;
    }
    NxNode* n = &doc->nodes[idx];
    memset(n, 0, sizeof(*n));
    n->gen = keep_gen;
    n->parent = n->first_child = n->last_child = n->prev = n->next = -1;
    return idx;
}

static void free_slot(NxDocument* doc, int32_t idx) {
    NxNode* n = &doc->nodes[idx];
    if (n->type == NX_NODE_ELEMENT) {
        const char* in_id = nx_intern(doc, "id", 2);
        for (int i = 0; i < n->attr_count; i++) {
            if (n->attrs[i].name == in_id) idmap_remove(doc, n->attrs[i].value);
        }
    }
    for (int i = 0; i < n->attr_count; i++) free((void*)n->attrs[i].value);
    free(n->attrs);
    free(n->text);
    free(n->listeners);
    n->type = 0;
    n->gen++; /* invalidate old handles */
    n->next = doc->free_head;
    doc->free_head = idx;
}

/* ---- lifecycle ---- */
NxDocument* nx_doc_new(void) {
    NxDocument* doc = calloc(1, sizeof(NxDocument));
    doc->free_head = -1;
    int32_t root = alloc_slot2(doc, 0);
    doc->nodes[root].gen = 1; /* handle 0 is reserved as invalid */
    doc->nodes[root].type = NX_NODE_DOCUMENT;
    doc->nodes[root].tag = nx_intern(doc, "#document", -1);
    return doc;
}

void nx_doc_free(NxDocument* doc) {
    if (!doc) return;
    for (int i = 0; i < doc->count; i++) {
        NxNode* n = &doc->nodes[i];
        if (n->type == 0) continue;
        for (int j = 0; j < n->attr_count; j++) free((void*)n->attrs[j].value);
        free(n->attrs);
        free(n->text);
        free(n->listeners);
    }
    free(doc->nodes);
    for (int i = 0; i < doc->str_count; i++) free((void*)doc->strings[i]);
    free(doc->strings);
    free(doc->str_hash);
    for (int i = 0; i < doc->id_cap; i++) {
        if (doc->ids[i].key && doc->ids[i].key != (char*)1) free(doc->ids[i].key);
    }
    free(doc->ids);
    free(doc);
}

NxNodeRef nx_doc_root(NxDocument* doc) { return doc ? handle_of(doc, 0) : 0; }

int nx_node_slot_bound(NxDocument* doc) { return doc ? doc->count : 0; }

int32_t nx_node_index(NxNodeRef ref) {
    return (int32_t)((uint32_t)ref & NX_HANDLE_IDX_MASK);
}

/* ---- accessors ---- */
NxNodeType nx_node_type(NxDocument* doc, NxNodeRef node) {
    NxNode* n = slot(doc, node);
    return n ? (NxNodeType)n->type : (NxNodeType)0;
}

const char* nx_node_name(NxDocument* doc, NxNodeRef node) {
    NxNode* n = slot(doc, node);
    if (!n) return NULL;
    if (n->type == NX_NODE_TEXT) return "#text";
    if (n->type == NX_NODE_COMMENT) return "#comment";
    return n->tag;
}

const char* nx_node_text(NxDocument* doc, NxNodeRef node, int* len_out) {
    NxNode* n = slot(doc, node);
    if (!n || (n->type != NX_NODE_TEXT && n->type != NX_NODE_COMMENT)) {
        if (len_out) *len_out = 0;
        return NULL;
    }
    if (len_out) *len_out = n->text_len;
    return n->text ? n->text : "";
}

NxNodeRef nx_node_parent(NxDocument* doc, NxNodeRef node) {
    NxNode* n = slot(doc, node);
    if (!n || n->parent < 0) return 0;
    return handle_of(doc, n->parent);
}
NxNodeRef nx_node_first_child(NxDocument* doc, NxNodeRef node) {
    NxNode* n = slot(doc, node);
    if (!n || n->first_child < 0) return 0;
    return handle_of(doc, n->first_child);
}
NxNodeRef nx_node_last_child(NxDocument* doc, NxNodeRef node) {
    NxNode* n = slot(doc, node);
    if (!n || n->last_child < 0) return 0;
    return handle_of(doc, n->last_child);
}
NxNodeRef nx_node_next_sibling(NxDocument* doc, NxNodeRef node) {
    NxNode* n = slot(doc, node);
    if (!n || n->next < 0) return 0;
    return handle_of(doc, n->next);
}
NxNodeRef nx_node_prev_sibling(NxDocument* doc, NxNodeRef node) {
    NxNode* n = slot(doc, node);
    if (!n || n->prev < 0) return 0;
    return handle_of(doc, n->prev);
}

int nx_node_depth(NxDocument* doc, NxNodeRef node) {
    int d = 0;
    NxNodeRef cur = node;
    while (cur) {
        cur = nx_node_parent(doc, cur);
        if (++d > NX_MAX_DEPTH + 8) break;
    }
    return d;
}

/* ---- attributes ---- */
int nx_node_attr_count(NxDocument* doc, NxNodeRef node) {
    NxNode* n = slot(doc, node);
    return n ? n->attr_count : 0;
}
const char* nx_node_attr_name(NxDocument* doc, NxNodeRef node, int i) {
    NxNode* n = slot(doc, node);
    if (!n || i < 0 || i >= n->attr_count) return NULL;
    return n->attrs[i].name;
}
const char* nx_node_attr_value(NxDocument* doc, NxNodeRef node, int i) {
    NxNode* n = slot(doc, node);
    if (!n || i < 0 || i >= n->attr_count) return NULL;
    return n->attrs[i].value;
}
const char* nx_node_get_attr(NxDocument* doc, NxNodeRef node, const char* name) {
    NxNode* n = slot(doc, node);
    if (!n) return NULL;
    const char* in = nx_intern(doc, name, -1);
    for (int i = 0; i < n->attr_count; i++) {
        if (n->attrs[i].name == in) return n->attrs[i].value;
    }
    return NULL;
}

bool nx_node_set_attr(NxDocument* doc, NxNodeRef node, const char* name, const char* value) {
    NxNode* n = slot(doc, node);
    if (!n || !name || !value) return false;
    const char* in = nx_intern(doc, name, -1);
    for (int i = 0; i < n->attr_count; i++) {
        if (n->attrs[i].name == in) {
            if (in == nx_intern(doc, "id", 2)) idmap_remove(doc, n->attrs[i].value);
            free((void*)n->attrs[i].value);
            n->attrs[i].value = strdup(value);
            if (in == nx_intern(doc, "id", 2)) {
                idmap_set(doc, value, (int32_t)((uint32_t)node & NX_HANDLE_IDX_MASK));
            }
            return true;
        }
    }
    if (n->attr_count == n->attr_cap) {
        n->attr_cap = n->attr_cap ? n->attr_cap * 2 : 4;
        n->attrs = realloc(n->attrs, (size_t)n->attr_cap * sizeof(NxAttr));
    }
    n->attrs[n->attr_count].name = in;
    n->attrs[n->attr_count].value = strdup(value);
    n->attr_count++;
    if (in == nx_intern(doc, "id", 2)) idmap_set(doc, value, (int32_t)((uint32_t)node & NX_HANDLE_IDX_MASK));
    return true;
}

bool nx_node_remove_attr(NxDocument* doc, NxNodeRef node, const char* name) {
    NxNode* n = slot(doc, node);
    if (!n) return false;
    const char* in = nx_intern(doc, name, -1);
    for (int i = 0; i < n->attr_count; i++) {
        if (n->attrs[i].name == in) {
            if (in == nx_intern(doc, "id", 2)) idmap_remove(doc, n->attrs[i].value);
            free((void*)n->attrs[i].value);
            n->attrs[i] = n->attrs[n->attr_count - 1];
            n->attr_count--;
            return true;
        }
    }
    return false;
}

/* ---- construction ---- */
static int32_t new_node(NxDocument* doc, uint16_t type, const char* tag, const char* text,
                        int len) {
    uint16_t gen = 0;
    if (doc->free_head >= 0) gen = doc->nodes[doc->free_head].gen;
    int32_t idx = alloc_slot2(doc, gen);
    if (idx < 0) return -1;
    NxNode* n = &doc->nodes[idx];
    n->type = type;
    if (tag) n->tag = nx_intern(doc, tag, -1);
    if (text) {
        n->text = malloc((size_t)len + 1);
        memcpy(n->text, text, (size_t)len);
        n->text[len] = '\0';
        n->text_len = len;
    }
    return idx;
}

NxNodeRef nx_node_create_element(NxDocument* doc, const char* tag) {
    if (!doc || !tag) return 0;
    int32_t idx = new_node(doc, NX_NODE_ELEMENT, tag, NULL, 0);
    return idx >= 0 ? handle_of(doc, idx) : 0;
}
NxNodeRef nx_node_create_text(NxDocument* doc, const char* text, int len) {
    if (!doc || !text) return 0;
    if (len < 0) len = (int)strlen(text);
    int32_t idx = new_node(doc, NX_NODE_TEXT, NULL, text, len);
    return idx >= 0 ? handle_of(doc, idx) : 0;
}
NxNodeRef nx_node_create_comment(NxDocument* doc, const char* text, int len) {
    if (!doc || !text) return 0;
    if (len < 0) len = (int)strlen(text);
    int32_t idx = new_node(doc, NX_NODE_COMMENT, NULL, text, len);
    return idx >= 0 ? handle_of(doc, idx) : 0;
}

bool nx_node_append_child(NxDocument* doc, NxNodeRef parent, NxNodeRef child) {
    return nx_node_insert_before(doc, parent, child, 0);
}

bool nx_node_insert_before(NxDocument* doc, NxNodeRef parent, NxNodeRef child, NxNodeRef before) {
    NxNode* p = slot(doc, parent);
    NxNode* c = slot(doc, child);
    if (!p || !c || c == p) return false;
    if (c->type == NX_NODE_DOCUMENT) return false;
    if (nx_node_is_ancestor(doc, child, parent)) return false; /* cycle */
    /* depth check: child subtree depth + parent depth */
    if (nx_node_depth(doc, parent) + 1 > NX_MAX_DEPTH) return false;
    /* detach from old parent */
    if (c->parent >= 0) {
        NxNode* op = &doc->nodes[c->parent];
        if (op->first_child == (int32_t)((uint32_t)child & NX_HANDLE_IDX_MASK)) {
            op->first_child = c->next;
        }
        if (op->last_child == (int32_t)((uint32_t)child & NX_HANDLE_IDX_MASK)) {
            op->last_child = c->prev;
        }
        if (c->prev >= 0) doc->nodes[c->prev].next = c->next;
        if (c->next >= 0) doc->nodes[c->next].prev = c->prev;
        c->parent = c->prev = c->next = -1;
    }
    int32_t ci = (int32_t)((uint32_t)child & NX_HANDLE_IDX_MASK);
    int32_t bi = -1;
    if (before) {
        NxNode* b = slot(doc, before);
        if (!b || b->parent != (int32_t)((uint32_t)parent & NX_HANDLE_IDX_MASK)) return false;
        bi = (int32_t)((uint32_t)before & NX_HANDLE_IDX_MASK);
    }
    c->parent = (int32_t)((uint32_t)parent & NX_HANDLE_IDX_MASK);
    if (bi >= 0) {
        c->prev = doc->nodes[bi].prev;
        c->next = bi;
        if (doc->nodes[bi].prev >= 0) doc->nodes[doc->nodes[bi].prev].next = ci;
        doc->nodes[bi].prev = ci;
        if (p->first_child == bi) p->first_child = ci;
    } else {
        c->prev = p->last_child;
        c->next = -1;
        if (p->last_child >= 0) doc->nodes[p->last_child].next = ci;
        p->last_child = ci;
        if (p->first_child < 0) p->first_child = ci;
    }
    return true;
}

bool nx_node_remove_child(NxDocument* doc, NxNodeRef parent, NxNodeRef child) {
    NxNode* p = slot(doc, parent);
    NxNode* c = slot(doc, child);
    if (!p || !c || c->parent != (int32_t)((uint32_t)parent & NX_HANDLE_IDX_MASK)) return false;
    int32_t ci = (int32_t)((uint32_t)child & NX_HANDLE_IDX_MASK);
    if (c->prev >= 0) doc->nodes[c->prev].next = c->next;
    if (c->next >= 0) doc->nodes[c->next].prev = c->prev;
    if (p->first_child == ci) p->first_child = c->next;
    if (p->last_child == ci) p->last_child = c->prev;
    c->parent = c->prev = c->next = -1;
    return true;
}

bool nx_node_replace_text(NxDocument* doc, NxNodeRef text_node, const char* text, int len) {
    NxNode* n = slot(doc, text_node);
    if (!n || n->type != NX_NODE_TEXT || !text) return false;
    if (len < 0) len = (int)strlen(text);
    free(n->text);
    n->text = malloc((size_t)len + 1);
    memcpy(n->text, text, (size_t)len);
    n->text[len] = '\0';
    n->text_len = len;
    return true;
}

bool nx_node_is_ancestor(NxDocument* doc, NxNodeRef ancestor, NxNodeRef node) {
    int32_t a = (int32_t)((uint32_t)ancestor & NX_HANDLE_IDX_MASK);
    NxNodeRef cur = nx_node_parent(doc, node);
    int guard = 0;
    while (cur && guard++ < NX_MAX_DEPTH + 8) {
        if ((int32_t)((uint32_t)cur & NX_HANDLE_IDX_MASK) == a) return true;
        cur = nx_node_parent(doc, cur);
    }
    return false;
}

bool nx_node_destroy(NxDocument* doc, NxNodeRef node) {
    NxNode* n = slot(doc, node);
    if (!n || n->type == NX_NODE_DOCUMENT) return false;
    /* children first (re-slot each iteration: free_slot mutates the slot) */
    while (n->first_child >= 0) {
        if (!nx_node_destroy(doc, handle_of(doc, n->first_child))) break;
        n = slot(doc, node);
        if (!n) return true; /* parent got destroyed too (defensive) */
    }
    if (n->parent >= 0) {
        nx_node_remove_child(doc, handle_of(doc, n->parent), node);
    }
    free_slot(doc, (int32_t)((uint32_t)node & NX_HANDLE_IDX_MASK));
    return true;
}

/* ---- ids & queries ---- */
/* Detached subtrees keep their slots (and ids) until destroyed, but they are
   no longer part of the document: queries must not return them. */
static bool slot_attached(NxDocument* doc, int32_t idx) {
    int guard = 0;
    while (idx >= 0 && guard++ <= NX_MAX_DEPTH) {
        NxNode* n = &doc->nodes[idx];
        if (n->type == 0) return false;
        if (n->type == NX_NODE_DOCUMENT) return true;
        idx = n->parent;
    }
    return false;
}

NxNodeRef nx_doc_get_element_by_id(NxDocument* doc, const char* id) {
    if (!doc || !id) return 0;
    int32_t idx = idmap_get(doc, id);
    if (idx < 0) return 0;
    NxNode* n = slot(doc, handle_of(doc, idx));
    if (!n || n->type != NX_NODE_ELEMENT) return 0;
    if (!slot_attached(doc, idx)) return 0;
    return handle_of(doc, idx);
}

/* Selector parts store raw (ptr,len) slices of the caller's selector string,
   interned/matched against the document during traversal. */
typedef struct SelPartRaw {
    const char* tag;
    int tag_len;
    const char* id;
    int id_len;
    const char* cls[4];
    int cls_len[4];
    int cls_count;
} SelPartRaw;

static int parse_selector_raw(const char* sel, SelPartRaw* parts, int max) {
    int count = 0;
    const char* s = sel;
    while (*s && count < max) {
        while (*s == ' ' || *s == '\t' || *s == '\n') s++;
        if (!*s) break;
        SelPartRaw p = {0};
        const char* start = s;
        while (*s && *s != ' ' && *s != '\t' && *s != '\n') s++;
        const char* end = s;
        const char* t = start;
        if (t < end && *t != '#' && *t != '.') {
            const char* te = t;
            while (te < end && *te != '#' && *te != '.') te++;
            p.tag = t;
            p.tag_len = (int)(te - t);
            t = te;
        }
        while (t < end && (*t == '#' || *t == '.')) {
            char kind = *t++;
            const char* te = t;
            while (te < end && *te != '#' && *te != '.') te++;
            if (kind == '#') {
                p.id = t;
                p.id_len = (int)(te - t);
            } else if (p.cls_count < 4) {
                p.cls[p.cls_count] = t;
                p.cls_len[p.cls_count] = (int)(te - t);
                p.cls_count++;
            }
            t = te;
        }
        parts[count++] = p;
    }
    return count;
}

static bool part_matches_raw(NxDocument* doc, NxNode* n, const SelPartRaw* p) {
    if (n->type != NX_NODE_ELEMENT) return false;
    if (p->tag_len > 0) {
        if (!n->tag || (int)strlen(n->tag) != p->tag_len || memcmp(n->tag, p->tag, (size_t)p->tag_len)) {
            return false;
        }
    }
    const char* in_id = nx_intern(doc, "id", 2);
    const char* in_cls = nx_intern(doc, "class", 5);
    if (p->id_len > 0) {
        const char* got = NULL;
        for (int i = 0; i < n->attr_count; i++) {
            if (n->attrs[i].name == in_id) got = n->attrs[i].value;
        }
        if (!got || (int)strlen(got) != p->id_len || memcmp(got, p->id, (size_t)p->id_len)) {
            return false;
        }
    }
    if (p->cls_count > 0) {
        const char* cls_attr = NULL;
        for (int j = 0; j < n->attr_count; j++) {
            if (n->attrs[j].name == in_cls) cls_attr = n->attrs[j].value;
        }
        if (!cls_attr) return false;
        for (int i = 0; i < p->cls_count; i++) {
            const char* s = cls_attr;
            size_t want = (size_t)p->cls_len[i];
            bool found = false;
            while (*s) {
                while (*s == ' ') s++;
                const char* e = s;
                while (*e && *e != ' ') e++;
                if ((size_t)(e - s) == want && strncmp(s, p->cls[i], want) == 0) {
                    found = true;
                    break;
                }
                s = e;
            }
            if (!found) return false;
        }
    }
    return true;
}

static bool matches_chain(NxDocument* doc, NxNodeRef node, const SelPartRaw* parts, int count) {
    /* last part must match node; earlier parts match ancestors in order */
    NxNode* n = slot(doc, node);
    if (!n || !part_matches_raw(doc, n, &parts[count - 1])) return false;
    int pi = count - 2;
    NxNodeRef cur = nx_node_parent(doc, node);
    int guard = 0;
    while (pi >= 0 && cur && guard++ < NX_MAX_DEPTH + 8) {
        NxNode* a = slot(doc, cur);
        if (a && part_matches_raw(doc, a, &parts[pi])) pi--;
        cur = nx_node_parent(doc, cur);
    }
    return pi < 0;
}

static void query_walk(NxDocument* doc, NxNodeRef node, const SelPartRaw* parts, int count,
                       NxNodeRef* out, int max, int* found) {
    for (NxNodeRef c = nx_node_first_child(doc, node); c; c = nx_node_next_sibling(doc, c)) {
        if (nx_node_type(doc, c) != NX_NODE_ELEMENT) continue;
        if (*found < max && matches_chain(doc, c, parts, count)) out[(*found)++] = c;
        if (*found < max) query_walk(doc, c, parts, count, out, max, found);
        else break;
    }
}

NxNodeRef nx_doc_query_selector(NxDocument* doc, const char* selector) {
    if (!doc || !selector) return 0;
    SelPartRaw parts[8];
    int count = parse_selector_raw(selector, parts, 8);
    if (count == 0) return 0;
    NxNodeRef out[1];
    int found = 0;
    query_walk(doc, nx_doc_root(doc), parts, count, out, 1, &found);
    return found ? out[0] : 0;
}

int nx_doc_query_selector_all(NxDocument* doc, const char* selector, NxNodeRef* out, int max) {
    if (!doc || !selector || !out || max <= 0) return 0;
    SelPartRaw parts[8];
    int count = parse_selector_raw(selector, parts, 8);
    if (count == 0) return 0;
    int found = 0;
    query_walk(doc, nx_doc_root(doc), parts, count, out, max, &found);
    return found;
}

/* ---- entities ---- */
typedef struct Entity {
    const char* name;
    int len;
    int cp;
} Entity;

static const Entity k_entities[] = {
    {"amp", 3, 38},  {"lt", 2, 60},   {"gt", 2, 62},    {"quot", 4, 34},
    {"apos", 4, 39}, {"nbsp", 4, 160}, {"copy", 4, 169}, {"reg", 3, 174},
    {"hellip", 6, 8230}, {"mdash", 5, 8212}, {"ndash", 5, 8211},
    {"laquo", 5, 171}, {"raquo", 5, 187}, {"times", 5, 215}, {"divide", 7, 247},
    {"euro", 4, 8364}, {"pound", 5, 163}, {"yen", 3, 165}, {"sect", 4, 167},
    {"para", 4, 182}, {"deg", 3, 176}, {"plusmn", 6, 177}, {"sup1", 4, 185},
    {"sup2", 4, 178}, {"sup3", 4, 179}, {"micro", 5, 181}, {"middot", 6, 183},
    {"frac14", 6, 188}, {"frac12", 6, 189}, {"frac34", 6, 190}, {"iquest", 6, 191},
    {"iexcl", 5, 161}, {"cent", 4, 162}, {"curren", 6, 164}, {"brvbar", 6, 166},
    {"uml", 3, 168}, {"ordf", 4, 170}, {"not", 3, 172}, {"shy", 3, 173},
    {"macr", 4, 175}, {"acute", 5, 180}, {"cedil", 5, 184}, {"ordm", 4, 186},
    {"szlig", 5, 223}, {"agrave", 6, 224}, {"aacute", 6, 225}, {"acirc", 5, 226},
    {"atilde", 6, 227}, {"auml", 4, 228}, {"aring", 5, 229}, {"aelig", 5, 230},
    {"ccedil", 6, 231}, {"egrave", 6, 232}, {"eacute", 6, 233}, {"ecirc", 5, 234},
    {"euml", 4, 235}, {"igrave", 6, 236}, {"iacute", 6, 237}, {"icirc", 5, 238},
    {"iuml", 4, 239}, {"eth", 3, 240},    {"ntilde", 6, 241}, {"ograve", 6, 242},
    {"oacute", 6, 243}, {"ocirc", 5, 244}, {"otilde", 6, 245}, {"ouml", 4, 246},
    {"oslash", 6, 248}, {"ugrave", 6, 249}, {"uacute", 6, 250}, {"ucirc", 5, 251},
    {"uuml", 4, 252},  {"yacute", 6, 253}, {"thorn", 5, 254},  {"yuml", 4, 255},
    {"fnof", 4, 402},  {"Alpha", 5, 913},  {"Beta", 4, 914},   {"Gamma", 5, 915},
    {"Delta", 5, 916}, {"Theta", 5, 920},  {"Lambda", 6, 923},
    {"Pi", 2, 928}, {"Sigma", 5, 931}, {"Phi", 3, 934}, {"Omega", 5, 937},
    {"alpha", 5, 945}, {"beta", 4, 946}, {"gamma", 5, 947}, {"delta", 5, 948},
    {"theta", 5, 952}, {"lambda", 6, 955}, {"pi", 2, 960}, {"sigma", 5, 963},
    {"sigmaf", 6, 962}, {"phi", 3, 966}, {"omega", 5, 969}, {"larr", 4, 8592},
    {"uarr", 4, 8593}, {"rarr", 4, 8594}, {"darr", 4, 8595}, {"harr", 4, 8596},
    {"crarr", 5, 8629}, {"lArr", 4, 8656}, {"rArr", 4, 8658}, {"hArr", 4, 8660},
    {"forall", 6, 8704}, {"part", 4, 8706}, {"exist", 5, 8707}, {"empty", 5, 8709},
    {"nabla", 5, 8711}, {"isin", 4, 8712}, {"notin", 5, 8713}, {"ni", 2, 8715},
    {"prod", 4, 8719}, {"sum", 3, 8721}, {"minus", 5, 8722}, {"lowast", 6, 8727},
    {"radic", 5, 8730}, {"prop", 4, 8733}, {"infin", 5, 8734}, {"ang", 3, 8736},
    {"and", 3, 8743}, {"or", 2, 8744}, {"cap", 3, 8745}, {"cup", 3, 8746},
    {"int", 3, 8747}, {"there4", 6, 8756}, {"sim", 3, 8764}, {"cong", 4, 8773},
    {"asymp", 5, 8776}, {"ne", 2, 8800}, {"equiv", 5, 8801}, {"le", 2, 8804},
    {"ge", 2, 8805}, {"sub", 3, 8834}, {"sup", 3, 8835}, {"nsub", 4, 8836},
    {"sube", 4, 8838}, {"supe", 4, 8839}, {"oplus", 5, 8853}, {"otimes", 6, 8855},
    {"perp", 4, 8869}, {"sdot", 4, 8901}, {"lceil", 5, 8968}, {"rceil", 5, 8969},
    {"lfloor", 6, 8970}, {"rfloor", 6, 8971}, {"lang", 4, 9001}, {"rang", 4, 9002},
    {"loz", 3, 9674}, {"spades", 6, 9824}, {"clubs", 5, 9827}, {"hearts", 6, 9829},
    {"diams", 5, 9830}, {"OElig", 5, 338}, {"oelig", 5, 339}, {"Scaron", 6, 352},
    {"scaron", 6, 353}, {"Yuml", 4, 376}, {"circ", 4, 710}, {"tilde", 5, 732},
    {"zwnj", 4, 8204}, {"zwj", 3, 8205}, {"lrm", 3, 8206}, {"rlm", 3, 8207},
    {"ndash", 5, 8211}, {"mdash", 5, 8212}, {"lsquo", 5, 8216}, {"rsquo", 5, 8217},
    {"sbquo", 5, 8218}, {"ldquo", 5, 8220}, {"rdquo", 5, 8221}, {"bdquo", 5, 8222},
    {"dagger", 6, 8224}, {"Dagger", 6, 8225}, {"permil", 6, 8240}, {"prime", 5, 8242},
    {"Prime", 5, 8243}, {"lsaquo", 6, 8249}, {"rsaquo", 6, 8250}, {"oline", 5, 8254},
    {"frasl", 5, 8260}, {"weierp", 6, 8472}, {"image", 5, 8465}, {"real", 4, 8476},
    {"trade", 5, 8482}, {"alefsym", 7, 8501}, {"larr", 4, 8592}, {"uarr", 4, 8593},
    {"rarr", 4, 8594}, {"darr", 4, 8595}, {"harr", 4, 8596}, {"crarr", 5, 8629},
    {"lArr", 4, 8656}, {"uArr", 4, 8657}, {"rArr", 4, 8658}, {"dArr", 4, 8659},
    {"hArr", 4, 8660}, {"forall", 6, 8704}, {"part", 4, 8706}, {"exist", 5, 8707},
    {"empty", 5, 8709}, {"nabla", 5, 8711}, {"isin", 4, 8712}, {"notin", 5, 8713},
    {"ni", 2, 8715}, {"prod", 4, 8719}, {"sum", 3, 8721}, {"minus", 5, 8722},
    {"lowast", 6, 8727}, {"radic", 5, 8730}, {"prop", 4, 8733}, {"infin", 5, 8734},
    {"ang", 3, 8736}, {"and", 3, 8743}, {"or", 2, 8744}, {"cap", 3, 8745},
    {"cup", 3, 8746}, {"int", 3, 8747}, {"there4", 6, 8756}, {"sim", 3, 8764},
    {"cong", 4, 8773}, {"asymp", 5, 8776}, {"ne", 2, 8800}, {"equiv", 5, 8801},
    {"le", 2, 8804}, {"ge", 2, 8805}, {"sub", 3, 8834}, {"sup", 3, 8835},
    {"nsub", 4, 8836}, {"sube", 4, 8838}, {"supe", 4, 8839}, {"oplus", 5, 8853},
    {"otimes", 6, 8855}, {"perp", 4, 8869}, {"sdot", 4, 8901}, {"lceil", 5, 8968},
    {"rceil", 5, 8969}, {"lfloor", 6, 8970}, {"rfloor", 6, 8971}, {"lang", 4, 9001},
    {"rang", 4, 9002}, {"loz", 3, 9674}, {"spades", 6, 9824}, {"clubs", 5, 9827},
    {"hearts", 6, 9829}, {"diams", 5, 9830},
};

static int utf8_encode(int cp, char* out) {
    if (cp < 0x80) {
        out[0] = (char)cp;
        return 1;
    }
    if (cp < 0x800) {
        out[0] = (char)(0xC0 | (cp >> 6));
        out[1] = (char)(0x80 | (cp & 0x3F));
        return 2;
    }
    if (cp < 0x10000) {
        out[0] = (char)(0xE0 | (cp >> 12));
        out[1] = (char)(0x80 | ((cp >> 6) & 0x3F));
        out[2] = (char)(0x80 | (cp & 0x3F));
        return 3;
    }
    out[0] = (char)(0xF0 | (cp >> 18));
    out[1] = (char)(0x80 | ((cp >> 12) & 0x3F));
    out[2] = (char)(0x80 | ((cp >> 6) & 0x3F));
    out[3] = (char)(0x80 | (cp & 0x3F));
    return 4;
}

char* nx_html_unescape(const char* s, int len, int* out_len) {
    if (len < 0) len = (int)strlen(s);
    char* out = malloc((size_t)len * 4 + 1);
    int o = 0;
    for (int i = 0; i < len;) {
        if (s[i] == '&') {
            int semi = -1;
            for (int j = i + 1; j < len && j < i + 32; j++) {
                if (s[j] == ';') {
                    semi = j;
                    break;
                }
                if (!(s[j] >= '0' && s[j] <= '9') && !(s[j] >= 'a' && s[j] <= 'z') &&
                    !(s[j] >= 'A' && s[j] <= 'Z') && s[j] != '#') {
                    break;
                }
            }
            if (semi > i + 1) {
                const char* ent = s + i + 1;
                int elen = semi - i - 1;
                if (ent[0] == '#') {
                    int cp = 0;
                    bool digits = false;
                    bool hex = elen > 1 && (ent[1] == 'x' || ent[1] == 'X');
                    int k = hex ? 2 : 1;
                    for (; k < elen; k++) {
                        char c = ent[k];
                        int v = -1;
                        if (hex) {
                            if (c >= '0' && c <= '9') v = c - '0';
                            else if (c >= 'a' && c <= 'f') v = c - 'a' + 10;
                            else if (c >= 'A' && c <= 'F') v = c - 'A' + 10;
                        } else if (c >= '0' && c <= '9') {
                            v = c - '0';
                        }
                        if (v < 0) continue; /* stray char: ignore */
                        digits = true;
                        cp = cp * (hex ? 16 : 10) + v;
                        if (cp > 0x10FFFF) cp = 0x110000; /* clamp sentinel */
                    }
                    if (!digits) {
                        /* no digits: keep the literal source text */
                        int lit = semi - i + 1;
                        memcpy(out + o, s + i, (size_t)lit);
                        o += lit;
                    } else if (cp == 0 || cp > 0x10FFFF ||
                               (cp >= 0xD800 && cp <= 0xDFFF)) {
                        o += utf8_encode(0xFFFD, out + o); /* U+FFFD */
                    } else {
                        /* Windows-1252 remap for C1 control range */
                        static const int k_cp1252[32] = {
                            0x20AC, 0x81,   0x201A, 0x0192, 0x201E, 0x2026, 0x2020,
                            0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D,
                            0x017D, 0x8F,   0x90,   0x2018, 0x2019, 0x201C, 0x201D,
                            0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A,
                            0x0153, 0x9D,   0x017E, 0x0178};
                        if (cp >= 0x80 && cp <= 0x9F) cp = k_cp1252[cp - 0x80];
                        o += utf8_encode(cp, out + o);
                    }
                    i = semi + 1;
                    continue;
                }
                bool found = false;
                for (size_t e = 0; e < sizeof(k_entities) / sizeof(k_entities[0]); e++) {
                    if ((int)strlen(k_entities[e].name) == elen &&
                        memcmp(k_entities[e].name, ent, (size_t)elen) == 0) {
                        o += utf8_encode(k_entities[e].cp, out + o);
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    /* unknown entity: keep the literal source text */
                    int lit = semi - i + 1;
                    memcpy(out + o, s + i, (size_t)lit);
                    o += lit;
                }
                i = semi + 1;
                continue;
            }
        }
        out[o++] = s[i++];
    }
    out[o] = '\0';
    if (out_len) *out_len = o;
    return out;
}

char* nx_html_escape(const char* s, int len) {
    if (len < 0) len = (int)strlen(s);
    char* out = malloc((size_t)len * 6 + 1);
    int o = 0;
    for (int i = 0; i < len; i++) {
        switch (s[i]) {
            case '&': memcpy(out + o, "&amp;", 5); o += 5; break;
            case '<': memcpy(out + o, "&lt;", 4); o += 4; break;
            case '>': memcpy(out + o, "&gt;", 4); o += 4; break;
            case '"': memcpy(out + o, "&quot;", 6); o += 6; break;
            case '\'': memcpy(out + o, "&#39;", 5); o += 5; break;
            default: out[o++] = s[i];
        }
    }
    out[o] = '\0';
    return out;
}

/* ---- text content & serialization ---- */
typedef struct StrBuf {
    char* data;
    int len, cap;
} StrBuf;

static void sb_init(StrBuf* sb) {
    sb->cap = 256;
    sb->data = malloc((size_t)sb->cap);
    sb->len = 0;
}
static void sb_put(StrBuf* sb, const char* s, int n) {
    if (sb->len + n + 1 > sb->cap) {
        while (sb->len + n + 1 > sb->cap) sb->cap *= 2;
        sb->data = realloc(sb->data, (size_t)sb->cap);
    }
    memcpy(sb->data + sb->len, s, (size_t)n);
    sb->len += n;
}
static void sb_puts(StrBuf* sb, const char* s) { sb_put(sb, s, (int)strlen(s)); }

static void text_content_rec(NxDocument* doc, NxNodeRef node, StrBuf* sb) {
    NxNode* n = slot(doc, node);
    if (!n) return;
    if (n->type == NX_NODE_TEXT || n->type == NX_NODE_COMMENT) {
        if (n->text) sb_put(sb, n->text, n->text_len);
        return;
    }
    for (NxNodeRef c = nx_node_first_child(doc, node); c; c = nx_node_next_sibling(doc, c)) {
        text_content_rec(doc, c, sb);
    }
}

char* nx_node_text_content(NxDocument* doc, NxNodeRef node) {
    if (!doc || !slot(doc, node)) return NULL;
    StrBuf sb;
    sb_init(&sb);
    text_content_rec(doc, node, &sb);
    sb.data[sb.len] = '\0';
    return sb.data;
}

static bool is_void_tag(const char* tag) {
    static const char* k_void[] = {"area", "base", "br",   "col",  "embed", "hr",
                                   "img",  "input", "link", "meta", "param", "source",
                                   "track", "wbr"};
    for (size_t i = 0; i < sizeof(k_void) / sizeof(k_void[0]); i++) {
        if (strcmp(tag, k_void[i]) == 0) return true;
    }
    return false;
}

static void serialize_rec(NxDocument* doc, NxNodeRef node, StrBuf* sb) {
    NxNode* n = slot(doc, node);
    if (!n) return;
    if (n->type == NX_NODE_TEXT) {
        char* esc = nx_html_escape(n->text ? n->text : "", n->text_len);
        sb_puts(sb, esc);
        free(esc);
        return;
    }
    if (n->type == NX_NODE_COMMENT) {
        sb_puts(sb, "<!--");
        if (n->text) sb_put(sb, n->text, n->text_len);
        sb_puts(sb, "-->");
        return;
    }
    if (n->type == NX_NODE_DOCUMENT) {
        for (NxNodeRef c = nx_node_first_child(doc, node); c; c = nx_node_next_sibling(doc, c)) {
            serialize_rec(doc, c, sb);
        }
        return;
    }
    /* element */
    sb_puts(sb, "<");
    sb_puts(sb, n->tag ? n->tag : "div");
    for (int i = 0; i < n->attr_count; i++) {
        sb_puts(sb, " ");
        sb_puts(sb, n->attrs[i].name);
        sb_puts(sb, "=\"");
        char* esc = nx_html_escape(n->attrs[i].value, -1);
        sb_puts(sb, esc);
        free(esc);
        sb_puts(sb, "\"");
    }
    if (n->tag && is_void_tag(n->tag)) {
        sb_puts(sb, ">");
        return;
    }
    sb_puts(sb, ">");
    for (NxNodeRef c = nx_node_first_child(doc, node); c; c = nx_node_next_sibling(doc, c)) {
        serialize_rec(doc, c, sb);
    }
    sb_puts(sb, "</");
    sb_puts(sb, n->tag ? n->tag : "div");
    sb_puts(sb, ">");
}

char* nx_node_serialize(NxDocument* doc, NxNodeRef node) {
    if (!doc || !slot(doc, node)) return NULL;
    StrBuf sb;
    sb_init(&sb);
    serialize_rec(doc, node, &sb);
    sb.data[sb.len] = '\0';
    return sb.data;
}

/* ---- events ---- */
bool nx_event_make(NxEvent* ev, const char* type, bool bubbles, bool cancelable) {
    if (!ev || !type) return false;
    memset(ev, 0, sizeof(*ev));
    ev->type = type;
    ev->bubbles = bubbles;
    ev->cancelable = cancelable;
    return true;
}

bool nx_node_add_listener(NxDocument* doc, NxNodeRef node, const NxListenerSpec* spec) {
    NxNode* n = slot(doc, node);
    if (!n || !spec || !spec->type || !spec->cb) return false;
    if (n->listener_count == n->listener_cap) {
        n->listener_cap = n->listener_cap ? n->listener_cap * 2 : 4;
        n->listeners = realloc(n->listeners, (size_t)n->listener_cap * sizeof(NxListener));
    }
    NxListener* l = &n->listeners[n->listener_count++];
    l->type = nx_intern(doc, spec->type, -1);
    l->cb = spec->cb;
    l->user = spec->user;
    l->capture = spec->capture;
    l->once = spec->once;
    return true;
}

bool nx_node_remove_listener(NxDocument* doc, NxNodeRef node, const char* type, bool capture,
                             NxEventCallback cb, void* user) {
    NxNode* n = slot(doc, node);
    if (!n || !type) return false;
    const char* in = nx_intern(doc, type, -1);
    for (int i = 0; i < n->listener_count; i++) {
        NxListener* l = &n->listeners[i];
        if (l->type == in && l->capture == capture && l->cb == cb && l->user == user) {
            *l = n->listeners[n->listener_count - 1];
            n->listener_count--;
            return true;
        }
    }
    return false;
}

static void invoke_listeners(NxDocument* doc, NxNode* n, NxEvent* ev, bool capture_phase) {
    /* snapshot: listeners may add/remove during dispatch */
    int count = n->listener_count;
    if (count == 0) return;
    NxListener* snap = malloc(sizeof(NxListener) * (size_t)count);
    memcpy(snap, n->listeners, sizeof(NxListener) * (size_t)count);
    NxNodeRef self = handle_of(doc, (int32_t)((uint32_t)(n - doc->nodes)));
    ev->current_target = self;
    for (int i = 0; i < count && !ev->immediate_stopped; i++) {
        NxListener* l = &snap[i];
        if (l->capture != capture_phase) continue;
        if (l->type != ev->type) continue;
        if (l->once) nx_node_remove_listener(doc, self, (const char*)l->type, l->capture, l->cb,
                                             l->user);
        l->cb(doc, ev, l->user);
        if (ev->immediate_stopped) break;
    }
    free(snap);
}

bool nx_event_dispatch(NxDocument* doc, NxNodeRef target, NxEvent* ev) {
    if (!doc || !slot(doc, target) || !ev || !ev->type) return false;
    ev->type = nx_intern(doc, ev->type, -1); /* pointer identity vs listeners */
    ev->target = target;
    ev->propagation_stopped = false;
    ev->immediate_stopped = false;
    ev->default_prevented = false;

    /* build path root..parent(target) */
    int depth = 0;
    NxNodeRef path[NX_MAX_DEPTH + 2];
    for (NxNodeRef cur = target; cur && depth < NX_MAX_DEPTH + 2;
         cur = nx_node_parent(doc, cur)) {
        path[depth++] = cur;
    }
    /* capture: root..parent */
    ev->event_phase = 1;
    for (int i = depth - 1; i >= 1 && !ev->propagation_stopped; i--) {
        NxNode* n = slot(doc, path[i]);
        if (n) invoke_listeners(doc, n, ev, true);
    }
    /* target */
    if (!ev->propagation_stopped) {
        ev->event_phase = 2;
        NxNode* n = slot(doc, target);
        if (n) {
            invoke_listeners(doc, n, ev, true);
            if (!ev->immediate_stopped) invoke_listeners(doc, n, ev, false);
        }
    }
    /* bubble: parent..root */
    if (ev->bubbles && !ev->propagation_stopped) {
        ev->event_phase = 3;
        for (int i = 1; i < depth && !ev->propagation_stopped; i++) {
            NxNode* n = slot(doc, path[i]);
            if (n) invoke_listeners(doc, n, ev, false);
        }
    }
    return !ev->default_prevented;
}
