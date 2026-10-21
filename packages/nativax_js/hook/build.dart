import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

/// Compiles QuickJS-ng (vendored under third_party/quickjs) together with the
/// NativaX C bridge into a single dynamic library bundled as a code asset.
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final os = input.config.code.targetOS;
    final arch = input.config.code.targetArchitecture;
    final is64Bit = arch == Architecture.arm64 ||
        arch == Architecture.arm64e ||
        arch == Architecture.x64 ||
        arch == Architecture.riscv64;
    final builder = CBuilder.library(
      name: 'nativax_quickjs',
      assetName: 'src/ffi/bindings.dart',
      sources: [
        'src/nativax_bridge.c',
        'src/nativax_wasm.c',
        if (os == OS.linux || os == OS.android) 'src/nativax_gl.c' else 'src/nativax_gl_stub.c',
        'third_party/quickjs/quickjs.c',
        'third_party/quickjs/libregexp.c',
        'third_party/quickjs/libunicode.c',
        'third_party/quickjs/dtoa.c',
        'third_party/wasm3/m3_bind.c',
        'third_party/wasm3/m3_code.c',
        'third_party/wasm3/m3_compile.c',
        'third_party/wasm3/m3_core.c',
        'third_party/wasm3/m3_deterministic.c',
        'third_party/wasm3/m3_env.c',
        'third_party/wasm3/m3_exec.c',
        'third_party/wasm3/m3_function.c',
        'third_party/wasm3/m3_info.c',
        'third_party/wasm3/m3_module.c',
        'third_party/wasm3/m3_parse.c',
        'third_party/wasm3/m3_snapshot.c',
        'third_party/wasm3/m3_validate.c',
        'third_party/wasm3/m3_xxh64.c',
      ],
      includes: const [
        'third_party/quickjs',
        'third_party/wasm3',
        'third_party/khronos',
        'third_party/stb',
        'src',
      ],
      defines: {
        '_GNU_SOURCE': null,
        // wasm3 checks this against the native stack before entering wasm.
        // Keep it below iOS worker-thread stacks (512 KiB); Rapier's deepest
        // calls are far shorter than this.
        'd_m3MaxNativeStack': '393216',
        // 64-bit slots avoid the alignment dance wasm3 needs in 32-bit slot
        // mode. 32-bit targets keep the documented default.
        if (is64Bit) 'd_m3Use32BitSlots': '0',
        if (os == OS.windows) 'WIN32_LEAN_AND_MEAN': null,
      },
      flags: [
        if (os != OS.windows) ...['-w', '-fvisibility=hidden'],
        if (os == OS.windows) ...['/experimental:c11atomics', '/w'],
      ],
      libraries: [
        if (os == OS.linux || os == OS.android) 'm',
        if (os == OS.linux || os == OS.android) 'dl',
        if (os == OS.linux) 'pthread',
      ],
      std: os == OS.windows ? 'c11' : 'gnu11',
    );
    await builder.run(
      input: input,
      output: output,
      logger: Logger('')
        ..level = Level.INFO
        ..onRecord.listen((r) => print(r.message)),
    );
  });
}
