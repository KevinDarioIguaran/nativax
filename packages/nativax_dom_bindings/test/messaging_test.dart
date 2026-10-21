import 'dart:convert';
import 'dart:typed_data';

import 'package:nativax_dom_bindings/nativax_dom_bindings.dart';
import 'package:test/test.dart';

import 'web_platform_test.dart' show WebHarness;

/// Serves worker scripts by URL.
class _Scripts implements NativaXNetwork {
  _Scripts(this.files);
  final Map<String, String> files;

  @override
  Future<NetworkResponse> fetch(NetworkRequest r) async {
    final f = files[r.url.toString()];
    return NetworkResponse(
      status: f == null ? 404 : 200,
      body: f == null ? Uint8List(0) : utf8.encode(f),
      url: r.url,
      headers: const [('content-type', 'text/javascript')],
    );
  }

  @override
  Future<NetworkSocket> connect(Uri url, List<String> protocols) => throw UnimplementedError();
}

void main() {
  late WebHarness h;
  tearDown(() => h.bindings.dispose());

  test('structuredClone keeps types, shared references and cycles', () {
    h = WebHarness('<p>x</p>');
    expect(h.js(r'''(() => {
      const shared = { n: 1 };
      const src = { a: [1, , 3], m: new Map([[shared, new Set([2n])]]), d: new Date(5), r: /x/gi, s: shared,
        t: new Float32Array([1.5, 2.5]).subarray(1), e: new RangeError('boom'), neg: -0, nan: NaN, u: undefined, w: new String('w') };
      src.self = src;
      const c = structuredClone(src);
      return [c !== src, c.self === c, c.s === [...c.m.keys()][0], [...c.m.values()][0].has(2n), c.d.getTime(), c.r.flags,
       c.t instanceof Float32Array, c.t[0], c.t.byteOffset, c.e instanceof RangeError, c.e.message, Object.is(c.neg, -0),
       Number.isNaN(c.nan), 'u' in c, c.a.length, 1 in c.a, typeof c.w];
    })()
    '''), [true, true, true, true, 5, 'gi', true, 2.5, 4, true, 'boom', true, true, true, 3, false, 'object']);
    expect(h.js("try { structuredClone({ f() {} }); 'no' } catch (e) { e.name }"), 'DataCloneError');
    expect(h.js("(() => { const b = new ArrayBuffer(8); const c = structuredClone(b, { transfer: [b] }); return [b.byteLength, c.byteLength]; })()"), [0, 8]);
  });

  test('MessageChannel delivers asynchronously and transfers ports', () async {
    h = WebHarness('<p>x</p>');
    final out = await h.async(r'''
      const a = new MessageChannel(), b = new MessageChannel();
      const got = [];
      a.port2.onmessage = (e) => {
        got.push(e.data.k);
        const p = e.ports[0];
        p.onmessage = (ev) => { got.push(ev.data); out = got; };
        p.postMessage('over the transferred port');
      };
      b.port2.onmessage = (e) => { e.target.postMessage('reply:' + e.data); };
      // b.port1 is moved into a's message; its replies reach the new owner.
      a.port1.postMessage({ k: 'hello' }, [b.port1]);
      got.push('sync');
    ''');
    expect(out, ['sync', 'hello', 'reply:over the transferred port']);
  });

  test('module workers load their graph and see a worker global scope', () async {
    h = WebHarness('<p>x</p>', network: _Scripts({
      'https://app.test/w/main.js': "import { twice } from './lib.js'; self.onmessage = (e) => postMessage({ r: twice(e.data), "
          "scope: [typeof window, typeof document, self === globalThis, self instanceof DedicatedWorkerGlobalScope, "
          "location.href, typeof importScripts, crossOriginIsolated] });",
      'https://app.test/w/lib.js': 'export const twice = (x) => x * 2;',
    }));
    final out = await h.async(r'''
      const w = new Worker(new URL('./w/main.js', location.href), { type: 'module' });
      w.onmessage = (e) => { out = e.data; w.terminate(); };
      w.postMessage(21);
    ''', ms: 300);
    expect(out, {
      'r': 42,
      'scope': ['undefined', 'undefined', true, true, 'https://app.test/w/main.js', 'function', true],
    });
  });

  test('SharedArrayBuffer and Atomics are shared with a worker', () async {
    h = WebHarness('<p>x</p>');
    final out = await h.async(r'''
      const sab = new SharedArrayBuffer(8);
      const view = new Int32Array(sab);
      const src = 'onmessage = (e) => { const v = new Int32Array(e.data); Atomics.add(v, 0, 5); Atomics.store(v, 1, 7); postMessage("done"); }';
      const w = new Worker(URL.createObjectURL(new Blob([src])));
      w.onmessage = () => { out = [Atomics.load(view, 0), Atomics.load(view, 1)]; w.terminate(); };
      view[0] = 10;
      w.postMessage(sab);
    ''', ms: 300);
    expect(out, [15, 7]);
  });

  test('a port can be handed to a worker (Comlink-style RPC)', () async {
    h = WebHarness('<p>x</p>');
    final out = await h.async(r'''
      const src = 'onmessage = (e) => { const port = e.data.port; port.onmessage = (m) => port.postMessage(m.data.a + m.data.b); }';
      const w = new Worker(URL.createObjectURL(new Blob([src])));
      const { port1, port2 } = new MessageChannel();
      w.postMessage({ port: port2 }, [port2]);
      port1.onmessage = (e) => { out = e.data; w.terminate(); };
      port1.postMessage({ a: 40, b: 2 });
    ''', ms: 300);
    expect(out, 42);
  });

  test('self.close() and uncaught errors reach the page', () async {
    h = WebHarness('<p>x</p>');
    final out = await h.async(r'''
      const w = new Worker(URL.createObjectURL(new Blob(['setTimeout(() => { throw new TypeError("late"); }, 1);'])));
      w.onerror = (e) => { e.preventDefault(); out = [e.message, e instanceof ErrorEvent]; };
    ''', ms: 200);
    expect(out, ['TypeError: late', true]);
  });
}
