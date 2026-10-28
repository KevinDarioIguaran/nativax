#include "nativax/text.h"

#include "nativax/log.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "stb_truetype.h"

#define NX_MAX_FONTS 8
#define NX_ATLAS_PAGE 1024
#define NX_ATLAS_PAD 1

typedef struct NxFont {
    uint8_t* data; /* owned copy (stb keeps raw pointers) */
    long data_len;
    stbtt_fontinfo info;
    unsigned units_per_em;
    float ascent, descent, line_gap; /* font units */
    bool used;
} NxFont;

typedef struct NxGlyph {
    int32_t page;      /* texture registry id */
    float u0, v0, u1, v1;
    float xoff, yoff;  /* bitmap offset from (pen, baseline) */
    float w, h;        /* bitmap size px */
    float advance;
} NxGlyph;

typedef struct NxAtlasPage {
    uint8_t* pixels; /* A8 coverage, stride = NX_ATLAS_PAGE */
    int32_t reg_id;
    int shelf_x, shelf_y, shelf_h;
} NxAtlasPage;

static NxFont g_fonts[NX_MAX_FONTS];
static int g_font_count;

static NxAtlasPage* g_pages;
static int g_page_count, g_page_cap;

/* glyph cache: open-addressed hash (font,size,codepoint) -> NxGlyph */
typedef struct GlyphKeyEntry {
    uint64_t key;
    NxGlyph glyph;
} GlyphKeyEntry;

static GlyphKeyEntry* g_glyphs;
static int g_glyph_cap, g_glyph_count;

static uint32_t utf8_len(uint32_t cp) {
    if (cp < 0x80) return 1;
    if (cp < 0x800) return 2;
    if (cp < 0x10000) return 3;
    return 4;
}

uint32_t nx_utf8_decode(const char* s, int len, int* i) {
    if (*i >= len) return 0;
    const uint8_t* u = (const uint8_t*)s;
    uint32_t cp = u[*i];
    int n = 0;
    if (cp < 0x80) {
        n = 1;
    } else if ((cp & 0xE0) == 0xC0) {
        cp &= 0x1F; n = 2;
    } else if ((cp & 0xF0) == 0xE0) {
        cp &= 0x0F; n = 3;
    } else if ((cp & 0xF8) == 0xF0) {
        cp &= 0x07; n = 4;
    } else {
        (*i)++;
        return 0xFFFD;
    }
    for (int k = 1; k < n; k++) {
        if (*i + k >= len || (u[*i + k] & 0xC0) != 0x80) {
            *i += k;
            return 0xFFFD;
        }
        cp = (cp << 6) | (u[*i + k] & 0x3F);
    }
    *i += n;
    return cp;
}

int32_t nx_font_load_mem(const uint8_t* data, long len) {
    if (g_font_count >= NX_MAX_FONTS) return -1;
    NxFont* f = &g_fonts[g_font_count];
    f->data = malloc((size_t)len);
    if (!f->data) return -1;
    memcpy(f->data, data, (size_t)len);
    f->data_len = len;
    if (!stbtt_InitFont(&f->info, f->data, stbtt_GetFontOffsetForIndex(f->data, 0))) {
        free(f->data);
        f->data = NULL;
        return -1;
    }
    int a, d, g;
    stbtt_GetFontVMetrics(&f->info, &a, &d, &g);
    /* unitsPerEm from the 'head' table (offset table directory walk) */
    f->units_per_em = 0;
    const uint8_t* raw = f->data;
    long num_tables = (raw[4] << 8) | raw[5];
    for (long t = 0; t < num_tables; t++) {
        const uint8_t* rec = raw + 12 + t * 16;
        if (memcmp(rec, "head", 4) == 0) {
            long off = ((long)rec[8] << 24) | ((long)rec[9] << 16) | ((long)rec[10] << 8) | rec[11];
            if (off + 20 <= f->data_len) {
                f->units_per_em = (unsigned)((raw[off + 18] << 8) | raw[off + 19]);
            }
            break;
        }
    }
    if (f->units_per_em == 0) f->units_per_em = 2048;
    f->ascent = (float)a;
    f->descent = (float)-d; /* positive downward */
    f->line_gap = (float)g;
    f->used = true;
    return g_font_count++;
}

int32_t nx_font_load(const char* path) {
    FILE* fp = fopen(path, "rb");
    if (!fp) return -1;
    fseek(fp, 0, SEEK_END);
    long len = ftell(fp);
    fseek(fp, 0, SEEK_SET);
    uint8_t* data = malloc((size_t)len);
    if (!data || fread(data, 1, (size_t)len, fp) != (size_t)len) {
        free(data);
        fclose(fp);
        return -1;
    }
    fclose(fp);
    int32_t id = nx_font_load_mem(data, len);
    free(data); /* load_mem copies */
    return id;
}

void nx_font_reset(void) {
    for (int i = 0; i < g_font_count; i++) free(g_fonts[i].data);
    memset(g_fonts, 0, sizeof(g_fonts));
    g_font_count = 0;
    for (int i = 0; i < g_page_count; i++) free(g_pages[i].pixels);
    free(g_pages);
    g_pages = NULL;
    g_page_count = g_page_cap = 0;
    free(g_glyphs);
    g_glyphs = NULL;
    g_glyph_cap = g_glyph_count = 0;
}

float nx_font_ascent(int32_t font, float size) {
    if (font < 0 || font >= g_font_count) return 0;
    const NxFont* f = &g_fonts[font];
    return f->ascent / (float)f->units_per_em * size;
}
float nx_font_descent(int32_t font, float size) {
    if (font < 0 || font >= g_font_count) return 0;
    const NxFont* f = &g_fonts[font];
    return f->descent / (float)f->units_per_em * size;
}
float nx_font_line_height(int32_t font, float size) {
    if (font < 0 || font >= g_font_count) return 0;
    const NxFont* f = &g_fonts[font];
    return (f->ascent + f->descent + f->line_gap) / (float)f->units_per_em * size;
}

/* ---- atlas ---- */
static NxAtlasPage* page_new(void) {
    if (g_page_count == g_page_cap) {
        g_page_cap = g_page_cap ? g_page_cap * 2 : 4;
        g_pages = realloc(g_pages, (size_t)g_page_cap * sizeof(NxAtlasPage));
    }
    NxAtlasPage* p = &g_pages[g_page_count++];
    p->pixels = calloc((size_t)NX_ATLAS_PAGE * NX_ATLAS_PAGE, 1);
    p->shelf_x = p->shelf_y = p->shelf_h = 0;
    p->reg_id = nx_tex_register(NX_TEX_GLYPH, NX_ATLAS_PAGE, NX_ATLAS_PAGE, NX_ATLAS_PAGE,
                                p->pixels);
    return p;
}

/* returns false when w/h exceed page size */
static bool atlas_pack(int w, int h, int* out_page, int* out_x, int* out_y) {
    for (int attempt = 0; attempt < 2; attempt++) {
        NxAtlasPage* p = g_page_count ? &g_pages[g_page_count - 1] : page_new();
        if (p->shelf_x + w + NX_ATLAS_PAD > NX_ATLAS_PAGE) {
            p->shelf_x = 0;
            p->shelf_y += p->shelf_h + NX_ATLAS_PAD;
            p->shelf_h = 0;
        }
        if (p->shelf_y + h + NX_ATLAS_PAD > NX_ATLAS_PAGE) {
            page_new();
            continue;
        }
        *out_page = g_page_count - 1;
        *out_x = p->shelf_x;
        *out_y = p->shelf_y;
        p->shelf_x += w + NX_ATLAS_PAD;
        if (h > p->shelf_h) p->shelf_h = h;
        return true;
    }
    return false;
}

static uint64_t glyph_key(int32_t font, int size_q, uint32_t cp) {
    return ((uint64_t)(uint32_t)font << 48) | ((uint64_t)(uint32_t)size_q << 32) | cp;
}

static NxGlyph* glyph_lookup(uint64_t key) {
    if (!g_glyph_cap) return NULL;
    uint32_t mask = (uint32_t)g_glyph_cap - 1;
    uint32_t i = (uint32_t)(key * 0x9E3779B97F4A7C15ULL) & mask;
    for (;;) {
        GlyphKeyEntry* e = &g_glyphs[i];
        if (e->key == key + 1 && e->glyph.w >= 0) return &e->glyph; /* key stored +1, empty=-1 */
        if (e->key == 0) return NULL;
        i = (i + 1) & mask;
    }
}

static void glyph_insert(uint64_t key, NxGlyph g) {
    if (g_glyph_cap == 0 || (g_glyph_count + 1) * 4 > g_glyph_cap * 3) {
        int new_cap = g_glyph_cap ? g_glyph_cap * 2 : 1024;
        GlyphKeyEntry* nt = calloc((size_t)new_cap, sizeof(GlyphKeyEntry));
        uint32_t mask = (uint32_t)new_cap - 1;
        for (int i = 0; i < g_glyph_cap; i++) {
            if (g_glyphs[i].key == 0) continue;
            uint32_t j = (uint32_t)(g_glyphs[i].key * 0x9E3779B97F4A7C15ULL) & mask;
            while (nt[j].key != 0) j = (j + 1) & mask;
            nt[j] = g_glyphs[i];
        }
        free(g_glyphs);
        g_glyphs = nt;
        g_glyph_cap = new_cap;
    }
    uint32_t mask = (uint32_t)g_glyph_cap - 1;
    uint32_t i = (uint32_t)(key * 0x9E3779B97F4A7C15ULL) & mask;
    while (g_glyphs[i].key != 0) i = (i + 1) & mask;
    g_glyphs[i].key = key + 1;
    g_glyphs[i].glyph = g;
    g_glyph_count++;
}

static NxGlyph* glyph_get(int32_t font, float size, uint32_t cp) {
    int size_q = (int)(size + 0.5f);
    if (size_q < 1) size_q = 1;
    if (size_q > 512) size_q = 512;
    uint64_t key = glyph_key(font, size_q, cp);
    NxGlyph* hit = glyph_lookup(key);
    if (hit) return hit;

    const NxFont* f = &g_fonts[font];
    float scale = stbtt_ScaleForMappingEmToPixels(&f->info, (float)size_q);
    int glyph = stbtt_FindGlyphIndex(&f->info, cp);
    int adv;
    stbtt_GetGlyphHMetrics(&f->info, glyph, &adv, NULL);

    NxGlyph g = {.page = -1, .advance = adv * scale};
    int ix0, iy0, ix1, iy1;
    stbtt_GetGlyphBitmapBox(&f->info, glyph, scale, scale, &ix0, &iy0, &ix1, &iy1);
    int w = ix1 - ix0, h = iy1 - iy0;
    if (w > 0 && h > 0) {
        int pg, px, py;
        if (atlas_pack(w, h, &pg, &px, &py)) {
            NxAtlasPage* page = &g_pages[pg];
            stbtt_MakeGlyphBitmap(&f->info, page->pixels + (size_t)py * NX_ATLAS_PAGE + px, w, h,
                                  NX_ATLAS_PAGE, scale, scale, glyph);
            g.page = page->reg_id;
            g.u0 = (float)px / NX_ATLAS_PAGE;
            g.v0 = (float)py / NX_ATLAS_PAGE;
            g.u1 = (float)(px + w) / NX_ATLAS_PAGE;
            g.v1 = (float)(py + h) / NX_ATLAS_PAGE;
            g.xoff = (float)ix0;
            g.yoff = (float)iy0;
            g.w = (float)w;
            g.h = (float)h;
        } else {
            NX_WARN("glyph atlas full: %04X at %dpx not rasterized", cp, size_q);
        }
    }
    glyph_insert(key, g);
    return glyph_lookup(key);
}

float nx_font_advance(int32_t font, float size, const char* utf8, int len) {
    if (font < 0 || font >= g_font_count) return 0;
    float pen = 0;
    int i = 0;
    while (i < len) {
        uint32_t cp = nx_utf8_decode(utf8, len, &i);
        if (cp == 0) break;
        const NxGlyph* g = glyph_get(font, size, cp);
        pen += g->advance;
    }
    return pen;
}

void nx_text_emit(NxDisplayList* dl, float x, float baseline_y, int32_t font, float size_px,
                  NxColor color, const char* utf8, int len) {
    if (font < 0 || font >= g_font_count || len <= 0) return;
    float pen = x;
    int i = 0;
    (void)utf8_len;
    while (i < len) {
        uint32_t cp = nx_utf8_decode(utf8, len, &i);
        if (cp == 0) break;
        if (cp == ' ') { /* fast path: space advances, never visible */
            const NxGlyph* g = glyph_get(font, size_px, cp);
            pen += g->advance;
            continue;
        }
        const NxGlyph* g = glyph_get(font, size_px, cp);
        if (g->page >= 0) {
            nx_dl_emit_quad(dl, pen + g->xoff, baseline_y + g->yoff, pen + g->xoff + g->w,
                            baseline_y + g->yoff + g->h, g->u0, g->v0, g->u1, g->v1, color,
                            g->page, true);
        }
        pen += g->advance;
    }
}
