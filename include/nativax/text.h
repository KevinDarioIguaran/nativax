#ifndef NATIVAX_TEXT_H
#define NATIVAX_TEXT_H

/*
    Font registry, glyph atlas and LTR per-codepoint shaping (v1).

    Limitations (documented): no HarfBuzz shaping, no bidi, no kerning tables
    applied (stb_truetype advances only), Latin/LTR only. The atlas packs
    glyphs on demand per (font, size, codepoint) into R8 pages; insertion order
    is paint order, which is deterministic for golden tests.
*/

#include "nativax/display_list.h"

int32_t nx_font_load(const char* path);            /* returns font id or -1 */
int32_t nx_font_load_mem(const uint8_t* data, long len);
void nx_font_reset(void);                          /* drop fonts + atlas pages */

float nx_font_ascent(int32_t font, float size);
float nx_font_descent(int32_t font, float size);   /* positive below baseline */
float nx_font_line_height(int32_t font, float size);
float nx_font_advance(int32_t font, float size, const char* utf8, int len);

/* Shape + emit glyph quads at baseline (x, baseline_y). */
void nx_text_emit(NxDisplayList* dl, float x, float baseline_y, int32_t font, float size_px,
                  NxColor color, const char* utf8, int len);

/* UTF-8 helper shared with the DOM: decodes one codepoint, advances *i. */
uint32_t nx_utf8_decode(const char* s, int len, int* i);

#endif /* NATIVAX_TEXT_H */
