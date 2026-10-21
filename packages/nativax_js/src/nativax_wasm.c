/*
 * WebAssembly for NativaX, implemented with wasm3 (MIT, vendored under
 * third_party/wasm3) and exposed to script code through a small private
 * native object. The JS-facing `WebAssembly.*` surface is defined by
 * lib/src/wasm_prelude.dart.
 *
 * Design notes:
 *  - A `WebAssembly.Module` owns a validated copy of the bytes. Every
 *    instantiation parses those bytes into a fresh wasm3 module, so one
 *    compiled module can be instantiated more than once.
 *  - Imported functions are linked after `m3_LoadModule` (wasm3 requires the
 *    module to belong to a runtime before host functions can be attached).
 *  - JS exceptions thrown by an import are parked and re-thrown from the
 *    native call that trapped. wasm3 itself never sees a JSValue.
 *  - Linear memory is exposed as an external ArrayBuffer over wasm3's bytes.
 *    `memory.grow` can move that allocation, so the old ArrayBuffer is
 *    detached and replaced; the wasm-bindgen glue detects the detached views
 *    and refreshes its caches exactly as it does in a browser.
 */
#include "nativax_wasm.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "m3_env.h"
#include "nativax_runtime_internal.h"
#include "quickjs.h"

#define NX_WASM_STACK_BYTES (2 * 1024 * 1024)
#define NX_WASM_MEMORY_LIMIT (512ull * 1024 * 1024)
#define NX_WASM_MAX_MODULE_BYTES (64ull * 1024 * 1024)
#define NX_WASM_MAX_MODULES 256
#define NX_WASM_MAX_INSTANCES 32
/* Rapier's heaviest single export call in the B4 integration test uses about
 * 7.8M gas units. 500M gives a large physics scene plenty of headroom while
 * still stopping a runaway `loop br 0` in well under a second. */
#define NX_WASM_GAS_PER_CALL (1000ull * 1000 * 1000)

typedef struct NxWasm NxWasm;
typedef struct NxWasmInstance NxWasmInstance;

typedef struct NxWasmModule {
  int used;
  int refs;
  int32_t handle;
  uint8_t *bytes;
  uint32_t len;
} NxWasmModule;

typedef struct NxWasmImport {
  NxWasmInstance *instance;
  JSValue function;
  char *module_name;
  char *field_name;
  uint16_t num_args;
  uint16_t num_rets;
  m3type_t *types; /* returns first, then arguments (wasm3 layout) */
} NxWasmImport;

typedef struct NxWasmExport {
  uint8_t kind; /* d_externalKind_* */
  IM3Function function;
  IM3Memory memory;
  IM3Table table;
  IM3Global global;
} NxWasmExport;

struct NxWasmInstance {
  int used;
  int32_t handle;
  NxWasm *owner;
  NxWasmModule *module;
  IM3Runtime runtime;
  IM3Module wasm;
  NxWasmImport **imports;
  uint32_t num_imports;
  NxWasmExport *exports;
  uint32_t num_exports;
  JSValue memory_buffer;
  uint8_t *memory_ptr;
  size_t memory_len;
  JSValue pending_error;
  int has_pending_error;
  int call_depth;
  const char *current_function;
};

struct NxWasm {
  NxRuntime *nx;
  JSContext *ctx;
  IM3Environment env;
  NxWasmModule **modules;
  uint32_t modules_len;
  uint32_t modules_cap;
  NxWasmInstance **instances;
  uint32_t instances_len;
  uint32_t instances_cap;
};

/* --- small utilities ----------------------------------------------------- */

static char *nx_wasm_strdup(const char *s) {
  if (s == NULL) return NULL;
  size_t len = strlen(s);
  char *copy = (char *)malloc(len + 1);
  if (copy != NULL) memcpy(copy, s, len + 1);
  return copy;
}

static int nx_wasm_grow_array(void **array, uint32_t *cap, uint32_t needed,
                              size_t elem_size) {
  if (needed <= *cap) return 0;
  uint32_t next = *cap ? *cap : 8;
  while (next < needed) {
    if (next > 0x3fffffff) return -1;
    next *= 2;
  }
  void *p = realloc(*array, (size_t)next * elem_size);
  if (p == NULL) return -1;
  *array = p;
  *cap = next;
  return 0;
}

static const char *nx_wasm_type_name(m3type_t type) {
  switch (type) {
    case c_m3Type_i32:
      return "i32";
    case c_m3Type_i64:
      return "i64";
    case c_m3Type_f32:
      return "f32";
    case c_m3Type_f64:
      return "f64";
    case c_m3Type_funcref:
      return "funcref";
    case c_m3Type_externref:
      return "externref";
    default:
      return "externref";
  }
}

static void nx_wasm_instance_free(NxWasmInstance *instance);

static uint32_t nx_wasm_live_modules(NxWasm *wasm) {
  uint32_t n = 0;
  for (uint32_t i = 0; i < wasm->modules_len; i++) {
    if (wasm->modules[i] != NULL && wasm->modules[i]->used) n++;
  }
  return n;
}

static uint32_t nx_wasm_live_instances(NxWasm *wasm) {
  uint32_t n = 0;
  for (uint32_t i = 0; i < wasm->instances_len; i++) {
    if (wasm->instances[i] != NULL && wasm->instances[i]->used) n++;
  }
  return n;
}

static NxWasmModule *nx_wasm_module_get(NxWasm *wasm, int32_t handle) {
  if (wasm == NULL || handle <= 0 || (uint32_t)handle > wasm->modules_len) {
    return NULL;
  }
  NxWasmModule *m = wasm->modules[handle - 1];
  return m != NULL && m->used ? m : NULL;
}

static NxWasmInstance *nx_wasm_instance_get(NxWasm *wasm, int32_t handle) {
  if (wasm == NULL || handle <= 0 || (uint32_t)handle > wasm->instances_len) {
    return NULL;
  }
  NxWasmInstance *i = wasm->instances[handle - 1];
  return i != NULL && i->used ? i : NULL;
}

static void nx_wasm_module_destroy(NxWasm *wasm, NxWasmModule *module) {
  if (module == NULL) return;
  module->used = 0;
  if (wasm != NULL && module->handle > 0 &&
      (uint32_t)module->handle <= wasm->modules_len &&
      wasm->modules[module->handle - 1] == module) {
    wasm->modules[module->handle - 1] = NULL;
  }
  free(module->bytes);
  free(module);
}

static int32_t nx_wasm_add_module(NxWasm *wasm, NxWasmModule *module) {
  if (nx_wasm_grow_array((void **)&wasm->modules, &wasm->modules_cap,
                         wasm->modules_len + 1, sizeof(*wasm->modules)) != 0) {
    return 0;
  }
  wasm->modules[wasm->modules_len++] = module;
  module->handle = (int32_t)wasm->modules_len;
  module->used = 1;
  return module->handle;
}

static int32_t nx_wasm_add_instance(NxWasm *wasm, NxWasmInstance *instance) {
  if (nx_wasm_grow_array((void **)&wasm->instances, &wasm->instances_cap,
                         wasm->instances_len + 1, sizeof(*wasm->instances)) !=
      0) {
    return 0;
  }
  wasm->instances[wasm->instances_len++] = instance;
  instance->handle = (int32_t)wasm->instances_len;
  instance->used = 1;
  return instance->handle;
}

/* Accepts ArrayBuffer, SharedArrayBuffer and any typed-array/DataView view. */
static int nx_wasm_bytes(JSContext *ctx, JSValueConst value, const uint8_t **out,
                         size_t *out_len) {
  size_t len = 0;
  uint8_t *data = JS_GetArrayBuffer(ctx, &len, value);
  if (data != NULL) {
    *out = data;
    *out_len = len;
    return 0;
  }
  JS_FreeValue(ctx, JS_GetException(ctx));
  size_t offset = 0;
  size_t bytes_per_element = 0;
  JSValue buffer =
      JS_GetTypedArrayBuffer(ctx, value, &offset, &len, &bytes_per_element);
  if (JS_IsException(buffer)) {
    JS_FreeValue(ctx, JS_GetException(ctx));
    return -1;
  }
  size_t buffer_len = 0;
  uint8_t *base = JS_GetArrayBuffer(ctx, &buffer_len, buffer);
  JS_FreeValue(ctx, buffer);
  if (base == NULL) return -1;
  if (offset > buffer_len || len > buffer_len - offset) return -1;
  *out = base + offset;
  *out_len = len;
  return 0;
}

static JSValue nx_wasm_error(JSContext *ctx, const char *name,
                             const char *message) {
  JSValue error = JS_NewError(ctx);
  if (JS_IsException(error)) return error;
  JS_SetPropertyStr(ctx, error, "name", JS_NewString(ctx, name));
  JS_SetPropertyStr(ctx, error, "message", JS_NewString(ctx, message));
  return JS_Throw(ctx, error);
}

static m3type_t nx_wasm_slot_type(m3type_t type) {
  /* Reference arguments reach JS as heap handles/numbers. wasm3's raw ABI
   * stores them in the same 64-bit cell as i32. */
  if (type == c_m3Type_funcref || type == c_m3Type_externref ||
      type == c_m3Type_exnref || type == c_m3Type_contref) {
    return c_m3Type_i32;
  }
  return type;
}

static char nx_wasm_type_char(m3type_t type) {
  switch (nx_wasm_slot_type(type)) {
    case c_m3Type_i32:
      return 'i';
    case c_m3Type_i64:
      return 'I';
    case c_m3Type_f32:
      return 'f';
    case c_m3Type_f64:
      return 'F';
    default:
      return 'v';
  }
}

/* wasm3 signature: results before '(', then arguments, e.g. "i(ii)". */
static char *nx_wasm_signature(IM3FuncType type) {
  uint16_t nrets = GetFuncTypeNumResults(type);
  uint16_t nargs = GetFuncTypeNumParams(type);
  char *sig = (char *)malloc((size_t)nrets + nargs + 4);
  if (sig == NULL) return NULL;
  char *p = sig;
  if (nrets == 0) {
    *p++ = 'v';
  } else {
    for (uint16_t i = 0; i < nrets; i++) {
      *p++ = nx_wasm_type_char(GetFuncTypeResultType(type, i));
    }
  }
  *p++ = '(';
  for (uint16_t i = 0; i < nargs; i++) {
    *p++ = nx_wasm_type_char(GetFuncTypeParamType(type, i));
  }
  *p++ = ')';
  *p = '\0';
  return sig;
}

static void nx_wasm_clear_pending(NxWasmInstance *instance) {
  if (instance->has_pending_error) {
    JS_FreeValue(instance->owner->ctx, instance->pending_error);
    instance->pending_error = JS_UNDEFINED;
    instance->has_pending_error = 0;
  }
}

static void nx_wasm_set_pending(NxWasmInstance *instance, JSValue error) {
  nx_wasm_clear_pending(instance);
  instance->pending_error = error;
  instance->has_pending_error = 1;
}

/* Throws the parked JS exception, or an error for a wasm3 trap. */
static JSValue nx_wasm_fail(NxWasmInstance *instance, M3Result result) {
  JSContext *ctx = instance->owner->ctx;
  if (instance->has_pending_error) {
    JSValue error = instance->pending_error;
    instance->pending_error = JS_UNDEFINED;
    instance->has_pending_error = 0;
    return JS_Throw(ctx, error);
  }
  const char *message = result ? result : "WebAssembly operation failed";
  char composed[512];
  if (strncmp(message, "[trap]", 6) == 0 && instance->current_function != NULL) {
    snprintf(composed, sizeof(composed), "%s in %s", message,
             instance->current_function);
    message = composed;
  }
  const char *name =
      strncmp(message, "[trap]", 6) == 0 ? "RuntimeError" : "LinkError";
  return nx_wasm_error(ctx, name, message);
}

/* --- linear memory ------------------------------------------------------- */

/* wasm3 may move linear memory when it grows. Keep the JS ArrayBuffer in
 * sync, detaching the previous one so cached typed-array views report zero
 * length and the wasm-bindgen glue rebuilds them. */
static void nx_wasm_refresh_memory(NxWasmInstance *instance) {
  if (instance->wasm == NULL) return;
  size_t len = 0;
  uint8_t *ptr = m3_GetMemory(instance->wasm, &len, 0);
  if (ptr == NULL) return;
  if (ptr == instance->memory_ptr && len == instance->memory_len &&
      !JS_IsUndefined(instance->memory_buffer)) {
    return;
  }
  JSContext *ctx = instance->owner->ctx;
  if (!JS_IsUndefined(instance->memory_buffer)) {
    JS_DetachArrayBuffer(ctx, instance->memory_buffer);
    JS_FreeValue(ctx, instance->memory_buffer);
  }
  instance->memory_buffer =
      JS_NewArrayBuffer(ctx, ptr, len, 0, NULL, NULL, false);
  instance->memory_ptr = ptr;
  instance->memory_len = len;
}

/* --- imports ------------------------------------------------------------- */

static int nx_wasm_js_to_wasm(JSContext *ctx, JSValueConst value,
                              m3type_t type, uint64_t *slot) {
  switch (nx_wasm_slot_type(type)) {
    case c_m3Type_i32: {
      int32_t v;
      if (JS_ToInt32(ctx, &v, value)) return -1;
      *slot = (uint32_t)v;
      return 0;
    }
    case c_m3Type_i64: {
      int64_t v;
      if (JS_ToBigInt64(ctx, &v, value)) return -1;
      *slot = (uint64_t)v;
      return 0;
    }
    case c_m3Type_f32: {
      double v;
      float f;
      if (JS_ToFloat64(ctx, &v, value)) return -1;
      f = (float)v;
      *slot = 0;
      memcpy(slot, &f, sizeof(f));
      return 0;
    }
    case c_m3Type_f64: {
      double v;
      if (JS_ToFloat64(ctx, &v, value)) return -1;
      memcpy(slot, &v, sizeof(v));
      return 0;
    }
    default:
      JS_ThrowTypeError(ctx, "unsupported WebAssembly value type");
      return -1;
  }
}

static int nx_wasm_wasm_to_js(JSContext *ctx, m3type_t type, uint64_t slot,
                              JSValue *out) {
  switch (nx_wasm_slot_type(type)) {
    case c_m3Type_i32: {
      int32_t v;
      memcpy(&v, &slot, sizeof(v));
      *out = JS_NewInt32(ctx, v);
      return 0;
    }
    case c_m3Type_i64: {
      int64_t v;
      memcpy(&v, &slot, sizeof(v));
      *out = JS_NewBigInt64(ctx, v);
      return 0;
    }
    case c_m3Type_f32: {
      float v;
      memcpy(&v, &slot, sizeof(v));
      *out = JS_NewFloat64(ctx, (double)v);
      return 0;
    }
    case c_m3Type_f64: {
      double v;
      memcpy(&v, &slot, sizeof(v));
      *out = JS_NewFloat64(ctx, v);
      return 0;
    }
    default:
      JS_ThrowTypeError(ctx, "unsupported WebAssembly value type");
      return -1;
  }
}

/* One raw entry point for every JS import. `_sp` is an array of 64-bit cells:
 * the return cells first, then one cell per argument, which is the ABI
 * documented by wasm3. */
static const void *nx_wasm_raw_import(IM3Runtime runtime, IM3ImportContext ctx,
                                      uint64_t *sp, void *mem) {
  (void)runtime;
  (void)mem;
  NxWasmImport *import = (NxWasmImport *)ctx->userdata;
  if (import == NULL || import->instance == NULL) return m3Err_trapAbort;
  NxWasmInstance *instance = import->instance;
  JSContext *js = instance->owner->ctx;
  nx_wasm_refresh_memory(instance);

  JSValue args[32];
  JSValue *argv = args;
  if (import->num_args > 32) {
    argv = (JSValue *)malloc(sizeof(JSValue) * import->num_args);
    if (argv == NULL) {
      nx_wasm_set_pending(instance, JS_NewError(js));
      return m3Err_trapAbort;
    }
  }
  for (uint16_t i = 0; i < import->num_args; i++) argv[i] = JS_UNDEFINED;
  int failed = 0;
  for (uint16_t i = 0; i < import->num_args; i++) {
    m3type_t type = import->types[import->num_rets + i];
    if (nx_wasm_wasm_to_js(js, type, sp[import->num_rets + i], &argv[i])) {
      failed = 1;
      break;
    }
  }
  if (failed) {
    for (uint16_t i = 0; i < import->num_args; i++) JS_FreeValue(js, argv[i]);
    nx_wasm_set_pending(instance, JS_GetException(js));
    if (argv != args) free(argv);
    return m3Err_trapAbort;
  }

  JSValue result =
      JS_Call(js, import->function, JS_UNDEFINED, import->num_args, argv);
  for (uint16_t i = 0; i < import->num_args; i++) JS_FreeValue(js, argv[i]);
  if (argv != args) free(argv);
  if (JS_IsException(result)) {
    nx_wasm_set_pending(instance, JS_GetException(js));
    return m3Err_trapAbort;
  }

  int ok = 1;
  if (import->num_rets == 0) {
    JS_FreeValue(js, result);
  } else if (import->num_rets == 1) {
    ok = nx_wasm_js_to_wasm(js, result, import->types[0], &sp[0]) == 0;
    JS_FreeValue(js, result);
  } else if (!JS_IsArray(result)) {
    JS_FreeValue(js, result);
    JS_ThrowTypeError(js, "WebAssembly import must return an array");
    ok = 0;
  } else {
    for (uint16_t i = 0; i < import->num_rets; i++) {
      JSValue v = JS_GetPropertyUint32(js, result, i);
      if (JS_IsException(v) ||
          nx_wasm_js_to_wasm(js, v, import->types[i], &sp[i])) {
        JS_FreeValue(js, v);
        ok = 0;
        break;
      }
      JS_FreeValue(js, v);
    }
    JS_FreeValue(js, result);
  }
  if (!ok) {
    nx_wasm_set_pending(instance, JS_GetException(js));
    return m3Err_trapAbort;
  }
  return m3Err_none;
}

/* --- instantiation ------------------------------------------------------- */

static JSValue nx_wasm_instantiate_impl(JSContext *ctx, NxWasm *wasm,
                                        NxWasmModule *module,
                                        JSValueConst import_object,
                                        int *out_handle) {
  if (module == NULL) {
    return nx_wasm_error(ctx, "CompileError", "invalid WebAssembly.Module");
  }
  if (!JS_IsObject(import_object) || JS_IsNull(import_object)) {
    return nx_wasm_error(ctx, "TypeError",
                         "WebAssembly.Instance expects an import object");
  }
  if (nx_wasm_live_instances(wasm) >= NX_WASM_MAX_INSTANCES) {
    return nx_wasm_error(ctx, "LinkError",
                         "too many live WebAssembly instances");
  }

  NxWasmInstance *instance = (NxWasmInstance *)calloc(1, sizeof(*instance));
  if (instance == NULL) return JS_ThrowOutOfMemory(ctx);
  instance->owner = wasm;
  instance->module = module;
  module->refs++;
  instance->memory_buffer = JS_UNDEFINED;
  instance->pending_error = JS_UNDEFINED;

  instance->runtime = m3_NewRuntime(wasm->env, NX_WASM_STACK_BYTES, NULL);
  if (instance->runtime == NULL) {
    nx_wasm_instance_free(instance);
    return JS_ThrowOutOfMemory(ctx);
  }
  m3_SetResourceLimit(instance->runtime, c_m3Limit_MemoryBytes,
                      NX_WASM_MEMORY_LIMIT);

  IM3Module parsed = NULL;
  M3Result result =
      m3_ParseModule(wasm->env, &parsed, module->bytes, module->len);
  if (result != NULL) {
    nx_wasm_instance_free(instance);
    return nx_wasm_error(ctx, "CompileError", result);
  }
  result = m3_LoadModule(instance->runtime, parsed);
  if (result != NULL) {
    /* m3_LoadModule owns the parsed module even on failure. */
    nx_wasm_instance_free(instance);
    return nx_wasm_error(ctx, "LinkError", result);
  }
  instance->wasm = parsed;

  /* Resolve imported functions. wasm3 links by (module, field) name and may
   * bind every matching import in one call, so matching names are linked once
   * and share one descriptor. */
  uint32_t function_imports = parsed->numFuncImports;
  instance->imports =
      (NxWasmImport **)calloc(function_imports ? function_imports : 1,
                              sizeof(NxWasmImport *));
  if (instance->imports == NULL) {
    nx_wasm_instance_free(instance);
    return JS_ThrowOutOfMemory(ctx);
  }

  for (uint32_t i = 0; i < function_imports; i++) {
    IM3Function function = &parsed->functions[i];
    const char *module_name = function->import.moduleUtf8;
    const char *field_name = function->import.fieldUtf8;
    if (module_name == NULL || field_name == NULL) continue;

    int duplicate = 0;
    for (uint32_t j = 0; j < instance->num_imports; j++) {
      NxWasmImport *known = instance->imports[j];
      if (known->module_name != NULL &&
          strcmp(known->module_name, module_name) == 0 &&
          strcmp(known->field_name, field_name) == 0) {
        duplicate = 1;
        break;
      }
    }
    if (duplicate) continue;

    JSValue ns = JS_GetPropertyStr(ctx, import_object, module_name);
    if (JS_IsException(ns)) {
      nx_wasm_instance_free(instance);
      return JS_EXCEPTION;
    }
    if (!JS_IsObject(ns) || JS_IsNull(ns)) {
      JS_FreeValue(ctx, ns);
      nx_wasm_instance_free(instance);
      char message[256];
      snprintf(message, sizeof(message), "missing import namespace %s",
               module_name);
      return nx_wasm_error(ctx, "LinkError", message);
    }
    JSValue fn = JS_GetPropertyStr(ctx, ns, field_name);
    JS_FreeValue(ctx, ns);
    if (JS_IsException(fn)) {
      nx_wasm_instance_free(instance);
      return JS_EXCEPTION;
    }
    if (!JS_IsFunction(ctx, fn)) {
      JS_FreeValue(ctx, fn);
      nx_wasm_instance_free(instance);
      char message[256];
      snprintf(message, sizeof(message), "import %s.%s is not a function",
               module_name, field_name);
      return nx_wasm_error(ctx, "LinkError", message);
    }

    NxWasmImport *import = (NxWasmImport *)calloc(1, sizeof(*import));
    if (import == NULL) {
      JS_FreeValue(ctx, fn);
      nx_wasm_instance_free(instance);
      return JS_ThrowOutOfMemory(ctx);
    }
    import->instance = instance;
    import->function = fn;
    import->module_name = nx_wasm_strdup(module_name);
    import->field_name = nx_wasm_strdup(field_name);
    IM3FuncType type = function->funcType;
    import->num_rets = GetFuncTypeNumResults(type);
    import->num_args = GetFuncTypeNumParams(type);
    import->types = (m3type_t *)malloc(
        sizeof(m3type_t) * (import->num_rets + import->num_args));
    if (import->types == NULL || import->module_name == NULL ||
        import->field_name == NULL) {
      free(import->types);
      free(import->module_name);
      free(import->field_name);
      JS_FreeValue(ctx, fn);
      free(import);
      nx_wasm_instance_free(instance);
      return JS_ThrowOutOfMemory(ctx);
    }
    for (uint16_t r = 0; r < import->num_rets; r++) {
      import->types[r] = GetFuncTypeResultType(type, r);
    }
    for (uint16_t a = 0; a < import->num_args; a++) {
      import->types[import->num_rets + a] = GetFuncTypeParamType(type, a);
    }
    char *signature = nx_wasm_signature(type);
    if (signature == NULL) {
      free(import->types);
      free(import->module_name);
      free(import->field_name);
      JS_FreeValue(ctx, fn);
      free(import);
      nx_wasm_instance_free(instance);
      return JS_ThrowOutOfMemory(ctx);
    }
    result = m3_LinkRawFunctionEx(parsed, module_name, field_name, signature,
                                  nx_wasm_raw_import, import);
    free(signature);
    if (result != NULL) {
      free(import->types);
      free(import->module_name);
      free(import->field_name);
      JS_FreeValue(ctx, fn);
      free(import);
      nx_wasm_instance_free(instance);
      char message[320];
      snprintf(message, sizeof(message), "cannot link %s.%s: %s", module_name,
               field_name, result);
      return nx_wasm_error(ctx, "LinkError", message);
    }
    instance->imports[instance->num_imports++] = import;
  }

  /* Memory/table/global imports need host-side objects that wasm3 can only
   * satisfy through another module. Fail clearly instead of running against
   * a zero-filled memory. */
  for (uint32_t i = 0; i < parsed->numMemories; i++) {
    if (parsed->memories[i]->imported) {
      nx_wasm_instance_free(instance);
      return nx_wasm_error(ctx, "LinkError",
                           "imported WebAssembly.Memory is not supported yet");
    }
  }
  for (uint32_t i = 0; i < parsed->numTables; i++) {
    if (parsed->tables[i]->imported) {
      nx_wasm_instance_free(instance);
      return nx_wasm_error(ctx, "LinkError",
                           "imported WebAssembly.Table is not supported yet");
    }
  }
  for (uint32_t i = 0; i < parsed->numGlobals; i++) {
    if (parsed->globals[i].imported) {
      nx_wasm_instance_free(instance);
      return nx_wasm_error(ctx, "LinkError",
                           "imported WebAssembly.Global is not supported yet");
    }
  }

  /* Arm gas metering before compilation so every generated body is charged.
   * The budget is reset before each outermost call. */
  m3_SetResourceLimit(instance->runtime, c_m3Limit_GasUnits,
                      NX_WASM_GAS_PER_CALL);
  result = m3_CompileModule(parsed);
  if (result != NULL) {
    nx_wasm_instance_free(instance);
    return nx_wasm_error(ctx, "CompileError", result);
  }

  if (parsed->startFunction >= 0) {
    result = m3_RunStart(parsed);
    if (result != NULL || instance->has_pending_error) {
      JSValue error = nx_wasm_fail(instance, result);
      nx_wasm_instance_free(instance);
      return error;
    }
  }

  instance->exports =
      (NxWasmExport *)calloc(parsed->numExports ? parsed->numExports : 1,
                             sizeof(NxWasmExport));
  if (instance->exports == NULL) {
    nx_wasm_instance_free(instance);
    return JS_ThrowOutOfMemory(ctx);
  }
  instance->num_exports = parsed->numExports;
  for (uint32_t i = 0; i < parsed->numExports; i++) {
    M3Export *e = &parsed->exports[i];
    NxWasmExport *out = &instance->exports[i];
    out->kind = e->kind;
    if (e->kind == d_externalKind_function) {
      if (e->index < parsed->numFunctions) {
        out->function = &parsed->functions[e->index];
      }
    } else if (e->kind == d_externalKind_memory) {
      if (e->index < parsed->numMemories) {
        out->memory = parsed->memories[e->index];
      }
    } else if (e->kind == d_externalKind_table) {
      if (e->index < parsed->numTables) {
        out->table = parsed->tables[e->index];
      }
    } else if (e->kind == d_externalKind_global) {
      if (e->index < parsed->numGlobals) {
        out->global = &parsed->globals[e->index];
      }
    }
  }

  nx_wasm_refresh_memory(instance);

  int32_t handle = nx_wasm_add_instance(wasm, instance);
  if (handle == 0) {
    nx_wasm_instance_free(instance);
    return JS_ThrowOutOfMemory(ctx);
  }
  *out_handle = handle;
  return JS_UNDEFINED;
}

static void nx_wasm_instance_free(NxWasmInstance *instance) {
  if (instance == NULL) return;
  NxWasm *wasm = instance->owner;
  JSContext *ctx = wasm ? wasm->ctx : NULL;
  if (instance->handle > 0 && wasm != NULL &&
      (uint32_t)instance->handle <= wasm->instances_len &&
      wasm->instances[instance->handle - 1] == instance) {
    wasm->instances[instance->handle - 1] = NULL;
  }
  if (ctx != NULL) {
    if (!JS_IsUndefined(instance->memory_buffer)) {
      JS_DetachArrayBuffer(ctx, instance->memory_buffer);
      JS_FreeValue(ctx, instance->memory_buffer);
      instance->memory_buffer = JS_UNDEFINED;
    }
    if (instance->has_pending_error) {
      JS_FreeValue(ctx, instance->pending_error);
      instance->pending_error = JS_UNDEFINED;
      instance->has_pending_error = 0;
    }
    for (uint32_t i = 0; i < instance->num_imports; i++) {
      NxWasmImport *import = instance->imports[i];
      if (import == NULL) continue;
      if (!JS_IsUndefined(import->function)) {
        JS_FreeValue(ctx, import->function);
      }
      free(import->module_name);
      free(import->field_name);
      free(import->types);
      free(import);
    }
  }
  free(instance->imports);
  free(instance->exports);
  if (instance->runtime != NULL) m3_FreeRuntime(instance->runtime);
  if (instance->module != NULL) {
    instance->module->refs--;
    if (instance->module->refs <= 0 && !instance->module->used) {
      nx_wasm_module_destroy(wasm, instance->module);
    }
  }
  free(instance);
}

/* --- native functions called by the prelude ------------------------------ */

static JSValue nx_wasm_compile_call(JSContext *ctx, JSValueConst this_val,
                                    int argc, JSValueConst *argv) {
  (void)this_val;
  NxRuntime *nx = (NxRuntime *)JS_GetContextOpaque(ctx);
  NxWasm *wasm = nx ? nx->wasm : NULL;
  if (wasm == NULL) return JS_ThrowInternalError(ctx, "wasm is not available");
  if (argc < 1) return JS_ThrowTypeError(ctx, "buffer expected");
  const uint8_t *bytes = NULL;
  size_t len = 0;
  if (nx_wasm_bytes(ctx, argv[0], &bytes, &len) != 0) {
    return nx_wasm_error(ctx, "CompileError", "expected a BufferSource");
  }
  if (len > NX_WASM_MAX_MODULE_BYTES) {
    return nx_wasm_error(ctx, "CompileError", "WebAssembly module is too large");
  }
  if (nx_wasm_live_modules(wasm) >= NX_WASM_MAX_MODULES) {
    return nx_wasm_error(ctx, "CompileError",
                         "too many live WebAssembly modules");
  }

  /* Parse + compile in a throwaway runtime. A module object must own bytes
   * that stay alive for the life of every instance; the temporary validation
   * module is freed here. */
  IM3Module parsed = NULL;
  M3Result result = m3_ParseModule(wasm->env, &parsed, bytes, (uint32_t)len);
  if (result != NULL) return nx_wasm_error(ctx, "CompileError", result);
  IM3Runtime probe = m3_NewRuntime(wasm->env, 1024 * 1024, NULL);
  if (probe == NULL) {
    m3_FreeModule(parsed);
    return JS_ThrowOutOfMemory(ctx);
  }
  result = m3_LoadModule(probe, parsed);
  if (result == NULL) result = m3_CompileModule(parsed);
  m3_FreeRuntime(probe);
  if (result != NULL) return nx_wasm_error(ctx, "CompileError", result);

  NxWasmModule *module = (NxWasmModule *)calloc(1, sizeof(*module));
  if (module == NULL) return JS_ThrowOutOfMemory(ctx);
  module->bytes = (uint8_t *)malloc(len ? len : 1);
  if (module->bytes == NULL) {
    free(module);
    return JS_ThrowOutOfMemory(ctx);
  }
  if (len) memcpy(module->bytes, bytes, len);
  module->len = (uint32_t)len;
  module->refs = 1;
  if (nx_wasm_add_module(wasm, module) == 0) {
    free(module->bytes);
    free(module);
    return JS_ThrowOutOfMemory(ctx);
  }
  return JS_NewInt32(ctx, module->handle);
}

static JSValue nx_wasm_validate_call(JSContext *ctx, JSValueConst this_val,
                                     int argc, JSValueConst *argv) {
  (void)this_val;
  NxRuntime *nx = (NxRuntime *)JS_GetContextOpaque(ctx);
  NxWasm *wasm = nx ? nx->wasm : NULL;
  if (wasm == NULL || argc < 1) return JS_FALSE;
  const uint8_t *bytes = NULL;
  size_t len = 0;
  if (nx_wasm_bytes(ctx, argv[0], &bytes, &len) != 0) return JS_FALSE;
  if (len > NX_WASM_MAX_MODULE_BYTES) return JS_FALSE;
  IM3Module parsed = NULL;
  M3Result result = m3_ParseModule(wasm->env, &parsed, bytes, (uint32_t)len);
  if (result != NULL) return JS_FALSE;
  IM3Runtime probe = m3_NewRuntime(wasm->env, 1024 * 1024, NULL);
  if (probe == NULL) {
    m3_FreeModule(parsed);
    return JS_FALSE;
  }
  result = m3_LoadModule(probe, parsed);
  if (result == NULL) result = m3_CompileModule(parsed);
  m3_FreeRuntime(probe);
  return JS_NewBool(ctx, result == NULL);
}

static JSValue nx_wasm_module_info_call(JSContext *ctx, JSValueConst this_val,
                                        int argc, JSValueConst *argv) {
  (void)this_val;
  NxRuntime *nx = (NxRuntime *)JS_GetContextOpaque(ctx);
  NxWasm *wasm = nx ? nx->wasm : NULL;
  if (wasm == NULL) return JS_ThrowInternalError(ctx, "wasm is not available");
  int32_t handle = 0;
  if (argc < 1 || JS_ToInt32(ctx, &handle, argv[0])) {
    return JS_ThrowTypeError(ctx, "WebAssembly.Module expected");
  }
  NxWasmModule *module = nx_wasm_module_get(wasm, handle);
  if (module == NULL) {
    return nx_wasm_error(ctx, "CompileError", "invalid WebAssembly.Module");
  }
  IM3Module parsed = NULL;
  M3Result result =
      m3_ParseModule(wasm->env, &parsed, module->bytes, module->len);
  if (result != NULL) return nx_wasm_error(ctx, "CompileError", result);

  JSValue info = JS_NewObject(ctx);
  JSValue imports = JS_NewArray(ctx);
  JSValue exports = JS_NewArray(ctx);
  if (JS_IsException(info) || JS_IsException(imports) ||
      JS_IsException(exports)) {
    JS_FreeValue(ctx, info);
    JS_FreeValue(ctx, imports);
    JS_FreeValue(ctx, exports);
    m3_FreeModule(parsed);
    return JS_EXCEPTION;
  }
  uint32_t out = 0;
  for (uint32_t i = 0; i < parsed->numFuncImports; i++) {
    IM3Function f = &parsed->functions[i];
    if (f->import.moduleUtf8 == NULL || f->import.fieldUtf8 == NULL) continue;
    JSValue item = JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, item, "module",
                      JS_NewString(ctx, f->import.moduleUtf8));
    JS_SetPropertyStr(ctx, item, "name",
                      JS_NewString(ctx, f->import.fieldUtf8));
    JS_SetPropertyStr(ctx, item, "kind", JS_NewInt32(ctx, 0));
    JS_SetPropertyUint32(ctx, imports, out++, item);
  }
  for (uint32_t i = 0; i < parsed->numMemories; i++) {
    IM3Memory m = parsed->memories[i];
    if (!m->imported) continue;
    JSValue item = JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, item, "module", JS_NewString(ctx, m->import.moduleUtf8));
    JS_SetPropertyStr(ctx, item, "name", JS_NewString(ctx, m->import.fieldUtf8));
    JS_SetPropertyStr(ctx, item, "kind", JS_NewInt32(ctx, 2));
    JS_SetPropertyUint32(ctx, imports, out++, item);
  }
  for (uint32_t i = 0; i < parsed->numTables; i++) {
    IM3Table t = parsed->tables[i];
    if (!t->imported) continue;
    JSValue item = JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, item, "module", JS_NewString(ctx, t->import.moduleUtf8));
    JS_SetPropertyStr(ctx, item, "name", JS_NewString(ctx, t->import.fieldUtf8));
    JS_SetPropertyStr(ctx, item, "kind", JS_NewInt32(ctx, 1));
    JS_SetPropertyUint32(ctx, imports, out++, item);
  }
  for (uint32_t i = 0; i < parsed->numGlobals; i++) {
    M3Global *g = &parsed->globals[i];
    if (!g->imported) continue;
    JSValue item = JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, item, "module", JS_NewString(ctx, g->import.moduleUtf8));
    JS_SetPropertyStr(ctx, item, "name", JS_NewString(ctx, g->import.fieldUtf8));
    JS_SetPropertyStr(ctx, item, "kind", JS_NewInt32(ctx, 3));
    JS_SetPropertyUint32(ctx, imports, out++, item);
  }
  out = 0;
  for (uint32_t i = 0; i < parsed->numExports; i++) {
    M3Export *e = &parsed->exports[i];
    JSValue item = JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, item, "name",
                      JS_NewStringLen(ctx, e->name, e->nameLength));
    JS_SetPropertyStr(ctx, item, "kind", JS_NewInt32(ctx, e->kind));
    JS_SetPropertyUint32(ctx, exports, out++, item);
  }
  JS_SetPropertyStr(ctx, info, "imports", imports);
  JS_SetPropertyStr(ctx, info, "exports", exports);
  m3_FreeModule(parsed);
  return info;
}

static JSValue nx_wasm_instantiate_call(JSContext *ctx, JSValueConst this_val,
                                        int argc, JSValueConst *argv) {
  (void)this_val;
  NxRuntime *nx = (NxRuntime *)JS_GetContextOpaque(ctx);
  NxWasm *wasm = nx ? nx->wasm : NULL;
  if (wasm == NULL) return JS_ThrowInternalError(ctx, "wasm is not available");
  int32_t module_handle = 0;
  if (argc < 1 || JS_ToInt32(ctx, &module_handle, argv[0])) {
    return JS_ThrowTypeError(ctx, "WebAssembly.Module expected");
  }
  NxWasmModule *module = nx_wasm_module_get(wasm, module_handle);
  if (module == NULL) {
    return nx_wasm_error(ctx, "CompileError", "invalid WebAssembly.Module");
  }
  JSValue imports = argc > 1 ? argv[1] : JS_UNDEFINED;
  JSValue empty = JS_UNDEFINED;
  if (JS_IsUndefined(imports) || JS_IsNull(imports)) {
    empty = JS_NewObject(ctx);
    imports = empty;
  }
  int handle = 0;
  JSValue result =
      nx_wasm_instantiate_impl(ctx, wasm, module, imports, &handle);
  if (!JS_IsUndefined(empty)) JS_FreeValue(ctx, empty);
  if (JS_IsException(result)) return result;
  JS_FreeValue(ctx, result);
  return JS_NewInt32(ctx, handle);
}

static JSValue nx_wasm_start_call(JSContext *ctx, JSValueConst this_val,
                                  int argc, JSValueConst *argv) {
  (void)this_val;
  NxRuntime *nx = (NxRuntime *)JS_GetContextOpaque(ctx);
  NxWasm *wasm = nx ? nx->wasm : NULL;
  int32_t handle = 0;
  if (wasm == NULL || argc < 1 || JS_ToInt32(ctx, &handle, argv[0])) {
    return JS_ThrowTypeError(ctx, "invalid instance");
  }
  NxWasmInstance *instance = nx_wasm_instance_get(wasm, handle);
  if (instance == NULL) return JS_ThrowTypeError(ctx, "invalid instance");
  nx_wasm_clear_pending(instance);
  if (instance->call_depth == 0) {
    m3_SetResourceLimit(instance->runtime, c_m3Limit_GasUnits,
                        NX_WASM_GAS_PER_CALL);
  }
  instance->call_depth++;
  M3Result result = m3_RunStart(instance->wasm);
  instance->call_depth--;
  nx_wasm_refresh_memory(instance);
  if (result != NULL || instance->has_pending_error) {
    return nx_wasm_fail(instance, result);
  }
  return JS_UNDEFINED;
}

static JSValue nx_wasm_exports_call(JSContext *ctx, JSValueConst this_val,
                                    int argc, JSValueConst *argv) {
  (void)this_val;
  NxRuntime *nx = (NxRuntime *)JS_GetContextOpaque(ctx);
  NxWasm *wasm = nx ? nx->wasm : NULL;
  int32_t handle = 0;
  if (wasm == NULL || argc < 1 || JS_ToInt32(ctx, &handle, argv[0])) {
    return JS_ThrowTypeError(ctx, "invalid instance");
  }
  NxWasmInstance *instance = nx_wasm_instance_get(wasm, handle);
  if (instance == NULL) return JS_ThrowTypeError(ctx, "invalid instance");
  nx_wasm_refresh_memory(instance);
  JSValue list = JS_NewArray(ctx);
  if (JS_IsException(list)) return list;
  uint32_t out_index = 0;
  for (uint32_t i = 0; i < instance->num_exports; i++) {
    M3Export *e = &instance->wasm->exports[i];
    NxWasmExport *x = &instance->exports[i];
    JSValue desc = JS_NewObject(ctx);
    if (JS_IsException(desc)) {
      JS_FreeValue(ctx, list);
      return desc;
    }
    JS_SetPropertyStr(ctx, desc, "id", JS_NewInt32(ctx, (int32_t)i));
    JS_SetPropertyStr(ctx, desc, "name",
                      JS_NewStringLen(ctx, e->name, e->nameLength));
    if (x->kind == d_externalKind_function) {
      JS_SetPropertyStr(ctx, desc, "kind", JS_NewInt32(ctx, 0));
      JSValue args = JS_NewArray(ctx);
      JSValue rets = JS_NewArray(ctx);
      uint32_t nargs = x->function ? m3_GetArgCount(x->function) : 0;
      uint32_t nrets = x->function ? m3_GetRetCount(x->function) : 0;
      for (uint32_t j = 0; j < nargs; j++) {
        JS_SetPropertyUint32(
            ctx, args, j,
            JS_NewString(ctx,
                         nx_wasm_type_name(m3_GetArgType(x->function, j))));
      }
      for (uint32_t j = 0; j < nrets; j++) {
        JS_SetPropertyUint32(
            ctx, rets, j,
            JS_NewString(ctx,
                         nx_wasm_type_name(m3_GetRetType(x->function, j))));
      }
      JS_SetPropertyStr(ctx, desc, "args", args);
      JS_SetPropertyStr(ctx, desc, "results", rets);
    } else if (x->kind == d_externalKind_memory) {
      JS_SetPropertyStr(ctx, desc, "kind", JS_NewInt32(ctx, 2));
      JS_SetPropertyStr(ctx, desc, "initial",
                        JS_NewInt64(ctx, (int64_t)x->memory->initPages));
      if (x->memory->hasMax) {
        JS_SetPropertyStr(ctx, desc, "maximum",
                          JS_NewInt64(ctx, (int64_t)x->memory->maxPages));
      }
    } else if (x->kind == d_externalKind_table) {
      JS_SetPropertyStr(ctx, desc, "kind", JS_NewInt32(ctx, 1));
      JS_SetPropertyStr(ctx, desc, "initial",
                        JS_NewInt64(ctx, (int64_t)x->table->initSize));
      if (x->table->hasMax) {
        JS_SetPropertyStr(ctx, desc, "maximum",
                          JS_NewInt64(ctx, (int64_t)x->table->maxSize));
      }
    } else if (x->kind == d_externalKind_global) {
      JS_SetPropertyStr(ctx, desc, "kind", JS_NewInt32(ctx, 3));
      JS_SetPropertyStr(ctx, desc, "valueType",
                        JS_NewString(ctx, nx_wasm_type_name(x->global->type)));
      JS_SetPropertyStr(ctx, desc, "mutable",
                        JS_NewBool(ctx, x->global->isMutable));
    } else {
      JS_FreeValue(ctx, desc);
      continue;
    }
    JS_SetPropertyUint32(ctx, list, out_index++, desc);
  }
  return list;
}

static JSValue nx_wasm_call_call(JSContext *ctx, JSValueConst this_val,
                                 int argc, JSValueConst *argv) {
  (void)this_val;
  NxRuntime *nx = (NxRuntime *)JS_GetContextOpaque(ctx);
  NxWasm *wasm = nx ? nx->wasm : NULL;
  int32_t handle = 0;
  int32_t export_id = 0;
  if (wasm == NULL || argc < 2 || JS_ToInt32(ctx, &handle, argv[0]) ||
      JS_ToInt32(ctx, &export_id, argv[1])) {
    return JS_ThrowTypeError(ctx, "invalid WebAssembly call");
  }
  NxWasmInstance *instance = nx_wasm_instance_get(wasm, handle);
  if (instance == NULL || export_id < 0 ||
      (uint32_t)export_id >= instance->num_exports) {
    return JS_ThrowTypeError(ctx, "invalid WebAssembly export");
  }
  NxWasmExport *x = &instance->exports[export_id];
  if (x->kind != d_externalKind_function || x->function == NULL) {
    return JS_ThrowTypeError(ctx, "WebAssembly export is not callable");
  }
  IM3Function function = x->function;
  uint32_t nargs = m3_GetArgCount(function);
  uint32_t nrets = m3_GetRetCount(function);
  if ((uint32_t)(argc - 2) != nargs) {
    return JS_ThrowTypeError(ctx, "WebAssembly function expects %u arguments",
                             nargs);
  }
  nx_wasm_clear_pending(instance);

  typedef union {
    int32_t i32;
    int64_t i64;
    float f32;
    double f64;
    uintptr_t ref;
  } NxSlot;
  NxSlot stack_values[32] = {0};
  NxSlot *values = stack_values;
  if (nargs > 32) {
    values = (NxSlot *)calloc(nargs ? nargs : 1, sizeof(NxSlot));
    if (values == NULL) return JS_ThrowOutOfMemory(ctx);
  }
  const void *argptrs[64];
  const void **argptr_list = argptrs;
  if (nargs > 64) {
    argptr_list = (const void **)calloc(nargs, sizeof(void *));
    if (argptr_list == NULL) {
      if (values != stack_values) free(values);
      return JS_ThrowOutOfMemory(ctx);
    }
  }
  int failed = 0;
  for (uint32_t i = 0; i < nargs; i++) {
    m3type_t type = m3_GetArgType(function, i);
    switch (nx_wasm_slot_type(type)) {
      case c_m3Type_i32:
        if (JS_ToInt32(ctx, &values[i].i32, argv[i + 2])) failed = 1;
        argptr_list[i] = &values[i].i32;
        break;
      case c_m3Type_i64:
        if (JS_ToBigInt64(ctx, &values[i].i64, argv[i + 2])) failed = 1;
        argptr_list[i] = &values[i].i64;
        break;
      case c_m3Type_f32: {
        double d;
        if (JS_ToFloat64(ctx, &d, argv[i + 2])) failed = 1;
        values[i].f32 = (float)d;
        argptr_list[i] = &values[i].f32;
        break;
      }
      case c_m3Type_f64:
        if (JS_ToFloat64(ctx, &values[i].f64, argv[i + 2])) failed = 1;
        argptr_list[i] = &values[i].f64;
        break;
      default:
        JS_ThrowTypeError(ctx, "unsupported WebAssembly argument type");
        failed = 1;
        break;
    }
    if (failed) break;
  }
  if (failed) {
    if (values != stack_values) free(values);
    if (argptr_list != argptrs) free((void *)argptr_list);
    return JS_EXCEPTION;
  }

  if (instance->call_depth == 0) {
    m3_SetResourceLimit(instance->runtime, c_m3Limit_GasUnits,
                        NX_WASM_GAS_PER_CALL);
  }
  instance->current_function = m3_GetFunctionName(function);
  instance->call_depth++;
  M3Result result = m3_Call(function, nargs, argptr_list);
  instance->call_depth--;
  nx_wasm_refresh_memory(instance);
  if (result != NULL || instance->has_pending_error) {
    if (values != stack_values) free(values);
    if (argptr_list != argptrs) free((void *)argptr_list);
    return nx_wasm_fail(instance, result);
  }

  NxSlot results[16] = {0};
  NxSlot *ret_values = results;
  if (nrets > 16) {
    ret_values = (NxSlot *)calloc(nrets, sizeof(NxSlot));
    if (ret_values == NULL) {
      if (values != stack_values) free(values);
      if (argptr_list != argptrs) free((void *)argptr_list);
      return JS_ThrowOutOfMemory(ctx);
    }
  }
  void *retptrs[16];
  void **retptr_list = retptrs;
  if (nrets > 16) {
    retptr_list = (void **)calloc(nrets, sizeof(void *));
    if (retptr_list == NULL) {
      if (ret_values != results) free(ret_values);
      if (values != stack_values) free(values);
      if (argptr_list != argptrs) free((void *)argptr_list);
      return JS_ThrowOutOfMemory(ctx);
    }
  }
  for (uint32_t i = 0; i < nrets; i++) retptr_list[i] = &ret_values[i];
  if (nrets > 0) {
    result = m3_GetResults(function, nrets, (const void **)retptr_list);
    if (result != NULL) {
      if (retptr_list != retptrs) free(retptr_list);
      if (ret_values != results) free(ret_values);
      if (values != stack_values) free(values);
      if (argptr_list != argptrs) free((void *)argptr_list);
      return nx_wasm_fail(instance, result);
    }
  }

  JSValue value = JS_UNDEFINED;
  if (nrets == 1) {
    if (nx_wasm_wasm_to_js(ctx, m3_GetRetType(function, 0),
                           *(uint64_t *)&ret_values[0], &value) != 0) {
      value = JS_EXCEPTION;
    }
  } else if (nrets > 1) {
    value = JS_NewArray(ctx);
    if (!JS_IsException(value)) {
      for (uint32_t i = 0; i < nrets; i++) {
        JSValue item = JS_UNDEFINED;
        if (nx_wasm_wasm_to_js(ctx, m3_GetRetType(function, i),
                               *(uint64_t *)&ret_values[i], &item) != 0) {
          JS_FreeValue(ctx, value);
          value = JS_EXCEPTION;
          break;
        }
        JS_SetPropertyUint32(ctx, value, i, item);
      }
    }
  }

  if (retptr_list != retptrs) free(retptr_list);
  if (ret_values != results) free(ret_values);
  if (values != stack_values) free(values);
  if (argptr_list != argptrs) free((void *)argptr_list);
  return value;
}

/* Returns the current memory ArrayBuffer (same JS object until a grow). */
static JSValue nx_wasm_memory_call(JSContext *ctx, JSValueConst this_val,
                                   int argc, JSValueConst *argv) {
  (void)this_val;
  NxRuntime *nx = (NxRuntime *)JS_GetContextOpaque(ctx);
  NxWasm *wasm = nx ? nx->wasm : NULL;
  int32_t handle = 0;
  if (wasm == NULL || argc < 1 || JS_ToInt32(ctx, &handle, argv[0])) {
    return JS_ThrowTypeError(ctx, "invalid instance");
  }
  NxWasmInstance *instance = nx_wasm_instance_get(wasm, handle);
  if (instance == NULL) return JS_ThrowTypeError(ctx, "invalid instance");
  nx_wasm_refresh_memory(instance);
  if (JS_IsUndefined(instance->memory_buffer)) {
    return nx_wasm_error(ctx, "TypeError", "module has no memory");
  }
  return JS_DupValue(ctx, instance->memory_buffer);
}

static JSValue nx_wasm_grow_call(JSContext *ctx, JSValueConst this_val,
                                 int argc, JSValueConst *argv) {
  (void)this_val;
  NxRuntime *nx = (NxRuntime *)JS_GetContextOpaque(ctx);
  NxWasm *wasm = nx ? nx->wasm : NULL;
  int32_t handle = 0;
  int32_t export_id = 0;
  int32_t delta = 0;
  if (wasm == NULL || argc < 3 || JS_ToInt32(ctx, &handle, argv[0]) ||
      JS_ToInt32(ctx, &export_id, argv[1]) ||
      JS_ToInt32(ctx, &delta, argv[2])) {
    return JS_ThrowTypeError(ctx, "invalid WebAssembly.Memory.grow");
  }
  NxWasmInstance *instance = nx_wasm_instance_get(wasm, handle);
  if (instance == NULL || export_id < 0 ||
      (uint32_t)export_id >= instance->num_exports) {
    return JS_ThrowTypeError(ctx, "invalid WebAssembly memory export");
  }
  NxWasmExport *x = &instance->exports[export_id];
  if (x->kind != d_externalKind_memory || x->memory == NULL) {
    return JS_ThrowTypeError(ctx, "WebAssembly export is not memory");
  }
  if (delta < 0) return JS_ThrowRangeError(ctx, "invalid memory grow delta");
  uint64_t old_pages = x->memory->numPages;
  uint64_t next = old_pages + (uint64_t)delta;
  if (next > 0x10000) return JS_NewInt32(ctx, -1);
  M3Result result = ResizeMemory(instance->runtime, x->memory, next);
  nx_wasm_refresh_memory(instance);
  if (result != NULL) return JS_NewInt32(ctx, -1);
  return JS_NewInt64(ctx, (int64_t)old_pages);
}

static JSValue nx_wasm_release_module_call(JSContext *ctx,
                                           JSValueConst this_val, int argc,
                                           JSValueConst *argv) {
  (void)this_val;
  NxRuntime *nx = (NxRuntime *)JS_GetContextOpaque(ctx);
  NxWasm *wasm = nx ? nx->wasm : NULL;
  int32_t handle = 0;
  if (wasm == NULL || argc < 1 || JS_ToInt32(ctx, &handle, argv[0])) {
    return JS_UNDEFINED;
  }
  NxWasmModule *module = nx_wasm_module_get(wasm, handle);
  if (module == NULL) return JS_UNDEFINED;
  module->used = 0;
  module->refs--;
  if (module->refs <= 0) nx_wasm_module_destroy(wasm, module);
  return JS_UNDEFINED;
}

static JSValue nx_wasm_release_instance_call(JSContext *ctx,
                                             JSValueConst this_val, int argc,
                                             JSValueConst *argv) {
  (void)this_val;
  NxRuntime *nx = (NxRuntime *)JS_GetContextOpaque(ctx);
  NxWasm *wasm = nx ? nx->wasm : NULL;
  int32_t handle = 0;
  if (wasm == NULL || argc < 1 || JS_ToInt32(ctx, &handle, argv[0])) {
    return JS_UNDEFINED;
  }
  NxWasmInstance *instance = nx_wasm_instance_get(wasm, handle);
  if (instance == NULL) return JS_UNDEFINED;
  instance->used = 0;
  nx_wasm_instance_free(instance);
  return JS_UNDEFINED;
}

/* --- installation / teardown -------------------------------------------- */

void nx_wasm_install(NxRuntime *nx) {
  if (nx == NULL) return;
  JSContext *ctx = nx->ctx;
  NxWasm *wasm = (NxWasm *)calloc(1, sizeof(*wasm));
  if (wasm == NULL) return;
  wasm->nx = nx;
  wasm->ctx = ctx;
  wasm->env = m3_NewEnvironment();
  if (wasm->env == NULL) {
    free(wasm);
    return;
  }
  nx->wasm = wasm;

  JSValue native = JS_NewObject(ctx);
  if (JS_IsException(native)) return;
  JS_SetPropertyStr(ctx, native, "compile",
                    JS_NewCFunction(ctx, nx_wasm_compile_call, "compile", 1));
  JS_SetPropertyStr(ctx, native, "validate",
                    JS_NewCFunction(ctx, nx_wasm_validate_call, "validate", 1));
  JS_SetPropertyStr(
      ctx, native, "moduleInfo",
      JS_NewCFunction(ctx, nx_wasm_module_info_call, "moduleInfo", 1));
  JS_SetPropertyStr(
      ctx, native, "instantiate",
      JS_NewCFunction(ctx, nx_wasm_instantiate_call, "instantiate", 2));
  JS_SetPropertyStr(ctx, native, "start",
                    JS_NewCFunction(ctx, nx_wasm_start_call, "start", 1));
  JS_SetPropertyStr(ctx, native, "exports",
                    JS_NewCFunction(ctx, nx_wasm_exports_call, "exports", 1));
  JS_SetPropertyStr(ctx, native, "call",
                    JS_NewCFunction(ctx, nx_wasm_call_call, "call", 2));
  JS_SetPropertyStr(ctx, native, "memory",
                    JS_NewCFunction(ctx, nx_wasm_memory_call, "memory", 1));
  JS_SetPropertyStr(ctx, native, "grow",
                    JS_NewCFunction(ctx, nx_wasm_grow_call, "grow", 3));
  JS_SetPropertyStr(
      ctx, native, "releaseModule",
      JS_NewCFunction(ctx, nx_wasm_release_module_call, "releaseModule", 1));
  JS_SetPropertyStr(
      ctx, native, "releaseInstance",
      JS_NewCFunction(ctx, nx_wasm_release_instance_call, "releaseInstance", 1));

  JSValue global = JS_GetGlobalObject(ctx);
  JS_SetPropertyStr(ctx, global, "__nx_wasm_native", native);
  JS_FreeValue(ctx, global);
}

void nx_wasm_free(NxRuntime *nx) {
  if (nx == NULL || nx->wasm == NULL) return;
  NxWasm *wasm = nx->wasm;
  for (uint32_t i = 0; i < wasm->instances_len; i++) {
    NxWasmInstance *instance = wasm->instances[i];
    if (instance == NULL) continue;
    instance->used = 0;
    nx_wasm_instance_free(instance);
  }
  for (uint32_t i = 0; i < wasm->modules_len; i++) {
    NxWasmModule *module = wasm->modules[i];
    if (module == NULL) continue;
    nx_wasm_module_destroy(wasm, module);
  }
  free(wasm->instances);
  free(wasm->modules);
  if (wasm->env != NULL) m3_FreeEnvironment(wasm->env);
  free(wasm);
  nx->wasm = NULL;
}
