import 'web_prelude_idb.dart';

/// Blobs, forms, fetch, XHR, WebSocket and IndexedDB (part of the web
/// platform prelude). Network calls go through the host's network policy.
const String webIoApis = _io + webIndexedDb + _ioExports;

const String _io = r'''
// ============================================================================
// Blob, File, FileReader, FileList, object URLs
// ============================================================================
const blobBytes = new WeakMap();
class Blob {
  constructor(parts = [], options = {}) {
    const chunks = [];
    for (const p of parts) {
      if (p instanceof Blob) chunks.push(blobBytes.get(p));
      else if (p instanceof ArrayBuffer || ArrayBuffer.isView(p)) chunks.push(toBytes(p).slice());
      else chunks.push(utf8Encode(String(p)));
    }
    const size = chunks.reduce((a, c) => a + c.length, 0);
    const all = new Uint8Array(size);
    let o = 0;
    for (const c of chunks) { all.set(c, o); o += c.length; }
    blobBytes.set(this, all);
    hidden(this, '_type', options.type ? String(options.type).toLowerCase() : '');
  }
  get size() { return blobBytes.get(this).length; }
  get type() { return this._type; }
  slice(start = 0, end = this.size, type = '') {
    const b = new Blob([], { type });
    blobBytes.set(b, blobBytes.get(this).slice(start < 0 ? Math.max(this.size + start, 0) : start, end < 0 ? this.size + end : end));
    return b;
  }
  text() { return Promise.resolve(utf8Decode(blobBytes.get(this))); }
  arrayBuffer() { return Promise.resolve(blobBytes.get(this).slice().buffer); }
  bytes() { return Promise.resolve(blobBytes.get(this).slice()); }
  stream() { throw new DOMException('Streams are not supported', 'NotSupportedError'); }
}
Blob.prototype[Symbol.toStringTag] = 'Blob';
class File extends Blob {
  constructor(parts, name, options = {}) {
    super(parts, options);
    hidden(this, '_name', String(name));
    hidden(this, '_modified', options.lastModified ?? Date.now());
  }
  get name() { return this._name; }
  get lastModified() { return this._modified; }
  get webkitRelativePath() { return ''; }
}
File.prototype[Symbol.toStringTag] = 'File';
class FileList extends Array { item(i) { return this[i] || null; } }
const fileListOf = (files) => FileList.from(files);
const objectUrls = new Map();
URL.createObjectURL = (obj) => {
  if (!(obj instanceof Blob)) throw new TypeError("Failed to execute 'createObjectURL' on 'URL': Overload resolution failed.");
  const url = 'blob:' + (location.origin && location.origin !== 'null' ? location.origin : 'nativax://local') + '/' + crypto.randomUUID();
  objectUrls.set(url, obj);
  return url;
};
URL.revokeObjectURL = (url) => { objectUrls.delete(String(url)); };

class FileReader extends EventTarget {
  constructor() {
    super();
    Object.assign(this, { readyState: 0, result: null, error: null });
  }
  _read(blob, as, arg) {
    if (!(blob instanceof Blob)) throw new TypeError('parameter 1 is not of type Blob');
    if (this.readyState === 1) throw new DOMException('The object is already busy reading Blobs.', 'InvalidStateError');
    this.readyState = 1;
    this.result = null;
    setTimeout(() => {
      if (this.readyState !== 1) return;
      const bytes = blobBytes.get(blob);
      this.dispatchEvent(new ProgressEvent('loadstart', { total: bytes.length }));
      switch (as) {
        case 'text': this.result = utf8Decode(bytes); break;
        case 'buffer': this.result = bytes.slice().buffer; break;
        case 'binary': { let s = ''; for (const b of bytes) s += String.fromCharCode(b); this.result = s; break; }
        default: this.result = `data:${blob.type || 'application/octet-stream'};base64,${bytesToBase64(bytes)}`;
      }
      this.readyState = 2;
      this.dispatchEvent(new ProgressEvent('progress', { lengthComputable: true, loaded: bytes.length, total: bytes.length }));
      this.dispatchEvent(new ProgressEvent('load', { lengthComputable: true, loaded: bytes.length, total: bytes.length }));
      this.dispatchEvent(new ProgressEvent('loadend', { lengthComputable: true, loaded: bytes.length, total: bytes.length }));
    }, 0);
  }
  readAsText(b, enc) { this._read(b, 'text', enc); }
  readAsDataURL(b) { this._read(b, 'url'); }
  readAsArrayBuffer(b) { this._read(b, 'buffer'); }
  readAsBinaryString(b) { this._read(b, 'binary'); }
  abort() {
    if (this.readyState !== 1) return;
    this.readyState = 2;
    this.result = null;
    this.error = new DOMException('The operation was aborted.', 'AbortError');
    this.dispatchEvent(new ProgressEvent('abort'));
    this.dispatchEvent(new ProgressEvent('loadend'));
  }
}
FileReader.EMPTY = 0; FileReader.LOADING = 1; FileReader.DONE = 2;

// ============================================================================
// FormData
// ============================================================================
class FormData {
  constructor(form, submitter) {
    hidden(this, '_e', []);
    if (form === undefined) return;
    if (!(form instanceof Element) || form.localName !== 'form') throw new TypeError("Failed to construct 'FormData': parameter 1 is not of type 'HTMLFormElement'.");
    for (const el of form.elements) {
      const name = el.getAttribute('name');
      if (!name || el.disabled || el.closest('datalist')) continue;
      const t = el.localName === 'input' ? el.type : el.localName;
      if (t === 'button' || t === 'reset' || t === 'image' || t === 'fieldset' || t === 'output' || t === 'object') continue;
      if (t === 'submit' || (el.localName === 'button' && (el.getAttribute('type') || 'submit') === 'submit')) {
        if (el === submitter) this.append(name, el.value);
        continue;
      }
      if ((t === 'checkbox' || t === 'radio') && !el.checked) continue;
      if (t === 'file') { this.append(name, new File([], '', { type: 'application/octet-stream' })); continue; }
      if (el.localName === 'select') { for (const o of el.selectedOptions) this.append(name, o.value); continue; }
      this.append(name, el.value);
    }
  }
  _v(v, filename) {
    if (v instanceof Blob) return v instanceof File && filename === undefined ? v : new File([v], filename ?? (v instanceof File ? v.name : 'blob'), { type: v.type });
    return String(v);
  }
  append(k, v, f) { this._e.push([String(k), this._v(v, f)]); }
  set(k, v, f) {
    k = String(k);
    const i = this._e.findIndex((e) => e[0] === k);
    const val = this._v(v, f);
    if (i < 0) { this._e.push([k, val]); return; }
    this._e[i][1] = val;
    for (let j = this._e.length - 1; j > i; j--) if (this._e[j][0] === k) this._e.splice(j, 1);
  }
  get(k) { const e = this._e.find((x) => x[0] === String(k)); return e ? e[1] : null; }
  getAll(k) { return this._e.filter((x) => x[0] === String(k)).map((x) => x[1]); }
  has(k) { return this._e.some((x) => x[0] === String(k)); }
  delete(k) { const n = String(k); for (let i = this._e.length - 1; i >= 0; i--) if (this._e[i][0] === n) this._e.splice(i, 1); }
  forEach(fn, self) { for (const [k, v] of this._e) fn.call(self, v, k, this); }
  *entries() { yield* this._e.map((e) => [e[0], e[1]]); }
  *keys() { for (const e of this._e) yield e[0]; }
  *values() { for (const e of this._e) yield e[1]; }
  [Symbol.iterator]() { return this.entries(); }
}

// ============================================================================
// AbortController / AbortSignal
// ============================================================================
class AbortSignal extends EventTarget {
  constructor() { super(); hidden(this, '_s', { aborted: false, reason: undefined }); }
  get aborted() { return this._s.aborted; }
  get reason() { return this._s.reason; }
  throwIfAborted() { if (this.aborted) throw this.reason; }
  _abort(reason) {
    if (this._s.aborted) return;
    this._s.aborted = true;
    this._s.reason = reason === undefined ? new DOMException('signal is aborted without reason', 'AbortError') : reason;
    this.dispatchEvent(new Event('abort'));
  }
  static abort(reason) { const s = new AbortSignal(); s._abort(reason); return s; }
  static timeout(ms) { const s = new AbortSignal(); setTimeout(() => s._abort(new DOMException('signal timed out', 'TimeoutError')), ms); return s; }
  static any(signals) {
    const s = new AbortSignal();
    for (const x of signals) {
      if (x.aborted) { s._abort(x.reason); break; }
      x.addEventListener('abort', () => s._abort(x.reason), { once: true });
    }
    return s;
  }
}
class AbortController {
  constructor() { hidden(this, '_signal', new AbortSignal()); }
  get signal() { return this._signal; }
  abort(reason) { this._signal._abort(reason); }
}

// ============================================================================
// Headers, Request, Response, fetch
// ============================================================================
const normName = (n) => String(n).toLowerCase();
class Headers {
  constructor(init) {
    hidden(this, '_h', []);
    if (init instanceof Headers) for (const [k, v] of init) this.append(k, v);
    else if (Array.isArray(init)) for (const [k, v] of init) this.append(k, v);
    else if (init && typeof init === 'object') for (const k of Object.keys(init)) this.append(k, init[k]);
  }
  append(k, v) {
    const name = normName(k);
    if (!/^[!#$%&'*+.^_`|~0-9a-z-]+$/.test(name)) throw new TypeError(`'${k}' is not a valid HTTP header field name.`);
    this._h.push([name, String(v).trim()]);
  }
  set(k, v) { this.delete(k); this.append(k, v); }
  get(k) { const n = normName(k); const vals = this._h.filter((h) => h[0] === n).map((h) => h[1]); return vals.length ? vals.join(', ') : null; }
  getSetCookie() { return this._h.filter((h) => h[0] === 'set-cookie').map((h) => h[1]); }
  has(k) { const n = normName(k); return this._h.some((h) => h[0] === n); }
  delete(k) { const n = normName(k); for (let i = this._h.length - 1; i >= 0; i--) if (this._h[i][0] === n) this._h.splice(i, 1); }
  forEach(fn, self) { for (const [k, v] of this) fn.call(self, v, k, this); }
  *entries() {
    const names = [...new Set(this._h.map((h) => h[0]))].sort();
    for (const n of names) yield [n, this.get(n)];
  }
  *keys() { for (const [k] of this.entries()) yield k; }
  *values() { for (const [, v] of this.entries()) yield v; }
  [Symbol.iterator]() { return this.entries(); }
}
// Body extraction: [bytes, contentType]
// ============================================================================
// ReadableStream (default reader; enough for fetch bodies and progress
// readers such as three.js' FileLoader)
// ============================================================================
class ReadableStreamDefaultReader {
  constructor(stream) {
    if (stream._s.locked) throw new TypeError('ReadableStream is locked');
    stream._s.locked = true;
    hidden(this, '_stream', stream);
    this.closed = stream._s.closedPromise;
  }
  read() {
    const s = this._stream._s;
    if (s.queue.length) return Promise.resolve({ value: s.queue.shift(), done: false });
    if (s.error !== undefined) return Promise.reject(s.error);
    if (s.done) return Promise.resolve({ value: undefined, done: true });
    const p = new Promise((resolve, reject) => s.waiting.push({ resolve, reject }));
    this._stream._pull();
    return p;
  }
  releaseLock() { this._stream._s.locked = false; }
  cancel(reason) { return this._stream.cancel(reason); }
}
class ReadableStream {
  constructor(source = {}) {
    let closedResolve, closedReject;
    const closedPromise = new Promise((res, rej) => { closedResolve = res; closedReject = rej; });
    closedPromise.catch(() => {});
    const s = { queue: [], waiting: [], done: false, error: undefined, locked: false, pulling: false, closedPromise, closedResolve, closedReject, source };
    hidden(this, '_s', s);
    const flush = () => {
      while (s.waiting.length && s.queue.length) s.waiting.shift().resolve({ value: s.queue.shift(), done: false });
      if (s.done && !s.queue.length) while (s.waiting.length) s.waiting.shift().resolve({ value: undefined, done: true });
      if (s.error !== undefined) while (s.waiting.length) s.waiting.shift().reject(s.error);
    };
    const controller = {
      get desiredSize() { return s.done ? 0 : 1 - s.queue.length; },
      enqueue: (chunk) => { if (s.done) throw new TypeError('stream is closed'); s.queue.push(chunk); flush(); },
      close: () => { if (s.done) return; s.done = true; s.closedResolve(); flush(); },
      error: (e) => { if (s.error !== undefined) return; s.error = e; s.done = true; s.closedReject(e); flush(); },
    };
    hidden(this, '_controller', controller);
    hidden(this, '_flush', flush);
    try {
      const r = source.start ? source.start(controller) : undefined;
      if (r && typeof r.then === 'function') r.then(() => this._pull(), (e) => controller.error(e));
    } catch (e) { controller.error(e); }
  }
  _pull() {
    const s = this._s;
    if (!s.source.pull || s.pulling || s.done || s.queue.length) return;
    s.pulling = true;
    Promise.resolve().then(() => s.source.pull(this._controller)).then(
      () => { s.pulling = false; if (s.waiting.length) this._pull(); },
      (e) => { s.pulling = false; this._controller.error(e); });
  }
  get locked() { return this._s.locked; }
  getReader(options) {
    if (options && options.mode === 'byob') throw new TypeError('BYOB readers are not supported');
    return new ReadableStreamDefaultReader(this);
  }
  cancel(reason) {
    const s = this._s;
    s.queue.length = 0;
    if (!s.done) { s.done = true; s.closedResolve(); this._flush(); }
    return Promise.resolve(s.source.cancel ? s.source.cancel(reason) : undefined);
  }
  async *[Symbol.asyncIterator]() {
    const reader = this.getReader();
    try { for (;;) { const { value, done } = await reader.read(); if (done) return; yield value; } } finally { reader.releaseLock(); }
  }
  static from(iterable) {
    const it = (iterable[Symbol.asyncIterator] || iterable[Symbol.iterator]).call(iterable);
    return new ReadableStream({ async pull(c) { const { value, done } = await it.next(); if (done) c.close(); else c.enqueue(value); } });
  }
}
const streamOfBytes = (bytes) => new ReadableStream({ start(c) { if (bytes && bytes.length) c.enqueue(bytes); c.close(); } });
const readAll = async (stream) => {
  const reader = stream.getReader();
  const parts = [];
  let total = 0;
  for (;;) {
    const { value, done } = await reader.read();
    if (done) break;
    const chunk = toBytes(value);
    parts.push(chunk);
    total += chunk.length;
  }
  const out = new Uint8Array(total);
  let o = 0;
  for (const p of parts) { out.set(p, o); o += p.length; }
  return out;
};

const extractBody = (body) => {
  if (body === null || body === undefined) return [null, null];
  if (body instanceof ReadableStream) return [body, null];
  if (typeof body === 'string') return [utf8Encode(body), 'text/plain;charset=UTF-8'];
  if (body instanceof URLSearchParams) return [utf8Encode(body.toString()), 'application/x-www-form-urlencoded;charset=UTF-8'];
  if (body instanceof Blob) return [blobBytes.get(body), body.type || null];
  if (body instanceof ArrayBuffer || ArrayBuffer.isView(body)) return [toBytes(body).slice(), null];
  if (body instanceof FormData) {
    const boundary = '----NativaXFormBoundary' + crypto.randomUUID().replace(/-/g, '');
    const chunks = [];
    for (const [k, v] of body) {
      if (v instanceof File) {
        chunks.push(utf8Encode(`--${boundary}\r\nContent-Disposition: form-data; name="${k}"; filename="${v.name}"\r\nContent-Type: ${v.type || 'application/octet-stream'}\r\n\r\n`), blobBytes.get(v), utf8Encode('\r\n'));
      } else {
        chunks.push(utf8Encode(`--${boundary}\r\nContent-Disposition: form-data; name="${k}"\r\n\r\n${v}\r\n`));
      }
    }
    chunks.push(utf8Encode(`--${boundary}--\r\n`));
    return [new Blob(chunks).__bytes(), `multipart/form-data; boundary=${boundary}`];
  }
  return [utf8Encode(String(body)), 'text/plain;charset=UTF-8'];
};
hidden(Blob.prototype, '__bytes', function () { return blobBytes.get(this); });
class BodyMixin {
  _initBody(bytes) { hidden(this, '_body', bytes); hidden(this, '_used', { v: false }); }
  get bodyUsed() { return this._used.v; }
  get body() {
    if (this._body === null) return null;
    if (this._body instanceof ReadableStream) return this._body;
    // Reading the stream disturbs the body, as in browsers.
    if (!this._stream) { hidden(this, '_stream', streamOfBytes(this._body)); this._used.v = true; }
    return this._stream;
  }
  _consume() {
    if (this._used.v) return Promise.reject(new TypeError('Body has already been consumed.'));
    this._used.v = true;
    if (this._body instanceof ReadableStream) return readAll(this._body);
    return Promise.resolve(this._body || new Uint8Array(0));
  }
  text() { return this._consume().then((b) => utf8Decode(b)); }
  json() { return this.text().then((t) => JSON.parse(t)); }
  arrayBuffer() { return this._consume().then((b) => b.slice().buffer); }
  bytes() { return this._consume().then((b) => b.slice()); }
  blob() { return this._consume().then((b) => new Blob([b], { type: (this.headers.get('content-type') || '').split(';')[0] })); }
  formData() {
    return this.text().then((t) => {
      const fd = new FormData();
      const ct = this.headers.get('content-type') || '';
      if (ct.includes('application/x-www-form-urlencoded')) for (const [k, v] of new URLSearchParams(t)) fd.append(k, v);
      else throw new TypeError('Could not parse content as FormData.');
      return fd;
    });
  }
}
const mixBody = (C) => { for (const k of Object.getOwnPropertyNames(BodyMixin.prototype)) if (k !== 'constructor') defineProperty(C.prototype, k, Object.getOwnPropertyDescriptor(BodyMixin.prototype, k)); };
class Request {
  constructor(input, init = {}) {
    let url, base = {};
    if (input instanceof Request) { base = input; url = input.url; }
    else url = new URL(String(input), document.baseURI).href;
    const method = String(init.method || base.method || 'GET').toUpperCase();
    const headers = new Headers(init.headers || base.headers);
    let body = null;
    if (init.body !== undefined && init.body !== null) {
      if (method === 'GET' || method === 'HEAD') throw new TypeError("Failed to construct 'Request': Request with GET/HEAD method cannot have body.");
      const [bytes, type] = extractBody(init.body);
      body = bytes;
      if (type && !headers.has('content-type')) headers.set('content-type', type);
    } else if (base._body) body = base._body;
    Object.assign(this, {
      url, method, headers, signal: init.signal || base.signal || new AbortSignal(), mode: init.mode || 'cors',
      credentials: init.credentials || 'same-origin', cache: init.cache || 'default', redirect: init.redirect || 'follow',
      referrer: 'about:client', referrerPolicy: init.referrerPolicy || '', integrity: init.integrity || '',
      keepalive: !!init.keepalive, destination: '', priority: init.priority || 'auto',
    });
    this._initBody(body);
  }
  clone() { if (this.bodyUsed) throw new TypeError('Request body is already used'); return new Request(this); }
}
mixBody(Request);
const statusTexts = { 200: 'OK', 201: 'Created', 204: 'No Content', 301: 'Moved Permanently', 302: 'Found', 304: 'Not Modified', 400: 'Bad Request', 401: 'Unauthorized', 403: 'Forbidden', 404: 'Not Found', 500: 'Internal Server Error' };
class Response {
  constructor(body = null, init = {}) {
    const status = init.status ?? 200;
    if (status < 200 || status > 599) throw new RangeError(`Failed to construct 'Response': The status provided (${status}) is outside the range [200, 599].`);
    const headers = new Headers(init.headers);
    const [bytes, type] = extractBody(body);
    if (type && !headers.has('content-type')) headers.set('content-type', type);
    Object.assign(this, { status, statusText: init.statusText ?? '', headers, type: 'default', url: init.url || '', redirected: !!init.redirected });
    this._initBody(bytes);
  }
  get ok() { return this.status >= 200 && this.status < 300; }
  clone() {
    if (this.bodyUsed) throw new TypeError('Response body is already used');
    const r = new Response(null, { status: this.status, statusText: this.statusText, headers: this.headers, url: this.url, redirected: this.redirected });
    hidden(r, '_body', this._body instanceof ReadableStream ? this._body : (this._body ? this._body.slice() : null));
    r.type = this.type;
    return r;
  }
  static error() { const r = new Response(null, { status: 200 }); defineProperty(r, 'status', { value: 0 }); r.type = 'error'; return r; }
  static json(data, init = {}) { const h = new Headers(init.headers); if (!h.has('content-type')) h.set('content-type', 'application/json'); return new Response(JSON.stringify(data), Object.assign({}, init, { headers: h })); }
  static redirect(url, status = 302) { return new Response(null, { status, headers: { location: new URL(url, document.baseURI).href } }); }
}
mixBody(Response);
// Response objects need their body slot writable for clone().
const dataUrl = (url) => {
  const m = /^data:([^,]*?)(;base64)?,(.*)$/s.exec(url);
  if (!m) throw new TypeError('Failed to fetch');
  const type = m[1] || 'text/plain;charset=US-ASCII';
  const bytes = m[2] ? base64ToBytes(decodeURIComponent(m[3])) : utf8Encode(decodeURIComponent(m[3]));
  return new Response(bytes, { status: 200, headers: { 'content-type': type } });
};
const fetch = (input, init = {}) => {
  let req;
  try { req = new Request(input, init); } catch (e) { return Promise.reject(e); }
  const signal = req.signal;
  if (signal.aborted) return Promise.reject(signal.reason);
  if (req.url.startsWith('data:')) { try { return Promise.resolve(dataUrl(req.url)); } catch (e) { return Promise.reject(e); } }
  if (req.url.startsWith('blob:')) {
    const b = objectUrls.get(req.url);
    if (!b) return Promise.reject(new TypeError('Failed to fetch'));
    return Promise.resolve(new Response(b, { status: 200, headers: { 'content-type': b.type } }));
  }
  return new Promise((resolve, reject) => {
    const id = nextAsync++;
    const onAbort = () => { asyncCalls.delete(id); host('net.abort', id); reject(signal.reason); };
    signal.addEventListener('abort', onAbort, { once: true });
    asyncCalls.set(id, {
      resolve: (r) => {
        signal.removeEventListener('abort', onAbort);
        const bytes = r.body === null ? null : new Uint8Array(takeBuffer(r.body));
        const res = new Response(r.status === 204 || r.status === 304 || req.method === 'HEAD' ? null : bytes,
          { status: r.status < 200 || r.status > 599 ? 200 : r.status, statusText: r.statusText, headers: r.headers, url: r.url, redirected: r.redirected });
        if (r.status < 200 || r.status > 599) defineProperty(res, 'status', { value: r.status });
        res.type = 'basic';
        resolve(res);
      },
      reject: (e) => { signal.removeEventListener('abort', onAbort); reject(new TypeError('Failed to fetch' + (e ? ` (${e})` : ''))); },
    });
    host('net.fetch', id, {
      url: req.url, method: req.method, headers: [...req.headers], body: req._body ? putBuffer(req._body) : null,
      timeout: init.timeout,
    });
  });
};

// ============================================================================
// XMLHttpRequest (async only)
// ============================================================================
class XMLHttpRequestEventTarget extends EventTarget {}
class XMLHttpRequest extends XMLHttpRequestEventTarget {
  constructor() {
    super();
    hidden(this, '_x', { headers: new Headers(), readyState: 0, status: 0, statusText: '', response: null, text: '', resHeaders: null, url: '', method: 'GET', controller: null, sent: false, timer: null, mime: null });
    Object.assign(this, { responseType: '', timeout: 0, withCredentials: false, upload: new XMLHttpRequestEventTarget() });
  }
  get readyState() { return this._x.readyState; }
  get status() { return this._x.status; }
  get statusText() { return this._x.statusText; }
  get responseURL() { return this._x.url; }
  get responseText() {
    if (this.responseType !== '' && this.responseType !== 'text') throw new DOMException("The value is only accessible if the object's 'responseType' is '' or 'text'.", 'InvalidStateError');
    return this._x.text;
  }
  get responseXML() { return null; }
  get response() {
    const x = this._x;
    if (this.responseType === '' || this.responseType === 'text') return x.text;
    return x.readyState === 4 ? x.response : null;
  }
  _state(n) { this._x.readyState = n; this.dispatchEvent(new Event('readystatechange')); }
  open(method, url, async = true) {
    if (async === false) throw new DOMException('Synchronous XMLHttpRequest is not supported', 'InvalidAccessError');
    const x = this._x;
    if (x.controller) x.controller.abort();
    Object.assign(x, { method: String(method).toUpperCase(), url: new URL(String(url), document.baseURI).href, headers: new Headers(), sent: false, status: 0, text: '', response: null, controller: null });
    this._state(1);
  }
  setRequestHeader(k, v) {
    if (this._x.readyState !== 1 || this._x.sent) throw new DOMException("The object's state must be OPENED.", 'InvalidStateError');
    this._x.headers.append(k, v);
  }
  overrideMimeType(m) { this._x.mime = String(m); }
  getResponseHeader(k) { return this._x.resHeaders ? this._x.resHeaders.get(k) : null; }
  getAllResponseHeaders() {
    if (!this._x.resHeaders) return '';
    return [...this._x.resHeaders].map(([k, v]) => `${k}: ${v}\r\n`).join('');
  }
  send(body = null) {
    const x = this._x;
    if (x.readyState !== 1 || x.sent) throw new DOMException("The object's state must be OPENED.", 'InvalidStateError');
    x.sent = true;
    x.controller = new AbortController();
    const finish = (type) => {
      x.status = 0; x.statusText = ''; x.text = ''; x.response = null;
      this._state(4);
      this.dispatchEvent(new ProgressEvent(type));
      this.dispatchEvent(new ProgressEvent('loadend'));
    };
    if (this.timeout > 0) x.timer = setTimeout(() => { x.controller.abort(new DOMException('timeout', 'TimeoutError')); }, this.timeout);
    this.dispatchEvent(new ProgressEvent('loadstart'));
    fetch(x.url, { method: x.method, headers: x.headers, body: x.method === 'GET' || x.method === 'HEAD' ? undefined : body, signal: x.controller.signal })
      .then(async (res) => {
        clearTimeout(x.timer);
        x.status = res.status; x.statusText = res.statusText; x.resHeaders = res.headers; x.url = res.url || x.url;
        this._state(2);
        const bytes = res._body || new Uint8Array(0);
        this._state(3);
        const t = this.responseType;
        if (t === '' || t === 'text') x.text = utf8Decode(bytes);
        else if (t === 'json') { try { x.response = JSON.parse(utf8Decode(bytes)); } catch (e) { x.response = null; } }
        else if (t === 'arraybuffer') x.response = bytes.slice().buffer;
        else if (t === 'blob') x.response = new Blob([bytes], { type: x.mime || (res.headers.get('content-type') || '') });
        else if (t === 'document') x.response = null;
        this._state(4);
        const total = bytes.length;
        this.dispatchEvent(new ProgressEvent('progress', { lengthComputable: true, loaded: total, total }));
        this.dispatchEvent(new ProgressEvent('load', { lengthComputable: true, loaded: total, total }));
        this.dispatchEvent(new ProgressEvent('loadend', { lengthComputable: true, loaded: total, total }));
      }, (e) => {
        clearTimeout(x.timer);
        if (e && e.name === 'TimeoutError') finish('timeout');
        else if (e && e.name === 'AbortError') finish('abort');
        else finish('error');
      });
  }
  abort() { const x = this._x; if (x.controller) x.controller.abort(); }
}
for (const [k, v] of Object.entries({ UNSENT: 0, OPENED: 1, HEADERS_RECEIVED: 2, LOADING: 3, DONE: 4 })) { XMLHttpRequest[k] = v; XMLHttpRequest.prototype[k] = v; }

// ============================================================================
// WebSocket
// ============================================================================
const sockets = new Map();
let nextSocket = 1;
class WebSocket extends EventTarget {
  constructor(url, protocols = []) {
    super();
    let u;
    try { u = new URL(String(url), document.baseURI); } catch (e) { throw new DOMException(`The URL '${url}' is invalid.`, 'SyntaxError'); }
    if (u.protocol === 'http:') u = new URL('ws:' + u.href.slice(5));
    if (u.protocol === 'https:') u = new URL('wss:' + u.href.slice(6));
    if (u.protocol !== 'ws:' && u.protocol !== 'wss:') throw new DOMException(`The URL's scheme must be either 'ws' or 'wss'. '${u.protocol}' is not allowed.`, 'SyntaxError');
    if (u.hash) throw new DOMException('The URL contains a fragment identifier.', 'SyntaxError');
    const id = nextSocket++;
    hidden(this, '_w', { id, readyState: 0, protocol: '', url: u.href });
    this.binaryType = 'blob';
    sockets.set(id, this);
    host('ws.open', id, u.href, Array.isArray(protocols) ? protocols.map(String) : [String(protocols)]);
  }
  get url() { return this._w.url; }
  get readyState() { return this._w.readyState; }
  get protocol() { return this._w.protocol; }
  get extensions() { return ''; }
  get bufferedAmount() { return 0; }
  send(data) {
    if (this._w.readyState === 0) throw new DOMException("Failed to execute 'send' on 'WebSocket': Still in CONNECTING state.", 'InvalidStateError');
    if (this._w.readyState !== 1) return;
    if (typeof data === 'string') host('ws.send', this._w.id, data, false);
    else if (data instanceof Blob) host('ws.send', this._w.id, bytesToBase64(blobBytes.get(data)), true);
    else if (data instanceof ArrayBuffer || ArrayBuffer.isView(data)) host('ws.send', this._w.id, bytesToBase64(toBytes(data)), true);
    else host('ws.send', this._w.id, String(data), false);
  }
  close(code, reason) {
    if (code !== undefined && code !== 1000 && (code < 3000 || code > 4999)) throw new DOMException(`The code must be either 1000, or between 3000 and 4999. ${code} is neither.`, 'InvalidAccessError');
    if (this._w.readyState >= 2) return;
    this._w.readyState = 2;
    host('ws.close', this._w.id, code ?? 1000, reason === undefined ? '' : String(reason));
  }
}
for (const [k, v] of Object.entries({ CONNECTING: 0, OPEN: 1, CLOSING: 2, CLOSED: 3 })) { WebSocket[k] = v; WebSocket.prototype[k] = v; }
register('__nx_ws', (msg) => {
  const ws = sockets.get(msg.id);
  if (!ws) return;
  switch (msg.type) {
    case 'open':
      ws._w.readyState = 1;
      ws._w.protocol = msg.protocol || '';
      ws.dispatchEvent(new Event('open'));
      break;
    case 'message': {
      let data = msg.data;
      if (msg.binary !== undefined) {
        const bytes = base64ToBytes(msg.binary);
        data = ws.binaryType === 'arraybuffer' ? bytes.buffer : new Blob([bytes]);
      }
      ws.dispatchEvent(new MessageEvent('message', { data, origin: new URL(ws.url).origin }));
      break;
    }
    case 'error':
      ws.dispatchEvent(new Event('error'));
      break;
    case 'close':
      ws._w.readyState = 3;
      sockets.delete(msg.id);
      ws.dispatchEvent(new CloseEvent('close', { code: msg.code, reason: msg.reason, wasClean: !!msg.wasClean }));
      break;
  }
});
''';

const String _ioExports = r'''
// ============================================================================
// Dedicated workers: each runs in its own engine (on its own thread when the
// host provides a worker launcher), connected by an implicit MessagePort.
// ============================================================================
const workers = new Map();
const transferOf = (o) => Array.isArray(o) ? o : (o && o.transfer ? [...o.transfer] : []);
class Worker extends EventTarget {
  constructor(url, options = {}) {
    super();
    const href = new URL(String(url), document.baseURI).href;
    let source = null;
    if (href.startsWith('blob:')) {
      const b = objectUrls.get(href);
      if (!b) throw new DOMException(`Failed to construct 'Worker': Script at '${href}' cannot be accessed.`, 'SecurityError');
      source = utf8Decode(blobBytes.get(b));
    } else if (href.startsWith('data:')) {
      const m = /^data:[^,]*?(;base64)?,(.*)$/s.exec(href);
      if (m) source = m[1] ? utf8Decode(base64ToBytes(decodeURIComponent(m[2]))) : decodeURIComponent(m[2]);
    }
    const type = options && options.type === 'module' ? 'module' : 'classic';
    const [id, port] = host('worker.create', href, { type, name: options && options.name ? String(options.name) : '', source });
    const p = adoptPort(port);
    hidden(this, '_w', { id, port: p, terminated: false });
    p.addEventListener('message', (e) => this.dispatchEvent(new MessageEvent('message', { data: e.data, ports: e.ports })));
    p.addEventListener('messageerror', () => this.dispatchEvent(new MessageEvent('messageerror')));
    p.start();
    workers.set(id, this);
  }
  postMessage(message, transfer) { if (!this._w.terminated) this._w.port.postMessage(message, transferOf(transfer)); }
  terminate() {
    const w = this._w;
    if (w.terminated) return;
    w.terminated = true;
    workers.delete(w.id);
    w.port.close();
    host('worker.terminate', w.id);
  }
}
for (const t of ['message', 'messageerror', 'error']) {
  defineProperty(Worker.prototype, 'on' + t, {
    get() { return (this._handlers || {})[t] || null; },
    set(fn) {
      if (!this._handlers) hidden(this, '_handlers', {});
      if (this._handlers[t]) this.removeEventListener(t, this._handlers[t]);
      this._handlers[t] = typeof fn === 'function' ? fn : null;
      if (this._handlers[t]) this.addEventListener(t, this._handlers[t]);
    },
    configurable: true, enumerable: true,
  });
}
register('__nx_worker', (msg) => {
  const w = workers.get(msg.id);
  if (msg.type === 'console' && typeof console !== 'undefined') { (console[msg.level] || console.log)(msg.text); return; }
  if (!w) return;
  if (msg.type === 'error') {
    const ev = new ErrorEvent('error', { message: msg.message, filename: msg.filename || '', lineno: msg.lineno || 0, colno: msg.colno || 0, cancelable: true });
    if (w.dispatchEvent(ev) && typeof console !== 'undefined') console.error(`Uncaught ${msg.message}`);
  } else if (msg.type === 'close') {
    workers.delete(msg.id);
  }
});

for (const [name, value] of Object.entries({
  Blob, File, FileList, FileReader, FormData, AbortController, AbortSignal, Headers, Request, Response, fetch, ReadableStream, ReadableStreamDefaultReader,
  XMLHttpRequest, XMLHttpRequestEventTarget, XMLHttpRequestUpload: XMLHttpRequestEventTarget, WebSocket, Worker,
  indexedDB, IDBFactory, IDBDatabase, IDBTransaction, IDBObjectStore, IDBIndex, IDBRequest, IDBOpenDBRequest,
  IDBCursor, IDBCursorWithValue, IDBKeyRange, IDBVersionChangeEvent,
})) defineProperty(globalThis, name, { value, enumerable: false, writable: true, configurable: true });
''';
