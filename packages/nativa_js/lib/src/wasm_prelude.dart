/// The `WebAssembly.*` surface. It is installed right after the host prelude,
/// before any document or worker script runs. All heavy lifting (parsing,
/// validation, linking, calls and linear memory) happens in
/// `src/nativax_wasm.c`; this layer only supplies the browser-facing classes
/// and keeps native handles alive for exactly as long as their exports are.
const String wasmPrelude = r'''
(() => {
'use strict';
const native = globalThis.__nx_wasm_native;
delete globalThis.__nx_wasm_native;
if (!native) return;

const HANDLE = Symbol('nativax.wasm.handle');
const MEMORY = Symbol('nativax.wasm.memory');
const define = (obj, name, value) =>
  Object.defineProperty(obj, name, { value, writable: false, enumerable: false, configurable: true });
const defineExport = (obj, name, value) =>
  Object.defineProperty(obj, name, { value, writable: true, enumerable: true, configurable: true });
const KIND_NAMES = ['function', 'table', 'memory', 'global'];

class CompileError extends Error {
  constructor(message) { super(message); this.name = 'CompileError'; }
}
class LinkError extends Error {
  constructor(message) { super(message); this.name = 'LinkError'; }
}
class RuntimeError extends Error {
  constructor(message) { super(message); this.name = 'RuntimeError'; }
}
for (const C of [CompileError, LinkError, RuntimeError]) C.prototype[Symbol.toStringTag] = 'Error';

const errors = { CompileError, LinkError, RuntimeError };
const convertError = (e, fallback) => {
  if (e && e.name === 'LinkError') return new LinkError(e.message);
  if (e && e.name === 'RuntimeError') return new RuntimeError(e.message);
  if (e && e.name === 'CompileError') return new CompileError(e.message);
  return new (errors[fallback] || Error)(e && e.message !== undefined ? e.message : String(e));
};

const registry = typeof FinalizationRegistry === 'function'
  ? new FinalizationRegistry((entry) => {
      try {
        if (entry.kind === 0) native.releaseModule(entry.handle);
        else native.releaseInstance(entry.handle);
      } catch (_) {}
    })
  : null;
const keep = (owner, entry) => { if (registry) registry.register(owner, entry, owner); };

/* State shared by an Instance and everything reachable through its exports.
 * An exported function keeps the instance (and therefore the module bytes)
 * alive exactly like the browser's exported-function identity does. */
const releaseState = (state) => {
  if (state.released) return;
  state.released = true;
  try { native.releaseInstance(state.handle); } catch (_) {}
};

class Module {
  constructor(bytes) {
    if (new.target !== Module) throw new TypeError('Class constructor Module cannot be invoked without new');
    if (typeof DataView !== 'undefined' && bytes instanceof DataView) {
      bytes = new Uint8Array(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    }
    if (!(bytes instanceof ArrayBuffer) &&
        !(typeof SharedArrayBuffer !== 'undefined' && bytes instanceof SharedArrayBuffer) &&
        !ArrayBuffer.isView(bytes)) {
      throw new TypeError('WebAssembly.Module expects a BufferSource');
    }
    let handle;
    try {
      handle = native.compile(bytes);
    } catch (e) {
      throw convertError(e, 'CompileError');
    }
    define(this, HANDLE, { handle });
    keep(this, { kind: 0, handle });
  }
  get [Symbol.toStringTag]() { return 'WebAssembly.Module'; }
  static exports(module) {
    if (!(module instanceof Module)) throw new TypeError('WebAssembly.Module expected');
    return native.moduleInfo(module[HANDLE].handle).exports.map((e) =>
      Object.freeze({ name: e.name, kind: KIND_NAMES[e.kind] }));
  }
  static imports(module) {
    if (!(module instanceof Module)) throw new TypeError('WebAssembly.Module expected');
    return native.moduleInfo(module[HANDLE].handle).imports.map((i) =>
      Object.freeze({ module: i.module, name: i.name, kind: KIND_NAMES[i.kind] }));
  }
  static customSections() { return []; }
}

const memoryBuffer = (state, id) => native.memory(state.handle, id);

class Memory {
  constructor(token, state, id, descriptor) {
    if (token !== MEMORY) {
      throw new TypeError('WebAssembly.Memory objects are created by an Instance');
    }
    define(this, HANDLE, { state, id, descriptor });
  }
  get buffer() {
    const h = this[HANDLE];
    if (h.state.released) throw new TypeError('WebAssembly.Memory is no longer available');
    return memoryBuffer(h.state, h.id);
  }
  grow(delta) {
    const h = this[HANDLE];
    if (h.state.released) throw new TypeError('WebAssembly.Memory is no longer available');
    delta = delta | 0;
    if (delta < 0) throw new RangeError('WebAssembly.Memory.grow expects a non-negative delta');
    return native.grow(h.state.handle, h.id, delta);
  }
  get [Symbol.toStringTag]() { return 'WebAssembly.Memory'; }
}

class Table {
  constructor() {
    throw new TypeError('WebAssembly.Table is not supported by this build yet');
  }
  get [Symbol.toStringTag]() { return 'WebAssembly.Table'; }
}

class Global {
  constructor() {
    throw new TypeError('WebAssembly.Global is not supported by this build yet');
  }
  get [Symbol.toStringTag]() { return 'WebAssembly.Global'; }
}

const buildExports = (state) => {
  const descriptors = native.exports(state.handle);
  const exports = {};
  for (const desc of descriptors) {
    if (desc.kind === 0) {
      const fn = (...args) => {
        if (state.released) throw new TypeError('WebAssembly.Instance is no longer available');
        try {
          return native.call(state.handle, desc.id, ...args);
        } catch (e) {
          // Traps are represented as Error objects with a WebAssembly name in
          // C; give them their real constructor. Exceptions thrown by a JS
          // import (RangeError, DOMException, ...) pass through untouched.
          if (e && (e.name === 'RuntimeError' || e.name === 'LinkError' || e.name === 'CompileError')) {
            throw convertError(e, e.name);
          }
          throw e;
        }
      };
      define(fn, 'name', desc.name);
      define(fn, 'length', desc.args.length);
      defineExport(exports, desc.name, fn);
    } else if (desc.kind === 2) {
      defineExport(exports, desc.name, new Memory(MEMORY, state, desc.id, desc));
    } else if (desc.kind === 1) {
      throw new LinkError('exported WebAssembly.Table is not supported yet');
    } else if (desc.kind === 3) {
      throw new LinkError('exported WebAssembly.Global is not supported yet');
    }
  }
  return exports;
};

class Instance {
  constructor(module, importObject) {
    if (new.target !== Instance) throw new TypeError('Class constructor Instance cannot be invoked without new');
    if (!(module instanceof Module)) throw new TypeError('WebAssembly.Instance expects a Module');
    if (importObject === undefined || importObject === null) importObject = {};
    if (typeof importObject !== 'object') throw new TypeError('imports must be an object');
    let handle;
    try {
      handle = native.instantiate(module[HANDLE].handle, importObject);
    } catch (e) {
      throw convertError(e, 'LinkError');
    }
    const state = { handle, module, released: false };
    define(this, HANDLE, state);
    try {
      define(this, 'exports', buildExports(state));
    } catch (e) {
      releaseState(state);
      throw e;
    }
    keep(state, { kind: 1, handle });
  }
  get [Symbol.toStringTag]() { return 'WebAssembly.Instance'; }
}

const compile = async (bytes) => new Module(bytes);

const instantiate = async (bytesOrModule, importObject) => {
  if (bytesOrModule instanceof Module) {
    return new Instance(bytesOrModule, importObject);
  }
  const module = new Module(bytesOrModule);
  return { module, instance: new Instance(module, importObject) };
};

const instantiateStreaming = async (source, importObject) => {
  if (!source || typeof source.arrayBuffer !== 'function') {
    throw new TypeError('WebAssembly.instantiateStreaming expects a Response');
  }
  return instantiate(await source.arrayBuffer(), importObject);
};

const validate = (bytes) => {
  try { return !!native.validate(bytes); } catch (_) { return false; }
};

const WebAssembly = Object.freeze({
  Module, Instance, Memory, Table, Global,
  CompileError, LinkError, RuntimeError,
  compile, instantiate, instantiateStreaming, validate,
});
define(globalThis, 'WebAssembly', WebAssembly);
})();
''';
