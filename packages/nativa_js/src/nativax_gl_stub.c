/* Platforms without EGL/GLES yet (iOS, macOS, Windows): WebGL reports
 * itself unavailable (getContext returns null). Surfaces and image decoding
 * still need a real implementation there; see docs/javascript-supported.md. */
#include "nativax_gl.h"

void nx_gl_install(JSContext *ctx) { (void)ctx; }
void nx_gl_release_current(void) {}
int32_t nx_gl_available(void) { return 0; }
int64_t nx_surface_create(void) { return 0; }
void nx_surface_retain(int64_t id) { (void)id; }
void nx_surface_release(int64_t id) { (void)id; }
const uint8_t *nx_surface_acquire(int64_t id, int32_t *width, int32_t *height, int64_t *frame) {
  (void)id;
  *width = 0;
  *height = 0;
  *frame = 0;
  return 0;
}
int64_t nx_surface_frame(int64_t id) { (void)id; return 0; }
