/*
    nativax-debug: headless diagnostic CLI for the native pipeline.

    Parses HTML (+ optional CSS files) and writes reviewable artifacts:
      <out>/dom.txt      indented DOM tree with attributes and text
      <out>/css.txt      parsed rules: canonical selectors, media, decls
      <out>/summary.json machine-readable counts for diffing runs

    Exit codes: 0 ok, 1 usage, 2 parse error, 3 io error.
    Style/layout dumps join when style.c/layout.c land (Phase 6).
*/
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>

#include "nativax/debug_dump.h"
#include "nativax/dom.h"
#include "nativax/html.h"

#define MAX_CSS 16

static void usage(void) {
    fprintf(stderr,
            "usage: nativax-debug --html file.html [--css file.css ...] "
            "--out dir\n");
}

int main(int argc, char** argv) {
    const char* html_path = NULL;
    const char* css_paths[MAX_CSS];
    int css_count = 0;
    const char* out_dir = NULL;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--html") == 0 && i + 1 < argc) html_path = argv[++i];
        else if (strcmp(argv[i], "--css") == 0 && i + 1 < argc) {
            if (css_count < MAX_CSS) css_paths[css_count++] = argv[++i];
        } else if (strcmp(argv[i], "--out") == 0 && i + 1 < argc) out_dir = argv[++i];
        else {
            usage();
            return 1;
        }
    }
    if (!html_path || !out_dir) {
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
    }

    if (mkdir(out_dir, 0755) != 0 && errno != EEXIST) {
        fprintf(stderr, "nativax-debug: mkdir %s: %s\n", out_dir, strerror(errno));
        for (int i = 0; i < css_count; i++) cs_sheet_free(sheets[i]);
        nx_doc_free(doc);
        return 3;
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
        fclose(cf2);
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
                " \"css\": {\"files\": %d, \"rules\": %d,"
                " \"dropped_rules\": %d, \"dropped_decls\": %d}}\n",
                html_path, st.elements, st.text, st.comments, st.max_depth,
                css_count, rules, dropped_rules, dropped_decls);
        fclose(jf);
    }

    for (int i = 0; i < css_count; i++) cs_sheet_free(sheets[i]);
    nx_doc_free(doc);
    if (!ok) return 3;
    printf("nativax-debug: wrote %s/{dom.txt,dom.json,css.txt,summary.json}\n",
           out_dir);
    return 0;
}
