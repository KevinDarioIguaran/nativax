import 'dart:io';

import 'package:nativa_benchmark/render_fixtures.dart';

void main(List<String> args) {
  final nodes = args.isEmpty ? 800 : int.parse(args[0]);
  final out = args.length > 1 ? args[1] : '/tmp/tailwind_app_$nodes.html';
  writeFixture('tailwind-app', nodes, out);
  stdout.writeln('wrote $out');
}
