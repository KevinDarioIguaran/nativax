/* WebGL is not wired to JavaScriptCore yet: it reports itself unavailable
 * (getContext returns null) on every platform. Surfaces and image decoding
 * return empty results. */
#include "nativax_bridge.h"

NX_EXPORT void nx_gl_release_current(void) {}
NX_EXPORT int32_t nx_gl_available(void) { return 0; }
NX_EXPORT int64_t nx_surface_create(void) { return 0; }
NX_EXPORT void nx_surface_retain(int64_t id) { (void)id; }
NX_EXPORT void nx_surface_release(int64_t id) { (void)id; }
NX_EXPORT const uint8_t *nx_surface_acquire(int64_t id, int32_t *width, int32_t *height, int64_t *frame) {
  (void)id;
  *width = 0;
  *height = 0;
  *frame = 0;
  return 0;
}
NX_EXPORT int64_t nx_surface_frame(int64_t id) { (void)id; return 0; }
