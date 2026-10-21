/*
 * NativaX WebGL on OpenGL ES 3.0 / EGL. See nativax_gl.h.
 *
 * Threading: a WebGL context belongs to one script runtime, but that runtime
 * may run on different OS threads over time (Dart isolates migrate). Every
 * native call makes the context current on the calling thread if needed;
 * nx_gl_release_current() undoes it at the end of each script entry.
 */
#include "nativax_gl.h"

#include <math.h>
#include <stdio.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#if !defined(_WIN32)
#include <dlfcn.h>
#include <pthread.h>
#endif

#define GL_GLES_PROTOTYPES 0
#include <GLES3/gl3.h>
#define EGL_EGL_PROTOTYPES 0
#include <EGL/egl.h>
#include <EGL/eglext.h>

#define STBI_ONLY_JPEG
#define STBI_ONLY_PNG
#define STBI_ONLY_BMP
#define STBI_ONLY_GIF
#define STBI_NO_STDIO
#define STB_IMAGE_IMPLEMENTATION
#define STB_IMAGE_STATIC
#include "stb_image.h"

#include "nativax_gl_funcs.h"

/* --- dynamic loading ---------------------------------------------------------- */

typedef struct {
#define NX_DECL(name, type) type name;
  NX_GL_FUNCS(NX_DECL)
#undef NX_DECL
} NxGlApi;

static NxGlApi gl;

static struct {
  PFNEGLGETPROCADDRESSPROC GetProcAddress;
  PFNEGLGETDISPLAYPROC GetDisplay;
  PFNEGLINITIALIZEPROC Initialize;
  PFNEGLBINDAPIPROC BindAPI;
  PFNEGLCHOOSECONFIGPROC ChooseConfig;
  PFNEGLCREATECONTEXTPROC CreateContext;
  PFNEGLDESTROYCONTEXTPROC DestroyContext;
  PFNEGLMAKECURRENTPROC MakeCurrent;
  PFNEGLGETCURRENTCONTEXTPROC GetCurrentContext;
  PFNEGLGETCURRENTDISPLAYPROC GetCurrentDisplay;
  PFNEGLGETCURRENTSURFACEPROC GetCurrentSurface;
  PFNEGLQUERYSTRINGPROC QueryString;
  PFNEGLGETERRORPROC GetError;
  PFNEGLCREATEPBUFFERSURFACEPROC CreatePbufferSurface;
  PFNEGLGETPLATFORMDISPLAYEXTPROC GetPlatformDisplayEXT;
} egl;

static pthread_mutex_t nx_gl_lock = PTHREAD_MUTEX_INITIALIZER;
static int nx_gl_state = 0; /* 0 untried, 1 ok, -1 unavailable */
static EGLDisplay nx_dpy = EGL_NO_DISPLAY;
static EGLConfig nx_config;
static EGLSurface nx_pbuffer = EGL_NO_SURFACE; /* when surfaceless is missing */
static char nx_gl_error[256];

static void *nx_open(const char *const *names) {
  for (int i = 0; names[i]; i++) {
    void *h = dlopen(names[i], RTLD_NOW | RTLD_LOCAL);
    if (h) return h;
  }
  return NULL;
}

static int nx_gl_load(void) {
  static const char *const egl_names[] = {"libEGL.so.1", "libEGL.so", NULL};
  static const char *const gles_names[] = {"libGLESv2.so.2", "libGLESv2.so", NULL};
  void *libegl = nx_open(egl_names);
  void *libgles = nx_open(gles_names);
  if (!libegl || !libgles) {
    snprintf(nx_gl_error, sizeof nx_gl_error, "EGL/GLES libraries not found");
    return -1;
  }
#define NX_EGL(field, sym) egl.field = (void *)dlsym(libegl, sym)
  NX_EGL(GetProcAddress, "eglGetProcAddress");
  NX_EGL(GetDisplay, "eglGetDisplay");
  NX_EGL(Initialize, "eglInitialize");
  NX_EGL(BindAPI, "eglBindAPI");
  NX_EGL(ChooseConfig, "eglChooseConfig");
  NX_EGL(CreateContext, "eglCreateContext");
  NX_EGL(DestroyContext, "eglDestroyContext");
  NX_EGL(MakeCurrent, "eglMakeCurrent");
  NX_EGL(GetCurrentContext, "eglGetCurrentContext");
  NX_EGL(GetCurrentDisplay, "eglGetCurrentDisplay");
  NX_EGL(GetCurrentSurface, "eglGetCurrentSurface");
  NX_EGL(QueryString, "eglQueryString");
  NX_EGL(GetError, "eglGetError");
  NX_EGL(CreatePbufferSurface, "eglCreatePbufferSurface");
#undef NX_EGL
  if (!egl.GetProcAddress || !egl.GetDisplay || !egl.MakeCurrent || !egl.CreateContext) {
    snprintf(nx_gl_error, sizeof nx_gl_error, "incomplete EGL library");
    return -1;
  }
  egl.GetPlatformDisplayEXT =
      (PFNEGLGETPLATFORMDISPLAYEXTPROC)egl.GetProcAddress("eglGetPlatformDisplayEXT");
#define NX_LOAD(name, type)                                       \
  gl.name = (type)dlsym(libgles, "gl" #name);                     \
  if (!gl.name) gl.name = (type)egl.GetProcAddress("gl" #name);   \
  if (!gl.name) {                                                 \
    snprintf(nx_gl_error, sizeof nx_gl_error, "missing gl%s", #name); \
    return -1;                                                    \
  }
  NX_GL_FUNCS(NX_LOAD)
#undef NX_LOAD
  return 0;
}

static int nx_gl_init_locked(void) {
  if (nx_gl_state != 0) return nx_gl_state;
  nx_gl_state = -1;
  if (nx_gl_load() < 0) return -1;
  /* A surfaceless display needs no window system (works in tests and in
   * headless processes); fall back to the default display. */
  const char *client = egl.QueryString(EGL_NO_DISPLAY, EGL_EXTENSIONS);
  if (client && strstr(client, "EGL_MESA_platform_surfaceless") && egl.GetPlatformDisplayEXT) {
    nx_dpy = egl.GetPlatformDisplayEXT(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, NULL);
  }
  if (nx_dpy == EGL_NO_DISPLAY) nx_dpy = egl.GetDisplay(EGL_DEFAULT_DISPLAY);
  if (nx_dpy == EGL_NO_DISPLAY || !egl.Initialize(nx_dpy, NULL, NULL)) {
    snprintf(nx_gl_error, sizeof nx_gl_error, "eglInitialize failed (0x%x)", egl.GetError());
    return -1;
  }
  egl.BindAPI(EGL_OPENGL_ES_API);
  const EGLint attrs[] = {EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT, EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
                          EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
                          EGL_NONE};
  EGLint n = 0;
  if (!egl.ChooseConfig(nx_dpy, attrs, &nx_config, 1, &n) || n < 1) {
    const EGLint any[] = {EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT, EGL_NONE};
    if (!egl.ChooseConfig(nx_dpy, any, &nx_config, 1, &n) || n < 1) {
      snprintf(nx_gl_error, sizeof nx_gl_error, "no OpenGL ES 3 EGL config");
      return -1;
    }
  }
  const char *ext = egl.QueryString(nx_dpy, EGL_EXTENSIONS);
  if (!ext || !strstr(ext, "EGL_KHR_surfaceless_context")) {
    const EGLint pb[] = {EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE};
    nx_pbuffer = egl.CreatePbufferSurface(nx_dpy, nx_config, pb);
  }
  nx_gl_state = 1;
  return 1;
}

static int nx_gl_init(void) {
  pthread_mutex_lock(&nx_gl_lock);
  int r = nx_gl_init_locked();
  pthread_mutex_unlock(&nx_gl_lock);
  return r;
}

int32_t nx_gl_available(void) { return nx_gl_init() == 1 ? 1 : 0; }

/* --- surfaces ----------------------------------------------------------------- */

typedef struct NxSurface {
  int64_t id;
  int refs;
  pthread_mutex_t lock;
  uint8_t *buf[3];
  int32_t w[3], h[3];
  size_t cap[3];
  int back, ready, front;
  bool fresh; /* ready holds a frame newer than front */
  int64_t frame;
  struct NxSurface *next;
} NxSurface;

static NxSurface *nx_surfaces = NULL;
static int64_t nx_next_surface = 1;

static NxSurface *nx_surface_find_locked(int64_t id) {
  for (NxSurface *s = nx_surfaces; s; s = s->next)
    if (s->id == id) return s;
  return NULL;
}

int64_t nx_surface_create(void) {
  NxSurface *s = (NxSurface *)calloc(1, sizeof(NxSurface));
  if (!s) return 0;
  pthread_mutex_init(&s->lock, NULL);
  s->refs = 1;
  s->back = 0;
  s->ready = 1;
  s->front = 2;
  pthread_mutex_lock(&nx_gl_lock);
  s->id = nx_next_surface++;
  s->next = nx_surfaces;
  nx_surfaces = s;
  pthread_mutex_unlock(&nx_gl_lock);
  return s->id;
}

void nx_surface_retain(int64_t id) {
  pthread_mutex_lock(&nx_gl_lock);
  NxSurface *s = nx_surface_find_locked(id);
  if (s) s->refs++;
  pthread_mutex_unlock(&nx_gl_lock);
}

void nx_surface_release(int64_t id) {
  NxSurface *dead = NULL;
  pthread_mutex_lock(&nx_gl_lock);
  for (NxSurface **pp = &nx_surfaces; *pp; pp = &(*pp)->next) {
    if ((*pp)->id == id) {
      if (--(*pp)->refs == 0) {
        dead = *pp;
        *pp = dead->next;
      }
      break;
    }
  }
  pthread_mutex_unlock(&nx_gl_lock);
  if (dead) {
    for (int i = 0; i < 3; i++) free(dead->buf[i]);
    pthread_mutex_destroy(&dead->lock);
    free(dead);
  }
}

static NxSurface *nx_surface_get(int64_t id) {
  pthread_mutex_lock(&nx_gl_lock);
  NxSurface *s = nx_surface_find_locked(id);
  pthread_mutex_unlock(&nx_gl_lock);
  return s;
}

/* Copies a bottom-up GL readback into the surface's back buffer (flipping it
 * to top-down) and publishes it. */
static void nx_surface_publish(int64_t id, const uint8_t *pixels, int32_t w, int32_t h,
                               bool opaque) {
  NxSurface *s = nx_surface_get(id);
  if (!s || w <= 0 || h <= 0) return;
  size_t row = (size_t)w * 4, need = row * (size_t)h;
  int b = s->back; /* only the producer touches back */
  if (s->cap[b] < need) {
    free(s->buf[b]);
    s->buf[b] = (uint8_t *)malloc(need);
    s->cap[b] = s->buf[b] ? need : 0;
    if (!s->buf[b]) return;
  }
  for (int32_t y = 0; y < h; y++) {
    memcpy(s->buf[b] + (size_t)y * row, pixels + (size_t)(h - 1 - y) * row, row);
  }
  if (opaque) {
    for (size_t i = 3; i < need; i += 4) s->buf[b][i] = 255;
  }
  s->w[b] = w;
  s->h[b] = h;
  pthread_mutex_lock(&s->lock);
  int t = s->ready;
  s->ready = s->back;
  s->back = t;
  s->fresh = true;
  s->frame++;
  pthread_mutex_unlock(&s->lock);
}

const uint8_t *nx_surface_acquire(int64_t id, int32_t *width, int32_t *height,
                                  int64_t *frame) {
  NxSurface *s = nx_surface_get(id);
  *width = 0;
  *height = 0;
  *frame = 0;
  if (!s) return NULL;
  pthread_mutex_lock(&s->lock);
  if (s->fresh) {
    int t = s->front;
    s->front = s->ready;
    s->ready = t;
    s->fresh = false;
  }
  const uint8_t *p = s->buf[s->front];
  *width = s->w[s->front];
  *height = s->h[s->front];
  *frame = s->frame;
  pthread_mutex_unlock(&s->lock);
  return *width > 0 ? p : NULL;
}

int64_t nx_surface_frame(int64_t id) {
  NxSurface *s = nx_surface_get(id);
  if (!s) return 0;
  pthread_mutex_lock(&s->lock);
  int64_t f = s->frame;
  pthread_mutex_unlock(&s->lock);
  return f;
}

/* --- image bitmaps (decoded RGBA8, process-wide, transferable) --------------- */

typedef struct NxBitmap {
  int64_t id;
  int32_t w, h;
  uint8_t *rgba; /* top row first */
  struct NxBitmap *next;
} NxBitmap;

static NxBitmap *nx_bitmaps = NULL;
static int64_t nx_next_bitmap = 1;

static int64_t nx_bitmap_add(uint8_t *rgba, int32_t w, int32_t h) {
  NxBitmap *b = (NxBitmap *)calloc(1, sizeof(NxBitmap));
  if (!b) {
    free(rgba);
    return 0;
  }
  b->rgba = rgba;
  b->w = w;
  b->h = h;
  pthread_mutex_lock(&nx_gl_lock);
  b->id = nx_next_bitmap++;
  b->next = nx_bitmaps;
  nx_bitmaps = b;
  pthread_mutex_unlock(&nx_gl_lock);
  return b->id;
}

static NxBitmap *nx_bitmap_get(int64_t id) {
  pthread_mutex_lock(&nx_gl_lock);
  NxBitmap *b = nx_bitmaps;
  while (b && b->id != id) b = b->next;
  pthread_mutex_unlock(&nx_gl_lock);
  return b;
}

static void nx_bitmap_free(int64_t id) {
  NxBitmap *dead = NULL;
  pthread_mutex_lock(&nx_gl_lock);
  for (NxBitmap **pp = &nx_bitmaps; *pp; pp = &(*pp)->next) {
    if ((*pp)->id == id) {
      dead = *pp;
      *pp = dead->next;
      break;
    }
  }
  pthread_mutex_unlock(&nx_gl_lock);
  if (dead) {
    free(dead->rgba);
    free(dead);
  }
}

static void nx_flip_rows(uint8_t *p, size_t row, int32_t h) {
  uint8_t *tmp = (uint8_t *)malloc(row);
  if (!tmp) return;
  for (int32_t y = 0; y < h / 2; y++) {
    uint8_t *a = p + (size_t)y * row, *b = p + (size_t)(h - 1 - y) * row;
    memcpy(tmp, a, row);
    memcpy(a, b, row);
    memcpy(b, tmp, row);
  }
  free(tmp);
}

static void nx_premultiply(uint8_t *p, size_t n) {
  for (size_t i = 0; i < n; i += 4) {
    unsigned a = p[i + 3];
    if (a == 255) continue;
    p[i] = (uint8_t)((p[i] * a + 127) / 255);
    p[i + 1] = (uint8_t)((p[i + 1] * a + 127) / 255);
    p[i + 2] = (uint8_t)((p[i + 2] * a + 127) / 255);
  }
}

/* --- contexts ------------------------------------------------------------------ */

typedef struct NxGl {
  EGLContext egl;
  int version; /* 1 or 2 */
  int64_t surface;
  int32_t w, h;
  bool alpha, depth, stencil, antialias, premultiplied, preserve;
  int samples;
  GLuint fbo, color_rb, depth_rb;     /* default framebuffer (maybe MSAA) */
  GLuint resolve_fbo, resolve_rb;     /* single-sampled copy for readback */
  bool dirty, lost;
  bool flip_y, premultiply; /* WebGL UNPACK_* state (not GL state) */
  GLuint user_draw_fbo, user_read_fbo; /* 0 = default */
  uint8_t *readback;
  size_t readback_cap;
} NxGl;

#define NX_MAX_CONTEXTS 64
static NxGl *nx_contexts[NX_MAX_CONTEXTS + 1];

/* Per-thread: the context that was current before we switched. */
static __thread EGLDisplay nx_prev_dpy = EGL_NO_DISPLAY;
static __thread EGLContext nx_prev_ctx = EGL_NO_CONTEXT;
static __thread EGLSurface nx_prev_draw = EGL_NO_SURFACE, nx_prev_read = EGL_NO_SURFACE;
static __thread bool nx_switched = false;
static __thread EGLContext nx_current = EGL_NO_CONTEXT;

static bool nx_make_current(NxGl *g) {
  if (nx_current == g->egl && egl.GetCurrentContext() == g->egl) return true;
  if (!nx_switched) {
    nx_prev_ctx = egl.GetCurrentContext();
    nx_prev_dpy = egl.GetCurrentDisplay();
    nx_prev_draw = egl.GetCurrentSurface(EGL_DRAW);
    nx_prev_read = egl.GetCurrentSurface(EGL_READ);
    nx_switched = true;
  }
  if (!egl.MakeCurrent(nx_dpy, nx_pbuffer, nx_pbuffer, g->egl)) return false;
  nx_current = g->egl;
  return true;
}

void nx_gl_release_current(void) {
  if (!nx_switched) return;
  nx_switched = false;
  nx_current = EGL_NO_CONTEXT;
  if (nx_prev_ctx != EGL_NO_CONTEXT && nx_prev_dpy != EGL_NO_DISPLAY) {
    egl.MakeCurrent(nx_prev_dpy, nx_prev_draw, nx_prev_read, nx_prev_ctx);
  } else {
    egl.MakeCurrent(nx_dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
  }
  nx_prev_ctx = EGL_NO_CONTEXT;
  nx_prev_dpy = EGL_NO_DISPLAY;
}

static void nx_free_framebuffer(NxGl *g) {
  if (g->fbo) gl.DeleteFramebuffers(1, &g->fbo);
  if (g->resolve_fbo) gl.DeleteFramebuffers(1, &g->resolve_fbo);
  GLuint rbs[3] = {g->color_rb, g->depth_rb, g->resolve_rb};
  gl.DeleteRenderbuffers(3, rbs);
  g->fbo = g->resolve_fbo = g->color_rb = g->depth_rb = g->resolve_rb = 0;
}

/* (Re)creates the default framebuffer at w×h, keeping user bindings. */
static void nx_alloc_framebuffer(NxGl *g, int32_t w, int32_t h) {
  if (w < 1) w = 1;
  if (h < 1) h = 1;
  nx_free_framebuffer(g);
  g->w = w;
  g->h = h;
  GLint prev_rb = 0;
  gl.GetIntegerv(GL_RENDERBUFFER_BINDING, &prev_rb);
  gl.GenFramebuffers(1, &g->fbo);
  gl.BindFramebuffer(GL_FRAMEBUFFER, g->fbo);
  gl.GenRenderbuffers(1, &g->color_rb);
  gl.BindRenderbuffer(GL_RENDERBUFFER, g->color_rb);
  if (g->samples > 1) {
    gl.RenderbufferStorageMultisample(GL_RENDERBUFFER, g->samples, GL_RGBA8, w, h);
  } else {
    gl.RenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, w, h);
  }
  gl.FramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, g->color_rb);
  if (g->depth || g->stencil) {
    gl.GenRenderbuffers(1, &g->depth_rb);
    gl.BindRenderbuffer(GL_RENDERBUFFER, g->depth_rb);
    GLenum fmt = g->stencil ? GL_DEPTH24_STENCIL8 : GL_DEPTH_COMPONENT24;
    if (g->samples > 1) {
      gl.RenderbufferStorageMultisample(GL_RENDERBUFFER, g->samples, fmt, w, h);
    } else {
      gl.RenderbufferStorage(GL_RENDERBUFFER, fmt, w, h);
    }
    GLenum att = g->stencil ? GL_DEPTH_STENCIL_ATTACHMENT : GL_DEPTH_ATTACHMENT;
    gl.FramebufferRenderbuffer(GL_FRAMEBUFFER, att, GL_RENDERBUFFER, g->depth_rb);
  }
  if (g->samples > 1) {
    gl.GenFramebuffers(1, &g->resolve_fbo);
    gl.BindFramebuffer(GL_FRAMEBUFFER, g->resolve_fbo);
    gl.GenRenderbuffers(1, &g->resolve_rb);
    gl.BindRenderbuffer(GL_RENDERBUFFER, g->resolve_rb);
    gl.RenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, w, h);
    gl.FramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, g->resolve_rb);
  }
  /* A fresh drawing buffer is cleared to transparent black (WebGL §2.2). */
  gl.BindFramebuffer(GL_FRAMEBUFFER, g->fbo);
  GLfloat cc[4];
  gl.GetFloatv(GL_COLOR_CLEAR_VALUE, cc);
  GLboolean mask[4];
  gl.GetBooleanv(GL_COLOR_WRITEMASK, mask);
  GLboolean scissor = gl.IsEnabled(GL_SCISSOR_TEST);
  gl.Disable(GL_SCISSOR_TEST);
  gl.ColorMask(1, 1, 1, 1);
  gl.ClearColor(0, 0, 0, 0);
  gl.ClearDepthf(1);
  gl.ClearStencil(0);
  gl.Clear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
  gl.ClearColor(cc[0], cc[1], cc[2], cc[3]);
  gl.ColorMask(mask[0], mask[1], mask[2], mask[3]);
  if (scissor) gl.Enable(GL_SCISSOR_TEST);
  gl.BindRenderbuffer(GL_RENDERBUFFER, (GLuint)prev_rb);
  gl.BindFramebuffer(GL_DRAW_FRAMEBUFFER, g->user_draw_fbo ? g->user_draw_fbo : g->fbo);
  gl.BindFramebuffer(GL_READ_FRAMEBUFFER, g->user_read_fbo ? g->user_read_fbo : g->fbo);
}

/* Copies the drawing buffer to the canvas surface. */
static void nx_present(NxGl *g) {
  if (!g->dirty || g->lost || !g->surface) return;
  g->dirty = false;
  size_t need = (size_t)g->w * (size_t)g->h * 4;
  if (g->readback_cap < need) {
    free(g->readback);
    g->readback = (uint8_t *)malloc(need);
    g->readback_cap = g->readback ? need : 0;
    if (!g->readback) return;
  }
  GLint pack_align = 4, pack_buffer = 0;
  gl.GetIntegerv(GL_PACK_ALIGNMENT, &pack_align);
  gl.GetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &pack_buffer);
  GLboolean scissor = gl.IsEnabled(GL_SCISSOR_TEST);
  gl.Disable(GL_SCISSOR_TEST);
  GLuint src = g->fbo;
  if (g->resolve_fbo) {
    gl.BindFramebuffer(GL_READ_FRAMEBUFFER, g->fbo);
    gl.BindFramebuffer(GL_DRAW_FRAMEBUFFER, g->resolve_fbo);
    gl.BlitFramebuffer(0, 0, g->w, g->h, 0, 0, g->w, g->h, GL_COLOR_BUFFER_BIT, GL_NEAREST);
    src = g->resolve_fbo;
  }
  gl.BindFramebuffer(GL_READ_FRAMEBUFFER, src);
  gl.BindBuffer(GL_PIXEL_PACK_BUFFER, 0);
  gl.PixelStorei(GL_PACK_ALIGNMENT, 1);
  gl.ReadPixels(0, 0, g->w, g->h, GL_RGBA, GL_UNSIGNED_BYTE, g->readback);
  gl.PixelStorei(GL_PACK_ALIGNMENT, pack_align);
  gl.BindBuffer(GL_PIXEL_PACK_BUFFER, (GLuint)pack_buffer);
  if (scissor) gl.Enable(GL_SCISSOR_TEST);
  gl.BindFramebuffer(GL_DRAW_FRAMEBUFFER, g->user_draw_fbo ? g->user_draw_fbo : g->fbo);
  gl.BindFramebuffer(GL_READ_FRAMEBUFFER, g->user_read_fbo ? g->user_read_fbo : g->fbo);
  /* Unpremultiplied contexts store straight alpha; the surface is
   * premultiplied (what the UI composites). */
  if (g->alpha && !g->premultiplied) nx_premultiply(g->readback, need);
  nx_surface_publish(g->surface, g->readback, g->w, g->h, !g->alpha);
  if (!g->preserve) {
    /* The drawing buffer is cleared after compositing (WebGL §2.2). */
    GLfloat cc[4];
    gl.GetFloatv(GL_COLOR_CLEAR_VALUE, cc);
    GLboolean mask[4];
    gl.GetBooleanv(GL_COLOR_WRITEMASK, mask);
    GLboolean dmask = 1;
    gl.GetBooleanv(GL_DEPTH_WRITEMASK, &dmask);
    gl.BindFramebuffer(GL_DRAW_FRAMEBUFFER, g->fbo);
    if (scissor) gl.Disable(GL_SCISSOR_TEST);
    gl.ColorMask(1, 1, 1, 1);
    gl.DepthMask(1);
    gl.ClearColor(0, 0, 0, 0);
    gl.Clear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
    gl.ClearColor(cc[0], cc[1], cc[2], cc[3]);
    gl.ColorMask(mask[0], mask[1], mask[2], mask[3]);
    gl.DepthMask(dmask);
    if (scissor) gl.Enable(GL_SCISSOR_TEST);
    gl.BindFramebuffer(GL_DRAW_FRAMEBUFFER, g->user_draw_fbo ? g->user_draw_fbo : g->fbo);
  }
}

/* --- script bindings ------------------------------------------------------------ */

static NxGl *nx_ctx_arg(JSContext *ctx, JSValueConst v) {
  int32_t h = 0;
  if (JS_ToInt32(ctx, &h, v) < 0 || h < 1 || h > NX_MAX_CONTEXTS || !nx_contexts[h]) {
    JS_ThrowTypeError(ctx, "invalid WebGL context");
    return NULL;
  }
  NxGl *g = nx_contexts[h];
  if (!nx_make_current(g)) {
    JS_ThrowInternalError(ctx, "could not make the WebGL context current (0x%x)", egl.GetError());
    return NULL;
  }
  return g;
}

static inline int32_t I(JSContext *ctx, JSValueConst v) {
  int32_t x = 0;
  JS_ToInt32(ctx, &x, v);
  return x;
}
static inline uint32_t U(JSContext *ctx, JSValueConst v) {
  int64_t x = 0;
  JS_ToInt64(ctx, &x, v);
  return (uint32_t)x;
}
static inline int64_t L(JSContext *ctx, JSValueConst v) {
  int64_t x = 0;
  JS_ToInt64(ctx, &x, v);
  return x;
}
static inline float F(JSContext *ctx, JSValueConst v) {
  double x = 0;
  JS_ToFloat64(ctx, &x, v);
  return (float)x;
}
static inline GLboolean B(JSContext *ctx, JSValueConst v) { return JS_ToBool(ctx, v) ? GL_TRUE : GL_FALSE; }

/* Pointer and byte length of an ArrayBuffer, SharedArrayBuffer or view. */
static uint8_t *nx_bytes(JSContext *ctx, JSValueConst v, size_t *len, size_t *elem) {
  size_t size = 0;
  *elem = 1;
  uint8_t *p = JS_GetArrayBuffer(ctx, &size, v);
  if (p) {
    *len = size;
    return p;
  }
  JS_FreeValue(ctx, JS_GetException(ctx));
  size_t offset = 0, bytes = 0, per = 0;
  JSValue ab = JS_GetTypedArrayBuffer(ctx, v, &offset, &bytes, &per);
  if (JS_IsException(ab)) {
    JS_FreeValue(ctx, JS_GetException(ctx));
    /* DataView */
    JSValue buf = JS_GetPropertyStr(ctx, v, "buffer");
    JSValue off = JS_GetPropertyStr(ctx, v, "byteOffset");
    JSValue blen = JS_GetPropertyStr(ctx, v, "byteLength");
    p = JS_GetArrayBuffer(ctx, &size, buf);
    int64_t o = 0, l = 0;
    JS_ToInt64(ctx, &o, off);
    JS_ToInt64(ctx, &l, blen);
    JS_FreeValue(ctx, buf);
    JS_FreeValue(ctx, off);
    JS_FreeValue(ctx, blen);
    if (!p) {
      JS_FreeValue(ctx, JS_GetException(ctx));
      *len = 0;
      return NULL;
    }
    *len = (size_t)l;
    return p + o;
  }
  p = JS_GetArrayBuffer(ctx, &size, ab);
  JS_FreeValue(ctx, ab);
  if (!p) return NULL;
  *len = bytes;
  *elem = per ? per : 1;
  return p + offset;
}

#define GLFN(name) \
  static JSValue js_##name(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv)
#define ENTER()                       \
  (void)this_val;                     \
  (void)argc;                         \
  NxGl *g = nx_ctx_arg(ctx, argv[0]); \
  if (!g) return JS_EXCEPTION;        \
  (void)g;
#define A(i) argv[(i) + 1]
#define DRAWN() g->dirty = true

/* Context management ----------------------------------------------------------- */

/* createContext(surfaceId, version, alpha, depth, stencil, antialias,
 * premultipliedAlpha, preserveDrawingBuffer, width, height) -> handle | 0 */
static JSValue js_createContext(JSContext *ctx, JSValueConst this_val, int argc,
                                JSValueConst *argv) {
  (void)this_val;
  if (argc < 10) return JS_ThrowTypeError(ctx, "createContext: 10 arguments");
  if (nx_gl_init() != 1) return JS_NewInt32(ctx, 0);
  int slot = 0;
  pthread_mutex_lock(&nx_gl_lock);
  for (int i = 1; i <= NX_MAX_CONTEXTS; i++) {
    if (!nx_contexts[i]) {
      slot = i;
      nx_contexts[i] = (NxGl *)calloc(1, sizeof(NxGl));
      break;
    }
  }
  pthread_mutex_unlock(&nx_gl_lock);
  if (!slot || !nx_contexts[slot]) return JS_NewInt32(ctx, 0);
  NxGl *g = nx_contexts[slot];
  g->surface = L(ctx, argv[0]);
  g->version = I(ctx, argv[1]);
  g->alpha = JS_ToBool(ctx, argv[2]);
  g->depth = JS_ToBool(ctx, argv[3]);
  g->stencil = JS_ToBool(ctx, argv[4]);
  g->antialias = JS_ToBool(ctx, argv[5]);
  g->premultiplied = JS_ToBool(ctx, argv[6]);
  g->preserve = JS_ToBool(ctx, argv[7]);
  const EGLint attrs[] = {EGL_CONTEXT_MAJOR_VERSION, 3, EGL_CONTEXT_MINOR_VERSION, 0, EGL_NONE};
  g->egl = egl.CreateContext(nx_dpy, nx_config, EGL_NO_CONTEXT, attrs);
  if (g->egl == EGL_NO_CONTEXT || !nx_make_current(g)) {
    if (g->egl != EGL_NO_CONTEXT) egl.DestroyContext(nx_dpy, g->egl);
    free(g);
    nx_contexts[slot] = NULL;
    return JS_NewInt32(ctx, 0);
  }
  if (g->surface) nx_surface_retain(g->surface);
  if (g->antialias) {
    GLint max = 0;
    gl.GetIntegerv(GL_MAX_SAMPLES, &max);
    g->samples = max >= 4 ? 4 : (max > 1 ? max : 0);
  }
  /* WebGL defaults that differ from GLES. */
  gl.PixelStorei(GL_PACK_ALIGNMENT, 4);
  gl.PixelStorei(GL_UNPACK_ALIGNMENT, 4);
  nx_alloc_framebuffer(g, I(ctx, argv[8]), I(ctx, argv[9]));
  gl.Viewport(0, 0, g->w, g->h);
  gl.Scissor(0, 0, g->w, g->h);
  return JS_NewInt32(ctx, slot);
}

GLFN(destroyContext) {
  (void)this_val;
  (void)argc;
  int32_t h = I(ctx, argv[0]);
  if (h < 1 || h > NX_MAX_CONTEXTS || !nx_contexts[h]) return JS_UNDEFINED;
  NxGl *g = nx_contexts[h];
  if (nx_make_current(g)) nx_free_framebuffer(g);
  nx_gl_release_current();
  egl.DestroyContext(nx_dpy, g->egl);
  if (g->surface) nx_surface_release(g->surface);
  free(g->readback);
  pthread_mutex_lock(&nx_gl_lock);
  nx_contexts[h] = NULL;
  pthread_mutex_unlock(&nx_gl_lock);
  free(g);
  return JS_UNDEFINED;
}

GLFN(resize) {
  ENTER();
  int32_t w = I(ctx, A(0)), h = I(ctx, A(1));
  if (w != g->w || h != g->h) nx_alloc_framebuffer(g, w, h);
  return JS_UNDEFINED;
}

GLFN(present) {
  ENTER();
  nx_present(g);
  return JS_UNDEFINED;
}

GLFN(setLost) {
  ENTER();
  g->lost = JS_ToBool(ctx, A(0));
  return JS_UNDEFINED;
}

GLFN(error) {
  (void)this_val;
  (void)argc;
  (void)argv;
  nx_gl_init();
  return JS_NewString(ctx, nx_gl_error);
}

/* Framebuffer bindings map `null` to the context's default framebuffer. */
GLFN(bindFramebuffer) {
  ENTER();
  GLenum target = U(ctx, A(0));
  GLuint fb = U(ctx, A(1));
  if (target == GL_FRAMEBUFFER || target == GL_DRAW_FRAMEBUFFER) g->user_draw_fbo = fb;
  if (target == GL_FRAMEBUFFER || target == GL_READ_FRAMEBUFFER) g->user_read_fbo = fb;
  gl.BindFramebuffer(target, fb ? fb : g->fbo);
  return JS_UNDEFINED;
}

/* Simple calls ------------------------------------------------------------------- */

#define V0(js, call) GLFN(js) { ENTER(); call; return JS_UNDEFINED; }
#define D0(js, call) GLFN(js) { ENTER(); call; DRAWN(); return JS_UNDEFINED; }

V0(activeTexture, gl.ActiveTexture(U(ctx, A(0))))
V0(attachShader, gl.AttachShader(U(ctx, A(0)), U(ctx, A(1))))
V0(beginQuery, gl.BeginQuery(U(ctx, A(0)), U(ctx, A(1))))
V0(beginTransformFeedback, gl.BeginTransformFeedback(U(ctx, A(0))))
V0(bindBuffer, gl.BindBuffer(U(ctx, A(0)), U(ctx, A(1))))
V0(bindBufferBase, gl.BindBufferBase(U(ctx, A(0)), U(ctx, A(1)), U(ctx, A(2))))
V0(bindBufferRange, gl.BindBufferRange(U(ctx, A(0)), U(ctx, A(1)), U(ctx, A(2)), (GLintptr)L(ctx, A(3)), (GLsizeiptr)L(ctx, A(4))))
V0(bindRenderbuffer, gl.BindRenderbuffer(U(ctx, A(0)), U(ctx, A(1))))
V0(bindSampler, gl.BindSampler(U(ctx, A(0)), U(ctx, A(1))))
V0(bindTexture, gl.BindTexture(U(ctx, A(0)), U(ctx, A(1))))
V0(bindTransformFeedback, gl.BindTransformFeedback(U(ctx, A(0)), U(ctx, A(1))))
V0(bindVertexArray, gl.BindVertexArray(U(ctx, A(0))))
V0(blendColor, gl.BlendColor(F(ctx, A(0)), F(ctx, A(1)), F(ctx, A(2)), F(ctx, A(3))))
V0(blendEquation, gl.BlendEquation(U(ctx, A(0))))
V0(blendEquationSeparate, gl.BlendEquationSeparate(U(ctx, A(0)), U(ctx, A(1))))
V0(blendFunc, gl.BlendFunc(U(ctx, A(0)), U(ctx, A(1))))
V0(blendFuncSeparate, gl.BlendFuncSeparate(U(ctx, A(0)), U(ctx, A(1)), U(ctx, A(2)), U(ctx, A(3))))
D0(blitFramebuffer, gl.BlitFramebuffer(I(ctx, A(0)), I(ctx, A(1)), I(ctx, A(2)), I(ctx, A(3)), I(ctx, A(4)), I(ctx, A(5)), I(ctx, A(6)), I(ctx, A(7)), U(ctx, A(8)), U(ctx, A(9))))
D0(clear, gl.Clear(U(ctx, A(0))))
D0(clearBufferfi, gl.ClearBufferfi(U(ctx, A(0)), I(ctx, A(1)), F(ctx, A(2)), I(ctx, A(3))))
V0(clearColor, gl.ClearColor(F(ctx, A(0)), F(ctx, A(1)), F(ctx, A(2)), F(ctx, A(3))))
V0(clearDepth, gl.ClearDepthf(F(ctx, A(0))))
V0(clearStencil, gl.ClearStencil(I(ctx, A(0))))
V0(colorMask, gl.ColorMask(B(ctx, A(0)), B(ctx, A(1)), B(ctx, A(2)), B(ctx, A(3))))
V0(compileShader, gl.CompileShader(U(ctx, A(0))))
V0(copyBufferSubData, gl.CopyBufferSubData(U(ctx, A(0)), U(ctx, A(1)), (GLintptr)L(ctx, A(2)), (GLintptr)L(ctx, A(3)), (GLsizeiptr)L(ctx, A(4))))
V0(copyTexImage2D, gl.CopyTexImage2D(U(ctx, A(0)), I(ctx, A(1)), U(ctx, A(2)), I(ctx, A(3)), I(ctx, A(4)), I(ctx, A(5)), I(ctx, A(6)), I(ctx, A(7))))
V0(copyTexSubImage2D, gl.CopyTexSubImage2D(U(ctx, A(0)), I(ctx, A(1)), I(ctx, A(2)), I(ctx, A(3)), I(ctx, A(4)), I(ctx, A(5)), I(ctx, A(6)), I(ctx, A(7))))
V0(copyTexSubImage3D, gl.CopyTexSubImage3D(U(ctx, A(0)), I(ctx, A(1)), I(ctx, A(2)), I(ctx, A(3)), I(ctx, A(4)), I(ctx, A(5)), I(ctx, A(6)), I(ctx, A(7)), I(ctx, A(8))))
V0(cullFace, gl.CullFace(U(ctx, A(0))))
V0(depthFunc, gl.DepthFunc(U(ctx, A(0))))
V0(depthMask, gl.DepthMask(B(ctx, A(0))))
V0(depthRange, gl.DepthRangef(F(ctx, A(0)), F(ctx, A(1))))
V0(detachShader, gl.DetachShader(U(ctx, A(0)), U(ctx, A(1))))
V0(disable, gl.Disable(U(ctx, A(0))))
V0(disableVertexAttribArray, gl.DisableVertexAttribArray(U(ctx, A(0))))
D0(drawArrays, gl.DrawArrays(U(ctx, A(0)), I(ctx, A(1)), I(ctx, A(2))))
D0(drawArraysInstanced, gl.DrawArraysInstanced(U(ctx, A(0)), I(ctx, A(1)), I(ctx, A(2)), I(ctx, A(3))))
D0(drawElements, gl.DrawElements(U(ctx, A(0)), I(ctx, A(1)), U(ctx, A(2)), (const void *)(intptr_t)L(ctx, A(3))))
D0(drawElementsInstanced, gl.DrawElementsInstanced(U(ctx, A(0)), I(ctx, A(1)), U(ctx, A(2)), (const void *)(intptr_t)L(ctx, A(3)), I(ctx, A(4))))
D0(drawRangeElements, gl.DrawRangeElements(U(ctx, A(0)), U(ctx, A(1)), U(ctx, A(2)), I(ctx, A(3)), U(ctx, A(4)), (const void *)(intptr_t)L(ctx, A(5))))
V0(enable, gl.Enable(U(ctx, A(0))))
V0(enableVertexAttribArray, gl.EnableVertexAttribArray(U(ctx, A(0))))
V0(endQuery, gl.EndQuery(U(ctx, A(0))))
V0(endTransformFeedback, gl.EndTransformFeedback())
V0(finish, gl.Finish())
V0(flush, gl.Flush())
V0(framebufferRenderbuffer, gl.FramebufferRenderbuffer(U(ctx, A(0)), U(ctx, A(1)), U(ctx, A(2)), U(ctx, A(3))))
V0(framebufferTexture2D, gl.FramebufferTexture2D(U(ctx, A(0)), U(ctx, A(1)), U(ctx, A(2)), U(ctx, A(3)), I(ctx, A(4))))
V0(framebufferTextureLayer, gl.FramebufferTextureLayer(U(ctx, A(0)), U(ctx, A(1)), U(ctx, A(2)), I(ctx, A(3)), I(ctx, A(4))))
V0(frontFace, gl.FrontFace(U(ctx, A(0))))
V0(generateMipmap, gl.GenerateMipmap(U(ctx, A(0))))
V0(hint, gl.Hint(U(ctx, A(0)), U(ctx, A(1))))
V0(lineWidth, gl.LineWidth(F(ctx, A(0))))
V0(linkProgram, gl.LinkProgram(U(ctx, A(0))))
V0(pauseTransformFeedback, gl.PauseTransformFeedback())
V0(polygonOffset, gl.PolygonOffset(F(ctx, A(0)), F(ctx, A(1))))
V0(readBuffer, gl.ReadBuffer(U(ctx, A(0))))
V0(renderbufferStorage, gl.RenderbufferStorage(U(ctx, A(0)), U(ctx, A(1)), I(ctx, A(2)), I(ctx, A(3))))
V0(renderbufferStorageMultisample, gl.RenderbufferStorageMultisample(U(ctx, A(0)), I(ctx, A(1)), U(ctx, A(2)), I(ctx, A(3)), I(ctx, A(4))))
V0(resumeTransformFeedback, gl.ResumeTransformFeedback())
V0(sampleCoverage, gl.SampleCoverage(F(ctx, A(0)), B(ctx, A(1))))
V0(samplerParameterf, gl.SamplerParameterf(U(ctx, A(0)), U(ctx, A(1)), F(ctx, A(2))))
V0(samplerParameteri, gl.SamplerParameteri(U(ctx, A(0)), U(ctx, A(1)), I(ctx, A(2))))
V0(scissor, gl.Scissor(I(ctx, A(0)), I(ctx, A(1)), I(ctx, A(2)), I(ctx, A(3))))
V0(stencilFunc, gl.StencilFunc(U(ctx, A(0)), I(ctx, A(1)), U(ctx, A(2))))
V0(stencilFuncSeparate, gl.StencilFuncSeparate(U(ctx, A(0)), U(ctx, A(1)), I(ctx, A(2)), U(ctx, A(3))))
V0(stencilMask, gl.StencilMask(U(ctx, A(0))))
V0(stencilMaskSeparate, gl.StencilMaskSeparate(U(ctx, A(0)), U(ctx, A(1))))
V0(stencilOp, gl.StencilOp(U(ctx, A(0)), U(ctx, A(1)), U(ctx, A(2))))
V0(stencilOpSeparate, gl.StencilOpSeparate(U(ctx, A(0)), U(ctx, A(1)), U(ctx, A(2)), U(ctx, A(3))))
V0(texParameterf, gl.TexParameterf(U(ctx, A(0)), U(ctx, A(1)), F(ctx, A(2))))
V0(texParameteri, gl.TexParameteri(U(ctx, A(0)), U(ctx, A(1)), I(ctx, A(2))))
V0(texStorage2D, gl.TexStorage2D(U(ctx, A(0)), I(ctx, A(1)), U(ctx, A(2)), I(ctx, A(3)), I(ctx, A(4))))
V0(texStorage3D, gl.TexStorage3D(U(ctx, A(0)), I(ctx, A(1)), U(ctx, A(2)), I(ctx, A(3)), I(ctx, A(4)), I(ctx, A(5))))
V0(uniform1f, gl.Uniform1f(I(ctx, A(0)), F(ctx, A(1))))
V0(uniform2f, gl.Uniform2f(I(ctx, A(0)), F(ctx, A(1)), F(ctx, A(2))))
V0(uniform3f, gl.Uniform3f(I(ctx, A(0)), F(ctx, A(1)), F(ctx, A(2)), F(ctx, A(3))))
V0(uniform4f, gl.Uniform4f(I(ctx, A(0)), F(ctx, A(1)), F(ctx, A(2)), F(ctx, A(3)), F(ctx, A(4))))
V0(uniform1i, gl.Uniform1i(I(ctx, A(0)), I(ctx, A(1))))
V0(uniform2i, gl.Uniform2i(I(ctx, A(0)), I(ctx, A(1)), I(ctx, A(2))))
V0(uniform3i, gl.Uniform3i(I(ctx, A(0)), I(ctx, A(1)), I(ctx, A(2)), I(ctx, A(3))))
V0(uniform4i, gl.Uniform4i(I(ctx, A(0)), I(ctx, A(1)), I(ctx, A(2)), I(ctx, A(3)), I(ctx, A(4))))
V0(uniform1ui, gl.Uniform1ui(I(ctx, A(0)), U(ctx, A(1))))
V0(uniform2ui, gl.Uniform2ui(I(ctx, A(0)), U(ctx, A(1)), U(ctx, A(2))))
V0(uniform3ui, gl.Uniform3ui(I(ctx, A(0)), U(ctx, A(1)), U(ctx, A(2)), U(ctx, A(3))))
V0(uniform4ui, gl.Uniform4ui(I(ctx, A(0)), U(ctx, A(1)), U(ctx, A(2)), U(ctx, A(3)), U(ctx, A(4))))
V0(uniformBlockBinding, gl.UniformBlockBinding(U(ctx, A(0)), U(ctx, A(1)), U(ctx, A(2))))
V0(useProgram, gl.UseProgram(U(ctx, A(0))))
V0(validateProgram, gl.ValidateProgram(U(ctx, A(0))))
V0(vertexAttrib1f, gl.VertexAttrib1f(U(ctx, A(0)), F(ctx, A(1))))
V0(vertexAttrib2f, gl.VertexAttrib2f(U(ctx, A(0)), F(ctx, A(1)), F(ctx, A(2))))
V0(vertexAttrib3f, gl.VertexAttrib3f(U(ctx, A(0)), F(ctx, A(1)), F(ctx, A(2)), F(ctx, A(3))))
V0(vertexAttrib4f, gl.VertexAttrib4f(U(ctx, A(0)), F(ctx, A(1)), F(ctx, A(2)), F(ctx, A(3)), F(ctx, A(4))))
V0(vertexAttribI4i, gl.VertexAttribI4i(U(ctx, A(0)), I(ctx, A(1)), I(ctx, A(2)), I(ctx, A(3)), I(ctx, A(4))))
V0(vertexAttribI4ui, gl.VertexAttribI4ui(U(ctx, A(0)), U(ctx, A(1)), U(ctx, A(2)), U(ctx, A(3)), U(ctx, A(4))))
V0(vertexAttribDivisor, gl.VertexAttribDivisor(U(ctx, A(0)), U(ctx, A(1))))
V0(vertexAttribIPointer, gl.VertexAttribIPointer(U(ctx, A(0)), I(ctx, A(1)), U(ctx, A(2)), I(ctx, A(3)), (const void *)(intptr_t)L(ctx, A(4))))
V0(vertexAttribPointer, gl.VertexAttribPointer(U(ctx, A(0)), I(ctx, A(1)), U(ctx, A(2)), B(ctx, A(3)), I(ctx, A(4)), (const void *)(intptr_t)L(ctx, A(5))))
V0(viewport, gl.Viewport(I(ctx, A(0)), I(ctx, A(1)), I(ctx, A(2)), I(ctx, A(3))))
V0(deleteProgram, gl.DeleteProgram(U(ctx, A(0))))
V0(deleteShader, gl.DeleteShader(U(ctx, A(0))))

/* Object names ---------------------------------------------------------------- */

#define GEN(js, fn) GLFN(js) { ENTER(); GLuint n = 0; gl.fn(1, &n); return JS_NewUint32(ctx, n); }
#define DEL(js, fn) GLFN(js) { ENTER(); GLuint n = U(ctx, A(0)); gl.fn(1, &n); return JS_UNDEFINED; }
GEN(createBuffer, GenBuffers)
GEN(createFramebuffer, GenFramebuffers)
GEN(createQuery, GenQueries)
GEN(createRenderbuffer, GenRenderbuffers)
GEN(createSampler, GenSamplers)
GEN(createTexture, GenTextures)
GEN(createTransformFeedback, GenTransformFeedbacks)
GEN(createVertexArray, GenVertexArrays)
DEL(deleteBuffer, DeleteBuffers)
DEL(deleteQuery, DeleteQueries)
DEL(deleteRenderbuffer, DeleteRenderbuffers)
DEL(deleteSampler, DeleteSamplers)
DEL(deleteTexture, DeleteTextures)
DEL(deleteTransformFeedback, DeleteTransformFeedbacks)
DEL(deleteVertexArray, DeleteVertexArrays)

GLFN(deleteFramebuffer) {
  ENTER();
  GLuint n = U(ctx, A(0));
  if (g->user_draw_fbo == n) g->user_draw_fbo = 0;
  if (g->user_read_fbo == n) g->user_read_fbo = 0;
  gl.DeleteFramebuffers(1, &n);
  return JS_UNDEFINED;
}

GLFN(createProgram) { ENTER(); return JS_NewUint32(ctx, gl.CreateProgram()); }
GLFN(createShader) { ENTER(); return JS_NewUint32(ctx, gl.CreateShader(U(ctx, A(0)))); }

/* Queries ---------------------------------------------------------------------- */

GLFN(getError) { ENTER(); return JS_NewUint32(ctx, gl.GetError()); }
GLFN(isEnabled) { ENTER(); return JS_NewBool(ctx, gl.IsEnabled(U(ctx, A(0)))); }
GLFN(checkFramebufferStatus) { ENTER(); return JS_NewUint32(ctx, gl.CheckFramebufferStatus(U(ctx, A(0)))); }

static JSValue nx_int_array(JSContext *ctx, const GLint *v, int n) {
  JSValue a = JS_NewArray(ctx);
  for (int i = 0; i < n; i++) JS_SetPropertyUint32(ctx, a, i, JS_NewInt32(ctx, v[i]));
  return a;
}

/* getIntegerv(pname, count) -> number | number[] */
GLFN(getIntegerv) {
  ENTER();
  GLint v[16] = {0};
  int n = I(ctx, A(1));
  if (n < 1 || n > 16) n = 1;
  gl.GetIntegerv(U(ctx, A(0)), v);
  return n == 1 ? JS_NewInt32(ctx, v[0]) : nx_int_array(ctx, v, n);
}

GLFN(getInteger64v) {
  ENTER();
  GLint64 v = 0;
  gl.GetInteger64v(U(ctx, A(0)), &v);
  return JS_NewFloat64(ctx, (double)v);
}

GLFN(getFloatv) {
  ENTER();
  GLfloat v[16] = {0};
  int n = I(ctx, A(1));
  if (n < 1 || n > 16) n = 1;
  gl.GetFloatv(U(ctx, A(0)), v);
  if (n == 1) return JS_NewFloat64(ctx, v[0]);
  JSValue a = JS_NewArray(ctx);
  for (int i = 0; i < n; i++) JS_SetPropertyUint32(ctx, a, i, JS_NewFloat64(ctx, v[i]));
  return a;
}

GLFN(getBooleanv) {
  ENTER();
  GLboolean v[4] = {0};
  int n = I(ctx, A(1));
  if (n < 1 || n > 4) n = 1;
  gl.GetBooleanv(U(ctx, A(0)), v);
  if (n == 1) return JS_NewBool(ctx, v[0]);
  JSValue a = JS_NewArray(ctx);
  for (int i = 0; i < n; i++) JS_SetPropertyUint32(ctx, a, i, JS_NewBool(ctx, v[i]));
  return a;
}

GLFN(getString) {
  ENTER();
  const GLubyte *s = gl.GetString(U(ctx, A(0)));
  return s ? JS_NewString(ctx, (const char *)s) : JS_NULL;
}

/* GLES extension names (for getSupportedExtensions). */
GLFN(getExtensions) {
  ENTER();
  GLint n = 0;
  gl.GetIntegerv(GL_NUM_EXTENSIONS, &n);
  JSValue a = JS_NewArray(ctx);
  for (GLint i = 0; i < n; i++) {
    const GLubyte *s = gl.GetStringi(GL_EXTENSIONS, (GLuint)i);
    if (s) JS_SetPropertyUint32(ctx, a, (uint32_t)i, JS_NewString(ctx, (const char *)s));
  }
  return a;
}

GLFN(getIndexedParameter) {
  ENTER();
  GLint v = 0;
  gl.GetIntegeri_v(U(ctx, A(0)), U(ctx, A(1)), &v);
  return JS_NewInt32(ctx, v);
}

#define IV(js, fn, nargs_expr)                  \
  GLFN(js) {                                    \
    ENTER();                                    \
    GLint v = 0;                                \
    nargs_expr;                                 \
    return JS_NewInt32(ctx, v);                 \
  }
IV(getShaderParameter, GetShaderiv, gl.GetShaderiv(U(ctx, A(0)), U(ctx, A(1)), &v))
IV(getProgramParameter, GetProgramiv, gl.GetProgramiv(U(ctx, A(0)), U(ctx, A(1)), &v))
IV(getBufferParameter, GetBufferParameteriv, gl.GetBufferParameteriv(U(ctx, A(0)), U(ctx, A(1)), &v))
IV(getRenderbufferParameter, GetRenderbufferParameteriv, gl.GetRenderbufferParameteriv(U(ctx, A(0)), U(ctx, A(1)), &v))
IV(getTexParameteri, GetTexParameteriv, gl.GetTexParameteriv(U(ctx, A(0)), U(ctx, A(1)), &v))
IV(getFramebufferAttachmentParameter, GetFramebufferAttachmentParameteriv,
   gl.GetFramebufferAttachmentParameteriv(U(ctx, A(0)), U(ctx, A(1)), U(ctx, A(2)), &v))
IV(getQuery, GetQueryiv, gl.GetQueryiv(U(ctx, A(0)), U(ctx, A(1)), &v))
IV(getSamplerParameteri, GetSamplerParameteriv, gl.GetSamplerParameteriv(U(ctx, A(0)), U(ctx, A(1)), &v))
IV(getVertexAttribi, GetVertexAttribiv, gl.GetVertexAttribiv(U(ctx, A(0)), U(ctx, A(1)), &v))
IV(getActiveUniformBlockParameteri, GetActiveUniformBlockiv,
   gl.GetActiveUniformBlockiv(U(ctx, A(0)), U(ctx, A(1)), U(ctx, A(2)), &v))

GLFN(getQueryParameter) {
  ENTER();
  GLuint v = 0;
  gl.GetQueryObjectuiv(U(ctx, A(0)), U(ctx, A(1)), &v);
  return JS_NewUint32(ctx, v);
}

GLFN(getTexParameterf) {
  ENTER();
  GLfloat v = 0;
  gl.GetTexParameterfv(U(ctx, A(0)), U(ctx, A(1)), &v);
  return JS_NewFloat64(ctx, v);
}

GLFN(getSamplerParameterf) {
  ENTER();
  GLfloat v = 0;
  gl.GetSamplerParameterfv(U(ctx, A(0)), U(ctx, A(1)), &v);
  return JS_NewFloat64(ctx, v);
}

GLFN(getVertexAttribf4) {
  ENTER();
  GLfloat v[4] = {0};
  gl.GetVertexAttribfv(U(ctx, A(0)), U(ctx, A(1)), v);
  JSValue a = JS_NewArray(ctx);
  for (int i = 0; i < 4; i++) JS_SetPropertyUint32(ctx, a, i, JS_NewFloat64(ctx, v[i]));
  return a;
}

GLFN(getShaderPrecisionFormat) {
  ENTER();
  GLint range[2] = {0, 0}, precision = 0;
  gl.GetShaderPrecisionFormat(U(ctx, A(0)), U(ctx, A(1)), range, &precision);
  GLint v[3] = {range[0], range[1], precision};
  return nx_int_array(ctx, v, 3);
}

GLFN(getInternalformatParameter) {
  ENTER();
  GLint count = 0;
  GLenum target = U(ctx, A(0)), fmt = U(ctx, A(1)), pname = U(ctx, A(2));
  if (pname == GL_SAMPLES) gl.GetInternalformativ(target, fmt, GL_NUM_SAMPLE_COUNTS, 1, &count);
  if (count < 0) count = 0;
  if (count > 32) count = 32;
  GLint v[32] = {0};
  if (count > 0) gl.GetInternalformativ(target, fmt, pname, count, v);
  return nx_int_array(ctx, v, count);
}

/* Strings ------------------------------------------------------------------------ */

GLFN(shaderSource) {
  ENTER();
  size_t len = 0;
  const char *src = JS_ToCStringLen(ctx, &len, A(1));
  if (!src) return JS_EXCEPTION;
  GLint l = (GLint)len;
  gl.ShaderSource(U(ctx, A(0)), 1, &src, &l);
  JS_FreeCString(ctx, src);
  return JS_UNDEFINED;
}

static JSValue nx_log(JSContext *ctx, GLuint obj, bool program) {
  GLint len = 0;
  if (program)
    gl.GetProgramiv(obj, GL_INFO_LOG_LENGTH, &len);
  else
    gl.GetShaderiv(obj, GL_INFO_LOG_LENGTH, &len);
  if (len <= 0) return JS_NewString(ctx, "");
  char *buf = (char *)malloc((size_t)len + 1);
  if (!buf) return JS_ThrowOutOfMemory(ctx);
  GLsizei got = 0;
  if (program)
    gl.GetProgramInfoLog(obj, len, &got, buf);
  else
    gl.GetShaderInfoLog(obj, len, &got, buf);
  buf[got] = 0;
  JSValue s = JS_NewString(ctx, buf);
  free(buf);
  return s;
}
GLFN(getShaderInfoLog) { ENTER(); return nx_log(ctx, U(ctx, A(0)), false); }
GLFN(getProgramInfoLog) { ENTER(); return nx_log(ctx, U(ctx, A(0)), true); }

GLFN(getShaderSource) {
  ENTER();
  GLint len = 0;
  GLuint s = U(ctx, A(0));
  gl.GetShaderiv(s, GL_SHADER_SOURCE_LENGTH, &len);
  if (len <= 0) return JS_NewString(ctx, "");
  char *buf = (char *)malloc((size_t)len + 1);
  GLsizei got = 0;
  gl.GetShaderSource(s, len, &got, buf);
  buf[got] = 0;
  JSValue r = JS_NewString(ctx, buf);
  free(buf);
  return r;
}

#define LOC(js, fn, ret_new)                                  \
  GLFN(js) {                                                  \
    ENTER();                                                  \
    const char *name = JS_ToCString(ctx, A(1));               \
    if (!name) return JS_EXCEPTION;                           \
    JSValue r = ret_new(ctx, gl.fn(U(ctx, A(0)), name));      \
    JS_FreeCString(ctx, name);                                \
    return r;                                                 \
  }
LOC(getUniformLocation, GetUniformLocation, JS_NewInt32)
LOC(getAttribLocation, GetAttribLocation, JS_NewInt32)
LOC(getFragDataLocation, GetFragDataLocation, JS_NewInt32)
LOC(getUniformBlockIndex, GetUniformBlockIndex, JS_NewUint32)

GLFN(bindAttribLocation) {
  ENTER();
  const char *name = JS_ToCString(ctx, A(2));
  if (!name) return JS_EXCEPTION;
  gl.BindAttribLocation(U(ctx, A(0)), U(ctx, A(1)), name);
  JS_FreeCString(ctx, name);
  return JS_UNDEFINED;
}

/* [name, size, type] or null */
static JSValue nx_active(JSContext *ctx, GLuint program, GLuint index, int kind) {
  GLint max = 0;
  GLenum pname = kind == 0 ? GL_ACTIVE_ATTRIBUTE_MAX_LENGTH
                 : kind == 1 ? GL_ACTIVE_UNIFORM_MAX_LENGTH
                             : GL_TRANSFORM_FEEDBACK_VARYING_MAX_LENGTH;
  gl.GetProgramiv(program, pname, &max);
  if (max < 1) max = 256;
  char *name = (char *)calloc(1, (size_t)max + 1);
  GLsizei len = 0;
  GLint size = 0;
  GLenum type = 0;
  if (kind == 0)
    gl.GetActiveAttrib(program, index, max, &len, &size, &type, name);
  else if (kind == 1)
    gl.GetActiveUniform(program, index, max, &len, &size, &type, name);
  else
    gl.GetTransformFeedbackVarying(program, index, max, &len, &size, &type, name);
  if (type == 0) {
    free(name);
    return JS_NULL;
  }
  JSValue a = JS_NewArray(ctx);
  JS_SetPropertyUint32(ctx, a, 0, JS_NewStringLen(ctx, name, (size_t)len));
  JS_SetPropertyUint32(ctx, a, 1, JS_NewInt32(ctx, size));
  JS_SetPropertyUint32(ctx, a, 2, JS_NewUint32(ctx, type));
  free(name);
  return a;
}
GLFN(getActiveAttrib) { ENTER(); return nx_active(ctx, U(ctx, A(0)), U(ctx, A(1)), 0); }
GLFN(getActiveUniform) { ENTER(); return nx_active(ctx, U(ctx, A(0)), U(ctx, A(1)), 1); }
GLFN(getTransformFeedbackVarying) { ENTER(); return nx_active(ctx, U(ctx, A(0)), U(ctx, A(1)), 2); }

GLFN(getActiveUniformBlockName) {
  ENTER();
  GLuint program = U(ctx, A(0)), index = U(ctx, A(1));
  GLint len = 0;
  gl.GetActiveUniformBlockiv(program, index, GL_UNIFORM_BLOCK_NAME_LENGTH, &len);
  if (len <= 0) return JS_NULL;
  char *name = (char *)calloc(1, (size_t)len + 1);
  GLsizei got = 0;
  gl.GetActiveUniformBlockName(program, index, len, &got, name);
  JSValue r = JS_NewStringLen(ctx, name, (size_t)got);
  free(name);
  return r;
}

GLFN(getActiveUniformBlockIndices) {
  ENTER();
  GLuint program = U(ctx, A(0)), index = U(ctx, A(1));
  GLint n = 0;
  gl.GetActiveUniformBlockiv(program, index, GL_UNIFORM_BLOCK_ACTIVE_UNIFORMS, &n);
  if (n <= 0) return JS_NewArray(ctx);
  GLint *v = (GLint *)calloc((size_t)n, sizeof(GLint));
  gl.GetActiveUniformBlockiv(program, index, GL_UNIFORM_BLOCK_ACTIVE_UNIFORM_INDICES, v);
  JSValue a = nx_int_array(ctx, v, n);
  free(v);
  return a;
}

/* getActiveUniforms(program, indices[], pname) -> number[] */
GLFN(getActiveUniforms) {
  ENTER();
  JSValue arr = A(1);
  int64_t n = 0;
  JS_GetLength(ctx, arr, &n);
  if (n <= 0 || n > 4096) return JS_NewArray(ctx);
  GLuint *idx = (GLuint *)calloc((size_t)n, sizeof(GLuint));
  GLint *out = (GLint *)calloc((size_t)n, sizeof(GLint));
  for (int64_t i = 0; i < n; i++) {
    JSValue v = JS_GetPropertyUint32(ctx, arr, (uint32_t)i);
    idx[i] = U(ctx, v);
    JS_FreeValue(ctx, v);
  }
  gl.GetActiveUniformsiv(U(ctx, A(0)), (GLsizei)n, idx, U(ctx, A(2)), out);
  JSValue a = nx_int_array(ctx, out, (int)n);
  free(idx);
  free(out);
  return a;
}

static const char **nx_string_list(JSContext *ctx, JSValueConst arr, int64_t *count) {
  int64_t n = 0;
  JS_GetLength(ctx, arr, &n);
  if (n < 0 || n > 4096) n = 0;
  *count = n;
  const char **names = (const char **)calloc((size_t)(n ? n : 1), sizeof(char *));
  for (int64_t i = 0; i < n; i++) {
    JSValue v = JS_GetPropertyUint32(ctx, arr, (uint32_t)i);
    names[i] = JS_ToCString(ctx, v);
    JS_FreeValue(ctx, v);
  }
  return names;
}

static void nx_free_string_list(JSContext *ctx, const char **names, int64_t n) {
  for (int64_t i = 0; i < n; i++)
    if (names[i]) JS_FreeCString(ctx, names[i]);
  free((void *)names);
}

GLFN(getUniformIndices) {
  ENTER();
  int64_t n = 0;
  const char **names = nx_string_list(ctx, A(1), &n);
  GLuint *out = (GLuint *)calloc((size_t)(n ? n : 1), sizeof(GLuint));
  gl.GetUniformIndices(U(ctx, A(0)), (GLsizei)n, names, out);
  JSValue a = JS_NewArray(ctx);
  for (int64_t i = 0; i < n; i++) JS_SetPropertyUint32(ctx, a, (uint32_t)i, JS_NewUint32(ctx, out[i]));
  free(out);
  nx_free_string_list(ctx, names, n);
  return a;
}

GLFN(transformFeedbackVaryings) {
  ENTER();
  int64_t n = 0;
  const char **names = nx_string_list(ctx, A(1), &n);
  gl.TransformFeedbackVaryings(U(ctx, A(0)), (GLsizei)n, names, U(ctx, A(2)));
  nx_free_string_list(ctx, names, n);
  return JS_UNDEFINED;
}

/* Arrays of enums ---------------------------------------------------------------- */

static GLenum *nx_enum_list(JSContext *ctx, JSValueConst arr, int64_t *count) {
  int64_t n = 0;
  JS_GetLength(ctx, arr, &n);
  if (n < 0 || n > 64) n = 0;
  *count = n;
  GLenum *v = (GLenum *)calloc((size_t)(n ? n : 1), sizeof(GLenum));
  for (int64_t i = 0; i < n; i++) {
    JSValue x = JS_GetPropertyUint32(ctx, arr, (uint32_t)i);
    v[i] = U(ctx, x);
    JS_FreeValue(ctx, x);
  }
  return v;
}

GLFN(drawBuffers) {
  ENTER();
  int64_t n = 0;
  GLenum *v = nx_enum_list(ctx, A(0), &n);
  /* For the default framebuffer WebGL says BACK; ours is an FBO. */
  if (!g->user_draw_fbo && n == 1 && v[0] == GL_BACK) v[0] = GL_COLOR_ATTACHMENT0;
  gl.DrawBuffers((GLsizei)n, v);
  free(v);
  return JS_UNDEFINED;
}

GLFN(invalidateFramebuffer) {
  ENTER();
  int64_t n = 0;
  GLenum *v = nx_enum_list(ctx, A(1), &n);
  if (g->user_draw_fbo || U(ctx, A(0)) == GL_READ_FRAMEBUFFER) {
    gl.InvalidateFramebuffer(U(ctx, A(0)), (GLsizei)n, v);
  }
  free(v);
  return JS_UNDEFINED;
}

/* Buffers ---------------------------------------------------------------------- */

/* bufferData(target, sizeOrView, usage, srcOffsetElements, lengthElements) */
GLFN(bufferData) {
  ENTER();
  GLenum target = U(ctx, A(0)), usage = U(ctx, A(2));
  if (JS_IsNumber(A(1))) {
    gl.BufferData(target, (GLsizeiptr)L(ctx, A(1)), NULL, usage);
    return JS_UNDEFINED;
  }
  size_t len = 0, elem = 1;
  uint8_t *p = nx_bytes(ctx, A(1), &len, &elem);
  if (!p && len) return JS_ThrowTypeError(ctx, "bufferData: invalid data");
  size_t off = (size_t)L(ctx, A(3)) * elem;
  size_t n = len;
  if (off > len) return JS_ThrowRangeError(ctx, "bufferData: srcOffset out of range");
  int64_t count = L(ctx, A(4));
  n = count > 0 ? (size_t)count * elem : len - off;
  if (off + n > len) return JS_ThrowRangeError(ctx, "bufferData: length out of range");
  gl.BufferData(target, (GLsizeiptr)n, p ? p + off : NULL, usage);
  return JS_UNDEFINED;
}

/* bufferSubData(target, dstByteOffset, view, srcOffsetElements, lengthElements) */
GLFN(bufferSubData) {
  ENTER();
  size_t len = 0, elem = 1;
  uint8_t *p = nx_bytes(ctx, A(2), &len, &elem);
  if (!p) return JS_ThrowTypeError(ctx, "bufferSubData: invalid data");
  size_t off = (size_t)L(ctx, A(3)) * elem;
  if (off > len) return JS_ThrowRangeError(ctx, "bufferSubData: srcOffset out of range");
  int64_t count = L(ctx, A(4));
  size_t n = count > 0 ? (size_t)count * elem : len - off;
  if (off + n > len) return JS_ThrowRangeError(ctx, "bufferSubData: length out of range");
  gl.BufferSubData(U(ctx, A(0)), (GLintptr)L(ctx, A(1)), (GLsizeiptr)n, p + off);
  return JS_UNDEFINED;
}

/* getBufferSubData(target, srcByteOffset, dstView, dstOffsetElements, lengthElements) */
GLFN(getBufferSubData) {
  ENTER();
  size_t len = 0, elem = 1;
  uint8_t *p = nx_bytes(ctx, A(2), &len, &elem);
  if (!p) return JS_ThrowTypeError(ctx, "getBufferSubData: invalid destination");
  size_t off = (size_t)L(ctx, A(3)) * elem;
  int64_t count = L(ctx, A(4));
  size_t n = count > 0 ? (size_t)count * elem : len - off;
  if (off + n > len) return JS_ThrowRangeError(ctx, "getBufferSubData: out of range");
  GLenum target = U(ctx, A(0));
  void *src = gl.MapBufferRange(target, (GLintptr)L(ctx, A(1)), (GLsizeiptr)n, GL_MAP_READ_BIT);
  if (src) {
    memcpy(p + off, src, n);
    gl.UnmapBuffer(target);
  }
  return JS_UNDEFINED;
}

/* Uniforms with arrays ------------------------------------------------------------ */

/* uniformNv(kind, location, view, srcOffset, srcLength); kind: 1..4 f, 11..14 i,
 * 21..24 ui */
GLFN(uniformv) {
  ENTER();
  int kind = I(ctx, A(0));
  GLint loc = I(ctx, A(1));
  size_t len = 0, elem = 4;
  uint8_t *p = nx_bytes(ctx, A(2), &len, &elem);
  if (!p) return JS_ThrowTypeError(ctx, "uniform: invalid data");
  size_t off = (size_t)L(ctx, A(3)) * 4;
  int64_t sl = L(ctx, A(4));
  size_t n = sl > 0 ? (size_t)sl * 4 : len - off;
  if (off + n > len) return JS_ThrowRangeError(ctx, "uniform: out of range");
  int comps = kind % 10;
  GLsizei count = (GLsizei)(n / 4 / (size_t)comps);
  const void *d = p + off;
  switch (kind) {
    case 1: gl.Uniform1fv(loc, count, d); break;
    case 2: gl.Uniform2fv(loc, count, d); break;
    case 3: gl.Uniform3fv(loc, count, d); break;
    case 4: gl.Uniform4fv(loc, count, d); break;
    case 11: gl.Uniform1iv(loc, count, d); break;
    case 12: gl.Uniform2iv(loc, count, d); break;
    case 13: gl.Uniform3iv(loc, count, d); break;
    case 14: gl.Uniform4iv(loc, count, d); break;
    case 21: gl.Uniform1uiv(loc, count, d); break;
    case 22: gl.Uniform2uiv(loc, count, d); break;
    case 23: gl.Uniform3uiv(loc, count, d); break;
    case 24: gl.Uniform4uiv(loc, count, d); break;
  }
  return JS_UNDEFINED;
}

/* uniformMatrix(kind, location, transpose, view, srcOffset, srcLength); kind
 * = columns*10 + rows */
GLFN(uniformMatrix) {
  ENTER();
  int kind = I(ctx, A(0));
  GLint loc = I(ctx, A(1));
  GLboolean tr = B(ctx, A(2));
  size_t len = 0, elem = 4;
  uint8_t *p = nx_bytes(ctx, A(3), &len, &elem);
  if (!p) return JS_ThrowTypeError(ctx, "uniformMatrix: invalid data");
  size_t off = (size_t)L(ctx, A(4)) * 4;
  int64_t sl = L(ctx, A(5));
  size_t n = sl > 0 ? (size_t)sl * 4 : len - off;
  if (off + n > len) return JS_ThrowRangeError(ctx, "uniformMatrix: out of range");
  int cells = (kind / 10) * (kind % 10);
  GLsizei count = (GLsizei)(n / 4 / (size_t)cells);
  const GLfloat *d = (const GLfloat *)(p + off);
  switch (kind) {
    case 22: gl.UniformMatrix2fv(loc, count, tr, d); break;
    case 33: gl.UniformMatrix3fv(loc, count, tr, d); break;
    case 44: gl.UniformMatrix4fv(loc, count, tr, d); break;
    case 23: gl.UniformMatrix2x3fv(loc, count, tr, d); break;
    case 24: gl.UniformMatrix2x4fv(loc, count, tr, d); break;
    case 32: gl.UniformMatrix3x2fv(loc, count, tr, d); break;
    case 34: gl.UniformMatrix3x4fv(loc, count, tr, d); break;
    case 42: gl.UniformMatrix4x2fv(loc, count, tr, d); break;
    case 43: gl.UniformMatrix4x3fv(loc, count, tr, d); break;
  }
  return JS_UNDEFINED;
}

GLFN(vertexAttrib4fv) {
  ENTER();
  size_t len = 0, elem = 4;
  uint8_t *p = nx_bytes(ctx, A(1), &len, &elem);
  if (!p || len < 16) return JS_ThrowTypeError(ctx, "vertexAttrib4fv: 4 floats expected");
  gl.VertexAttrib4fv(U(ctx, A(0)), (const GLfloat *)p);
  return JS_UNDEFINED;
}

/* clearBuffer(kind 0=f,1=i,2=ui, buffer, drawbuffer, view, srcOffset) */
GLFN(clearBufferv) {
  ENTER();
  int kind = I(ctx, A(0));
  size_t len = 0, elem = 4;
  uint8_t *p = nx_bytes(ctx, A(3), &len, &elem);
  if (!p) return JS_ThrowTypeError(ctx, "clearBuffer: invalid data");
  size_t off = (size_t)L(ctx, A(4)) * 4;
  if (off + 4 > len) return JS_ThrowRangeError(ctx, "clearBuffer: out of range");
  GLenum buffer = U(ctx, A(1));
  GLint draw = I(ctx, A(2));
  if (kind == 0) gl.ClearBufferfv(buffer, draw, (const GLfloat *)(p + off));
  else if (kind == 1) gl.ClearBufferiv(buffer, draw, (const GLint *)(p + off));
  else gl.ClearBufferuiv(buffer, draw, (const GLuint *)(p + off));
  DRAWN();
  return JS_UNDEFINED;
}

/* Pixel store and textures ------------------------------------------------------- */

#define UNPACK_FLIP_Y_WEBGL 0x9240
#define UNPACK_PREMULTIPLY_ALPHA_WEBGL 0x9241
#define UNPACK_COLORSPACE_CONVERSION_WEBGL 0x9243

GLFN(pixelStorei) {
  ENTER();
  GLenum p = U(ctx, A(0));
  GLint v = I(ctx, A(1));
  if (p == UNPACK_FLIP_Y_WEBGL) g->flip_y = v != 0;
  else if (p == UNPACK_PREMULTIPLY_ALPHA_WEBGL) g->premultiply = v != 0;
  else if (p == UNPACK_COLORSPACE_CONVERSION_WEBGL) {
  } else gl.PixelStorei(p, v);
  return JS_UNDEFINED;
}

static int nx_bytes_per_pixel(GLenum format, GLenum type) {
  int comps;
  switch (format) {
    case GL_RED: case GL_RED_INTEGER: case GL_ALPHA: case GL_LUMINANCE: case GL_DEPTH_COMPONENT: comps = 1; break;
    case GL_RG: case GL_RG_INTEGER: case GL_LUMINANCE_ALPHA: case GL_DEPTH_STENCIL: comps = 2; break;
    case GL_RGB: case GL_RGB_INTEGER: comps = 3; break;
    default: comps = 4; break;
  }
  switch (type) {
    case GL_UNSIGNED_BYTE: case GL_BYTE: return comps;
    case GL_UNSIGNED_SHORT: case GL_SHORT: case GL_HALF_FLOAT: return comps * 2;
    case GL_UNSIGNED_INT: case GL_INT: case GL_FLOAT: return comps * 4;
    case GL_UNSIGNED_SHORT_5_6_5: case GL_UNSIGNED_SHORT_4_4_4_4: case GL_UNSIGNED_SHORT_5_5_5_1: return 2;
    case GL_UNSIGNED_INT_2_10_10_10_REV: case GL_UNSIGNED_INT_10F_11F_11F_REV:
    case GL_UNSIGNED_INT_5_9_9_9_REV: case GL_UNSIGNED_INT_24_8: return 4;
    case GL_FLOAT_32_UNSIGNED_INT_24_8_REV: return 8;
  }
  return comps;
}

/* Applies WebGL UNPACK_FLIP_Y / PREMULTIPLY to tightly packed ArrayBufferView
 * data (returns a temporary copy, or src when nothing applies). */
static const uint8_t *nx_unpack(NxGl *g, const uint8_t *src, int32_t w, int32_t h, int32_t depth,
                                GLenum format, GLenum type, uint8_t **owned) {
  *owned = NULL;
  if (!src || (!g->flip_y && !g->premultiply)) return src;
  GLint align = 4;
  gl.GetIntegerv(GL_UNPACK_ALIGNMENT, &align);
  size_t bpp = (size_t)nx_bytes_per_pixel(format, type);
  size_t row = (size_t)w * bpp;
  size_t stride = (row + (size_t)align - 1) / (size_t)align * (size_t)align;
  size_t layer = stride * (size_t)h;
  size_t total = layer * (size_t)(depth > 0 ? depth : 1);
  uint8_t *copy = (uint8_t *)malloc(total ? total : 1);
  if (!copy) return src;
  memcpy(copy, src, total);
  for (int32_t z = 0; z < (depth > 0 ? depth : 1); z++) {
    uint8_t *base = copy + layer * (size_t)z;
    if (g->premultiply && format == GL_RGBA && type == GL_UNSIGNED_BYTE) {
      for (int32_t y = 0; y < h; y++) nx_premultiply(base + stride * (size_t)y, row);
    }
    if (g->flip_y) nx_flip_rows(base, stride, h);
  }
  *owned = copy;
  return copy;
}

/* texImage2D(target, level, internalformat, width, height, border, format,
 * type, view|null, srcOffsetElements) */
GLFN(texImage2D) {
  ENTER();
  GLenum format = U(ctx, A(6)), type = U(ctx, A(7));
  int32_t w = I(ctx, A(3)), h = I(ctx, A(4));
  const uint8_t *data = NULL;
  if (!JS_IsNull(A(8)) && !JS_IsUndefined(A(8))) {
    size_t len = 0, elem = 1;
    uint8_t *p = nx_bytes(ctx, A(8), &len, &elem);
    if (!p) return JS_ThrowTypeError(ctx, "texImage2D: invalid pixels");
    size_t off = (size_t)L(ctx, A(9)) * elem;
    if (off > len) return JS_ThrowRangeError(ctx, "texImage2D: srcOffset out of range");
    data = p + off;
  }
  uint8_t *owned = NULL;
  data = nx_unpack(g, data, w, h, 1, format, type, &owned);
  gl.TexImage2D(U(ctx, A(0)), I(ctx, A(1)), I(ctx, A(2)), w, h, I(ctx, A(5)), format, type, data);
  free(owned);
  return JS_UNDEFINED;
}

/* texImage2DOffset(...same, pboOffset) uploads from PIXEL_UNPACK_BUFFER. */
GLFN(texImage2DOffset) {
  ENTER();
  gl.TexImage2D(U(ctx, A(0)), I(ctx, A(1)), I(ctx, A(2)), I(ctx, A(3)), I(ctx, A(4)), I(ctx, A(5)),
                U(ctx, A(6)), U(ctx, A(7)), (const void *)(intptr_t)L(ctx, A(8)));
  return JS_UNDEFINED;
}

/* texSubImage2D(target, level, x, y, width, height, format, type, view, srcOffset) */
GLFN(texSubImage2D) {
  ENTER();
  GLenum format = U(ctx, A(6)), type = U(ctx, A(7));
  int32_t w = I(ctx, A(4)), h = I(ctx, A(5));
  size_t len = 0, elem = 1;
  uint8_t *p = nx_bytes(ctx, A(8), &len, &elem);
  if (!p) return JS_ThrowTypeError(ctx, "texSubImage2D: invalid pixels");
  size_t off = (size_t)L(ctx, A(9)) * elem;
  if (off > len) return JS_ThrowRangeError(ctx, "texSubImage2D: srcOffset out of range");
  uint8_t *owned = NULL;
  const uint8_t *data = nx_unpack(g, p + off, w, h, 1, format, type, &owned);
  gl.TexSubImage2D(U(ctx, A(0)), I(ctx, A(1)), I(ctx, A(2)), I(ctx, A(3)), w, h, format, type, data);
  free(owned);
  return JS_UNDEFINED;
}

/* texImage3D(target, level, internalformat, w, h, depth, border, format, type, view|null, srcOffset) */
GLFN(texImage3D) {
  ENTER();
  GLenum format = U(ctx, A(7)), type = U(ctx, A(8));
  int32_t w = I(ctx, A(3)), h = I(ctx, A(4)), d = I(ctx, A(5));
  const uint8_t *data = NULL;
  if (!JS_IsNull(A(9)) && !JS_IsUndefined(A(9))) {
    size_t len = 0, elem = 1;
    uint8_t *p = nx_bytes(ctx, A(9), &len, &elem);
    if (!p) return JS_ThrowTypeError(ctx, "texImage3D: invalid pixels");
    data = p + (size_t)L(ctx, A(10)) * elem;
  }
  uint8_t *owned = NULL;
  data = nx_unpack(g, data, w, h, d, format, type, &owned);
  gl.TexImage3D(U(ctx, A(0)), I(ctx, A(1)), I(ctx, A(2)), w, h, d, I(ctx, A(6)), format, type, data);
  free(owned);
  return JS_UNDEFINED;
}

/* texSubImage3D(target, level, x, y, z, w, h, d, format, type, view, srcOffset) */
GLFN(texSubImage3D) {
  ENTER();
  GLenum format = U(ctx, A(8)), type = U(ctx, A(9));
  int32_t w = I(ctx, A(5)), h = I(ctx, A(6)), d = I(ctx, A(7));
  size_t len = 0, elem = 1;
  uint8_t *p = nx_bytes(ctx, A(10), &len, &elem);
  if (!p) return JS_ThrowTypeError(ctx, "texSubImage3D: invalid pixels");
  uint8_t *owned = NULL;
  const uint8_t *data = nx_unpack(g, p + (size_t)L(ctx, A(11)) * elem, w, h, d, format, type, &owned);
  gl.TexSubImage3D(U(ctx, A(0)), I(ctx, A(1)), I(ctx, A(2)), I(ctx, A(3)), I(ctx, A(4)), w, h, d,
                   format, type, data);
  free(owned);
  return JS_UNDEFINED;
}

/* compressedTexImage(dims 2|3, sub 0|1, ...GL args..., view, srcOffset, srcLength) */
GLFN(compressedTexImage2D) {
  ENTER();
  size_t len = 0, elem = 1;
  uint8_t *p = nx_bytes(ctx, A(6), &len, &elem);
  if (!p) return JS_ThrowTypeError(ctx, "compressedTexImage2D: invalid data");
  size_t off = (size_t)L(ctx, A(7)) * elem;
  int64_t sl = L(ctx, A(8));
  size_t n = sl > 0 ? (size_t)sl * elem : len - off;
  gl.CompressedTexImage2D(U(ctx, A(0)), I(ctx, A(1)), U(ctx, A(2)), I(ctx, A(3)), I(ctx, A(4)),
                          I(ctx, A(5)), (GLsizei)n, p + off);
  return JS_UNDEFINED;
}

GLFN(compressedTexSubImage2D) {
  ENTER();
  size_t len = 0, elem = 1;
  uint8_t *p = nx_bytes(ctx, A(7), &len, &elem);
  if (!p) return JS_ThrowTypeError(ctx, "compressedTexSubImage2D: invalid data");
  size_t off = (size_t)L(ctx, A(8)) * elem;
  int64_t sl = L(ctx, A(9));
  size_t n = sl > 0 ? (size_t)sl * elem : len - off;
  gl.CompressedTexSubImage2D(U(ctx, A(0)), I(ctx, A(1)), I(ctx, A(2)), I(ctx, A(3)), I(ctx, A(4)),
                             I(ctx, A(5)), U(ctx, A(6)), (GLsizei)n, p + off);
  return JS_UNDEFINED;
}

GLFN(compressedTexImage3D) {
  ENTER();
  size_t len = 0, elem = 1;
  uint8_t *p = nx_bytes(ctx, A(7), &len, &elem);
  if (!p) return JS_ThrowTypeError(ctx, "compressedTexImage3D: invalid data");
  size_t off = (size_t)L(ctx, A(8)) * elem;
  int64_t sl = L(ctx, A(9));
  size_t n = sl > 0 ? (size_t)sl * elem : len - off;
  gl.CompressedTexImage3D(U(ctx, A(0)), I(ctx, A(1)), U(ctx, A(2)), I(ctx, A(3)), I(ctx, A(4)),
                          I(ctx, A(5)), I(ctx, A(6)), (GLsizei)n, p + off);
  return JS_UNDEFINED;
}

GLFN(compressedTexSubImage3D) {
  ENTER();
  size_t len = 0, elem = 1;
  uint8_t *p = nx_bytes(ctx, A(9), &len, &elem);
  if (!p) return JS_ThrowTypeError(ctx, "compressedTexSubImage3D: invalid data");
  size_t off = (size_t)L(ctx, A(10)) * elem;
  int64_t sl = L(ctx, A(11));
  size_t n = sl > 0 ? (size_t)sl * elem : len - off;
  gl.CompressedTexSubImage3D(U(ctx, A(0)), I(ctx, A(1)), I(ctx, A(2)), I(ctx, A(3)), I(ctx, A(4)),
                             I(ctx, A(5)), I(ctx, A(6)), I(ctx, A(7)), U(ctx, A(8)), (GLsizei)n, p + off);
  return JS_UNDEFINED;
}

/* Converts RGBA8 rows to the requested upload format (RGBA/RGB/RG/RED/
 * LUMINANCE[_ALPHA]/ALPHA, UNSIGNED_BYTE). Returns NULL when unsupported. */
static uint8_t *nx_convert_rgba8(const uint8_t *src, int32_t w, int32_t h, GLenum format) {
  int comps;
  switch (format) {
    case GL_RGBA: return NULL;
    case GL_RGB: comps = 3; break;
    case GL_RG: case GL_LUMINANCE_ALPHA: comps = 2; break;
    case GL_RED: case GL_LUMINANCE: case GL_ALPHA: comps = 1; break;
    default: return NULL;
  }
  size_t n = (size_t)w * (size_t)h;
  uint8_t *out = (uint8_t *)malloc(n * (size_t)comps + 1);
  if (!out) return NULL;
  for (size_t i = 0; i < n; i++) {
    const uint8_t *s = src + i * 4;
    uint8_t *d = out + i * (size_t)comps;
    switch (format) {
      case GL_RGB: d[0] = s[0]; d[1] = s[1]; d[2] = s[2]; break;
      case GL_RG: d[0] = s[0]; d[1] = s[1]; break;
      case GL_LUMINANCE_ALPHA: d[0] = s[0]; d[1] = s[3]; break;
      case GL_RED: case GL_LUMINANCE: d[0] = s[0]; break;
      case GL_ALPHA: d[0] = s[3]; break;
    }
  }
  return out;
}

/* texImageBitmap(sub 0|1, target, level, internalformat|xoffset, yoffset,
 * format, type, bitmapId, zoffset|-1) — uploads an ImageBitmap. UNPACK_FLIP_Y
 * and PREMULTIPLY do not apply (the bitmap was prepared at creation). */
GLFN(texImageBitmap) {
  ENTER();
  int sub = I(ctx, A(0));
  GLenum target = U(ctx, A(1));
  GLint level = I(ctx, A(2));
  GLenum format = U(ctx, A(5)), type = U(ctx, A(6));
  NxBitmap *b = nx_bitmap_get(L(ctx, A(7)));
  if (!b) return JS_ThrowTypeError(ctx, "The image bitmap is closed or detached");
  if (type != GL_UNSIGNED_BYTE) {
    return JS_ThrowTypeError(ctx, "texImage from ImageBitmap supports UNSIGNED_BYTE only");
  }
  uint8_t *converted = nx_convert_rgba8(b->rgba, b->w, b->h, format);
  const uint8_t *data = converted ? converted : b->rgba;
  GLint align = 4;
  gl.GetIntegerv(GL_UNPACK_ALIGNMENT, &align);
  GLint row_length = 0, skip_rows = 0, skip_pixels = 0, pbo = 0;
  gl.GetIntegerv(GL_UNPACK_ROW_LENGTH, &row_length);
  gl.GetIntegerv(GL_UNPACK_SKIP_ROWS, &skip_rows);
  gl.GetIntegerv(GL_UNPACK_SKIP_PIXELS, &skip_pixels);
  gl.GetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING, &pbo);
  gl.PixelStorei(GL_UNPACK_ALIGNMENT, 1);
  gl.PixelStorei(GL_UNPACK_ROW_LENGTH, 0);
  gl.PixelStorei(GL_UNPACK_SKIP_ROWS, 0);
  gl.PixelStorei(GL_UNPACK_SKIP_PIXELS, 0);
  if (pbo) gl.BindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
  int32_t z = I(ctx, A(8));
  if (sub) {
    if (z >= 0)
      gl.TexSubImage3D(target, level, I(ctx, A(3)), I(ctx, A(4)), z, b->w, b->h, 1, format, type, data);
    else
      gl.TexSubImage2D(target, level, I(ctx, A(3)), I(ctx, A(4)), b->w, b->h, format, type, data);
  } else {
    gl.TexImage2D(target, level, I(ctx, A(3)), b->w, b->h, 0, format, type, data);
  }
  if (pbo) gl.BindBuffer(GL_PIXEL_UNPACK_BUFFER, (GLuint)pbo);
  gl.PixelStorei(GL_UNPACK_ALIGNMENT, align);
  gl.PixelStorei(GL_UNPACK_ROW_LENGTH, row_length);
  gl.PixelStorei(GL_UNPACK_SKIP_ROWS, skip_rows);
  gl.PixelStorei(GL_UNPACK_SKIP_PIXELS, skip_pixels);
  free(converted);
  return JS_UNDEFINED;
}

/* readPixels(x, y, w, h, format, type, view|null, dstOffsetElements | pboOffset) */
GLFN(readPixels) {
  ENTER();
  int32_t x = I(ctx, A(0)), y = I(ctx, A(1)), w = I(ctx, A(2)), h = I(ctx, A(3));
  GLenum format = U(ctx, A(4)), type = U(ctx, A(5));
  /* Reading the multisampled default framebuffer needs a resolve. */
  bool from_default = g->user_read_fbo == 0;
  if (from_default && g->resolve_fbo) {
    gl.BindFramebuffer(GL_READ_FRAMEBUFFER, g->fbo);
    gl.BindFramebuffer(GL_DRAW_FRAMEBUFFER, g->resolve_fbo);
    GLboolean scissor = gl.IsEnabled(GL_SCISSOR_TEST);
    gl.Disable(GL_SCISSOR_TEST);
    gl.BlitFramebuffer(0, 0, g->w, g->h, 0, 0, g->w, g->h, GL_COLOR_BUFFER_BIT, GL_NEAREST);
    if (scissor) gl.Enable(GL_SCISSOR_TEST);
    gl.BindFramebuffer(GL_READ_FRAMEBUFFER, g->resolve_fbo);
  }
  if (JS_IsNull(A(6)) || JS_IsUndefined(A(6))) {
    gl.ReadPixels(x, y, w, h, format, type, (void *)(intptr_t)L(ctx, A(7)));
  } else {
    size_t len = 0, elem = 1;
    uint8_t *p = nx_bytes(ctx, A(6), &len, &elem);
    if (!p) return JS_ThrowTypeError(ctx, "readPixels: invalid destination");
    size_t off = (size_t)L(ctx, A(7)) * elem;
    GLint align = 4;
    gl.GetIntegerv(GL_PACK_ALIGNMENT, &align);
    size_t row = (size_t)w * (size_t)nx_bytes_per_pixel(format, type);
    size_t stride = (row + (size_t)align - 1) / (size_t)align * (size_t)align;
    size_t need = h > 0 ? stride * (size_t)(h - 1) + row : 0;
    if (off > len || need > len - off) return JS_ThrowRangeError(ctx, "readPixels: destination too small");
    gl.ReadPixels(x, y, w, h, format, type, p + off);
  }
  if (from_default && g->resolve_fbo) {
    gl.BindFramebuffer(GL_DRAW_FRAMEBUFFER, g->user_draw_fbo ? g->user_draw_fbo : g->fbo);
    gl.BindFramebuffer(GL_READ_FRAMEBUFFER, g->fbo);
  }
  return JS_UNDEFINED;
}

/* Syncs -------------------------------------------------------------------------- */

#define NX_MAX_SYNCS 1024
static GLsync nx_syncs[NX_MAX_SYNCS];
static __thread int nx_sync_hint = 1;

GLFN(fenceSync) {
  ENTER();
  GLsync s = gl.FenceSync(U(ctx, A(0)), U(ctx, A(1)));
  if (!s) return JS_NewInt32(ctx, 0);
  pthread_mutex_lock(&nx_gl_lock);
  int id = 0;
  for (int k = 0; k < NX_MAX_SYNCS; k++) {
    int i = (nx_sync_hint + k) % NX_MAX_SYNCS;
    if (i && !nx_syncs[i]) {
      nx_syncs[i] = s;
      id = i;
      nx_sync_hint = i + 1;
      break;
    }
  }
  pthread_mutex_unlock(&nx_gl_lock);
  if (!id) gl.DeleteSync(s);
  return JS_NewInt32(ctx, id);
}

static GLsync nx_sync_arg(JSContext *ctx, JSValueConst v) {
  int32_t i = I(ctx, v);
  return i > 0 && i < NX_MAX_SYNCS ? nx_syncs[i] : NULL;
}

GLFN(deleteSync) {
  ENTER();
  int32_t i = I(ctx, A(0));
  if (i > 0 && i < NX_MAX_SYNCS && nx_syncs[i]) {
    gl.DeleteSync(nx_syncs[i]);
    nx_syncs[i] = NULL;
  }
  return JS_UNDEFINED;
}

GLFN(clientWaitSync) {
  ENTER();
  GLsync s = nx_sync_arg(ctx, A(0));
  if (!s) return JS_NewUint32(ctx, GL_WAIT_FAILED);
  return JS_NewUint32(ctx, gl.ClientWaitSync(s, U(ctx, A(1)), (GLuint64)L(ctx, A(2))));
}

GLFN(getSyncParameter) {
  ENTER();
  GLsync s = nx_sync_arg(ctx, A(0));
  if (!s) return JS_NULL;
  GLint v = 0;
  GLsizei n = 0;
  gl.GetSynciv(s, U(ctx, A(1)), 1, &n, &v);
  return JS_NewInt32(ctx, v);
}

/* Image decoding (createImageBitmap) ------------------------------------------- */

/* decodeImage(bytes, flipY, premultiply) -> [bitmapId, width, height] | null */
static JSValue js_decodeImage(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
  (void)this_val;
  (void)argc;
  size_t len = 0, elem = 1;
  uint8_t *p = nx_bytes(ctx, argv[0], &len, &elem);
  if (!p || len == 0 || len > INT32_MAX) return JS_NULL;
  int w = 0, h = 0, comps = 0;
  stbi_uc *rgba = stbi_load_from_memory(p, (int)len, &w, &h, &comps, 4);
  if (!rgba) return JS_NULL;
  size_t n = (size_t)w * (size_t)h * 4;
  /* stb allocates with malloc; ownership moves to the bitmap registry. */
  if (JS_ToBool(ctx, argv[1])) nx_flip_rows(rgba, (size_t)w * 4, h);
  if (JS_ToBool(ctx, argv[2])) nx_premultiply(rgba, n);
  int64_t id = nx_bitmap_add(rgba, w, h);
  JSValue a = JS_NewArray(ctx);
  JS_SetPropertyUint32(ctx, a, 0, JS_NewInt64(ctx, id));
  JS_SetPropertyUint32(ctx, a, 1, JS_NewInt32(ctx, w));
  JS_SetPropertyUint32(ctx, a, 2, JS_NewInt32(ctx, h));
  return a;
}

/* bitmapFromPixels(rgbaView, width, height, flipY, premultiply) -> id */
static JSValue js_bitmapFromPixels(JSContext *ctx, JSValueConst this_val, int argc,
                                   JSValueConst *argv) {
  (void)this_val;
  (void)argc;
  size_t len = 0, elem = 1;
  uint8_t *p = nx_bytes(ctx, argv[0], &len, &elem);
  int32_t w = I(ctx, argv[1]), h = I(ctx, argv[2]);
  size_t n = (size_t)w * (size_t)h * 4;
  if (!p || w <= 0 || h <= 0 || len < n) return JS_ThrowRangeError(ctx, "invalid pixel data");
  uint8_t *copy = (uint8_t *)malloc(n);
  if (!copy) return JS_ThrowOutOfMemory(ctx);
  memcpy(copy, p, n);
  if (JS_ToBool(ctx, argv[3])) nx_flip_rows(copy, (size_t)w * 4, h);
  if (JS_ToBool(ctx, argv[4])) nx_premultiply(copy, n);
  return JS_NewInt64(ctx, nx_bitmap_add(copy, w, h));
}

/* bitmapPixels(id) -> Uint8Array copy of the RGBA8 pixels */
static JSValue js_bitmapPixels(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
  (void)this_val;
  (void)argc;
  NxBitmap *b = nx_bitmap_get(L(ctx, argv[0]));
  if (!b) return JS_NULL;
  return JS_NewUint8ArrayCopy(ctx, b->rgba, (size_t)b->w * (size_t)b->h * 4);
}

static JSValue js_bitmapFree(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
  (void)this_val;
  (void)argc;
  nx_bitmap_free(L(ctx, argv[0]));
  return JS_UNDEFINED;
}

/* Surfaces from script --------------------------------------------------------- */

static JSValue js_surfaceCreate(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
  (void)this_val;
  (void)argc;
  (void)argv;
  return JS_NewInt64(ctx, nx_surface_create());
}

static JSValue js_surfaceRetain(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
  (void)this_val;
  (void)argc;
  nx_surface_retain(L(ctx, argv[0]));
  return JS_UNDEFINED;
}

static JSValue js_surfaceRelease(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
  (void)this_val;
  (void)argc;
  nx_surface_release(L(ctx, argv[0]));
  return JS_UNDEFINED;
}

/* Registration ------------------------------------------------------------------ */

#define FN(name, n) JS_CFUNC_DEF(#name, n, js_##name)
static const JSCFunctionListEntry nx_gl_funcs[] = {
    FN(createContext, 10), FN(destroyContext, 1), FN(resize, 3), FN(present, 1), FN(setLost, 2),
    FN(error, 0), FN(bindFramebuffer, 3),
    FN(activeTexture, 2), FN(attachShader, 3), FN(beginQuery, 3), FN(beginTransformFeedback, 2),
    FN(bindBuffer, 3), FN(bindBufferBase, 4), FN(bindBufferRange, 6), FN(bindRenderbuffer, 3),
    FN(bindSampler, 3), FN(bindTexture, 3), FN(bindTransformFeedback, 3), FN(bindVertexArray, 2),
    FN(blendColor, 5), FN(blendEquation, 2), FN(blendEquationSeparate, 3), FN(blendFunc, 3),
    FN(blendFuncSeparate, 5), FN(blitFramebuffer, 11), FN(clear, 2), FN(clearBufferfi, 5),
    FN(clearColor, 5), FN(clearDepth, 2), FN(clearStencil, 2), FN(colorMask, 5), FN(compileShader, 2),
    FN(copyBufferSubData, 6), FN(copyTexImage2D, 9), FN(copyTexSubImage2D, 9), FN(copyTexSubImage3D, 10),
    FN(cullFace, 2), FN(depthFunc, 2), FN(depthMask, 2), FN(depthRange, 3), FN(detachShader, 3),
    FN(disable, 2), FN(disableVertexAttribArray, 2), FN(drawArrays, 4), FN(drawArraysInstanced, 5),
    FN(drawElements, 5), FN(drawElementsInstanced, 6), FN(drawRangeElements, 7), FN(enable, 2),
    FN(enableVertexAttribArray, 2), FN(endQuery, 2), FN(endTransformFeedback, 1), FN(finish, 1),
    FN(flush, 1), FN(framebufferRenderbuffer, 5), FN(framebufferTexture2D, 6),
    FN(framebufferTextureLayer, 6), FN(frontFace, 2), FN(generateMipmap, 2), FN(hint, 3),
    FN(lineWidth, 2), FN(linkProgram, 2), FN(pauseTransformFeedback, 1), FN(polygonOffset, 3),
    FN(readBuffer, 2), FN(renderbufferStorage, 5), FN(renderbufferStorageMultisample, 6),
    FN(resumeTransformFeedback, 1), FN(sampleCoverage, 3), FN(samplerParameterf, 4),
    FN(samplerParameteri, 4), FN(scissor, 5), FN(stencilFunc, 4), FN(stencilFuncSeparate, 5),
    FN(stencilMask, 2), FN(stencilMaskSeparate, 3), FN(stencilOp, 4), FN(stencilOpSeparate, 5),
    FN(texParameterf, 4), FN(texParameteri, 4), FN(texStorage2D, 6), FN(texStorage3D, 7),
    FN(uniform1f, 3), FN(uniform2f, 4), FN(uniform3f, 5), FN(uniform4f, 6), FN(uniform1i, 3),
    FN(uniform2i, 4), FN(uniform3i, 5), FN(uniform4i, 6), FN(uniform1ui, 3), FN(uniform2ui, 4),
    FN(uniform3ui, 5), FN(uniform4ui, 6), FN(uniformBlockBinding, 4), FN(useProgram, 2),
    FN(validateProgram, 2), FN(vertexAttrib1f, 3), FN(vertexAttrib2f, 4), FN(vertexAttrib3f, 5),
    FN(vertexAttrib4f, 6), FN(vertexAttribI4i, 6), FN(vertexAttribI4ui, 6), FN(vertexAttribDivisor, 3),
    FN(vertexAttribIPointer, 6), FN(vertexAttribPointer, 7), FN(viewport, 5), FN(deleteProgram, 2),
    FN(deleteShader, 2), FN(createBuffer, 1), FN(createFramebuffer, 1), FN(createQuery, 1),
    FN(createRenderbuffer, 1), FN(createSampler, 1), FN(createTexture, 1), FN(createTransformFeedback, 1),
    FN(createVertexArray, 1), FN(deleteBuffer, 2), FN(deleteQuery, 2), FN(deleteRenderbuffer, 2),
    FN(deleteSampler, 2), FN(deleteTexture, 2), FN(deleteTransformFeedback, 2), FN(deleteVertexArray, 2),
    FN(deleteFramebuffer, 2), FN(createProgram, 1), FN(createShader, 2), FN(getError, 1),
    FN(isEnabled, 2), FN(checkFramebufferStatus, 2), FN(getIntegerv, 3), FN(getInteger64v, 2),
    FN(getFloatv, 3), FN(getBooleanv, 3), FN(getString, 2), FN(getExtensions, 1),
    FN(getIndexedParameter, 3), FN(getShaderParameter, 3), FN(getProgramParameter, 3),
    FN(getBufferParameter, 3), FN(getRenderbufferParameter, 3), FN(getTexParameteri, 3),
    FN(getTexParameterf, 3), FN(getFramebufferAttachmentParameter, 4), FN(getQuery, 3),
    FN(getQueryParameter, 3), FN(getSamplerParameteri, 3), FN(getSamplerParameterf, 3),
    FN(getVertexAttribi, 3), FN(getVertexAttribf4, 3), FN(getActiveUniformBlockParameteri, 4),
    FN(getShaderPrecisionFormat, 3), FN(getInternalformatParameter, 4), FN(shaderSource, 3),
    FN(getShaderInfoLog, 2), FN(getProgramInfoLog, 2), FN(getShaderSource, 2),
    FN(getUniformLocation, 3), FN(getAttribLocation, 3), FN(getFragDataLocation, 3),
    FN(getUniformBlockIndex, 3), FN(bindAttribLocation, 4), FN(getActiveAttrib, 3),
    FN(getActiveUniform, 3), FN(getTransformFeedbackVarying, 3), FN(getActiveUniformBlockName, 3),
    FN(getActiveUniformBlockIndices, 3), FN(getActiveUniforms, 4), FN(getUniformIndices, 3),
    FN(transformFeedbackVaryings, 4), FN(drawBuffers, 2), FN(invalidateFramebuffer, 3),
    FN(bufferData, 6), FN(bufferSubData, 6), FN(getBufferSubData, 6), FN(uniformv, 6),
    FN(uniformMatrix, 7), FN(vertexAttrib4fv, 3), FN(clearBufferv, 6), FN(pixelStorei, 3),
    FN(texImage2D, 11), FN(texImage2DOffset, 10), FN(texSubImage2D, 11), FN(texImage3D, 12),
    FN(texSubImage3D, 13), FN(compressedTexImage2D, 10), FN(compressedTexSubImage2D, 11),
    FN(compressedTexImage3D, 11), FN(compressedTexSubImage3D, 13), FN(texImageBitmap, 10),
    FN(readPixels, 9), FN(fenceSync, 3), FN(deleteSync, 2), FN(clientWaitSync, 4),
    FN(getSyncParameter, 3), FN(decodeImage, 3), FN(bitmapFromPixels, 5), FN(bitmapPixels, 1),
    FN(bitmapFree, 1), FN(surfaceCreate, 0), FN(surfaceRetain, 1), FN(surfaceRelease, 1),
};

void nx_gl_install(JSContext *ctx) {
  JSValue obj = JS_NewObjectProto(ctx, JS_NULL);
  JS_SetPropertyFunctionList(ctx, obj, nx_gl_funcs, sizeof nx_gl_funcs / sizeof nx_gl_funcs[0]);
  JSValue global = JS_GetGlobalObject(ctx);
  JS_SetPropertyStr(ctx, global, "__nx_gl_native", obj);
  JS_FreeValue(ctx, global);
}
