#ifndef NATIVAX_APP_H
#define NATIVAX_APP_H

/*
    Application host: the pipeline owner.

    Loads an HTML entry document from a project directory, resolves its
    stylesheets (external <link> files + inline <style>), builds layout, paints
    the display list, and runs the page's scripts against the native DOM.

    Hot reload entry points keep the contract explicit:

      css  -> re-read stylesheets, restyle in place, relayout, repaint
              (DOM and JS state survive)
      js   -> fresh JS context, scripts re-executed against the live DOM
              (DOM survives, JS heap state is dropped — documented)
      doc  -> full document reload (everything rebuilt, state reset)
*/

#include <stdbool.h>
#include <stdint.h>

#include "nativax/display_list.h"
#include "nativax/dom.h"
#include "nativax/js_dom.h"
#include "nativax/js_engine.h"
#include "nativax/js_loop.h"
#include "nativax/layout.h"

typedef struct NxApp NxApp;

typedef struct NxAppConfig {
    const char* root;      /* project directory holding index.html and assets */
    const char* entry;     /* entry file relative to root (default index.html) */
    const char* font_path; /* TTF for text; NULL = assets/fonts/DejaVuSans.ttf */
    int width, height;     /* viewport in CSS px */
} NxAppConfig;

NxApp* nx_app_new(const NxAppConfig* cfg);
void nx_app_free(NxApp* app);

/* Parse the entry document and bring the pipeline up. On failure returns
   false and *error (caller frees) holds a message. */
bool nx_app_load(NxApp* app, char** error);

/* Resize the viewport (CSS px) and invalidate style/layout. */
void nx_app_set_viewport(NxApp* app, int width, int height);

/* Device pixel ratio used when painting (display lists stay in CSS px). */
void nx_app_set_dpi(NxApp* app, float dpi);

/* Run due timers + one animation frame, then repaint if anything is dirty.
   Returns true when the display list changed. */
bool nx_app_update(NxApp* app, double now_ms);

/* Latest display list (valid until the next nx_app_update). */
const NxDisplayList* nx_app_list(NxApp* app);

NxDocument* nx_app_doc(NxApp* app);
NxLayout* nx_app_layout(NxApp* app);

/* Scroll the first overflow:scroll/auto container by (dx,dy) CSS px and relayout. */
bool nx_app_scroll(NxApp* app, float dx, float dy);
NxJs* nx_app_js(NxApp* app);

/* Mark the document as needing restyle + relayout + repaint. */
void nx_app_mark_dirty(NxApp* app);

/* Pointer input in CSS px: hit-tests the layout and dispatches a click. */
bool nx_app_pointer(NxApp* app, float x, float y, bool down);

/* Pointer movement in CSS px: dispatches `pointermove` on the hit node.
   No layout invalidation (hover styling is not implemented yet). */
bool nx_app_pointer_move(NxApp* app, float x, float y);

/* Keyboard input (NxKey value from platform.h). `keydown`/`keyup` are
   dispatched on <body> and bubble; the v1 event object carries no key data
   yet, so listeners can react but not inspect the key. */
bool nx_app_key(NxApp* app, int key, bool down);

/* Hot reload (see contract above). Return false when the new state could not
   be loaded; the previous state is kept where possible. */
bool nx_app_reload_css(NxApp* app);
bool nx_app_reload_js(NxApp* app);
bool nx_app_reload_document(NxApp* app);

/* Diagnostics: compact JSON with the current pipeline sizes. */
char* nx_app_stats_json(NxApp* app);

/* Phase timings, measured with CLOCK_MONOTONIC on the real pipeline.
   Load fields come from the last nx_app_load()/reload_document; the rest
   reflect the most recent nx_app_update()/reload. All values in ms. */
typedef struct NxAppTimings {
    double load_read_ms;     /* entry file read */
    double load_parse_ms;    /* HTML parse */
    double load_collect_ms;  /* stylesheet + script collection */
    double load_layout_ms;   /* first style resolution + layout */
    double load_script_ms;   /* JS context creation + script execution */
    double load_total_ms;    /* read+parse+collect+layout+script */
    double restyle_ms;       /* last cascade resolution */
    double relayout_ms;      /* last layout run */
    double paint_ms;         /* last display-list build */
    double frame_ms;         /* last nx_app_update() including timers */
} NxAppTimings;

const NxAppTimings* nx_app_timings(NxApp* app);

/* Redraw needed (dev server can skip work when false). */
bool nx_app_needs_paint(NxApp* app);

#endif /* NATIVAX_APP_H */
