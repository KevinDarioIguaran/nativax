import 'package:nativa_dom/nativa_dom.dart' as dom;
import 'package:nativa_js/nativa_js.dart';
import 'package:test/test.dart';

import 'web_platform_test.dart' show WebHarness;

const _triangle = r'''
  const vs = `#version 300 es
    in vec2 p; void main() { gl_Position = vec4(p, 0.0, 1.0); }`;
  const fs = `#version 300 es
    precision highp float; uniform vec4 color; out vec4 o; void main() { o = color; }`;
  const prog = gl.createProgram();
  for (const [type, src] of [[gl.VERTEX_SHADER, vs], [gl.FRAGMENT_SHADER, fs]]) {
    const s = gl.createShader(type);
    gl.shaderSource(s, src);
    gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
    gl.attachShader(prog, s);
  }
  gl.linkProgram(prog);
  if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(prog));
  gl.useProgram(prog);
  const vao = gl.createVertexArray();
  gl.bindVertexArray(vao);
  const buf = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, buf);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
  const loc = gl.getAttribLocation(prog, 'p');
  gl.enableVertexAttribArray(loc);
  gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
  gl.uniform4fv(gl.getUniformLocation(prog, 'color'), [0, 1, 0, 1]);
  gl.clearColor(1, 0, 0, 1);
  gl.clear(gl.COLOR_BUFFER_BIT);
  gl.drawArrays(gl.TRIANGLES, 0, 3);
''';

void main() {
  WebHarness? harness;
  // Skipped tests (no GL) never create a harness.
  tearDown(() {
    harness?.bindings.dispose();
    harness = null;
  });

  test('WebGL2 on an OffscreenCanvas: shaders, buffers, draw and readPixels', () {
    if (!GlSurfaces.available) return markTestSkipped('no EGL/OpenGL ES 3');
    final h = harness = WebHarness('<p>x</p>');
    final out = h.js('''(() => {
      const gl = new OffscreenCanvas(8, 8).getContext('webgl2');
      $_triangle
      const px = new Uint8Array(4);
      gl.readPixels(4, 4, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, px);
      return [gl instanceof WebGL2RenderingContext, Array.from(px), gl.getError(),
        gl.getParameter(gl.VERSION), gl.getParameter(gl.MAX_TEXTURE_SIZE) >= 2048,
        Array.from(gl.getParameter(gl.VIEWPORT)), gl.getParameter(gl.CURRENT_PROGRAM) === prog,
        gl.getSupportedExtensions().includes('WEBGL_lose_context'), gl.drawingBufferWidth];
    })()''');
    expect(out, [true, [0, 255, 0, 255], 0, 'WebGL 2.0 (OpenGL ES 3.0 NativaX)', true, [0, 0, 8, 8], true, true, 8]);
  });

  test('textures from ImageBitmap decoded natively (PNG)', () async {
    if (!GlSurfaces.available) return markTestSkipped('no EGL/OpenGL ES 3');
    final h = harness = WebHarness('<p>x</p>');
    // 2x1 PNG: red, blue.
    const png = 'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAIAAAB7QOjdAAAAEElEQVR4nGP4z8DAwPCfAQAG/AH/i1Ce2gAAAABJRU5ErkJggg==';
    final out = await h.async('''
      const bytes = Uint8Array.from(atob('$png'), (c) => c.charCodeAt(0));
      createImageBitmap(new Blob([bytes], { type: 'image/png' })).then((bmp) => {
        const gl = new OffscreenCanvas(2, 1).getContext('webgl2');
        const tex = gl.createTexture();
        gl.bindTexture(gl.TEXTURE_2D, tex);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, bmp);
        const fb = gl.createFramebuffer();
        gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
        gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, tex, 0);
        const px = new Uint8Array(8);
        gl.readPixels(0, 0, 2, 1, gl.RGBA, gl.UNSIGNED_BYTE, px);
        out = [bmp.width, bmp.height, Array.from(px), gl.checkFramebufferStatus(gl.FRAMEBUFFER) === gl.FRAMEBUFFER_COMPLETE];
      }, (e) => { out = String(e); });
    ''');
    expect(out, [2, 1, [255, 0, 0, 255, 0, 0, 255, 255], true]);
  });

  test('a worker renders into a transferred canvas and frames reach its surface', () async {
    if (!GlSurfaces.available) return markTestSkipped('no EGL/OpenGL ES 3');
    final h = harness = WebHarness('<canvas id="c" width="16" height="16"></canvas>');
    final out = await h.async('''
      const src = `onmessage = (e) => {
        const canvas = e.data.canvas;
        const gl = canvas.getContext('webgl2', { antialias: true });
        ${_triangle.replaceAll('`', r'\`').replaceAll(r'$', r'\$')}
        requestAnimationFrame(() => { gl.clearColor(0, 0, 1, 1); gl.clear(gl.COLOR_BUFFER_BIT); postMessage('drawn'); });
      };`;
      const w = new Worker(URL.createObjectURL(new Blob([src])));
      const off = document.getElementById('c').transferControlToOffscreen();
      w.onmessage = (e) => { out = e.data; };
      w.postMessage({ canvas: off }, [off]);
    ''', ms: 600);
    expect(h.errors, isEmpty);
    expect(out, 'drawn');
    final canvas = h.document.getElementById('c')!;
    final surface = dom.canvasSurfaces[canvas]!;
    final frame = GlSurfaces.acquire(surface)!;
    expect([frame.width, frame.height], [16, 16]);
    expect(frame.pixels.sublist(0, 4), [0, 0, 255, 255], reason: 'latest frame: the blue clear from rAF');
  });
}
