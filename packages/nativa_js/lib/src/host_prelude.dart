/// Installed once per context. Captures the raw `__nx_host` C function,
/// removes it from the global object and exposes the frozen `__nx.host`
/// wrapper that turns host error envelopes into real script exceptions.
const String nativaxHostPrelude = r'''
(() => {
  const raw = globalThis.__nx_host;
  const rawRegister = globalThis.__nx_register;
  const takeBuffer = globalThis.__nx_buffer_take;
  const putBuffer = globalThis.__nx_buffer_put;
  const shareSab = globalThis.__nx_sab_share;
  const openSab = globalThis.__nx_sab_open;
  const gl = globalThis.__nx_gl_native || null;
  const decodeUtf8 = globalThis.__nx_decode_utf8 || null;
  delete globalThis.__nx_decode_utf8;
  delete globalThis.__nx_sab_share;
  delete globalThis.__nx_sab_open;
  delete globalThis.__nx_gl_native;
  delete globalThis.__nx_host;
  delete globalThis.__nx_register;
  delete globalThis.__nx_buffer_take;
  delete globalThis.__nx_buffer_put;
  // Callbacks for Engine.callGlobal live in a registry scripts cannot reach.
  const register = (name, fn) => rawRegister(String(name), fn);
  const ctors = { Error, TypeError, RangeError, SyntaxError };
  const domNames = new Set([
    'IndexSizeError', 'HierarchyRequestError', 'WrongDocumentError', 'InvalidCharacterError',
    'NoModificationAllowedError', 'NotFoundError', 'NotSupportedError', 'InUseAttributeError',
    'InvalidStateError', 'SyntaxError', 'InvalidModificationError', 'NamespaceError',
    'InvalidAccessError', 'TypeMismatchError', 'SecurityError', 'NetworkError', 'AbortError',
    'URLMismatchError', 'QuotaExceededError', 'TimeoutError', 'InvalidNodeTypeError',
    'DataCloneError', 'EncodingError', 'NotReadableError', 'UnknownError', 'ConstraintError',
    'DataError', 'TransactionInactiveError', 'ReadOnlyError', 'VersionError', 'OperationError',
    'NotAllowedError', 'OptOutError',
  ]);
  const stringify = JSON.stringify;
  const hasOwn = Object.prototype.hasOwnProperty;
  const host = (name, ...args) => {
    const r = raw(stringify([name, args]));
    if (r === undefined || r === null) return undefined;
    if (hasOwn.call(r, 'error')) {
      const type = r.error.type;
      if (globalThis.DOMException && domNames.has(type)) {
        throw new globalThis.DOMException(r.error.message, type);
      }
      const C = ctors[type];
      const e = C ? new C(r.error.message) : new Error(r.error.message);
      if (!C) e.name = type;
      throw e;
    }
    return r.ok;
  };
  // Rejected module evaluations (top-level await, failed imports).
  rawRegister('__nx_module_error', (e) => {
    try {
      raw(stringify(['__module_error', [{
        name: e && e.name ? String(e.name) : 'Error',
        message: e && e.message !== undefined ? String(e.message) : String(e),
        stack: e && e.stack ? String(e.stack) : '',
      }]]));
    } catch (_) {}
  });
  Object.defineProperty(globalThis, '__nx', {
    value: Object.freeze({ host, register, takeBuffer, putBuffer, shareSab, openSab, gl, decodeUtf8 }),
    enumerable: false, writable: false, configurable: true,
  });
})();
''';
