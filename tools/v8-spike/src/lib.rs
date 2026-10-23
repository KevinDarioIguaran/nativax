use std::ffi::{c_char, CStr};
use std::sync::Once;
use v8::{Context, ContextScope, Isolate, String as V8String};

static INIT: Once = Once::new();

fn init_v8() {
    INIT.call_once(|| {
        let platform = v8::new_default_platform(0, false).make_shared();
        v8::V8::initialize_platform(platform);
        v8::V8::initialize();
    });
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

/// Evaluates a JS expression and returns its string form. The caller owns the
/// returned C string and must free it with `nv8_free`.
#[no_mangle]
pub extern "C" fn nv8_eval(source: *const c_char) -> *mut c_char {
    init_v8();
    if source.is_null() {
        return std::ptr::null_mut();
    }
    let source = unsafe { CStr::from_ptr(source) }.to_string_lossy().to_string();
    let isolate = &mut Isolate::new(v8::CreateParams::default());
    v8::scope!(let handle_scope, isolate);
    let context = Context::new(handle_scope, Default::default());
    let scope = &mut ContextScope::new(handle_scope, context);
    let source = match V8String::new(scope, &source) {
        Some(s) => s,
        None => return std::ptr::null_mut(),
    };
    let script = match v8::Script::compile(scope, source, None) {
        Some(s) => s,
        None => return std::ptr::null_mut(),
    };
    let result = match script.run(scope) {
        Some(v) => v,
        None => return std::ptr::null_mut(),
    };
    let text = result.to_string(scope).map(|s| s.to_rust_string_lossy(scope)).unwrap_or_default();
    match std::ffi::CString::new(text) {
        Ok(s) => s.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn nv8_free(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        drop(std::ffi::CString::from_raw(ptr));
    }
}
