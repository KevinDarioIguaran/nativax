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
NxJs* nx_app_js(NxApp* app);

/* Mark the document as needing restyle + relayout + repaint. */
void nx_app_mark_dirty(NxApp* app);

/* Pointer input in CSS px: hit-tests the layout and dispatches a click. */
bool nx_app_pointer(NxApp* app, float x, float y, bool down);

/* Hot reload (see contract above). Return false when the new state could not
   be loaded; the previous state is kept where possible. */
bool nx_app_reload_css(NxApp* app);
bool nx_app_reload_js(NxApp* app);
bool nx_app_reload_document(NxApp* app);

/* Diagnostics: compact JSON with the current pipeline sizes. */
char* nx_app_stats_json(NxApp* app);

/* Redraw needed (dev server can skip work when false). */
bool nx_app_needs_paint(NxApp* app);

#endif /* NATIVAX_APP_H */
