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
    /// Owned by the near-heap-limit callback; freed on dispose.
    heap_handle: *mut v8::IsolateHandle,
}

impl Drop for State {
    fn drop(&mut self) {
        if !self.heap_handle.is_null() {
            // Unregister before freeing the callback's data.
            self.isolate
                .remove_near_heap_limit_callback(near_heap_limit, 0);
            unsafe { drop(Box::from_raw(self.heap_handle)) };
            self.heap_handle = std::ptr::null_mut();
        }
    }
}

/// Extra room granted once the heap limit is near, so V8 can unwind the
/// terminated script instead of aborting the process.
const HEAP_HEADROOM: usize = 16 * 1024 * 1024;

/// Near the heap limit: stop the running script (uncatchable termination)
/// and report it, instead of letting V8 abort with an OOM.
unsafe extern "C" fn near_heap_limit(
    data: *mut c_void,
    current_heap_limit: usize,
    _initial_heap_limit: usize,
) -> usize {
    HEAP_EXHAUSTED.with(|f| f.set(true));
    TERMINATED.with(|f| f.set(true));
    let handle = unsafe { &*(data as *const v8::IsolateHandle) };
    handle.terminate_execution();
    current_heap_limit + HEAP_HEADROOM
}

/// Asks the kernel to drop this library's clean, file-backed pages from the
/// resident set. Startup (snapshot deserialisation) touches most of the
/// ~26 MB of builtins once; only the hot pages fault back in afterwards.
/// No effect on behaviour: the pages are re-read from the file on demand.
fn release_cold_code_pages() {
    const MADV_PAGEOUT: libc::c_int = 21;
    let mut info: libc::Dl_info = unsafe { std::mem::zeroed() };
    let anchor = release_cold_code_pages as *const c_void;
    if unsafe { libc::dladdr(anchor, &mut info) } == 0 || info.dli_fname.is_null() {
        return;
    }
    let path = unsafe { CStr::from_ptr(info.dli_fname) }.to_string_lossy().to_string();
    let Ok(maps) = std::fs::read_to_string("/proc/self/maps") else {
        return;
    };
    for line in maps.lines() {
        let mut fields = line.split_whitespace();
        let (Some(range), Some(perms)) = (fields.next(), fields.next()) else {
            continue;
        };
        // Only read-only/executable mappings: never touch writable data.
        if perms.contains('w') || !line.ends_with(path.as_str()) {
            continue;
        }
        let Some((start, end)) = range.split_once('-') else {
            continue;
        };
        let (Ok(start), Ok(end)) = (
            usize::from_str_radix(start, 16),
            usize::from_str_radix(end, 16),
        ) else {
            continue;
        };
        unsafe { libc::madvise(start as *mut c_void, end - start, MADV_PAGEOUT) };
    }
}

const MEMORY_ERROR: &str = r#"{"__nativax_error":"heap limit reached","kind":"memory"}"#;

/// After script ran: when the heap callback terminated it, clear the
/// termination so the isolate stays usable and report a memory error.
fn memory_error(isolate: &v8::Isolate) -> Option<*mut c_char> {
    if !TERMINATED.with(|f| f.replace(false)) {
        return None;
    }
    isolate.cancel_terminate_execution();
    Some(string_result(MEMORY_ERROR.to_string()))
}

thread_local! {
    static STATE: Cell<*mut State> = const { Cell::new(std::ptr::null_mut()) };
    static HOST_CB: Cell<Option<HostCb>> = const { Cell::new(None) };
    static TAKE_BUFFER_CB: Cell<Option<TakeBufferCb>> = const { Cell::new(None) };
    static PUT_BUFFER_CB: Cell<Option<PutBufferCb>> = const { Cell::new(None) };
    static HEAP_EXHAUSTED: Cell<bool> = const { Cell::new(false) };
    /// Set by the heap callback, consumed by the call that was terminated.
    static TERMINATED: Cell<bool> = const { Cell::new(false) };
}

fn init_v8() {
    INIT.call_once(|| {
        // Extra V8 flags for memory experiments (e.g. "--lite-mode").
        if let Ok(flags) = std::env::var("NATIVAX_V8_FLAGS") {
            v8::V8::set_flags_from_string(&flags);
        }
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
    let heap_handle = Box::into_raw(Box::new(isolate.thread_safe_handle()));
    isolate.add_near_heap_limit_callback(near_heap_limit, heap_handle as *mut c_void);
    HEAP_EXHAUSTED.with(|f| f.set(false));
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
        heap_handle,
    });
    let ptr = Box::into_raw(state);
    STATE.with(|s| s.set(ptr));
    if std::env::var("NATIVAX_V8_KEEP_CODE").is_err() {
        release_cold_code_pages();
    }
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
    let State { isolate, context, .. } = state;
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
    let result = script.run(scope);
    if let Some(error) = memory_error(scope) {
        return error;
    }
    let Some(result) = result else {
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
    let State { isolate, context, .. } = state;
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
    let result = dispatcher.call(scope, recv, &[name_value.into(), arg_value]);
    if let Some(error) = memory_error(scope) {
        return error;
    }
    let Some(result) = result else {
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
        if TERMINATED.with(|f| f.replace(false)) {
            state.isolate.cancel_terminate_execution();
        }
    }
    0
}

/// 1 when a script was stopped at the heap limit since the last clear.
#[no_mangle]
pub extern "C" fn nv8_heap_exhausted() -> u32 {
    HEAP_EXHAUSTED.with(|f| f.get()) as u32
}

#[no_mangle]
pub extern "C" fn nv8_clear_heap_exhausted() {
    HEAP_EXHAUSTED.with(|f| f.set(false));
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
        state.isolate.low_memory_notification();
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
