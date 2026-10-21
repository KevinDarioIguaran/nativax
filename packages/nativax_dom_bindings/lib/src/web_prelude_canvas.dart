/// `CanvasRenderingContext2D`: state lives here (for getters), drawing
/// commands are recorded and flushed to the host once per microtask.
const String webCanvas = r'''
// ============================================================================
// Canvas 2D
// ============================================================================
const canvasContexts = new WeakMap();
class CanvasGradient {
  constructor(kind, args) { hidden(this, '_g', { kind, args, stops: [] }); }
  addColorStop(offset, color) {
    const o = Number(offset);
    if (!(o >= 0 && o <= 1)) throw new DOMException('The provided value is outside the range [0, 1].', 'IndexSizeError');
    this._g.stops.push([o, String(color)]);
  }
}
class CanvasPattern { constructor() { hidden(this, '_p', true); } setTransform() {} }
class ImageData {
  constructor(a, b, c) {
    let data, w, h;
    if (a instanceof Uint8ClampedArray) { data = a; w = b; h = c ?? a.length / 4 / b; }
    else { w = a; h = b; data = new Uint8ClampedArray(w * h * 4); }
    Object.assign(this, { data, width: w, height: h, colorSpace: 'srgb' });
  }
}
class TextMetrics {}
class Path2D {
  constructor(src) {
    hidden(this, '_ops', []);
    if (src instanceof Path2D) this._ops.push(...src._ops);
    else if (typeof src === 'string') this._ops.push(['svgPath', src]);
  }
  addPath(p) { this._ops.push(...p._ops); }
}
for (const m of ['moveTo', 'lineTo', 'bezierCurveTo', 'quadraticCurveTo', 'arc', 'arcTo', 'ellipse', 'rect', 'roundRect', 'closePath']) {
  Path2D.prototype[m] = function (...args) { this._ops.push([m, ...args.map((v) => (Array.isArray(v) ? v : (typeof v === 'object' && v !== null ? v : Number(v))))]); };
}
const styleOp = (v) => {
  if (v instanceof CanvasGradient) return { gradient: v._g.kind, args: v._g.args, stops: v._g.stops.slice() };
  if (v instanceof CanvasPattern) return '#000000';
  return String(v);
};
const defaultCanvasState = () => ({
  fillStyle: '#000000', strokeStyle: '#000000', lineWidth: 1, lineCap: 'butt', lineJoin: 'miter', miterLimit: 10,
  font: '10px sans-serif', textAlign: 'start', textBaseline: 'alphabetic', direction: 'inherit', globalAlpha: 1,
  globalCompositeOperation: 'source-over', shadowColor: 'rgba(0, 0, 0, 0)', shadowBlur: 0, shadowOffsetX: 0,
  shadowOffsetY: 0, lineDash: [], lineDashOffset: 0, imageSmoothingEnabled: true, imageSmoothingQuality: 'low',
  filter: 'none', letterSpacing: '0px', wordSpacing: '0px', fontKerning: 'auto',
  transform: [1, 0, 0, 1, 0, 0],
});
class CanvasRenderingContext2D {
  constructor(canvas) {
    hidden(this, 'canvas', canvas);
    hidden(this, '_s', defaultCanvasState());
    hidden(this, '_stack', []);
    hidden(this, '_ops', []);
    hidden(this, '_pending', { v: false });
  }
  _op(...op) {
    this._ops.push(op);
    if (!this._pending.v) {
      this._pending.v = true;
      queueMicrotask(() => this._flush());
    }
  }
  _flush() {
    this._pending.v = false;
    if (this._ops.length === 0) return;
    const ops = this._ops.splice(0, this._ops.length);
    host('canvas.draw', this.canvas[ID], this.canvas.width, this.canvas.height, ops);
  }
  _reset() {
    Object.assign(this._s, defaultCanvasState());
    this._stack.length = 0;
    this._ops.length = 0;
    this._op('reset');
  }
  getContextAttributes() { return { alpha: true, colorSpace: 'srgb', desynchronized: false, willReadFrequently: false }; }
  save() { this._stack.push(Object.assign({}, this._s, { transform: this._s.transform.slice(), lineDash: this._s.lineDash.slice() })); this._op('save'); }
  restore() { const s = this._stack.pop(); if (s) { Object.assign(this._s, s); this._op('restore'); } }
  reset() { this._reset(); }
  isContextLost() { return false; }
  // Transforms (tracked here for getTransform, replayed by the host).
  _mul(a, b, c, d, e, f) {
    const [A, B, C, D, E, F] = this._s.transform;
    this._s.transform = [A * a + C * b, B * a + D * b, A * c + C * d, B * c + D * d, A * e + C * f + E, B * e + D * f + F];
    this._op('setTransform', ...this._s.transform);
  }
  scale(x, y) { this._mul(x, 0, 0, y, 0, 0); }
  rotate(r) { const c = Math.cos(r), s = Math.sin(r); this._mul(c, s, -s, c, 0, 0); }
  translate(x, y) { this._mul(1, 0, 0, 1, x, y); }
  transform(a, b, c, d, e, f) { this._mul(a, b, c, d, e, f); }
  setTransform(a = 1, b = 0, c = 0, d = 1, e = 0, f = 0) {
    if (typeof a === 'object' && a !== null) ({ a = 1, b = 0, c = 0, d = 1, e = 0, f = 0 } = a);
    this._s.transform = [a, b, c, d, e, f].map(Number);
    this._op('setTransform', ...this._s.transform);
  }
  resetTransform() { this.setTransform(1, 0, 0, 1, 0, 0); }
  getTransform() { const [a, b, c, d, e, f] = this._s.transform; return { a, b, c, d, e, f, m11: a, m12: b, m21: c, m22: d, m41: e, m42: f, is2D: true, isIdentity: a === 1 && b === 0 && c === 0 && d === 1 && e === 0 && f === 0 }; }
  // Styles.
  createLinearGradient(x0, y0, x1, y1) { return new CanvasGradient('linear', [x0, y0, x1, y1].map(Number)); }
  createRadialGradient(x0, y0, r0, x1, y1, r1) { return new CanvasGradient('radial', [x0, y0, r0, x1, y1, r1].map(Number)); }
  createConicGradient(a, x, y) { return new CanvasGradient('conic', [a, x, y].map(Number)); }
  createPattern() { return new CanvasPattern(); }
  setLineDash(segs) { const d = [...segs].map(Number); if (d.some((x) => !(x >= 0))) return; this._s.lineDash = d.length % 2 ? [...d, ...d] : d; this._op('set', 'lineDash', this._s.lineDash); }
  getLineDash() { return this._s.lineDash.slice(); }
  // Rectangles.
  clearRect(x, y, w, h) { this._op('clearRect', +x, +y, +w, +h); }
  fillRect(x, y, w, h) { this._op('fillRect', +x, +y, +w, +h); }
  strokeRect(x, y, w, h) { this._op('strokeRect', +x, +y, +w, +h); }
  // Paths.
  beginPath() { this._op('beginPath'); }
  closePath() { this._op('closePath'); }
  moveTo(x, y) { this._op('moveTo', +x, +y); }
  lineTo(x, y) { this._op('lineTo', +x, +y); }
  bezierCurveTo(a, b, c, d, e, f) { this._op('bezierCurveTo', +a, +b, +c, +d, +e, +f); }
  quadraticCurveTo(a, b, c, d) { this._op('quadraticCurveTo', +a, +b, +c, +d); }
  arc(x, y, r, s, e, ccw = false) {
    if (r < 0) throw new DOMException('The radius provided is negative.', 'IndexSizeError');
    this._op('arc', +x, +y, +r, +s, +e, !!ccw);
  }
  arcTo(x1, y1, x2, y2, r) { this._op('arcTo', +x1, +y1, +x2, +y2, +r); }
  ellipse(x, y, rx, ry, rot, s, e, ccw = false) { this._op('ellipse', +x, +y, +rx, +ry, +rot, +s, +e, !!ccw); }
  rect(x, y, w, h) { this._op('rect', +x, +y, +w, +h); }
  roundRect(x, y, w, h, radii = 0) { this._op('roundRect', +x, +y, +w, +h, Array.isArray(radii) ? radii.map(Number) : [Number(radii)]); }
  _pathArgs(a, b) { return a instanceof Path2D ? [a._ops, b === undefined ? 'nonzero' : String(b)] : [null, a === undefined ? 'nonzero' : String(a)]; }
  fill(a, b) { this._op('fill', ...this._pathArgs(a, b)); }
  stroke(p) { this._op('stroke', p instanceof Path2D ? p._ops : null); }
  clip(a, b) { this._op('clip', ...this._pathArgs(a, b)); }
  isPointInPath() { return false; }
  isPointInStroke() { return false; }
  // Text.
  fillText(t, x, y, maxWidth) { this._op('fillText', String(t), +x, +y, maxWidth === undefined ? null : +maxWidth); }
  strokeText(t, x, y, maxWidth) { this._op('strokeText', String(t), +x, +y, maxWidth === undefined ? null : +maxWidth); }
  measureText(t) {
    const m = host('canvas.measure', this._s.font, String(t));
    const r = Object.create(TextMetrics.prototype);
    Object.assign(r, {
      width: m.width, actualBoundingBoxLeft: 0, actualBoundingBoxRight: m.width, actualBoundingBoxAscent: m.ascent,
      actualBoundingBoxDescent: m.descent, fontBoundingBoxAscent: m.ascent, fontBoundingBoxDescent: m.descent,
      emHeightAscent: m.ascent, emHeightDescent: m.descent, alphabeticBaseline: 0, hangingBaseline: m.ascent * 0.8,
      ideographicBaseline: -m.descent,
    });
    return r;
  }
  // Images and pixels.
  drawImage(img, ...args) {
    if (img instanceof Element && img.localName === 'canvas') this._op('drawCanvas', img[ID], ...args.map(Number));
  }
  createImageData(a, b) { return a instanceof ImageData ? new ImageData(a.width, a.height) : new ImageData(Math.abs(a), Math.abs(b)); }
  getImageData(x, y, w, h) { return new ImageData(Math.abs(w), Math.abs(h)); }
  putImageData(data, x, y) { this._op('putImageData', +x, +y, data.width, data.height, bytesToBase64(new Uint8Array(data.data.buffer))); }
  drawFocusIfNeeded() {}
  scrollPathIntoView() {}
}
const stateProps = {
  fillStyle: (v) => (v instanceof CanvasGradient || v instanceof CanvasPattern ? v : String(v)),
  strokeStyle: (v) => (v instanceof CanvasGradient || v instanceof CanvasPattern ? v : String(v)),
  lineWidth: (v) => (Number(v) > 0 && Number.isFinite(+v) ? +v : undefined),
  lineCap: (v) => (['butt', 'round', 'square'].includes(v) ? v : undefined),
  lineJoin: (v) => (['miter', 'round', 'bevel'].includes(v) ? v : undefined),
  miterLimit: (v) => (Number(v) > 0 ? +v : undefined),
  font: (v) => String(v),
  textAlign: (v) => (['start', 'end', 'left', 'right', 'center'].includes(v) ? v : undefined),
  textBaseline: (v) => (['top', 'hanging', 'middle', 'alphabetic', 'ideographic', 'bottom'].includes(v) ? v : undefined),
  direction: (v) => String(v),
  globalAlpha: (v) => (Number(v) >= 0 && Number(v) <= 1 ? +v : undefined),
  globalCompositeOperation: (v) => String(v),
  shadowColor: (v) => String(v),
  shadowBlur: (v) => (Number(v) >= 0 ? +v : undefined),
  shadowOffsetX: (v) => (Number.isFinite(+v) ? +v : undefined),
  shadowOffsetY: (v) => (Number.isFinite(+v) ? +v : undefined),
  lineDashOffset: (v) => (Number.isFinite(+v) ? +v : undefined),
  imageSmoothingEnabled: (v) => !!v,
  imageSmoothingQuality: (v) => String(v),
  filter: (v) => String(v),
  letterSpacing: (v) => String(v),
  wordSpacing: (v) => String(v),
  fontKerning: (v) => String(v),
};
for (const [name, norm] of Object.entries(stateProps)) {
  defineProperty(CanvasRenderingContext2D.prototype, name, {
    get() { return this._s[name]; },
    set(v) {
      const n = norm(v);
      if (n === undefined) return;
      this._s[name] = n;
      this._op('set', name, name === 'fillStyle' || name === 'strokeStyle' ? styleOp(n) : n);
    },
    configurable: true, enumerable: true,
  });
}
EP.getContext = function (type) {
  if (this.localName !== 'canvas') return undefined;
  if (String(type) !== '2d') return null;
  let ctx = canvasContexts.get(this);
  if (!ctx) { ctx = new CanvasRenderingContext2D(this); canvasContexts.set(this, ctx); }
  return ctx;
};
// Setting width/height clears the bitmap and resets the context.
for (const dim of ['width', 'height']) {
  const desc = Object.getOwnPropertyDescriptor(EP, dim);
  defineProperty(EP, dim, {
    get: desc.get,
    set(v) {
      desc.set.call(this, v);
      if (this.localName === 'canvas') { const ctx = canvasContexts.get(this); if (ctx) ctx._reset(); }
    },
    configurable: true, enumerable: true,
  });
}
EP.toDataURL = function () { return 'data:,'; };
for (const [name, value] of Object.entries({ CanvasRenderingContext2D, CanvasGradient, CanvasPattern, ImageData, TextMetrics, Path2D })) {
  defineProperty(globalThis, name, { value, enumerable: false, writable: true, configurable: true });
}
''';
