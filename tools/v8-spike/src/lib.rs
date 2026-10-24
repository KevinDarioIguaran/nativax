use std::cell::Cell;
use std::ffi::{c_char, c_void, CStr, CString};
use std::sync::Once;
use v8::{
    ArrayBuffer, ArrayBufferView, Context, ContextScope, Function, Isolate, Local, Script,
    String as V8String, Value,
};

static INIT: Once = Once::new();

type HostCb = extern "C" fn(*const c_char) -> *mut c_char;
type TakeBufferCb = extern "C" fn(u32, *mut u64) -> *mut u8;
type PutBufferCb = extern "C" fn(*const u8, usize) -> u32;

struct State {
    isolate: Box<v8::OwnedIsolate>,
    context: v8::Global<Context>,
}

thread_local! {
    static STATE: Cell<*mut State> = const { Cell::new(std::ptr::null_mut()) };
    static HOST_CB: Cell<Option<HostCb>> = const { Cell::new(None) };
    static TAKE_BUFFER_CB: Cell<Option<TakeBufferCb>> = const { Cell::new(None) };
    static PUT_BUFFER_CB: Cell<Option<PutBufferCb>> = const { Cell::new(None) };
}

fn init_v8() {
    INIT.call_once(|| {
        let platform = v8::new_default_platform(1, false).make_shared();
        v8::V8::initialize_platform(platform.clone());
        v8::V8::initialize();
        // V8 must keep the platform alive for the process lifetime.
        std::mem::forget(platform);
    });
}

fn host_callback(
    scope: &mut v8::PinScope,
    args: v8::FunctionCallbackArguments,
    mut rv: v8::ReturnValue,
) {
    let Some(cb) = HOST_CB.with(|c| c.get()) else {
        rv.set_undefined();
        return;
    };
    let Some(arg) = args.get(0).to_string(scope) else {
        rv.set_undefined();
        return;
    };
    let request = arg.to_rust_string_lossy(scope);
    let Ok(c_request) = CString::new(request) else {
        rv.set_undefined();
        return;
    };
    let response_ptr = cb(c_request.as_ptr());
    if response_ptr.is_null() {
        rv.set_undefined();
        return;
    }
    let response = unsafe { CStr::from_ptr(response_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { libc::free(response_ptr as *mut c_void) };
    if let Some(text) = V8String::new(scope, &response) {
        if let Some(value) = v8::json::parse(scope, text) {
            rv.set(value);
            return;
        }
    }
    rv.set_undefined();
}

fn buffer_take_callback(
    scope: &mut v8::PinScope,
    args: v8::FunctionCallbackArguments,
    mut rv: v8::ReturnValue,
) {
    let Some(cb) = TAKE_BUFFER_CB.with(|c| c.get()) else {
        rv.set_null();
        return;
    };
    let id = args.get(0).uint32_value(scope).unwrap_or(0);
    let mut len = 0u64;
    let ptr = cb(id, &mut len);
    if ptr.is_null() || len == u64::MAX {
        rv.set_null();
        return;
    }
    let buffer = ArrayBuffer::new(scope, len as usize);
    if let Some(data) = buffer.data() {
        unsafe {
            std::ptr::copy_nonoverlapping(ptr, data.as_ptr() as *mut u8, len as usize);
            libc::free(ptr as *mut c_void);
        }
        rv.set(buffer.into());
    } else {
        unsafe { libc::free(ptr as *mut c_void) };
        rv.set_null();
    }
}

fn buffer_put_callback(
    scope: &mut v8::PinScope,
    args: v8::FunctionCallbackArguments,
    mut rv: v8::ReturnValue,
) {
    let Some(cb) = PUT_BUFFER_CB.with(|c| c.get()) else {
        rv.set_uint32(0);
        return;
    };
    let Some(value) = args.get(0).to_object(scope) else {
        rv.set_uint32(0);
        return;
    };
    let Some(view) = v8::Local::<ArrayBufferView>::try_from(value).ok() else {
        rv.set_uint32(0);
        return;
    };
    let ptr = view.data() as *const u8;
    let len = view.byte_length();
    rv.set_uint32(cb(ptr, len));
}

fn decode_utf8_callback(
    scope: &mut v8::PinScope,
    args: v8::FunctionCallbackArguments,
    mut rv: v8::ReturnValue,
) {
    let Some(value) = args.get(0).to_object(scope) else {
        rv.set_null();
        return;
    };
    let Some(view) = v8::Local::<ArrayBufferView>::try_from(value).ok() else {
        rv.set_null();
        return;
    };
    let data = view.data() as *const u8;
    let len = view.byte_length();
    if data.is_null() {
        rv.set_null();
        return;
    }
    let bytes = unsafe { std::slice::from_raw_parts(data, len) };
    match V8String::new_from_utf8(scope, bytes, v8::NewStringType::Normal) {
        Some(text) => rv.set(text.into()),
        None => rv.set_null(),
    }
}

fn json_result(scope: &mut v8::PinScope, value: Local<Value>) -> String {
    if value.is_undefined() || value.is_null() {
        return "null".to_string();
    }
    match v8::json::stringify(scope, value) {
        Some(s) => {
            let text = s.to_rust_string_lossy(scope);
            if text == "undefined" {
                "null".to_string()
            } else {
                text
            }
        }
        None => "null".to_string(),
    }
}

fn string_result(value: String) -> *mut c_char {
    match CString::new(value) {
        Ok(s) => s.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn nv8_create(memory_limit: usize, _max_stack: usize) -> *mut c_void {
    init_v8();
    let existing = STATE.with(|s| s.get());
    if !existing.is_null() {
        return existing as *mut c_void;
    }
    let params = if memory_limit > 0 {
        v8::CreateParams::default().heap_limits(0, memory_limit)
    } else {
        v8::CreateParams::default()
    };
    let mut isolate = Box::new(Isolate::new(params));
    let context_global;
    {
        let isolate_ref = &mut *isolate;
        v8::scope!(let handle_scope, isolate_ref);
        let context = Context::new(handle_scope, Default::default());
        let scope = &mut ContextScope::new(handle_scope, context);
        let global = context.global(scope);
        let host = Function::new(scope, host_callback).unwrap();
        let host_key = V8String::new(scope, "__nx_host").unwrap();
        global.set(scope, host_key.into(), host.into());
        let bootstrap = V8String::new(
            scope,
            r#"
globalThis.__nx_registry = new Map();
globalThis.__nx_register = (name, fn) => { __nx_registry.set(String(name), fn); };
globalThis.__nx_call = (name, arg) => {
  const fn = __nx_registry.get(String(name));
  return fn ? fn(arg) : undefined;
};
globalThis.__nx_buffer_take = () => null;
globalThis.__nx_buffer_put = () => 0;
globalThis.__nx_sab_share = () => 0;
globalThis.__nx_sab_open = () => null;
globalThis.__nx_gl_native = null;
"#,
        )
        .unwrap();
        let script = Script::compile(scope, bootstrap, None).unwrap();
        script.run(scope);
        let take = Function::new(scope, buffer_take_callback).unwrap();
        let take_key = V8String::new(scope, "__nx_buffer_take").unwrap();
        global.set(scope, take_key.into(), take.into());
        let put = Function::new(scope, buffer_put_callback).unwrap();
        let put_key = V8String::new(scope, "__nx_buffer_put").unwrap();
        global.set(scope, put_key.into(), put.into());
        let decode = Function::new(scope, decode_utf8_callback).unwrap();
        let decode_key = V8String::new(scope, "__nx_decode_utf8").unwrap();
        global.set(scope, decode_key.into(), decode.into());
        context_global = v8::Global::new(scope, context);
    }
    let state = Box::new(State {
        isolate,
        context: context_global,
    });
    let ptr = Box::into_raw(state);
    STATE.with(|s| s.set(ptr));
    ptr as *mut c_void
}

#[no_mangle]
pub extern "C" fn nv8_set_host_callback(cb: Option<HostCb>) {
    HOST_CB.with(|c| c.set(cb));
}

#[no_mangle]
pub extern "C" fn nv8_set_buffer_callbacks(
    take: Option<TakeBufferCb>,
    put: Option<PutBufferCb>,
) {
    TAKE_BUFFER_CB.with(|c| c.set(take));
    PUT_BUFFER_CB.with(|c| c.set(put));
}

#[no_mangle]
pub extern "C" fn nv8_eval(source: *const c_char) -> *mut c_char {
    let state_ptr = STATE.with(|s| s.get());
    if state_ptr.is_null() || source.is_null() {
        return string_result("null".to_string());
    }
    let state = unsafe { &mut *state_ptr };
    let source = unsafe { CStr::from_ptr(source) }.to_string_lossy().to_string();
    let State { isolate, context } = state;
    let isolate = &mut **isolate;
    v8::scope!(let handle_scope, isolate);
    let context = v8::Local::new(handle_scope, &*context);
    let scope = &mut ContextScope::new(handle_scope, context);
    let Some(code) = V8String::new(scope, &source) else {
        return string_result("null".to_string());
    };
    let Some(script) = v8::Script::compile(scope, code, None) else {
        return string_result(r#"{"__nativax_error":"compile error"}"#.to_string());
    };
    let Some(result) = script.run(scope) else {
        return string_result(r#"{"__nativax_error":"runtime error"}"#.to_string());
    };
    string_result(json_result(scope, result))
}

#[no_mangle]
pub extern "C" fn nv8_call_global(
    name: *const c_char,
    argument: *const c_char,
) -> *mut c_char {
    let state_ptr = STATE.with(|s| s.get());
    if state_ptr.is_null() || name.is_null() {
        return string_result("null".to_string());
    }
    let state = unsafe { &mut *state_ptr };
    let name = unsafe { CStr::from_ptr(name) }.to_string_lossy().to_string();
    let argument = if argument.is_null() {
        "null".to_string()
    } else {
        unsafe { CStr::from_ptr(argument) }.to_string_lossy().to_string()
    };
    let State { isolate, context } = state;
    let isolate = &mut **isolate;
    v8::scope!(let handle_scope, isolate);
    let context = v8::Local::new(handle_scope, &*context);
    let scope = &mut ContextScope::new(handle_scope, context);
    let global = context.global(scope);
    let Some(dispatcher_key) = V8String::new(scope, "__nx_call") else {
        return string_result("null".to_string());
    };
    let Some(dispatcher) = global.get(scope, dispatcher_key.into()) else {
        return string_result("null".to_string());
    };
    let Some(dispatcher) = v8::Local::<v8::Function>::try_from(dispatcher).ok() else {
        return string_result("null".to_string());
    };
    let Some(name_value) = V8String::new(scope, &name) else {
        return string_result("null".to_string());
    };
    let Some(arg_value) = V8String::new(scope, &argument)
        .and_then(|s| v8::json::parse(scope, s))
    else {
        return string_result("null".to_string());
    };
    let recv = global.into();
    let Some(result) = dispatcher.call(scope, recv, &[name_value.into(), arg_value]) else {
        return string_result(r#"{"__nativax_error":"call error"}"#.to_string());
    };
    string_result(json_result(scope, result))
}

#[no_mangle]
pub extern "C" fn nv8_memory_used() -> u64 {
    let state_ptr = STATE.with(|s| s.get());
    if state_ptr.is_null() {
        return 0;
    }
    let state = unsafe { &mut *state_ptr };
    state.isolate.get_heap_statistics().used_heap_size() as u64
}

#[no_mangle]
pub extern "C" fn nv8_drain_microtasks() -> u32 {
    let state_ptr = STATE.with(|s| s.get());
    if !state_ptr.is_null() {
        let state = unsafe { &mut *state_ptr };
        state.isolate.perform_microtask_checkpoint();
    }
    0
}

#[no_mangle]
pub extern "C" fn nv8_has_pending_microtasks() -> u32 {
    0
}

#[no_mangle]
pub extern "C" fn nv8_gc() {
    let state_ptr = STATE.with(|s| s.get());
    if !state_ptr.is_null() {
        let state = unsafe { &mut *state_ptr };
        state
            .isolate
            .request_garbage_collection_for_testing(v8::GarbageCollectionType::Full);
    }
}

#[no_mangle]
pub extern "C" fn nv8_dispose() {
    let ptr = STATE.with(|s| s.replace(std::ptr::null_mut()));
    if !ptr.is_null() {
        unsafe {
            drop(Box::from_raw(ptr));
        }
    }
}

#[no_mangle]
pub extern "C" fn nv8_free(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        drop(CString::from_raw(ptr));
    }
}

/// Parses a JSON file with V8's native JSON parser and returns the array
/// length (or 0 on error). Used by the Dart FFI prototype only.
#[no_mangle]
pub extern "C" fn nv8_parse_json_file(path: *const c_char) -> u32 {
    init_v8();
    if path.is_null() {
        return 0;
    }
    let path = unsafe { CStr::from_ptr(path) }.to_string_lossy().to_string();
    let text = match std::fs::read_to_string(&path) {
        Ok(v) => v,
        Err(_) => return 0,
    };
    let isolate = &mut Isolate::new(v8::CreateParams::default());
    v8::scope!(let handle_scope, isolate);
    let context = Context::new(handle_scope, Default::default());
    let scope = &mut ContextScope::new(handle_scope, context);
    let source = match V8String::new(scope, &text) {
        Some(s) => s,
        None => return 0,
    };
    let parsed = match v8::json::parse(scope, source) {
        Some(v) => v,
        None => return 0,
    };
    let obj = match parsed.to_object(scope) {
        Some(o) => o,
        None => return 0,
    };
    let key = V8String::new(scope, "length").unwrap();
    match obj.get(scope, key.into()) {
        Some(v) => v.uint32_value(scope).unwrap_or(0),
        None => 0,
    }
}
