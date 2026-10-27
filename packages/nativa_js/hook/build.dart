import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

/// Compiles the engine-independent NativaX native support (memory, buffer
/// handoff, surfaces) into a dynamic library bundled as a code asset. The
/// script engine, JavaScriptCore, is not linked: `JscEngine` opens the
/// host's library at run time.
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final os = input.config.code.targetOS;
    final builder = CBuilder.library(
      name: 'nativax_native',
      assetName: 'src/ffi/bindings.dart',
      sources: const ['src/nativax_bridge.c', 'src/nativax_gl_stub.c'],
      includes: const ['src'],
      defines: {if (os == OS.windows) 'WIN32_LEAN_AND_MEAN': null},
      flags: [
        if (os != OS.windows) ...['-w', '-fvisibility=hidden'],
        if (os == OS.windows) '/w',
      ],
      libraries: [if (os == OS.linux) 'pthread'],
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
