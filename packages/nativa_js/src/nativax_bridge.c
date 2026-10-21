#include "nativax_bridge.h"

#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
#else
#include <pthread.h>
#include <time.h>
#endif

#include "quickjs.h"
#include "nativax_gl.h"
#include "nativax_runtime_internal.h"
#include "nativax_wasm.h"

static int64_t nx_now_ms(void) {
#if defined(_WIN32)
  return (int64_t)GetTickCount64();
#else
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
#endif
}

void *nx_alloc(int64_t size) { return malloc(size > 0 ? (size_t)size : 1); }

void nx_free(void *ptr) { free(ptr); }

static void nx_store(const char *data, size_t len, char **out,
                     int64_t *out_len) {
  char *buf = (char *)nx_alloc((int64_t)len + 1);
  if (len > 0) memcpy(buf, data, len);
  buf[len] = '\0';
  *out = buf;
  *out_len = (int64_t)len;
}

static int nx_interrupt(JSRuntime *rt, void *opaque) {
  (void)rt;
  NxRuntime *nx = (NxRuntime *)opaque;
  return nx->deadline_ms != 0 && nx_now_ms() > nx->deadline_ms;
}

/* JSON-serializes `value` into *out. Non-serializable values produce "". */
static void nx_serialize(JSContext *ctx, JSValueConst value, char **out,
                         int64_t *out_len) {
  JSValue json = JS_JSONStringify(ctx, value, JS_UNDEFINED, JS_UNDEFINED);
  if (JS_IsException(json)) {
    JS_FreeValue(ctx, JS_GetException(ctx));
    nx_store("", 0, out, out_len);
    return;
  }
  if (JS_IsUndefined(json)) {
    nx_store("", 0, out, out_len);
    return;
  }
  size_t len = 0;
  const char *str = JS_ToCStringLen(ctx, &len, json);
  JS_FreeValue(ctx, json);
  if (str == NULL) {
    JS_FreeValue(ctx, JS_GetException(ctx));
    nx_store("", 0, out, out_len);
    return;
  }
  nx_store(str, len, out, out_len);
  JS_FreeCString(ctx, str);
}

static void nx_copy_string_prop(JSContext *ctx, JSValueConst from,
                                JSValueConst to, const char *name) {
  JSValue v = JS_GetPropertyStr(ctx, from, name);
  if (JS_IsException(v)) {
    JS_FreeValue(ctx, JS_GetException(ctx));
    return;
  }
  if (!JS_IsUndefined(v) && !JS_IsNull(v)) {
    JSValue s = JS_ToString(ctx, v);
    if (JS_IsException(s)) {
      JS_FreeValue(ctx, JS_GetException(ctx));
    } else {
      JS_SetPropertyStr(ctx, to, name, s);
    }
  }
  JS_FreeValue(ctx, v);
}

/* Takes the pending exception and serializes it as an error descriptor. */
static void nx_take_exception(JSContext *ctx, char **out, int64_t *out_len) {
  JSValue exc = JS_GetException(ctx);
  int uncatchable = JS_IsUncatchableError(exc);
  JSValue desc = JS_NewObject(ctx);
  if (JS_IsError(exc)) {
    nx_copy_string_prop(ctx, exc, desc, "name");
    nx_copy_string_prop(ctx, exc, desc, "message");
    nx_copy_string_prop(ctx, exc, desc, "stack");
  } else {
    JSValue s = JS_ToString(ctx, exc);
    if (JS_IsException(s)) {
      JS_FreeValue(ctx, JS_GetException(ctx));
      s = JS_NewString(ctx, "<unprintable exception>");
    }
    JS_SetPropertyStr(ctx, desc, "name", JS_NewString(ctx, "Error"));
    JS_SetPropertyStr(ctx, desc, "message", s);
  }
  JS_SetPropertyStr(ctx, desc, "uncatchable", JS_NewBool(ctx, uncatchable));
  JS_FreeValue(ctx, exc);
  nx_serialize(ctx, desc, out, out_len);
  JS_FreeValue(ctx, desc);
}

/* --- Native buffer handoff -------------------------------------------------
 * Byte buffers move between Dart and script code (and later between
 * runtimes on different threads) without JSON or base64: the producer parks
 * malloc'd memory under an id and the consumer adopts it. The registry is
 * process-wide and guarded by a mutex. */

typedef struct NxParked {
  int64_t id;
  uint8_t *data;
  size_t len;
  struct NxParked *next;
} NxParked;

#if defined(_WIN32)
static SRWLOCK nx_park_lock = SRWLOCK_INIT;
#define NX_LOCK() AcquireSRWLockExclusive(&nx_park_lock)
#define NX_UNLOCK() ReleaseSRWLockExclusive(&nx_park_lock)
#else
static pthread_mutex_t nx_park_lock = PTHREAD_MUTEX_INITIALIZER;
#define NX_LOCK() pthread_mutex_lock(&nx_park_lock)
#define NX_UNLOCK() pthread_mutex_unlock(&nx_park_lock)
#endif

static NxParked *nx_parked = NULL;
static int64_t nx_next_park_id = 1;

int64_t nx_buffer_put(void *data, int64_t len) {
  NxParked *p = (NxParked *)malloc(sizeof(NxParked));
  if (p == NULL) return 0;
  p->data = (uint8_t *)data;
  p->len = len > 0 ? (size_t)len : 0;
  NX_LOCK();
  p->id = nx_next_park_id++;
  p->next = nx_parked;
  nx_parked = p;
  NX_UNLOCK();
  return p->id;
}

void *nx_buffer_take(int64_t id, int64_t *len) {
  NxParked *found = NULL;
  NX_LOCK();
  for (NxParked **pp = &nx_parked; *pp != NULL; pp = &(*pp)->next) {
    if ((*pp)->id == id) {
      found = *pp;
      *pp = found->next;
      break;
    }
  }
  NX_UNLOCK();
  if (found == NULL) {
    *len = -1;
    return NULL;
  }
  void *data = found->data;
  *len = (int64_t)found->len;
  free(found);
  return data;
}

static void *nx_adopted_realloc(JSRuntime *rt, void *opaque, void *ptr,
                                size_t size) {
  (void)rt;
  (void)opaque;
  if (size == 0) {
    free(ptr);
    return NULL;
  }
  return realloc(ptr, size);
}

/* __nx_buffer_take(id) -> ArrayBuffer adopting the parked bytes. */
static JSValue nx_buffer_take_call(JSContext *ctx, JSValueConst this_val,
                                   int argc, JSValueConst *argv) {
  (void)this_val;
  int64_t id = 0;
  if (argc < 1 || JS_ToInt64(ctx, &id, argv[0]) < 0) return JS_EXCEPTION;
  int64_t len = 0;
  uint8_t *data = (uint8_t *)nx_buffer_take(id, &len);
  if (len < 0) return JS_ThrowReferenceError(ctx, "unknown buffer %lld", (long long)id);
  if (data == NULL) data = (uint8_t *)malloc(1);
  return JS_NewArrayBuffer(ctx, data, (size_t)len, 0, nx_adopted_realloc, NULL, false);
}

/* __nx_buffer_put(ArrayBuffer | view) -> id of a copy of its bytes. */
static JSValue nx_buffer_put_call(JSContext *ctx, JSValueConst this_val,
                                  int argc, JSValueConst *argv) {
  (void)this_val;
  if (argc < 1) return JS_ThrowTypeError(ctx, "buffer expected");
  size_t len = 0;
  /* ArrayBuffer or SharedArrayBuffer first, then any typed array view. */
  uint8_t *src = JS_GetArrayBuffer(ctx, &len, argv[0]);
  if (src == NULL) {
    JS_FreeValue(ctx, JS_GetException(ctx));
    size_t offset = 0, bytes_per = 0;
    JSValue ab = JS_GetTypedArrayBuffer(ctx, argv[0], &offset, &len, &bytes_per);
    if (JS_IsException(ab)) return JS_ThrowTypeError(ctx, "ArrayBuffer or view expected");
    size_t ab_len = 0;
    uint8_t *base = JS_GetArrayBuffer(ctx, &ab_len, ab);
    JS_FreeValue(ctx, ab);
    if (base == NULL) return JS_EXCEPTION;
    src = base + offset;
  }
  uint8_t *copy = (uint8_t *)malloc(len > 0 ? len : 1);
  if (copy == NULL) return JS_ThrowOutOfMemory(ctx);
  if (len > 0) memcpy(copy, src, len);
  return JS_NewInt64(ctx, nx_buffer_put(copy, (int64_t)len));
}

/* --- SharedArrayBuffer across runtimes ---------------------------------------
 * SAB memory carries a header with an atomic reference count, so the same
 * bytes can back SharedArrayBuffer objects in several runtimes (one per
 * worker thread) and is freed when the last one is collected. */

typedef struct {
  volatile int64_t refs;
  size_t len;
} NxSabHeader;

#define NX_SAB_HEADER ((sizeof(NxSabHeader) + 15) & ~(size_t)15)

#if defined(_WIN32)
#define NX_ATOMIC_INC(p) InterlockedIncrement64((volatile LONG64 *)(p))
#define NX_ATOMIC_DEC(p) InterlockedDecrement64((volatile LONG64 *)(p))
#else
#define NX_ATOMIC_INC(p) __atomic_add_fetch((p), 1, __ATOMIC_SEQ_CST)
#define NX_ATOMIC_DEC(p) __atomic_sub_fetch((p), 1, __ATOMIC_SEQ_CST)
#endif

static NxSabHeader *nx_sab_header(void *data) {
  return (NxSabHeader *)((uint8_t *)data - NX_SAB_HEADER);
}

static void *nx_sab_alloc(void *opaque, size_t size) {
  (void)opaque;
  uint8_t *block = (uint8_t *)calloc(1, NX_SAB_HEADER + size);
  if (block == NULL) return NULL;
  NxSabHeader *h = (NxSabHeader *)block;
  h->refs = 1;
  h->len = size;
  return block + NX_SAB_HEADER;
}

static void nx_sab_dup(void *opaque, void *ptr) {
  (void)opaque;
  NX_ATOMIC_INC(&nx_sab_header(ptr)->refs);
}

static void nx_sab_free(void *opaque, void *ptr) {
  (void)opaque;
  NxSabHeader *h = nx_sab_header(ptr);
  if (NX_ATOMIC_DEC(&h->refs) == 0) free(h);
}

static const JSSharedArrayBufferFunctions nx_sab_functions = {
    nx_sab_alloc, nx_sab_free, nx_sab_dup, NULL};

/* Parked SAB references for transfer between runtimes. */
typedef struct NxSharedParked {
  int64_t id;
  void *data;
  size_t len;
  struct NxSharedParked *next;
} NxSharedParked;

static NxSharedParked *nx_shared_parked = NULL;

/* __nx_sab_share(sab) -> id holding one reference to its memory. Each id
 * can be opened once. */
static JSValue nx_sab_share_call(JSContext *ctx, JSValueConst this_val,
                                 int argc, JSValueConst *argv) {
  (void)this_val;
  size_t len = 0;
  uint8_t *data = argc > 0 ? JS_GetArrayBuffer(ctx, &len, argv[0]) : NULL;
  if (data == NULL) return JS_EXCEPTION;
  NxSharedParked *p = (NxSharedParked *)malloc(sizeof(NxSharedParked));
  if (p == NULL) return JS_ThrowOutOfMemory(ctx);
  nx_sab_dup(NULL, data);
  p->data = data;
  p->len = len;
  NX_LOCK();
  p->id = nx_next_park_id++;
  p->next = nx_shared_parked;
  nx_shared_parked = p;
  NX_UNLOCK();
  return JS_NewInt64(ctx, p->id);
}

/* __nx_sab_open(id) -> SharedArrayBuffer over the shared memory. */
static JSValue nx_sab_open_call(JSContext *ctx, JSValueConst this_val,
                                int argc, JSValueConst *argv) {
  (void)this_val;
  int64_t id = 0;
  if (argc < 1 || JS_ToInt64(ctx, &id, argv[0]) < 0) return JS_EXCEPTION;
  NxSharedParked *found = NULL;
  NX_LOCK();
  for (NxSharedParked **pp = &nx_shared_parked; *pp != NULL; pp = &(*pp)->next) {
    if ((*pp)->id == id) {
      found = *pp;
      *pp = found->next;
      break;
    }
  }
  NX_UNLOCK();
  if (found == NULL) return JS_ThrowReferenceError(ctx, "unknown shared buffer");
  /* JS_NewArrayBuffer takes its own reference (sab_dup); drop the parked one. */
  JSValue sab = JS_NewArrayBuffer(ctx, (uint8_t *)found->data, found->len, 0,
                                  NULL, NULL, true);
  nx_sab_free(NULL, found->data);
  free(found);
  return sab;
}

/* globalThis.__nx_host(request: string) -> parsed JSON response | undefined */
static JSValue nx_host_call(JSContext *ctx, JSValueConst this_val, int argc,
                            JSValueConst *argv) {
  (void)this_val;
  NxRuntime *nx = (NxRuntime *)JS_GetContextOpaque(ctx);
  if (argc < 1 || !JS_IsString(argv[0])) {
    return JS_ThrowTypeError(ctx, "__nx_host expects a string");
  }
  size_t len = 0;
  const char *req = JS_ToCStringLen(ctx, &len, argv[0]);
  if (req == NULL) return JS_EXCEPTION;
  char *resp = NULL;
  int64_t resp_len = 0;
  nx->host(nx->id, req, (int64_t)len, &resp, &resp_len);
  JS_FreeCString(ctx, req);
  if (resp == NULL) {
    return JS_ThrowInternalError(ctx, "host returned no response");
  }
  JSValue result = JS_UNDEFINED;
  if (resp_len > 0) {
    result = JS_ParseJSON(ctx, resp, (size_t)resp_len, "<host>");
  }
  nx_free(resp);
  return result;
}

/* globalThis.__nx_register(name: string, fn: function): stores a callback
 * in the runtime's private registry. The host prelude captures and removes
 * this function before any document script runs. */
static JSValue nx_register_call(JSContext *ctx, JSValueConst this_val,
                                int argc, JSValueConst *argv) {
  (void)this_val;
  NxRuntime *nx = (NxRuntime *)JS_GetContextOpaque(ctx);
  if (argc < 2 || !JS_IsString(argv[0]) || !JS_IsFunction(ctx, argv[1])) {
    return JS_ThrowTypeError(ctx, "__nx_register expects (name, function)");
  }
  const char *name = JS_ToCString(ctx, argv[0]);
  if (name == NULL) return JS_EXCEPTION;
  JS_SetPropertyStr(ctx, nx->callbacks, name, JS_DupValue(ctx, argv[1]));
  JS_FreeCString(ctx, name);
  return JS_UNDEFINED;
}

/* Sends `["__module", [op, ...args]]` to the host and returns the `ok`
 * value of its reply, or JS_EXCEPTION (with a pending exception). */
static JSValue nx_module_request(JSContext *ctx, const char *op,
                                 const char *a, const char *b) {
  NxRuntime *nx = (NxRuntime *)JS_GetContextOpaque(ctx);
  JSValue req = JS_NewArray(ctx);
  JSValue args = JS_NewArray(ctx);
  JS_SetPropertyUint32(ctx, args, 0, JS_NewString(ctx, op));
  if (a) JS_SetPropertyUint32(ctx, args, 1, JS_NewString(ctx, a));
  if (b) JS_SetPropertyUint32(ctx, args, 2, JS_NewString(ctx, b));
  JS_SetPropertyUint32(ctx, req, 0, JS_NewString(ctx, "__module"));
  JS_SetPropertyUint32(ctx, req, 1, args);
  char *text = NULL;
  int64_t text_len = 0;
  nx_serialize(ctx, req, &text, &text_len);
  JS_FreeValue(ctx, req);
  char *resp = NULL;
  int64_t resp_len = 0;
  nx->host(nx->id, text, text_len, &resp, &resp_len);
  nx_free(text);
  if (resp == NULL || resp_len == 0) {
    if (resp) nx_free(resp);
    return JS_ThrowInternalError(ctx, "module host returned no response");
  }
  JSValue reply = JS_ParseJSON(ctx, resp, (size_t)resp_len, "<host>");
  nx_free(resp);
  if (JS_IsException(reply)) return reply;
  JSValue err = JS_GetPropertyStr(ctx, reply, "error");
  if (!JS_IsUndefined(err)) {
    JSValue msg = JS_GetPropertyStr(ctx, err, "message");
    const char *m = JS_ToCString(ctx, msg);
    JS_ThrowTypeError(ctx, "%s", m ? m : "module error");
    if (m) JS_FreeCString(ctx, m);
    JS_FreeValue(ctx, msg);
    JS_FreeValue(ctx, err);
    JS_FreeValue(ctx, reply);
    return JS_EXCEPTION;
  }
  JS_FreeValue(ctx, err);
  JSValue ok = JS_GetPropertyStr(ctx, reply, "ok");
  JS_FreeValue(ctx, reply);
  return ok;
}

/* Resolves `name` against the importing module's URL through the host. */
static char *nx_module_normalize(JSContext *ctx, const char *base,
                                 const char *name, void *opaque) {
  (void)opaque;
  JSValue url = nx_module_request(ctx, "resolve", base, name);
  if (JS_IsException(url)) return NULL;
  const char *s = JS_ToCString(ctx, url);
  JS_FreeValue(ctx, url);
  if (s == NULL) return NULL;
  char *copy = js_strdup(ctx, s);
  JS_FreeCString(ctx, s);
  return copy;
}

/* Fetches a module's source from the host (which prefetched it), compiles
 * it and sets `import.meta.url`. */
static JSModuleDef *nx_module_loader(JSContext *ctx, const char *module_name,
                                     void *opaque) {
  (void)opaque;
  JSValue source = nx_module_request(ctx, "source", module_name, NULL);
  if (JS_IsException(source)) return NULL;
  if (!JS_IsString(source)) {
    JS_FreeValue(ctx, source);
    JS_ThrowReferenceError(ctx, "could not load module '%s'", module_name);
    return NULL;
  }
  size_t len = 0;
  const char *code = JS_ToCStringLen(ctx, &len, source);
  JS_FreeValue(ctx, source);
  if (code == NULL) return NULL;
  JSValue func = JS_Eval(ctx, code, len, module_name,
                         JS_EVAL_TYPE_MODULE | JS_EVAL_FLAG_COMPILE_ONLY);
  JS_FreeCString(ctx, code);
  if (JS_IsException(func)) return NULL;
  JSModuleDef *m = (JSModuleDef *)JS_VALUE_GET_PTR(func);
  JSValue meta = JS_GetImportMeta(ctx, m);
  if (!JS_IsException(meta)) {
    JS_DefinePropertyValueStr(ctx, meta, "url", JS_NewString(ctx, module_name),
                              JS_PROP_C_W_E);
    JS_FreeValue(ctx, meta);
  }
  JS_FreeValue(ctx, func);
  return m;
}

NxRuntime *nx_runtime_new(int64_t runtime_id, int64_t memory_limit,
                          int64_t stack_size, NxHostCallback host) {
  NxRuntime *nx = (NxRuntime *)calloc(1, sizeof(NxRuntime));
  if (nx == NULL) return NULL;
  nx->id = runtime_id;
  nx->host = host;
  nx->rt = JS_NewRuntime();
  if (nx->rt == NULL) {
    free(nx);
    return NULL;
  }
  if (memory_limit > 0) JS_SetMemoryLimit(nx->rt, (size_t)memory_limit);
  if (stack_size > 0) JS_SetMaxStackSize(nx->rt, (size_t)stack_size);
  JS_SetInterruptHandler(nx->rt, nx_interrupt, nx);
  JS_SetModuleLoaderFunc(nx->rt, nx_module_normalize, nx_module_loader, nx);
  JS_SetSharedArrayBufferFunctions(nx->rt, &nx_sab_functions);
  nx->ctx = JS_NewContext(nx->rt);
  if (nx->ctx == NULL) {
    JS_FreeRuntime(nx->rt);
    free(nx);
    return NULL;
  }
  JS_SetContextOpaque(nx->ctx, nx);
  nx->callbacks = JS_NewObjectProto(nx->ctx, JS_NULL);
  JSValue global = JS_GetGlobalObject(nx->ctx);
  JS_SetPropertyStr(nx->ctx, global, "__nx_host",
                    JS_NewCFunction(nx->ctx, nx_host_call, "__nx_host", 1));
  JS_SetPropertyStr(nx->ctx, global, "__nx_register",
                    JS_NewCFunction(nx->ctx, nx_register_call, "__nx_register", 2));
  JS_SetPropertyStr(nx->ctx, global, "__nx_buffer_take",
                    JS_NewCFunction(nx->ctx, nx_buffer_take_call, "__nx_buffer_take", 1));
  JS_SetPropertyStr(nx->ctx, global, "__nx_buffer_put",
                    JS_NewCFunction(nx->ctx, nx_buffer_put_call, "__nx_buffer_put", 1));
  JS_SetPropertyStr(nx->ctx, global, "__nx_sab_share",
                    JS_NewCFunction(nx->ctx, nx_sab_share_call, "__nx_sab_share", 1));
  JS_SetPropertyStr(nx->ctx, global, "__nx_sab_open",
                    JS_NewCFunction(nx->ctx, nx_sab_open_call, "__nx_sab_open", 1));
  nx_gl_install(nx->ctx);
  nx_wasm_install(nx);
  JS_FreeValue(nx->ctx, global);
  return nx;
}

void nx_runtime_free(NxRuntime *nx) {
  if (nx == NULL) return;
  nx_wasm_free(nx);
  JS_FreeValue(nx->ctx, nx->callbacks);
  JS_FreeContext(nx->ctx);
  JS_FreeRuntime(nx->rt);
  free(nx);
}

void nx_set_can_block(NxRuntime *nx, int32_t can_block) {
  JS_SetCanBlock(nx->rt, can_block != 0);
}

void nx_set_budget_ms(NxRuntime *nx, int64_t budget_ms) {
  nx->deadline_ms = budget_ms > 0 ? nx_now_ms() + budget_ms : 0;
}

static int32_t nx_finish(NxRuntime *nx, JSValue result, char **out,
                         int64_t *out_len) {
  if (JS_IsException(result)) {
    nx_take_exception(nx->ctx, out, out_len);
    return NX_EXCEPTION;
  }
  nx_serialize(nx->ctx, result, out, out_len);
  JS_FreeValue(nx->ctx, result);
  return NX_OK;
}

int32_t nx_eval(NxRuntime *nx, const char *source, int64_t len,
                const char *filename, char **out, int64_t *out_len) {
  JS_UpdateStackTop(nx->rt);
  JSValue result = JS_Eval(nx->ctx, source, (size_t)len,
                           filename ? filename : "<nativax>",
                           JS_EVAL_TYPE_GLOBAL);
  return nx_finish(nx, result, out, out_len);
}

int32_t nx_eval_module(NxRuntime *nx, const char *source, int64_t len,
                       const char *url, char **out, int64_t *out_len) {
  JS_UpdateStackTop(nx->rt);
  JSContext *ctx = nx->ctx;
  const char *name = url ? url : "<module>";
  JSValue func = JS_Eval(ctx, source, (size_t)len, name,
                         JS_EVAL_TYPE_MODULE | JS_EVAL_FLAG_COMPILE_ONLY);
  if (JS_IsException(func)) return nx_finish(nx, func, out, out_len);
  JSModuleDef *m = (JSModuleDef *)JS_VALUE_GET_PTR(func);
  JSValue meta = JS_GetImportMeta(ctx, m);
  if (!JS_IsException(meta)) {
    JS_DefinePropertyValueStr(ctx, meta, "url", JS_NewString(ctx, name),
                              JS_PROP_C_W_E);
    JS_FreeValue(ctx, meta);
  }
  if (JS_ResolveModule(ctx, func) < 0) {
    JS_FreeValue(ctx, func);
    return nx_finish(nx, JS_EXCEPTION, out, out_len);
  }
  JSValue result = JS_EvalFunction(ctx, func);
  if (JS_IsException(result)) return nx_finish(nx, result, out, out_len);
  /* Module evaluation returns a promise (top-level await). Rejections are
   * reported through the host's registered "__nx_module_error" callback. */
  if (JS_IsPromise(result)) {
    JSValue handler = JS_GetPropertyStr(ctx, nx->callbacks, "__nx_module_error");
    if (JS_IsFunction(ctx, handler)) {
      JSAtom catch_atom = JS_NewAtom(ctx, "catch");
      JSValue r = JS_Invoke(ctx, result, catch_atom, 1, &handler);
      JS_FreeAtom(ctx, catch_atom);
      JS_FreeValue(ctx, r);
    }
    JS_FreeValue(ctx, handler);
  }
  JS_FreeValue(ctx, result);
  nx_store("", 0, out, out_len);
  return NX_OK;
}

int32_t nx_call(NxRuntime *nx, const char *function_name, const char *json_arg,
                int64_t len, char **out, int64_t *out_len) {
  JS_UpdateStackTop(nx->rt);
  JSContext *ctx = nx->ctx;
  JSValue global = JS_GetGlobalObject(ctx);
  JSValue fn = JS_GetPropertyStr(ctx, nx->callbacks, function_name);
  if (!JS_IsFunction(ctx, fn)) {
    JS_FreeValue(ctx, fn);
    fn = JS_GetPropertyStr(ctx, global, function_name);
  }
  if (!JS_IsFunction(ctx, fn)) {
    JS_FreeValue(ctx, fn);
    JS_FreeValue(ctx, global);
    JS_ThrowTypeError(ctx, "%s is not a function", function_name);
    return nx_finish(nx, JS_EXCEPTION, out, out_len);
  }
  JSValue arg = len > 0 ? JS_ParseJSON(ctx, json_arg, (size_t)len, "<arg>")
                        : JS_UNDEFINED;
  if (JS_IsException(arg)) {
    JS_FreeValue(ctx, fn);
    JS_FreeValue(ctx, global);
    return nx_finish(nx, JS_EXCEPTION, out, out_len);
  }
  JSValue result = JS_Call(ctx, fn, global, 1, &arg);
  JS_FreeValue(ctx, arg);
  JS_FreeValue(ctx, fn);
  JS_FreeValue(ctx, global);
  return nx_finish(nx, result, out, out_len);
}

int32_t nx_run_jobs(NxRuntime *nx, int32_t max_jobs, char **out,
                    int64_t *out_len) {
  JS_UpdateStackTop(nx->rt);
  int32_t executed = 0;
  *out = NULL;
  *out_len = 0;
  while (executed < max_jobs && JS_IsJobPending(nx->rt)) {
    JSContext *job_ctx = NULL;
    int r = JS_ExecutePendingJob(nx->rt, &job_ctx);
    if (r < 0) {
      nx_take_exception(job_ctx ? job_ctx : nx->ctx, out, out_len);
      return -1;
    }
    if (r == 0) break;
    executed++;
  }
  return executed;
}

int32_t nx_has_pending_jobs(NxRuntime *nx) {
  return JS_IsJobPending(nx->rt) ? 1 : 0;
}

void nx_run_gc(NxRuntime *nx) { JS_RunGC(nx->rt); }

int64_t nx_memory_used(NxRuntime *nx) {
  JSMemoryUsage usage;
  JS_ComputeMemoryUsage(nx->rt, &usage);
  return usage.memory_used_size;
}
