#include "nativax/image.h"

#include "nativax/display_list.h"
#include "nativax/log.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "stb_image.h"

typedef struct NxImageEntry {
    char url[256];
    int width, height;
    uint8_t* pixels; /* RGBA8, owned */
    int32_t reg_id;
    long bytes;
    unsigned long last_used;
} NxImageEntry;

static NxImageEntry* g_images;
static int g_count, g_cap;
static long g_budget = 64L * 1024 * 1024;
static long g_bytes;
static unsigned long g_clock;

static void evict_if_needed(void) {
    while (g_bytes > g_budget && g_count > 0) {
        int lru = 0;
        for (int i = 1; i < g_count; i++) {
            if (g_images[i].last_used < g_images[lru].last_used) lru = i;
        }
        NxImageEntry* e = &g_images[lru];
        NX_DEBUG("image evict %s (%ld bytes)", e->url, e->bytes);
        nx_tex_detach(e->reg_id);
        free(e->pixels);
        g_bytes -= e->bytes;
        g_images[lru] = g_images[g_count - 1];
        g_count--;
    }
}

int32_t nx_image_load_url(const char* url, const uint8_t* bytes, int len) {
    for (int i = 0; i < g_count; i++) {
        if (strcmp(g_images[i].url, url) == 0) {
            g_images[i].last_used = ++g_clock;
            return g_images[i].reg_id;
        }
    }
    int w, h, comp;
    unsigned char* px = stbi_load_from_memory(bytes, len, &w, &h, &comp, 4);
    if (!px) {
        NX_WARN("image decode failed for %s: %s", url, stbi_failure_reason());
        return -1;
    }
    if (g_count == g_cap) {
        g_cap = g_cap ? g_cap * 2 : 16;
        g_images = realloc(g_images, (size_t)g_cap * sizeof(NxImageEntry));
    }
    NxImageEntry* e = &g_images[g_count++];
    snprintf(e->url, sizeof(e->url), "%s", url);
    e->width = w;
    e->height = h;
    e->pixels = px; /* stbi malloc; freed with free() */
    e->bytes = (long)w * h * 4;
    e->last_used = ++g_clock;
    e->reg_id = nx_tex_register(NX_TEX_IMAGE, w, h, w * 4, px);
    g_bytes += e->bytes;
    evict_if_needed();
    return e->reg_id;
}

int32_t nx_image_load_file(const char* path) {
    FILE* fp = fopen(path, "rb");
    if (!fp) return -1;
    fseek(fp, 0, SEEK_END);
    long len = ftell(fp);
    fseek(fp, 0, SEEK_SET);
    if (len <= 0 || len > 128L * 1024 * 1024) {
        fclose(fp);
        return -1;
    }
    uint8_t* bytes = malloc((size_t)len);
    if (!bytes || fread(bytes, 1, (size_t)len, fp) != (size_t)len) {
        free(bytes);
        fclose(fp);
        return -1;
    }
    fclose(fp);
    int32_t id = nx_image_load_url(path, bytes, (int)len);
    free(bytes);
    return id;
}

void nx_image_set_budget(long bytes) { g_budget = bytes; }

void nx_image_reset(void) {
    for (int i = 0; i < g_count; i++) {
        nx_tex_detach(g_images[i].reg_id);
        free(g_images[i].pixels);
    }
    free(g_images);
    g_images = NULL;
    g_count = g_cap = 0;
    g_bytes = 0;
}

int nx_image_count(void) { return g_count; }
long nx_image_bytes(void) { return g_bytes; }
