import 'dart:typed_data';

import 'package:nativa_js/nativa_js.dart';
import 'package:test/test.dart';

/// Minimal `(i32, i32) -> i32` module exported as `add`.
final Uint8List _addModule = Uint8List.fromList(const [
  0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, //
  0x01, 0x07, 0x01, 0x60, 0x02, 0x7f, 0x7f, 0x01, 0x7f,
  0x03, 0x02, 0x01, 0x00,
  0x07, 0x07, 0x01, 0x03, 0x61, 0x64, 0x64, 0x00, 0x00,
  0x0a, 0x09, 0x01, 0x07, 0x00, 0x20, 0x00, 0x20, 0x01, 0x6a, 0x0b,
]);

/// One page of memory exported as `memory`.
final Uint8List _memoryModule = Uint8List.fromList(const [
  0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, //
  0x05, 0x03, 0x01, 0x00, 0x01,
  0x07, 0x0a, 0x01, 0x06, 0x6d, 0x65, 0x6d, 0x6f, 0x72, 0x79, 0x02, 0x00,
]);

/// `(i64, i64) -> i64` exported as `add64`.
final Uint8List _add64Module = Uint8List.fromList(const [
  0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, //
  0x01, 0x07, 0x01, 0x60, 0x02, 0x7e, 0x7e, 0x01, 0x7e,
  0x03, 0x02, 0x01, 0x00,
  0x07, 0x09, 0x01, 0x05, 0x61, 0x64, 0x64, 0x36, 0x34, 0x00, 0x00,
  0x0a, 0x09, 0x01, 0x07, 0x00, 0x20, 0x00, 0x20, 0x01, 0x7c, 0x0b,
]);

/// Imports `env.inc: (i32) -> i32` and exports `call(i32) = inc(x, 1)`.
final Uint8List _importModule = Uint8List.fromList(const [
  0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, //
  0x01, 0x06, 0x01, 0x60, 0x01, 0x7f, 0x01, 0x7f,
  0x02, 0x0b, 0x01, 0x03, 0x65, 0x6e, 0x76, 0x03, 0x69, 0x6e, 0x63, 0x00, 0x00,
  0x03, 0x02, 0x01, 0x00,
  0x07, 0x08, 0x01, 0x04, 0x63, 0x61, 0x6c, 0x6c, 0x00, 0x01,
  0x0a, 0x08, 0x01, 0x06, 0x00, 0x20, 0x00, 0x10, 0x00, 0x0b,
]);

/// Grows its exported memory from wasm itself (`memory.grow`).
final Uint8List _growModule = Uint8List.fromList(const [
  0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, //
  0x01, 0x06, 0x01, 0x60, 0x01, 0x7f, 0x01, 0x7f,
  0x03, 0x02, 0x01, 0x00,
  0x05, 0x04, 0x01, 0x01, 0x01, 0x04,
  0x07, 0x11, 0x02, 0x04, 0x67, 0x72, 0x6f, 0x77, 0x00, 0x00,
  0x06, 0x6d, 0x65, 0x6d, 0x6f, 0x72, 0x79, 0x02, 0x00,
  0x0a, 0x08, 0x01, 0x06, 0x00, 0x20, 0x00, 0x40, 0x00, 0x0b,
]);
final Uint8List _loopModule = Uint8List.fromList(const [
  0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, //
  0x01, 0x04, 0x01, 0x60, 0x00, 0x00,
  0x03, 0x02, 0x01, 0x00,
  0x07, 0x07, 0x01, 0x03, 0x72, 0x75, 0x6e, 0x00, 0x00,
  0x0a, 0x09, 0x01, 0x07, 0x00, 0x03, 0x40, 0x0c, 0x00, 0x0b, 0x0b,
]);

void main() {
  late QuickJsEngine engine;
  setUp(() => engine = QuickJsEngine());
  tearDown(() => engine.dispose());

  test('compiles, validates and instantiates a module', () {
    final result = engine.evaluate('''
      (() => {
        const bytes = new Uint8Array(${_addModule.toList()});
        if (!WebAssembly.validate(bytes)) throw new Error('not valid');
        const module = new WebAssembly.Module(bytes);
        const instance = new WebAssembly.Instance(module, {});
        const view = new DataView(bytes.buffer);
        const fromView = new WebAssembly.Instance(new WebAssembly.Module(view), {});
        return [instance.exports.add(20, 22), module instanceof WebAssembly.Module,
                instance instanceof WebAssembly.Instance,
                fromView.exports.add(1, 2),
                Object.prototype.toString.call(instance.exports.add)];
      })()
    ''');
    expect(result, [42, true, true, 3, '[object Function]']);
  });

  test('async compile/instantiate return standard shapes', () async {
    engine.evaluate('''
      globalThis.ready = null;
      WebAssembly.instantiate(new Uint8Array(${_addModule.toList()}), {})
        .then(async ({module, instance}) => ({
          sum: instance.exports.add(-2, 5),
          module: module instanceof WebAssembly.Module,
          instance: instance instanceof WebAssembly.Instance,
          same: (await WebAssembly.instantiate(module)) instanceof WebAssembly.Instance,
        }))
        .then((value) => { globalThis.ready = value; });
    ''');
    for (var i = 0; i < 100 && engine.evaluate('globalThis.ready') == null; i++) {
      engine.drainMicrotasks();
    }
    final ready = engine.evaluate('globalThis.ready') as Map;
    expect(ready['sum'], 3);
    expect(ready['module'], isTrue);
    expect(ready['instance'], isTrue);
    expect(ready['same'], isTrue);
  });

  test('linear memory exposes a live buffer and grows', () {
    final result = engine.evaluate('''
      (() => {
        const instance = new WebAssembly.Instance(
          new WebAssembly.Module(new Uint8Array(${_memoryModule.toList()})), {});
        const memory = instance.exports.memory;
        const before = memory.buffer;
        const initial = before.byteLength;
        new Uint8Array(before)[0] = 0x7b;
        const oldPages = memory.grow(1);
        const after = memory.buffer;
        return [initial, after.byteLength, oldPages,
                new Uint8Array(after)[0], before.byteLength,
                memory instanceof WebAssembly.Memory];
      })()
    ''');
    expect(result, [65536, 131072, 1, 0x7b, 0, true]);
  });

  test('bad bytes produce a CompileError and validate returns false', () {
    final result = engine.evaluate('''
      (() => {
        const bad = new Uint8Array([0, 0x61, 0x73, 0x6d, 1, 0, 0, 0, 1]);
        let name = null;
        try { new WebAssembly.Module(bad); } catch (e) { name = e.name + ':' + (e instanceof WebAssembly.CompileError); }
        return [WebAssembly.validate(bad), name];
      })()
    ''');
    expect(result, [false, 'CompileError:true']);
  });

  test('i64 values cross the boundary as BigInt', () {
    final result = engine.evaluate('''
      (() => {
        const instance = new WebAssembly.Instance(
          new WebAssembly.Module(new Uint8Array(${_add64Module.toList()})), {});
        const value = instance.exports.add64(9007199254740991n, 2n);
        return [typeof value, value.toString()];
      })()
    ''');
    expect(result, ['bigint', '9007199254740993']);
  });

  test('JS imports receive numbers and thrown errors propagate unchanged', () {
    final result = engine.evaluate('''
      (() => {
        const instance = new WebAssembly.Instance(
          new WebAssembly.Module(new Uint8Array(${_importModule.toList()})),
          { env: { inc: (x) => x + 1 } });
        const sum = instance.exports.call(41);
        let error = null;
        const other = new WebAssembly.Instance(
          new WebAssembly.Module(new Uint8Array(${_importModule.toList()})),
          { env: { inc: () => { throw new RangeError('boom'); } } });
        try { other.exports.call(1); } catch (e) { error = e.name + ':' + e.message + ':' + (e instanceof RangeError); }
        return [sum, error];
      })()
    ''');
    expect(result, [42, 'RangeError:boom:true']);
  });

  test('a module can be instantiated more than once with isolated memory', () {
    final result = engine.evaluate('''
      (() => {
        const module = new WebAssembly.Module(new Uint8Array(${_memoryModule.toList()}));
        const a = new WebAssembly.Instance(module, {}).exports.memory;
        const b = new WebAssembly.Instance(module, {}).exports.memory;
        new Uint8Array(a.buffer)[0] = 1;
        return [new Uint8Array(a.buffer)[0], new Uint8Array(b.buffer)[0],
                a.buffer !== b.buffer];
      })()
    ''');
    expect(result, [1, 0, true]);
  });

  test('memory.grow inside wasm detaches the old JS buffer', () {
    final result = engine.evaluate('''
      (() => {
        const instance = new WebAssembly.Instance(
          new WebAssembly.Module(new Uint8Array(${_growModule.toList()})), {});
        const memory = instance.exports.memory;
        const before = memory.buffer;
        new Uint8Array(before)[0] = 7;
        const oldPages = instance.exports.grow(1);
        const after = memory.buffer;
        return [oldPages, after.byteLength, before.byteLength,
                before !== after, new Uint8Array(after)[0]];
      })()
    ''');
    expect(result, [1, 131072, 0, true, 7]);
  });

  test('a runaway wasm loop is stopped by the gas budget', () {
    expect(
      () => engine.evaluate('''
        new WebAssembly.Instance(
          new WebAssembly.Module(new Uint8Array(${_loopModule.toList()})), {})
          .exports.run()
      '''),
      throwsA(isA<JavaScriptException>()
          .having((e) => e.name, 'name', 'RuntimeError')
          .having((e) => e.message, 'message', contains('out of gas'))),
    );
  });

  test('Module.imports/exports expose the link shape', () {
    final result = engine.evaluate('''
      (() => {
        const module = new WebAssembly.Module(new Uint8Array(${_importModule.toList()}));
        const imports = WebAssembly.Module.imports(module);
        const exports = WebAssembly.Module.exports(module);
        return [imports.length, imports[0].module, imports[0].name,
                imports[0].kind, exports.length, exports[0].name,
                exports[0].kind];
      })()
    ''');
    expect(result, [1, 'env', 'inc', 'function', 1, 'call', 'function']);
  });

  test('missing imports fail with LinkError and import callbacks run', () {
    final missing = engine.evaluate('''
      (() => {
        try {
          new WebAssembly.Instance(
            new WebAssembly.Module(new Uint8Array(${_importModule.toList()})), {});
        } catch (e) { return e.name + ':' + (e instanceof WebAssembly.LinkError); }
      })()
    ''');
    expect(missing, 'LinkError:true');

    // The full linker path (32 wasm-bindgen imports calling back into JS) is
    // covered by packages/nativax/test/wasm_rapier_test.dart.
  });
}
