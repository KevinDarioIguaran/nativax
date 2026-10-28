#include "nativax/js_engine.h"

#include "nativax/log.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

struct NxJs {
    JSGlobalContextRef ctx;
    JSClassRef fn_class; /* callable class for native functions */
    int budget_ms;       /* 0 = unlimited; soft budget, see eval_common */
};

/* ---- time helpers ---- */
static double now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec / 1e6;
}

/* ---- string helpers ---- */
static char* jsstring_to_utf8(JSStringRef s) {
    size_t n = JSStringGetMaximumUTF8CStringSize(s);
    char* out = malloc(n);
    if (!out) return NULL;
    JSStringGetUTF8CString(s, out, n);
    return out;
}

static JSStringRef utf8_to_jsstring(const char* s) {
    return JSStringCreateWithUTF8CString(s);
}

static char* exception_to_string(JSContextRef ctx, JSValueRef exc) {
    JSStringRef s = JSValueToStringCopy(ctx, exc, NULL);
    if (!s) return strdup("(unprintable exception)");
    char* out = jsstring_to_utf8(s);
    JSStringRelease(s);
    return out;
}

char* nx_js_value_to_json(JSContextRef ctx, JSValueRef v) {
    if (!v || JSValueIsUndefined(ctx, v) || JSValueIsNull(ctx, v)) {
        return strdup("null");
    }
    /* route through JSON.stringify for correct escaping/objects */
    JSStringRef fn_src = utf8_to_jsstring("(function(v){try{return JSON.stringify(v);}catch(e){return"
                                          " JSON.stringify(String(v));}})");
    JSValueRef fn_v = JSEvaluateScript(ctx, fn_src, NULL, NULL, 1, NULL);
    JSStringRelease(fn_src);
    if (!fn_v || !JSValueIsObject(ctx, fn_v)) {
        return strdup("null");
    }
    JSValueRef args[1] = {v};
    JSValueRef res = JSObjectCallAsFunction(ctx, (JSObjectRef)fn_v, NULL, 1, args, NULL);
    if (!res) {
        return strdup("null");
    }
    JSStringRef s = JSValueToStringCopy(ctx, res, NULL);
    if (!s) return strdup("null");
    char* out = jsstring_to_utf8(s);
    JSStringRelease(s);
    return out ? out : strdup("null");
}

/* ---- lifecycle ---- */
static JSValueRef class_call_as_function(JSContextRef ctx, JSObjectRef function, JSObjectRef self,
                                         size_t argc, const JSValueRef argv[],
                                         JSValueRef* exception);

static void native_fn_finalize(JSObjectRef function);

NxJs* nx_js_new(void) {
    NxJs* js = calloc(1, sizeof(NxJs));
    if (!js) return NULL;
    js->ctx = JSGlobalContextCreate(NULL);
    if (!js->ctx) {
        free(js);
        return NULL;
    }
    JSClassDefinition fn_def = kJSClassDefinitionEmpty;
    fn_def.className = "NativaXNativeFunction";
    fn_def.callAsFunction = class_call_as_function;
    fn_def.finalize = native_fn_finalize;
    js->fn_class = JSClassCreate(&fn_def);
    return js;
}

void nx_js_free(NxJs* js) {
    if (!js) return;
    JSClassRelease(js->fn_class);
    JSGlobalContextRelease(js->ctx); /* finalizers free native data */
    free(js);
}

JSContextRef nx_js_ctx(NxJs* js) { return js->ctx; }

/* ---- eval ---- */
static bool eval_common(NxJs* js, const char* code, const char* url, JSValueRef* out,
                        char** error) {
    JSStringRef src = utf8_to_jsstring(code);
    JSStringRef url_s = url ? utf8_to_jsstring(url) : NULL;
    JSValueRef exc = NULL;
    double t0 = now_ms();
    JSValueRef res = JSEvaluateScript(js->ctx, src, NULL, url_s, 1, &exc);
    double elapsed = now_ms() - t0;
    JSStringRelease(src);
    if (url_s) JSStringRelease(url_s);
    if (!res) {
        if (error) *error = exc ? exception_to_string(js->ctx, exc) : strdup("(unknown error)");
        return false;
    }
    if (js->budget_ms > 0 && elapsed > (double)js->budget_ms) {
        NX_WARN("script exceeded time budget: %.0f ms > %d ms (%s)", elapsed, js->budget_ms,
                url ? url : "<eval>");
    }
    if (out) *out = res;
    return true;
}

bool nx_js_eval(NxJs* js, const char* code, const char* url, char** error) {
    return eval_common(js, code, url, NULL, error);
}

char* nx_js_eval_json(NxJs* js, const char* expr, char** error) {
    size_t n = strlen(expr) + 64;
    char* wrapped = malloc(n);
    snprintf(wrapped, n, "JSON.stringify((function(){return (%s)})())", expr);
    JSValueRef res = NULL;
    if (!eval_common(js, wrapped, "<eval>", &res, error)) {
        free(wrapped);
        return NULL;
    }
    free(wrapped);
    if (JSValueIsUndefined(js->ctx, res) || JSValueIsNull(js->ctx, res)) {
        return strdup("null"); /* JSON.stringify(undefined) is undefined */
    }
    JSStringRef s = JSValueToStringCopy(js->ctx, res, NULL);
    if (!s) {
        /* undefined result of JSON.stringify */
        return strdup("null");
    }
    char* out = jsstring_to_utf8(s);
    JSStringRelease(s);
    return out;
}

char* nx_js_call_json(NxJs* js, const char* fn_name, const char* json_args, char** error) {
    char code[512];
    snprintf(code, sizeof(code), "typeof %s === 'function'", fn_name);
    JSValueRef is_fn = NULL;
    if (!eval_common(js, code, "<check>", &is_fn, error)) {
        return NULL;
    }
    if (!JSValueToBoolean(js->ctx, is_fn)) {
        if (error) *error = strdup("not a function");
        return NULL;
    }
    JSStringRef fn_name_s = utf8_to_jsstring(fn_name);
    JSValueRef fn_v = JSObjectGetProperty(js->ctx, JSContextGetGlobalObject(js->ctx), fn_name_s,
                                          NULL);
    JSStringRelease(fn_name_s);
    if (!fn_v || !JSValueIsObject(js->ctx, fn_v)) {
        if (error) *error = strdup("function not found");
        return NULL;
    }
    /* parse args (JSON literals only: re-evaluation has no side effects) */
    char code2[1024];
    snprintf(code2, sizeof(code2), "(%s)", json_args ? json_args : "[]");
    JSValueRef args_v = NULL;
    if (!eval_common(js, code2, "<args>", &args_v, error)) {
        return NULL;
    }
    if (!args_v || !JSValueIsObject(js->ctx, args_v)) {
        if (error) *error = strdup("json_args must be a JSON value");
        return NULL;
    }
    JSObjectRef arr = (JSObjectRef)args_v;
    JSStringRef len_name = utf8_to_jsstring("length");
    JSValueRef len_v = JSObjectGetProperty(js->ctx, arr, len_name, NULL);
    JSStringRelease(len_name);
    if (!len_v) {
        if (error) *error = strdup("json_args has no length (must be an array)");
        return NULL;
    }
    size_t argc = (size_t)JSValueToNumber(js->ctx, len_v, NULL);
    if (argc > 8) argc = 8;
    JSValueRef* argv = argc ? malloc(sizeof(JSValueRef) * argc) : NULL;
    for (size_t i = 0; i < argc; i++) {
        argv[i] = JSObjectGetPropertyAtIndex(js->ctx, arr, (unsigned)i, NULL);
    }
    JSValueRef exc = NULL;
    double t0 = now_ms();
    JSValueRef res = JSObjectCallAsFunction(js->ctx, (JSObjectRef)fn_v, NULL, argc, argv, &exc);
    double elapsed = now_ms() - t0;
    free(argv);
    if (!res) {
        if (error) *error = exc ? exception_to_string(js->ctx, exc) : strdup("(call failed)");
        return NULL;
    }
    if (js->budget_ms > 0 && elapsed > (double)js->budget_ms) {
        NX_WARN("function call exceeded time budget: %.0f ms > %d ms (%s)", elapsed,
                js->budget_ms, fn_name);
    }
    return nx_js_value_to_json(js->ctx, res);
}

/* ---- native functions ----
   The classic C API has no user-data slot on JSObjectMakeFunctionWithCallback,
   so native functions are callable objects of a private class carrying their
   data as private data (freed by the class finalizer). */
typedef struct NativeFnData {
    NxJsNativeFn fn;
    void* user;
} NativeFnData;

static JSValueRef native_call_as_function(JSContextRef ctx, JSObjectRef function,
                                          JSObjectRef self, size_t argc, const JSValueRef argv[],
                                          JSValueRef* exc, void* data) {
    (void)exc;
    NativeFnData* d = (NativeFnData*)data;
    return d->fn(ctx, function, self, argc, argv, d->user);
}

static void native_fn_finalize(JSObjectRef function) {
    free(JSObjectGetPrivate(function));
    (void)function;
}

/* bridge: JSClass callAsFunction has no user-data param, but JSObjectGetPrivate does */
static JSValueRef class_call_as_function(JSContextRef ctx, JSObjectRef function, JSObjectRef self,
                                         size_t argc, const JSValueRef argv[],
                                         JSValueRef* exception) {
    NativeFnData* d = (NativeFnData*)JSObjectGetPrivate(function);
    return native_call_as_function(ctx, function, self, argc, argv, exception, d);
}

bool nx_js_set_function(NxJs* js, const char* name, NxJsNativeFn fn, void* user) {
    NativeFnData* d = malloc(sizeof(NativeFnData));
    d->fn = fn;
    d->user = user;
    JSObjectRef obj = JSObjectMake(js->ctx, js->fn_class, d);
    if (!obj) {
        free(d);
        return false;
    }
    JSStringRef key = utf8_to_jsstring(name);
    JSObjectSetProperty(js->ctx, JSContextGetGlobalObject(js->ctx), key, obj,
                        kJSPropertyAttributeNone, NULL);
    JSStringRelease(key);
    return true;
}

void nx_js_set_time_budget_ms(NxJs* js, int budget_ms) { js->budget_ms = budget_ms; }

/* ---- constructors ---- */
JSValueRef nx_js_number(JSContextRef ctx, double v) { return JSValueMakeNumber(ctx, v); }
JSValueRef nx_js_bool(JSContextRef ctx, bool v) { return JSValueMakeBoolean(ctx, v); }
JSValueRef nx_js_string(JSContextRef ctx, const char* s) {
    JSStringRef str = utf8_to_jsstring(s);
    JSValueRef v = JSValueMakeString(ctx, str);
    JSStringRelease(str);
    return v;
}

JSValueRef nx_js_json(JSContextRef ctx, const char* json) {
    char code[2048];
    snprintf(code, sizeof(code), "(%s)", json && json[0] ? json : "null");
    JSStringRef src = utf8_to_jsstring(code);
    JSValueRef v = JSEvaluateScript(ctx, src, NULL, NULL, 1, NULL);
    JSStringRelease(src);
    return v ? v : JSValueMakeNull(ctx);
}
