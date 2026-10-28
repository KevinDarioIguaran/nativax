/*
    NativaX C runtime — unit + golden tests (headless, no GPU/display).

    Golden policy: PNG goldens live in native/tests/goldens/. A missing golden
    is written on first run and reported as CREATED (must then be committed);
    an existing golden is compared with a small tolerance. Tests never pass by
    skipping a comparison silently.
*/
#include "nativax/display_list.h"
#include "nativax/image.h"
#include "nativax/raster.h"
#include "nativax/text.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "stb_image.h"
#include "stb_image_write.h"

static int g_failures;
static int g_checks;

#define CHECK(cond, ...)                                            \
    do {                                                            \
        g_checks++;                                                 \
        if (!(cond)) {                                              \
            g_failures++;                                           \
            fprintf(stderr, "FAIL %s:%d: ", __FILE__, __LINE__);    \
            fprintf(stderr, __VA_ARGS__);                           \
            fputc('\n', stderr);                                    \
        }                                                           \
    } while (0)

static const char* font_path(void) {
    static char path[512];
    snprintf(path, sizeof(path), "%s/assets/fonts/DejaVuSans.ttf", NATIVAX_SOURCE_DIR);
    return path;
}

static void reset_all_state(void) {
    nx_image_reset();
    nx_font_reset();
    nx_tex_reset_all();
}

/* ---- UTF-8 ---- */
static void test_utf8(void) {
    int i;
    i = 0; CHECK(nx_utf8_decode("A", 1, &i) == 'A' && i == 1, "ascii decode");
    i = 0; CHECK(nx_utf8_decode("\xc3\xa9", 2, &i) == 0xE9 && i == 2, "2-byte decode");
    i = 0; CHECK(nx_utf8_decode("\xe2\x82\xac", 3, &i) == 0x20AC && i == 3, "3-byte decode");
    i = 0; CHECK(nx_utf8_decode("\xf0\x9f\x98\x80", 4, &i) == 0x1F600 && i == 4, "4-byte decode");
    i = 0; CHECK(nx_utf8_decode("\xff", 1, &i) == 0xFFFD, "invalid byte -> U+FFFD");
}

/* ---- display list structure ---- */
static void test_dl_basics(void) {
    NxDisplayList dl;
    nx_dl_init(&dl);

    nx_dl_reset(&dl);
    nx_dl_fill_rect(&dl, 10, 10, 100, 50, (NxColor){1, 0, 0, 1}, NULL);
    nx_dl_fill_rect(&dl, 10, 70, 100, 50, (NxColor){0, 1, 0, 1}, NULL);
    CHECK(dl.group_count == 1, "consecutive same-texture fills merge into one group (got %u)",
          dl.group_count);
    CHECK(dl.vert_count == 8 && dl.index_count == 12, "two quads: 8 verts 12 indices (got %u/%u)",
          dl.vert_count, dl.index_count);

    nx_dl_reset(&dl);
    float radii[4] = {12, 12, 12, 12};
    nx_dl_fill_rect(&dl, 0, 0, 100, 100, (NxColor){1, 1, 1, 1}, radii);
    CHECK(dl.index_count >= 3 * 12, "rounded rect uses arc tessellation (got %u indices)",
          dl.index_count);

    nx_dl_reset(&dl);
    nx_dl_push_clip(&dl, 10, 20, 100, 50);
    nx_dl_fill_rect(&dl, 0, 0, 320, 200, (NxColor){0, 0, 1, 1}, NULL);
    nx_dl_pop_clip(&dl);
    nx_dl_fill_rect(&dl, 0, 0, 320, 200, (NxColor){1, 1, 1, 1}, NULL);
    CHECK(dl.groups[0].has_scissor && dl.groups[0].scissor[0] == 10 &&
              dl.groups[0].scissor[1] == 20 && dl.groups[0].scissor[2] == 100 &&
              dl.groups[0].scissor[3] == 50,
          "clip becomes scissor group");
    CHECK(!dl.groups[1].has_scissor, "pop restores unclipped group");

    /* nested clip intersects */
    nx_dl_reset(&dl);
    nx_dl_push_clip(&dl, 0, 0, 100, 100);
    nx_dl_push_clip(&dl, 50, 50, 100, 100);
    nx_dl_fill_rect(&dl, 0, 0, 10, 10, (NxColor){1, 1, 1, 1}, NULL);
    nx_dl_pop_clip(&dl);
    nx_dl_pop_clip(&dl);
    CHECK(dl.groups[0].scissor[0] == 50 && dl.groups[0].scissor[2] == 50,
          "nested clips intersect (got %d %d)", dl.groups[0].scissor[0], dl.groups[0].scissor[2]);

    /* stroke degenerates when border eats the box */
    nx_dl_reset(&dl);
    nx_dl_stroke_rect(&dl, 0, 0, 8, 8, (NxColor){1, 1, 1, 1}, NULL, 8);
    CHECK(dl.index_count == 6, "degenerate border falls back to fill (6 indices, got %u)",
          dl.index_count);

    nx_dl_free(&dl);
}

/* ---- text ---- */
static void test_text(void) {
    reset_all_state();
    int32_t font = nx_font_load(font_path());
    CHECK(font >= 0, "font loads: %s", font_path());
    if (font < 0) return;

    float asc = nx_font_ascent(font, 16);
    float desc = nx_font_descent(font, 16);
    float lh = nx_font_line_height(font, 16);
    CHECK(asc > 10 && asc < 17, "ascent sane at 16px (got %.2f)", asc);
    CHECK(desc > 1 && desc < 8, "descent sane at 16px (got %.2f)", desc);
    CHECK(lh > asc && lh < asc + desc + 8, "line height sane (got %.2f)", lh);

    float w_hello = nx_font_advance(font, 16, "Hello", 5);
    float w_hi = nx_font_advance(font, 16, "Hi", 2);
    float w_hello24 = nx_font_advance(font, 24, "Hello", 5);
    CHECK(w_hello > w_hi, "longer text wider (%.1f > %.1f)", w_hello, w_hi);
    CHECK(w_hello24 > w_hello * 1.3f, "larger size wider (%.1f vs %.1f)", w_hello24, w_hello);
    CHECK(fabsf(w_hello - nx_font_advance(font, 16, "Hello", 5)) < 0.01f,
          "advance deterministic");

    /* emission is deterministic and texture-grouped */
    NxDisplayList d1, d2;
    nx_dl_init(&d1);
    nx_dl_init(&d2);
    nx_dl_reset(&d1);
    nx_dl_reset(&d2);
    nx_text_emit(&d1, 0, 20, font, 16, (NxColor){0, 0, 0, 1}, "Hello NativaX", 13);
    nx_text_emit(&d2, 0, 20, font, 16, (NxColor){0, 0, 0, 1}, "Hello NativaX", 13);
    char s1[4096], s2[4096];
    nx_dl_describe(&d1, s1, sizeof(s1));
    nx_dl_describe(&d2, s2, sizeof(s2));
    CHECK(strcmp(s1, s2) == 0, "text emission deterministic");
    CHECK(d1.group_count >= 1 && d1.groups[0].alpha_only, "glyphs use alpha-only group");
    CHECK(d1.vert_count > 20, "glyph quads emitted (%u verts)", d1.vert_count);
    nx_dl_free(&d1);
    nx_dl_free(&d2);
    reset_all_state();
}

/* ---- images ---- */
static void test_images(void) {
    reset_all_state();
    const char* png_path = "/tmp/nativax_test_img.png";
    uint8_t px[8 * 8 * 4];
    for (int i = 0; i < 64; i++) {
        px[i * 4] = (uint8_t)(i * 4);
        px[i * 4 + 1] = 100;
        px[i * 4 + 2] = 200;
        px[i * 4 + 3] = 255;
    }
    CHECK(stbi_write_png(png_path, 8, 8, 4, px, 8 * 4), "write test png");

    int32_t img = nx_image_load_file(png_path);
    CHECK(img > 0, "image loads (reg id %d)", img);
    const NxTextureInfo* info = nx_tex_info(img);
    CHECK(info && info->kind == NX_TEX_IMAGE && info->width == 8 && info->height == 8,
          "image registered as RGBA8 8x8");
    CHECK(nx_image_count() == 1 && nx_image_bytes() == 8 * 8 * 4, "cache bytes tracked");

    int32_t again = nx_image_load_file(png_path);
    CHECK(again == img, "same path hits cache");

    /* LRU eviction under tiny budget */
    nx_image_set_budget(8 * 8 * 4); /* exactly one image */
    uint8_t px2[4 * 4 * 4] = {0};
    const char* png2 = "/tmp/nativax_test_img2.png";
    CHECK(stbi_write_png(png2, 4, 4, 4, px2, 4 * 4), "write second png");
    int32_t img2 = nx_image_load_file(png2);
    CHECK(img2 > 0 && img2 != img, "second image distinct");
    const NxTextureInfo* evicted = nx_tex_info(img);
    CHECK(evicted && evicted->pixels == NULL, "LRU evicted first image (detached)");
    nx_image_set_budget(64L * 1024 * 1024);
    reset_all_state();
    remove(png_path);
    remove(png2);
}

/* ---- golden scene ---- */
static void build_golden_scene(NxDisplayList* dl, int32_t font, int32_t img) {
    nx_dl_reset(dl);
    nx_dl_fill_rect(dl, 0, 0, 320, 200, (NxColor){0.94f, 0.95f, 0.97f, 1}, NULL);
    float r12[4] = {12, 12, 12, 12};
    nx_dl_fill_rect(dl, 20, 20, 280, 160, (NxColor){1, 1, 1, 1}, r12);
    nx_dl_stroke_rect(dl, 20, 20, 280, 160, (NxColor){0.84f, 0.86f, 0.91f, 1}, r12, 1);
    float r8[4] = {8, 8, 8, 8};
    nx_dl_fill_rect(dl, 40, 40, 80, 32, (NxColor){0.23f, 0.36f, 1.0f, 1}, r8);
    nx_dl_text(dl, 48, 62, font, 16, (NxColor){1, 1, 1, 1}, "NativaX", 7);
    if (img > 0) {
        nx_dl_image(dl, 248, 36, 32, 32, img, (NxColor){1, 1, 1, 1});
    }
    nx_dl_push_clip(dl, 40, 90, 240, 60);
    nx_dl_text(dl, 44, 112, font, 18, (NxColor){0.06f, 0.09f, 0.19f, 1},
               "Hello from the C runtime", 24);
    nx_dl_fill_rect(dl, 44, 120, 200, 6, (NxColor){0.23f, 0.36f, 1.0f, 0.5f}, NULL);
    nx_dl_pop_clip(dl);
    nx_dl_fill_rect(dl, 240, 150, 200, 40, (NxColor){1, 0, 0, 1}, NULL); /* overflows clip? no: after pop */
}

static void test_raster_golden(void) {
    reset_all_state();
    int32_t font = nx_font_load(font_path());
    CHECK(font >= 0, "font loads for golden");
    if (font < 0) return;

    /* in-memory gradient image via file round-trip */
    uint8_t px[8 * 8 * 4];
    for (int i = 0; i < 64; i++) {
        px[i * 4] = (uint8_t)(i * 4);
        px[i * 4 + 1] = 60;
        px[i * 4 + 2] = 180;
        px[i * 4 + 3] = 255;
    }
    const char* tmp = "/tmp/nativax_golden_src.png";
    stbi_write_png(tmp, 8, 8, 4, px, 8 * 4);
    int32_t img = nx_image_load_file(tmp);
    CHECK(img > 0, "golden image loads");

    NxDisplayList dl;
    nx_dl_init(&dl);
    build_golden_scene(&dl, font, img);

    char desc[8192];
    nx_dl_describe(&dl, desc, sizeof(desc));
    CHECK(strstr(desc, "clip=[40 90 240 60]") != NULL, "golden scene has clip group:\n%s", desc);
    CHECK(strstr(desc, "alpha=1") != NULL, "golden scene has glyph group");

    NxRaster r;
    nx_raster_init(&r, 320, 200);
    nx_raster_clear(&r, (NxColor){1, 1, 1, 1});
    nx_raster_run(&r, &dl);

    /* spot checks */
    uint8_t* center = r.pixels + ((size_t)75 * 320 + 200) * 4;
    CHECK(center[0] > 245 && center[1] > 245 && center[2] > 245, "card interior white (got %d %d %d)",
          center[0], center[1], center[2]);
    uint8_t* accent = r.pixels + ((size_t)68 * 320 + 116) * 4;
    CHECK(accent[2] > 200 && accent[0] < 120, "accent pill is blue (got %d %d %d)", accent[0],
          accent[1], accent[2]);
    uint8_t* outside = r.pixels + ((size_t)8 * 320 + 8) * 4;
    CHECK(outside[0] < 250, "background is light gray (got %d)", outside[0]);

    char golden_path[512], cur_path[512];
    snprintf(golden_path, sizeof(golden_path), "%s/tests/goldens/render_basic.png",
             NATIVAX_SOURCE_DIR);
    snprintf(cur_path, sizeof(cur_path), "/tmp/nativax_render_basic.png");
    nx_raster_write_png(&r, cur_path);

    int gw, gh, gc;
    unsigned char* golden = stbi_load(golden_path, &gw, &gh, &gc, 4);
    if (!golden) {
        /* first run: create the golden, require commit */
        char cmd[1200];
        snprintf(cmd, sizeof(cmd), "mkdir -p '%s/tests/goldens' && cp '%s' '%s'", NATIVAX_SOURCE_DIR,
                 cur_path, golden_path);
        CHECK(system(cmd) == 0, "golden created at %s (COMMIT THIS FILE)", golden_path);
        fprintf(stderr, "NOTICE: golden %s created from current output\n", golden_path);
    } else {
        CHECK(gw == r.width && gh == r.height, "golden size %dx%d vs current %dx%d", gw, gh,
              r.width, r.height);
        if (gw == r.width && gh == r.height) {
            int off = 0;
            long total = (long)gw * gh;
            for (long i = 0; i < total; i++) {
                for (int c = 0; c < 4; c++) {
                    int d = abs((int)golden[i * 4 + c] - (int)r.pixels[i * 4 + c]);
                    if (d > 3) {
                        off++;
                        break;
                    }
                }
            }
            double pct = 100.0 * off / total;
            CHECK(pct <= 0.5, "golden pixel diff %.3f%% (allowed 0.5%%); current: %s", pct, cur_path);
        }
        stbi_image_free(golden);
    }

    nx_raster_free(&r);
    nx_dl_free(&dl);
    remove(tmp);
    reset_all_state();
}

/* ---- long text wrap-free emission stays in one group per page ---- */
static void test_text_pages(void) {
    reset_all_state();
    int32_t font = nx_font_load(font_path());
    if (font < 0) {
        CHECK(false, "font loads");
        return;
    }
    NxDisplayList dl;
    nx_dl_init(&dl);
    char buf[64];
    for (int size = 12; size <= 48; size += 6) {
        snprintf(buf, sizeof(buf), "The quick brown fox %d", size);
        nx_dl_reset(&dl);
        nx_text_emit(&dl, 0, 30, font, (float)size, (NxColor){0, 0, 0, 1}, buf, (int)strlen(buf));
        CHECK(dl.vert_count > 0, "size %d emits glyphs", size);
    }
    nx_dl_free(&dl);
    reset_all_state();
}

static void check_golden_png(const char* name, NxRaster* r) {
    char golden_path[512], cur_path[512];
    snprintf(golden_path, sizeof(golden_path), "%s/tests/goldens/%s.png", NATIVAX_SOURCE_DIR, name);
    snprintf(cur_path, sizeof(cur_path), "/tmp/nativax_%s.png", name);
    nx_raster_write_png(r, cur_path);
    int gw, gh, gc;
    unsigned char* golden = stbi_load(golden_path, &gw, &gh, &gc, 4);
    if (!golden) {
        char cmd[1200];
        snprintf(cmd, sizeof(cmd), "mkdir -p '%s/tests/goldens' && cp '%s' '%s'", NATIVAX_SOURCE_DIR, cur_path, golden_path);
        CHECK(system(cmd) == 0, "golden created: %s (COMMIT)", golden_path);
        fprintf(stderr, "NOTICE: golden %s created\n", golden_path);
    } else {
        CHECK(gw == r->width && gh == r->height, "golden size %s", name);
        if (gw == r->width && gh == r->height) {
            long off = 0, total = (long)gw * gh;
            for (long i = 0; i < total; i++) {
                int bad = 0;
                for (int c = 0; c < 4; c++) {
                    if (abs((int)golden[i*4+c] - (int)r->pixels[i*4+c]) > 3) { bad = 1; break; }
                }
                if (bad) off++;
            }
            double pct = 100.0 * off / total;
            CHECK(pct <= 0.5, "golden %s diff %.3f%%", name, pct);
        }
        stbi_image_free(golden);
    }
}

/* ---- extra visual regression scenes ---- */
static void test_vr_flex(void) {
    reset_all_state();
    int32_t font = nx_font_load(font_path());
    if (font < 0) return;
    NxDisplayList dl; nx_dl_init(&dl); nx_dl_reset(&dl);
    /* page bg */
    nx_dl_fill_rect(&dl, 0, 0, 320, 200, (NxColor){0.94f,0.95f,0.97f,1}, NULL);
    /* flex container simulated via display list: three rects with gap */
    nx_dl_fill_rect(&dl, 20, 20, 90, 40, (NxColor){0.23f,0.36f,1.0f,1}, NULL);
    nx_dl_fill_rect(&dl, 120, 20, 90, 40, (NxColor){0.23f,0.36f,1.0f,1}, NULL);
    nx_dl_fill_rect(&dl, 220, 20, 80, 40, (NxColor){0.23f,0.36f,1.0f,1}, NULL);
    NxRaster r; nx_raster_init(&r, 320, 200); nx_raster_clear(&r, (NxColor){1,1,1,1});
    nx_raster_run(&r, &dl);
    check_golden_png("vr_flex", &r);
    nx_raster_free(&r); nx_dl_free(&dl); reset_all_state();
}

static void test_vr_opacity_transform(void) {
    reset_all_state();
    NxDisplayList dl; nx_dl_init(&dl); nx_dl_reset(&dl);
    nx_dl_fill_rect(&dl, 0, 0, 320, 200, (NxColor){0.1f,0.1f,0.15f,1}, NULL);
    nx_dl_begin_layer(&dl, 0.6f);
    float rad[4]={16,16,16,16};
    nx_dl_fill_rect(&dl, 40, 40, 200, 80, (NxColor){0.9f,0.3f,0.3f,1}, rad);
    nx_dl_end_layer(&dl);
    NxMat2x3 m = nx_mat_translate(20, 0);
    nx_dl_push_transform(&dl, &m);
    nx_dl_fill_rect(&dl, 40, 140, 120, 40, (NxColor){0.3f,0.8f,0.4f,1}, NULL);
    nx_dl_pop_transform(&dl);
    NxRaster r; nx_raster_init(&r, 320, 200); nx_raster_clear(&r, (NxColor){0,0,0,1});
    nx_raster_run(&r, &dl);
    check_golden_png("vr_opacity_transform", &r);
    nx_raster_free(&r); nx_dl_free(&dl); reset_all_state();
}

static void test_vr_overflow(void) {
    reset_all_state();
    NxDisplayList dl; nx_dl_init(&dl); nx_dl_reset(&dl);
    nx_dl_fill_rect(&dl, 0, 0, 320, 200, (NxColor){0.95f,0.95f,0.95f,1}, NULL);
    nx_dl_push_clip(&dl, 50, 50, 120, 60);
    nx_dl_fill_rect(&dl, 40, 40, 200, 100, (NxColor){0.2f,0.5f,0.9f,1}, NULL);
    nx_dl_pop_clip(&dl);
    NxRaster r; nx_raster_init(&r, 320, 200); nx_raster_clear(&r, (NxColor){1,1,1,1});
    nx_raster_run(&r, &dl);
    check_golden_png("vr_overflow", &r);
    nx_raster_free(&r); nx_dl_free(&dl); reset_all_state();
}

static void test_vr_text_align(void) {
    reset_all_state();
    int32_t font = nx_font_load(font_path());
    if (font < 0) return;
    NxDisplayList dl; nx_dl_init(&dl); nx_dl_reset(&dl);
    nx_dl_fill_rect(&dl, 0, 0, 320, 200, (NxColor){1,1,1,1}, NULL);
    NxColor c = (NxColor){0,0,0,1};
    nx_dl_text(&dl, 0, 30, font, 16, c, "left aligned", 12);
    NxRaster r; nx_raster_init(&r, 320, 200); nx_raster_clear(&r, (NxColor){1,1,1,1});
    nx_raster_run(&r, &dl);
    check_golden_png("vr_text_align", &r);
    nx_raster_free(&r); nx_dl_free(&dl); reset_all_state();
}

static void test_vr_borders(void) {
    reset_all_state();
    NxDisplayList dl; nx_dl_init(&dl); nx_dl_reset(&dl);
    nx_dl_fill_rect(&dl, 0, 0, 320, 200, (NxColor){0.9f,0.9f,0.9f,1}, NULL);
    float rad[4]={10,10,10,10};
    nx_dl_stroke_rect(&dl, 20, 20, 120, 60, (NxColor){0.8f,0.2f,0.2f,1}, rad, 3);
    nx_dl_stroke_rect(&dl, 160, 20, 120, 60, (NxColor){0.2f,0.2f,0.8f,1}, NULL, 2);
    NxRaster r; nx_raster_init(&r, 320, 200); nx_raster_clear(&r, (NxColor){1,1,1,1});
    nx_raster_run(&r, &dl);
    check_golden_png("vr_borders", &r);
    nx_raster_free(&r); nx_dl_free(&dl); reset_all_state();
}


/* ---- 10 HTML/CSS 2D debug scenes ---- */
static void vr_scene(int idx) {
    reset_all_state();
    NxDisplayList dl; nx_dl_init(&dl); nx_dl_reset(&dl);
    int32_t font = nx_font_load(font_path());
    char name[64]; snprintf(name, sizeof(name), "vr_scene_%02d", idx);
    switch (idx) {
    case 0:
        nx_dl_fill_rect(&dl, 0,0,320,200,(NxColor){1,1,1,1},NULL);
        { float r[4]={8,8,8,8}; nx_dl_fill_rect(&dl,20,20,120,60,(NxColor){0.2f,0.4f,0.8f,1},r); }
        nx_dl_stroke_rect(&dl,20,100,120,60,(NxColor){0.8f,0.2f,0.2f,1},NULL,2);
        break;
    case 1:
        nx_dl_fill_rect(&dl,0,0,320,200,(NxColor){0.9f,0.9f,0.95f,1},NULL);
        nx_dl_push_clip(&dl,40,40,120,80);
        nx_dl_fill_rect(&dl,30,30,200,120,(NxColor){0.3f,0.7f,0.4f,1},NULL);
        nx_dl_pop_clip(&dl);
        break;
    case 2: {
        nx_dl_fill_rect(&dl,0,0,320,200,(NxColor){0.1f,0.1f,0.15f,1},NULL);
        nx_dl_begin_layer(&dl,0.5f);
        nx_dl_fill_rect(&dl,50,50,150,80,(NxColor){0.9f,0.5f,0.2f,1},NULL);
        nx_dl_end_layer(&dl);
        break;
    }
    case 3: {
        NxMat2x3 m=nx_mat_translate(30,20);
        nx_dl_push_transform(&dl,&m);
        nx_dl_fill_rect(&dl,0,0,100,50,(NxColor){0.6f,0.2f,0.7f,1},NULL);
        nx_dl_pop_transform(&dl);
        break;
    }
    case 4:
        if (font>=0) nx_dl_text(&dl,20,40,font,20,(NxColor){0,0,0,1},"Hello Debug",11);
        break;
    case 5:
        nx_dl_fill_rect(&dl,0,0,320,200,(NxColor){1,1,1,1},NULL);
        { float r[4]={20,5,20,5}; nx_dl_fill_rect(&dl,30,30,100,60,(NxColor){0.4f,0.6f,0.9f,1},r); }
        break;
    case 6: {
        NxMat2x3 s=nx_mat_scale(1.5f,1.5f);
        nx_dl_push_transform(&dl,&s);
        nx_dl_fill_rect(&dl,10,10,60,40,(NxColor){0.9f,0.7f,0.1f,1},NULL);
        nx_dl_pop_transform(&dl);
        break;
    }
    case 7:
        nx_dl_fill_rect(&dl,0,0,320,200,(NxColor){0.8f,0.8f,0.8f,1},NULL);
        nx_dl_begin_layer(&dl,0.3f);
        nx_dl_fill_rect(&dl,80,60,160,80,(NxColor){0,0,0,1},NULL);
        nx_dl_end_layer(&dl);
        break;
    case 8:
        nx_dl_fill_rect(&dl,0,0,320,200,(NxColor){0.95f,0.95f,0.95f,1},NULL);
        nx_dl_push_clip(&dl,100,80,120,60);
        nx_dl_fill_rect(&dl,0,0,320,200,(NxColor){0.1f,0.8f,0.8f,1},NULL);
        nx_dl_pop_clip(&dl);
        break;
    case 9:
        nx_dl_fill_rect(&dl,0,0,320,200,(NxColor){0.2f,0.2f,0.25f,1},NULL);
        { float r[4]={0,30,0,30}; nx_dl_fill_rect(&dl,40,40,100,100,(NxColor){0.8f,0.4f,0.4f,1},r); }
        break;
    }
    NxRaster r; nx_raster_init(&r,320,200); nx_raster_clear(&r,(NxColor){0,0,0,1});
    nx_raster_run(&r,&dl);
    check_golden_png(name,&r);
    nx_raster_free(&r); nx_dl_free(&dl);
    reset_all_state();
}

static void test_vr_10_scenes(void) {
    for (int i=0;i<10;i++) vr_scene(i);
}
static void test_effects(void) {
    reset_all_state();
    int32_t font = nx_font_load(font_path());
    CHECK(font >= 0, "font loads for effects");
    if (font < 0) return;

    /* transform stack is a real stack */
    NxDisplayList dl;
    nx_dl_init(&dl);
    nx_dl_reset(&dl);
    NxMat2x3 m = nx_mat_translate(10, 20);
    nx_dl_push_transform(&dl, &m);
    NxMat2x3 m2 = nx_mat_scale(2, 2);
    nx_dl_push_transform(&dl, &m2);
    nx_dl_fill_rect(&dl, 0, 0, 5, 5, (NxColor){1, 0, 0, 1}, NULL);
    /* point (0,0) -> scale -> (0,0) -> translate -> (10,20) */
    CHECK(fabsf(dl.verts[0].x - 10.0f) < 0.01f && fabsf(dl.verts[0].y - 20.0f) < 0.01f,
          "nested transform applied (got %.1f,%.1f)", dl.verts[0].x, dl.verts[0].y);
    nx_dl_pop_transform(&dl);
    nx_dl_pop_transform(&dl);
    nx_dl_reset(&dl);
    nx_dl_fill_rect(&dl, 3, 4, 5, 5, (NxColor){0, 0, 0, 1}, NULL);
    CHECK(fabsf(dl.verts[0].x - 3.0f) < 0.01f && fabsf(dl.verts[0].y - 4.0f) < 0.01f,
          "pop restores identity");

    /* layer records and forced boundaries */
    nx_dl_reset(&dl);
    nx_dl_fill_rect(&dl, 0, 0, 1, 1, (NxColor){1, 0, 0, 1}, NULL);
    uint32_t groups_before = dl.group_count;
    nx_dl_begin_layer(&dl, 0.5f);
    nx_dl_fill_rect(&dl, 0, 0, 1, 1, (NxColor){0, 1, 0, 1}, NULL);
    nx_dl_end_layer(&dl);
    nx_dl_fill_rect(&dl, 0, 0, 1, 1, (NxColor){0, 0, 1, 1}, NULL);
    CHECK(dl.layer_count == 1, "one layer recorded (got %u)", dl.layer_count);
    CHECK(dl.layers[0].opacity > 0.49f && dl.layers[0].opacity < 0.51f, "layer opacity stored");
    CHECK(dl.layers[0].parent == -1, "top-level layer parent -1");
    CHECK(dl.layers[0].group_count >= 1, "layer has at least one group");
    /* the layer must not have merged with the preceding same-texture group */
    CHECK(dl.group_count > groups_before, "layer forced a new group");

    /* nested layers */
    nx_dl_reset(&dl);
    nx_dl_begin_layer(&dl, 1.0f);
    nx_dl_begin_layer(&dl, 0.25f);
    nx_dl_fill_rect(&dl, 0, 0, 1, 1, (NxColor){1, 1, 1, 1}, NULL);
    nx_dl_end_layer(&dl);
    nx_dl_end_layer(&dl);
    CHECK(dl.layer_count == 2, "two layers (got %u)", dl.layer_count);
    CHECK(dl.layers[1].parent == 0, "inner layer parent is outer (got %d)", dl.layers[1].parent);

    /* group opacity composites the whole range once (not per primitive) */
    NxRaster r;
    nx_raster_init(&r, 20, 20);
    nx_raster_clear(&r, (NxColor){0, 0, 0, 1});
    NxDisplayList dl2;
    nx_dl_init(&dl2);
    nx_dl_reset(&dl2);
    nx_dl_begin_layer(&dl2, 0.5f);
    nx_dl_fill_rect(&dl2, 0, 0, 20, 20, (NxColor){0, 0, 1, 1}, NULL);
    nx_dl_fill_rect(&dl2, 10, 0, 10, 20, (NxColor){1, 0, 0, 1}, NULL);
    nx_dl_end_layer(&dl2);
    nx_raster_run(&r, &dl2);
    uint8_t* px = r.pixels + ((size_t)10 * 20 + 15) * 4;
    /* right half: red at 50% over black, NOT blended with the blue underneath */
    CHECK(px[0] > 120 && px[0] < 140 && px[1] < 20 && px[2] < 20,
          "group opacity applied once (got %d %d %d)", px[0], px[1], px[2]);
    nx_raster_free(&r);
    nx_dl_free(&dl2);

    /* rounded corners: corner pixel stays background, center is filled */
    nx_raster_init(&r, 20, 20);
    nx_raster_clear(&r, (NxColor){0, 0, 0, 1});
    nx_dl_reset(&dl);
    float rad[4] = {8, 8, 8, 8};
    nx_dl_fill_rect(&dl, 0, 0, 20, 20, (NxColor){1, 0, 0, 1}, rad);
    nx_raster_run(&r, &dl);
    uint8_t* corner = r.pixels + 0;
    uint8_t* center = r.pixels + ((size_t)10 * 20 + 10) * 4;
    CHECK(corner[0] < 10 && corner[1] < 10 && corner[2] < 10, "rounded corner is background (got %d %d %d)",
          corner[0], corner[1], corner[2]);
    CHECK(center[0] > 180 && center[1] < 20 && center[2] < 20, "rounded center is red (got %d %d %d)",
          center[0], center[1], center[2]);
    nx_raster_free(&r);

    /* matrix invert */
    NxMat2x3 t = nx_mat_translate(5, 7);
    NxMat2x3 inv;
    CHECK(nx_mat_invert(&t, &inv), "translate invertible");
    NxMat2x3 id = nx_mat_mul(&t, &inv);
    CHECK(fabsf(id.a - 1) < 1e-5f && fabsf(id.e) < 1e-5f, "inverse is correct");

    nx_dl_free(&dl);
    reset_all_state();
}
int main(int argc, char** argv) {
    if (argc > 1 && strcmp(argv[1], "--dump-atlas") == 0) {
        /* debug aid: rasterize a phrase and dump glyph atlas pages */
        reset_all_state();
        int32_t font = nx_font_load(font_path());
        NxDisplayList dl;
        nx_dl_init(&dl);
        nx_dl_reset(&dl);
        nx_text_emit(&dl, 20, 60, font, 32, (NxColor){0, 0, 0, 1}, "Hello NativaX 123", 16);
        NxRaster r;
        nx_raster_init(&r, 320, 100);
        nx_raster_clear(&r, (NxColor){1, 1, 1, 1});
        nx_raster_run(&r, &dl);
        nx_raster_write_png(&r, "/tmp/atlas_text.png");
        for (int i = 0; i < 3; i++) {
            const NxTextureInfo* info = nx_tex_info(i + 1);
            if (info && info->kind == NX_TEX_GLYPH && info->pixels) {
                char path[64];
                snprintf(path, sizeof(path), "/tmp/atlas_page%d.png", i);
                NxRaster page;
                nx_raster_init(&page, info->width, info->height);
                for (int y = 0; y < info->height; y++) {
                    for (int x = 0; x < info->width; x++) {
                        uint8_t a = info->pixels[(size_t)y * info->stride + x];
                        uint8_t* p = page.pixels + ((size_t)y * info->width + x) * 4;
                        p[0] = p[1] = p[2] = a;
                        p[3] = 255;
                    }
                }
                nx_raster_write_png(&page, path);
                nx_raster_free(&page);
            }
        }
        nx_raster_free(&r);
        nx_dl_free(&dl);
        return 0;
    }
    test_utf8();
    test_dl_basics();
    test_text();
    test_images();
    test_raster_golden();
    test_text_pages();
    test_effects();
    test_vr_10_scenes();
    test_vr_flex();
    test_vr_opacity_transform();
    test_vr_overflow();
    test_vr_text_align();
    test_vr_borders();

    fprintf(stderr, "%d checks, %d failures\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
