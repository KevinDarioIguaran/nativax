import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

/// Compiles the NativaX C bridge (JavaScriptCore-backed) into a single
/// dynamic library bundled as a code asset. JavaScriptCore itself comes from
/// the host platform (system library / framework) and is opened via FFI.
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final os = input.config.code.targetOS;
    final builder = CBuilder.library(
      name: 'nativax_jsc',
      assetName: 'src/ffi/bindings.dart',
      sources: [
        'src/nativax_bridge.c',
        'src/nativax_jit.c',
      ],
      includes: [
        'src',
        if (os == OS.linux || os == OS.android) '/usr/include/webkitgtk-4.1',
      ],
      defines: {
        if (os == OS.windows) 'WIN32_LEAN_AND_MEAN': null,
      },
      flags: [
        if (os != OS.windows) ...['-w', '-fvisibility=hidden', '-fsigned-char'],
        if (os == OS.windows) ...['/experimental:c11atomics', '/w'],
      ],
      libraries: [
        if (os == OS.linux || os == OS.android) 'javascriptcoregtk-4.1',
        if (os == OS.linux || os == OS.android) 'm',
        if (os == OS.linux || os == OS.android) 'dl',
        if (os == OS.linux) 'pthread',
        if (os == OS.macOS || os == OS.iOS) 'JavaScriptCore',
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