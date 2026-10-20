#include "nativax_bridge.h"

#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
#else
#include <time.h>
#endif

#include "quickjs.h"

struct NxRuntime {
  JSRuntime *rt;
  JSContext *ctx;
  int64_t id;
  NxHostCallback host;
  int64_t deadline_ms; /* 0 = no deadline */
};

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
  nx->ctx = JS_NewContext(nx->rt);
  if (nx->ctx == NULL) {
    JS_FreeRuntime(nx->rt);
    free(nx);
    return NULL;
  }
  JS_SetContextOpaque(nx->ctx, nx);
  JSValue global = JS_GetGlobalObject(nx->ctx);
  JS_SetPropertyStr(nx->ctx, global, "__nx_host",
                    JS_NewCFunction(nx->ctx, nx_host_call, "__nx_host", 1));
  JS_FreeValue(nx->ctx, global);
  return nx;
}

void nx_runtime_free(NxRuntime *nx) {
  if (nx == NULL) return;
  JS_FreeContext(nx->ctx);
  JS_FreeRuntime(nx->rt);
  free(nx);
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

int32_t nx_call(NxRuntime *nx, const char *function_name, const char *json_arg,
                int64_t len, char **out, int64_t *out_len) {
  JS_UpdateStackTop(nx->rt);
  JSContext *ctx = nx->ctx;
  JSValue global = JS_GetGlobalObject(ctx);
  JSValue fn = JS_GetPropertyStr(ctx, global, function_name);
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
