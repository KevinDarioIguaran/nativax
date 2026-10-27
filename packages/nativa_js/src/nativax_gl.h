/*
 * NativaX WebGL: WebGL 1/2 implemented on OpenGL ES 3.0 through EGL, called
 * directly from script code (no Dart in the per-call path).
 *
 * Rendering goes to an offscreen framebuffer per context. When a frame is
 * presented, its pixels are copied to a "surface": a process-wide triple
 * buffer that the UI reads to display the canvas, from any thread, without
 * ever blocking the renderer.
 */
#ifndef NATIVAX_GL_H
#define NATIVAX_GL_H

#include <stdint.h>

#include "nativax_bridge.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Installs the internal `__nx_gl_native` object on ctx's global object (the
 * host prelude captures and removes it). */
void nx_gl_install(void *ctx);

/* Restores the GL context that was current on this thread before script code
 * made a WebGL context current. Called after every entry into script code,
 * because Dart isolates can move between OS threads between tasks. */
NX_EXPORT void nx_gl_release_current(void);

/* Whether GL is available in this process (EGL + GLES 3 loaded). */
NX_EXPORT int32_t nx_gl_available(void);

/* Surfaces (canvas backing stores shared with the UI). */
NX_EXPORT int64_t nx_surface_create(void);
NX_EXPORT void nx_surface_retain(int64_t id);
NX_EXPORT void nx_surface_release(int64_t id);

/* Latest complete frame of surface `id` as RGBA8 (top row first,
 * premultiplied alpha), valid until the next acquire. Returns NULL when the
 * surface has no frame yet. *frame increases with every presented frame. */
NX_EXPORT const uint8_t *nx_surface_acquire(int64_t id, int32_t *width,
                                            int32_t *height, int64_t *frame);

/* Frame counter of the newest presented frame (0: none). */
NX_EXPORT int64_t nx_surface_frame(int64_t id);

#ifdef __cplusplus
}
#endif

#endif /* NATIVAX_GL_H */
