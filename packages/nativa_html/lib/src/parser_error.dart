/// A recoverable parse error. Parsing continues; errors are collected so
/// tooling can surface them instead of hiding malformed markup.
class HtmlParseError {
  const HtmlParseError(this.code, this.offset, this.line, this.column, [this.detail]);

  /// Stable identifier, e.g. `unexpected-end-tag`, `eof-in-tag`.
  final String code;
  final int offset;

  /// 1-based.
  final int line;
  final int column;
  final String? detail;

  @override
  String toString() =>
      '$line:$column $code${detail == null ? '' : ' ($detail)'}';
}

/// Input rejected by a hard limit (size, nodes or depth policy).
class HtmlLimitException implements Exception {
  HtmlLimitException(this.message);
  final String message;

  @override
  String toString() => 'HtmlLimitException: $message';
}

class HtmlParserLimits {
  const HtmlParserLimits({
    this.maxInputLength = 4 * 1024 * 1024,
    this.maxNodes = 100000,
    this.maxDepth = 200,
    this.maxErrors = 1000,
  });

  /// Characters; larger inputs are rejected before tokenizing.
  final int maxInputLength;

  /// Nodes created by one parse; exceeding it aborts the parse.
  final int maxNodes;

  /// Open-element depth. Deeper start tags are inserted as siblings at the
  /// limit instead of nesting further (reported as `nesting-too-deep`).
  final int maxDepth;

  /// Errors kept; later ones are counted but dropped.
  final int maxErrors;
}
