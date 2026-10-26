// Prints, as JSON, whether nativa_css parses each property name given on the
// command line. Run from the repository root with the workspace config:
//
//   dart --packages=.dart_tool/package_config.json \
//     tools/audit/dart/css_support.dart width padding box-sizing
import 'dart:convert';

import 'package:nativa_css/nativa_css.dart';

void main(List<String> names) {
  print(jsonEncode({for (final name in names) name: isSupportedProperty(name)}));
}
