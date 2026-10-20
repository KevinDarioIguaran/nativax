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
    final builder = CBuilder.library(
      name: 'nativax_quickjs',
      assetName: 'src/ffi/bindings.dart',
      sources: const [
        'src/nativax_bridge.c',
        'third_party/quickjs/quickjs.c',
        'third_party/quickjs/libregexp.c',
        'third_party/quickjs/libunicode.c',
        'third_party/quickjs/dtoa.c',
      ],
      includes: const ['third_party/quickjs'],
      defines: {
        '_GNU_SOURCE': null,
        if (os == OS.windows) 'WIN32_LEAN_AND_MEAN': null,
      },
      flags: [
        if (os != OS.windows) ...['-w', '-fvisibility=hidden'],
        if (os == OS.windows) ...['/experimental:c11atomics', '/w'],
      ],
      libraries: [if (os == OS.linux || os == OS.android) 'm'],
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
