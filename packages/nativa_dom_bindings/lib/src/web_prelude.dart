import 'web_prelude_webgl.dart';
import 'web_prelude_canvas.dart';
import 'web_prelude_io.dart';
import 'web_prelude_platform.dart';

/// Web platform APIs layered on the DOM prelude. Evaluated inside the DOM
/// prelude's closure (it uses `host`, `wrap`, `ID`, `Event`, ...), before the
/// globals are published.
const String webPlatformPrelude = _events + _elements + webPlatformApis + webIoApis + webCanvas + webGl;

const String _events = r'''
// ============================================================================
// Events: classes, script-side event targets, handler properties
// ============================================================================
const reportError = (e) => {
  try {
    const ev = new ErrorEvent('error', {
      error: e, message: e && e.message !== undefined ? String(e.message) : String(e),
      cancelable: true,
    });
    if (globalThis.dispatchEvent(ev) && typeof console !== 'undefined') console.error('Uncaught', e);
  } catch (inner) {
    if (typeof console !== 'undefined') console.error('Uncaught', e);
  }
};

// Script-only targets (XHR, WebSocket, AbortSignal, ...) keep listeners here.
const localListeners = new WeakMap();
const isHostTarget = (t) => t !== null && typeof t === 'object' && t[ID] !== undefined;
const ETP = EventTarget.prototype;
const hostAdd = ETP.addEventListener;
const hostRemove = ETP.removeEventListener;
const hostDispatch = ETP.dispatchEvent;
const optionsOf = (o) => (o && typeof o === 'object' ? o : {});
// Window methods also work unbound (`addEventListener(...)` at top level).
ETP.addEventListener = function (type, cb, options) {
  if (this === undefined || this === null) return ETP.addEventListener.call(globalThis, type, cb, options);
  const o = optionsOf(options);
  captureOf(options);
  if (cb === null || cb === undefined) return;
  if (o.signal && o.signal.aborted) return;
  if (o.signal) o.signal.addEventListener('abort', () => this.removeEventListener(type, cb, options), { once: true });
  const passiveRoot = this === globalThis || this === document ||
    this.localName === 'html' || this.localName === 'body';
  const passiveDefault = (type === 'touchstart' || type === 'touchmove' || type === 'wheel' || type === 'mousewheel') &&
    passiveRoot && o.passive !== false;
  if (passiveDefault || o.passive === true) passiveListeners.add(listenerId(cb));
  if (isHostTarget(this)) return hostAdd.call(this, type, cb, options);
  if (typeof cb !== 'function' && typeof cb !== 'object') throw new TypeError('listener must be a function');
  let m = localListeners.get(this);
  if (!m) { m = new Map(); localListeners.set(this, m); }
  type = String(type);
  let list = m.get(type);
  if (!list) { list = []; m.set(type, list); }
  const capture = captureOf(options);
  if (list.some((l) => l.cb === cb && l.capture === capture)) return;
  list.push({ cb, capture, once: !!o.once, removed: false });
};
ETP.removeEventListener = function (type, cb, options) {
  if (this === undefined || this === null) return ETP.removeEventListener.call(globalThis, type, cb, options);
  captureOf(options);
  if (isHostTarget(this)) return hostRemove.call(this, type, cb, options);
  const m = localListeners.get(this);
  const list = m && m.get(String(type));
  if (!list) return;
  const capture = captureOf(options);
  const i = list.findIndex((l) => l.cb === cb && l.capture === capture);
  if (i >= 0) { list[i].removed = true; list.splice(i, 1); }
};
ETP.dispatchEvent = function (ev) {
  if (this === undefined || this === null) return ETP.dispatchEvent.call(globalThis, ev);
  if (isHostTarget(this)) return hostDispatch.call(this, ev);
  if (!(ev instanceof Event)) throw new TypeError('parameter is not an Event');
  if (ev.__local && ev.__local.dispatching) throw new DOMException('The event is already being dispatched.', 'InvalidStateError');
  if (!ev.__initialized) throw new DOMException('The event is not initialized.', 'InvalidStateError');
  if (ev.__stop) {
    ev.__stop = false;
    ev.__immediate = false;
    hidden(ev, '__lastTarget', this);
    return true;
  }
  ev.__dispatching = true;
  hidden(ev, '__lastTarget', this);
  const state = { target: this, currentTarget: this, phase: 2, prevented: false, stopped: false, immediate: false, dispatching: true };
  defineProperty(ev, '__local', { value: state, configurable: true, writable: true });
  try {
    const m = localListeners.get(this);
    const list = m && m.get(ev.type);
    if (list) {
      withCurrentEvent(ev, () => {
        for (const l of list.slice()) {
          if (l.removed) continue;
          if (l.once) { l.removed = true; list.splice(list.indexOf(l), 1); }
          try { invoke(l.cb, this, ev); } catch (e) { reportError(e); }
          if (state.immediate) break;
        }
      });
    }
  } finally {
    state.dispatching = false;
    state.currentTarget = null;
    state.phase = 0;
    ev.__dispatching = false;
    ev.__stop = false;
    ev.__immediate = false;
  }
  return !state.prevented;
};

// Event: init dictionaries, script-side dispatch state, legacy members.
const EvP = Event.prototype;
const evGet = (name, fn) => defineProperty(EvP, name, { get: fn, configurable: true, enumerable: true });
const evGetSet = (name, get, set) => defineProperty(EvP, name, { get, set, configurable: true, enumerable: true });
for (const [name, value] of Object.entries({
  NONE: 0, CAPTURING_PHASE: 1, AT_TARGET: 2, BUBBLING_PHASE: 3,
})) {
  if (!(name in EvP)) defineProperty(EvP, name, { value, enumerable: true, configurable: true });
}
evGet('target', function () {
  if (this.__local) return this.__local.target;
  return this.__id ? wrap(host('event.get', this.__id, 'target')) : (this.__lastTarget || null);
});
evGet('currentTarget', function () {
  if (this.__local) return this.__local.currentTarget;
  return this.__id ? wrap(host('event.get', this.__id, 'currentTarget')) : null;
});
evGet('srcElement', function () { return this.target; });
evGet('eventPhase', function () {
  if (this.__local) return this.__local.phase;
  return this.__id ? host('event.get', this.__id, 'eventPhase') : 0;
});
evGet('defaultPrevented', function () {
  if (this.__local) return this.__local.prevented;
  return this.__id ? host('event.get', this.__id, 'defaultPrevented') : !!this.__prevented;
});
evGetSet('returnValue', function () { return !this.defaultPrevented; }, function (value) {
  if (value === false) this.preventDefault();
});
evGet('composed', function () { return !!(this.__init && this.__init.composed); });
evGetSet('cancelBubble', function () {
  return !!(this.__stop || (this.__local && this.__local.stopped));
}, function (value) {
  if (value) this.stopPropagation();
});
evGet('timeStamp', function () { return this.__desc ? this.__desc.timeStamp - perfOrigin : (this.__created || 0); });
EvP.preventDefault = function () {
  if (this.__passive || !this.cancelable) return;
  this.__prevented = true;
  if (this.__local) this.__local.prevented = true;
  else if (this.__id) host('event.call', this.__id, 'preventDefault');
};
EvP.stopPropagation = function () {
  this.__stop = true;
  if (this.__local) this.__local.stopped = true;
  else if (this.__id) host('event.call', this.__id, 'stopPropagation');
};
EvP.stopImmediatePropagation = function () {
  this.__stop = true;
  this.__immediate = true;
  if (this.__local) { this.__local.stopped = true; this.__local.immediate = true; }
  else if (this.__id) host('event.call', this.__id, 'stopImmediatePropagation');
};
EvP.composedPath = function () {
  if (!this.__dispatching && !(this.__local && this.__local.dispatching)) return [];
  const path = [];
  for (let n = this.target; n; n = n.parentNode) path.push(n);
  if (path.length && path[path.length - 1] === document) path.push(globalThis);
  return path;
};
EvP.initEvent = function (type, bubbles = false, cancelable = false) {
  if (arguments.length === 0) throw new TypeError('initEvent requires a type');
  if (this.__dispatching || (this.__local && this.__local.dispatching)) return;
  if (this.__id) return;
  hidden(this, '__type', String(type));
  hidden(this, '__init', { bubbles: !!bubbles, cancelable: !!cancelable });
  hidden(this, '__initialized', true);
  this.__prevented = false;
  this.__stop = false;
  this.__immediate = false;
};
if (CustomEvent) {
  CustomEvent.prototype.initCustomEvent = function (type, bubbles = false, cancelable = false, detail = null) {
    if (arguments.length === 0) throw new TypeError('initCustomEvent requires a type');
    if (this.__dispatching || (this.__local && this.__local.dispatching)) return;
    if (this.__id) return;
    this.initEvent(type, bubbles, cancelable);
    defineProperty(this, 'detail', { value: detail, writable: false, configurable: true, enumerable: true });
  };
}
Event.prototype[Symbol.toStringTag] = 'Event';

// Subclasses declare their fields and defaults; values come from the init
// dictionary (script-created) or the host event's detail (trusted).
const defineEventClass = (name, Base, fields) => {
  const C = class extends Base {
    constructor(type, init = {}) {
      super(type, init);
      const f = this.__fields ? Object.assign({}, this.__fields) : {};
      for (const k of Object.keys(fields)) if (init && init[k] !== undefined) f[k] = init[k];
      hidden(this, '__fields', f);
    }
  };
  defineProperty(C, 'name', { value: name });
  for (const [k, def] of Object.entries(fields)) {
    defineProperty(C.prototype, k, {
      get() {
        const f = this.__fields;
        if (f && k in f) return f[k];
        const d = this.__desc && this.__desc.detail;
        if (d && k in d) return d[k];
        return typeof def === 'function' ? def.call(this) : def;
      },
      configurable: true, enumerable: true,
    });
  }
  C.prototype[Symbol.toStringTag] = name;
  return C;
};
const UIEventBase = defineEventClass('UIEvent', Event, { view: null, detail: 0, which: 0 });
class UIEvent extends UIEventBase {
  constructor(type, init = {}) {
    init = init || {};
    if (init.view !== undefined && init.view !== null && !(init.view instanceof Window)) {
      throw new TypeError('view must be a Window');
    }
    super(type, init);
  }
}
UIEvent.prototype[Symbol.toStringTag] = 'UIEvent';
const initFields = (ev, values) => {
  const f = ev.__fields ? Object.assign({}, ev.__fields) : {};
  Object.assign(f, values);
  hidden(ev, '__fields', f);
};
UIEvent.prototype.initUIEvent = function (type, bubbles = false, cancelable = false, view = null, detail = 0) {
  if (arguments.length === 0) throw new TypeError('initUIEvent requires a type');
  if (this.__dispatching || (this.__local && this.__local.dispatching)) return;
  this.initEvent(type, bubbles, cancelable);
  initFields(this, { view, detail });
};

const mouseFields = {
  screenX: 0, screenY: 0, clientX: 0, clientY: 0, pageX() { return this.clientX + (globalThis.scrollX || 0); },
  pageY() { return this.clientY + (globalThis.scrollY || 0); },
  offsetX() { const t = this.target; const r = t && t.getBoundingClientRect ? t.getBoundingClientRect() : null; let left = r && r.left ? r.left : (t && t.offsetLeft) || 0; if (!left && t && t.parentElement) left = parseFloat(getComputedStyle(t.parentElement).marginLeft || '0') || 0; return this.clientX - left; },
  offsetY() { const t = this.target; const r = t && t.getBoundingClientRect ? t.getBoundingClientRect() : null; const top = r && r.top ? r.top : (t && t.offsetTop) || 0; return this.clientY - top; },
  x() { return this.clientX; },
  y() { return this.clientY; }, movementX: 0, movementY: 0, ctrlKey: false, shiftKey: false, altKey: false,
  metaKey: false, button: 0, buttons: 0, relatedTarget: null,
};
const MouseEvent = defineEventClass('MouseEvent', UIEvent, mouseFields);
MouseEvent.prototype.initMouseEvent = function (type, bubbles = false, cancelable = false, view = null, detail = 0,
  screenX = 0, screenY = 0, clientX = 0, clientY = 0, ctrlKey = false, altKey = false,
  shiftKey = false, metaKey = false, button = 0, relatedTarget = null) {
  if (arguments.length === 0) throw new TypeError('initMouseEvent requires a type');
  if (this.__dispatching || (this.__local && this.__local.dispatching)) return;
  this.initEvent(type, bubbles, cancelable);
  initFields(this, { view, detail, screenX, screenY, clientX, clientY, ctrlKey, altKey, shiftKey, metaKey, button, relatedTarget });
};
MouseEvent.prototype.getModifierState = function (k) {
  return ({ Control: this.ctrlKey, Shift: this.shiftKey, Alt: this.altKey, Meta: this.metaKey })[k] || false;
};
const PointerEvent = defineEventClass('PointerEvent', MouseEvent, {
  pointerId: 1, width: 1, height: 1, pressure: 0, tangentialPressure: 0, tiltX: 0, tiltY: 0, twist: 0,
  pointerType: 'mouse', isPrimary: true,
});
const WheelEvent = defineEventClass('WheelEvent', MouseEvent, { deltaX: 0, deltaY: 0, deltaZ: 0, deltaMode: 0 });
const DragEvent = defineEventClass('DragEvent', MouseEvent, { dataTransfer: null });
const KeyboardEvent = defineEventClass('KeyboardEvent', UIEvent, {
  key: '', code: '', location: 0, ctrlKey: false, shiftKey: false, altKey: false, metaKey: false,
  repeat: false, isComposing: false, charCode: 0, keyCode: 0,
});
KeyboardEvent.prototype.getModifierState = MouseEvent.prototype.getModifierState;
KeyboardEvent.prototype.initKeyboardEvent = function (type, bubbles = false, cancelable = false, view = null,
  key = '', location = 0, ctrlKey = false, altKey = false, shiftKey = false, metaKey = false) {
  if (arguments.length === 0) throw new TypeError('initKeyboardEvent requires a type');
  if (this.__dispatching || (this.__local && this.__local.dispatching)) return;
  this.initEvent(type, bubbles, cancelable);
  initFields(this, { view, key, location, ctrlKey, altKey, shiftKey, metaKey });
};
const FocusEvent = defineEventClass('FocusEvent', UIEvent, { relatedTarget: null });
const InputEvent = defineEventClass('InputEvent', UIEvent, { data: null, inputType: '', isComposing: false, dataTransfer: null });
const CompositionEvent = defineEventClass('CompositionEvent', UIEvent, { data: '' });
const TouchEvent = defineEventClass('TouchEvent', UIEvent, { touches: [], targetTouches: [], changedTouches: [], altKey: false, ctrlKey: false, metaKey: false, shiftKey: false });
const SubmitEvent = defineEventClass('SubmitEvent', Event, { submitter: null });
const FormDataEvent = defineEventClass('FormDataEvent', Event, { formData: null });
const ErrorEvent = defineEventClass('ErrorEvent', Event, { message: '', filename: '', lineno: 0, colno: 0, error: null });
const PromiseRejectionEvent = defineEventClass('PromiseRejectionEvent', Event, { promise: null, reason: undefined });
const MessageEvent = defineEventClass('MessageEvent', Event, { data: null, origin: '', lastEventId: '', source: null, ports: [] });
const CloseEvent = defineEventClass('CloseEvent', Event, { wasClean: false, code: 0, reason: '' });
const ProgressEvent = defineEventClass('ProgressEvent', Event, { lengthComputable: false, loaded: 0, total: 0 });
const HashChangeEvent = defineEventClass('HashChangeEvent', Event, { oldURL: '', newURL: '' });
const PopStateEvent = defineEventClass('PopStateEvent', Event, { state: null });
const PageTransitionEvent = defineEventClass('PageTransitionEvent', Event, { persisted: false });
const StorageEvent = defineEventClass('StorageEvent', Event, { key: null, oldValue: null, newValue: null, url: '', storageArea: null });
const AnimationEvent = defineEventClass('AnimationEvent', Event, { animationName: '', elapsedTime: 0, pseudoElement: '' });
const TransitionEvent = defineEventClass('TransitionEvent', Event, { propertyName: '', elapsedTime: 0, pseudoElement: '' });
const ToggleEvent = defineEventClass('ToggleEvent', Event, { oldState: '', newState: '' });
const ClipboardEvent = defineEventClass('ClipboardEvent', Event, { clipboardData: null });
const MediaQueryListEvent = defineEventClass('MediaQueryListEvent', Event, { matches: false, media: '' });

// Drag-and-drop sessions: one DataTransfer per drag, shared by its events.
const dragSessions = new Map();
class DataTransfer {
  constructor() {
    hidden(this, '_d', new Map());
    this.dropEffect = 'none';
    this.effectAllowed = 'all';
  }
  setData(type, data) { this._d.set(String(type).toLowerCase(), String(data)); }
  getData(type) { const t = String(type).toLowerCase(); return this._d.get(t === 'text' ? 'text/plain' : t) ?? ''; }
  clearData(type) { if (type === undefined) this._d.clear(); else this._d.delete(String(type).toLowerCase()); }
  get types() { return [...this._d.keys()]; }
  get files() { return []; }
  get items() { return [...this._d].map(([type, v]) => ({ kind: 'string', type, getAsString: (cb) => cb(v), getAsFile: () => null })); }
  setDragImage() {}
}
const dataTransferFor = (id) => {
  let dt = dragSessions.get(id);
  if (!dt) { dt = new DataTransfer(); dragSessions.set(id, dt); if (dragSessions.size > 16) dragSessions.delete(dragSessions.keys().next().value); }
  return dt;
};

const eventProtos = {
  click: MouseEvent, dblclick: MouseEvent, contextmenu: PointerEvent, mousedown: MouseEvent, mouseup: MouseEvent,
  mousemove: MouseEvent, mouseover: MouseEvent, mouseout: MouseEvent, mouseenter: MouseEvent, mouseleave: MouseEvent,
  pointerdown: PointerEvent, pointerup: PointerEvent, pointermove: PointerEvent, pointerover: PointerEvent,
  pointerout: PointerEvent, pointerenter: PointerEvent, pointerleave: PointerEvent, pointercancel: PointerEvent,
  wheel: WheelEvent, keydown: KeyboardEvent, keyup: KeyboardEvent, keypress: KeyboardEvent, focus: FocusEvent,
  blur: FocusEvent, focusin: FocusEvent, focusout: FocusEvent, input: InputEvent, beforeinput: InputEvent,
  submit: SubmitEvent, error: ErrorEvent, message: MessageEvent, hashchange: HashChangeEvent,
  popstate: PopStateEvent, storage: StorageEvent, toggle: ToggleEvent, change: MediaQueryListEvent,
  dragstart: DragEvent, drag: DragEvent, dragend: DragEvent, dragenter: DragEvent, dragleave: DragEvent,
  dragover: DragEvent, drop: DragEvent, touchstart: TouchEvent, touchmove: TouchEvent, touchend: TouchEvent,
};
eventProtoFor = (type) => {
  if (type === 'change') return Event.prototype;
  const C = eventProtos[type];
  if (type.startsWith('nativax:')) return CustomEvent.prototype;
  return C ? C.prototype : Event.prototype;
};

// on<event> handler properties for every common event type.
const allHandlerNames = [
  'abort', 'afterprint', 'animationend', 'animationiteration', 'animationstart', 'auxclick', 'beforeinput',
  'beforeprint', 'beforeunload', 'blur', 'cancel', 'canplay', 'canplaythrough', 'change', 'click', 'close',
  'contextmenu', 'copy', 'cut', 'dblclick', 'drag', 'dragend', 'dragenter', 'dragleave', 'dragover',
  'dragstart', 'drop', 'durationchange', 'emptied', 'ended', 'error', 'focus', 'focusin', 'focusout',
  'formdata', 'hashchange', 'input', 'invalid', 'keydown', 'keypress', 'keyup', 'languagechange', 'load',
  'loadeddata', 'loadedmetadata', 'loadend', 'loadstart', 'message', 'messageerror', 'mousedown',
  'mouseenter', 'mouseleave', 'mousemove', 'mouseout', 'mouseover', 'mouseup', 'offline', 'online', 'open',
  'pagehide', 'pageshow', 'paste', 'pause', 'play', 'playing', 'pointercancel', 'pointerdown',
  'pointerenter', 'pointerleave', 'pointermove', 'pointerout', 'pointerover', 'pointerup', 'popstate',
  'progress', 'ratechange', 'readystatechange', 'rejectionhandled', 'reset', 'resize', 'scroll', 'scrollend',
  'search', 'seeked', 'seeking', 'select', 'selectionchange', 'selectstart', 'slotchange', 'stalled',
  'storage', 'submit', 'suspend', 'timeout', 'timeupdate', 'toggle', 'touchcancel', 'touchend', 'touchmove',
  'touchstart', 'transitionend', 'transitionrun', 'transitionstart', 'unhandledrejection', 'unload',
  'upgradeneeded', 'success', 'complete', 'blocked', 'versionchange', 'visibilitychange', 'volumechange',
  'waiting', 'wheel',
];
for (const name of allHandlerNames) {
  if (Object.getOwnPropertyDescriptor(ETP, 'on' + name)) continue;
  defineProperty(ETP, 'on' + name, {
    get() { const h = handlers.get(this); return (h && h[name]) || null; },
    set(fn) {
      let h = handlers.get(this);
      if (!h) { h = {}; handlers.set(this, h); }
      h.__wrappers = h.__wrappers || {};
      if (h[name]) {
        this.removeEventListener(name, h.__wrappers[name]);
        if (prefixedEvents[name]) this.removeEventListener(prefixedEvents[name], h.__wrappers[name]);
      }
      if (typeof fn === 'function') {
        h[name] = fn;
        const wrapper = function (ev) {
          const r = name === 'error' && ev instanceof ErrorEvent && this === globalThis
            ? fn.call(this, ev.message, ev.filename, ev.lineno, ev.colno, ev.error)
            : fn.call(this, ev);
          if (r === false || (name === 'beforeunload' && typeof r === 'string')) ev.preventDefault();
        };
        h.__wrappers[name] = wrapper;
        this.addEventListener(name, wrapper);
        if (prefixedEvents[name]) this.addEventListener(prefixedEvents[name], wrapper);
      } else {
        h[name] = null;
      }
    },
    configurable: true,
  });
}
// Inline handler attributes (<button onclick="...">) compile on first use.
const compileInlineHandlers = (root) => {
  const els = root.querySelectorAll ? root.querySelectorAll('*') : [];
  for (const el of [root, ...els]) {
    if (!el || !el.getAttributeNames) continue;
    for (const attr of el.getAttributeNames()) {
      if (!attr.startsWith('on') || !allHandlerNames.includes(attr.slice(2))) continue;
      try {
        const fn = new Function('event', String(el.getAttribute(attr)));
        el[attr] = fn;
      } catch (e) { reportError(e); }
    }
  }
};
''';

const String _elements = r'''
// ============================================================================
// HTML element interfaces
// ============================================================================
const DOMRectReadOnly = class DOMRectReadOnly {
  constructor(x = 0, y = 0, width = 0, height = 0) {
    hidden(this, '_v', [Number(x), Number(y), Number(width), Number(height)]);
  }
  get x() { return this._v[0]; } get y() { return this._v[1]; }
  get width() { return this._v[2]; } get height() { return this._v[3]; }
  get left() { return Math.min(this.x, this.x + this.width); }
  get right() { return Math.max(this.x, this.x + this.width); }
  get top() { return Math.min(this.y, this.y + this.height); }
  get bottom() { return Math.max(this.y, this.y + this.height); }
  toJSON() { const { x, y, width, height, top, right, bottom, left } = this; return { x, y, width, height, top, right, bottom, left }; }
  static fromRect(r = {}) { return new this(r.x, r.y, r.width, r.height); }
};
class DOMRect extends DOMRectReadOnly {
  set x(v) { this._v[0] = Number(v); } set y(v) { this._v[1] = Number(v); }
  set width(v) { this._v[2] = Number(v); } set height(v) { this._v[3] = Number(v); }
  get x() { return this._v[0]; } get y() { return this._v[1]; }
  get width() { return this._v[2]; } get height() { return this._v[3]; }
}
class DOMPoint {
  constructor(x = 0, y = 0, z = 0, w = 1) { Object.assign(this, { x, y, z, w }); }
  static fromPoint(p = {}) { return new DOMPoint(p.x, p.y, p.z, p.w); }
  toJSON() { return { x: this.x, y: this.y, z: this.z, w: this.w }; }
}

const boxOf = (el) => host('layout.box', el[ID]) || null;
const emptyBox = { x: 0, y: 0, width: 0, height: 0, offsetX: 0, offsetY: 0, clientWidth: 0, clientHeight: 0, scrollWidth: 0, scrollHeight: 0, scrollTop: 0, scrollLeft: 0 };
const layoutBox = (el) => boxOf(el) || emptyBox;

class HTMLElement extends Element {
  constructor() {
    // Custom element construction: new.target is the registered class.
    const def = customRegistryByCtor.get(new.target);
    if (!def) throw new TypeError('Illegal constructor');
    const pending = upgrading.pop();
    if (pending) return pending;
    const el = wrap(host('doc.createElement', document[ID], def.name));
    Object.setPrototypeOf(el, new.target.prototype);
    upgraded.add(el);
    return el;
  }
}
globalThis.HTMLElement = HTMLElement;
const HEP = HTMLElement.prototype;

// Geometry.
accessor(EP, 'offsetWidth', function () { const b = layoutBox(this); return Math.round(b.offsetWidth ?? b.width); });
accessor(EP, 'offsetHeight', function () { const b = layoutBox(this); return Math.round(b.offsetHeight ?? b.height); });
accessor(EP, 'offsetTop', function () { return Math.round(layoutBox(this).offsetY); });
accessor(EP, 'offsetLeft', function () { return Math.round(layoutBox(this).offsetX); });
accessor(EP, 'offsetParent', function () { return boxOf(this) ? document.body : null; });
accessor(EP, 'clientWidth', function () { return Math.round(layoutBox(this).clientWidth); });
accessor(EP, 'clientHeight', function () { return Math.round(layoutBox(this).clientHeight); });
accessor(EP, 'clientTop', function () { return 0; });
accessor(EP, 'clientLeft', function () { return 0; });
accessor(EP, 'scrollWidth', function () { return Math.round(layoutBox(this).scrollWidth); });
accessor(EP, 'scrollHeight', function () { return Math.round(layoutBox(this).scrollHeight); });
accessor(EP, 'scrollTop', function () {
  return this === document.documentElement || this === document.body ? globalThis.scrollY : layoutBox(this).scrollTop;
}, function (v) {
  if (this === document.documentElement || this === document.body) globalThis.scrollTo(globalThis.scrollX, Number(v));
});
accessor(EP, 'scrollLeft', function () { return layoutBox(this).scrollLeft; }, function () {});
EP.getBoundingClientRect = function () { const b = layoutBox(this); return new DOMRect(b.x, b.y, b.width, b.height); };
EP.getClientRects = function () { const b = boxOf(this); return b ? [new DOMRect(b.x, b.y, b.width, b.height)] : []; };
EP.scrollIntoView = function (arg) {
  const smooth = arg && typeof arg === 'object' && arg.behavior === 'smooth';
  host('layout.scrollIntoView', this[ID], !!smooth);
};
EP.scrollIntoViewIfNeeded = function () { this.scrollIntoView(); };
EP.scrollTo = EP.scroll = EP.scrollBy = function () {};
EP.checkVisibility = function () { return !!boxOf(this) && getComputedStyle(this).visibility !== 'hidden'; };
EP.animate = function (keyframes, options) {
  const finished = Promise.resolve();
  const anim = Object.assign(new EventTarget(), {
    playState: 'finished', currentTime: 0, effect: null, finished, ready: Promise.resolve(),
    cancel() {}, finish() {}, play() {}, pause() {}, reverse() {}, commitStyles() {}, persist() {},
    onfinish: null, oncancel: null,
  });
  return anim;
};
EP.getAnimations = function () { return []; };
EP.attachShadow = function (init = {}) {
  const existing = shadowRoots.get(this);
  if (existing) return existing;
  const mode = init && init.mode === 'closed' ? 'closed' : 'open';
  const root = new ShadowRoot(this, mode, init && init.delegatesFocus);
  shadowRoots.set(this, root);
  return root;
};
EP.requestFullscreen = function () { return Promise.reject(new DOMException('Fullscreen is not supported', 'NotSupportedError')); };
EP.requestPointerLock = function () {};
EP.setPointerCapture = EP.releasePointerCapture = function () {};
EP.hasPointerCapture = function () { return false; };
EP.focus = function () { host('el.focus', this[ID]); };
EP.webkitMatchesSelector = EP.matches;
accessor(EP, 'outerHTML', get('outerHTML'), function (v) {
  host('el.outerHTML', this[ID], String(v));
});
accessor(EP, 'innerText', function () {
  if (this.hidden) return '';
  return this.textContent;
}, function (v) { this.textContent = v; });
accessor(EP, 'outerText', function () { return this.innerText; }, function (v) { this.replaceWith(String(v)); });
accessor(EP, 'shadowRoot', function () {
  const root = shadowRoots.get(this);
  return root && root.mode === 'open' ? root : null;
});
accessor(EP, 'assignedSlot', function () { return null; });
accessor(EP, 'slot', function () { return this.getAttribute('slot') || ''; }, function (v) { this.setAttribute('slot', v); });
accessor(EP, 'part', function () { return this.classList; });
accessor(EP, 'isContentEditable', function () {
  for (let e = this; e; e = e.parentElement) {
    const v = e.getAttribute('contenteditable');
    if (v !== null) return v !== 'false';
  }
  return false;
});
accessor(EP, 'contentEditable', function () { const v = this.getAttribute('contenteditable'); return v === null ? 'inherit' : (v === '' ? 'true' : v); },
  function (v) { if (v === 'inherit') this.removeAttribute('contenteditable'); else this.setAttribute('contenteditable', v); });
accessor(EP, 'tabIndex', function () {
  const v = parseInt(this.getAttribute('tabindex'), 10);
  if (!Number.isNaN(v)) return v;
  return ['a', 'button', 'input', 'select', 'textarea', 'summary', 'iframe'].includes(this.localName) ? 0 : -1;
}, function (v) { this.setAttribute('tabindex', String(Math.trunc(Number(v)) || 0)); });
for (const [prop, attr] of [['accessKey', 'accesskey'], ['enterKeyHint', 'enterkeyhint'], ['inputMode', 'inputmode'],
  ['autocapitalize', 'autocapitalize'], ['nonce', 'nonce'], ['popover', 'popover'], ['role', 'role'], ['type', 'type'],
  ['autocomplete', 'autocomplete'], ['accept', 'accept'], ['pattern', 'pattern'], ['min', 'min'], ['max', 'max'],
  ['step', 'step'], ['formAction', 'formaction'], ['enctype', 'enctype'], ['download', 'download'],
  ['hreflang', 'hreflang'], ['ping', 'ping'], ['referrerPolicy', 'referrerpolicy'], ['crossOrigin', 'crossorigin'],
  ['loading', 'loading'], ['decoding', 'decoding'], ['srcset', 'srcset'], ['sizes', 'sizes'], ['useMap', 'usemap'],
  ['media', 'media'], ['label', 'label'], ['wrap', 'wrap'], ['dirName', 'dirname'], ['formMethod', 'formmethod'],
  ['formTarget', 'formtarget'], ['poster', 'poster'], ['preload', 'preload'], ['kind', 'kind'], ['srclang', 'srclang'],
  ['integrity', 'integrity'], ['as', 'as'], ['charset', 'charset'], ['content', 'content'], ['httpEquiv', 'http-equiv'],
  ['scope', 'scope'], ['abbr', 'abbr'], ['headers', 'headers'], ['datetime', 'datetime'], ['dateTime', 'datetime'],
  ['cite', 'cite'], ['shape', 'shape'], ['coords', 'coords'], ['allow', 'allow'], ['sandbox', 'sandbox'],
  ['srcdoc', 'srcdoc'], ['form', null]]) {
  if (attr === null) continue;
  accessor(EP, prop, function () { const v = this.getAttribute(attr); return v === null ? '' : v; },
    function (v) { this.setAttribute(attr, v); });
}
for (const attr of ['inert', 'draggable', 'spellcheck', 'translate', 'noValidate', 'formNoValidate', 'novalidate',
  'controls', 'loop', 'muted', 'autoplay', 'playsInline', 'defer', 'async', 'noModule', 'reversed', 'open',
  'allowFullscreen', 'default', 'isMap', 'indeterminate']) {
  const name = attr.toLowerCase();
  if (attr === 'open') continue;
  if (attr === 'draggable') {
    accessor(EP, attr, function () { const v = this.getAttribute('draggable'); return v === 'true' || (v === null && (this.localName === 'img' || (this.localName === 'a' && this.hasAttribute('href')))); },
      function (v) { this.setAttribute('draggable', v ? 'true' : 'false'); });
    continue;
  }
  if (attr === 'spellcheck' || attr === 'translate') {
    accessor(EP, attr, function () { return this.getAttribute(name) !== 'false' && this.getAttribute(name) !== 'no'; },
      function (v) { this.setAttribute(name, attr === 'translate' ? (v ? 'yes' : 'no') : String(!!v)); });
    continue;
  }
  accessor(EP, attr, function () { return this.hasAttribute(name); }, function (v) { this.toggleAttribute(name, !!v); });
}
// ARIA reflection (ariaLabel, ariaHidden, ...).
for (const a of ['atomic', 'autoComplete', 'busy', 'checked', 'colCount', 'colIndex', 'colSpan', 'current',
  'description', 'disabled', 'expanded', 'hasPopup', 'hidden', 'invalid', 'keyShortcuts', 'label', 'level',
  'live', 'modal', 'multiLine', 'multiSelectable', 'orientation', 'placeholder', 'posInSet', 'pressed',
  'readOnly', 'required', 'roleDescription', 'rowCount', 'rowIndex', 'rowSpan', 'selected', 'setSize', 'sort',
  'valueMax', 'valueMin', 'valueNow', 'valueText']) {
  const attr = 'aria-' + a.toLowerCase();
  accessor(EP, 'aria' + a[0].toUpperCase() + a.slice(1), function () { return this.getAttribute(attr); },
    function (v) { if (v === null) this.removeAttribute(attr); else this.setAttribute(attr, v); });
}

// Forms.
const isFormControl = (el) => ['input', 'select', 'textarea', 'button', 'fieldset', 'output', 'object'].includes(el.localName);
accessor(EP, 'form', function () {
  if (!isFormControl(this) && !['label', 'legend', 'option'].includes(this.localName)) return undefined;
  const id = this.getAttribute('form');
  if (id) { const f = document.getElementById(id); return f && f.localName === 'form' ? f : null; }
  if (this.localName === 'label') { const c = this.control; return c ? c.form : null; }
  return this.closest('form');
});
class ValidityState {}
const validityOf = (el) => {
  const v = host('el.validity', el[ID]);
  const o = Object.create(ValidityState.prototype);
  for (const k of ['valueMissing', 'typeMismatch', 'patternMismatch', 'tooLong', 'tooShort', 'rangeUnderflow',
    'rangeOverflow', 'stepMismatch', 'badInput', 'customError', 'valid']) hidden(o, k, v[k]);
  return o;
};
accessor(EP, 'validity', function () { return validityOf(this); });
accessor(EP, 'validationMessage', function () { return host('el.validity', this[ID]).validationMessage; });
accessor(EP, 'willValidate', function () { return host('el.validity', this[ID]).willValidate; });
EP.checkValidity = function () { return host('el.call', this[ID], 'checkValidity', []); };
EP.reportValidity = function () { return host('el.call', this[ID], 'reportValidity', []); };
EP.setCustomValidity = function (m) { host('el.call', this[ID], 'setCustomValidity', [domString(m)]); };
EP.requestSubmit = function (submitter) {
  if (this.localName !== 'form') return;
  if (submitter !== undefined && submitter !== null) {
    if (submitter.form !== this) throw new DOMException('The submitter is not owned by this form.', 'NotFoundError');
    submitter.click();
    return;
  }
  host('el.call', this[ID], 'requestSubmit', [null]);
};
EP.submit = function () { host('el.call', this[ID], 'submit', []); };
EP.reset = function () { host('el.call', this[ID], 'reset', []); };
accessor(EP, 'elements', function () {
  if (this.localName !== 'form' && this.localName !== 'fieldset') return undefined;
  const list = (this.localName === 'form'
    ? host('el.formControls', this[ID])
    : this.querySelectorAll('input,select,textarea,button,fieldset,output,object').map((e) => [e[ID], 1, e.localName])
  ).map((d) => (Array.isArray(d) ? wrap(d) : d));
  return controlsCollection(list);
});
class RadioNodeList extends Array {
  get value() { const c = this.find((e) => e.checked); return c ? c.value : ''; }
  set value(v) { const c = this.find((e) => e.value === String(v)); if (c) c.checked = true; }
}
class HTMLFormControlsCollection extends Array {
  item(i) { return this[i] || null; }
  namedItem(name) {
    const matches = this.filter((e) => e.id === name || e.getAttribute('name') === name);
    if (matches.length === 0) return null;
    if (matches.length === 1) return matches[0];
    return RadioNodeList.from(matches);
  }
}
const controlsCollection = (list) => {
  const c = HTMLFormControlsCollection.from(list);
  for (const e of list) {
    for (const key of [e.getAttribute('name'), e.id]) {
      if (!key || /^\d+$/.test(key) || key in c) continue;
      defineProperty(c, key, { get() { return c.namedItem(key); }, enumerable: false, configurable: true });
    }
  }
  return c;
};
accessor(EP, 'labels', function () {
  if (!isFormControl(this)) return undefined;
  const out = [];
  const id = this.id;
  for (const l of document.querySelectorAll('label')) {
    if ((id && l.htmlFor === id) || (!l.htmlFor && l.contains(this))) out.push(l);
  }
  return out;
});
accessor(EP, 'control', function () {
  if (this.localName !== 'label') return undefined;
  const f = this.htmlFor;
  if (f) return document.getElementById(f);
  return this.querySelector('input:not([type=hidden]),select,textarea,button,meter,output,progress');
});
accessor(EP, 'defaultValue', function () {
  return this.localName === 'textarea' ? this.textContent : (this.getAttribute('value') || '');
}, function (v) { if (this.localName === 'textarea') this.textContent = v; else this.setAttribute('value', v); });
accessor(EP, 'defaultChecked', function () { return this.hasAttribute('checked'); }, function (v) { this.toggleAttribute('checked', !!v); });
accessor(EP, 'valueAsNumber', function () {
  const t = this.type;
  const v = this.value;
  if (t === 'date' || t === 'datetime-local' || t === 'month') { const d = Date.parse(t === 'month' ? v + '-01' : v + (t === 'date' ? 'T00:00:00Z' : 'Z')); return Number.isNaN(d) ? NaN : d; }
  if (t === 'time') { const m = /^(\d\d):(\d\d)(?::(\d\d))?/.exec(v); return m ? ((+m[1] * 60 + +m[2]) * 60 + +(m[3] || 0)) * 1000 : NaN; }
  if (t === 'number' || t === 'range') return v === '' ? NaN : Number(v);
  return NaN;
}, function (n) {
  const t = this.type;
  if (Number.isNaN(n)) { this.value = ''; return; }
  if (t === 'date') this.value = new Date(n).toISOString().slice(0, 10);
  else if (t === 'time') { const d = new Date(n); this.value = d.toISOString().slice(11, 16); }
  else this.value = String(n);
});
accessor(EP, 'valueAsDate', function () {
  const n = this.valueAsNumber;
  return ['date', 'time', 'month', 'week', 'datetime-local'].includes(this.type) && !Number.isNaN(n) ? new Date(n) : null;
}, function (d) { this.valueAsNumber = d === null ? NaN : d.getTime(); });
for (const [prop, attr] of [['maxLength', 'maxlength'], ['minLength', 'minlength'], ['size', 'size'], ['rows', 'rows'],
  ['cols', 'cols'], ['width', 'width'], ['height', 'height'], ['start', 'start'], ['span', 'span'],
  ['colSpan', 'colspan'], ['rowSpan', 'rowspan']]) {
  const defaults = { maxLength: -1, minLength: -1, size: 20, rows: 2, cols: 20, start: 1, span: 1, colSpan: 1, rowSpan: 1 };
  accessor(EP, prop, function () {
    const v = parseInt(this.getAttribute(attr), 10);
    if (!Number.isNaN(v)) return v;
    if ((prop === 'width' || prop === 'height') && ['img', 'canvas', 'video'].includes(this.localName)) {
      if (this.localName === 'canvas') return prop === 'width' ? 300 : 150;
      return Math.round(layoutBox(this)[prop]);
    }
    return defaults[prop] !== undefined ? defaults[prop] : 0;
  }, function (v) { this.setAttribute(attr, String(Math.trunc(Number(v)))); });
}
accessor(EP, 'files', function () { return this.localName === 'input' && this.type === 'file' ? fileListOf([]) : undefined; }, function () {});
accessor(EP, 'selectionStart', function () { return this.value === undefined ? null : String(this.value).length; }, function () {});
accessor(EP, 'selectionEnd', function () { return this.value === undefined ? null : String(this.value).length; }, function () {});
accessor(EP, 'selectionDirection', function () { return 'none'; }, function () {});
EP.setSelectionRange = function () {};
EP.select = function () {};
EP.setRangeText = function (text) { this.value = String(text); };
EP.stepUp = function (n = 1) {
  const step = Number(this.getAttribute('step')) || 1;
  const v = (Number(this.value) || 0) + step * n;
  const max = this.getAttribute('max');
  this.value = String(max !== null ? Math.min(v, Number(max)) : v);
};
EP.stepDown = function (n = 1) { this.stepUp(-n); };
EP.showPicker = function () {};
// Options and selects.
accessor(EP, 'selected', function () { return this.localName === 'option' ? host('node.get', this[ID], 'optionSelected') : undefined; },
  function (v) { if (this.localName === 'option') host('el.call', this[ID], 'setOptionSelected', [!!v]); });
accessor(EP, 'defaultSelected', function () { return this.hasAttribute('selected'); }, function (v) { this.toggleAttribute('selected', !!v); });
accessor(EP, 'text', function () { return this.localName === 'option' ? this.textContent.replace(/\s+/g, ' ').trim() : this.textContent; },
  function (v) { this.textContent = v; });
accessor(EP, 'index', function () {
  if (this.localName !== 'option') return undefined;
  const s = this.closest('select');
  return s ? s.options.indexOf(this) : 0;
});
accessor(EP, 'selectedOptions', function () {
  if (this.localName !== 'select') return undefined;
  return wrapAll(host('el.selectedOptions', this[ID]));
});
accessor(EP, 'length', function () { return this.localName === 'select' ? this.options.length : undefined; });
EP.add = function (option, before = null) {
  if (this.localName !== 'select') return;
  const ref = typeof before === 'number' ? this.options[before] : before;
  (ref ? ref.parentNode : this).insertBefore(option, ref || null);
};
EP.item = function (i) { return this.localName === 'select' ? this.options[i] || null : undefined; };
EP.namedItem = function (n) { return this.localName === 'select' ? this.options.find((o) => o.id === n || o.getAttribute('name') === n) || null : undefined; };
const nodeRemove = Node.prototype.remove;
EP.remove = function (...args) {
  if (this.localName === 'select' && typeof args[0] === 'number') { const o = this.options[args[0]]; if (o) o.remove(); return; }
  nodeRemove.call(this);
};

// Links: URL decomposition of href.
const resolvedHref = (el) => {
  const raw = el.getAttribute('href');
  if (raw === null) return '';
  try { return new URL(raw, document.baseURI).href; } catch (e) { return raw; }
};
const urlPart = (el, part) => {
  const href = resolvedHref(el);
  try { return new URL(href)[part]; } catch (e) { return ''; }
};
const setUrlPart = (el, part, value) => {
  try {
    const u = new URL(resolvedHref(el));
    const parts = { protocol: u.protocol, host: u.host, pathname: u.pathname, search: u.search, hash: u.hash };
    let v = String(value);
    if (part === 'hash' && v && !v.startsWith('#')) v = '#' + v;
    if (part === 'search' && v && !v.startsWith('?')) v = '?' + v;
    parts[part] = v;
    el.setAttribute('href', parts.protocol + '//' + parts.host + parts.pathname + parts.search + parts.hash);
  } catch (e) {}
};
accessor(EP, 'href', function () {
  if (this.localName === 'a' || this.localName === 'area' || this.localName === 'link' || this.localName === 'base') return resolvedHref(this);
  const v = this.getAttribute('href'); return v === null ? '' : v;
}, function (v) { this.setAttribute('href', v); });
for (const part of ['hash', 'pathname', 'search', 'host', 'hostname', 'port', 'protocol', 'origin', 'username', 'password']) {
  accessor(EP, part, function () { return urlPart(this, part); }, function (v) { setUrlPart(this, part, v); });
}
accessor(EP, 'relList', function () { return (this.getAttribute('rel') || '').split(/\s+/).filter(Boolean); });
// Images and media sources resolve against the document URL.
accessor(EP, 'src', function () {
  const v = this.getAttribute('src');
  if (v === null || v === '') return '';
  try { return new URL(v, document.baseURI).href; } catch (e) { return v; }
}, function (v) { this.setAttribute('src', v); });
accessor(EP, 'currentSrc', function () { return this.src; });
accessor(EP, 'naturalWidth', function () { return 0; });
accessor(EP, 'naturalHeight', function () { return 0; });
accessor(EP, 'complete', function () { return true; });
EP.decode = function () { return Promise.reject(new DOMException('The image cannot be decoded.', 'EncodingError')); };

// Media elements: NativaX has no media pipeline; they report
// MEDIA_ERR_SRC_NOT_SUPPORTED like a browser without codecs.
const mediaState = new WeakMap();
const media = (el) => memo(mediaState, el, () => ({ paused: true, currentTime: 0, volume: 1, muted: el.hasAttribute('muted'), playbackRate: 1 }));
class MediaError { constructor(code, message) { this.code = code; this.message = message; } }
MediaError.MEDIA_ERR_ABORTED = 1; MediaError.MEDIA_ERR_NETWORK = 2; MediaError.MEDIA_ERR_DECODE = 3; MediaError.MEDIA_ERR_SRC_NOT_SUPPORTED = 4;
const isMedia = (el) => el.localName === 'video' || el.localName === 'audio';
EP.play = function () {
  if (!isMedia(this)) return undefined;
  return Promise.reject(new DOMException('The element has no supported sources.', 'NotSupportedError'));
};
EP.pause = function () { if (isMedia(this)) media(this).paused = true; };
EP.load = function () { if (isMedia(this)) setTimeout(() => this.dispatchEvent(new Event('error')), 0); };
EP.canPlayType = function () { return ''; };
EP.fastSeek = function () {};
for (const p of ['currentTime', 'volume', 'playbackRate']) {
  accessor(EP, p, function () { return isMedia(this) ? media(this)[p] : undefined; }, function (v) { if (isMedia(this)) media(this)[p] = Number(v); });
}
accessor(EP, 'paused', function () { return isMedia(this) ? true : undefined; });
accessor(EP, 'ended', function () { return isMedia(this) ? false : undefined; });
accessor(EP, 'duration', function () { return isMedia(this) ? NaN : undefined; });
accessor(EP, 'readyState', function () { return isMedia(this) ? 0 : undefined; });
accessor(EP, 'networkState', function () { return isMedia(this) ? 3 : undefined; });
accessor(EP, 'error', function () { return isMedia(this) ? new MediaError(4, 'MEDIA_ELEMENT_ERROR: Format error') : undefined; });
accessor(EP, 'videoWidth', function () { return 0; });
accessor(EP, 'videoHeight', function () { return 0; });
accessor(EP, 'buffered', function () { return { length: 0, start() { throw new DOMException('', 'IndexSizeError'); }, end() { throw new DOMException('', 'IndexSizeError'); } }; });
accessor(EP, 'textTracks', function () { return []; });

// Canvas: no 2D/WebGL backend yet.
EP.getContext = function () { return null; };
EP.toDataURL = function () { return 'data:,'; };
EP.toBlob = function (cb) { setTimeout(() => cb(null), 0); };
EP.captureStream = undefined;

// Dialog and details.
accessor(EP, 'open', function () {
  return this.localName === 'dialog' || this.localName === 'details' ? this.hasAttribute('open') : undefined;
}, function (v) { this.toggleAttribute('open', !!v); });
EP.show = function () { if (this.localName === 'dialog') host('el.call', this[ID], 'show', []); };
EP.showModal = function () { if (this.localName === 'dialog') host('el.call', this[ID], 'showModal', []); };
EP.close = function (v) { if (this.localName === 'dialog') host('el.call', this[ID], 'close', [v === undefined ? null : String(v)]); };
EP.requestClose = function () { if (this.localName === 'dialog') host('el.call', this[ID], 'requestClose', []); };
accessor(EP, 'returnValue', function () { return host('node.get', this[ID], 'returnValue'); },
  function (v) { host('node.set', this[ID], 'returnValue', String(v)); });
EP.showPopover = function () { this.toggleAttribute('hidden', false); };
EP.hidePopover = function () { this.toggleAttribute('hidden', true); };
EP.togglePopover = function () { this.toggleAttribute('hidden'); };
// Template content: the children live in the element itself.
accessor(EP, 'content', function () {
  if (this.localName !== 'template') { const v = this.getAttribute('content'); return v === null ? '' : v; }
  const frag = document.createDocumentFragment();
  for (const c of [...this.childNodes]) frag.appendChild(c.cloneNode(true));
  return frag;
});

// Node.compareDocumentPosition and tree walking.
Node.DOCUMENT_POSITION_DISCONNECTED = 1; Node.DOCUMENT_POSITION_PRECEDING = 2; Node.DOCUMENT_POSITION_FOLLOWING = 4;
Node.DOCUMENT_POSITION_CONTAINS = 8; Node.DOCUMENT_POSITION_CONTAINED_BY = 16; Node.DOCUMENT_POSITION_IMPLEMENTATION_SPECIFIC = 32;
NP.compareDocumentPosition = function (other) {
  if (other === this) return 0;
  if (this.contains(other)) return 20;
  if (other.contains(this)) return 10;
  if (this.getRootNode() !== other.getRootNode()) return 1 | 32 | 2;
  const path = (n) => { const p = []; for (; n; n = n.parentNode) p.unshift(n); return p; };
  const a = path(this), b = path(other);
  let i = 0;
  while (a[i] === b[i]) i++;
  const siblings = [...a[i - 1].childNodes];
  return siblings.indexOf(a[i]) < siblings.indexOf(b[i]) ? 4 : 2;
};
NP.lookupNamespaceURI = function () { return 'http://www.w3.org/1999/xhtml'; };
NP.isDefaultNamespace = function (ns) { return ns === 'http://www.w3.org/1999/xhtml'; };
accessor(NP, 'baseURI', function () { return document.baseURI; });
const NodeFilter = Object.freeze({
  FILTER_ACCEPT: 1, FILTER_REJECT: 2, FILTER_SKIP: 3, SHOW_ALL: 0xFFFFFFFF, SHOW_ELEMENT: 0x1,
  SHOW_ATTRIBUTE: 0x2, SHOW_TEXT: 0x4, SHOW_CDATA_SECTION: 0x8, SHOW_PROCESSING_INSTRUCTION: 0x40,
  SHOW_COMMENT: 0x80, SHOW_DOCUMENT: 0x100, SHOW_DOCUMENT_TYPE: 0x200, SHOW_DOCUMENT_FRAGMENT: 0x400,
});
const acceptNode = (filter, whatToShow, node) => {
  if (!(whatToShow & (1 << (node.nodeType - 1)))) return 3;
  if (!filter) return 1;
  return typeof filter === 'function' ? filter(node) : filter.acceptNode(node);
};
class TreeWalker {
  constructor(root, whatToShow = 0xFFFFFFFF, filter = null) { Object.assign(this, { root, whatToShow, filter, currentNode: root }); }
  _accept(n) { return acceptNode(this.filter, this.whatToShow, n); }
  parentNode() {
    for (let n = this.currentNode; n && n !== this.root;) { n = n.parentNode; if (n && this._accept(n) === 1) return (this.currentNode = n); }
    return null;
  }
  _next(n) {
    if (n.firstChild) return n.firstChild;
    for (; n && n !== this.root; n = n.parentNode) if (n.nextSibling) return n.nextSibling;
    return null;
  }
  nextNode() {
    let n = this.currentNode;
    while ((n = this._next(n))) {
      const r = this._accept(n);
      if (r === 1) return (this.currentNode = n);
    }
    return null;
  }
  previousNode() {
    let n = this.currentNode;
    while (n && n !== this.root) {
      let p = n.previousSibling;
      if (p) { while (p.lastChild) p = p.lastChild; n = p; } else n = n.parentNode;
      if (n && this._accept(n) === 1) return (this.currentNode = n);
    }
    return null;
  }
  firstChild() { for (let c = this.currentNode.firstChild; c; c = c.nextSibling) if (this._accept(c) === 1) return (this.currentNode = c); return null; }
  lastChild() { for (let c = this.currentNode.lastChild; c; c = c.previousSibling) if (this._accept(c) === 1) return (this.currentNode = c); return null; }
  nextSibling() { for (let c = this.currentNode.nextSibling; c; c = c.nextSibling) if (this._accept(c) === 1) return (this.currentNode = c); return null; }
  previousSibling() { for (let c = this.currentNode.previousSibling; c; c = c.previousSibling) if (this._accept(c) === 1) return (this.currentNode = c); return null; }
}
class NodeIterator extends TreeWalker {
  get referenceNode() { return this.currentNode; }
  get pointerBeforeReferenceNode() { return true; }
  detach() {}
}

// Specific element interfaces, all sharing the HTMLElement prototype chain.
const elementInterfaces = {
  HTMLAnchorElement: ['a'], HTMLAreaElement: ['area'], HTMLAudioElement: ['audio'], HTMLBRElement: ['br'],
  HTMLBaseElement: ['base'], HTMLBodyElement: ['body'], HTMLButtonElement: ['button'], HTMLCanvasElement: ['canvas'],
  HTMLDListElement: ['dl'], HTMLDataElement: ['data'], HTMLDataListElement: ['datalist'], HTMLDetailsElement: ['details'],
  HTMLDialogElement: ['dialog'], HTMLDirectoryElement: ['dir'], HTMLDivElement: ['div'], HTMLEmbedElement: ['embed'], HTMLFieldSetElement: ['fieldset'],
  HTMLFrameElement: ['frame'], HTMLFrameSetElement: ['frameset'], HTMLFontElement: ['font'],
  HTMLFormElement: ['form'], HTMLHRElement: ['hr'], HTMLHeadElement: ['head'],
  HTMLHeadingElement: ['h1', 'h2', 'h3', 'h4', 'h5', 'h6'], HTMLHtmlElement: ['html'], HTMLIFrameElement: ['iframe'],
  HTMLImageElement: ['img'], HTMLInputElement: ['input'], HTMLLIElement: ['li'], HTMLLabelElement: ['label'],
  HTMLLegendElement: ['legend'], HTMLLinkElement: ['link'], HTMLMapElement: ['map'], HTMLMenuElement: ['menu'],
  HTMLMetaElement: ['meta'], HTMLMeterElement: ['meter'], HTMLModElement: ['ins', 'del'], HTMLOListElement: ['ol'],
  HTMLObjectElement: ['object'], HTMLOptGroupElement: ['optgroup'], HTMLOptionElement: ['option'],
  HTMLOutputElement: ['output'], HTMLParagraphElement: ['p'], HTMLParamElement: ['param'], HTMLPictureElement: ['picture'], HTMLPreElement: ['pre'],
  HTMLMarqueeElement: ['marquee'], HTMLBaseFontElement: ['basefont'],
  HTMLProgressElement: ['progress'], HTMLQuoteElement: ['q', 'blockquote'], HTMLScriptElement: ['script'],
  HTMLSelectElement: ['select'], HTMLSlotElement: ['slot'], HTMLSourceElement: ['source'], HTMLSpanElement: ['span'],
  HTMLStyleElement: ['style'], HTMLTableCaptionElement: ['caption'], HTMLTableCellElement: ['td', 'th'],
  HTMLTableColElement: ['col', 'colgroup'], HTMLTableElement: ['table'], HTMLTableRowElement: ['tr'],
  HTMLTableSectionElement: ['thead', 'tbody', 'tfoot'], HTMLTemplateElement: ['template'],
  HTMLTextAreaElement: ['textarea'], HTMLTimeElement: ['time'], HTMLTitleElement: ['title'], HTMLTrackElement: ['track'],
  HTMLUListElement: ['ul'], HTMLUnknownElement: [],
};
class HTMLMediaElement extends HTMLElement {}
for (const k of ['NETWORK_EMPTY', 'NETWORK_IDLE', 'NETWORK_LOADING', 'NETWORK_NO_SOURCE']) HTMLMediaElement[k] = ['NETWORK_EMPTY', 'NETWORK_IDLE', 'NETWORK_LOADING', 'NETWORK_NO_SOURCE'].indexOf(k);
const interfaceClasses = { HTMLElement, HTMLMediaElement };
elementProtos = { '*': HEP };
for (const [name, tags] of Object.entries(elementInterfaces)) {
  const Base = name === 'HTMLAudioElement' || name === 'HTMLVideoElement' ? HTMLMediaElement : HTMLElement;
  const C = class extends Base {};
  defineProperty(C, 'name', { value: name });
  C.prototype[Symbol.toStringTag] = name;
  interfaceClasses[name] = C;
  for (const t of tags) elementProtos[t] = C.prototype;
}
{
  const C = class HTMLVideoElement extends HTMLMediaElement {};
  interfaceClasses.HTMLVideoElement = C;
  elementProtos.video = C.prototype;
}
// Body/Frameset event handlers forward to Window (HTML spec).
for (const proto of [interfaceClasses.HTMLBodyElement && interfaceClasses.HTMLBodyElement.prototype,
  interfaceClasses.HTMLFrameSetElement && interfaceClasses.HTMLFrameSetElement.prototype]) {
  if (!proto) continue;
  for (const name of handlerProps) {
    if (name.startsWith('webkit')) continue;
    const prop = 'on' + name;
    defineProperty(proto, prop, {
      get() { return globalThis[prop] || null; },
      set(fn) { globalThis[prop] = typeof fn === 'function' ? fn : null; },
      configurable: true, enumerable: true,
    });
  }
}
for (const name of ['HTMLBodyElement', 'HTMLFrameSetElement']) {
  const C = interfaceClasses[name];
  if (C && !globalThis[name]) hidden(globalThis, name, C);
}
for (const t of ['abbr', 'address', 'article', 'aside', 'b', 'bdi', 'bdo', 'cite', 'code', 'dd', 'dfn', 'dt', 'em',
  'figcaption', 'figure', 'footer', 'header', 'hgroup', 'i', 'kbd', 'main', 'mark', 'nav', 'noscript', 'rp', 'rt',
  'ruby', 's', 'samp', 'search', 'section', 'small', 'strong', 'sub', 'summary', 'sup', 'u', 'var', 'wbr']) elementProtos[t] = HEP;
class SVGElement extends Element {}
class SVGGraphicsElement extends SVGElement {
  getBBox() { const b = layoutBox(this); return new DOMRect(0, 0, b.width, b.height); }
  getCTM() { return null; }
  getScreenCTM() { return null; }
}
class SVGSVGElement extends SVGGraphicsElement {}
interfaceClasses.SVGElement = SVGElement;
interfaceClasses.SVGGraphicsElement = SVGGraphicsElement;
interfaceClasses.SVGSVGElement = SVGSVGElement;
for (const t of ['circle', 'rect', 'path', 'line', 'polyline', 'polygon', 'ellipse', 'g', 'text', 'tspan', 'use',
  'image', 'defs', 'symbol', 'clippath', 'mask', 'pattern', 'lineargradient', 'radialgradient', 'stop', 'filter',
  'foreignobject', 'marker', 'title', 'desc']) {
  if (t === 'title') continue;
  elementProtos[t] = SVGGraphicsElement.prototype;
}
elementProtos.svg = SVGSVGElement.prototype;
// Elements created through createElementNS(svg) or inside <svg> are SVG.
accessor(SVGElement.prototype, 'namespaceURI', function () { return 'http://www.w3.org/2000/svg'; });
accessor(SVGElement.prototype, 'ownerSVGElement', function () { return this.closest('svg') === this ? null : this.closest('svg'); });
accessor(SVGElement.prototype, 'className', function () { const v = this.getAttribute('class') || ''; return { baseVal: v, animVal: v }; });
accessor(SVGElement.prototype, 'dataset', Object.getOwnPropertyDescriptor(EP, 'dataset').get);

// Custom elements (autonomous). Upgrades happen when a wrapper is created
// for an element with a registered name; lifecycle callbacks are driven by
// an internal mutation observer.
const customRegistry = new Map();       // name -> { name, ctor, observed }
const customRegistryByCtor = new Map(); // ctor -> def
const upgrading = [];
const upgraded = new WeakSet();
const connectedSet = new WeakSet();
const whenDefined = new Map();
const callLifecycle = (el, name, ...args) => {
  const fn = el[name];
  if (typeof fn === 'function') { try { fn.apply(el, args); } catch (e) { reportError(e); } }
};
const upgradeElement = (el, def) => {
  if (upgraded.has(el)) return;
  upgraded.add(el);
  Object.setPrototypeOf(el, def.ctor.prototype);
  upgrading.push(el);
  try {
    const r = new def.ctor();
    if (r !== el) throw new DOMException('custom element constructor did not return the element', 'InvalidStateError');
  } catch (e) {
    reportError(e);
  } finally {
    const i = upgrading.indexOf(el);
    if (i >= 0) upgrading.splice(i, 1);
  }
  for (const a of def.observed) {
    if (el.hasAttribute(a)) callLifecycle(el, 'attributeChangedCallback', a, null, el.getAttribute(a));
  }
  if (el.isConnected) { connectedSet.add(el); callLifecycle(el, 'connectedCallback'); }
};
upgradeHook = (w, localName) => {
  const def = customRegistry.get(localName);
  if (def && !upgrading.includes(w)) upgradeElement(w, def);
};
const customElements = {
  define(name, ctor, options) {
    name = String(name);
    if (!/^[a-z][a-z0-9._·À-￿]*-[a-z0-9._\-·À-￿]*$/.test(name)) {
      throw new DOMException(`"${name}" is not a valid custom element name`, 'SyntaxError');
    }
    if (customRegistry.has(name)) throw new DOMException(`"${name}" has already been defined`, 'NotSupportedError');
    if (typeof ctor !== 'function') throw new TypeError('constructor must be a function');
    const observed = Array.isArray(ctor.observedAttributes) ? ctor.observedAttributes.map(String) : [];
    const def = { name, ctor, observed };
    customRegistry.set(name, def);
    customRegistryByCtor.set(ctor, def);
    host('custom.define', name);
    ensureLifecycleObserver();
    for (const el of document.querySelectorAll(name)) upgradeElement(el, def);
    const waiting = whenDefined.get(name);
    if (waiting) { waiting.resolve(ctor); }
  },
  get(name) { const d = customRegistry.get(String(name)); return d ? d.ctor : undefined; },
  getName(ctor) { const d = customRegistryByCtor.get(ctor); return d ? d.name : null; },
  whenDefined(name) {
    name = String(name);
    const d = customRegistry.get(name);
    if (d) return Promise.resolve(d.ctor);
    let w = whenDefined.get(name);
    if (!w) { let resolve; const promise = new Promise((r) => { resolve = r; }); w = { promise, resolve }; whenDefined.set(name, w); }
    return w.promise;
  },
  upgrade(root) { for (const el of [root, ...root.querySelectorAll('*')]) { const d = customRegistry.get(el.localName); if (d) upgradeElement(el, d); } },
};
let lifecycleObserver = null;
const ensureLifecycleObserver = () => {
  if (lifecycleObserver) return;
  lifecycleObserver = new MutationObserver((records) => {
    for (const r of records) {
      if (r.type === 'attributes') {
        const el = r.target;
        const def = customRegistryByCtor.get(el.constructor);
        if (def && def.observed.includes(r.attributeName)) {
          callLifecycle(el, 'attributeChangedCallback', r.attributeName, r.oldValue, el.getAttribute(r.attributeName));
        }
        continue;
      }
      const visit = (n, added) => {
        if (n.nodeType !== 1) return;
        for (const el of [n, ...n.querySelectorAll('*')]) {
          const def = customRegistry.get(el.localName);
          if (!def) continue;
          if (!upgraded.has(el)) upgradeElement(el, def);
          if (added && el.isConnected && !connectedSet.has(el)) { connectedSet.add(el); callLifecycle(el, 'connectedCallback'); }
          if (!added && !el.isConnected && connectedSet.has(el)) { connectedSet.delete(el); callLifecycle(el, 'disconnectedCallback'); }
        }
      };
      for (const n of r.addedNodes) visit(n, true);
      for (const n of r.removedNodes) visit(n, false);
    }
  });
  lifecycleObserver.observe(document, { childList: true, subtree: true, attributes: true, attributeOldValue: true });
};
''';
