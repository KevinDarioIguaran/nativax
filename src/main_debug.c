/*
    nativax-debug: headless diagnostic CLI for the native pipeline.

    Parses HTML (+ optional CSS files) and writes reviewable artifacts:
      <out>/dom.txt      indented DOM tree with attributes and text
      <out>/css.txt      parsed rules: canonical selectors, media, decls
      <out>/layout.txt   box tree: geometry + text runs (style/layout/paint)
      <out>/summary.json machine-readable counts for diffing runs
      <out>/render.png   optional CPU raster of the painted page (--render)

    Exit codes: 0 ok, 1 usage, 2 parse error, 3 io error.
*/
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>

#include "nativax/debug_dump.h"
#include "nativax/display_list.h"
#include "nativax/dom.h"
#include "nativax/platform.h"
#include <signal.h>
#include <execinfo.h>
#include <unistd.h>
#include "nativax/html.h"
#include "nativax/layout.h"
#include "nativax/paint.h"
#include "nativax/raster.h"
#include "nativax/text.h"

#define MAX_CSS 16
#define MAX_INLINE 32

static void usage(void) {
    fprintf(stderr,
            "usage: nativax-debug --html file.html [--css file.css ...] "
            "--out dir [--width px --height px] [--render out.png]\n");
}


static void nx_debug_crash_handler(int sig) {
    void* fr[64];
    int n = backtrace(fr, 64);
    fprintf(stderr, "\nnativax-debug: fatal signal %d\n", sig);
    backtrace_symbols_fd(fr, n, STDERR_FILENO);
    signal(sig, SIG_DFL);
    raise(sig);
}
static void nx_debug_crash_init(void) {
    signal(SIGSEGV, nx_debug_crash_handler);
    signal(SIGABRT, nx_debug_crash_handler);
    signal(SIGFPE, nx_debug_crash_handler);
    signal(SIGILL, nx_debug_crash_handler);
}

int main(int argc, char** argv) {
    nx_debug_crash_init();
    const char* html_path = NULL;
    const char* css_paths[MAX_CSS];
    int css_count = 0;
    const char* out_dir = NULL;
    const char* render_path = NULL;
    int width = 1024, height = 768;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--html") == 0 && i + 1 < argc) html_path = argv[++i];
        else if (strcmp(argv[i], "--css") == 0 && i + 1 < argc) {
            if (css_count < MAX_CSS) css_paths[css_count++] = argv[++i];
        } else if (strcmp(argv[i], "--out") == 0 && i + 1 < argc) out_dir = argv[++i];
        else if (strcmp(argv[i], "--render") == 0 && i + 1 < argc) render_path = argv[++i];
        else if (strcmp(argv[i], "--width") == 0 && i + 1 < argc) width = atoi(argv[++i]);
        else if (strcmp(argv[i], "--height") == 0 && i + 1 < argc) height = atoi(argv[++i]);
        else {
            usage();
            return 1;
        }
    }
    if (!html_path || !out_dir || width <= 0 || height <= 0) {
        usage();
        return 1;
    }

    /* read html */
    FILE* f = fopen(html_path, "rb");
    if (!f) {
        fprintf(stderr, "nativax-debug: cannot open %s: %s\n", html_path,
                strerror(errno));
        return 3;
    }
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (sz < 0 || sz > 16 * 1024 * 1024) {
        fclose(f);
        fprintf(stderr, "nativax-debug: bad html size\n");
        return 3;
    }
    char* html = malloc((size_t)sz + 1);
    size_t rd = fread(html, 1, (size_t)sz, f);
    html[rd] = '\0';
    fclose(f);

    NxDocument* doc = nx_doc_new();
    char* err = NULL;
    if (!nx_html_parse(doc, html, (int)rd, &err)) {
        fprintf(stderr, "nativax-debug: html parse failed: %s\n",
                err ? err : "unknown");
        free(err);
        free(html);
        nx_doc_free(doc);
        return 2;
    }
    free(html);

    /* parse css files */
    CsSheet* sheets[MAX_CSS];
    for (int i = 0; i < css_count; i++) {
        FILE* cf = fopen(css_paths[i], "rb");
        if (!cf) {
            fprintf(stderr, "nativax-debug: cannot open %s: %s\n", css_paths[i],
                    strerror(errno));
            nx_doc_free(doc);
            return 3;
        }
        fseek(cf, 0, SEEK_END);
        long csz = ftell(cf);
        fseek(cf, 0, SEEK_SET);
        char* css = malloc((size_t)csz + 1);
        size_t crd = fread(css, 1, (size_t)csz, cf);
        css[crd] = '\0';
        fclose(cf);
        sheets[i] = cs_sheet_parse(css, (int)crd);
        free(css);
        if (!sheets[i]) {
            fprintf(stderr, "nativax-debug: css parse failed: %s\n", css_paths[i]);
            for (int k = 0; k < i; k++) cs_sheet_free(sheets[k]);
            nx_doc_free(doc);
            return 2;
        }
    }

    if (mkdir(out_dir, 0755) != 0 && errno != EEXIST) {
        fprintf(stderr, "nativax-debug: mkdir %s: %s\n", out_dir, strerror(errno));
        for (int i = 0; i < css_count; i++) cs_sheet_free(sheets[i]);
        nx_doc_free(doc);
        return 3;
    }

    /* ---- style → layout → paint ---------------------------------------- */
    /* inline <style> sheets (v1 order: file sheets first, then inline) */
    CsSheet* inline_sheets[MAX_INLINE];
    int inline_count = nx_style_collect_inline(doc, inline_sheets, MAX_INLINE);
    const CsSheet* all_sheets[MAX_CSS + MAX_INLINE];
    int all_count = 0;
    for (int i = 0; i < css_count; i++) all_sheets[all_count++] = sheets[i];
    for (int i = 0; i < inline_count; i++) all_sheets[all_count++] = inline_sheets[i];

    int32_t font = nx_font_load(NATIVAX_SOURCE_DIR "/assets/fonts/DejaVuSans.ttf");
    if (font < 0) font = nx_font_load("assets/fonts/DejaVuSans.ttf");
    NxLayout* lay = NULL;
    if (font < 0) {
        fprintf(stderr, "nativax-debug: warning: font unavailable; layout skipped\n");
    } else {
        lay = nx_layout_build(doc, all_sheets, all_count, (float)width, (float)height, font);
        if (!lay) {
            fprintf(stderr, "nativax-debug: layout failed\n");
            for (int i = 0; i < css_count; i++) cs_sheet_free(sheets[i]);
            for (int i = 0; i < inline_count; i++) cs_sheet_free(inline_sheets[i]);
            nx_doc_free(doc);
            return 2;
        }
    }

    char path[1024];
    int ok = 1;

    snprintf(path, sizeof(path), "%s/dom.txt", out_dir);
    FILE* df = fopen(path, "w");
    if (!df) {
        fprintf(stderr, "nativax-debug: write %s: %s\n", path, strerror(errno));
        ok = 0;
    } else {
        nxd_dump_dom(df, doc, nx_doc_root(doc), 0);
        fclose(df);
    }

    snprintf(path, sizeof(path), "%s/dom.json", out_dir);
    FILE* jdom = fopen(path, "w");
    if (!jdom) {
        fprintf(stderr, "nativax-debug: write %s: %s\n", path, strerror(errno));
        ok = 0;
    } else {
        nxd_dump_dom_json(jdom, doc, nx_doc_root(doc));
        fclose(jdom);
    }

    NxdDomStats st;
    memset(&st, 0, sizeof(st));
    nxd_dom_stats(doc, nx_doc_root(doc), 0, &st);

    int rules = 0, dropped_rules = 0, dropped_decls = 0;
    snprintf(path, sizeof(path), "%s/css.txt", out_dir);
    FILE* cf2 = fopen(path, "w");
    if (!cf2) {
        fprintf(stderr, "nativax-debug: write %s: %s\n", path, strerror(errno));
        ok = 0;
    } else {
        for (int i = 0; i < css_count; i++) {
            fprintf(cf2, "# file: %s\n", css_paths[i]);
            nxd_dump_css(cf2, sheets[i]);
            rules += sheets[i]->rule_count;
            dropped_rules += sheets[i]->dropped_rules;
            dropped_decls += sheets[i]->dropped_decls;
        }
        for (int i = 0; i < inline_count; i++) {
            fprintf(cf2, "# inline <style> [%d]\n", i);
            nxd_dump_css(cf2, inline_sheets[i]);
            rules += inline_sheets[i]->rule_count;
            dropped_rules += inline_sheets[i]->dropped_rules;
            dropped_decls += inline_sheets[i]->dropped_decls;
        }
        fclose(cf2);
    }

    /* ---- layout.txt ----------------------------------------------------- */
    int lay_boxes = 0, lay_runs = 0;
    snprintf(path, sizeof(path), "%s/layout.txt", out_dir);
    FILE* lf = fopen(path, "w");
    if (!lf) {
        fprintf(stderr, "nativax-debug: write %s: %s\n", path, strerror(errno));
        ok = 0;
    } else {
        nxd_dump_layout(lf, doc, lay);
        fclose(lf);
    }
    if (lay) nxd_layout_stats(lay, &lay_boxes, &lay_runs);

    /* ---- displaylist.txt ----------------------------------------------- */
    if (lay) {
        NxDisplayList dl;
        nx_dl_init(&dl);
        if (nx_paint(&dl, lay, font)) {
            snprintf(path, sizeof(path), "%s/displaylist.txt", out_dir);
            FILE* dlf = fopen(path, "w");
            if (dlf) {
                nxd_dump_display_list(dlf, &dl);
                fclose(dlf);
            }
        }
        nx_dl_free(&dl);
    }


    /* ---- optional PNG render ------------------------------------------- */
    if (render_path && lay) {
        NxDisplayList dl;
        nx_dl_init(&dl);
        if (!nx_paint(&dl, lay, font)) {
            fprintf(stderr, "nativax-debug: paint failed\n");
            ok = 0;
        } else {
            NxRaster raster;
            nx_raster_init(&raster, width, height);
            nx_raster_clear(&raster, (NxColor){1, 1, 1, 1});
            nx_raster_run(&raster, &dl);
            if (!nx_raster_write_png(&raster, render_path)) {
                fprintf(stderr, "nativax-debug: write %s failed\n", render_path);
                ok = 0;
            }
            nx_raster_free(&raster);
        }
        nx_dl_free(&dl);
    }

    snprintf(path, sizeof(path), "%s/summary.json", out_dir);
    FILE* jf = fopen(path, "w");
    if (!jf) {
        fprintf(stderr, "nativax-debug: write %s: %s\n", path, strerror(errno));
        ok = 0;
    } else {
        fprintf(jf,
                "{\"html\": \"%s\", \"dom\": {\"elements\": %d, \"text\": %d,"
                " \"comments\": %d, \"max_depth\": %d},"
                " \"css\": {\"files\": %d, \"inline_styles\": %d, \"rules\": %d,"
                " \"dropped_rules\": %d, \"dropped_decls\": %d},"
                " \"layout\": {\"viewport\": [%d, %d], \"boxes\": %d,"
                " \"runs\": %d}}\n",
                html_path, st.elements, st.text, st.comments, st.max_depth,
                css_count, inline_count, rules, dropped_rules, dropped_decls,
                width, height, lay_boxes, lay_runs);
        fclose(jf);
    }

    for (int i = 0; i < css_count; i++) cs_sheet_free(sheets[i]);
    for (int i = 0; i < inline_count; i++) cs_sheet_free(inline_sheets[i]);
    nx_layout_free(lay);
    nx_doc_free(doc);
    if (!ok) return 3;
    printf("nativax-debug: wrote %s/{dom.txt,dom.json,css.txt,layout.txt,displaylist.txt,summary.json}%s%s\n",
           out_dir, render_path ? ", " : "", render_path ? render_path : "");
    return 0;
}
