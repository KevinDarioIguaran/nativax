#ifndef NATIVAX_IMAGE_H
#define NATIVAX_IMAGE_H

/*
    Image decode (PNG/JPEG via stb_image) + byte-budgeted cache keyed by
    caller-provided URL string. Registered textures are RGBA8 in the display
    list registry; pixels stay owned here until nx_image_reset().
*/

#include <stdint.h>

int32_t nx_image_load_file(const char* path);   /* registry id or -1 */
int32_t nx_image_load_url(const char* url, const uint8_t* bytes, int len);
void nx_image_set_budget(long bytes);           /* default 64 MB LRU */
void nx_image_reset(void);                      /* frees all cached images */
int nx_image_count(void);
long nx_image_bytes(void);

#endif /* NATIVAX_IMAGE_H */
