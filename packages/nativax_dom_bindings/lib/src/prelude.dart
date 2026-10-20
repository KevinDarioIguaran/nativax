/// Script-side half of the DOM bindings. Wrappers hold only a numeric id;
/// every property access goes through `__nx.host`, so scripts never see Dart
/// objects. Installed once per runtime, before any document script.
const String domPrelude = r'''
(() => {
'use strict';
const host = __nx.host;
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

const protoFor = (t, n) => {
  if (t === 1) return Element.prototype;
  if (t === 3) return Text.prototype;
  if (t === 8) return Comment.prototype;
  if (t === 9) return Document.prototype;
  if (t === 11) return DocumentFragment.prototype;
  if (t === 0) return Window.prototype;
  return Node.prototype;
};

// desc: null | [id, nodeType, localName]
const wrap = (desc) => {
  if (desc === null || desc === undefined) return null;
  const id = desc[0];
  const ref = cache.get(id);
  let w = ref && ref.deref();
  if (w) return w;
  w = Object.create(protoFor(desc[1], desc[2]));
  hidden(w, ID, id);
  cache.set(id, new WeakRef(w));
  finalizer.register(w, id);
  return w;
};
const wrapAll = (descs) => descs.map(wrap);
const idOf = (node, what = 'node') => {
  const id = node !== null && typeof node === 'object' ? node[ID] : undefined;
  if (id === undefined) throw new TypeError(`parameter is not a ${what}`);
  return id;
};
const nodeArg = (n) => (typeof n === 'string' ? document.createTextNode(n) : n);

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
const eventFor = (desc) => {
  let ev = events.get(desc.id);
  if (!ev) {
    ev = Object.create(Event.prototype);
    hidden(ev, '__id', desc.id);
    hidden(ev, '__desc', desc);
    for (const k of Object.keys(desc.detail || {})) hidden(ev, k, desc.detail[k]);
    events.set(desc.id, ev);
  }
  return ev;
};

const invoke = (cb, self, ev) => {
  if (typeof cb === 'function') cb.call(self, ev);
  else if (cb && typeof cb.handleEvent === 'function') cb.handleEvent(ev);
};
hidden(globalThis, '__nx_dispatch', (msg) => {
  const cb = listeners.get(msg.listener);
  if (!cb) return;
  const ev = eventFor(msg.event);
  const self = wrap(msg.currentTarget);
  // Inline handler properties (el.onclick) are stored as listeners too.
  invoke(cb, self, ev);
});
hidden(globalThis, '__nx_eventDone', (id) => { events.delete(id); });
hidden(globalThis, '__nx_releaseListener', (id) => {
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
const accessor = (proto, name, getter, setter) =>
  defineProperty(proto, name, { get: getter, set: setter, configurable: true, enumerable: true });

class Node extends EventTarget {
  constructor() { throw new TypeError('Illegal constructor'); }
  appendChild(child) { host('node.insertBefore', this[ID], idOf(child), null); return child; }
  insertBefore(child, ref) {
    host('node.insertBefore', this[ID], idOf(child), ref === null || ref === undefined ? null : idOf(ref));
    return child;
  }
  removeChild(child) { host('node.removeChild', this[ID], idOf(child)); return child; }
  replaceChild(newChild, oldChild) { host('node.replaceChild', this[ID], idOf(newChild), idOf(oldChild)); return oldChild; }
  remove() { host('node.remove', this[ID]); }
  contains(other) { return other === null ? false : host('node.contains', this[ID], idOf(other)); }
  cloneNode(deep = false) { return wrap(host('node.clone', this[ID], !!deep)); }
  hasChildNodes() { return host('node.get', this[ID], 'childCount') > 0; }
  append(...nodes) { for (const n of nodes) this.appendChild(nodeArg(n)); }
  prepend(...nodes) { const first = this.firstChild; for (const n of nodes) this.insertBefore(nodeArg(n), first); }
  replaceChildren(...nodes) { host('node.replaceChildren', this[ID], nodes.map((n) => idOf(nodeArg(n)))); }
}
Node.ELEMENT_NODE = 1; Node.TEXT_NODE = 3; Node.COMMENT_NODE = 8; Node.DOCUMENT_NODE = 9; Node.DOCUMENT_FRAGMENT_NODE = 11;
const NP = Node.prototype;
accessor(NP, 'nodeType', get('nodeType'));
accessor(NP, 'nodeName', get('nodeName'));
accessor(NP, 'isConnected', get('isConnected'));
accessor(NP, 'parentNode', getNode('parentNode'));
accessor(NP, 'parentElement', getNode('parentElement'));
accessor(NP, 'firstChild', getNode('firstChild'));
accessor(NP, 'lastChild', getNode('lastChild'));
accessor(NP, 'nextSibling', getNode('nextSibling'));
accessor(NP, 'previousSibling', getNode('previousSibling'));
accessor(NP, 'childNodes', getNodes('childNodes'));
accessor(NP, 'ownerDocument', function () { return this.nodeType === 9 ? null : document; });
accessor(NP, 'textContent', get('textContent'), function (v) {
  host('node.set', this[ID], 'textContent', v === null || v === undefined ? '' : String(v));
});
accessor(NP, 'nodeValue', function () { return this.nodeType === 1 || this.nodeType === 9 ? null : this.textContent; },
  function (v) { if (this.nodeType !== 1 && this.nodeType !== 9) this.textContent = v; });

class CharacterData extends Node {}
accessor(CharacterData.prototype, 'data', get('textContent'), function (v) { this.textContent = v; });
accessor(CharacterData.prototype, 'length', function () { return this.textContent.length; });
class Text extends CharacterData {}
class Comment extends CharacterData {}

// ---- ParentNode / queries --------------------------------------------------
const queries = (proto) => {
  proto.querySelector = function (s) { return wrap(host('q.one', this[ID], String(s))); };
  proto.querySelectorAll = function (s) { return wrapAll(host('q.all', this[ID], String(s))); };
  proto.getElementsByTagName = function (s) { return wrapAll(host('q.tag', this[ID], String(s))); };
  proto.getElementsByClassName = function (s) { return wrapAll(host('q.class', this[ID], String(s))); };
  accessor(proto, 'children', getNodes('children'));
  accessor(proto, 'firstElementChild', getNode('firstElementChild'));
  accessor(proto, 'lastElementChild', getNode('lastElementChild'));
  accessor(proto, 'childElementCount', function () { return this.children.length; });
};

class DocumentFragment extends Node {}
queries(DocumentFragment.prototype);

// ---- Element -----------------------------------------------------------------
class DOMTokenList {
  constructor(el) { hidden(this, '__el', el); }
  get length() { return host('cl.list', this.__el[ID]).length; }
  get value() { return this.__el.className; }
  item(i) { const l = host('cl.list', this.__el[ID]); return i < l.length ? l[i] : null; }
  contains(t) { return host('cl.list', this.__el[ID]).includes(String(t)); }
  add(...t) { host('cl.add', this.__el[ID], t.map(String)); }
  remove(...t) { host('cl.remove', this.__el[ID], t.map(String)); }
  toggle(t, force) { return host('cl.toggle', this.__el[ID], String(t), force === undefined ? null : !!force); }
  replace(a, b) { return host('cl.replace', this.__el[ID], String(a), String(b)); }
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

class Element extends Node {
  getAttribute(n) { return host('attr.get', this[ID], String(n)); }
  setAttribute(n, v) { host('attr.set', this[ID], String(n), String(v)); }
  removeAttribute(n) { host('attr.remove', this[ID], String(n)); }
  hasAttribute(n) { return host('attr.get', this[ID], String(n)) !== null; }
  toggleAttribute(n, force) { return host('attr.toggle', this[ID], String(n), force === undefined ? null : !!force); }
  getAttributeNames() { return Object.keys(this.attributesObject()); }
  attributesObject() { return host('node.get', this[ID], 'attributes'); }
  matches(s) { return host('q.matches', this[ID], String(s)); }
  closest(s) { return wrap(host('q.closest', this[ID], String(s))); }
  focus() { host('el.focus', this[ID]); }
  blur() { host('el.blur', this[ID]); }
  click() { host('el.click', this[ID]); }
  before(...nodes) { const p = this.parentNode; if (p) for (const n of nodes) p.insertBefore(nodeArg(n), this); }
  after(...nodes) {
    const p = this.parentNode; if (!p) return;
    let ref = this.nextSibling;
    for (const n of nodes) p.insertBefore(nodeArg(n), ref);
  }
  replaceWith(...nodes) { const p = this.parentNode; if (!p) return; this.before(...nodes); this.remove(); }
  insertAdjacentHTML(pos, html) { host('el.insertAdjacentHTML', this[ID], String(pos), String(html)); }
  get style() { return memo(styles, this, styleFor); }
  set style(v) { this.style.cssText = v; }
  get dataset() { return memo(datasets, this, datasetFor); }
  get classList() { return memo(classLists, this, (e) => new DOMTokenList(e)); }
  get attributes() {
    const o = this.attributesObject();
    return Object.keys(o).map((name) => ({ name, value: o[name] }));
  }
}
const EP = Element.prototype;
queries(EP);
accessor(EP, 'tagName', get('tagName'));
accessor(EP, 'localName', get('localName'));
accessor(EP, 'nextElementSibling', getNode('nextElementSibling'));
accessor(EP, 'previousElementSibling', getNode('previousElementSibling'));
accessor(EP, 'innerHTML', get('innerHTML'), function (v) { host('node.set', this[ID], 'innerHTML', String(v)); });
accessor(EP, 'outerHTML', get('outerHTML'));
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

// ---- Document ----------------------------------------------------------------
class Document extends Node {
  createElement(n) { return wrap(host('doc.createElement', String(n))); }
  createTextNode(t) { return wrap(host('doc.createText', String(t))); }
  createComment(t) { return wrap(host('doc.createComment', String(t))); }
  createDocumentFragment() { return wrap(host('doc.createFragment')); }
  getElementById(id) { return wrap(host('doc.byId', String(id))); }
  createEvent() { return new Event(''); }
}
const DP = Document.prototype;
queries(DP);
accessor(DP, 'documentElement', function () { return wrap(host('doc.get', 'documentElement')); });
accessor(DP, 'head', function () { return wrap(host('doc.get', 'head')); });
accessor(DP, 'body', function () { return wrap(host('doc.get', 'body')); });
accessor(DP, 'activeElement', function () { return wrap(host('doc.get', 'activeElement')); });
accessor(DP, 'title', function () { return host('doc.get', 'title'); },
  function (v) { host('doc.setTitle', String(v)); });
accessor(DP, 'readyState', function () { return host('doc.get', 'readyState'); });

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

const navigator = Object.freeze({
  get language() { return env().languages[0] || 'en-US'; },
  get languages() { return Object.freeze(env().languages.slice()); },
  get platform() { return env().platform; },
  userAgent: 'NativaX/0.1 (QuickJS-ng)',
  onLine: true,
});

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

for (const [name, value] of Object.entries({
  Event, CustomEvent, EventTarget, Node, CharacterData, Text, Comment, Element, DocumentFragment,
  Document, DOMTokenList, CSSStyleDeclaration, Window, MediaQueryList,
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
// Caches are keyed by id; the Window wrapper is globalThis itself.
cache.set(win[ID], new WeakRef(globalThis));
})();
''';
