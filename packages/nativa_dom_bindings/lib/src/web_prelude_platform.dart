import 'web_prelude_audio.dart';
import 'web_prelude_cssom.dart';
import 'web_prelude_intl.dart';

/// Window-level platform APIs (part of the web platform prelude).
const String webPlatformApis =
    webAudio + _platform + webIntl + _observers + webCssom + _document;

const String _platform = r'''
// ============================================================================
// Timing, animation frames, randomness, encoding, cloning
// ============================================================================
const perfOrigin = host('perf.origin');
const perfEntries = [];
class PerformanceEntry {
  constructor(name, entryType, startTime, duration, detail = null) {
    Object.assign(this, { name, entryType, startTime, duration, detail });
  }
  toJSON() { const { name, entryType, startTime, duration, detail } = this; return { name, entryType, startTime, duration, detail }; }
}
class PerformanceMark extends PerformanceEntry {
  constructor(name, options = {}) { super(String(name), 'mark', options.startTime ?? performance.now(), 0, options.detail ?? null); }
}
class PerformanceMeasure extends PerformanceEntry {}
const markTime = (v) => {
  if (v === undefined) return undefined;
  if (typeof v === 'number') return v;
  const m = [...perfEntries].reverse().find((e) => e.entryType === 'mark' && e.name === v);
  if (!m) throw new DOMException(`The mark '${v}' does not exist.`, 'SyntaxError');
  return m.startTime;
};
const performance = Object.assign(new EventTarget(), {
  now: () => host('perf.now'),
  get timeOrigin() { return perfOrigin; },
  mark(name, options) { const m = new PerformanceMark(name, options); perfEntries.push(m); return m; },
  measure(name, a, b) {
    let start, end, detail = null;
    if (a && typeof a === 'object') { start = markTime(a.start) ?? 0; end = markTime(a.end) ?? (a.duration !== undefined ? start + a.duration : performance.now()); detail = a.detail ?? null; }
    else { start = markTime(a) ?? 0; end = markTime(b) ?? performance.now(); }
    const m = new PerformanceMeasure(String(name), 'measure', start, end - start, detail);
    perfEntries.push(m);
    return m;
  },
  getEntries() { return perfEntries.slice(); },
  getEntriesByType(t) { return t === 'navigation' ? [navigationEntry] : perfEntries.filter((e) => e.entryType === t); },
  getEntriesByName(n, t) { return perfEntries.filter((e) => e.name === n && (!t || e.entryType === t)); },
  clearMarks(n) { for (let i = perfEntries.length - 1; i >= 0; i--) if (perfEntries[i].entryType === 'mark' && (n === undefined || perfEntries[i].name === n)) perfEntries.splice(i, 1); },
  clearMeasures(n) { for (let i = perfEntries.length - 1; i >= 0; i--) if (perfEntries[i].entryType === 'measure' && (n === undefined || perfEntries[i].name === n)) perfEntries.splice(i, 1); },
  clearResourceTimings() {},
  setResourceTimingBufferSize() {},
  toJSON() { return { timeOrigin: perfOrigin }; },
  timing: { navigationStart: perfOrigin },
  navigation: { type: 0, redirectCount: 0 },
  eventCounts: new Map(),
});
const navigationEntry = new PerformanceEntry('document', 'navigation', 0, 0);
Object.assign(navigationEntry, {
  type: 'navigate', redirectCount: 0, initiatorType: 'navigation', nextHopProtocol: '', workerStart: 0,
  redirectStart: 0, redirectEnd: 0, fetchStart: 0, domainLookupStart: 0, domainLookupEnd: 0, connectStart: 0,
  connectEnd: 0, secureConnectionStart: 0, requestStart: 0, responseStart: 0, responseEnd: 0, transferSize: 0,
  encodedBodySize: 0, decodedBodySize: 0, unloadEventStart: 0, unloadEventEnd: 0, domInteractive: 0,
  domContentLoadedEventStart: 0, domContentLoadedEventEnd: 0, domComplete: 0, loadEventStart: 0, loadEventEnd: 0,
});
class PerformanceObserver {
  constructor(cb) { this._cb = cb; }
  observe() {}
  disconnect() {}
  takeRecords() { return []; }
}
PerformanceObserver.supportedEntryTypes = ['mark', 'measure', 'navigation'];

// Animation frames run at ~60 Hz on the timer loop.
const frameCallbacks = new Map();
let nextFrame = 1;
let frameTimer = null;
// Frames are paced at 60 Hz against a fixed grid, so timer lateness does not
// accumulate into a lower frame rate.
const framePeriod = 1000 / 60;
let lastFrame = 0;
const runFrame = () => {
  frameTimer = null;
  const now = performance.now();
  lastFrame = now;
  const batch = [...frameCallbacks];
  frameCallbacks.clear();
  for (const [, cb] of batch) { try { cb(now); } catch (e) { reportError(e); } }
};
const requestAnimationFrame = (cb) => {
  if (typeof cb !== 'function') throw new TypeError('callback is not a function');
  const id = nextFrame++;
  frameCallbacks.set(id, cb);
  if (frameTimer === null) {
    const now = performance.now();
    const due = lastFrame + framePeriod - now;
    frameTimer = setTimeout(runFrame, due > 1 ? Math.floor(due) : 0);
  }
  return id;
};
const cancelAnimationFrame = (id) => { frameCallbacks.delete(id); };
const requestIdleCallback = (cb, opts) => setTimeout(() => {
  const start = performance.now();
  cb({ didTimeout: false, timeRemaining: () => Math.max(0, 50 - (performance.now() - start)) });
}, 1);
const cancelIdleCallback = (id) => clearTimeout(id);

const crypto = {
  getRandomValues(arr) {
    if (!ArrayBuffer.isView(arr) || arr instanceof Float32Array || arr instanceof Float64Array) {
      throw new DOMException('The provided ArrayBufferView is not an integer array', 'TypeMismatchError');
    }
    if (arr.byteLength > 65536) throw new DOMException('quota exceeded', 'QuotaExceededError');
    const bytes = host('crypto.random', arr.byteLength);
    new Uint8Array(arr.buffer, arr.byteOffset, arr.byteLength).set(bytes);
    return arr;
  },
  randomUUID() {
    const b = crypto.getRandomValues(new Uint8Array(16));
    b[6] = (b[6] & 0x0f) | 0x40; b[8] = (b[8] & 0x3f) | 0x80;
    const h = [...b].map((x) => x.toString(16).padStart(2, '0')).join('');
    return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
  },
  subtle: undefined,
};

// UTF-8 TextEncoder / TextDecoder.
const utf8Encode = (s) => {
  s = String(s);
  const out = [];
  for (let i = 0; i < s.length; i++) {
    let c = s.charCodeAt(i);
    if (c >= 0xd800 && c <= 0xdbff && i + 1 < s.length) {
      const d = s.charCodeAt(i + 1);
      if (d >= 0xdc00 && d <= 0xdfff) { c = 0x10000 + ((c - 0xd800) << 10) + (d - 0xdc00); i++; }
      else c = 0xfffd;
    } else if (c >= 0xd800 && c <= 0xdfff) c = 0xfffd;
    if (c < 0x80) out.push(c);
    else if (c < 0x800) out.push(0xc0 | (c >> 6), 0x80 | (c & 63));
    else if (c < 0x10000) out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
    else out.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 63), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
  }
  return new Uint8Array(out);
};
const utf8Decode = (bytes, fatal = false) => {
  let s = '';
  for (let i = 0; i < bytes.length;) {
    const b = bytes[i];
    let c, n;
    if (b < 0x80) { c = b; n = 1; }
    else if (b >= 0xc2 && b < 0xe0) { c = b & 31; n = 2; }
    else if (b >= 0xe0 && b < 0xf0) { c = b & 15; n = 3; }
    else if (b >= 0xf0 && b < 0xf5) { c = b & 7; n = 4; }
    else { if (fatal) throw new TypeError('The encoded data was not valid.'); s += '�'; i++; continue; }
    if (i + n > bytes.length) { if (fatal) throw new TypeError('The encoded data was not valid.'); s += '�'; break; }
    let ok = true;
    for (let k = 1; k < n; k++) {
      const x = bytes[i + k];
      if ((x & 0xc0) !== 0x80) { ok = false; break; }
      c = (c << 6) | (x & 63);
    }
    if (!ok) { if (fatal) throw new TypeError('The encoded data was not valid.'); s += '�'; i++; continue; }
    s += String.fromCodePoint(c);
    i += n;
  }
  return s;
};
const toBytes = (v) => {
  if (v instanceof Uint8Array) return v;
  if (ArrayBuffer.isView(v)) return new Uint8Array(v.buffer, v.byteOffset, v.byteLength);
  if (v instanceof ArrayBuffer) return new Uint8Array(v);
  return utf8Encode(v);
};
class TextEncoder {
  get encoding() { return 'utf-8'; }
  encode(s = '') { return utf8Encode(s); }
  encodeInto(s, dest) { const b = utf8Encode(s); const n = Math.min(b.length, dest.length); dest.set(b.subarray(0, n)); return { read: String(s).length, written: n }; }
}
class TextDecoder {
  constructor(label = 'utf-8', options = {}) {
    const l = String(label).toLowerCase();
    if (!['utf-8', 'utf8', 'unicode-1-1-utf-8'].includes(l)) throw new RangeError(`The encoding label provided ('${label}') is invalid.`);
    hidden(this, '_fatal', !!options.fatal);
    hidden(this, '_bom', !!options.ignoreBOM);
  }
  get encoding() { return 'utf-8'; }
  get fatal() { return this._fatal; }
  get ignoreBOM() { return this._bom; }
  decode(input) {
    if (input === undefined) return '';
    let b = toBytes(input);
    if (!this._bom && b.length >= 3 && b[0] === 0xef && b[1] === 0xbb && b[2] === 0xbf) b = b.subarray(3);
    return utf8Decode(b, this._fatal);
  }
}

const b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
const btoa = (s) => {
  s = String(s);
  let out = '';
  for (let i = 0; i < s.length; i += 3) {
    const a = s.charCodeAt(i), b = s.charCodeAt(i + 1), c = s.charCodeAt(i + 2);
    if (a > 255 || b > 255 || c > 255) throw new DOMException('The string to be encoded contains characters outside of the Latin1 range.', 'InvalidCharacterError');
    const n = (a << 16) | ((b || 0) << 8) | (c || 0);
    out += b64chars[n >> 18] + b64chars[(n >> 12) & 63] + (i + 1 < s.length ? b64chars[(n >> 6) & 63] : '=') + (i + 2 < s.length ? b64chars[n & 63] : '=');
  }
  return out;
};
const atob = (s) => {
  s = String(s).replace(/[\t\n\f\r ]/g, '');
  if (s.length % 4 === 0) s = s.replace(/==?$/, '');
  if (s.length % 4 === 1 || /[^A-Za-z0-9+/]/.test(s)) throw new DOMException('The string to be decoded is not correctly encoded.', 'InvalidCharacterError');
  let out = '', bits = 0, acc = 0;
  for (const ch of s) {
    acc = (acc << 6) | b64chars.indexOf(ch);
    bits += 6;
    if (bits >= 8) { bits -= 8; out += String.fromCharCode((acc >> bits) & 255); }
  }
  return out;
};
const bytesToBase64 = (bytes) => { let s = ''; for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]); return btoa(s); };
const base64ToBytes = (b64) => { const s = atob(b64); const out = new Uint8Array(s.length); for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i); return out; };

// ============================================================================
// Structured serialization (HTML §2.7): the wire format crossing runtimes.
// Plain JSON-compatible tree; byte payloads travel as parked native buffers
// (__nx.putBuffer/takeBuffer), shared memory as SAB handles.
// ============================================================================
const shareSab = __nx.shareSab;
const openSab = __nx.openSab;
const cloneError = (what) => new DOMException(`${what} could not be cloned.`, 'DataCloneError');
const typedArrayNames = ['Int8Array', 'Uint8Array', 'Uint8ClampedArray', 'Int16Array', 'Uint16Array', 'Int32Array', 'Uint32Array',
  'Float32Array', 'Float64Array', 'BigInt64Array', 'BigUint64Array', 'Float16Array'];
// Hooks for host objects (OffscreenCanvas, ImageBitmap): name -> { test, write, read }.
const transferables = new Map();
const isSab = (v) => typeof SharedArrayBuffer !== 'undefined' && v instanceof SharedArrayBuffer;
const serializeWire = (value, transfer = []) => {
  const refs = new Map();
  const transferSet = new Set(transfer);
  for (const t of transferSet) {
    if (t instanceof ArrayBuffer && t.detached) throw new DOMException('An ArrayBuffer is detached and could not be cloned.', 'DataCloneError');
  }
  const pending = []; // ArrayBuffers to detach after a successful serialization
  const ports = [];
  const write = (v) => {
    switch (typeof v) {
      case 'undefined': return ['u'];
      case 'boolean': case 'string': return v;
      case 'number':
        if (Number.isFinite(v) && !Object.is(v, -0)) return v;
        return ['n', Object.is(v, -0) ? '-0' : String(v)];
      case 'bigint': return ['b', v.toString()];
      case 'symbol': case 'function': throw cloneError(String(v));
    }
    if (v === null) return null;
    if (refs.has(v)) return ['r', refs.get(v)];
    const id = refs.size;
    refs.set(v, id);
    for (const [name, h] of transferables) {
      if (h.test(v)) {
        if (h.transferOnly && !transferSet.has(v)) throw cloneError(name);
        return ['H', id, name, h.write(v, transferSet.has(v))];
      }
    }
    if (v instanceof ArrayBuffer) {
      if (transferSet.has(v)) pending.push(v);
      return ['AB', id, putBuffer(v)];
    }
    if (isSab(v)) return ['SAB', id, shareSab(v)];
    if (ArrayBuffer.isView(v)) {
      const ctor = v instanceof DataView ? 'DataView' : typedArrayNames.find((n) => globalThis[n] && v instanceof globalThis[n]);
      if (!ctor) throw cloneError('view');
      return ['T', id, ctor, write(v.buffer), v.byteOffset, ctor === 'DataView' ? v.byteLength : v.length];
    }
    if (v instanceof MessagePort) {
      if (!transferSet.has(v)) throw new DOMException('A MessagePort could not be cloned because it was not transferred.', 'DataCloneError');
      ports.push(v);
      return ['P', id, v._port.id];
    }
    if (v instanceof Date) return ['D', id, v.getTime()];
    if (v instanceof RegExp) return ['R', id, v.source, v.flags];
    if (v instanceof Boolean || v instanceof Number || v instanceof String) return ['W', id, typeof v.valueOf(), write(v.valueOf())];
    if (typeof BigInt !== 'undefined' && Object.prototype.toString.call(v) === '[object BigInt]') return ['W', id, 'bigint', write(v.valueOf())];
    if (v instanceof Map) { const out = ['M', id, []]; for (const [k, x] of v) out[2].push([write(k), write(x)]); return out; }
    if (v instanceof Set) { const out = ['S', id, []]; for (const x of v) out[2].push(write(x)); return out; }
    if (typeof File !== 'undefined' && v instanceof File) return ['F', id, putBuffer(v.__bytes()), v.type, v.name, v.lastModified];
    if (typeof Blob !== 'undefined' && v instanceof Blob) return ['BL', id, putBuffer(v.__bytes()), v.type];
    if (v instanceof Error) {
      const name = ['Error', 'EvalError', 'RangeError', 'ReferenceError', 'SyntaxError', 'TypeError', 'URIError'].includes(v.name) ? v.name : 'Error';
      return ['E', id, name, String(v.message), v.stack === undefined ? null : String(v.stack)];
    }
    if (Array.isArray(v)) {
      const items = [];
      for (const k of Object.keys(v)) items.push([k, write(v[k])]);
      return ['A', id, v.length, items];
    }
    if (v instanceof Promise || v instanceof WeakMap || v instanceof WeakSet || (typeof WeakRef !== 'undefined' && v instanceof WeakRef)) {
      throw cloneError(Object.prototype.toString.call(v));
    }
    if (typeof Node !== 'undefined' && (v instanceof Node || (typeof Window !== 'undefined' && v instanceof Window))) throw cloneError('A DOM node');
    const out = ['O', id, []];
    for (const k of Object.keys(v)) out[2].push([k, write(v[k])]);
    return out;
  };
  const tree = write(value);
  for (const t of transferSet) {
    if (!(t instanceof ArrayBuffer) && !(t instanceof MessagePort) && ![...transferables.values()].some((h) => h.test(t))) {
      throw new DOMException('Value at index 0 does not have a transferable type.', 'DataCloneError');
    }
  }
  for (const t of transferSet) if (t instanceof MessagePort && !ports.includes(t)) { ports.push(t); }
  // Transferred buffers become detached in the sender.
  for (const b of pending) { try { structuredDetach(b); } catch (_) {} }
  for (const p of ports) p._neuter();
  const portIds = ports.map((p) => p._port.id);
  return { text: JSON.stringify([tree, portIds]), ports: portIds };
};
const serializeValue = (value, transfer) => serializeWire(value, transfer).text;
// Detaching: transfer() is the standard way; older engines lack it.
const structuredDetach = (b) => { if (typeof b.transfer === 'function') b.transfer(); };
const deserializeValue = (text) => {
  const [tree, portIds] = JSON.parse(text);
  const refs = [];
  const ports = portIds.map((id) => adoptPort(id));
  const read = (w) => {
    if (w === null || typeof w !== 'object') return w;
    const tag = w[0];
    switch (tag) {
      case 'u': return undefined;
      case 'n': return w[1] === '-0' ? -0 : Number(w[1]);
      case 'b': return BigInt(w[1]);
      case 'r': return refs[w[1]];
    }
    const id = w[1];
    let out;
    switch (tag) {
      case 'H': out = transferables.get(w[2]).read(w[3]); refs[id] = out; return out;
      case 'AB': out = takeBuffer(w[2]); refs[id] = out; return out;
      case 'SAB': out = openSab(w[2]); refs[id] = out; return out;
      case 'T': {
        const buffer = read(w[3]);
        out = w[2] === 'DataView' ? new DataView(buffer, w[4], w[5]) : new globalThis[w[2]](buffer, w[4], w[5]);
        refs[id] = out; return out;
      }
      case 'P': out = ports.find((p) => p._port.id === w[2]) || adoptPort(w[2]); refs[id] = out; return out;
      case 'D': out = new Date(w[2]); refs[id] = out; return out;
      case 'R': out = new RegExp(w[2], w[3]); refs[id] = out; return out;
      case 'W': out = Object(read(w[3])); refs[id] = out; return out;
      case 'M': out = new Map(); refs[id] = out; for (const [k, x] of w[2]) out.set(read(k), read(x)); return out;
      case 'S': out = new Set(); refs[id] = out; for (const x of w[2]) out.add(read(x)); return out;
      case 'BL': out = new Blob([new Uint8Array(takeBuffer(w[2]))], { type: w[3] }); refs[id] = out; return out;
      case 'F': out = new File([new Uint8Array(takeBuffer(w[2]))], w[4], { type: w[3], lastModified: w[5] }); refs[id] = out; return out;
      case 'E': {
        const C = globalThis[w[2]] || Error;
        out = new C(w[3]);
        if (w[4] !== null) defineProperty(out, 'stack', { value: w[4], writable: true, configurable: true });
        refs[id] = out; return out;
      }
      case 'A': out = new Array(w[2]); refs[id] = out; for (const [k, x] of w[3]) out[k] = read(x); return out;
      case 'O': out = {}; refs[id] = out; for (const [k, x] of w[2]) out[k] = read(x); return out;
    }
    throw new DOMException('Unknown serialized value', 'DataCloneError');
  };
  return { data: read(tree), ports };
};
const structuredClone = (...args) => {
  if (args.length === 0) throw new TypeError("Failed to execute 'structuredClone': 1 argument required, but only 0 present.");
  const [value, options] = args;
  const transfer = options && options.transfer ? [...options.transfer] : [];
  return deserializeValue(serializeValue(value, transfer)).data;
};

// ============================================================================
// MessagePort / MessageChannel. Ports have process-wide ids; the host routes
// messages to whichever runtime (window or worker thread) owns the partner.
// ============================================================================
const livePorts = new Map(); // id -> MessagePort
class MessagePort extends EventTarget {
  constructor(token, id) {
    if (token !== portToken) throw new TypeError('Illegal constructor');
    super();
    hidden(this, '_port', { id, started: false, closed: false, neutered: false, queue: [] });
    livePorts.set(id, this);
  }
  postMessage(message, transferOrOptions = []) {
    const st = this._port;
    if (st.neutered || st.closed) return;
    const transfer = Array.isArray(transferOrOptions) ? transferOrOptions
      : (transferOrOptions && transferOrOptions.transfer ? [...transferOrOptions.transfer] : []);
    if (transfer.includes(this)) throw new DOMException('Port cannot be transferred to itself.', 'DataCloneError');
    const w = serializeWire(message, transfer);
    host('port.post', st.id, w.text, w.ports);
  }
  start() {
    const st = this._port;
    if (st.started) return;
    st.started = true;
    const q = st.queue.splice(0);
    for (const m of q) this._dispatch(m);
  }
  close() { const st = this._port; if (st.closed) return; st.closed = true; livePorts.delete(st.id); host('port.close', st.id); }
  get onmessage() { return this._onmessage || null; }
  set onmessage(fn) {
    if (this._onmessage) this.removeEventListener('message', this._onmessage);
    defineProperty(this, '_onmessage', { value: typeof fn === 'function' ? fn : null, writable: true, configurable: true });
    if (this._onmessage) { this.addEventListener('message', this._onmessage); this.start(); }
  }
  _neuter() { const st = this._port; st.neutered = true; livePorts.delete(st.id); }
  _receive(wire) {
    if (this._port.closed) return;
    if (!this._port.started) { this._port.queue.push(wire); return; }
    this._dispatch(wire);
  }
  _dispatch(wire) {
    let decoded;
    try { decoded = deserializeValue(wire); } catch (e) {
      this.dispatchEvent(new MessageEvent('messageerror', { data: null }));
      return;
    }
    this.dispatchEvent(new MessageEvent('message', { data: decoded.data, ports: decoded.ports }));
  }
}
const portToken = Symbol('port');
const adoptPort = (id) => {
  const existing = livePorts.get(id);
  if (existing) return existing;
  host('port.adopt', id);
  return new MessagePort(portToken, id);
};
class MessageChannel {
  constructor() {
    const [a, b] = host('port.pair');
    Object.assign(this, { port1: new MessagePort(portToken, a), port2: new MessagePort(portToken, b) });
  }
}
register('__nx_port', (msg) => {
  const port = livePorts.get(msg.id);
  if (port) port._receive(msg.wire);
});

// ============================================================================
// location / history
// ============================================================================
const currentUrl = () => new URL(host('loc.get'));
const originOf = (u) => (u.origin && u.origin !== 'null') ? u.origin : u.protocol + '//' + u.host;
class Location {
  get href() { return host('loc.get'); }
  set href(v) { host('loc.set', String(v), false); }
  get origin() { return originOf(currentUrl()); }
  get protocol() { return currentUrl().protocol; }
  get host() { return currentUrl().host; }
  get hostname() { return currentUrl().hostname; }
  get port() { return currentUrl().port; }
  get pathname() { return currentUrl().pathname; }
  get search() { return currentUrl().search; }
  get hash() { return currentUrl().hash; }
  set hash(v) { let h = String(v); if (!h.startsWith('#')) h = '#' + h; host('loc.set', h, false); }
  set search(v) { const u = currentUrl(); let s = String(v); if (s && !s.startsWith('?')) s = '?' + s; host('loc.set', originOf(u) + u.pathname + s + u.hash, false); }
  set pathname(v) { const u = currentUrl(); host('loc.set', new URL(String(v), u.href).href, false); }
  get ancestorOrigins() { return []; }
  assign(url) { host('loc.set', String(url), false); }
  replace(url) { host('loc.set', String(url), true); }
  reload() {}
  toString() { return this.href; }
  valueOf() { return this; }
}
const location = new Location();
const history = {
  get length() { return host('hist.length'); },
  get state() { return host('hist.state'); },
  scrollRestoration: 'auto',
  pushState(state, title, url) { host('hist.push', false, structuredClone(state), url === undefined || url === null ? null : String(url)); },
  replaceState(state, title, url) { host('hist.push', true, structuredClone(state), url === undefined || url === null ? null : String(url)); },
  back() { host('hist.go', -1); },
  forward() { host('hist.go', 1); },
  go(n = 0) { host('hist.go', Number(n) || 0); },
};

// ============================================================================
// Styles: getComputedStyle, CSS namespace
// ============================================================================
const kebabToCamel = (s) => s.replace(/-([a-z])/g, (_, c) => c.toUpperCase());
const getComputedStyle = (el, pseudo) => {
  if (!(el instanceof Element)) throw new TypeError("Failed to execute 'getComputedStyle': parameter 1 is not of type 'Element'.");
  const values = host('css.computed', el[ID], pseudo === undefined || pseudo === null ? null : String(pseudo));
  const names = Object.keys(values).filter((n) => !n.startsWith('--'));
  const decl = Object.create(CSSStyleDeclaration.prototype);
  const api = {
    getPropertyValue: (p) => { p = String(p); return values[p.startsWith('--') ? p : p.toLowerCase()] ?? ''; },
    getPropertyPriority: () => '',
    setProperty() { throw new DOMException('the declaration is read-only', 'NoModificationAllowedError'); },
    removeProperty() { throw new DOMException('the declaration is read-only', 'NoModificationAllowedError'); },
    item: (i) => names[i] || '',
    get length() { return names.length; },
    get cssText() { return ''; },
    get parentRule() { return null; },
    [Symbol.iterator]: function* () { yield* names; },
  };
  return new Proxy(decl, {
    get(t, p) {
      if (p in api) return api[p];
      if (typeof p === 'string') {
        if (/^\d+$/.test(p)) return names[Number(p)];
        const k = camelToKebab(p);
        if (k in values) return values[k];
        if (p.startsWith('webkit')) return values[camelToKebab(p.slice(6)).replace(/^-/, '')] ?? '';
        if (p in CSSStyleDeclaration.prototype) return Reflect.get(t, p);
        return '';
      }
      return undefined;
    },
    set() { throw new DOMException('the declaration is read-only', 'NoModificationAllowedError'); },
    has(t, p) { return p in api || (typeof p === 'string' && camelToKebab(p) in values); },
  });
};
const CSS = Object.freeze({
  supports(a, b) { return b === undefined ? host('css.supports', String(a)) : host('css.supports', String(a), String(b)); },
  escape(v) {
    const s = String(v);
    let out = '';
    for (let i = 0; i < s.length; i++) {
      const c = s.charCodeAt(i);
      if (c === 0) out += '�';
      else if ((c >= 1 && c <= 0x1f) || c === 0x7f || (i === 0 && c >= 0x30 && c <= 0x39) || (i === 1 && c >= 0x30 && c <= 0x39 && s.charCodeAt(0) === 0x2d)) out += '\\' + c.toString(16) + ' ';
      else if (i === 0 && s.length === 1 && c === 0x2d) out += '\\' + s[i];
      else if (c >= 0x80 || c === 0x2d || c === 0x5f || (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a)) out += s[i];
      else out += '\\' + s[i];
    }
    return out;
  },
  registerProperty() {},
  px: (n) => `${n}px`, em: (n) => `${n}em`, rem: (n) => `${n}rem`, percent: (n) => `${n}%`,
  vw: (n) => `${n}vw`, vh: (n) => `${n}vh`, number: (n) => n,
});

// ============================================================================
// Storage, BroadcastChannel, MessageChannel
// ============================================================================
class Storage {
  constructor() { hidden(this, '_m', new Map()); }
  get length() { return this._m.size; }
  key(i) { return [...this._m.keys()][i] ?? null; }
  getItem(k) { k = String(k); return this._m.has(k) ? this._m.get(k) : null; }
  setItem(k, v) { this._m.set(String(k), String(v)); }
  removeItem(k) { this._m.delete(String(k)); }
  clear() { this._m.clear(); }
}
const storageProxy = (s) => new Proxy(s, {
  get(t, p) { if (typeof p !== 'string' || p in t) { const v = Reflect.get(t, p); return typeof v === 'function' ? v.bind(t) : v; } return t.getItem(p) ?? undefined; },
  set(t, p, v) { if (typeof p !== 'string' || p in t) return Reflect.set(t, p, v); t.setItem(p, v); return true; },
  deleteProperty(t, p) { t.removeItem(p); return true; },
  ownKeys(t) { return [...t._m.keys()]; },
  getOwnPropertyDescriptor(t, p) { const v = t.getItem(p); return v === null ? undefined : { value: v, enumerable: true, configurable: true, writable: true }; },
});
const sessionStorage = storageProxy(new Storage());

const channels = new Map(); // name -> Set<BroadcastChannel>
class BroadcastChannel extends EventTarget {
  constructor(name) {
    super();
    hidden(this, '_name', String(name));
    defineProperty(this, '_closed', { value: false, writable: true, enumerable: false });
    let set = channels.get(this._name);
    if (!set) { set = new Set(); channels.set(this._name, set); }
    set.add(this);
  }
  get name() { return this._name; }
  postMessage(data) {
    if (this._closed) throw new DOMException('BroadcastChannel is closed', 'InvalidStateError');
    const copy = structuredClone(data);
    for (const other of channels.get(this._name) || []) {
      if (other === this) continue;
      setTimeout(() => { if (!other._closed) other.dispatchEvent(new MessageEvent('message', { data: structuredClone(copy), origin: location.origin })); }, 0);
    }
  }
  close() { this._closed = true; const set = channels.get(this._name); if (set) set.delete(this); }
}
// ============================================================================
// navigator extensions
// ============================================================================
const caps = host('nav.capabilities');
const asyncCalls = new Map();
let nextAsync = 1;
const hostAsync = (op, ...args) => new Promise((resolve, reject) => {
  const id = nextAsync++;
  asyncCalls.set(id, { resolve, reject });
  host(op, id, ...args);
});
register('__nx_async', (msg) => {
  const p = asyncCalls.get(msg.id);
  if (!p) return;
  asyncCalls.delete(msg.id);
  if ('error' in msg) p.reject(msg.error);
  else p.resolve(msg.ok);
});
const platformName = navigator.platform;
const uaPlatform = { linux: 'X11; Linux x86_64', windows: 'Windows NT 10.0; Win64; x64', macos: 'Macintosh; Intel Mac OS X 10_15_7',
  android: 'Linux; Android 14', ios: 'iPhone; CPU iPhone OS 17_0 like Mac OS X' }[platformName] || 'Unknown';
defineProperty(navigator, 'userAgent', { value: `Mozilla/5.0 (${uaPlatform}) NativaX/0.1 (QuickJS-ng)`, enumerable: true });
defineProperty(navigator, 'platform', { get() { return { linux: 'Linux x86_64', windows: 'Win32', macos: 'MacIntel', android: 'Linux armv8l', ios: 'iPhone' }[platformName] || platformName; }, enumerable: true });
Object.assign(navigator, {
  appName: 'Netscape', appCodeName: 'Mozilla', appVersion: '5.0', product: 'Gecko', productSub: '20030107',
  vendor: '', vendorSub: '', cookieEnabled: true, doNotTrack: null, webdriver: false, pdfViewerEnabled: false,
  hardwareConcurrency: 4, maxTouchPoints: platformName === 'android' || platformName === 'ios' ? 5 : 0,
  javaEnabled: () => false,
  permissions: {
    query(desc) {
      const name = desc && desc.name;
      const granted = name === 'clipboard-write' ? caps.clipboard : false;
      const status = Object.assign(new EventTarget(), { name, state: granted ? 'granted' : 'denied', onchange: null });
      return Promise.resolve(status);
    },
  },
  storage: {
    estimate: () => Promise.resolve({ quota: 5 * 1024 * 1024, usage: localStorage ? JSON.stringify(Object.entries(localStorage)).length : 0 }),
    persist: () => Promise.resolve(false),
    persisted: () => Promise.resolve(false),
  },
  sendBeacon: () => false,
  registerProtocolHandler() {},
});
if (caps.clipboard) {
  navigator.clipboard = Object.assign(new EventTarget(), {
    writeText: (t) => hostAsync('clip.write', String(t)).then(() => undefined, (e) => { throw new DOMException(String(e), 'NotAllowedError'); }),
    readText: () => hostAsync('clip.read').catch((e) => { throw new DOMException(String(e), 'NotAllowedError'); }),
    write: (items) => Promise.reject(new DOMException('Only text is supported', 'NotAllowedError')),
    read: () => Promise.reject(new DOMException('Only text is supported', 'NotAllowedError')),
  });
}
if (caps.vibrate) navigator.vibrate = (p) => host('nav.vibrate', Array.isArray(p) ? p.map(Number) : Number(p) || 0);
''';

const String _observers = r'''
// ============================================================================
// MutationObserver, ResizeObserver, IntersectionObserver
// ============================================================================
const mutationObservers = new Map();
let nextObserver = 1;
class MutationRecord {}
const recordFrom = (r) => {
  const m = Object.create(MutationRecord.prototype);
  Object.assign(m, {
    type: r.type, target: wrap(r.target), addedNodes: wrapAll(r.addedNodes), removedNodes: wrapAll(r.removedNodes),
    previousSibling: wrap(r.previousSibling), nextSibling: wrap(r.nextSibling), attributeName: r.attributeName,
    attributeNamespace: r.attributeNamespace, oldValue: r.oldValue,
  });
  return m;
};
class MutationObserver {
  constructor(cb) {
    if (typeof cb !== 'function') throw new TypeError("Failed to construct 'MutationObserver': parameter 1 is not of type 'Function'.");
    hidden(this, '_id', nextObserver++);
    hidden(this, '_cb', cb);
    mutationObservers.set(this._id, this);
  }
  observe(target, options = {}) {
    const o = Object.assign({}, options);
    if ('attributeOldValue' in o || 'attributeFilter' in o) o.attributes = o.attributes ?? true;
    if ('characterDataOldValue' in o) o.characterData = o.characterData ?? true;
    if (!o.childList && !o.attributes && !o.characterData) {
      throw new TypeError("Failed to execute 'observe' on 'MutationObserver': The options object must set at least one of 'attributes', 'characterData', or 'childList' to true.");
    }
    if (o.attributes === false && ('attributeOldValue' in o || 'attributeFilter' in o)) throw new TypeError('attributeOldValue/attributeFilter require attributes');
    if (o.characterData === false && 'characterDataOldValue' in o) throw new TypeError('characterDataOldValue requires characterData');
    host('mo.observe', this._id, idOf(target), {
      childList: !!o.childList, attributes: !!o.attributes, characterData: !!o.characterData, subtree: !!o.subtree,
      attributeOldValue: !!o.attributeOldValue, characterDataOldValue: !!o.characterDataOldValue,
      attributeFilter: o.attributeFilter ? [...o.attributeFilter].map(String) : null,
    });
    mutationObservers.set(this._id, this);
  }
  disconnect() { host('mo.disconnect', this._id); }
  takeRecords() { return host('mo.take', this._id).map(recordFrom); }
}
const deliverMO = (ids) => {
  for (const id of ids) {
    const mo = mutationObservers.get(id);
    if (!mo) { host('mo.disconnect', id); continue; }
    const records = mo.takeRecords();
    if (records.length === 0) continue;
    try { mo._cb.call(mo, records, mo); } catch (e) { reportError(e); }
  }
  host('mo.queuedDone');
};
register('__nx_mo', deliverMO);
register('__nx_queue_mo', (ids) => queueMicrotask(() => deliverMO(ids)));

// Layout observers poll element boxes on animation frames while active.
const layoutObservers = new Set();
let layoutPolling = false;
const pollLayout = () => {
  if (layoutObservers.size === 0) { layoutPolling = false; return; }
  for (const o of [...layoutObservers]) { try { o._check(); } catch (e) { reportError(e); } }
  requestAnimationFrame(pollLayout);
};
const startLayoutPolling = () => { if (!layoutPolling) { layoutPolling = true; requestAnimationFrame(pollLayout); } };
class ResizeObserverEntry {}
class ResizeObserver {
  constructor(cb) {
    if (typeof cb !== 'function') throw new TypeError("Failed to construct 'ResizeObserver': parameter 1 is not of type 'Function'.");
    hidden(this, '_cb', cb);
    hidden(this, '_targets', new Map());
  }
  observe(target, options = {}) {
    idOf(target);
    this._targets.set(target, { last: null, box: options.box || 'content-box' });
    layoutObservers.add(this);
    startLayoutPolling();
  }
  unobserve(target) { this._targets.delete(target); if (this._targets.size === 0) layoutObservers.delete(this); }
  disconnect() { this._targets.clear(); layoutObservers.delete(this); }
  _check() {
    const entries = [];
    for (const [target, state] of this._targets) {
      const b = layoutBox(target);
      const key = b.width + 'x' + b.height;
      if (state.last === key) continue;
      state.last = key;
      const e = Object.create(ResizeObserverEntry.prototype);
      const size = [{ inlineSize: b.width, blockSize: b.height }];
      Object.assign(e, {
        target, contentRect: new DOMRectReadOnly(0, 0, b.clientWidth || b.width, b.clientHeight || b.height),
        borderBoxSize: size, contentBoxSize: [{ inlineSize: b.clientWidth || b.width, blockSize: b.clientHeight || b.height }],
        devicePixelContentBoxSize: size,
      });
      entries.push(e);
    }
    if (entries.length) this._cb.call(this, entries, this);
  }
}
class IntersectionObserverEntry {}
class IntersectionObserver {
  constructor(cb, options = {}) {
    if (typeof cb !== 'function') throw new TypeError("Failed to construct 'IntersectionObserver': parameter 1 is not of type 'Function'.");
    const t = options.threshold === undefined ? [0] : (Array.isArray(options.threshold) ? options.threshold : [options.threshold]);
    if (t.some((x) => x < 0 || x > 1)) throw new RangeError('Threshold values must be numbers between 0 and 1');
    hidden(this, '_cb', cb);
    hidden(this, '_targets', new Map());
    Object.assign(this, { root: options.root || null, rootMargin: options.rootMargin || '0px 0px 0px 0px', thresholds: t.slice().sort(), scrollMargin: '0px', delay: 0, trackVisibility: false });
  }
  observe(target) {
    idOf(target);
    if (!this._targets.has(target)) this._targets.set(target, { band: -2 });
    layoutObservers.add(this);
    startLayoutPolling();
  }
  unobserve(target) { this._targets.delete(target); if (this._targets.size === 0) layoutObservers.delete(this); }
  disconnect() { this._targets.clear(); layoutObservers.delete(this); }
  takeRecords() { return []; }
  _check() {
    const vp = host('layout.viewport');
    const rootRect = this.root ? this.root.getBoundingClientRect() : new DOMRectReadOnly(0, 0, vp.width, vp.height);
    const entries = [];
    for (const [target, state] of this._targets) {
      const r = target.getBoundingClientRect();
      const box = boxOf(target);
      const x1 = Math.max(r.left, rootRect.left), y1 = Math.max(r.top, rootRect.top);
      const x2 = Math.min(r.right, rootRect.right), y2 = Math.min(r.bottom, rootRect.bottom);
      const visible = box !== null && x2 >= x1 && y2 >= y1;
      const area = r.width * r.height;
      const inter = visible ? (x2 - x1) * (y2 - y1) : 0;
      const ratio = !visible ? 0 : (area > 0 ? inter / area : 1);
      let band = -1;
      for (let i = 0; i < this.thresholds.length; i++) if (visible && ratio >= this.thresholds[i]) band = i;
      if (band === state.band) continue;
      state.band = band;
      const e = Object.create(IntersectionObserverEntry.prototype);
      Object.assign(e, {
        target, time: performance.now(), rootBounds: rootRect, boundingClientRect: r,
        intersectionRect: visible ? new DOMRectReadOnly(x1, y1, x2 - x1, y2 - y1) : new DOMRectReadOnly(0, 0, 0, 0),
        isIntersecting: visible && (ratio > 0 || this.thresholds.includes(0)), intersectionRatio: ratio, isVisible: false,
      });
      entries.push(e);
    }
    if (entries.length) this._cb.call(this, entries, this);
  }
}
''';

const String _document = r'''
// ============================================================================
// Document and window members
// ============================================================================
let cookieJar = new Map();
const docProps = {
  URL: { get() { return host('loc.get'); } },
  documentURI: { get() { return host('loc.get'); } },
  baseURI: {
    get() {
      const base = document.querySelector('base[href]');
      if (base) { try { return new URL(base.getAttribute('href'), host('loc.get')).href; } catch (e) {} }
      return host('loc.get');
    },
  },
  location: { get() { return this === document ? location : null; }, set(v) { if (this === document) location.href = v; } },
  domain: { get() { return currentUrl().hostname; } },
  referrer: { get() { return ''; } },
  lastModified: { get() { const d = new Date(); const p = (n) => String(n).padStart(2, '0'); return `${p(d.getMonth() + 1)}/${p(d.getDate())}/${d.getFullYear()} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`; } },
  cookie: {
    get() { return [...cookieJar].map(([k, v]) => `${k}=${v}`).join('; '); },
    set(v) {
      const [pair, ...attrs] = String(v).split(';');
      const eq = pair.indexOf('=');
      const k = (eq < 0 ? '' : pair.slice(0, eq)).trim();
      const val = (eq < 0 ? pair : pair.slice(eq + 1)).trim();
      const expired = attrs.some((a) => /^\s*max-age\s*=\s*(-\d+|0)\s*$/i.test(a)) ||
        attrs.some((a) => { const m = /^\s*expires\s*=(.*)$/i.exec(a); return m && Date.parse(m[1]) < Date.now(); });
      if (expired) cookieJar.delete(k); else cookieJar.set(k, val);
    },
  },
  hidden: { get() { return false; } },
  visibilityState: { get() { return 'visible'; } },
  defaultView: { get() { return frameWindowByDoc.get(this) || globalThis; } },
  scrollingElement: { get() { return document.documentElement; } },
  dir: { get() { return document.documentElement ? document.documentElement.dir : ''; }, set(v) { if (document.documentElement) document.documentElement.dir = v; } },
  designMode: { get() { return 'off'; }, set() {} },
  currentScript: { get() { return null; } },
  fullscreenElement: { get() { return null; } },
  fullscreenEnabled: { get() { return false; } },
  pictureInPictureEnabled: { get() { return false; } },
  pointerLockElement: { get() { return null; } },
  timeline: { get() { return { currentTime: performance.now() }; } },
  styleSheets: { get() { return cssStyleSheetList(); } },
  adoptedStyleSheets: { get() { return []; }, set() {} },
  forms: { get() { return document.querySelectorAll('form'); } },
  images: { get() { return document.querySelectorAll('img'); } },
  links: { get() { return document.querySelectorAll('a[href], area[href]'); } },
  scripts: { get() { return document.querySelectorAll('script'); } },
  embeds: { get() { return document.querySelectorAll('embed'); } },
  plugins: { get() { return []; } },
  all: { get() { return document.querySelectorAll('*'); } },
  fonts: { get() { return fontFaceSet; } },
};
for (const [k, d] of Object.entries(docProps)) defineProperty(DP, k, Object.assign({ configurable: true, enumerable: true }, d));
DP.hasFocus = function () { return true; };
DP.execCommand = function () { return false; };
DP.queryCommandSupported = function () { return false; };
DP.queryCommandEnabled = function () { return false; };
DP.elementFromPoint = function () { return null; };
DP.elementsFromPoint = function () { return []; };
DP.caretPositionFromPoint = DP.caretRangeFromPoint = function () { return null; };
DP.getSelection = function () { return selection; };
DP.createRange = function () { return new Range(); };
DP.createTreeWalker = function (root, what, filter) { if (arguments.length < 1) throw new TypeError('1 argument required'); return new TreeWalker(root, what, filter); };
DP.createNodeIterator = function (root, what, filter) { return new NodeIterator(root, what, filter); };
DP.exitFullscreen = function () { return Promise.resolve(); };
DP.exitPointerLock = function () {};
DP.startViewTransition = function (cb) {
  const done = Promise.resolve().then(() => cb && cb());
  return { finished: done, ready: done, updateCallbackDone: done, skipTransition() {} };
};
DP.open = function () { return this; };
DP.close = function () {};
DP.write = DP.writeln = function (...s) { if (document.body) document.body.insertAdjacentHTML('beforeend', s.join('')); };
const createEventTypes = { Event, CustomEvent, UIEvent, MouseEvent, MouseEvents: MouseEvent, KeyboardEvent, FocusEvent, HTMLEvents: Event, Events: Event };
DP.createEvent = function (t) {
  const C = createEventTypes[t];
  if (!C) throw new DOMException(`The provided event type ('${t}') is invalid.`, 'NotSupportedError');
  const e = new C('');
  return e;
};

const fontFaceSet = Object.assign(new EventTarget(), {
  status: 'loaded',
  ready: null,
  size: 0,
  check: () => true,
  load: () => Promise.resolve([]),
  add() {}, delete() { return false; }, clear() {}, has: () => false,
  forEach() {},
  [Symbol.iterator]: function* () {},
});
fontFaceSet.ready = Promise.resolve(fontFaceSet);
class FontFace {
  constructor(family, source, descriptors = {}) { Object.assign(this, { family, status: 'unloaded', loaded: null }, descriptors); }
  load() { this.status = 'error'; return Promise.reject(new DOMException('Web fonts are not supported', 'NetworkError')); }
}

class Range {
  constructor() { Object.assign(this, { startContainer: document, startOffset: 0, endContainer: document, endOffset: 0, collapsed: true, commonAncestorContainer: document }); }
  setStart(n, o) { this.startContainer = n; this.startOffset = o; this._update(); }
  setEnd(n, o) { this.endContainer = n; this.endOffset = o; this._update(); }
  setStartBefore(n) { this.setStart(n.parentNode, [...n.parentNode.childNodes].indexOf(n)); }
  setStartAfter(n) { this.setStart(n.parentNode, [...n.parentNode.childNodes].indexOf(n) + 1); }
  setEndBefore(n) { this.setEnd(n.parentNode, [...n.parentNode.childNodes].indexOf(n)); }
  setEndAfter(n) { this.setEnd(n.parentNode, [...n.parentNode.childNodes].indexOf(n) + 1); }
  selectNode(n) { this.setStartBefore(n); this.setEndAfter(n); }
  selectNodeContents(n) { this.setStart(n, 0); this.setEnd(n, n.nodeType === 1 ? n.childNodes.length : n.textContent.length); }
  collapse(toStart = false) { if (toStart) this.setEnd(this.startContainer, this.startOffset); else this.setStart(this.endContainer, this.endOffset); }
  _update() { this.collapsed = this.startContainer === this.endContainer && this.startOffset === this.endOffset; this.commonAncestorContainer = this.startContainer; }
  cloneRange() { const r = new Range(); r.setStart(this.startContainer, this.startOffset); r.setEnd(this.endContainer, this.endOffset); return r; }
  _nodes() {
    const c = this.startContainer;
    if (c === this.endContainer && c.nodeType === 1) return [...c.childNodes].slice(this.startOffset, this.endOffset);
    return [];
  }
  cloneContents() { const f = document.createDocumentFragment(); for (const n of this._nodes()) f.appendChild(n.cloneNode(true)); return f; }
  extractContents() { const f = document.createDocumentFragment(); for (const n of this._nodes()) f.appendChild(n); return f; }
  deleteContents() { for (const n of this._nodes()) n.remove(); }
  insertNode(n) {
    const c = this.startContainer;
    if (c.nodeType === 3) {
      const parent = c.parentNode;
      if (!parent) throw new DOMException('The container has no parent.', 'HierarchyRequestError');
      if (this.startOffset < c.data.length) {
        const tail = c.splitText(this.startOffset);
        parent.insertBefore(n, tail);
      } else {
        parent.insertBefore(n, c.nextSibling);
      }
      return;
    }
    c.insertBefore(n, c.childNodes[this.startOffset] || null);
  }
  surroundContents(n) { n.appendChild(this.extractContents()); this.insertNode(n); }
  createContextualFragment(html) { const t = document.createElement('template'); t.innerHTML = String(html); const f = document.createDocumentFragment(); for (const c of [...t.childNodes]) f.appendChild(c); return f; }
  getBoundingClientRect() { return new DOMRect(); }
  getClientRects() { return []; }
  toString() { const c = this.startContainer; return c.nodeType === 3 ? c.data.slice(this.startOffset, this.endOffset) : this._nodes().map((n) => n.textContent).join(''); }
  detach() {}
}
const selection = {
  rangeCount: 0, isCollapsed: true, type: 'None', anchorNode: null, anchorOffset: 0, focusNode: null, focusOffset: 0,
  getRangeAt() { throw new DOMException('The index is not in the allowed range.', 'IndexSizeError'); },
  addRange() {}, removeRange() {}, removeAllRanges() {}, empty() {}, collapse() {}, collapseToStart() {},
  collapseToEnd() {}, extend() {}, selectAllChildren() {}, setBaseAndExtent() {}, deleteFromDocument() {},
  containsNode() { return false; }, modify() {}, toString() { return ''; },
};

class DOMParser {
  parseFromString(str, type) {
    const t = String(type || 'text/html').toLowerCase();
    if (!['text/html', 'text/xml', 'application/xml', 'application/xhtml+xml', 'image/svg+xml'].includes(t)) {
      throw new TypeError(`The provided value '${type}' is not a valid enum value of type DOMParserSupportedType.`);
    }
    // Parsed into a detached <html> element standing in for a document.
    const root = document.createElement('html');
    root.innerHTML = String(str);
    let head = root.querySelector('head');
    let body = root.querySelector('body');
    if (!body) { body = document.createElement('body'); for (const c of [...root.childNodes]) if (c.localName !== 'head') body.appendChild(c); root.appendChild(body); }
    if (!head) { head = document.createElement('head'); root.insertBefore(head, root.firstChild); }
    const doc = {
      documentElement: root, head, body, nodeType: 9, contentType: t,
      get title() { const el = root.querySelector('title'); return el ? el.textContent : ''; },
      querySelector: (s) => root.querySelector(s), querySelectorAll: (s) => root.querySelectorAll(s),
      getElementById: (id) => root.querySelector('#' + CSS.escape(id)),
      getElementsByTagName: (n) => root.getElementsByTagName(n), getElementsByClassName: (n) => root.getElementsByClassName(n),
      createElement: (n) => document.createElement(n), createTextNode: (s) => document.createTextNode(s),
      get children() { return [root]; }, get childNodes() { return [root]; }, get firstChild() { return root; },
    };
    return doc;
  }
}
class XMLSerializer { serializeToString(n) { return n.nodeType === 9 ? n.documentElement.outerHTML : (n.outerHTML ?? n.textContent); } }

// Constructors for common elements.
function Image(width, height) {
  const img = document.createElement('img');
  if (width !== undefined) img.width = width;
  if (height !== undefined) img.height = height;
  return img;
}
function Audio(src) { const a = document.createElement('audio'); if (src !== undefined) a.src = src; return a; }
function Option(text = '', value, defaultSelected = false, selected = false) {
  const o = document.createElement('option');
  o.textContent = String(text);
  if (value !== undefined) o.value = value;
  if (defaultSelected) o.setAttribute('selected', '');
  if (selected) o.selected = true;
  return o;
}

// Window scrolling and geometry.
const viewport = () => host('layout.viewport');
const scrollToArgs = (a, b) => {
  if (a && typeof a === 'object') return [a.left ?? viewport().scrollX, a.top ?? viewport().scrollY, a.behavior === 'smooth'];
  return [Number(a) || 0, Number(b) || 0, false];
};
const scrollTo = (a, b) => { const [x, y, smooth] = scrollToArgs(a, b); host('layout.scrollTo', x, y, smooth); };
const scrollBy = (a, b) => {
  const v = viewport();
  if (a && typeof a === 'object') { host('layout.scrollTo', v.scrollX + (a.left || 0), v.scrollY + (a.top || 0), a.behavior === 'smooth'); return; }
  host('layout.scrollTo', v.scrollX + (Number(a) || 0), v.scrollY + (Number(b) || 0), false);
};
const screenInfo = () => ({ w: env().width, h: env().height });
const screen = Object.assign(new EventTarget(), {
  get width() { return screenInfo().w; }, get height() { return screenInfo().h; },
  get availWidth() { return screenInfo().w; }, get availHeight() { return screenInfo().h; },
  availLeft: 0, availTop: 0, colorDepth: 24, pixelDepth: 24, isExtended: false,
});
screen.orientation = Object.assign(new EventTarget(), {
  get type() { const s = screenInfo(); return s.w >= s.h ? 'landscape-primary' : 'portrait-primary'; },
  get angle() { return 0; },
  lock: () => Promise.reject(new DOMException('Screen orientation lock is not supported', 'NotSupportedError')),
  unlock() {},
  onchange: null,
});
const visualViewport = Object.assign(new EventTarget(), {
  get width() { return env().width; }, get height() { return env().height; },
  get offsetLeft() { return 0; }, get offsetTop() { return 0; },
  get pageLeft() { return viewport().scrollX; }, get pageTop() { return viewport().scrollY; },
  get scale() { return 1; },
});

const alert = (m = '') => { host('nav.alert', String(m)); };
const confirm = (m = '') => { host('nav.alert', String(m)); return false; };
const prompt = (m = '', d = null) => { host('nav.alert', String(m)); return null; };
const print = () => {};
const open = () => null;
const postMessage = (data, origin) => {
  const copy = structuredClone(data);
  setTimeout(() => globalThis.dispatchEvent(new MessageEvent('message', { data: copy, origin: location.origin, source: globalThis })), 0);
};

// Media elements and images that can never load report their error once
// the document is ready (no media pipeline; images need a host resolver).
register('__nx_ready', () => {
  const t = performance.now();
  Object.assign(navigationEntry, {
    responseEnd: t, domInteractive: t, domContentLoadedEventStart: t, domContentLoadedEventEnd: t,
    domComplete: t, loadEventStart: t, loadEventEnd: t, duration: t,
  });
  compileInlineHandlers(document.documentElement);
  setTimeout(() => {
    for (const el of document.querySelectorAll('video, audio')) {
      if (el.getAttribute('src') || el.querySelector('source')) {
        for (const s of el.querySelectorAll('source')) s.dispatchEvent(new Event('error'));
        el.dispatchEvent(new Event('error'));
      }
    }
    if (!caps.network) {
      for (const img of document.querySelectorAll('img')) {
        const src = img.getAttribute('src') || '';
        if (/^https?:/i.test(src)) img.dispatchEvent(new Event('error'));
      }
    }
  }, 0);
});

const isSecureContext = (() => {
  try {
    const u = currentUrl();
    return u.protocol === 'https:' || u.protocol === 'file:' || u.protocol === 'about:' || u.protocol === 'app:' ||
      u.hostname === 'localhost' || u.hostname === '127.0.0.1';
  } catch (e) { return true; }
})();

const windowGlobals = {
  location, history, performance, PerformanceEntry, PerformanceMark, PerformanceMeasure, PerformanceObserver,
  requestAnimationFrame, cancelAnimationFrame, requestIdleCallback, cancelIdleCallback, crypto, TextEncoder,
  TextDecoder, btoa, atob, structuredClone, getComputedStyle, CSS, Storage, sessionStorage, BroadcastChannel,
  MessageChannel, MessagePort, MutationObserver, MutationRecord, ResizeObserver, ResizeObserverEntry,
  IntersectionObserver, IntersectionObserverEntry, DOMRect, DOMRectReadOnly, DOMPoint, DOMParser, XMLSerializer,
  Image, Audio, Option, Range, TreeWalker, NodeIterator, NodeFilter, FontFace, ValidityState, RadioNodeList,
  HTMLFormControlsCollection, MediaError, customElements, scrollTo, scroll: scrollTo, scrollBy, screen, visualViewport,
  alert, confirm, prompt, print, open, postMessage, reportError, Location, UIEvent, MouseEvent, PointerEvent,
  WheelEvent, DragEvent, KeyboardEvent, FocusEvent, InputEvent, CompositionEvent, TouchEvent, SubmitEvent,
  FormDataEvent, ErrorEvent, PromiseRejectionEvent, MessageEvent, CloseEvent, ProgressEvent, HashChangeEvent,
  PopStateEvent, PageTransitionEvent, StorageEvent, AnimationEvent, TransitionEvent, ToggleEvent, ClipboardEvent,
  MediaQueryListEvent, DataTransfer, isSecureContext,
  AudioContext, webkitAudioContext, AudioBuffer, AudioParam, AudioNode,
  AudioBufferSourceNode, AudioDestinationNode,
  GainNode: AudioGainNode, PannerNode: AudioPannerNode, AudioListener: AudioListenerNode,
  CSSStyleSheet, CSSRule, CSSStyleRule, CSSMediaRule, CSSImportRule,
  ...interfaceClasses,
};
if (typeof globalThis.Intl === 'undefined') windowGlobals.Intl = IntlPolyfill;
for (const [name, value] of Object.entries(windowGlobals)) {
  defineProperty(globalThis, name, { value, enumerable: false, writable: true, configurable: true });
}
for (const [name, getter] of Object.entries({
  scrollX: () => viewport().scrollX, scrollY: () => viewport().scrollY,
  pageXOffset: () => viewport().scrollX, pageYOffset: () => viewport().scrollY,
  outerWidth: () => env().width, outerHeight: () => env().height, screenX: () => 0, screenY: () => 0,
  screenLeft: () => 0, screenTop: () => 0,
  origin: () => { try { return currentUrl().origin || 'null'; } catch (e) { return 'null'; } },
  name: () => '', closed: () => false, length: () => 0, opener: () => null, frameElement: () => null,
  parent: () => globalThis, top: () => globalThis, crossOriginIsolated: () => true,
  status: () => '', event: () => undefined, isSecureContext: () => isSecureContext,
})) defineProperty(globalThis, name, { get: getter, enumerable: true, configurable: true });
Object.defineProperty(globalThis, 'frames', {
  get() {
    let wins = [];
    const collect = (root) => {
      for (const f of root.querySelectorAll('iframe')) wins.push(frameWindowFor(f));
    };
    collect(document);
    return new Proxy(wins, {
      get(t, p, r) {
        if (typeof p === 'string' && /^\d+$/.test(p)) return t[Number(p)];
        if (p === 'length') return t.length;
        if (p === 'item') return (i) => t[Number(i)] || null;
        if (p === 'namedItem') return (n) => t.find((w) => w.frameElement && (w.frameElement.id === n || w.frameElement.getAttribute('name') === n)) || null;
        return Reflect.get(t, p, r);
      },
    });
  }, enumerable: true, configurable: true,
});
''';
