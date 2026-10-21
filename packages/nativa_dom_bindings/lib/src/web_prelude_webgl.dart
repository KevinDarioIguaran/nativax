import 'web_prelude_webgl_constants.dart';

/// WebGL 1/2, OffscreenCanvas, ImageBitmap and createImageBitmap (part of
/// the web platform prelude, in windows and workers). Every GL call goes
/// from script straight to the native implementation (`__nx.gl`, OpenGL ES
/// 3 through EGL); frames are presented to the canvas surface after each
/// task that drew.
const String webGl = webGlConstants + r'''
// ============================================================================
// ImageBitmap (decoded RGBA8 in native memory; transferable without copies)
// ============================================================================
const glNative = __nx.gl;
const bitmapToken = Symbol('bitmap');
// Host image sources (img/video/2D canvas elements) expose their pixels
// through this symbol: () => { pixels: Uint8Array RGBA8, width, height }.
const sourceBitmap = Symbol('nativax.sourceBitmap');
const bitmapCleanup = new FinalizationRegistry((id) => { if (glNative) glNative.bitmapFree(id); });
class ImageBitmap {
  constructor(token, id, width, height) {
    if (token !== bitmapToken) throw new TypeError('Illegal constructor');
    hidden(this, '_b', { id, width, height, closed: false });
    bitmapCleanup.register(this, id, this);
  }
  get width() { return this._b.closed ? 0 : this._b.width; }
  get height() { return this._b.closed ? 0 : this._b.height; }
  close() {
    const b = this._b;
    if (b.closed) return;
    b.closed = true;
    bitmapCleanup.unregister(this);
    glNative.bitmapFree(b.id);
  }
}
const newBitmap = (id, w, h) => new ImageBitmap(bitmapToken, id, w, h);
transferables.set('ImageBitmap', {
  test: (v) => v instanceof ImageBitmap,
  write(v, transfer) {
    const b = v._b;
    if (b.closed) throw new DOMException('An ImageBitmap is detached and could not be cloned.', 'DataCloneError');
    if (!transfer) {
      const px = glNative.bitmapPixels(b.id);
      return [glNative.bitmapFromPixels(px, b.width, b.height, false, false), b.width, b.height];
    }
    b.closed = true;
    bitmapCleanup.unregister(v);
    return [b.id, b.width, b.height];
  },
  read: ([id, w, h]) => newBitmap(id, w, h),
});

const cropPixels = (px, w, h, sx, sy, sw, sh) => {
  const out = new Uint8Array(sw * sh * 4);
  for (let y = 0; y < sh; y++) {
    const yy = sy + y;
    if (yy < 0 || yy >= h) continue;
    for (let x = 0; x < sw; x++) {
      const xx = sx + x;
      if (xx < 0 || xx >= w) continue;
      out.set(px.subarray((yy * w + xx) * 4, (yy * w + xx) * 4 + 4), (y * sw + x) * 4);
    }
  }
  return out;
};
const resizePixels = (px, w, h, nw, nh) => {
  const out = new Uint8Array(nw * nh * 4);
  for (let y = 0; y < nh; y++) {
    const sy = Math.min(h - 1, Math.floor((y + 0.5) * h / nh));
    for (let x = 0; x < nw; x++) {
      const sx = Math.min(w - 1, Math.floor((x + 0.5) * w / nw));
      out.set(px.subarray((sy * w + sx) * 4, (sy * w + sx) * 4 + 4), (y * nw + x) * 4);
    }
  }
  return out;
};
const createImageBitmap = (source, ...rest) => new Promise((resolve, reject) => {
  if (!glNative) { reject(new DOMException('createImageBitmap is not available', 'NotSupportedError')); return; }
  let crop = null, options = {};
  if (rest.length >= 4) { crop = rest.slice(0, 4).map((n) => Math.trunc(Number(n))); options = rest[4] || {}; }
  else options = rest[0] || {};
  if (crop && (crop[2] === 0 || crop[3] === 0)) { reject(new RangeError('The crop rect width or height is 0.')); return; }
  const flip = options.imageOrientation === 'flipY';
  const premultiply = options.premultiplyAlpha === 'premultiply';
  const finish = (id, w, h) => {
    const needCrop = crop !== null;
    const rw = options.resizeWidth, rh = options.resizeHeight;
    if (!needCrop && !rw && !rh) { resolve(newBitmap(id, w, h)); return; }
    let px = glNative.bitmapPixels(id);
    glNative.bitmapFree(id);
    let cw = w, ch = h;
    if (needCrop) {
      let [sx, sy, sw, sh] = crop;
      if (sw < 0) { sx += sw; sw = -sw; }
      if (sh < 0) { sy += sh; sh = -sh; }
      px = cropPixels(px, w, h, sx, sy, sw, sh); cw = sw; ch = sh;
    }
    const nw = rw ? Math.trunc(rw) : (rh ? Math.round(cw * rh / ch) : cw);
    const nh = rh ? Math.trunc(rh) : (rw ? Math.round(ch * rw / cw) : ch);
    if (nw !== cw || nh !== ch) px = resizePixels(px, cw, ch, nw, nh);
    resolve(newBitmap(glNative.bitmapFromPixels(px, nw, nh, false, false), nw, nh));
  };
  try {
    if (source instanceof Blob) {
      const r = glNative.decodeImage(source.__bytes(), flip, premultiply);
      if (!r) { reject(new DOMException('The source image could not be decoded.', 'InvalidStateError')); return; }
      finish(r[0], r[1], r[2]);
    } else if (source instanceof ImageBitmap) {
      if (source._b.closed) { reject(new DOMException('The image source is detached.', 'InvalidStateError')); return; }
      const b = source._b;
      finish(glNative.bitmapFromPixels(glNative.bitmapPixels(b.id), b.width, b.height, flip, premultiply), b.width, b.height);
    } else if (typeof ImageData !== 'undefined' && source instanceof ImageData) {
      finish(glNative.bitmapFromPixels(source.data, source.width, source.height, flip, premultiply), source.width, source.height);
    } else if (source instanceof OffscreenCanvas && source._oc.ctx && source._oc.ctx._h) {
      const c = source._oc.ctx, w = c.drawingBufferWidth, h = c.drawingBufferHeight;
      const px = new Uint8Array(w * h * 4);
      c.readPixels(0, 0, w, h, 0x1908, 0x1401, px);
      // GL rows are bottom-up.
      finish(glNative.bitmapFromPixels(px, w, h, !flip, premultiply), w, h);
    } else {
      reject(new DOMException('createImageBitmap: unsupported source', 'NotSupportedError'));
    }
  } catch (e) { reject(e); }
});

// ============================================================================
// WebGL objects
// ============================================================================
class WebGLObject { constructor(ctx, name) { hidden(this, '_ctx', ctx); defineProperty(this, '_n', { value: name, writable: true }); } }
class WebGLBuffer extends WebGLObject {}
class WebGLTexture extends WebGLObject {}
class WebGLProgram extends WebGLObject {}
class WebGLShader extends WebGLObject {}
class WebGLFramebuffer extends WebGLObject {}
class WebGLRenderbuffer extends WebGLObject {}
class WebGLVertexArrayObject extends WebGLObject {}
class WebGLQuery extends WebGLObject {}
class WebGLSampler extends WebGLObject {}
class WebGLSync extends WebGLObject {}
class WebGLTransformFeedback extends WebGLObject {}
class WebGLUniformLocation { constructor(program, loc) { hidden(this, '_p', program); hidden(this, '_l', loc); } }
class WebGLActiveInfo { constructor(name, size, type) { Object.assign(this, { name, size, type }); } }
class WebGLShaderPrecisionFormat { constructor(a) { Object.assign(this, { rangeMin: a[0], rangeMax: a[1], precision: a[2] }); } }
const WebGLContextEvent = defineEventClass('WebGLContextEvent', Event, { statusMessage: '' });

const nameOf = (o) => (o ? o._n : 0);
const isView = (v) => ArrayBuffer.isView(v);

// getParameter result kinds by pname (everything else is a GLint).
const P = GL_CONSTANTS;
const paramKinds = new Map([
  ...[P.VENDOR, P.RENDERER, P.VERSION, P.SHADING_LANGUAGE_VERSION].map((p) => [p, 'string']),
  [P.ARRAY_BUFFER_BINDING, 'buffer'], [P.ELEMENT_ARRAY_BUFFER_BINDING, 'buffer'], [P.COPY_READ_BUFFER_BINDING, 'buffer'],
  [P.COPY_WRITE_BUFFER_BINDING, 'buffer'], [P.PIXEL_PACK_BUFFER_BINDING, 'buffer'], [P.PIXEL_UNPACK_BUFFER_BINDING, 'buffer'],
  [P.TRANSFORM_FEEDBACK_BUFFER_BINDING, 'buffer'], [P.UNIFORM_BUFFER_BINDING, 'buffer'],
  [P.CURRENT_PROGRAM, 'program'], [P.FRAMEBUFFER_BINDING, 'drawFramebuffer'], [P.READ_FRAMEBUFFER_BINDING, 'readFramebuffer'],
  [P.RENDERBUFFER_BINDING, 'renderbuffer'], [P.TEXTURE_BINDING_2D, 'texture'], [P.TEXTURE_BINDING_CUBE_MAP, 'texture'],
  [P.TEXTURE_BINDING_3D, 'texture'], [P.TEXTURE_BINDING_2D_ARRAY, 'texture'], [P.VERTEX_ARRAY_BINDING, 'vertexArray'],
  [P.SAMPLER_BINDING, 'sampler'], [P.TRANSFORM_FEEDBACK_BINDING, 'transformFeedback'],
  [P.VIEWPORT, 'i4'], [P.SCISSOR_BOX, 'i4'], [P.MAX_VIEWPORT_DIMS, 'i2'],
  [P.COLOR_CLEAR_VALUE, 'f4'], [P.BLEND_COLOR, 'f4'], [P.DEPTH_RANGE, 'f2'], [P.ALIASED_LINE_WIDTH_RANGE, 'f2'], [P.ALIASED_POINT_SIZE_RANGE, 'f2'],
  [P.COLOR_WRITEMASK, 'b4'],
  ...[P.BLEND, P.CULL_FACE, P.DEPTH_TEST, P.DITHER, P.POLYGON_OFFSET_FILL, P.SAMPLE_ALPHA_TO_COVERAGE, P.SAMPLE_COVERAGE,
    P.SCISSOR_TEST, P.STENCIL_TEST, P.DEPTH_WRITEMASK, P.SAMPLE_COVERAGE_INVERT, P.RASTERIZER_DISCARD,
    P.TRANSFORM_FEEDBACK_ACTIVE, P.TRANSFORM_FEEDBACK_PAUSED].map((p) => [p, 'bool']),
  ...[P.DEPTH_CLEAR_VALUE, P.LINE_WIDTH, P.POLYGON_OFFSET_FACTOR, P.POLYGON_OFFSET_UNITS, P.SAMPLE_COVERAGE_VALUE,
    P.MAX_TEXTURE_LOD_BIAS, 0x84FE, 0x84FF].map((p) => [p, 'float']),
  ...[P.MAX_ELEMENT_INDEX, P.MAX_SERVER_WAIT_TIMEOUT, P.MAX_UNIFORM_BLOCK_SIZE, P.MAX_COMBINED_VERTEX_UNIFORM_COMPONENTS,
    P.MAX_COMBINED_FRAGMENT_UNIFORM_COMPONENTS].map((p) => [p, 'i64']),
]);

// WebGL extension -> GLES extension it needs (null: always available).
const webgl2Extensions = {
  EXT_color_buffer_float: 'GL_EXT_color_buffer_float',
  EXT_color_buffer_half_float: 'GL_EXT_color_buffer_half_float',
  EXT_float_blend: 'GL_EXT_float_blend',
  OES_texture_float_linear: 'GL_OES_texture_float_linear',
  EXT_texture_filter_anisotropic: 'GL_EXT_texture_filter_anisotropic',
  EXT_texture_norm16: 'GL_EXT_texture_norm16',
  WEBGL_compressed_texture_s3tc: 'GL_EXT_texture_compression_s3tc',
  WEBGL_compressed_texture_s3tc_srgb: 'GL_EXT_texture_compression_s3tc_srgb',
  WEBGL_compressed_texture_astc: 'GL_KHR_texture_compression_astc_ldr',
  EXT_texture_compression_bptc: 'GL_EXT_texture_compression_bptc',
  EXT_texture_compression_rgtc: 'GL_EXT_texture_compression_rgtc',
  WEBGL_compressed_texture_etc: null,
  WEBGL_debug_renderer_info: null,
  WEBGL_lose_context: null,
  KHR_parallel_shader_compile: null,
  WEBGL_multi_draw: null,
  EXT_disjoint_timer_query_webgl2: 'GL_EXT_disjoint_timer_query',
};
const webgl1Extensions = Object.assign({}, webgl2Extensions, {
  ANGLE_instanced_arrays: null, OES_vertex_array_object: null, OES_element_index_uint: null, OES_standard_derivatives: null,
  OES_texture_float: null, OES_texture_half_float: null, OES_texture_half_float_linear: null, WEBGL_depth_texture: null,
  EXT_blend_minmax: null, EXT_shader_texture_lod: null, EXT_frag_depth: null, WEBGL_draw_buffers: null, EXT_sRGB: null,
  WEBGL_color_buffer_float: 'GL_EXT_color_buffer_float',
});
delete webgl1Extensions.EXT_color_buffer_float;
delete webgl1Extensions.EXT_disjoint_timer_query_webgl2;

// Contexts that drew during this task; presented in a microtask (after the
// task's script, e.g. a requestAnimationFrame callback, completes).
const drawnContexts = new Set();
let presentQueued = false;
const presentDrawn = () => {
  presentQueued = false;
  for (const c of drawnContexts) { if (c._h) glNative.present(c._h); }
  drawnContexts.clear();
};

class WebGL2RenderingContextImpl {
  constructor(canvas, version, attrs, surface, width, height) {
    const a = Object.assign({ alpha: true, depth: true, stencil: false, antialias: true, premultipliedAlpha: true,
      preserveDrawingBuffer: false, powerPreference: 'default', failIfMajorPerformanceCaveat: false, desynchronized: false }, attrs || {});
    const h = glNative.createContext(surface, version, !!a.alpha, !!a.depth, !!a.stencil, !!a.antialias, !!a.premultipliedAlpha,
      !!a.preserveDrawingBuffer, width, height);
    hidden(this, '_h', h);
    hidden(this, '_canvas', canvas);
    hidden(this, '_attrs', { alpha: !!a.alpha, depth: !!a.depth, stencil: !!a.stencil, antialias: !!a.antialias,
      premultipliedAlpha: !!a.premultipliedAlpha, preserveDrawingBuffer: !!a.preserveDrawingBuffer,
      powerPreference: a.powerPreference, failIfMajorPerformanceCaveat: false, desynchronized: false, xrCompatible: false });
    hidden(this, '_v', version);
    hidden(this, '_size', { w: width, h: height });
    hidden(this, '_o', { buffer: new Map(), texture: new Map(), program: new Map(), framebuffer: new Map(), renderbuffer: new Map(),
      vertexArray: new Map(), sampler: new Map(), transformFeedback: new Map(), query: new Map() });
    hidden(this, '_st', { lost: false, flipY: false, premultiply: false, colorspace: P.BROWSER_DEFAULT_WEBGL, ext: new Map(),
      gles: null, drawFb: null, readFb: null });
    defineProperty(this, 'drawingBufferColorSpace', { value: 'srgb', writable: true, enumerable: true });
    defineProperty(this, 'unpackColorSpace', { value: 'srgb', writable: true, enumerable: true });
  }
  get canvas() { return this._canvas; }
  get drawingBufferWidth() { return this._size.w; }
  get drawingBufferHeight() { return this._size.h; }
  get drawingBufferFormat() { return P.RGBA8; }
  _resize(w, h) {
    w = Math.max(1, w | 0); h = Math.max(1, h | 0);
    if (w === this._size.w && h === this._size.h) return;
    this._size.w = w; this._size.h = h;
    if (this._h) glNative.resize(this._h, w, h);
  }
  _drew() {
    drawnContexts.add(this);
    if (!presentQueued) { presentQueued = true; queueMicrotask(presentDrawn); }
  }
  _track(kind, obj) { this._o[kind].set(obj._n, obj); return obj; }
  getContextAttributes() { return this._st.lost ? null : Object.assign({}, this._attrs); }
  isContextLost() { return this._st.lost; }
  makeXRCompatible() { return Promise.resolve(); }
  _glesExtensions() { if (!this._st.gles) this._st.gles = new Set(glNative.getExtensions(this._h)); return this._st.gles; }
  getSupportedExtensions() {
    if (this._st.lost) return null;
    const table = this._v === 2 ? webgl2Extensions : webgl1Extensions;
    const gles = this._glesExtensions();
    return Object.keys(table).filter((k) => table[k] === null || gles.has(table[k]));
  }
  getExtension(name) {
    name = String(name);
    const key = Object.keys(this._v === 2 ? webgl2Extensions : webgl1Extensions).find((k) => k.toLowerCase() === name.toLowerCase());
    if (!key || !this.getSupportedExtensions().includes(key)) return null;
    let ext = this._st.ext.get(key);
    if (!ext) { ext = makeExtension(this, key); this._st.ext.set(key, ext); }
    return ext;
  }
  // ---- state ---------------------------------------------------------------
  activeTexture(t) { glNative.activeTexture(this._h, t); }
  blendColor(r, g, b, a) { glNative.blendColor(this._h, r, g, b, a); }
  blendEquation(m) { glNative.blendEquation(this._h, m); }
  blendEquationSeparate(a, b) { glNative.blendEquationSeparate(this._h, a, b); }
  blendFunc(s, d) { glNative.blendFunc(this._h, s, d); }
  blendFuncSeparate(a, b, c, d) { glNative.blendFuncSeparate(this._h, a, b, c, d); }
  clearColor(r, g, b, a) { glNative.clearColor(this._h, r, g, b, a); }
  clearDepth(d) { glNative.clearDepth(this._h, d); }
  clearStencil(s) { glNative.clearStencil(this._h, s); }
  colorMask(r, g, b, a) { glNative.colorMask(this._h, r, g, b, a); }
  cullFace(m) { glNative.cullFace(this._h, m); }
  depthFunc(f) { glNative.depthFunc(this._h, f); }
  depthMask(f) { glNative.depthMask(this._h, f); }
  depthRange(n, f) { glNative.depthRange(this._h, n, f); }
  disable(c) { glNative.disable(this._h, c); }
  enable(c) { glNative.enable(this._h, c); }
  frontFace(m) { glNative.frontFace(this._h, m); }
  hint(t, m) { glNative.hint(this._h, t, m); }
  isEnabled(c) { return glNative.isEnabled(this._h, c); }
  lineWidth(w) { glNative.lineWidth(this._h, w); }
  pixelStorei(p, v) {
    if (p === P.UNPACK_FLIP_Y_WEBGL) this._st.flipY = !!v;
    else if (p === P.UNPACK_PREMULTIPLY_ALPHA_WEBGL) this._st.premultiply = !!v;
    else if (p === P.UNPACK_COLORSPACE_CONVERSION_WEBGL) this._st.colorspace = v;
    glNative.pixelStorei(this._h, p, typeof v === 'boolean' ? (v ? 1 : 0) : v);
  }
  polygonOffset(f, u) { glNative.polygonOffset(this._h, f, u); }
  sampleCoverage(v, i) { glNative.sampleCoverage(this._h, v, i); }
  scissor(x, y, w, h) { glNative.scissor(this._h, x, y, w, h); }
  stencilFunc(f, r, m) { glNative.stencilFunc(this._h, f, r, m); }
  stencilFuncSeparate(fc, f, r, m) { glNative.stencilFuncSeparate(this._h, fc, f, r, m); }
  stencilMask(m) { glNative.stencilMask(this._h, m); }
  stencilMaskSeparate(f, m) { glNative.stencilMaskSeparate(this._h, f, m); }
  stencilOp(a, b, c) { glNative.stencilOp(this._h, a, b, c); }
  stencilOpSeparate(f, a, b, c) { glNative.stencilOpSeparate(this._h, f, a, b, c); }
  viewport(x, y, w, h) { glNative.viewport(this._h, x, y, w, h); }
  getError() { return this._st.lost ? P.CONTEXT_LOST_WEBGL : glNative.getError(this._h); }
  finish() { glNative.finish(this._h); }
  flush() { glNative.flush(this._h); }
  getParameter(p) {
    if (this._st.lost) return null;
    switch (p) {
      case P.VERSION: return this._v === 2 ? 'WebGL 2.0 (OpenGL ES 3.0 NativaX)' : 'WebGL 1.0 (OpenGL ES 2.0 NativaX)';
      case P.SHADING_LANGUAGE_VERSION: return this._v === 2 ? 'WebGL GLSL ES 3.00 (OpenGL ES GLSL ES 3.0 NativaX)' : 'WebGL GLSL ES 1.0 (OpenGL ES GLSL ES 1.0 NativaX)';
      case P.VENDOR: return 'WebKit';
      case P.RENDERER: return 'WebKit WebGL';
      case 0x9245: return glNative.getString(this._h, P.VENDOR);   // UNMASKED_VENDOR_WEBGL
      case 0x9246: return glNative.getString(this._h, P.RENDERER); // UNMASKED_RENDERER_WEBGL
      case P.UNPACK_FLIP_Y_WEBGL: return this._st.flipY;
      case P.UNPACK_PREMULTIPLY_ALPHA_WEBGL: return this._st.premultiply;
      case P.UNPACK_COLORSPACE_CONVERSION_WEBGL: return this._st.colorspace;
      case P.MAX_CLIENT_WAIT_TIMEOUT_WEBGL: return 0;
      case P.COMPRESSED_TEXTURE_FORMATS: return new Uint32Array(0);
      case P.FRAMEBUFFER_BINDING: return this._st.drawFb;
      case P.READ_FRAMEBUFFER_BINDING: return this._st.readFb;
      case 0x91B1: return true; // COMPLETION_STATUS_KHR is a program/shader query; harmless here
    }
    const kind = paramKinds.get(p);
    switch (kind) {
      case 'string': return glNative.getString(this._h, p);
      case 'i4': return new Int32Array(glNative.getIntegerv(this._h, p, 4));
      case 'i2': return new Int32Array(glNative.getIntegerv(this._h, p, 2));
      case 'f4': return new Float32Array(glNative.getFloatv(this._h, p, 4));
      case 'f2': return new Float32Array(glNative.getFloatv(this._h, p, 2));
      case 'b4': return glNative.getBooleanv(this._h, p, 4);
      case 'bool': return glNative.getBooleanv(this._h, p, 1);
      case 'float': return glNative.getFloatv(this._h, p, 1);
      case 'i64': return glNative.getInteger64v(this._h, p);
      case undefined: break;
      default: {
        const n = glNative.getIntegerv(this._h, p, 1);
        const map = this._o[kind];
        return n && map ? map.get(n) || null : null;
      }
    }
    const v = glNative.getIntegerv(this._h, p, 1);
    // Enum-valued and unsigned parameters come back as unsigned.
    return v < 0 && (p === P.STENCIL_WRITEMASK || p === P.STENCIL_BACK_WRITEMASK || p === P.STENCIL_VALUE_MASK || p === P.STENCIL_BACK_VALUE_MASK) ? v >>> 0 : v;
  }
  getShaderPrecisionFormat(s, p) { return new WebGLShaderPrecisionFormat(glNative.getShaderPrecisionFormat(this._h, s, p)); }
  getIndexedParameter(t, i) {
    const v = glNative.getIndexedParameter(this._h, t, i);
    if (t === P.UNIFORM_BUFFER_BINDING || t === P.TRANSFORM_FEEDBACK_BUFFER_BINDING) return this._o.buffer.get(v) || null;
    return v;
  }
  getInternalformatParameter(t, f, p) { return new Int32Array(glNative.getInternalformatParameter(this._h, t, f, p)); }

  // ---- buffers ---------------------------------------------------------------
  createBuffer() { return this._track('buffer', new WebGLBuffer(this, glNative.createBuffer(this._h))); }
  deleteBuffer(b) { if (b && b._n) { glNative.deleteBuffer(this._h, b._n); this._o.buffer.delete(b._n); b._n = 0; } }
  isBuffer(b) { return !!(b && b._n && this._o.buffer.has(b._n)); }
  bindBuffer(t, b) { glNative.bindBuffer(this._h, t, nameOf(b)); }
  bindBufferBase(t, i, b) { glNative.bindBufferBase(this._h, t, i, nameOf(b)); }
  bindBufferRange(t, i, b, o, s) { glNative.bindBufferRange(this._h, t, i, nameOf(b), o, s); }
  bufferData(t, data, usage, srcOffset = 0, length = 0) {
    if (typeof data === 'number') glNative.bufferData(this._h, t, data, usage, 0, 0);
    else if (data === null || data === undefined) throw new TypeError('bufferData: data is null');
    else glNative.bufferData(this._h, t, data, usage, srcOffset, length);
  }
  bufferSubData(t, offset, data, srcOffset = 0, length = 0) { glNative.bufferSubData(this._h, t, offset, data, srcOffset, length); }
  copyBufferSubData(r, w, ro, wo, s) { glNative.copyBufferSubData(this._h, r, w, ro, wo, s); }
  getBufferSubData(t, so, dst, dstOffset = 0, length = 0) { glNative.getBufferSubData(this._h, t, so, dst, dstOffset, length); }
  getBufferParameter(t, p) { return glNative.getBufferParameter(this._h, t, p); }

  // ---- shaders and programs -------------------------------------------------
  createShader(type) { const n = glNative.createShader(this._h, type); return n ? new WebGLShader(this, n) : null; }
  deleteShader(s) { if (s && s._n) { glNative.deleteShader(this._h, s._n); s._n = 0; } }
  isShader(s) { return !!(s && s._n); }
  shaderSource(s, src) { glNative.shaderSource(this._h, nameOf(s), String(src)); }
  getShaderSource(s) { return glNative.getShaderSource(this._h, nameOf(s)); }
  compileShader(s) { glNative.compileShader(this._h, nameOf(s)); }
  getShaderParameter(s, p) {
    if (p === 0x91B1) return true; // COMPLETION_STATUS_KHR (compiles are synchronous)
    const v = glNative.getShaderParameter(this._h, nameOf(s), p);
    return p === P.COMPILE_STATUS || p === P.DELETE_STATUS ? !!v : v;
  }
  getShaderInfoLog(s) { return glNative.getShaderInfoLog(this._h, nameOf(s)); }
  createProgram() { return this._track('program', new WebGLProgram(this, glNative.createProgram(this._h))); }
  deleteProgram(p) { if (p && p._n) { glNative.deleteProgram(this._h, p._n); this._o.program.delete(p._n); p._n = 0; } }
  isProgram(p) { return !!(p && p._n && this._o.program.has(p._n)); }
  attachShader(p, s) { glNative.attachShader(this._h, nameOf(p), nameOf(s)); }
  detachShader(p, s) { glNative.detachShader(this._h, nameOf(p), nameOf(s)); }
  getAttachedShaders(p) { return []; }
  bindAttribLocation(p, i, name) { glNative.bindAttribLocation(this._h, nameOf(p), i, String(name)); }
  linkProgram(p) { glNative.linkProgram(this._h, nameOf(p)); }
  validateProgram(p) { glNative.validateProgram(this._h, nameOf(p)); }
  useProgram(p) { glNative.useProgram(this._h, nameOf(p)); }
  getProgramParameter(p, pn) {
    if (pn === 0x91B1) return true;
    const v = glNative.getProgramParameter(this._h, nameOf(p), pn);
    return pn === P.LINK_STATUS || pn === P.DELETE_STATUS || pn === P.VALIDATE_STATUS ? !!v : v;
  }
  getProgramInfoLog(p) { return glNative.getProgramInfoLog(this._h, nameOf(p)); }
  getAttribLocation(p, name) { return glNative.getAttribLocation(this._h, nameOf(p), String(name)); }
  getFragDataLocation(p, name) { return glNative.getFragDataLocation(this._h, nameOf(p), String(name)); }
  getUniformLocation(p, name) {
    const l = glNative.getUniformLocation(this._h, nameOf(p), String(name));
    return l < 0 ? null : new WebGLUniformLocation(p, l);
  }
  getActiveAttrib(p, i) { const a = glNative.getActiveAttrib(this._h, nameOf(p), i); return a ? new WebGLActiveInfo(a[0], a[1], a[2]) : null; }
  getActiveUniform(p, i) { const a = glNative.getActiveUniform(this._h, nameOf(p), i); return a ? new WebGLActiveInfo(a[0], a[1], a[2]) : null; }
  getUniformBlockIndex(p, name) { return glNative.getUniformBlockIndex(this._h, nameOf(p), String(name)); }
  getActiveUniformBlockName(p, i) { return glNative.getActiveUniformBlockName(this._h, nameOf(p), i); }
  getActiveUniformBlockParameter(p, i, pn) {
    if (pn === P.UNIFORM_BLOCK_ACTIVE_UNIFORM_INDICES) return new Uint32Array(glNative.getActiveUniformBlockIndices(this._h, nameOf(p), i));
    const v = glNative.getActiveUniformBlockParameteri(this._h, nameOf(p), i, pn);
    return pn === P.UNIFORM_BLOCK_REFERENCED_BY_VERTEX_SHADER || pn === P.UNIFORM_BLOCK_REFERENCED_BY_FRAGMENT_SHADER ? !!v : v;
  }
  getActiveUniforms(p, indices, pn) {
    const v = glNative.getActiveUniforms(this._h, nameOf(p), Array.from(indices), pn);
    return pn === P.UNIFORM_IS_ROW_MAJOR ? v.map((x) => !!x) : v;
  }
  getUniformIndices(p, names) { return glNative.getUniformIndices(this._h, nameOf(p), Array.from(names, String)); }
  uniformBlockBinding(p, i, b) { glNative.uniformBlockBinding(this._h, nameOf(p), i, b); }
  transformFeedbackVaryings(p, v, m) { glNative.transformFeedbackVaryings(this._h, nameOf(p), Array.from(v, String), m); }
  getTransformFeedbackVarying(p, i) { const a = glNative.getTransformFeedbackVarying(this._h, nameOf(p), i); return a ? new WebGLActiveInfo(a[0], a[1], a[2]) : null; }

  // ---- uniforms ----------------------------------------------------------------
  uniform1f(l, x) { if (l) glNative.uniform1f(this._h, l._l, x); }
  uniform2f(l, x, y) { if (l) glNative.uniform2f(this._h, l._l, x, y); }
  uniform3f(l, x, y, z) { if (l) glNative.uniform3f(this._h, l._l, x, y, z); }
  uniform4f(l, x, y, z, w) { if (l) glNative.uniform4f(this._h, l._l, x, y, z, w); }
  uniform1i(l, x) { if (l) glNative.uniform1i(this._h, l._l, x); }
  uniform2i(l, x, y) { if (l) glNative.uniform2i(this._h, l._l, x, y); }
  uniform3i(l, x, y, z) { if (l) glNative.uniform3i(this._h, l._l, x, y, z); }
  uniform4i(l, x, y, z, w) { if (l) glNative.uniform4i(this._h, l._l, x, y, z, w); }
  uniform1ui(l, x) { if (l) glNative.uniform1ui(this._h, l._l, x); }
  uniform2ui(l, x, y) { if (l) glNative.uniform2ui(this._h, l._l, x, y); }
  uniform3ui(l, x, y, z) { if (l) glNative.uniform3ui(this._h, l._l, x, y, z); }
  uniform4ui(l, x, y, z, w) { if (l) glNative.uniform4ui(this._h, l._l, x, y, z, w); }
  _uv(kind, l, v, o, n, Ctor) {
    if (!l) return;
    if (!(v instanceof Ctor)) v = new Ctor(v);
    glNative.uniformv(this._h, kind, l._l, v, o || 0, n || 0);
  }
  uniform1fv(l, v, o, n) { this._uv(1, l, v, o, n, Float32Array); }
  uniform2fv(l, v, o, n) { this._uv(2, l, v, o, n, Float32Array); }
  uniform3fv(l, v, o, n) { this._uv(3, l, v, o, n, Float32Array); }
  uniform4fv(l, v, o, n) { this._uv(4, l, v, o, n, Float32Array); }
  uniform1iv(l, v, o, n) { this._uv(11, l, v, o, n, Int32Array); }
  uniform2iv(l, v, o, n) { this._uv(12, l, v, o, n, Int32Array); }
  uniform3iv(l, v, o, n) { this._uv(13, l, v, o, n, Int32Array); }
  uniform4iv(l, v, o, n) { this._uv(14, l, v, o, n, Int32Array); }
  uniform1uiv(l, v, o, n) { this._uv(21, l, v, o, n, Uint32Array); }
  uniform2uiv(l, v, o, n) { this._uv(22, l, v, o, n, Uint32Array); }
  uniform3uiv(l, v, o, n) { this._uv(23, l, v, o, n, Uint32Array); }
  uniform4uiv(l, v, o, n) { this._uv(24, l, v, o, n, Uint32Array); }
  _um(kind, l, t, v, o, n) {
    if (!l) return;
    if (!(v instanceof Float32Array)) v = new Float32Array(v);
    glNative.uniformMatrix(this._h, kind, l._l, t, v, o || 0, n || 0);
  }
  uniformMatrix2fv(l, t, v, o, n) { this._um(22, l, t, v, o, n); }
  uniformMatrix3fv(l, t, v, o, n) { this._um(33, l, t, v, o, n); }
  uniformMatrix4fv(l, t, v, o, n) { this._um(44, l, t, v, o, n); }
  uniformMatrix2x3fv(l, t, v, o, n) { this._um(23, l, t, v, o, n); }
  uniformMatrix2x4fv(l, t, v, o, n) { this._um(24, l, t, v, o, n); }
  uniformMatrix3x2fv(l, t, v, o, n) { this._um(32, l, t, v, o, n); }
  uniformMatrix3x4fv(l, t, v, o, n) { this._um(34, l, t, v, o, n); }
  uniformMatrix4x2fv(l, t, v, o, n) { this._um(42, l, t, v, o, n); }
  uniformMatrix4x3fv(l, t, v, o, n) { this._um(43, l, t, v, o, n); }
  getUniform() { return null; }

  // ---- vertex attributes ---------------------------------------------------
  enableVertexAttribArray(i) { glNative.enableVertexAttribArray(this._h, i); }
  disableVertexAttribArray(i) { glNative.disableVertexAttribArray(this._h, i); }
  vertexAttribPointer(i, s, t, n, st, o) { glNative.vertexAttribPointer(this._h, i, s, t, n, st, o); }
  vertexAttribIPointer(i, s, t, st, o) { glNative.vertexAttribIPointer(this._h, i, s, t, st, o); }
  vertexAttribDivisor(i, d) { glNative.vertexAttribDivisor(this._h, i, d); }
  vertexAttrib1f(i, x) { glNative.vertexAttrib1f(this._h, i, x); }
  vertexAttrib2f(i, x, y) { glNative.vertexAttrib2f(this._h, i, x, y); }
  vertexAttrib3f(i, x, y, z) { glNative.vertexAttrib3f(this._h, i, x, y, z); }
  vertexAttrib4f(i, x, y, z, w) { glNative.vertexAttrib4f(this._h, i, x, y, z, w); }
  vertexAttrib1fv(i, v) { glNative.vertexAttrib1f(this._h, i, v[0]); }
  vertexAttrib2fv(i, v) { glNative.vertexAttrib2f(this._h, i, v[0], v[1]); }
  vertexAttrib3fv(i, v) { glNative.vertexAttrib3f(this._h, i, v[0], v[1], v[2]); }
  vertexAttrib4fv(i, v) { glNative.vertexAttrib4f(this._h, i, v[0], v[1], v[2], v[3]); }
  vertexAttribI4i(i, x, y, z, w) { glNative.vertexAttribI4i(this._h, i, x, y, z, w); }
  vertexAttribI4ui(i, x, y, z, w) { glNative.vertexAttribI4ui(this._h, i, x, y, z, w); }
  vertexAttribI4iv(i, v) { glNative.vertexAttribI4i(this._h, i, v[0], v[1], v[2], v[3]); }
  vertexAttribI4uiv(i, v) { glNative.vertexAttribI4ui(this._h, i, v[0], v[1], v[2], v[3]); }
  getVertexAttrib(i, p) {
    if (p === P.CURRENT_VERTEX_ATTRIB) return new Float32Array(glNative.getVertexAttribf4(this._h, i, p));
    const v = glNative.getVertexAttribi(this._h, i, p);
    if (p === P.VERTEX_ATTRIB_ARRAY_BUFFER_BINDING) return this._o.buffer.get(v) || null;
    if (p === P.VERTEX_ATTRIB_ARRAY_ENABLED || p === P.VERTEX_ATTRIB_ARRAY_NORMALIZED || p === P.VERTEX_ATTRIB_ARRAY_INTEGER) return !!v;
    return v;
  }
  getVertexAttribOffset() { return 0; }
  createVertexArray() { return this._track('vertexArray', new WebGLVertexArrayObject(this, glNative.createVertexArray(this._h))); }
  deleteVertexArray(v) { if (v && v._n) { glNative.deleteVertexArray(this._h, v._n); this._o.vertexArray.delete(v._n); v._n = 0; } }
  isVertexArray(v) { return !!(v && v._n && this._o.vertexArray.has(v._n)); }
  bindVertexArray(v) { glNative.bindVertexArray(this._h, nameOf(v)); }

  // ---- drawing ---------------------------------------------------------------
  clear(m) { glNative.clear(this._h, m); this._drew(); }
  drawArrays(m, f, c) { glNative.drawArrays(this._h, m, f, c); this._drew(); }
  drawElements(m, c, t, o) { glNative.drawElements(this._h, m, c, t, o); this._drew(); }
  drawArraysInstanced(m, f, c, n) { glNative.drawArraysInstanced(this._h, m, f, c, n); this._drew(); }
  drawElementsInstanced(m, c, t, o, n) { glNative.drawElementsInstanced(this._h, m, c, t, o, n); this._drew(); }
  drawRangeElements(m, s, e, c, t, o) { glNative.drawRangeElements(this._h, m, s, e, c, t, o); this._drew(); }
  drawBuffers(b) { glNative.drawBuffers(this._h, Array.from(b)); }
  clearBufferfv(b, d, v, o = 0) { glNative.clearBufferv(this._h, 0, b, d, v instanceof Float32Array ? v : new Float32Array(v), o); this._drew(); }
  clearBufferiv(b, d, v, o = 0) { glNative.clearBufferv(this._h, 1, b, d, v instanceof Int32Array ? v : new Int32Array(v), o); this._drew(); }
  clearBufferuiv(b, d, v, o = 0) { glNative.clearBufferv(this._h, 2, b, d, v instanceof Uint32Array ? v : new Uint32Array(v), o); this._drew(); }
  clearBufferfi(b, d, depth, s) { glNative.clearBufferfi(this._h, b, d, depth, s); this._drew(); }
  readBuffer(s) { glNative.readBuffer(this._h, s); }
  readPixels(x, y, w, h, f, t, dst, offset = 0) {
    if (typeof dst === 'number') glNative.readPixels(this._h, x, y, w, h, f, t, null, dst);
    else glNative.readPixels(this._h, x, y, w, h, f, t, dst, offset);
  }

  // ---- framebuffers and renderbuffers ---------------------------------------------
  createFramebuffer() { return this._track('framebuffer', new WebGLFramebuffer(this, glNative.createFramebuffer(this._h))); }
  deleteFramebuffer(f) {
    if (!f || !f._n) return;
    if (this._st.drawFb === f) this._st.drawFb = null;
    if (this._st.readFb === f) this._st.readFb = null;
    glNative.deleteFramebuffer(this._h, f._n); this._o.framebuffer.delete(f._n); f._n = 0;
  }
  isFramebuffer(f) { return !!(f && f._n && this._o.framebuffer.has(f._n)); }
  bindFramebuffer(t, f) {
    if (t === P.FRAMEBUFFER || t === P.DRAW_FRAMEBUFFER) this._st.drawFb = f || null;
    if (t === P.FRAMEBUFFER || t === P.READ_FRAMEBUFFER) this._st.readFb = f || null;
    glNative.bindFramebuffer(this._h, t, nameOf(f));
  }
  checkFramebufferStatus(t) { return glNative.checkFramebufferStatus(this._h, t); }
  framebufferRenderbuffer(t, a, rt, r) { glNative.framebufferRenderbuffer(this._h, t, a, rt, nameOf(r)); }
  framebufferTexture2D(t, a, tt, tex, l) { glNative.framebufferTexture2D(this._h, t, a, tt, nameOf(tex), l); }
  framebufferTextureLayer(t, a, tex, l, layer) { glNative.framebufferTextureLayer(this._h, t, a, nameOf(tex), l, layer); }
  getFramebufferAttachmentParameter(t, a, p) {
    const v = glNative.getFramebufferAttachmentParameter(this._h, t, a, p);
    if (p === P.FRAMEBUFFER_ATTACHMENT_OBJECT_NAME) {
      const type = glNative.getFramebufferAttachmentParameter(this._h, t, a, P.FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE);
      return (type === P.TEXTURE ? this._o.texture : this._o.renderbuffer).get(v) || null;
    }
    return v;
  }
  blitFramebuffer(a, b, c, d, e, f, g, h, m, fi) { glNative.blitFramebuffer(this._h, a, b, c, d, e, f, g, h, m, fi); this._drew(); }
  invalidateFramebuffer(t, a) { glNative.invalidateFramebuffer(this._h, t, Array.from(a)); }
  invalidateSubFramebuffer(t, a) { glNative.invalidateFramebuffer(this._h, t, Array.from(a)); }
  createRenderbuffer() { return this._track('renderbuffer', new WebGLRenderbuffer(this, glNative.createRenderbuffer(this._h))); }
  deleteRenderbuffer(r) { if (r && r._n) { glNative.deleteRenderbuffer(this._h, r._n); this._o.renderbuffer.delete(r._n); r._n = 0; } }
  isRenderbuffer(r) { return !!(r && r._n && this._o.renderbuffer.has(r._n)); }
  bindRenderbuffer(t, r) { glNative.bindRenderbuffer(this._h, t, nameOf(r)); }
  renderbufferStorage(t, f, w, h) { glNative.renderbufferStorage(this._h, t, f === P.DEPTH_STENCIL ? P.DEPTH24_STENCIL8 : f, w, h); }
  renderbufferStorageMultisample(t, s, f, w, h) { glNative.renderbufferStorageMultisample(this._h, t, s, f, w, h); }
  getRenderbufferParameter(t, p) { return glNative.getRenderbufferParameter(this._h, t, p); }

  // ---- textures --------------------------------------------------------------
  createTexture() { return this._track('texture', new WebGLTexture(this, glNative.createTexture(this._h))); }
  deleteTexture(t) { if (t && t._n) { glNative.deleteTexture(this._h, t._n); this._o.texture.delete(t._n); t._n = 0; } }
  isTexture(t) { return !!(t && t._n && this._o.texture.has(t._n)); }
  bindTexture(t, tex) { glNative.bindTexture(this._h, t, nameOf(tex)); }
  texParameterf(t, p, v) { glNative.texParameterf(this._h, t, p, v); }
  texParameteri(t, p, v) { glNative.texParameteri(this._h, t, p, v); }
  getTexParameter(t, p) {
    if (p === P.TEXTURE_MAX_LOD || p === P.TEXTURE_MIN_LOD || p === 0x84FE) return glNative.getTexParameterf(this._h, t, p);
    const v = glNative.getTexParameteri(this._h, t, p);
    return p === P.TEXTURE_IMMUTABLE_FORMAT ? !!v : v;
  }
  generateMipmap(t) { glNative.generateMipmap(this._h, t); }
  texStorage2D(t, l, f, w, h) { glNative.texStorage2D(this._h, t, l, f, w, h); }
  texStorage3D(t, l, f, w, h, d) { glNative.texStorage3D(this._h, t, l, f, w, h, d); }
  // A TexImageSource as an ImageBitmap id (owned: free after upload).
  _bitmapFor(src) {
    if (src instanceof ImageBitmap) {
      if (src._b.closed) throw new DOMException('The image bitmap is detached.', 'InvalidStateError');
      return { id: src._b.id, w: src._b.width, h: src._b.height, owned: false };
    }
    const flip = this._st.flipY, pre = this._st.premultiply;
    if (typeof ImageData !== 'undefined' && src instanceof ImageData) {
      return { id: glNative.bitmapFromPixels(src.data, src.width, src.height, flip, pre), w: src.width, h: src.height, owned: true };
    }
    if (src instanceof OffscreenCanvas && src._oc.ctx && src._oc.ctx._h) {
      const c = src._oc.ctx, w = c.drawingBufferWidth, h = c.drawingBufferHeight;
      const px = new Uint8Array(w * h * 4);
      c.readPixels(0, 0, w, h, P.RGBA, P.UNSIGNED_BYTE, px);
      return { id: glNative.bitmapFromPixels(px, w, h, !flip, pre), w, h, owned: true };
    }
    const bmp = src && src[sourceBitmap] ? src[sourceBitmap]() : null;
    if (bmp) return { id: glNative.bitmapFromPixels(bmp.pixels, bmp.width, bmp.height, flip, pre), w: bmp.width, h: bmp.height, owned: true };
    throw new TypeError('texImage: unsupported image source');
  }
  _isSource(v) { return v !== null && typeof v === 'object' && !isView(v) && !(v instanceof ArrayBuffer); }
  texImage2D(...a) {
    let target, level, ifmt, w, h, border, fmt, type, src, off = 0;
    if (a.length === 6) { [target, level, ifmt, fmt, type, src] = a; border = 0; }
    else [target, level, ifmt, w, h, border, fmt, type, src, off = 0] = a;
    if (this._isSource(src)) {
      const b = this._bitmapFor(src);
      try { glNative.texImageBitmap(this._h, 0, target, level, ifmt, 0, fmt, type, b.id, -1); }
      finally { if (b.owned) glNative.bitmapFree(b.id); }
      return;
    }
    if (typeof src === 'number') glNative.texImage2DOffset(this._h, target, level, ifmt, w, h, border, fmt, type, src);
    else glNative.texImage2D(this._h, target, level, ifmt, w, h, border, fmt, type, src === undefined ? null : src, off);
  }
  texSubImage2D(...a) {
    let target, level, x, y, w, h, fmt, type, src, off = 0;
    if (a.length === 7) { [target, level, x, y, fmt, type, src] = a; }
    else [target, level, x, y, w, h, fmt, type, src, off = 0] = a;
    if (this._isSource(src)) {
      const b = this._bitmapFor(src);
      try { glNative.texImageBitmap(this._h, 1, target, level, x, y, fmt, type, b.id, -1); }
      finally { if (b.owned) glNative.bitmapFree(b.id); }
      return;
    }
    glNative.texSubImage2D(this._h, target, level, x, y, w, h, fmt, type, src, off);
  }
  texImage3D(target, level, ifmt, w, h, d, border, fmt, type, src, off = 0) {
    if (this._isSource(src)) throw new TypeError('texImage3D: image sources are not supported; use pixels');
    glNative.texImage3D(this._h, target, level, ifmt, w, h, d, border, fmt, type, src === undefined || typeof src === 'number' ? null : src, off);
  }
  texSubImage3D(target, level, x, y, z, w, h, d, fmt, type, src, off = 0) {
    if (this._isSource(src)) {
      const b = this._bitmapFor(src);
      try { glNative.texImageBitmap(this._h, 1, target, level, x, y, fmt, type, b.id, z); }
      finally { if (b.owned) glNative.bitmapFree(b.id); }
      return;
    }
    glNative.texSubImage3D(this._h, target, level, x, y, z, w, h, d, fmt, type, src, off);
  }
  compressedTexImage2D(t, l, f, w, h, b, data, o = 0, n = 0) { glNative.compressedTexImage2D(this._h, t, l, f, w, h, b, data, o, n); }
  compressedTexSubImage2D(t, l, x, y, w, h, f, data, o = 0, n = 0) { glNative.compressedTexSubImage2D(this._h, t, l, x, y, w, h, f, data, o, n); }
  compressedTexImage3D(t, l, f, w, h, d, b, data, o = 0, n = 0) { glNative.compressedTexImage3D(this._h, t, l, f, w, h, d, b, data, o, n); }
  compressedTexSubImage3D(t, l, x, y, z, w, h, d, f, data, o = 0, n = 0) { glNative.compressedTexSubImage3D(this._h, t, l, x, y, z, w, h, d, f, data, o, n); }
  copyTexImage2D(t, l, f, x, y, w, h, b) { glNative.copyTexImage2D(this._h, t, l, f, x, y, w, h, b); }
  copyTexSubImage2D(t, l, xo, yo, x, y, w, h) { glNative.copyTexSubImage2D(this._h, t, l, xo, yo, x, y, w, h); }
  copyTexSubImage3D(t, l, xo, yo, zo, x, y, w, h) { glNative.copyTexSubImage3D(this._h, t, l, xo, yo, zo, x, y, w, h); }

  // ---- samplers, queries, syncs, transform feedback --------------------------------
  createSampler() { return this._track('sampler', new WebGLSampler(this, glNative.createSampler(this._h))); }
  deleteSampler(s) { if (s && s._n) { glNative.deleteSampler(this._h, s._n); this._o.sampler.delete(s._n); s._n = 0; } }
  isSampler(s) { return !!(s && s._n && this._o.sampler.has(s._n)); }
  bindSampler(u, s) { glNative.bindSampler(this._h, u, nameOf(s)); }
  samplerParameteri(s, p, v) { glNative.samplerParameteri(this._h, nameOf(s), p, v); }
  samplerParameterf(s, p, v) { glNative.samplerParameterf(this._h, nameOf(s), p, v); }
  getSamplerParameter(s, p) {
    return p === P.TEXTURE_MAX_LOD || p === P.TEXTURE_MIN_LOD ? glNative.getSamplerParameterf(this._h, nameOf(s), p) : glNative.getSamplerParameteri(this._h, nameOf(s), p);
  }
  createQuery() { return this._track('query', new WebGLQuery(this, glNative.createQuery(this._h))); }
  deleteQuery(q) { if (q && q._n) { glNative.deleteQuery(this._h, q._n); this._o.query.delete(q._n); q._n = 0; } }
  isQuery(q) { return !!(q && q._n && this._o.query.has(q._n)); }
  beginQuery(t, q) { glNative.beginQuery(this._h, t, nameOf(q)); }
  endQuery(t) { glNative.endQuery(this._h, t); }
  getQuery(t, p) { const v = glNative.getQuery(this._h, t, p); return p === P.CURRENT_QUERY ? this._o.query.get(v) || null : v; }
  getQueryParameter(q, p) { const v = glNative.getQueryParameter(this._h, nameOf(q), p); return p === P.QUERY_RESULT_AVAILABLE ? !!v : v; }
  fenceSync(c, f) { const id = glNative.fenceSync(this._h, c, f); return id ? new WebGLSync(this, id) : null; }
  deleteSync(s) { if (s && s._n) { glNative.deleteSync(this._h, s._n); s._n = 0; } }
  isSync(s) { return !!(s && s._n); }
  clientWaitSync(s, f, t) { return glNative.clientWaitSync(this._h, nameOf(s), f, t); }
  waitSync() {}
  getSyncParameter(s, p) { return glNative.getSyncParameter(this._h, nameOf(s), p); }
  createTransformFeedback() { return this._track('transformFeedback', new WebGLTransformFeedback(this, glNative.createTransformFeedback(this._h))); }
  deleteTransformFeedback(t) { if (t && t._n) { glNative.deleteTransformFeedback(this._h, t._n); this._o.transformFeedback.delete(t._n); t._n = 0; } }
  isTransformFeedback(t) { return !!(t && t._n && this._o.transformFeedback.has(t._n)); }
  bindTransformFeedback(t, tf) { glNative.bindTransformFeedback(this._h, t, nameOf(tf)); }
  beginTransformFeedback(m) { glNative.beginTransformFeedback(this._h, m); }
  endTransformFeedback() { glNative.endTransformFeedback(this._h); }
  pauseTransformFeedback() { glNative.pauseTransformFeedback(this._h); }
  resumeTransformFeedback() { glNative.resumeTransformFeedback(this._h); }
}
for (const [k, v] of Object.entries(GL_CONSTANTS)) {
  defineProperty(WebGL2RenderingContextImpl.prototype, k, { value: v, enumerable: true });
  defineProperty(WebGL2RenderingContextImpl, k, { value: v, enumerable: true });
}
class WebGL2RenderingContext extends WebGL2RenderingContextImpl {}
class WebGLRenderingContext extends WebGL2RenderingContextImpl {}

const makeExtension = (gl, name) => {
  switch (name) {
    case 'EXT_texture_filter_anisotropic': return { TEXTURE_MAX_ANISOTROPY_EXT: 0x84FE, MAX_TEXTURE_MAX_ANISOTROPY_EXT: 0x84FF };
    case 'WEBGL_debug_renderer_info': return { UNMASKED_VENDOR_WEBGL: 0x9245, UNMASKED_RENDERER_WEBGL: 0x9246 };
    case 'KHR_parallel_shader_compile': return { COMPLETION_STATUS_KHR: 0x91B1, maxShaderCompilerThreadsKHR() {} };
    case 'WEBGL_lose_context': return {
      loseContext() {
        if (gl._st.lost) return;
        gl._st.lost = true;
        glNative.setLost(gl._h, true);
        const c = gl.canvas;
        setTimeout(() => c && c.dispatchEvent && c.dispatchEvent(new WebGLContextEvent('webglcontextlost', { cancelable: true })), 0);
      },
      restoreContext() {
        if (!gl._st.lost) return;
        gl._st.lost = false;
        glNative.setLost(gl._h, false);
        const c = gl.canvas;
        setTimeout(() => c && c.dispatchEvent && c.dispatchEvent(new WebGLContextEvent('webglcontextrestored')), 0);
      },
    };
    case 'WEBGL_multi_draw': return {
      multiDrawArraysWEBGL(m, firsts, fo, counts, co, n) { for (let i = 0; i < n; i++) gl.drawArrays(m, firsts[fo + i], counts[co + i]); },
      multiDrawElementsWEBGL(m, counts, co, t, offs, oo, n) { for (let i = 0; i < n; i++) gl.drawElements(m, counts[co + i], t, offs[oo + i]); },
      multiDrawArraysInstancedWEBGL(m, firsts, fo, counts, co, inst, io, n) { for (let i = 0; i < n; i++) gl.drawArraysInstanced(m, firsts[fo + i], counts[co + i], inst[io + i]); },
      multiDrawElementsInstancedWEBGL(m, counts, co, t, offs, oo, inst, io, n) { for (let i = 0; i < n; i++) gl.drawElementsInstanced(m, counts[co + i], t, offs[oo + i], inst[io + i]); },
    };
    case 'ANGLE_instanced_arrays': return {
      VERTEX_ATTRIB_ARRAY_DIVISOR_ANGLE: 0x88FE,
      drawArraysInstancedANGLE: (m, f, c, n) => gl.drawArraysInstanced(m, f, c, n),
      drawElementsInstancedANGLE: (m, c, t, o, n) => gl.drawElementsInstanced(m, c, t, o, n),
      vertexAttribDivisorANGLE: (i, d) => gl.vertexAttribDivisor(i, d),
    };
    case 'OES_vertex_array_object': return {
      VERTEX_ARRAY_BINDING_OES: 0x85B5,
      createVertexArrayOES: () => gl.createVertexArray(), deleteVertexArrayOES: (v) => gl.deleteVertexArray(v),
      isVertexArrayOES: (v) => gl.isVertexArray(v), bindVertexArrayOES: (v) => gl.bindVertexArray(v),
    };
    case 'WEBGL_draw_buffers': {
      const e = { drawBuffersWEBGL: (b) => gl.drawBuffers(b), MAX_COLOR_ATTACHMENTS_WEBGL: 0x8CDF, MAX_DRAW_BUFFERS_WEBGL: 0x8824 };
      for (let i = 0; i < 16; i++) { e['COLOR_ATTACHMENT' + i + '_WEBGL'] = 0x8CE0 + i; e['DRAW_BUFFER' + i + '_WEBGL'] = 0x8825 + i; }
      return e;
    }
    case 'WEBGL_depth_texture': return { UNSIGNED_INT_24_8_WEBGL: 0x84FA };
    case 'OES_texture_half_float': return { HALF_FLOAT_OES: 0x8D61 };
    case 'OES_standard_derivatives': return { FRAGMENT_SHADER_DERIVATIVE_HINT_OES: 0x8B8B };
    case 'EXT_blend_minmax': return { MIN_EXT: 0x8007, MAX_EXT: 0x8008 };
    case 'EXT_sRGB': return { SRGB_EXT: 0x8C40, SRGB_ALPHA_EXT: 0x8C42, SRGB8_ALPHA8_EXT: 0x8C43, FRAMEBUFFER_ATTACHMENT_COLOR_ENCODING_EXT: 0x8210 };
    case 'EXT_color_buffer_half_float': return { RGBA16F_EXT: 0x881A, RGB16F_EXT: 0x881B, FRAMEBUFFER_ATTACHMENT_COMPONENT_TYPE_EXT: 0x8211, UNSIGNED_NORMALIZED_EXT: 0x8C17 };
    case 'WEBGL_compressed_texture_s3tc': return { COMPRESSED_RGB_S3TC_DXT1_EXT: 0x83F0, COMPRESSED_RGBA_S3TC_DXT1_EXT: 0x83F1, COMPRESSED_RGBA_S3TC_DXT3_EXT: 0x83F2, COMPRESSED_RGBA_S3TC_DXT5_EXT: 0x83F3 };
    case 'WEBGL_compressed_texture_etc': return { COMPRESSED_R11_EAC: 0x9270, COMPRESSED_SIGNED_R11_EAC: 0x9271, COMPRESSED_RG11_EAC: 0x9272,
      COMPRESSED_SIGNED_RG11_EAC: 0x9273, COMPRESSED_RGB8_ETC2: 0x9274, COMPRESSED_SRGB8_ETC2: 0x9275, COMPRESSED_RGB8_PUNCHTHROUGH_ALPHA1_ETC2: 0x9276,
      COMPRESSED_SRGB8_PUNCHTHROUGH_ALPHA1_ETC2: 0x9277, COMPRESSED_RGBA8_ETC2_EAC: 0x9278, COMPRESSED_SRGB8_ALPHA8_ETC2_EAC: 0x9279 };
    case 'EXT_disjoint_timer_query_webgl2': return { QUERY_COUNTER_BITS_EXT: 0x8864, TIME_ELAPSED_EXT: 0x88BF, TIMESTAMP_EXT: 0x8E28, GPU_DISJOINT_EXT: 0x8FBB, queryCounterEXT() {} };
    default: return {};
  }
};

// ============================================================================
// OffscreenCanvas (WebGL; 2D is not available off the main thread yet)
// ============================================================================
const offscreenCleanup = new FinalizationRegistry((s) => { if (glNative && s) glNative.surfaceRelease(s); });
class OffscreenCanvas extends EventTarget {
  constructor(width, height, surface) {
    super();
    const s = surface || (glNative ? glNative.surfaceCreate() : 0);
    hidden(this, '_oc', { w: Math.max(0, width | 0), h: Math.max(0, height | 0), surface: s, ctx: null, detached: false });
    if (s) offscreenCleanup.register(this, s, this);
  }
  get width() { return this._oc.w; }
  set width(v) { this._oc.w = Math.max(0, v | 0); if (this._oc.ctx) this._oc.ctx._resize(this._oc.w, this._oc.h); }
  get height() { return this._oc.h; }
  set height(v) { this._oc.h = Math.max(0, v | 0); if (this._oc.ctx) this._oc.ctx._resize(this._oc.w, this._oc.h); }
  getContext(type, attrs) {
    const oc = this._oc;
    if (oc.detached) throw new DOMException('OffscreenCanvas is detached', 'InvalidStateError');
    type = String(type);
    if (type !== 'webgl2' && type !== 'webgl' && type !== 'experimental-webgl') {
      return null;
    }
    const version = type === 'webgl2' ? 2 : 1;
    if (oc.ctx) return oc.ctx._v === version ? oc.ctx : null;
    if (!glNative || !oc.surface) return null;
    const ctx = new (version === 2 ? WebGL2RenderingContext : WebGLRenderingContext)(this, version, attrs, oc.surface, oc.w || 1, oc.h || 1);
    if (!ctx._h) return null;
    oc.ctx = ctx;
    return ctx;
  }
  transferToImageBitmap() {
    const c = this._oc.ctx;
    if (!c) throw new DOMException('OffscreenCanvas has no rendering context', 'InvalidStateError');
    const w = c.drawingBufferWidth, h = c.drawingBufferHeight;
    const px = new Uint8Array(w * h * 4);
    c.readPixels(0, 0, w, h, P.RGBA, P.UNSIGNED_BYTE, px);
    return newBitmap(glNative.bitmapFromPixels(px, w, h, true, false), w, h);
  }
  convertToBlob() { return Promise.reject(new DOMException('convertToBlob is not supported yet', 'NotSupportedError')); }
}
for (const t of ['contextlost', 'contextrestored', 'webglcontextlost', 'webglcontextrestored']) {
  defineProperty(OffscreenCanvas.prototype, 'on' + t, { value: null, writable: true, configurable: true });
}
transferables.set('OffscreenCanvas', {
  transferOnly: true,
  test: (v) => v instanceof OffscreenCanvas,
  write(v) {
    const oc = v._oc;
    if (oc.ctx) throw new DOMException('Cannot transfer an OffscreenCanvas with a rendering context.', 'InvalidStateError');
    if (oc.detached) throw new DOMException('OffscreenCanvas is detached', 'DataCloneError');
    oc.detached = true;
    offscreenCleanup.unregister(v);
    return [oc.surface, oc.w, oc.h];
  },
  read: ([surface, w, h]) => new OffscreenCanvas(w, h, surface),
});

// Canvas elements: WebGL contexts and transferControlToOffscreen. The element
// shows its surface; the host is told which surface belongs to it.
const canvasGl = new WeakMap(); // element -> { surface, ctx, transferred }
const previousGetContext = EP.getContext;
EP.getContext = function (type, attrs) {
  if (this.localName !== 'canvas') return previousGetContext.call(this, type, attrs);
  type = String(type);
  if (type !== 'webgl2' && type !== 'webgl' && type !== 'experimental-webgl') {
    const st = canvasGl.get(this);
    if (st && (st.ctx || st.transferred)) return null;
    return previousGetContext.call(this, type, attrs);
  }
  let st = canvasGl.get(this);
  if (st && st.transferred) throw new DOMException('Cannot get a context from a canvas that has transferred its control to offscreen.', 'InvalidStateError');
  const version = type === 'webgl2' ? 2 : 1;
  if (st && st.ctx) return st.ctx._v === version ? st.ctx : null;
  if (!glNative) return null;
  if (!st) { st = { surface: glNative.surfaceCreate(), ctx: null, transferred: false }; canvasGl.set(this, st); host('canvas.surface', this[ID], st.surface); }
  const ctx = new (version === 2 ? WebGL2RenderingContext : WebGLRenderingContext)(this, version, attrs, st.surface, this.width || 300, this.height || 150);
  if (!ctx._h) return null;
  st.ctx = ctx;
  return ctx;
};
EP.transferControlToOffscreen = function () {
  if (this.localName !== 'canvas') throw new TypeError('transferControlToOffscreen is only available on canvas');
  let st = canvasGl.get(this);
  if (st && (st.ctx || st.transferred)) throw new DOMException('Cannot transfer control from a canvas that has a rendering context.', 'InvalidStateError');
  if (!glNative) throw new DOMException('OffscreenCanvas is not available', 'NotSupportedError');
  st = { surface: glNative.surfaceCreate(), ctx: null, transferred: true };
  canvasGl.set(this, st);
  host('canvas.surface', this[ID], st.surface);
  glNative.surfaceRetain(st.surface);
  return new OffscreenCanvas(this.width || 300, this.height || 150, st.surface);
};
for (const dim of ['width', 'height']) {
  const desc = Object.getOwnPropertyDescriptor(EP, dim);
  defineProperty(EP, dim, {
    get: desc.get,
    set(v) {
      desc.set.call(this, v);
      const st = this.localName === 'canvas' ? canvasGl.get(this) : null;
      if (st && st.ctx) st.ctx._resize(this.width, this.height);
    },
    configurable: true, enumerable: true,
  });
}

for (const [name, value] of Object.entries({
  WebGLRenderingContext, WebGL2RenderingContext, WebGLBuffer, WebGLTexture, WebGLProgram, WebGLShader, WebGLFramebuffer,
  WebGLRenderbuffer, WebGLVertexArrayObject, WebGLQuery, WebGLSampler, WebGLSync, WebGLTransformFeedback,
  WebGLUniformLocation, WebGLActiveInfo, WebGLShaderPrecisionFormat, WebGLContextEvent, OffscreenCanvas, ImageBitmap,
  createImageBitmap,
})) defineProperty(globalThis, name, { value, enumerable: false, writable: true, configurable: true });
''';
