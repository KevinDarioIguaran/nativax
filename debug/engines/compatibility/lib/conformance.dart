/// Conformance runners and reporting for NativaX.
///
/// The suites are not vendored: `bin/fetch_suites.dart` downloads pinned
/// commits into `.conformance/suites/<suite>`, and the runners read them from
/// there. Results are written as JSONL plus a Markdown summary.
library;

export 'src/html5lib_runner.dart';
export 'src/html_tree_runner.dart';
export 'src/report.dart';
export 'src/result.dart';
export 'src/suite_paths.dart';
export 'src/test262_runner.dart';
export 'src/url_runner.dart';
export 'src/validation.dart';
export 'src/wpt_runner.dart';
