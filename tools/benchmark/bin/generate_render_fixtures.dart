import 'dart:io';

import 'package:nativa_benchmark/render_fixtures.dart';

void main(List<String> args) {
  String? family;
  int? nodes;
  String? out;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--family':
      case '-f':
        family = args[++i];
      case '--nodes':
      case '-n':
        nodes = int.parse(args[++i]);
      case '--out':
      case '-o':
        out = args[++i];
      default:
        stderr.writeln('unknown argument: ${args[i]}');
        exit(64);
    }
  }
  if (out == null) {
    stderr.writeln('--out is required');
    exit(64);
  }
  writeFixture(family ?? 'list-overflow', nodes ?? 10000, out);
  stdout.writeln('wrote $out');
}
