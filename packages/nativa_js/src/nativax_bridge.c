#include "nativax_bridge.h"

#include <stdlib.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
#else
#include <pthread.h>
#include <time.h>
#endif

#include "nativax_gl.h"
#include "nativax_wasm.h"

#include <JavaScriptCore/JavaScript.h>

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

/* JSON-serializes `value` into *out. Non-serializable values produce "". */
static void nx_serialize(JSContextRef ctx, JSValueRef value, char **out,
                         int64_t *out_len) {
  JSValueRef exc = NULL;
  JSStringRef json = JSValueCreateJSONString(ctx, value, 0, &exc);
  if (json == NULL) {
    nx_store("", 0, out, out_len);
    if (exc) {
      // swallow
    }
    return;
  }
  size_t len = JSStringGetMaximumUTF8CStringSize(json);
  char *buf = (char *)nx_alloc((int64_t)len);
  size_t written = JSStringGetUTF8CString(json, buf, len);
  if (written == 0) {
    nx_store("", 0, out, out_len);
  } else {
    nx_store(buf, written > 0 ? written - 1 : 0, out, out_len);
  }
  nx_free(buf);
  JSStringRelease(json);
}

static void nx_copy_string_prop(JSContextRef ctx, JSValueRef from,
                                JSObjectRef to, const char *name) {
  JSStringRef pname = JSStringCreateWithUTF8CString(name);
  JSValueRef v = JSObjectGetProperty(ctx, from, pname, NULL);
  if (v && !JSValueIsUndefined(ctx, v) && !JSValueIsNull(ctx, v)) {
    JSStringRef s = JSValueToStringCopy(ctx, v, NULL);
    if (s) {
      JSObjectSetProperty(ctx, to, pname, JSValueMakeString(ctx, s), kJSPropertyAttributeNone, NULL);
      JSStringRelease(s);
    }
  }
  if (pname) JSStringRelease(pname);
}

/* Takes the pending exception and serializes it as an error descriptor. */
static void nx_take_exception(JSContextRef ctx, char **out, int64_t *out_len) {
  // The exception is passed in via JSValueRef? We'll handle by caller providing ctx only;
  // JSC stores last exception? We require caller to pass exception value. This helper
  // assumes *out already... We'll restructure: callers pass exception JSValueRef.
}

/* We'll implement exception handling inline instead. */

/* --- Native buffer handoff (same as before) --- */
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

/* Runtime struct */
struct NxRuntime {
  int64_t id;
  NxHostCallback host;
  JSGlobalContextRef ctx;
  JSObjectRef global;
  JSObjectRef callbacks;
  int64_t deadline_ms;
  int32_t can_block;
};

static void nx_host_dispatch(NxRuntime *nx, const char *req, int64_t len,
                             char **resp, int64_t *resp_len) {
  nx->host(nx->id, req, len, resp, resp_len);
}

#define NX_MAX_RUNTIMES 1024
static NxRuntime *nx_registry[NX_MAX_RUNTIMES];
static int nx_registry_count = 0;
static void nx_registry_add(NxRuntime *nx) {
  if (nx_registry_count < NX_MAX_RUNTIMES) nx_registry[nx_registry_count++] = nx;
}
static NxRuntime *nx_registry_find(JSContextRef ctx) {
  JSGlobalContextRef gctx = JSContextGetGlobalContext(ctx);
  for (int i = 0; i < nx_registry_count; i++) {
    if (nx_registry[i] && nx_registry[i]->ctx == gctx) return nx_registry[i];
  }
  return NULL;
}

/* Host callback bridge: JSC C function */
static JSValueRef nx_host_call(JSContextRef ctx, JSObjectRef function,
                               JSObjectRef thisObject, size_t argc,
                               const JSValueRef argv[], JSValueRef *exception) {
  (void)function; (void)thisObject;
  NxRuntime *nx = nx_registry_find(ctx);
  if (nx == NULL) return JSValueMakeUndefined(ctx);
  if (argc < 1 || !JSValueIsString(ctx, argv[0])) {
    JSStringRef msg = JSStringCreateWithUTF8CString("__nx_host expects a string");
    *exception = JSValueMakeString(ctx, msg);
    JSStringRelease(msg);
    return JSValueMakeUndefined(ctx);
  }
  size_t max = JSStringGetMaximumUTF8CStringSize(JSValueToStringCopy(ctx, argv[0], NULL));
  // simpler: convert
  JSStringRef jstr = JSValueToStringCopy(ctx, argv[0], NULL);
  size_t utf8size = JSStringGetMaximumUTF8CStringSize(jstr);
  char *req = (char *)malloc(utf8size);
  size_t written = JSStringGetUTF8CString(jstr, req, utf8size);
  size_t reqlen = written > 0 ? written - 1 : 0;
  char *resp = NULL;
  int64_t resp_len = 0;
  nx_host_dispatch(nx, req, (int64_t)reqlen, &resp, &resp_len);
  free(req);
  JSStringRelease(jstr);
  if (resp == NULL) {
    JSStringRef msg = JSStringCreateWithUTF8CString("host returned no response");
    *exception = JSValueMakeString(ctx, msg);
    JSStringRelease(msg);
    return JSValueMakeUndefined(ctx);
  }
  JSValueRef result = JSValueMakeUndefined(ctx);
  if (resp_len > 0) {
    JSStringRef jresp = JSStringCreateWithUTF8CString(resp);
    result = JSValueMakeFromJSONString(ctx, jresp);
    JSStringRelease(jresp);
    if (JSValueIsUndefined(ctx, result) && resp_len > 0) {
      // maybe parse failed; leave undefined
    }
  }
  free(resp);
  return result;
}

static JSValueRef nx_register_call(JSContextRef ctx, JSObjectRef function,
                                   JSObjectRef thisObject, size_t argc,
                                   const JSValueRef argv[], JSValueRef *exception) {
  (void)function; (void)thisObject;
  NxRuntime *nx = nx_registry_find(ctx);
  if (argc < 2 || !JSValueIsString(ctx, argv[0]) || !JSValueIsObject(ctx, argv[1])) {
    JSStringRef msg = JSStringCreateWithUTF8CString("__nx_register expects (name, function)");
    *exception = JSValueMakeString(ctx, msg);
    JSStringRelease(msg);
    return JSValueMakeUndefined(ctx);
  }
  JSStringRef namejs = JSValueToStringCopy(ctx, argv[0], NULL);
  JSObjectRef fn = JSValueToObject(ctx, argv[1], NULL);
  JSObjectSetProperty(ctx, nx->callbacks, namejs, fn, kJSPropertyAttributeNone, NULL);
  JSStringRelease(namejs);
  return JSValueMakeUndefined(ctx);
}

/* Buffer calls */
static void nx_buffer_deallocator(void *bytes, void *ctx) {
  (void)ctx;
  free(bytes);
}

static JSValueRef nx_buffer_take_call(JSContextRef ctx, JSObjectRef function,
                                      JSObjectRef thisObject, size_t argc,
                                      const JSValueRef argv[], JSValueRef *exception) {
  (void)function; (void)thisObject;
  if (argc < 1) {
    JSStringRef msg = JSStringCreateWithUTF8CString("id expected");
    *exception = JSValueMakeString(ctx, msg);
    JSStringRelease(msg);
    return JSValueMakeUndefined(ctx);
  }
  int64_t id = (int64_t)JSValueToNumber(ctx, argv[0], NULL);
  int64_t len = 0;
  uint8_t *data = (uint8_t *)nx_buffer_take(id, &len);
  if (len < 0) {
    JSStringRef msg = JSStringCreateWithUTF8CString("unknown buffer");
    *exception = JSValueMakeString(ctx, msg);
    JSStringRelease(msg);
    return JSValueMakeUndefined(ctx);
  }
  if (data == NULL) data = (uint8_t *)malloc(1);
  JSObjectRef ab = JSObjectMakeArrayBufferWithBytesNoCopy(ctx, data, (size_t)len, nx_buffer_deallocator, NULL, exception);
  return ab;
}

static JSValueRef nx_buffer_put_call(JSContextRef ctx, JSObjectRef function,
                                     JSObjectRef thisObject, size_t argc,
                                     const JSValueRef argv[], JSValueRef *exception) {
  (void)function; (void)thisObject;
  if (argc < 1) {
    JSStringRef msg = JSStringCreateWithUTF8CString("buffer expected");
    *exception = JSValueMakeString(ctx, msg);
    JSStringRelease(msg);
    return JSValueMakeUndefined(ctx);
  }
  // Get bytes
  JSObjectRef obj = JSValueToObject(ctx, argv[0], NULL);
  size_t len = 0;
  void *src = JSObjectGetArrayBufferBytesPtr(ctx, obj, exception);
  if (src != NULL) {
    len = JSObjectGetArrayBufferByteLength(ctx, obj, exception);
  } else {
    if (exception && *exception) { *exception = NULL; }
    JSObjectRef buf = JSObjectGetTypedArrayBuffer(ctx, obj, exception);
    if (buf) {
      src = JSObjectGetArrayBufferBytesPtr(ctx, buf, exception);
      if (src != NULL) {
        size_t off = JSObjectGetTypedArrayByteOffset(ctx, obj, exception);
        src = (uint8_t *)src + off;
        len = JSObjectGetTypedArrayByteLength(ctx, obj, exception);
      }
    }
  }
  if (src == NULL) src = malloc(1);
  uint8_t *copy = (uint8_t *)malloc(len > 0 ? len : 1);
  if (len > 0) memcpy(copy, src, len);
  int64_t id = nx_buffer_put(copy, (int64_t)len);
  return JSValueMakeNumber(ctx, (double)id);
}

/* SAB share/open simplified: store pointer+length in parked list (reuse nx_buffer? use shared parked) */
typedef struct NxSharedParked { int64_t id; void *data; size_t len; struct NxSharedParked *next; } NxSharedParked;
static NxSharedParked *nx_shared_parked = NULL;

static JSValueRef nx_sab_share_call(JSContextRef ctx, JSObjectRef function,
                                    JSObjectRef thisObject, size_t argc,
                                    const JSValueRef argv[], JSValueRef *exception) {
  (void)function; (void)thisObject;
  // Get ArrayBuffer bytes
  JSObjectRef obj = argc > 0 ? JSValueToObject(ctx, argv[0], NULL) : NULL;
  size_t len = 0;
  void *data = obj ? JSObjectGetArrayBufferBytesPtr(ctx, obj, exception) : NULL;
  if (obj) len = JSObjectGetArrayBufferByteLength(ctx, obj, exception);
  NxSharedParked *p = (NxSharedParked *)malloc(sizeof(NxSharedParked));
  p->data = data;
  p->len = len;
  NX_LOCK();
  p->id = nx_next_park_id++;
  p->next = nx_shared_parked;
  nx_shared_parked = p;
  NX_UNLOCK();
  return JSValueMakeNumber(ctx, (double)p->id);
}

static JSValueRef nx_sab_open_call(JSContextRef ctx, JSObjectRef function,
                                   JSObjectRef thisObject, size_t argc,
                                   const JSValueRef argv[], JSValueRef *exception) {
  (void)function; (void)thisObject;
  int64_t id = argc > 0 ? (int64_t)JSValueToNumber(ctx, argv[0], NULL) : 0;
  NxSharedParked *found = NULL;
  NX_LOCK();
  for (NxSharedParked **pp = &nx_shared_parked; *pp != NULL; pp = &(*pp)->next) {
    if ((*pp)->id == id) { found = *pp; *pp = found->next; break; }
  }
  NX_UNLOCK();
  if (!found) {
    JSStringRef msg = JSStringCreateWithUTF8CString("unknown shared buffer");
    *exception = JSValueMakeString(ctx, msg);
    JSStringRelease(msg);
    return JSValueMakeUndefined(ctx);
  }
  JSObjectRef ab = JSObjectMakeArrayBufferWithBytesNoCopy(ctx, found->data, found->len, NULL, NULL, exception);
  free(found);
  return ab;
}

/* GL install stub: call existing nx_gl_install? It expects JSContext*. We'll skip; gl_native null. */
/* wasm install: skip for now (nativax_wasm uses runtime). */

NxRuntime *nx_runtime_new(int64_t runtime_id, int64_t memory_limit,
                          int64_t stack_size, NxHostCallback host) {
  (void)memory_limit; (void)stack_size;
  setenv("JSC_useSharedArrayBuffer", "1", 1);
  NxRuntime *nx = (NxRuntime *)calloc(1, sizeof(NxRuntime));
  if (nx == NULL) return NULL;
  nx->id = runtime_id;
  nx->host = host;
  nx->ctx = JSGlobalContextCreate(NULL);
  if (nx->ctx == NULL) { free(nx); return NULL; }
  nx->global = JSContextGetGlobalObject(nx->ctx);
  nx->callbacks = JSObjectMake(nx->ctx, NULL, NULL);
  JSValueProtect(nx->ctx, nx->callbacks);
  // store nx pointer in global object private for host callbacks
  // Use a property instead
  JSStringRef key = JSStringCreateWithUTF8CString("__nx_ptr");
  // can't store pointer in JSValue easily; use global private via JSObjectSetPrivate on global? global may not allow private. 
  // We'll store in a static map? Instead pass nx via closure? JSC C callbacks don't have user data.
  // Workaround: store nx pointer in a global JS property as a number (pointer as double) - unsafe but ok for 64-bit? Use external.
  // Better: keep a global registry array indexed by runtime_id.
  JSStringRelease(key);

  // Register globals
  JSStringRef n1 = JSStringCreateWithUTF8CString("__nx_host");
  JSObjectRef f1 = JSObjectMakeFunctionWithCallback(nx->ctx, n1, nx_host_call);
  JSObjectSetProperty(nx->ctx, nx->global, n1, f1, kJSPropertyAttributeNone, NULL);
  JSStringRelease(n1);

  JSStringRef n2 = JSStringCreateWithUTF8CString("__nx_register");
  JSObjectRef f2 = JSObjectMakeFunctionWithCallback(nx->ctx, n2, nx_register_call);
  JSObjectSetProperty(nx->ctx, nx->global, n2, f2, kJSPropertyAttributeNone, NULL);
  JSStringRelease(n2);

  JSStringRef n3 = JSStringCreateWithUTF8CString("__nx_buffer_take");
  JSObjectRef f3 = JSObjectMakeFunctionWithCallback(nx->ctx, n3, nx_buffer_take_call);
  JSObjectSetProperty(nx->ctx, nx->global, n3, f3, kJSPropertyAttributeNone, NULL);
  JSStringRelease(n3);

  JSStringRef n4 = JSStringCreateWithUTF8CString("__nx_buffer_put");
  JSObjectRef f4 = JSObjectMakeFunctionWithCallback(nx->ctx, n4, nx_buffer_put_call);
  JSObjectSetProperty(nx->ctx, nx->global, n4, f4, kJSPropertyAttributeNone, NULL);
  JSStringRelease(n4);

  JSStringRef n5 = JSStringCreateWithUTF8CString("__nx_sab_share");
  JSObjectRef f5 = JSObjectMakeFunctionWithCallback(nx->ctx, n5, nx_sab_share_call);
  JSObjectSetProperty(nx->ctx, nx->global, n5, f5, kJSPropertyAttributeNone, NULL);
  JSStringRelease(n5);

  JSStringRef n6 = JSStringCreateWithUTF8CString("__nx_sab_open");
  JSObjectRef f6 = JSObjectMakeFunctionWithCallback(nx->ctx, n6, nx_sab_open_call);
  JSObjectSetProperty(nx->ctx, nx->global, n6, f6, kJSPropertyAttributeNone, NULL);
  JSStringRelease(n6);

  // Store nx pointer globally in a registry to retrieve in callbacks.
  // We'll use a static array.
  nx_registry_add(nx);

  // wasm/gl install skipped
  return nx;
}

void nx_runtime_free(NxRuntime *nx) {
  if (nx == NULL) return;
  // remove from registry
  for (int i = 0; i < nx_registry_count; i++) {
    if (nx_registry[i] == nx) { nx_registry[i] = nx_registry[--nx_registry_count]; break; }
  }
  JSValueUnprotect(nx->ctx, nx->callbacks);
  JSGlobalContextRelease(nx->ctx);
  free(nx);
}

void nx_set_can_block(NxRuntime *nx, int32_t can_block) { (void)nx; nx->can_block = can_block; }

void nx_set_budget_ms(NxRuntime *nx, int64_t budget_ms) {
  nx->deadline_ms = budget_ms > 0 ? nx_now_ms() + budget_ms : 0;
}

static int32_t nx_finish(NxRuntime *nx, JSValueRef result, JSValueRef exception, char **out, int64_t *out_len) {
  if (exception != NULL) {
    // serialize exception as error descriptor
    JSObjectRef desc = JSObjectMake(nx->ctx, NULL, NULL);
    JSValueRef exc = exception;
    if (JSValueIsObject(nx->ctx, exc)) {
      JSObjectRef o = JSValueToObject(nx->ctx, exc, NULL);
      // copy name, message, stack
      JSStringRef n = JSStringCreateWithUTF8CString("name");
      JSValueRef v = JSObjectGetProperty(nx->ctx, o, n, NULL);
      if (!JSValueIsUndefined(nx->ctx, v)) JSObjectSetProperty(nx->ctx, desc, n, v, kJSPropertyAttributeNone, NULL);
      JSStringRelease(n);
      JSStringRef m = JSStringCreateWithUTF8CString("message");
      v = JSObjectGetProperty(nx->ctx, o, m, NULL);
      if (!JSValueIsUndefined(nx->ctx, v)) JSObjectSetProperty(nx->ctx, desc, m, v, kJSPropertyAttributeNone, NULL);
      JSStringRelease(m);
      JSStringRef s = JSStringCreateWithUTF8CString("stack");
      v = JSObjectGetProperty(nx->ctx, o, s, NULL);
      if (!JSValueIsUndefined(nx->ctx, v)) JSObjectSetProperty(nx->ctx, desc, s, v, kJSPropertyAttributeNone, NULL);
      JSStringRelease(s);
    } else {
      JSStringRef n = JSStringCreateWithUTF8CString("name");
      JSObjectSetProperty(nx->ctx, desc, n, JSValueMakeString(nx->ctx, JSStringCreateWithUTF8CString("Error")), kJSPropertyAttributeNone, NULL);
      JSStringRelease(n);
      JSStringRef m = JSStringCreateWithUTF8CString("message");
      JSStringRef ms = JSValueToStringCopy(nx->ctx, exc, NULL);
      JSObjectSetProperty(nx->ctx, desc, m, JSValueMakeString(nx->ctx, ms), kJSPropertyAttributeNone, NULL);
      JSStringRelease(ms);
      JSStringRelease(m);
    }
    JSStringRef u = JSStringCreateWithUTF8CString("uncatchable");
    JSObjectSetProperty(nx->ctx, desc, u, JSValueMakeBoolean(nx->ctx, false), kJSPropertyAttributeNone, NULL);
    JSStringRelease(u);
    nx_serialize(nx->ctx, desc, out, out_len);
    return NX_EXCEPTION;
  }
  // check budget
  if (nx->deadline_ms != 0 && nx_now_ms() > nx->deadline_ms) {
    // throw timeout? We can't easily; just return exception descriptor
    JSStringRef msg = JSStringCreateWithUTF8CString("execution timeout");
    JSValueRef e = JSValueMakeString(nx->ctx, msg);
    JSStringRelease(msg);
    // build descriptor
    JSObjectRef desc2 = JSObjectMake(nx->ctx, NULL, NULL);
    JSStringRef n = JSStringCreateWithUTF8CString("name");
    JSObjectSetProperty(nx->ctx, desc2, n, JSValueMakeString(nx->ctx, JSStringCreateWithUTF8CString("Error")), kJSPropertyAttributeNone, NULL);
    JSStringRelease(n);
    JSStringRef m = JSStringCreateWithUTF8CString("message");
    JSObjectSetProperty(nx->ctx, desc2, m, e, kJSPropertyAttributeNone, NULL);
    JSStringRelease(m);
    nx_serialize(nx->ctx, desc2, out, out_len);
    return NX_EXCEPTION;
  }
  nx_serialize(nx->ctx, result, out, out_len);
  return NX_OK;
}

int32_t nx_eval(NxRuntime *nx, const char *source, int64_t len,
                const char *filename, char **out, int64_t *out_len) {
  char *buf = (char *)malloc((size_t)len + 1);
  if (len > 0) memcpy(buf, source, (size_t)len);
  buf[len] = '\0';
  JSStringRef src = JSStringCreateWithUTF8CString(buf);
  JSValueRef exc = NULL;
  JSStringRef url = NULL;
  if (filename) {
    // filename is null-terminated from Dart? ensure
    url = JSStringCreateWithUTF8CString(filename);
  }
  JSValueRef result = JSEvaluateScript(nx->ctx, src, NULL, url, 1, &exc);
  free(buf);
  if (url) JSStringRelease(url);
  JSStringRelease(src);
  int32_t r = nx_finish(nx, result, exc, out, out_len);
  return r;
}

int32_t nx_eval_module(NxRuntime *nx, const char *source, int64_t len,
                       const char *url, char **out, int64_t *out_len) {
  // JSC has no module API; evaluate as classic script.
  return nx_eval(nx, source, len, url, out, out_len);
}

int32_t nx_call(NxRuntime *nx, const char *function_name,
                const char *json_arg, int64_t len, char **out,
                int64_t *out_len) {
  JSValueRef exc = NULL;
  JSStringRef fname = JSStringCreateWithUTF8CString(function_name);
  JSObjectRef global = JSContextGetGlobalObject(nx->ctx);
  // first check callbacks
  JSValueRef fn = JSObjectGetProperty(nx->ctx, nx->callbacks, fname, NULL);
  if (!JSValueIsObject(nx->ctx, fn) || !JSObjectIsFunction(nx->ctx, (JSObjectRef)fn)) {
    fn = JSObjectGetProperty(nx->ctx, global, fname, NULL);
  }
  if (!JSValueIsObject(nx->ctx, fn) || !JSObjectIsFunction(nx->ctx, (JSObjectRef)fn)) {
    JSStringRef msg = JSStringCreateWithUTF8CString("not a function");
    exc = JSValueMakeString(nx->ctx, msg);
    JSStringRelease(msg);
    JSStringRelease(fname);
    return nx_finish(nx, JSValueMakeUndefined(nx->ctx), exc, out, out_len);
  }
  JSValueRef arg;
  if (len > 0) {
    JSStringRef jarg = JSStringCreateWithUTF8CString(json_arg); // json_arg null-terminated? yes from Dart (with null terminator? nx_store adds \0; Dart passes length; C string from Dart may not be null-terminated but we allocate? The Dart side passes Pointer<Char> to bytes with length; need null-terminate. We'll copy.)
    // ensure null-terminated
    char *buf = (char *)malloc(len + 1);
    memcpy(buf, json_arg, len);
    buf[len] = '\0';
    JSStringRef jarg2 = JSStringCreateWithUTF8CString(buf);
    arg = JSValueMakeFromJSONString(nx->ctx, jarg2);
    JSStringRelease(jarg2);
    free(buf);
    if (JSValueIsUndefined(nx->ctx, arg) && len > 0) {
      // maybe parse returned undefined on failure; check exception? JSC doesn't set exception. Leave.
    }
  } else {
    arg = JSValueMakeUndefined(nx->ctx);
  }
  JSValueRef args[1] = { arg };
  JSValueRef result = JSObjectCallAsFunction(nx->ctx, (JSObjectRef)fn, global, 1, args, &exc);
  JSStringRelease(fname);
  int32_t r = nx_finish(nx, result, exc, out, out_len);
  return r;
}

int32_t nx_run_jobs(NxRuntime *nx, int32_t max_jobs, char **out,
                    int64_t *out_len) {
  // JSC drains microtasks during eval; nothing pending. Return 0.
  (void)nx; (void)max_jobs; (void)out; (void)out_len;
  *out = NULL; *out_len = 0;
  return 0;
}

int32_t nx_has_pending_jobs(NxRuntime *nx) { (void)nx; return 0; }

void nx_run_gc(NxRuntime *nx) { JSGarbageCollect(nx->ctx); }

int64_t nx_memory_used(NxRuntime *nx) { (void)nx; return 0; }
