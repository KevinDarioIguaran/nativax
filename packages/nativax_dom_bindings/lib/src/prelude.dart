import 'web_prelude.dart';

/// Script-side half of the DOM bindings. Wrappers hold only a numeric id;
/// every property access goes through `__nx.host`, so scripts never see Dart
/// objects. Installed once per runtime, before any document script.
const String domPrelude =
    r'''
(() => {
'use strict';
const host = __nx.host;
// Present when this runtime is a worker's global scope (see WorkerScopeInfo).
const workerScope = globalThis.__nx_scope || null;
delete globalThis.__nx_scope;
// Bytes from the host arrive as parked native buffers (no base64/JSON).
const takeBuffer = __nx.takeBuffer;
const putBuffer = __nx.putBuffer;
// Host-invoked callbacks go to a private registry, not to globalThis.
const register = __nx.register;
const ID = Symbol('nativax.id');
const defineProperty = Object.defineProperty;
const hidden = (obj, name, value) =>
  defineProperty(obj, name, { value, enumerable: false, writable: false, configurable: true });

// ---- wrapper identity ------------------------------------------------------
const cache = new Map();                  // id -> WeakRef(wrapper)
const finalizer = new FinalizationRegistry((id) => {
  const ref = cache.get(id);
  if (ref && ref.deref() === undefined) {
    cache.delete(id);
    host('node.release', id);
  }
});

// Filled by the web platform prelude: tag name -> HTML*Element prototype.
let elementProtos = null;
let upgradeHook = null;
const protoFor = (t, n) => {
  if (t === 1) return (elementProtos && elementProtos[n]) || (elementProtos && elementProtos['*']) || Element.prototype;
  if (t === 3) return Text.prototype;
  if (t === 7) return ProcessingInstruction.prototype;
  if (t === 8) return Comment.prototype;
  if (t === 9) return Document.prototype;
  if (t === 10) return DocumentType.prototype;
  if (t === 11) return DocumentFragment.prototype;
  if (t === 0) return Window.prototype;
  return Node.prototype;
};

// Wrappers of nodes connected to the document are held strongly so their
// identity (and script-set properties) survive while the node is in the
// tree; the host demotes them to weak references when nodes are removed.
const strong = new Map();               // id -> wrapper
register('__nx_conn', (msg) => {
  for (const id of msg.detach) strong.delete(id);
  for (const id of msg.attach) {
    const ref = cache.get(id);
    const w = ref && ref.deref();
    if (w) strong.set(id, w);
  }
});

// desc: null | [id, nodeType, localName, connected]
const wrap = (desc) => {
  if (desc === null || desc === undefined) return null;
  const id = desc[0];
  const ref = cache.get(id);
  let w = ref && ref.deref();
  if (w) {
    if (desc[3] === true && !strong.has(id)) strong.set(id, w);
    return w;
  }
  w = Object.create(protoFor(desc[1], desc[2]));
  hidden(w, ID, id);
  cache.set(id, new WeakRef(w));
  finalizer.register(w, id);
  if (desc[3] === true) strong.set(id, w);
  if (upgradeHook && desc[1] === 1) upgradeHook(w, desc[2]);
  return w;
};
const wrapAll = (descs) => descs.map(wrap);
const idOf = (node, what = 'node') => {
  const id = node !== null && typeof node === 'object' ? node[ID] : undefined;
  if (id === undefined) throw new TypeError(`parameter is not a ${what}`);
  return id;
};
const domString = (v) => v === null ? 'null' : v === undefined ? 'undefined' : String(v);
const nodeArg = (n) => (n instanceof Node ? n : document.createTextNode(domString(n)));

// ---- listeners -------------------------------------------------------------
const listenerIds = new WeakMap();   // fn/object -> id
const listeners = new Map();         // id -> fn/object
let nextListener = 1;
const listenerId = (cb) => {
  let id = listenerIds.get(cb);
  if (id === undefined) {
    id = nextListener++;
    listenerIds.set(cb, id);
  }
  listeners.set(id, cb);
  return id;
};
const captureOf = (o) => (typeof o === 'boolean' ? o : !!(o && o.capture));

// ---- events ----------------------------------------------------------------
const events = new Map();            // event id -> Event object
class Event {
  constructor(type, init = {}) {
    if (arguments.length === 0) throw new TypeError('Event requires a type');
    hidden(this, '__type', String(type));
    hidden(this, '__init', { bubbles: !!init.bubbles, cancelable: !!init.cancelable });
  }
  get type() { return this.__desc ? this.__desc.type : this.__type; }
  get bubbles() { return this.__desc ? this.__desc.bubbles : this.__init.bubbles; }
  get cancelable() { return this.__desc ? this.__desc.cancelable : this.__init.cancelable; }
  get isTrusted() { return this.__desc ? this.__desc.isTrusted : false; }
  get target() { return this.__id ? wrap(host('event.get', this.__id, 'target')) : null; }
  get currentTarget() { return this.__id ? wrap(host('event.get', this.__id, 'currentTarget')) : null; }
  get eventPhase() { return this.__id ? host('event.get', this.__id, 'eventPhase') : 0; }
  get defaultPrevented() { return this.__id ? host('event.get', this.__id, 'defaultPrevented') : false; }
  get timeStamp() { return this.__desc ? this.__desc.timeStamp : 0; }
  preventDefault() { if (this.__id) host('event.call', this.__id, 'preventDefault'); }
  stopPropagation() { if (this.__id) host('event.call', this.__id, 'stopPropagation'); }
  stopImmediatePropagation() { if (this.__id) host('event.call', this.__id, 'stopImmediatePropagation'); }
}
Event.NONE = 0; Event.CAPTURING_PHASE = 1; Event.AT_TARGET = 2; Event.BUBBLING_PHASE = 3;
class CustomEvent extends Event {
  constructor(type, init = {}) { super(type, init); hidden(this, 'detail', init.detail === undefined ? null : init.detail); }
}
// Trusted events created by the host get their detail fields as properties
// (key, code, value, checked, ...).
let eventProtoFor = null;
const eventFor = (desc) => {
  let ev = events.get(desc.id);
  if (!ev) {
    ev = Object.create(eventProtoFor ? eventProtoFor(desc.type) : Event.prototype);
    hidden(ev, '__id', desc.id);
    hidden(ev, '__desc', desc);
    for (const k of Object.keys(desc.detail || {})) {
      if (k === '__drag') hidden(ev, 'dataTransfer', dataTransferFor(desc.detail[k]));
      else hidden(ev, k, desc.detail[k]);
    }
    events.set(desc.id, ev);
  }
  return ev;
};

const invoke = (cb, self, ev) => {
  if (typeof cb === 'function') cb.call(self, ev);
  else if (cb && typeof cb.handleEvent === 'function') cb.handleEvent(ev);
};
register('__nx_dispatch', (msg) => {
  const cb = listeners.get(msg.listener);
  if (!cb) return;
  const ev = eventFor(msg.event);
  const self = wrap(msg.currentTarget);
  // Inline handler properties (el.onclick) are stored as listeners too.
  invoke(cb, self, ev);
});
register('__nx_eventDone', (id) => { events.delete(id); });
register('__nx_releaseListener', (id) => {
  const cb = listeners.get(id);
  listeners.delete(id);
  if (cb) listenerIds.delete(cb);
});

class EventTarget {
  addEventListener(type, cb, options) {
    if (cb === null || cb === undefined) return;
    if (typeof cb !== 'function' && typeof cb !== 'object') throw new TypeError('listener must be a function');
    const once = !!(options && typeof options === 'object' && options.once);
    host('ev.add', idOf(this, 'EventTarget'), String(type), listenerId(cb), captureOf(options), once);
  }
  removeEventListener(type, cb, options) {
    const id = cb ? listenerIds.get(cb) : undefined;
    if (id === undefined) return;
    host('ev.remove', idOf(this, 'EventTarget'), String(type), id, captureOf(options));
  }
  dispatchEvent(ev) {
    if (!(ev instanceof Event)) throw new TypeError('parameter is not an Event');
    if (ev.__id) throw new Error('event is already being dispatched');
    const id = host('event.create', ev.type, ev.bubbles, ev.cancelable);
    hidden(ev, '__id', id);
    events.set(id, ev);
    try {
      return host('ev.dispatch', idOf(this, 'EventTarget'), id);
    } finally {
      events.delete(id);
      delete ev.__id;
    }
  }
}

// on<event> handler properties.
const handlerProps = ['click', 'input', 'change', 'submit', 'focus', 'blur', 'keydown', 'keyup', 'load', 'resize'];
const handlers = new WeakMap();
for (const name of handlerProps) {
  defineProperty(EventTarget.prototype, 'on' + name, {
    get() { const h = handlers.get(this); return (h && h[name]) || null; },
    set(fn) {
      let h = handlers.get(this);
      if (!h) { h = {}; handlers.set(this, h); }
      if (h[name]) this.removeEventListener(name, h.__wrappers[name]);
      h.__wrappers = h.__wrappers || {};
      if (typeof fn === 'function') {
        h[name] = fn;
        const wrapper = function (ev) {
          const r = fn.call(this, ev);
          if (r === false) ev.preventDefault();
        };
        h.__wrappers[name] = wrapper;
        this.addEventListener(name, wrapper);
      } else {
        h[name] = null;
      }
    },
    configurable: true,
  });
}

// ---- Node ------------------------------------------------------------------
const get = (name) => function () { return host('node.get', this[ID], name); };
const getNode = (name) => function () { return wrap(host('node.get', this[ID], name)); };
const getNodes = (name) => function () { return wrapAll(host('node.get', this[ID], name)); };
const liveLists = new Map();
const live = (kind) => function () {
  const key = this[ID] + ':' + kind;
  let list = liveLists.get(key);
  if (!list) {
    const Ctor = kind === 'children' ? HTMLCollection : NodeList;
    const raw = new Ctor(this[ID], kind);
    list = Ctor === HTMLCollection ? htmlCollectionFor(raw) : nodeListFor(raw);
    liveLists.set(key, list);
  }
  return list;
};

class NodeList {
  constructor(id, kind) { hidden(this, '__id', id); hidden(this, '__kind', kind); }
  _list() { return host('node.get', this.__id, this.__kind); }
  get length() { return this._list().length; }
  item(i) { const l = this._list(); return i >= 0 && i < l.length ? wrap(l[i]) : null; }
  forEach(fn, self) { const l = this._list(); for (let i = 0; i < l.length; i++) fn.call(self, wrap(l[i]), i, this); }
  *[Symbol.iterator]() { for (let i = 0; i < this.length; i++) yield this.item(i); }
  *entries() { for (let i = 0; i < this.length; i++) yield [i, this.item(i)]; }
  *keys() { for (let i = 0; i < this.length; i++) yield i; }
  *values() { for (let i = 0; i < this.length; i++) yield this.item(i); }
}
NodeList.prototype[Symbol.iterator] = Array.prototype[Symbol.iterator];
NodeList.prototype.keys = Array.prototype.keys;
if (Array.prototype.values) NodeList.prototype.values = Array.prototype.values;
NodeList.prototype.entries = Array.prototype.entries;
NodeList.prototype.forEach = Array.prototype.forEach;
class StaticNodeList extends NodeList {
  constructor(items) { super(-1, 'static'); hidden(this, '__items', items); }
  get length() { return this.__items.length; }
  item(i) { i = Number(i); return Number.isInteger(i) && i >= 0 && i < this.__items.length ? this.__items[i] : null; }
}
StaticNodeList.prototype[Symbol.iterator] = Array.prototype[Symbol.iterator];
StaticNodeList.prototype.keys = Array.prototype.keys;
if (Array.prototype.values) StaticNodeList.prototype.values = Array.prototype.values;
StaticNodeList.prototype.entries = Array.prototype.entries;
StaticNodeList.prototype.forEach = Array.prototype.forEach;
for (const m of ['map', 'filter', 'slice', 'indexOf', 'reduce', 'some', 'every', 'find', 'findIndex', 'join']) {
  if (Array.prototype[m]) StaticNodeList.prototype[m] = Array.prototype[m];
}
const staticNodeList = (descs) => {
  const items = descs.map(wrap);
  return new Proxy(new StaticNodeList(items), {
    get(t, p, r) {
      if (typeof p === 'string' && /^\d+$/.test(p)) return t.item(Number(p)) ?? undefined;
      return Reflect.get(t, p, r);
    },
    has(t, p) {
      if (typeof p === 'string' && /^\d+$/.test(p)) return Number(p) < t.length;
      return Reflect.has(t, p);
    },
    ownKeys(t) { const keys = []; for (let i = 0; i < t.length; i++) keys.push(String(i)); return keys; },
    getOwnPropertyDescriptor(t, p) {
      if (typeof p === 'string' && /^\d+$/.test(p)) {
        const i = Number(p);
        if (i >= t.length) return undefined;
        return { value: t.item(i), enumerable: true, configurable: true, writable: false };
      }
      return Reflect.getOwnPropertyDescriptor(t, p);
    },
  });
};
class HTMLCollection {
  constructor(id, kind) { hidden(this, '__id', id); hidden(this, '__kind', kind); }
  _list() { return host('node.get', this.__id, this.__kind); }
  get length() { return this._list().length; }
  item(i) {
    let n = Number(i); if (!Number.isFinite(n)) n = 0;
    const idx = ((Math.trunc(n) % 4294967296) + 4294967296) % 4294967296;
    const l = this._list();
    return idx < l.length ? wrap(l[idx]) : null;
  }
  namedItem(name) {
    name = String(name);
    if (!name) return null;
    for (const d of this._list()) {
      const e = wrap(d);
      if (e.id === name || (e.namespaceURI === HTML_NS && e.getAttribute('name') === name)) return e;
    }
    return null;
  }
  *[Symbol.iterator]() { for (const d of this._list()) yield wrap(d); }
  *entries() { const l = this._list(); for (let i = 0; i < l.length; i++) yield [i, wrap(l[i])]; }
  *keys() { const l = this._list(); for (let i = 0; i < l.length; i++) yield i; }
  *values() { for (const d of this._list()) yield wrap(d); }
}
class LiveQueryCollection extends HTMLCollection {
  constructor(id, op, arg) {
    super(id, 'query');
    hidden(this, '__op', op);
    hidden(this, '__arg', arg);
  }
  _list() { return host(this.__op, this.__id, this.__arg); }
}
class FilteredTagCollection extends HTMLCollection {
  constructor(id, name, namespaced, ns = null) {
    super(id, 'query');
    hidden(this, '__name', name);
    hidden(this, '__namespaced', namespaced);
    hidden(this, '__ns', ns === null || ns === undefined || ns === '' ? null : String(ns));
  }
  _list() {
    const name = this.__name, ns = this.__ns;
    return host('q.tag', this.__id, '*').filter((d) => {
      const e = wrap(d);
      if (this.__namespaced) {
        if (ns === '*') { /* any namespace */ }
        else if (ns === null) { if (e.namespaceURI !== null) return false; }
        else if (e.namespaceURI !== ns) return false;
        return name === '*' || e.localName === name;
      }
      if (name === '*') return true;
      if (e.namespaceURI === HTML_NS) { const qname = e.prefix ? e.prefix + ':' + e.localName : e.localName; return qname === asciiLower(name); }
      return e.tagName === name;
    });
  }
}
const nodeListFor = (list) => new Proxy(list, {
  get(t, p, r) {
    if (typeof p === 'string' && /^\d+$/.test(p)) {
      const i = Number(p);
      return i < t.length ? t.item(i) : undefined;
    }
    return Reflect.get(t, p, r);
  },
  has(t, p) {
    if (typeof p === 'string' && /^\d+$/.test(p)) return Number(p) < t.length;
    return Reflect.has(t, p);
  },
  ownKeys(t) {
    const keys = [];
    for (let i = 0; i < t.length; i++) keys.push(String(i));
    return keys;
  },
  getOwnPropertyDescriptor(t, p) {
    if (typeof p === 'string' && /^\d+$/.test(p)) {
      const i = Number(p);
      if (i >= t.length) return undefined;
      return { value: t.item(i), enumerable: true, configurable: true, writable: false };
    }
    return Reflect.getOwnPropertyDescriptor(t, p);
  },
});
const collectionNames = (collection) => {
  const names = [];
  const seen = new Set();
  for (const d of collection._list()) {
    const e = wrap(d);
    if (e.nodeType !== 1) continue;
    const name = e.id || (e.namespaceURI === HTML_NS ? e.getAttribute('name') : null);
    if (name && !seen.has(name)) { seen.add(name); names.push(name); }
  }
  return names;
};
const htmlCollectionFor = (collection) => new Proxy(collection, {
  get(t, p, r) {
    if (typeof p === 'string') {
      if (/^\d+$/.test(p)) return t.item(Number(p)) ?? undefined;
      if (!(p in t) && collectionNames(t).includes(p)) return t.namedItem(p);
    }
    return Reflect.get(t, p, r);
  },
  has(t, p) {
    if (typeof p === 'string') {
      if (/^\d+$/.test(p)) return Number(p) < t.length;
      if (collectionNames(t).includes(p)) return true;
    }
    return Reflect.has(t, p);
  },
  ownKeys(t) {
    const keys = [];
    for (let i = 0; i < t.length; i++) keys.push(String(i));
    return keys.concat(collectionNames(t));
  },
  getOwnPropertyDescriptor(t, p) {
    if (typeof p !== 'string') return undefined;
    if (/^\d+$/.test(p)) {
      const i = Number(p);
      if (i >= t.length) return undefined;
      return { value: t.item(i), enumerable: true, configurable: true, writable: false };
    }
    if (collectionNames(t).includes(p)) {
      return { value: t.namedItem(p), enumerable: false, configurable: true, writable: false };
    }
    return Reflect.getOwnPropertyDescriptor(t, p);
  },
  set(t, p, v, r) {
    if (typeof p === 'string' && /^\d+$/.test(p)) return false;
    return Reflect.set(t, p, v, r);
  },
});
const movingState = { value: false };
const accessor = (proto, name, getter, setter) =>
  defineProperty(proto, name, { get: getter, set: setter, configurable: true, enumerable: true });

class Node extends EventTarget {
  constructor() { throw new TypeError('Illegal constructor'); }
  appendChild(child) {
    if (child && child.nodeType === 1 && child.hasAttribute('nonce') && !movingState.value) child.setAttribute('nonce', '');
    host('node.insertBefore', this[ID], idOf(child), null);
    if (child && child.localName === 'iframe') queueMicrotask(() => { try { child.dispatchEvent(new Event('load')); } catch (e) {} });
    return child;
  }
  insertBefore(child, ref) {
    if (child && child.nodeType === 1 && child.hasAttribute('nonce') && !movingState.value) child.setAttribute('nonce', '');
    host('node.insertBefore', this[ID], idOf(child), ref === null || ref === undefined ? null : idOf(ref));
    return child;
  }
  removeChild(child) { host('node.removeChild', this[ID], idOf(child)); return child; }
  replaceChild(newChild, oldChild) { host('node.replaceChild', this[ID], idOf(newChild), idOf(oldChild)); return oldChild; }
  remove() { host('node.remove', this[ID]); }
  contains(other) { return other === null ? false : host('node.contains', this[ID], idOf(other)); }
  cloneNode(deep = false) { return wrap(host('node.clone', this[ID], !!deep)); }
  hasChildNodes() { return host('node.get', this[ID], 'childCount') > 0; }
  append(...nodes) { const args = nodeArgs(nodes); for (const n of args) if (n.contains(this)) throw new DOMException('The new child contains the parent.', 'HierarchyRequestError'); this.appendChild(fragmentOf(args)); }
  prepend(...nodes) {
    const args = nodeArgs(nodes);
    for (const n of args) if (n.contains(this)) throw new DOMException('The new child contains the parent.', 'HierarchyRequestError');
    const marker = document.createComment('');
    this.insertBefore(marker, this.firstChild);
    const frag = fragmentOf(args);
    this.insertBefore(frag, marker);
    this.removeChild(marker);
  }
  replaceChildren(...nodes) {
    const args = nodeArgs(nodes);
    for (const n of args) if (n.contains(this)) throw new DOMException('The new child contains the parent.', 'HierarchyRequestError');
    host('node.replaceChildren', this[ID], args.map((n) => idOf(n)));
  }
}
const NODE_CONSTANTS = {
  ELEMENT_NODE: 1, ATTRIBUTE_NODE: 2, TEXT_NODE: 3, CDATA_SECTION_NODE: 4,
  ENTITY_REFERENCE_NODE: 5, ENTITY_NODE: 6, PROCESSING_INSTRUCTION_NODE: 7,
  COMMENT_NODE: 8, DOCUMENT_NODE: 9, DOCUMENT_TYPE_NODE: 10,
  DOCUMENT_FRAGMENT_NODE: 11, NOTATION_NODE: 12,
  DOCUMENT_POSITION_DISCONNECTED: 0x01, DOCUMENT_POSITION_PRECEDING: 0x02,
  DOCUMENT_POSITION_FOLLOWING: 0x04, DOCUMENT_POSITION_CONTAINS: 0x08,
  DOCUMENT_POSITION_CONTAINED_BY: 0x10,
  DOCUMENT_POSITION_IMPLEMENTATION_SPECIFIC: 0x20,
};
for (const [name, value] of Object.entries(NODE_CONSTANTS)) {
  Node[name] = value;
  Node.prototype[name] = value;
}
const NP = Node.prototype;
accessor(NP, 'nodeType', get('nodeType'));
accessor(NP, 'nodeName', function () { return this.nodeType === 1 ? this.tagName : host('node.get', this[ID], 'nodeName'); });
accessor(NP, 'isConnected', get('isConnected'));
accessor(NP, 'parentNode', getNode('parentNode'));
accessor(NP, 'parentElement', getNode('parentElement'));
accessor(NP, 'firstChild', getNode('firstChild'));
accessor(NP, 'lastChild', getNode('lastChild'));
accessor(NP, 'nextSibling', getNode('nextSibling'));
accessor(NP, 'previousSibling', getNode('previousSibling'));
accessor(NP, 'nextElementSibling', getNode('nextElementSibling'));
accessor(NP, 'previousElementSibling', getNode('previousElementSibling'));
accessor(NP, 'childNodes', live('childNodes'));
accessor(NP, 'ownerDocument', function () { return this.nodeType === 9 ? null : wrap(host('node.get', this[ID], 'ownerDocument')); });
accessor(NP, 'textContent', get('textContent'), function (v) {
  host('node.set', this[ID], 'textContent', v === null || v === undefined ? '' : domString(v));
});
accessor(NP, 'nodeValue', function () {
  const t = this.nodeType;
  return t === 3 || t === 7 || t === 8 ? this.textContent : null;
}, function (v) {
  const t = this.nodeType;
  if (t === 3 || t === 7 || t === 8) this.textContent = v;
});

const nodeArgs = (nodes) => nodes.map(nodeArg);
const fragmentOf = (nodes) => {
  const frag = document.createDocumentFragment();
  for (const n of nodes) frag.appendChild(n);
  return frag;
};
NP.before = function (...raw) {
  const p = this.parentNode; if (!p) return;
  const marker = document.createComment('');
  p.insertBefore(marker, this);
  const frag = fragmentOf(nodeArgs(raw));
  p.insertBefore(frag, marker);
  p.removeChild(marker);
};
NP.after = function (...raw) {
  const p = this.parentNode; if (!p) return;
  const marker = document.createComment('');
  p.insertBefore(marker, this.nextSibling);
  const frag = fragmentOf(nodeArgs(raw));
  p.insertBefore(frag, marker);
  p.removeChild(marker);
};
NP.replaceWith = function (...raw) {
  const p = this.parentNode; if (!p) return;
  const marker = document.createComment('');
  p.insertBefore(marker, this);
  const frag = fragmentOf(nodeArgs(raw));
  if (this.parentNode === p) p.removeChild(this);
  p.insertBefore(frag, marker);
  p.removeChild(marker);
};

const DOM_EXCEPTION_CODES = {
  IndexSizeError: 1, HierarchyRequestError: 3, WrongDocumentError: 4, InvalidCharacterError: 5,
  NoModificationAllowedError: 7, NotFoundError: 8, NotSupportedError: 9, InUseAttributeError: 10,
  InvalidStateError: 11, SyntaxError: 12, InvalidModificationError: 13, NamespaceError: 14,
  InvalidAccessError: 15, TypeMismatchError: 17, SecurityError: 18, NetworkError: 19, AbortError: 20,
  URLMismatchError: 21, QuotaExceededError: 22, TimeoutError: 23, InvalidNodeTypeError: 24, DataCloneError: 25,
};
class DOMException extends Error {
  constructor(message = '', name = 'Error') {
    super(String(message));
    this.name = String(name);
  }
  get code() { return DOM_EXCEPTION_CODES[this.name] || 0; }
}
for (const [name, code] of Object.entries(DOM_EXCEPTION_CODES)) {
  defineProperty(DOMException, name, { value: code, enumerable: true });
  defineProperty(DOMException.prototype, name, { value: code, enumerable: true });
}
class CharacterData extends Node {}
const CDP = CharacterData.prototype;
const cdUnsigned = (v) => {
  const n = Number(v);
  if (!Number.isFinite(n) || n === 0) return 0;
  return ((Math.trunc(n) % 4294967296) + 4294967296) % 4294967296;
};
const cdIndex = (v, max) => {
  const i = cdUnsigned(v);
  if (i > max) throw new DOMException('index out of range', 'IndexSizeError');
  return i;
};
const cdCount = (v, max) => {
  const n = Number(v);
  if (!Number.isFinite(n) || n === 0) return 0;
  const i = Math.trunc(n);
  const unsigned = ((i % 4294967296) + 4294967296) % 4294967296;
  return Math.min(unsigned, max);
};
accessor(CDP, 'data', get('textContent'), function (v) { this.textContent = v === null ? '' : domString(v); });
accessor(CDP, 'length', function () { return this.textContent.length; });
CDP.appendData = function (data) {
  if (arguments.length < 1) throw new TypeError('appendData requires data');
  this.data = this.data + domString(data);
};
CDP.insertData = function (offset, data) {
  if (arguments.length < 2) throw new TypeError('insertData requires offset and data');
  const current = this.data;
  const i = cdIndex(offset, current.length);
  this.data = current.slice(0, i) + domString(data) + current.slice(i);
};
CDP.deleteData = function (offset, count) {
  if (arguments.length < 2) throw new TypeError('deleteData requires offset and count');
  const current = this.data;
  const i = cdIndex(offset, current.length);
  const n = cdCount(count, current.length - i);
  this.data = current.slice(0, i) + current.slice(i + n);
};
CDP.replaceData = function (offset, count, data) {
  if (arguments.length < 3) throw new TypeError('replaceData requires offset, count and data');
  const current = this.data;
  const i = cdIndex(offset, current.length);
  const n = cdCount(count, current.length - i);
  this.data = current.slice(0, i) + domString(data) + current.slice(i + n);
};
CDP.substringData = function (offset, count) {
  if (arguments.length < 2) throw new TypeError('substringData requires offset and count');
  const current = this.data;
  const i = cdIndex(offset, current.length);
  const n = cdCount(count, current.length - i);
  return current.slice(i, i + n);
};
class Text extends CharacterData {
  constructor(data = '') { return document.createTextNode(domString(data)); }
  get wholeText() {
    let first = this;
    while (first.previousSibling && first.previousSibling.nodeType === 3) first = first.previousSibling;
    let text = '';
    for (let n = first; n && n.nodeType === 3; n = n.nextSibling) text += n.data;
    return text;
  }
  splitText(offset) { return wrap(host('node.splitText', this[ID], Number(offset))); }
}
class CDATASection extends Text {
  get nodeType() { return 4; }
  get nodeName() { return '#cdata-section'; }
}
class Comment extends CharacterData {
  constructor(data = '') { return document.createComment(domString(data)); }
}
class ProcessingInstruction extends CharacterData {
  get target() { return host('node.get', this[ID], 'target'); }
}
class DocumentType extends Node {
  get name() { return host('node.get', this[ID], 'name'); }
  get publicId() { return host('node.get', this[ID], 'publicId'); }
  get systemId() { return host('node.get', this[ID], 'systemId'); }
}
NP.moveBefore = function (node, reference) {
  if (arguments.length < 2) throw new TypeError('moveBefore requires two arguments');
  if (!(node instanceof Node)) throw new TypeError('parameter is not a Node');
  if (node.ownerDocument && this.ownerDocument && node.ownerDocument !== this.ownerDocument) throw new DOMException('cross-document move', 'HierarchyRequestError');
  if (reference !== null && reference !== undefined && reference.parentNode !== this) throw new DOMException('reference is not a child', 'NotFoundError');
  if (node === reference) return node;
  movingState.value = true;
  try { this.insertBefore(node, reference === undefined ? null : reference); } finally { movingState.value = false; }
  return node;
};
Node.prototype.isSameNode = function (other) { return other === this; };
NP.compareDocumentPosition = function (other) {
  if (!(other instanceof Node)) throw new TypeError('parameter is not a Node');
  if (this === other) return 0;
  const rootOf = (n) => { let r = n; while (r.parentNode) r = r.parentNode; return r; };
  if (rootOf(this) !== rootOf(other)) return 1 | 32;
  if (this.contains(other)) return 8 | 4;
  if (other.contains(this)) return 16 | 2;
  const path = (n) => { const p = []; for (let x = n; x; x = x.parentNode) p.unshift(x); return p; };
  const a = path(this), b = path(other);
  let i = 0; while (i < a.length && i < b.length && a[i] === b[i]) i++;
  if (i >= a.length || i >= b.length) return 1 | 32;
  const pa = a[i - 1], ca = a[i], cb = b[i];
  const idx = (n) => [...pa.childNodes].indexOf(n);
  return idx(ca) < idx(cb) ? 2 : 4;
};
Node.prototype.hasChildNodes = function () { return this.childNodes.length > 0; };
Node.prototype.getRootNode = function () {
  let n = this;
  while (n.parentNode) n = n.parentNode;
  return n;
};
Node.prototype.normalize = function () {
  let child = this.firstChild;
  while (child) {
    if (child.nodeType === 3) {
      if (child.data === '') {
        const after = child.nextSibling;
        child.remove();
        child = after;
        continue;
      }
      let next = child.nextSibling;
      while (next && next.nodeType === 3) {
        child.data = child.data + next.data;
        const after = next.nextSibling;
        next.remove();
        next = after;
      }
    } else if (child.nodeType === 1 || child.nodeType === 11) {
      child.normalize();
    }
    child = child.nextSibling;
  }
};
Node.prototype.isEqualNode = function (other) {
  if (!other || other.nodeType !== this.nodeType) return false;
  if (this.nodeType === 10) {
    return this.name === other.name && this.publicId === other.publicId && this.systemId === other.systemId;
  }
  if (this.nodeType === 7) {
    return this.target === other.target && this.data === other.data;
  }
  if (this.nodeType === 1) {
    if (this.localName !== other.localName) return false;
    if (this.namespaceURI !== other.namespaceURI) return false;
    if (this.prefix !== other.prefix) return false;
    const a = this.attributes, b = other.attributes;
    if (a.length !== b.length) return false;
    for (const attr of a) {
      if (b.find((x) => x.namespaceURI === attr.namespaceURI && x.localName === attr.localName) === undefined) return false;
      const match = b.find((x) => x.namespaceURI === attr.namespaceURI && x.localName === attr.localName);
      if (match.value !== attr.value) return false;
    }
  } else if (this.nodeType === 3 || this.nodeType === 8) {
    if (this.data !== other.data) return false;
  }
  const ac = this.childNodes, bc = other.childNodes;
  if (ac.length !== bc.length) return false;
  for (let i = 0; i < ac.length; i++) {
    if (!ac[i].isEqualNode(bc[i])) return false;
  }
  return true;
};

// ---- ParentNode / queries --------------------------------------------------
const queries = (proto) => {
  proto.querySelector = function (s) { return wrap(host('q.one', this[ID], String(s))); };
  proto.querySelectorAll = function (s) { return staticNodeList(host('q.all', this[ID], String(s))); };
  proto.getElementsByTagName = function (s) { return htmlCollectionFor(new FilteredTagCollection(this[ID], String(s), false)); };
  proto.getElementsByTagNameNS = function (ns, s) { return htmlCollectionFor(new FilteredTagCollection(this[ID], String(s), true, ns)); };
  proto.getElementsByClassName = function (s) { return htmlCollectionFor(new LiveQueryCollection(this[ID], 'q.class', String(s))); };
  accessor(proto, 'children', live('children'));
  accessor(proto, 'firstElementChild', getNode('firstElementChild'));
  accessor(proto, 'lastElementChild', getNode('lastElementChild'));
  accessor(proto, 'childElementCount', function () { return this.children.length; });
};

class DocumentFragment extends Node {
  constructor() { return document.createDocumentFragment(); }
}
queries(DocumentFragment.prototype);
const byElementId = (root, id) => {
  const key = id === null || id === undefined ? '' : String(id);
  if (key === '') return null;
  return root.querySelector('[id="' + key.replace(/["\\]/g, '\\$&') + '"]');
};
DocumentFragment.prototype.getElementById = function (id) { return byElementId(this, id); };

// A pragmatic shadow-root facade: shadow children live in the host's light
// DOM so the CSS engine and Flutter renderer see them, while the game keeps
// using the standard shadowRoot API. CSS scoping is not emulated.
const shadowRoots = new WeakMap();
class ShadowRoot extends EventTarget {
  constructor(hostElement, mode, delegatesFocus) {
    super();
    hidden(this, '__hostEl', hostElement);
    hidden(this, '__mode', mode);
    hidden(this, '__delegatesFocus', !!delegatesFocus);
  }
  get host() { return this.__hostEl; }
  get mode() { return this.__mode; }
  get delegatesFocus() { return this.__delegatesFocus; }
  get ownerDocument() { return this.__hostEl.ownerDocument; }
  get isConnected() { return this.__hostEl.isConnected; }
  get innerHTML() { return this.__hostEl.innerHTML; }
  set innerHTML(v) { this.__hostEl.innerHTML = v; }
  get textContent() { return this.__hostEl.textContent; }
  set textContent(v) { this.__hostEl.textContent = v; }
  get innerText() { return this.__hostEl.innerText; }
  set innerText(v) { this.__hostEl.innerText = v; }
  get childNodes() { return this.__hostEl.childNodes; }
  get children() { return this.__hostEl.children; }
  get firstChild() { return this.__hostEl.firstChild; }
  get lastChild() { return this.__hostEl.lastChild; }
  get firstElementChild() { return this.__hostEl.firstElementChild; }
  get lastElementChild() { return this.__hostEl.lastElementChild; }
  get childElementCount() { return this.__hostEl.childElementCount; }
  get activeElement() { return this.__hostEl.ownerDocument.activeElement; }
  getRootNode() { return this; }
  appendChild(node) { return this.__hostEl.appendChild(node); }
  insertBefore(node, ref) { return this.__hostEl.insertBefore(node, ref); }
  removeChild(node) { return this.__hostEl.removeChild(node); }
  replaceChild(a, b) { return this.__hostEl.replaceChild(a, b); }
  append(...nodes) { this.__hostEl.append(...nodes); }
  prepend(...nodes) { this.__hostEl.prepend(...nodes); }
  replaceChildren(...nodes) { this.__hostEl.replaceChildren(...nodes); }
  contains(node) { return this.__hostEl.contains(node); }
  querySelector(s) { return this.__hostEl.querySelector(s); }
  querySelectorAll(s) { return this.__hostEl.querySelectorAll(s); }
  getElementsByTagName(s) { return this.__hostEl.getElementsByTagName(s); }
  getElementsByClassName(s) { return this.__hostEl.getElementsByClassName(s); }
  getElementById(id) {
    return this.__hostEl.querySelector('[id="' + String(id).replace(/["\\]/g, '\\$&') + '"]');
  }
  addEventListener(type, cb, options) { return this.__hostEl.addEventListener(type, cb, options); }
  removeEventListener(type, cb, options) { return this.__hostEl.removeEventListener(type, cb, options); }
  dispatchEvent(event) { return this.__hostEl.dispatchEvent(event); }
}
ShadowRoot.prototype[Symbol.toStringTag] = 'ShadowRoot';


// ---- Element -----------------------------------------------------------------
class DOMTokenList {
  constructor(el) { hidden(this, '__el', el); }
  get length() { return host('cl.list', this.__el[ID]).length; }
  get value() { return this.__el.className; }
  item(i) { i = Number(i); const l = host('cl.list', this.__el[ID]); return Number.isInteger(i) && i >= 0 && i < l.length ? l[i] : null; }
  contains(t) { return host('cl.list', this.__el[ID]).includes(String(t)); }
  add(...t) { host('cl.add', this.__el[ID], t.map(String)); }
  remove(...t) { host('cl.remove', this.__el[ID], t.map(String)); }
  toggle(t, force) { return host('cl.toggle', this.__el[ID], String(t), force === undefined ? null : !!force); }
  replace(a, b) { return host('cl.replace', this.__el[ID], String(a), String(b)); }
  supports() { throw new TypeError("DOMTokenList has no supported tokens."); }
  forEach(fn, self) { host('cl.list', this.__el[ID]).forEach((v, i) => fn.call(self, v, i, this)); }
  [Symbol.iterator]() { return host('cl.list', this.__el[ID])[Symbol.iterator](); }
  toString() { return this.value; }
}

const camelToKebab = (s) => s.replace(/[A-Z]/g, (m) => '-' + m.toLowerCase());
class CSSStyleDeclaration {
  getPropertyValue(p) { return host('style.get', this.__el[ID], String(p)); }
  getPropertyPriority(p) { return host('style.priority', this.__el[ID], String(p)); }
  setProperty(p, v, prio = '') { host('style.set', this.__el[ID], String(p), v === null || v === undefined ? '' : String(v), String(prio)); }
  removeProperty(p) { return host('style.remove', this.__el[ID], String(p)); }
  get cssText() { return host('node.get', this.__el[ID], 'styleText'); }
  set cssText(v) { host('style.cssText', this.__el[ID], String(v)); }
  get length() { return host('style.names', this.__el[ID]).length; }
  item(i) { return host('style.names', this.__el[ID])[i] || ''; }
}
const styleFor = (el) => new Proxy(Object.assign(Object.create(CSSStyleDeclaration.prototype), { __el: el }), {
  get(target, prop, recv) {
    if (typeof prop !== 'string' || prop in target) return Reflect.get(target, prop, recv);
    return target.getPropertyValue(camelToKebab(prop));
  },
  set(target, prop, value) {
    if (typeof prop !== 'string' || prop === '__el' || prop === 'cssText') return Reflect.set(target, prop, value);
    target.setProperty(camelToKebab(prop), value);
    return true;
  },
});

const datasetFor = (el) => new Proxy({}, {
  get(_, prop) {
    if (typeof prop !== 'string') return undefined;
    const v = el.getAttribute('data-' + camelToKebab(prop));
    return v === null ? undefined : v;
  },
  set(_, prop, value) { el.setAttribute('data-' + camelToKebab(String(prop)), String(value)); return true; },
  deleteProperty(_, prop) { el.removeAttribute('data-' + camelToKebab(String(prop))); return true; },
  has(_, prop) { return el.hasAttribute('data-' + camelToKebab(String(prop))); },
  ownKeys() {
    return Object.keys(el.attributesObject()).filter((k) => k.startsWith('data-'))
      .map((k) => k.slice(5).replace(/-([a-z])/g, (_, c) => c.toUpperCase()));
  },
  getOwnPropertyDescriptor(_, prop) {
    const v = el.getAttribute('data-' + camelToKebab(String(prop)));
    return v === null ? undefined : { value: v, enumerable: true, configurable: true, writable: true };
  },
});

const styles = new WeakMap();
const datasets = new WeakMap();
const classLists = new WeakMap();
const memo = (map, el, make) => { let v = map.get(el); if (!v) { v = make(el); map.set(el, v); } return v; };

const namespaces = new WeakMap();
const prefixes = new WeakMap();
const localNames = new WeakMap();
const HTML_NS = 'http://www.w3.org/1999/xhtml';
const asciiLower = (s) => String(s).replace(/[A-Z]/g, (c) => c.toLowerCase());
const SVG_NS = 'http://www.w3.org/2000/svg';
const MATHML_NS = 'http://www.w3.org/1998/Math/MathML';
const nsOf = (el) => {
  if (namespaces.has(el)) return namespaces.get(el);
  const name = host('node.get', el[ID], 'localName');
  if (name === 'svg' || (el.closest && el.closest('svg'))) return SVG_NS;
  if (name === 'math' || (el.closest && el.closest('math'))) return MATHML_NS;
  return HTML_NS;
};
const localOf = (el) => localNames.has(el) ? localNames.get(el) : host('node.get', el[ID], 'localName');
const prefixOf = (el) => prefixes.has(el) ? prefixes.get(el) : null;
const localNameOf = (name) => String(name).includes(':') ? String(name).split(':').pop() : String(name);
const attrToken = Symbol('nativax.attr');
class Attr {
  constructor(token, element, name, value, namespaceURI = null, prefix = null, localName = null) {
    if (token !== attrToken) throw new TypeError('Illegal constructor');
    hidden(this, '__el', element || null);
    hidden(this, '__name', String(name));
    defineProperty(this, '__value', { value: value == null ? '' : String(value), writable: true, enumerable: false, configurable: true });
    hidden(this, '__ns', namespaceURI == null ? null : String(namespaceURI));
    hidden(this, '__prefix', prefix == null ? null : String(prefix));
    hidden(this, '__local', localName == null ? (String(name).includes(':') ? String(name).split(':').pop() : String(name)) : String(localName));
  }
  get nodeType() { return 2; }
  get nodeName() { return this.__name; }
  get name() { return this.__name; }
  get localName() { return this.__local; }
  get prefix() { return this.__prefix; }
  get namespaceURI() { return this.__ns; }
  get specified() { return true; }
  get ownerDocument() { return document; }
  get baseURI() { return document.baseURI; }
  get ownerElement() { return this.__el; }
  get value() { return this.__el ? (this.__el.getAttribute(this.__name) ?? this.__value) : this.__value; }
  set value(v) { this.__value = v == null ? '' : String(v); if (this.__el) this.__el.setAttribute(this.__name, this.__value); }
  get nodeValue() { return this.value; }
  set nodeValue(v) { this.value = v; }
  get textContent() { return this.value; }
  set textContent(v) { this.value = v; }
  isSameNode(other) { return this === other; }
  cloneNode() { return new Attr(attrToken, null, this.__name, this.value, this.__ns, this.__prefix, this.__local); }
  toString() { return this.value; }
}
Attr.prototype[Symbol.toStringTag] = 'Attr';
const attrFor = (el, name, value, ns = null, prefix = null, localName = null) =>
  new Attr(attrToken, el, name, value, ns, prefix, localName);
const XLINK_NS = 'http://www.w3.org/1999/xlink';
const XML_NS = 'http://www.w3.org/XML/1998/namespace';
const attrsFor = (el) => {
  const entries = host('attr.entries', el[ID]);
  const ns = nsOf(el);
  const arr = entries.map((a) => {
    let an = a.namespaceURI, prefix = a.prefix, local = a.localName;
    if (an == null && a.name === 'xlink:href' && ns === SVG_NS) {
      an = XLINK_NS; prefix = 'xlink'; local = 'href';
    } else if (an == null && a.name === 'xml:lang' && ns !== HTML_NS) {
      an = XML_NS; prefix = 'xml'; local = 'lang';
    }
    return attrFor(el, a.name, a.value, an, prefix, local);
  });
  defineProperty(arr, 'item', { value: (i) => arr[i] || null, enumerable: false });
  defineProperty(arr, 'getNamedItem', { value: (n) => arr.find((a) => a.name === String(n)) || null, enumerable: false });
  defineProperty(arr, 'getNamedItemNS', { value: (ns, n) => arr.find((a) => a.namespaceURI === (ns == null || ns === '' ? null : String(ns)) && a.localName === (ns == null || ns === '' ? String(n) : String(n).split(':').pop())) || null, enumerable: false });
  defineProperty(arr, 'setNamedItem', { value: (a) => setAttributeNode(el, a), enumerable: false });
  defineProperty(arr, 'removeNamedItem', { value: (n) => removeAttributeNode(el, arr.find((a) => a.name === String(n))), enumerable: false });
  for (const a of arr) defineProperty(arr, a.name, { value: a, enumerable: false, configurable: true });
  return arr;
};
const setAttributeNode = (el, attr) => {
  if (!(attr instanceof Attr)) throw new TypeError('parameter is not an Attr');
  if (attr.ownerElement && attr.ownerElement !== el) throw new DOMException('The attribute is in use.', 'InUseAttributeError');
  const old = attr.namespaceURI != null
    ? el.getAttributeNodeNS(attr.namespaceURI, attr.localName)
    : el.getAttributeNode(attr.name);
  if (attr.namespaceURI != null) {
    el.setAttributeNS(attr.namespaceURI, attr.name, attr.value);
  } else {
    el.setAttribute(attr.name, attr.value);
  }
  hidden(attr, '__el', el);
  return old;
};
const removeAttributeNode = (el, attr) => {
  if (!(attr instanceof Attr) || attr.ownerElement !== el) throw new DOMException('The attribute is not owned by this element.', 'NotFoundError');
  if (attr.namespaceURI != null) el.removeAttributeNS(attr.namespaceURI, attr.localName);
  else el.removeAttribute(attr.name);
  hidden(attr, '__el', null);
  return attr;
};

class Element extends Node {
  get namespaceURI() { return namespaces.get(this) || (this.ownerDocument === document ? 'http://www.w3.org/1999/xhtml' : null); }
  get prefix() { const n = this.localName; return n.includes(':') ? n.split(':')[0] : null; }
  getAttribute(n) { return host('attr.get', this[ID], String(n)); }
  setAttribute(n, v) {
    host('attr.set', this[ID], String(n), String(v));
    const attrName = String(n).toLowerCase();
    if (/^on[a-z]+$/.test(attrName)) {
      try {
        const fn = new Function('event', 'with(this){' + String(v) + '\n}');
        this[attrName] = fn;
      } catch (_) {}
    }
    if (this.localName === 'iframe' && (String(n) === 'src' || String(n) === 'srcdoc')) {
      queueMicrotask(() => { try { if (this.isConnected) this.dispatchEvent(new Event('load')); } catch (e) {} });
    }
  }
  removeAttribute(n) { host('attr.remove', this[ID], String(n)); }
  hasAttribute(n) { return host('attr.get', this[ID], String(n)) !== null; }
  toggleAttribute(n, force) { return host('attr.toggle', this[ID], String(n), force === undefined ? null : !!force); }
  getAttributeNames() { return Object.keys(this.attributesObject()); }
  hasAttributes() { return this.getAttributeNames().length > 0; }
  getAttributeNS(ns, name) { return this.getAttribute(localNameOf(name)); }
  setAttributeNS(ns, name, value) { host('attr.setNS', this[ID], ns == null ? null : String(ns), String(name), String(value)); }
  removeAttributeNS(ns, name) { host('attr.removeNS', this[ID], ns == null ? null : String(ns), String(name)); }
  getAttributeNS(ns, name) { return host('attr.getNS', this[ID], ns == null ? null : String(ns), String(name)); }
  hasAttributeNS(ns, name) { return this.hasAttribute(localNameOf(name)); }
  insertAdjacentElement(position, element) {
    if (!(element instanceof Element)) throw new TypeError('parameter is not an Element');
    const p = this.parentNode;
    switch (String(position).toLowerCase()) {
      case 'beforebegin': if (!p) return null; p.insertBefore(element, this); break;
      case 'afterbegin': this.insertBefore(element, this.firstChild); break;
      case 'beforeend': this.appendChild(element); break;
      case 'afterend': if (!p) return null; p.insertBefore(element, this.nextSibling); break;
      default: throw new DOMException('invalid position', 'SyntaxError');
    }
    return element;
  }
  insertAdjacentText(position, text) {
    const node = document.createTextNode(domString(text));
    const p = this.parentNode;
    switch (String(position).toLowerCase()) {
      case 'beforebegin':
        if (!p) throw new DOMException('element has no parent', 'NoModificationAllowedError');
        p.insertBefore(node, this); break;
      case 'afterbegin': this.insertBefore(node, this.firstChild); break;
      case 'beforeend': this.appendChild(node); break;
      case 'afterend':
        if (!p) throw new DOMException('element has no parent', 'NoModificationAllowedError');
        p.insertBefore(node, this.nextSibling); break;
      default: throw new DOMException('invalid position', 'SyntaxError');
    }
  }
  attributesObject() { return host('node.get', this[ID], 'attributes'); }
  matches(s) { return host('q.matches', this[ID], String(s)); }
  closest(s) { return wrap(host('q.closest', this[ID], String(s))); }
  focus() { host('el.focus', this[ID]); }
  blur() { host('el.blur', this[ID]); }
  click() { host('el.click', this[ID]); }
  before(...nodes) { return NP.before.apply(this, nodes); }
  after(...nodes) { return NP.after.apply(this, nodes); }
  replaceWith(...nodes) { return NP.replaceWith.apply(this, nodes); }
  insertAdjacentHTML(pos, html) { host('el.insertAdjacentHTML', this[ID], String(pos), String(html)); }
  get style() { return memo(styles, this, styleFor); }
  set style(v) { this.style.cssText = v; }
  get dataset() { return memo(datasets, this, datasetFor); }
  get classList() {
    return memo(classLists, this, (e) => new Proxy(new DOMTokenList(e), {
      get(t, p, r) {
        if (typeof p === 'string' && /^\d+$/.test(p)) { const v = t.item(Number(p)); return v === null ? undefined : v; }
        return Reflect.get(t, p, r);
      },
    }));
  }
  set classList(_) {}
  get attributes() { return attrsFor(this); }
  getAttributeNode(n) { return this.attributes.getNamedItem(n); }
  getAttributeNodeNS(ns, n) { return this.attributes.getNamedItemNS(ns, n); }
  setAttributeNode(a) { return setAttributeNode(this, a); }
  setAttributeNodeNS(a) { return setAttributeNode(this, a); }
  removeAttributeNode(a) { return removeAttributeNode(this, a); }
}
const EP = Element.prototype;
queries(EP);
EP.getElementById = function (id) { return byElementId(this, id); };
accessor(EP, 'tagName', function () {
  const local = localOf(this), prefix = prefixOf(this), ns = nsOf(this);
  const doc = this.ownerDocument;
  const htmlDoc = !doc || doc.contentType === 'text/html';
  if (ns === HTML_NS && htmlDoc) return (prefix ? prefix.toUpperCase() + ':' : '') + local.toUpperCase();
  return (prefix ? prefix + ':' : '') + local;
});
accessor(EP, 'localName', function () { return localOf(this); });
accessor(EP, 'prefix', function () { return prefixOf(this); });
accessor(EP, 'namespaceURI', function () { return nsOf(this); });
accessor(EP, 'nextElementSibling', getNode('nextElementSibling'));
accessor(EP, 'previousElementSibling', getNode('previousElementSibling'));
accessor(EP, 'innerHTML', get('innerHTML'), function (v) { host('node.set', this[ID], 'innerHTML', String(v)); });
accessor(EP, 'outerHTML', get('outerHTML'), function (v) { host('el.outerHTML', this[ID], String(v)); });
accessor(EP, 'innerText', get('textContent'), function (v) { this.textContent = v; });
for (const p of ['value', 'checked', 'selectedIndex']) {
  accessor(EP, p, get(p), function (v) { host('node.set', this[ID], p, v); });
}
accessor(EP, 'selectedOptions', function () { const o = getNode('selectedOption').call(this); return o ? [o] : []; });
accessor(EP, 'options', getNodes('options'));
// Reflected string attributes.
for (const [prop, attr] of [['id', 'id'], ['className', 'class'], ['src', 'src'], ['href', 'href'],
  ['alt', 'alt'], ['type', 'type'], ['name', 'name'], ['placeholder', 'placeholder'], ['title', 'title'],
  ['lang', 'lang'], ['dir', 'dir'], ['htmlFor', 'for'], ['rel', 'rel'], ['target', 'target'],
  ['action', 'action'], ['method', 'method']]) {
  accessor(EP, prop, function () { const v = this.getAttribute(attr); return v === null ? '' : v; },
    function (v) { this.setAttribute(attr, v); });
}
// Reflected boolean attributes.
for (const attr of ['disabled', 'hidden', 'required', 'readOnly', 'multiple', 'autofocus']) {
  const name = attr.toLowerCase();
  accessor(EP, attr, function () { return this.hasAttribute(name); },
    function (v) { this.toggleAttribute(name, !!v); });
}
globalThis.HTMLElement = Element;
if (Symbol.unscopables) {
  Element.prototype[Symbol.unscopables] = { before: true, after: true, replaceWith: true, remove: true, prepend: true, append: true };
}

// ---- Document ----------------------------------------------------------------
const docMeta = new WeakMap();
const newDocument = (contentType = 'application/xml') => {
  const d = wrap(host('doc.new'));
  docMeta.set(d, { type: contentType, url: 'about:blank' });
  return d;
};
class Document extends Node {
  constructor() { return newDocument('application/xml'); }
  createElement(n) {
    const name = String(n);
    const el = wrap(host('doc.createElement', this[ID], name));
    if (this.contentType !== 'text/html') {
      Object.setPrototypeOf(el, Element.prototype);
      localNames.set(el, name);
      namespaces.set(el, this.contentType === 'application/xhtml+xml' ? HTML_NS : this.contentType === 'image/svg+xml' ? SVG_NS : null);
    }
    return el;
  }
  createElementNS(ns, n) {
    const name = String(n);
    const prefix = name.includes(':') ? name.split(':')[0] : null;
    const local = name.includes(':') ? name.split(':').pop() : name;
    const el = this.createElement(local);
    const namespace = ns === null || ns === undefined || ns === '' ? null : String(ns);
    namespaces.set(el, namespace);
    prefixes.set(el, prefix);
    localNames.set(el, local);
    if (namespace === HTML_NS) {
      if (local !== local.toLowerCase()) {
        if (globalThis.HTMLUnknownElement) Object.setPrototypeOf(el, globalThis.HTMLUnknownElement.prototype);
      } else if (typeof elementProtos !== 'undefined' && elementProtos[local]) {
        Object.setPrototypeOf(el, elementProtos[local]);
      }
    } else if (namespace === SVG_NS) {
      if (globalThis.SVGElement) Object.setPrototypeOf(el, globalThis.SVGElement.prototype);
    } else {
      Object.setPrototypeOf(el, Element.prototype);
    }
    return el;
  }
  createTextNode(t) { return wrap(host('doc.createText', this[ID], domString(t))); }
  createComment(t) { return wrap(host('doc.createComment', this[ID], domString(t))); }
  createProcessingInstruction(target, data) {
    const t = String(target), d = domString(data);
    const start = /^[:A-Z_a-z\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u02FF\u0370-\u037D\u037F-\u1FFF\u200C-\u200D\u2070-\u218F\u2C00-\u2FEF\u3001-\uD7FF\uF900-\uFDCF\uFDF0-\uFFFD]/;
    const rest = /^[:A-Z_a-z\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u02FF\u0370-\u037D\u037F-\u1FFF\u200C-\u200D\u2070-\u218F\u2C00-\u2FEF\u3001-\uD7FF\uF900-\uFDCF\uFDF0-\uFFFD\-.0-9\u00B7\u0300-\u036F\u203F-\u2040]*$/;
    if (!start.test(t) || !rest.test(t) || d.includes('?>')) {
      throw new DOMException('Invalid character', 'InvalidCharacterError');
    }
    return wrap(host('doc.createPI', this[ID], t, d));
  }
  createDocumentFragment() { return wrap(host('doc.createFragment', this[ID])); }
  createCDATASection(data) {
    if (this.contentType === 'text/html') {
      throw new DOMException('CDATA sections are not supported in HTML documents.', 'NotSupportedError');
    }
    const t = this.createTextNode(String(data));
    Object.setPrototypeOf(t, CDATASection.prototype);
    return t;
  }
  createAttribute(name) {
    let n = String(name);
    if (!n) throw new DOMException('Invalid character', 'InvalidCharacterError');
    if (this.contentType === 'text/html') n = n.toLowerCase();
    return attrFor(null, n, '', null, null, n);
  }
  createAttributeNS(ns, name) {
    const n = String(name);
    if (!n || /[\s"'<>\/]/.test(n)) throw new DOMException('Invalid character', 'InvalidCharacterError');
    return attrFor(null, n, '', ns, n.includes(':') ? n.split(':')[0] : null, n.includes(':') ? n.split(':').pop() : n);
  }
  getElementById(id) {
    return wrap(host('doc.byId', this[ID], String(id)));
  }
  getElementsByName(name) { return this.querySelectorAll('[name="' + String(name).replace(/"/g, '\\"') + '"]'); }
  importNode(node, deep = false) {
    const c = node.cloneNode(!!deep);
    if (c instanceof Element) {
      namespaces.set(c, node.namespaceURI);
      prefixes.set(c, node.prefix);
      localNames.set(c, node.localName);
    }
    if (c instanceof Node) {
      const frag = this.createDocumentFragment();
      frag.appendChild(c);
      frag.removeChild(c);
    }
    return c;
  }
  adoptNode(node) { return node; }
  createEvent() { return new Event(''); }
  get URL() { return docMeta.get(this)?.url || 'about:blank'; }
  get documentURI() { return this.URL; }
  get compatMode() { return 'CSS1Compat'; }
  get contentType() { return docMeta.get(this)?.type || 'text/html'; }
  get characterSet() { return 'UTF-8'; }
  get charset() { return 'UTF-8'; }
  get inputEncoding() { return 'UTF-8'; }
  get implementation() { return implementationFor(this); }
  get doctype() { return wrap(host('doc.get', this[ID], 'doctype')); }
  cloneNode(deep = false) {
    const c = wrap(host('node.clone', this[ID], !!deep));
    Object.setPrototypeOf(c, Object.getPrototypeOf(this));
    return c;
  }
}
class XMLDocument extends Document {}
class HTMLDocument extends Document {}
class DOMImplementation {
  constructor(doc) { hidden(this, '__doc', doc || null); }
  hasFeature() { return true; }
  createDocumentType(name, publicId = '', systemId = '') {
    const d = this.__doc || document;
    return wrap(host('doc.createDoctype', d[ID], String(name), String(publicId), String(systemId)));
  }
  createDocument(ns, qualifiedName = '', doctype = null) {
    const type = ns === HTML_NS ? 'application/xhtml+xml' : ns === SVG_NS ? 'image/svg+xml' : 'application/xml';
    const doc = newDocument(type);
    Object.setPrototypeOf(doc, XMLDocument.prototype);
    if (doctype) doc.appendChild(doctype);
    if (qualifiedName) doc.appendChild(doc.createElementNS(ns, String(qualifiedName)));
    return doc;
  }
  createHTMLDocument(title) {
    const doc = newDocument('text/html');
    doc.appendChild(wrap(host('doc.createDoctype', doc[ID], 'html', '', '')));
    const html = doc.createElement('html');
    doc.appendChild(html);
    const head = doc.createElement('head');
    html.appendChild(head);
    if (title !== undefined) {
      const t = doc.createElement('title');
      t.appendChild(doc.createTextNode(String(title)));
      head.appendChild(t);
    }
    html.appendChild(doc.createElement('body'));
    return doc;
  }
}
const implementations = new WeakMap();
const implementationFor = (doc) => {
  let impl = implementations.get(doc);
  if (!impl) { impl = new DOMImplementation(doc); implementations.set(doc, impl); }
  return impl;
};

// Minimal same-process iframe documents. NativaX does not run nested browsing
// contexts; this preserves the DOM surface (`contentDocument`, `contentWindow`,
// `frames`) and infers the document type from the URL.
const frameDocs = new WeakMap();
const frameWindows = new WeakMap();
const frameWindowByDoc = new WeakMap();
const inferDocumentType = (src) => {
  const s = String(src || '');
  if (s.startsWith('data:')) {
    const m = /^data:([^;,]+)/i.exec(s);
    return m ? m[1].toLowerCase() : 'text/plain';
  }
  if (s.startsWith('javascript:')) return 'text/html';
  const raw = s.split(/[?#]/)[0].toLowerCase();
  const qm = /[?&]type=([^&]+)/.exec(s), sm = /[?&]subtype=([^&]+)/.exec(s);
  if (qm && sm) return decodeURIComponent(qm[1]).toLowerCase() + '/' + decodeURIComponent(sm[1]).toLowerCase();
  if (raw.endsWith('.css')) return 'text/css';
  if (raw.endsWith('.gif')) return 'image/gif';
  if (raw.endsWith('.png')) return 'image/png';
  if (raw.endsWith('.jpg') || raw.endsWith('.jpeg')) return 'image/jpeg';
  if (raw.endsWith('.bmp')) return 'image/bmp';
  if (raw.endsWith('.xml')) return 'application/xml';
  if (raw.endsWith('.txt')) return 'text/plain';
  if (raw.endsWith('.html')) return 'text/html';
  try {
    const u = new URL(s, document.baseURI);
    const q = /[?&]type=([^&]+)/.exec(u.search);
    const sub = /[?&]subtype=([^&]+)/.exec(u.search);
    if (q && sub) return String(q[1]).toLowerCase() + '/' + String(sub[1]).toLowerCase();
    const path = u.pathname.toLowerCase();
    if (path.endsWith('.css')) return 'text/css';
    if (path.endsWith('.gif')) return 'image/gif';
    if (path.endsWith('.png')) return 'image/png';
    if (path.endsWith('.jpg') || path.endsWith('.jpeg')) return 'image/jpeg';
    if (path.endsWith('.bmp')) return 'image/bmp';
    if (path.endsWith('.xml')) return 'application/xml';
    if (path.endsWith('.txt')) return 'text/plain';
    if (path.endsWith('.html') || path.endsWith('/')) return 'text/html';
  } catch (e) {}
  return 'text/html';
};
const buildFrameDocument = (frame, type) => {
  const doc = newDocument(type);
  if (type === 'text/html') {
    doc.appendChild(wrap(host('doc.createDoctype', doc[ID], 'html', '', '')));
    const html = doc.createElement('html');
    doc.appendChild(html);
    const head = doc.createElement('head');
    html.appendChild(head);
    const body = doc.createElement('body');
    html.appendChild(body);
    const src = frame.getAttribute('src') || '';
    if (src.startsWith('javascript:')) body.textContent = 'text/html';
  }
  return doc;
};
const frameDocumentFor = (frame) => {
  let doc = frameDocs.get(frame);
  if (!doc) {
    doc = buildFrameDocument(frame, inferDocumentType(frame.getAttribute('src') || ''));
    frameDocs.set(frame, doc);
  }
  return doc;
};
const frameWindowFor = (frame) => {
  let win = frameWindows.get(frame);
  if (!win) {
    const doc = frameDocumentFor(frame);
    win = {
      document: doc, parent: globalThis, top: globalThis, frameElement: frame,
      window: null, self: null, closed: false,
      Document, XMLDocument, HTMLDocument, DOMImplementation, Node, Element, Text,
      Comment, ProcessingInstruction, DocumentFragment, Attr, DOMException, customElements,
      postMessage(message, targetOrigin) { globalThis.dispatchMessage && globalThis.dispatchMessage(message, targetOrigin); },
      addEventListener: (t, f) => frame.addEventListener(t, f),
      removeEventListener: (t, f) => frame.removeEventListener(t, f),
      dispatchEvent: (e) => frame.dispatchEvent(e),
    };
    win.window = win; win.self = win;
    frameWindowByDoc.set(doc, win);
    frameWindows.set(frame, win);
  }
  return win;
};
accessor(EP, 'contentDocument', function () {
  return this.localName === 'iframe' ? frameDocumentFor(this) : null;
});
accessor(EP, 'contentWindow', function () {
  return this.localName === 'iframe' ? frameWindowFor(this) : null;
});

const DP = Document.prototype;
queries(DP);
accessor(DP, 'documentElement', function () { return wrap(host('doc.get', this[ID], 'documentElement')); });
accessor(DP, 'head', function () { return wrap(host('doc.get', this[ID], 'head')); });
accessor(DP, 'body', function () { return wrap(host('doc.get', this[ID], 'body')); });
accessor(DP, 'activeElement', function () { return wrap(host('doc.get', this[ID], 'activeElement')); });
accessor(DP, 'title', function () { return host('doc.get', this[ID], 'title'); },
  function (v) { host('doc.setTitle', this[ID], String(v)); });
accessor(DP, 'readyState', function () { return host('doc.get', this[ID], 'readyState'); });

// ---- URL / URLSearchParams -------------------------------------------------
const urlEncode = (s) => encodeURIComponent(String(s)).replace(/%20/g, '+');
const urlDecode = (s) => {
  try { return decodeURIComponent(String(s).replace(/\+/g, ' ')); } catch (e) { return String(s); }
};
class URLSearchParams {
  constructor(init = '') {
    this._pairs = [];
    if (typeof init === 'string') {
      const text = init.startsWith('?') ? init.slice(1) : init;
      if (text) {
        for (const part of text.split('&')) {
          if (!part) continue;
          const eq = part.indexOf('=');
          const k = eq < 0 ? part : part.slice(0, eq);
          const v = eq < 0 ? '' : part.slice(eq + 1);
          this._pairs.push([urlDecode(k), urlDecode(v)]);
        }
      }
    } else if (init && typeof init[Symbol.iterator] === 'function') {
      for (const [k, v] of init) this._pairs.push([String(k), String(v)]);
    } else if (init && typeof init === 'object') {
      for (const k of Object.keys(init)) this._pairs.push([k, String(init[k])]);
    }
  }
  get size() { return this._pairs.length; }
  append(k, v) { this._pairs.push([String(k), String(v)]); }
  delete(k) { k = String(k); this._pairs = this._pairs.filter((p) => p[0] !== k); }
  get(k) { k = String(k); const p = this._pairs.find((x) => x[0] === k); return p ? p[1] : null; }
  getAll(k) { k = String(k); return this._pairs.filter((x) => x[0] === k).map((x) => x[1]); }
  has(k) { k = String(k); return this._pairs.some((x) => x[0] === k); }
  set(k, v) {
    k = String(k);
    const i = this._pairs.findIndex((x) => x[0] === k);
    if (i < 0) this._pairs.push([k, String(v)]);
    else { this._pairs[i][1] = String(v); this._pairs = this._pairs.filter((x, j) => j <= i || x[0] !== k); }
  }
  sort() { this._pairs.sort((a, b) => a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0); }
  forEach(fn, self) { for (const [k, v] of this._pairs) fn.call(self, v, k, this); }
  *keys() { for (const p of this._pairs) yield p[0]; }
  *values() { for (const p of this._pairs) yield p[1]; }
  *entries() { for (const p of this._pairs) yield [p[0], p[1]]; }
  [Symbol.iterator]() { return this.entries(); }
  toString() { return this._pairs.map(([k, v]) => urlEncode(k) + '=' + urlEncode(v)).join('&'); }
}
class URL {
  constructor(url, base) {
    const parsed = host('url.parse', String(url), base === null || base === undefined ? null : String(base));
    if (!parsed) throw new TypeError('Invalid URL');
    hidden(this, '__p', parsed);
  }
  get href() { return this.__p.href; }
  set href(v) { const p = host('url.parse', String(v), null); if (!p) throw new TypeError('Invalid URL'); this.__p = p; }
  get origin() { return this.__p.origin; }
  get protocol() { return this.__p.protocol; }
  get username() { return this.__p.username; }
  get password() { return this.__p.password; }
  get host() { return this.__p.host; }
  get hostname() { return this.__p.hostname; }
  get port() { return this.__p.port; }
  get pathname() { return this.__p.pathname; }
  get search() { return this.__p.search; }
  get hash() { return this.__p.hash; }
  get searchParams() {
    if (!this.__sp) {
      const sp = new URLSearchParams(this.search);
      Object.defineProperty(this, '__sp', { value: sp, configurable: true });
    }
    return this.__sp;
  }
  toString() { return this.href; }
  toJSON() { return this.href; }
  static canParse(url, base) {
    try { new URL(url, base); return true; } catch (e) { return false; }
  }
  static parse(url, base) {
    try { return new URL(url, base); } catch (e) { return null; }
  }
}
globalThis.URL = URL;
globalThis.URLSearchParams = URLSearchParams;

// ---- window, navigator, matchMedia, storage, nativax -------------------------
class Window extends EventTarget {}
const win = wrap(host('win.desc'));
const document = wrap(host('doc.desc'));

const env = () => host('env.get');
const mqls = new Set();
class MediaQueryList extends EventTarget {}
const matchMedia = (q) => {
  const query = String(q);
  const target = wrap(host('mql.create', query));
  defineProperty(target, 'media', { value: query, enumerable: true });
  defineProperty(target, 'matches', { get() { return host('mql.matches', query); }, enumerable: true });
  target.addListener = (fn) => target.addEventListener('change', fn);
  target.removeListener = (fn) => target.removeEventListener('change', fn);
  return target;
};

const navigator = {
  get language() { return env().languages[0] || 'en-US'; },
  get languages() { return Object.freeze(env().languages.slice()); },
  get platform() { return env().platform; },
  userAgent: 'NativaX/0.1 (QuickJS-ng)',
  onLine: true,
};

const makeStorage = () => {
  if (!host('storage.available')) return undefined;
  const api = {
    getItem: (k) => host('storage.get', String(k)),
    setItem: (k, v) => { host('storage.set', String(k), String(v)); },
    removeItem: (k) => { host('storage.remove', String(k)); },
    clear: () => { host('storage.clear'); },
    key: (i) => host('storage.keys')[i] ?? null,
    get length() { return host('storage.keys').length; },
  };
  return new Proxy(api, {
    get(t, p) { if (typeof p !== 'string' || p in t) return t[p]; const v = t.getItem(p); return v === null ? undefined : v; },
    set(t, p, v) { t.setItem(p, v); return true; },
    deleteProperty(t, p) { t.removeItem(p); return true; },
    ownKeys() { return host('storage.keys'); },
    getOwnPropertyDescriptor(t, p) {
      const v = t.getItem(String(p));
      return v === null ? undefined : { value: v, enumerable: true, configurable: true };
    },
  });
};
const localStorage = makeStorage();

const nativaxListeners = new Map();
const nativax = Object.freeze({
  version: '0.1.0',
  get platform() { return env().platform; },
  theme: Object.freeze({
    get brightness() { return host('theme.get').brightness; },
    get colors() { return Object.freeze(host('theme.get').colors); },
    setMode(mode) { return host('theme.setMode', String(mode)); },
  }),
  // Calls a handler registered by the Dart app; arguments and result are JSON.
  invoke(name, ...args) { return host('app.invoke', String(name), args); },
  addEventListener(type, fn) { win.addEventListener('nativax:' + type, fn); },
  removeEventListener(type, fn) { win.removeEventListener('nativax:' + type, fn); },
});

''' +
    webPlatformPrelude +
    r'''
if (workerScope) {
  // ---- dedicated worker global scope (HTML §10.2) ---------------------------
  for (const [name, value] of Object.entries({ Event, CustomEvent, EventTarget, DOMException })) hidden(globalThis, name, value);
  // Window-only members do not exist in workers.
  for (const name of ['history', 'localStorage', 'sessionStorage', 'alert', 'confirm', 'prompt', 'print', 'open', 'scrollTo',
    'scroll', 'scrollBy', 'screen', 'visualViewport', 'getComputedStyle', 'customElements', 'Image', 'Audio', 'Option',
    'DOMParser', 'XMLSerializer', 'Range', 'TreeWalker', 'NodeIterator', 'MutationObserver', 'ResizeObserver',
    'IntersectionObserver', 'scrollX', 'scrollY', 'pageXOffset', 'pageYOffset', 'outerWidth', 'outerHeight', 'screenX',
    'screenY', 'screenLeft', 'screenTop', 'frames', 'parent', 'top', 'opener', 'frameElement', 'length', 'closed',
    'status', 'event', 'innerWidth', 'innerHeight', 'devicePixelRatio', 'postMessage', 'name']) {
    try { delete globalThis[name]; } catch (_) {}
  }
  class WorkerGlobalScope extends EventTarget {}
  class DedicatedWorkerGlobalScope extends WorkerGlobalScope {}
  class WorkerLocation {
    get href() { return document.URL; }
    get origin() { return originOf(new URL(document.URL)); }
    get protocol() { return new URL(document.URL).protocol; }
    get host() { return new URL(document.URL).host; }
    get hostname() { return new URL(document.URL).hostname; }
    get port() { return new URL(document.URL).port; }
    get pathname() { return new URL(document.URL).pathname; }
    get search() { return new URL(document.URL).search; }
    get hash() { return new URL(document.URL).hash; }
    toString() { return this.href; }
  }
  for (const [name, value] of Object.entries({ WorkerGlobalScope, DedicatedWorkerGlobalScope, WorkerLocation })) hidden(globalThis, name, value);
  Object.setPrototypeOf(globalThis, DedicatedWorkerGlobalScope.prototype);
  hidden(globalThis, ID, win[ID]);
  const port = adoptPort(workerScope.port);
  port.addEventListener('message', (e) => globalThis.dispatchEvent(new MessageEvent('message', { data: e.data, ports: e.ports })));
  port.addEventListener('messageerror', () => globalThis.dispatchEvent(new MessageEvent('messageerror')));
  port.start();
  const workerLocation = new WorkerLocation();
  for (const [name, value] of Object.entries({
    self: globalThis, globalThis, navigator, location: workerLocation, name: workerScope.name,
    postMessage(message, transfer) { port.postMessage(message, Array.isArray(transfer) ? transfer : (transfer && transfer.transfer ? [...transfer.transfer] : [])); },
    close() { port.close(); host('worker.selfClose'); },
    importScripts(...urls) {
      if (workerScope.type === 'module') throw new TypeError("Module scripts don't support importScripts().");
      for (const u of urls) {
        const href = new URL(String(u), document.URL).href;
        const code = host('worker.importScript', href);
        if (code === null || code === undefined) throw new DOMException(`Failed to execute 'importScripts': The script at '${href}' failed to load.`, 'NetworkError');
        (0, eval)(code);
      }
    },
  })) defineProperty(globalThis, name, { value, enumerable: true, configurable: true, writable: true });
  for (const t of ['message', 'messageerror', 'error', 'unhandledrejection', 'rejectionhandled']) {
    let handler = null;
    defineProperty(globalThis, 'on' + t, {
      get() { return handler; },
      set(fn) {
        if (handler) globalThis.removeEventListener(t, handler);
        handler = typeof fn === 'function' ? fn : null;
        if (handler) globalThis.addEventListener(t, handler);
      },
      enumerable: true, configurable: true,
    });
  }
} else {
for (const [name, value] of Object.entries({
  Event, CustomEvent, EventTarget, Node, CharacterData, Text, Comment, ProcessingInstruction, DocumentType, Element, DocumentFragment,
  Document, XMLDocument, HTMLDocument, DOMImplementation, Attr, CDATASection, DOMTokenList, CSSStyleDeclaration, NodeList, HTMLCollection, Window, MediaQueryList, DOMException,
})) hidden(globalThis, name, value);

Object.setPrototypeOf(globalThis, Window.prototype);
hidden(globalThis, ID, win[ID]);
for (const [name, value] of Object.entries({
  window: globalThis, self: globalThis, globalThis, document, navigator, matchMedia, nativax,
})) defineProperty(globalThis, name, { value, enumerable: true, configurable: false, writable: false });
if (localStorage) defineProperty(globalThis, 'localStorage', { value: localStorage, enumerable: true });
defineProperty(globalThis, 'innerWidth', { get() { return env().width; }, enumerable: true });
defineProperty(globalThis, 'innerHeight', { get() { return env().height; }, enumerable: true });
defineProperty(globalThis, 'devicePixelRatio', { get() { return env().dpr; }, enumerable: true });
}
// Caches are keyed by id; the Window wrapper is globalThis itself.
cache.set(win[ID], new WeakRef(globalThis));
})();
''';
