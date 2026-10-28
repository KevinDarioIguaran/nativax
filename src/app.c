/*
    Application host implementation: document loading, the style → layout →
    paint pipeline, script execution and the hot-reload entry points.
*/
#include "nativax/app.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "nativax/css.h"
#include "nativax/html.h"
#include "nativax/log.h"
#include "nativax/paint.h"
#include "nativax/text.h"

#define MAX_SHEETS 32
#define MAX_SCRIPTS 32

struct NxApp {
    char root[1024];
    char entry[256];
    int width, height;
    int32_t font;

    NxDocument* doc;
    NxJs* js;
    NxLoop* loop;
    NxDomBindings* bind;
    NxLayout* lay;

    CsSheet* sheets[MAX_SHEETS];
    int sheet_count;

    char* scripts[MAX_SCRIPTS];
    char* script_names[MAX_SCRIPTS];
    int script_count;

    NxDisplayList dl;
    float dpi;
    NxAppTimings timings;
    bool style_dirty;
    bool paint_dirty;
    bool loaded;
};

/* ---- timing -------------------------------------------------------------- */

static double now_ms_time(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec / 1e6;
}

/* ---- file helpers -------------------------------------------------------- */

static char* read_file(const char* path, int* out_len) {
    FILE* f = fopen(path, "rb");
    if (!f) return NULL;
    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return NULL;
    }
    long size = ftell(f);
    if (size < 0 || size > 8 * 1024 * 1024) {
        fclose(f);
        return NULL;
    }
    rewind(f);
    char* buf = (char*)malloc((size_t)size + 1);
    if (!buf) {
        fclose(f);
        return NULL;
    }
    size_t rd = fread(buf, 1, (size_t)size, f);
    fclose(f);
    buf[rd] = '\0';
    if (out_len) *out_len = (int)rd;
    return buf;
}

static void join_path(char* out, size_t cap, const char* root, const char* rel) {
    while (*rel == '/') rel++;
    if (root[0] && root[strlen(root) - 1] == '/')
        snprintf(out, cap, "%s%s", root, rel);
    else
        snprintf(out, cap, "%s/%s", root, rel);
}

static bool name_is(const char* a, const char* b) {
    if (!a || !b) return false;
    for (; *a && *b; a++, b++) {
        char ca = *a, cb = *b;
        if (ca >= 'A' && ca <= 'Z') ca = (char)(ca - 'A' + 'a');
        if (cb >= 'A' && cb <= 'Z') cb = (char)(cb - 'A' + 'a');
        if (ca != cb) return false;
    }
    return *a == '\0' && *b == '\0';
}

/* ---- runtime lifecycle --------------------------------------------------- */

static void on_mutation(void* user) {
    NxApp* app = (NxApp*)user;
    app->style_dirty = true;
    app->paint_dirty = true;
}

static void free_sheets(NxApp* app) {
    for (int i = 0; i < app->sheet_count; i++) cs_sheet_free(app->sheets[i]);
    app->sheet_count = 0;
}

static void free_scripts(NxApp* app) {
    for (int i = 0; i < app->script_count; i++) {
        free(app->scripts[i]);
        free(app->script_names[i]);
    }
    app->script_count = 0;
}

/* Collect <link rel=stylesheet href> (read from the project directory) and
   inline <style> sheets in document order. */
static void collect_sheets(NxApp* app) {
    free_sheets(app);
    NxDocument* doc = app->doc;
    NxNodeRef stack[512];
    int sp = 0;
    NxNodeRef root = nx_doc_root(doc);
    for (NxNodeRef c = nx_node_first_child(doc, root); c && sp < 512;
         c = nx_node_next_sibling(doc, c))
        stack[sp++] = c;
    while (sp > 0 && app->sheet_count < MAX_SHEETS) {
        NxNodeRef node = stack[--sp];
        if (nx_node_type(doc, node) != NX_NODE_ELEMENT) continue;
        const char* tag = nx_node_name(doc, node);
        if (name_is(tag, "link")) {
            const char* rel = nx_node_get_attr(doc, node, "rel");
            const char* href = nx_node_get_attr(doc, node, "href");
            bool is_css = false;
            if (rel) {
                char buf[128];
                snprintf(buf, sizeof(buf), "%s", rel);
                for (char* p = buf; *p; p++)
                    if (*p >= 'A' && *p <= 'Z') *p = (char)(*p - 'A' + 'a');
                is_css = strstr(buf, "stylesheet") != NULL;
            }
            if (is_css && href) {
                char path[1400];
                join_path(path, sizeof(path), app->root, href);
                int len = 0;
                char* css = read_file(path, &len);
                if (css) {
                    CsSheet* sh = cs_sheet_parse(css, len);
                    if (sh) app->sheets[app->sheet_count++] = sh;
                    free(css);
                } else {
                    NX_WARN("stylesheet not found: %s", path);
                }
            }
        } else if (name_is(tag, "style")) {
            char* text = nx_node_text_content(doc, node);
            if (text && *text) {
                CsSheet* sh = cs_sheet_parse(text, (int)strlen(text));
                if (sh) app->sheets[app->sheet_count++] = sh;
            }
            free(text);
        }
        NxNodeRef kids[128];
        int kc = 0;
        for (NxNodeRef c = nx_node_first_child(doc, node); c && kc < 128;
             c = nx_node_next_sibling(doc, c))
            kids[kc++] = c;
        for (int i = kc - 1; i >= 0; i--)
            if (sp < 512) stack[sp++] = kids[i];
    }
}

static void collect_scripts(NxApp* app) {
    free_scripts(app);
    NxDocument* doc = app->doc;
    NxNodeRef stack[512];
    int sp = 0;
    NxNodeRef root = nx_doc_root(doc);
    for (NxNodeRef c = nx_node_first_child(doc, root); c && sp < 512;
         c = nx_node_next_sibling(doc, c))
        stack[sp++] = c;
    while (sp > 0 && app->script_count < MAX_SCRIPTS) {
        NxNodeRef node = stack[--sp];
        if (nx_node_type(doc, node) != NX_NODE_ELEMENT) continue;
        if (name_is(nx_node_name(doc, node), "script")) {
            const char* type = nx_node_get_attr(doc, node, "type");
            bool is_js = true;
            if (type && *type) {
                char buf[128];
                snprintf(buf, sizeof(buf), "%s", type);
                for (char* p = buf; *p; p++)
                    if (*p >= 'A' && *p <= 'Z') *p = (char)(*p - 'A' + 'a');
                is_js = strstr(buf, "javascript") != NULL || strstr(buf, "ecmascript") != NULL;
            }
            const char* src = nx_node_get_attr(doc, node, "src");
            char* code = NULL;
            char name[1400];
            if (src && *src) {
                char path[1400];
                join_path(path, sizeof(path), app->root, src);
                int len = 0;
                code = read_file(path, &len);
                snprintf(name, sizeof(name), "%s", src);
                if (!code) NX_WARN("script not found: %s", path);
            } else {
                code = nx_node_text_content(doc, node);
                snprintf(name, sizeof(name), "<inline-script-%d>", app->script_count);
            }
            if (is_js && code) {
                app->scripts[app->script_count] = code;
                app->script_names[app->script_count] = strdup(name);
                app->script_count++;
            } else {
                free(code);
            }
        }
        NxNodeRef kids[128];
        int kc = 0;
        for (NxNodeRef c = nx_node_first_child(doc, node); c && kc < 128;
             c = nx_node_next_sibling(doc, c))
            kids[kc++] = c;
        for (int i = kc - 1; i >= 0; i--)
            if (sp < 512) stack[sp++] = kids[i];
    }
}

static bool reset_runtime(NxApp* app) {
    if (app->bind) {
        nx_dom_bind_free(app->bind);
        app->bind = NULL;
    }
    if (app->loop) {
        nx_loop_free(app->loop);
        app->loop = NULL;
    }
    if (app->js) {
        nx_js_free(app->js);
        app->js = NULL;
    }
    app->js = nx_js_new();
    if (!app->js) return false;
    nx_js_set_time_budget_ms(app->js, 500);
    app->loop = nx_loop_new(app->js);
    if (app->loop) nx_loop_bind(app->loop);
    app->bind = nx_dom_bind_new(app->js, app->doc);
    if (!app->bind) {
        NX_ERROR("js dom bindings failed to install");
        return false;
    }
    nx_dom_bind_set_mutation_cb(app->bind, on_mutation, app);
    return true;
}

static void run_scripts(NxApp* app) {
    if (!app->js) return;
    for (int i = 0; i < app->script_count; i++) {
        char* err = NULL;
        if (!nx_js_eval(app->js, app->scripts[i], app->script_names[i], &err)) {
            NX_ERROR("script error in %s: %s", app->script_names[i], err ? err : "unknown");
        } else {
            NX_DEBUG("script ok: %s", app->script_names[i]);
        }
        free(err);
    }
}

/* ---- pipeline ------------------------------------------------------------ */

static bool build_layout(NxApp* app) {
    if (app->lay) {
        nx_layout_free(app->lay);
        app->lay = NULL;
    }
    double t0 = now_ms_time();
    app->lay = nx_layout_build(app->doc, (const CsSheet* const*)app->sheets, app->sheet_count,
                               (float)app->width, (float)app->height, app->font);
    double t1 = now_ms_time();
    /* nx_layout_build does cascade + layout in one call: report it as the
       layout phase and leave restyle_ms at 0 when it was not split. */
    app->timings.relayout_ms = t1 - t0;
    app->style_dirty = false;
    app->paint_dirty = true;
    return app->lay != NULL;
}

/* Re-resolve styles into the existing array (boxes hold pointers into it) and
   re-run layout in place. */
static bool restyle(NxApp* app) {
    if (!app->lay) return build_layout(app);
    /* cascade and layout timed separately so the report can attribute cost */
    if (nx_node_slot_bound(app->doc) > app->lay->styles_cap)
        return build_layout(app); /* document outgrew the style array */
    double t0 = now_ms_time();
    bool resolved = nx_style_resolve_into(app->doc, (const CsSheet* const*)app->sheets,
                                          app->sheet_count, (float)app->width, (float)app->height, 16.0f,
                                          app->lay->styles, app->lay->styles_cap);
    double t1 = now_ms_time();
    if (!resolved) return build_layout(app);
    nx_layout_run(app->lay, app->doc, (float)app->width, (float)app->height, app->font);
    double t2 = now_ms_time();
    app->timings.restyle_ms = t1 - t0;
    app->timings.relayout_ms = t2 - t1;
    app->style_dirty = false;
    app->paint_dirty = true;
    return true;
}

/* Painting borrows text pointers and style pointers from the layout, while any
   DOM mutation (textContent, remove, innerHTML, document reload) can free the
   underlying nodes. A valid layout is therefore a *precondition* for
   painting, not a side effect of the call order: repaint() always re-runs
   style+layout first when the document is dirty.
   (Found by ASan as heap-use-after-free in nx_utf8_decode during
   nx_app_reload_document — see debug/reports/phase1-report.md.) */
static void repaint(NxApp* app) {
    if (app->style_dirty) restyle(app);
    if (!app->lay) {
        app->paint_dirty = false;
        return;
    }
    nx_dl_reset(&app->dl);
    if (app->lay) {
        bool scaled = app->dpi > 0.0f && app->dpi != 1.0f;
        double t0 = now_ms_time();
        if (scaled) nx_dl_push_transform(&app->dl, &(NxMat2x3){app->dpi, 0, 0, app->dpi, 0, 0});
        nx_paint(&app->dl, app->lay, app->font);
        if (scaled) nx_dl_pop_transform(&app->dl);
        app->timings.paint_ms = now_ms_time() - t0;
    }
    app->paint_dirty = false;
}

/* ---- public API ---------------------------------------------------------- */

NxApp* nx_app_new(const NxAppConfig* cfg) {
    if (!cfg) return NULL;
    NxApp* app = (NxApp*)calloc(1, sizeof(*app));
    if (!app) return NULL;
    snprintf(app->root, sizeof(app->root), "%s", cfg->root ? cfg->root : ".");
    snprintf(app->entry, sizeof(app->entry), "%s",
             cfg->entry && *cfg->entry ? cfg->entry : "index.html");
    app->width = cfg->width > 0 ? cfg->width : 1024;
    app->height = cfg->height > 0 ? cfg->height : 768;
    app->dpi = 1.0f;
    nx_dl_init(&app->dl);

    const char* font_path = cfg->font_path;
    if (font_path && *font_path) app->font = nx_font_load(font_path);
    if (app->font < 0) app->font = nx_font_load("assets/fonts/DejaVuSans.ttf");
    if (app->font < 0) NX_WARN("no font could be loaded: text layout disabled");
    app->doc = nx_doc_new();
    if (!app->doc) {
        nx_app_free(app);
        return NULL;
    }
    return app;
}

void nx_app_free(NxApp* app) {
    if (!app) return;
    if (app->bind) nx_dom_bind_free(app->bind);
    if (app->loop) nx_loop_free(app->loop);
    if (app->js) nx_js_free(app->js);
    if (app->lay) nx_layout_free(app->lay);
    free_sheets(app);
    free_scripts(app);
    if (app->doc) nx_doc_free(app->doc);
    nx_dl_free(&app->dl);
    free(app);
}

bool nx_app_load(NxApp* app, char** error) {
    if (!app) return false;
    double t_start = now_ms_time();
    char path[1400];
    join_path(path, sizeof(path), app->root, app->entry);
    int len = 0;
    char* html = read_file(path, &len);
    double t_read = now_ms_time();
    if (!html) {
        if (error) {
            char msg[1600];
            snprintf(msg, sizeof(msg), "cannot read entry document: %s", path);
            *error = strdup(msg);
        }
        return false;
    }
    if (!nx_html_parse(app->doc, html, len, error)) {
        free(html);
        return false;
    }
    free(html);
    double t_parse = now_ms_time();

    collect_sheets(app);
    collect_scripts(app);
    double t_collect = now_ms_time();
    if (app->font < 0) app->font = nx_font_load("assets/fonts/DejaVuSans.ttf");
    if (!build_layout(app)) {
        if (error) *error = strdup("layout failed");
        return false;
    }
    double t_layout = now_ms_time();
    if (!reset_runtime(app)) {
        if (error) *error = strdup("javascript runtime failed to start");
        return false;
    }
    run_scripts(app);
    double t_script = now_ms_time();
    app->timings.load_read_ms = t_read - t_start;
    app->timings.load_parse_ms = t_parse - t_read;
    app->timings.load_collect_ms = t_collect - t_parse;
    app->timings.load_layout_ms = t_layout - t_collect;
    app->timings.load_script_ms = t_script - t_layout;
    app->timings.load_total_ms = t_script - t_start;
    /* scripts may have mutated the DOM: the layout built above is already
       stale, so keep the dirty flag instead of discarding it */
    app->paint_dirty = true;
    app->loaded = true;
    repaint(app);
    return true;
}

void nx_app_set_viewport(NxApp* app, int width, int height) {
    if (!app || width <= 0 || height <= 0) return;
    if (width == app->width && height == app->height) return;
    app->width = width;
    app->height = height;
    app->style_dirty = true;
    app->paint_dirty = true;
}

void nx_app_set_dpi(NxApp* app, float dpi) {
    if (!app || dpi <= 0.0f) return;
    if (app->dpi == dpi) return;
    app->dpi = dpi;
    app->paint_dirty = true;
}

void nx_app_mark_dirty(NxApp* app) {
    if (!app) return;
    app->style_dirty = true;
    app->paint_dirty = true;
}

bool nx_app_update(NxApp* app, double now_ms) {
    if (!app || !app->loaded) return false;
    double t0 = now_ms_time();
    if (app->loop) {
        nx_loop_run(app->loop, now_ms);
        nx_loop_frame(app->loop, now_ms);
    }
    bool changed = false;
    if (app->style_dirty) {
        restyle(app);
        changed = true;
    }
    if (app->paint_dirty) {
        repaint(app);
        changed = true;
    }
    app->timings.frame_ms = now_ms_time() - t0;
    return changed;
}

const NxAppTimings* nx_app_timings(NxApp* app) { return app ? &app->timings : NULL; }

const NxDisplayList* nx_app_list(NxApp* app) { return app ? &app->dl : NULL; }
NxDocument* nx_app_doc(NxApp* app) { return app ? app->doc : NULL; }
NxLayout* nx_app_layout(NxApp* app) { return app ? app->lay : NULL; }
NxJs* nx_app_js(NxApp* app) { return app ? app->js : NULL; }
bool nx_app_needs_paint(NxApp* app) { return app && (app->paint_dirty || app->style_dirty); }

/* ---- hit testing + input ------------------------------------------------- */

static NxNodeRef hit_box(const NxBox* box, float x, float y) {
    if (!box) return 0;
    float lx = x, ly = y;
    if (box->style && box->style->transform_set) {
        NxMat2x3 inv;
        NxMat2x3 m = nx_box_transform(box);
        if (nx_mat_invert(&m, &inv)) {
            lx = inv.a * x + inv.c * y + inv.e;
            ly = inv.b * x + inv.d * y + inv.f;
        }
    }
    if (box->style && box->style->overflow_hidden) {
        if (lx < box->x || lx >= box->x + box->w || ly < box->y || ly >= box->y + box->h)
            return 0;
    }

    NxNodeRef hit = 0;
    for (int i = box->child_count - 1; i >= 0; i--) {
        hit = hit_box(box->children[i], lx, ly);
        if (hit) break;
    }
    if (hit) return hit;
    if (box->node && lx >= box->x && lx < box->x + box->w && ly >= box->y &&
        ly < box->y + box->h)
        return box->node;
    return 0;
}

bool nx_app_pointer(NxApp* app, float x, float y, bool down) {
    if (!app || !app->lay || !app->bind) return false;
    NxNodeRef target = hit_box(app->lay->root, x, y);
    if (!target) return false;
    if (down) {
        NxEventPayload pl = {0};
        pl.x = x; pl.y = y; pl.button = 0;
        nx_dom_dispatch_js_event(app->bind, target, "click", &pl);
    }
    return true;
}

bool nx_app_pointer_move(NxApp* app, float x, float y) {
    if (!app || !app->lay || !app->bind) return false;
    NxNodeRef target = hit_box(app->lay->root, x, y);
    if (!target) return false;
    NxEventPayload pl = {0};
    pl.x = x; pl.y = y; pl.button = 0;
    nx_dom_dispatch_js_event(app->bind, target, "pointermove", &pl);
    return true;
}

bool nx_app_key(NxApp* app, int key, bool down) {
    (void)key; /* v1 event object has no keyboard payload (documented) */
    if (!app || !app->bind) return false;
    NxNodeRef target = nx_doc_query_selector(app->doc, "body");
    if (!target) target = nx_doc_root(app->doc);
    if (!target) return false;
    NxEventPayload pl = {0};
    pl.key = key;
    return nx_dom_dispatch_js_event(app->bind, target, down ? "keydown" : "keyup", &pl);
}

/* ---- hot reload ---------------------------------------------------------- */

bool nx_app_reload_css(NxApp* app) {
    if (!app || !app->loaded) return false;
    collect_sheets(app);
    bool ok = app->lay ? restyle(app) : build_layout(app);
    repaint(app);
    return ok;
}

bool nx_app_reload_js(NxApp* app) {
    if (!app || !app->loaded) return false;
    collect_scripts(app); /* script files were re-read from disk */
    if (!reset_runtime(app)) return false;
    /* The old JS context (and every wrapper it held) is gone: detached
       subtrees created by remove() can no longer be referenced, so reclaim
       their slots instead of leaking them for the lifetime of the document. */
    nx_doc_reap_detached(app->doc);
    run_scripts(app);
    app->style_dirty = true; /* scripts may have mutated the DOM on re-run */
    app->paint_dirty = true;
    return true;
}

bool nx_app_reload_document(NxApp* app) {
    if (!app) return false;
    char path[1400];
    join_path(path, sizeof(path), app->root, app->entry);
    int len = 0;
    char* html = read_file(path, &len);
    if (!html) return false;
    char* err = NULL;
    bool parsed = nx_html_parse(app->doc, html, len, &err);
    free(html);
    if (!parsed) {
        NX_ERROR("document reload failed: %s", err ? err : "parse error");
        free(err);
        /* nx_html_parse clears the previous tree first: the old layout now
           points at freed nodes, so rebuild it from the partial tree before
           anything can paint or hit-test again. */
        free_scripts(app);
        collect_sheets(app);
        collect_scripts(app);
        build_layout(app);
        app->loaded = true;
        return false;
    }
    free(err);
    free_scripts(app);
    collect_sheets(app);
    collect_scripts(app);
    if (!build_layout(app)) return false;
    if (!reset_runtime(app)) return false;
    /* same contract as reload_js: fresh context = nothing can reference the
       detached subtrees the previous session removed, so reclaim them */
    nx_doc_reap_detached(app->doc);
    run_scripts(app);
    app->loaded = true;
    repaint(app);
    return true;
}

/* ---- diagnostics --------------------------------------------------------- */

static int count_nodes(NxDocument* doc, NxNodeRef node) {
    int n = 1;
    for (NxNodeRef c = nx_node_first_child(doc, node); c; c = nx_node_next_sibling(doc, c))
        n += count_nodes(doc, c);
    return n;
}

char* nx_app_stats_json(NxApp* app) {
    if (!app) return NULL;
    char buf[1024];
    int nodes = app->doc ? count_nodes(app->doc, nx_doc_root(app->doc)) : 0;
    int boxes = 0;
    if (app->lay && app->lay->root) {
        /* root child count is enough as a stable pipeline signal here */
        boxes = app->lay->root->child_count;
    }
    snprintf(buf, sizeof(buf),
             "{\"nodes\":%d,\"top_level_boxes\":%d,\"sheets\":%d,\"scripts\":%d,"
             "\"listeners\":%d,\"vertices\":%u,\"groups\":%u,"
             "\"viewport\":[%d,%d],\"loaded\":%s}",
             nodes, boxes, app->sheet_count, app->script_count,
             app->bind ? nx_dom_listener_count(app->bind) : 0,
             app->dl.vert_count, app->dl.group_count, app->width, app->height,
             app->loaded ? "true" : "false");
    return strdup(buf);
}
