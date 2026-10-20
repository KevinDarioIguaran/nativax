sealed class Token {
  const Token(this.offset);

  /// Offset of the token's first character in the source.
  final int offset;
}

class StartTagToken extends Token {
  StartTagToken(super.offset, this.name, this.attributes, {this.selfClosing = false});
  final String name;

  /// In source order; duplicates already removed (first wins, as in HTML).
  final List<(String, String)> attributes;
  final bool selfClosing;
}

class EndTagToken extends Token {
  const EndTagToken(super.offset, this.name);
  final String name;
}

class TextToken extends Token {
  const TextToken(super.offset, this.data);
  final String data;
}

class CommentToken extends Token {
  const CommentToken(super.offset, this.data);
  final String data;
}

class DoctypeToken extends Token {
  const DoctypeToken(super.offset, this.name);
  final String name;
}
