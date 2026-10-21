import 'package:nativa_js/nativa_js.dart';
import 'package:test/test.dart';

void main() {
  test('native WebGL: clear, readPixels and present to a surface', () {
    if (!GlSurfaces.available) {
      markTestSkipped('no EGL/OpenGL ES 3 on this machine');
      return;
    }
    final engine = QuickJsEngine();
    addTearDown(engine.dispose);
    final surface = GlSurfaces.create();
    addTearDown(() => GlSurfaces.release(surface));
    final out = engine.evaluate('''
      const n = __nx.gl;
      // surface, version, alpha, depth, stencil, antialias, premultiplied, preserve, w, h
      const h = n.createContext($surface, 2, true, true, false, true, true, false, 4, 3);
      n.clearColor(h, 1, 0, 0, 1);
      n.clear(h, 0x4000);
      const px = new Uint8Array(4);
      n.readPixels(h, 0, 0, 1, 1, 0x1908, 0x1401, px, 0);
      n.present(h);
      const r = [h > 0, Array.from(px), n.getString(h, 0x1F02)];
      n.destroyContext(h);
      r;
    ''') as List;
    expect(out[0], true);
    expect(out[1], [255, 0, 0, 255]);
    expect(out[2], contains('OpenGL ES 3'));
    final frame = GlSurfaces.acquire(surface)!;
    expect([frame.width, frame.height, frame.frame], [4, 3, 1]);
    expect(frame.pixels.sublist(0, 4), [255, 0, 0, 255]);
  });
}
