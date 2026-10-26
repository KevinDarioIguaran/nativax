import 'dart:io';

/// `debug/datasets/visual_comparison`, resolved from this package directory.
String defaultDatasetDir() {
  final package = File.fromUri(Platform.script).parent.parent.path;
  return Directory('$package/../../datasets/visual_comparison').absolute.path;
}
