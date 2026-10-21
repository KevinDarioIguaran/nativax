import 'entities.dart';
import 'token.dart';

/// Elements whose content is not markup. `script`/`style` are raw text;
/// `textarea`/`title` are RCDATA (character references are decoded).
const Set<String> rawTextTags = {'script', 'style'};
const Set<String> rcdataTags = {'textarea', 'title'};

typedef ErrorSink = void Function(String code, int offset, [String? detail]);

/// A single-pass, linear-time HTML tokenizer modelled on the WHATWG
/// tokenizer states (data, tag open, tag name, attribute name/value,
/// markup declaration, comment, raw text). No regular expressions are used
/// on the markup itself.
class HtmlTokenizer {
  HtmlTokenizer(this.src, {required this.onError});

  final String src;
  final ErrorSink onError;
  int _pos = 0;

  bool get _eof => _pos >= src.length;

  static bool _isWs(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0c || c == 0x0d;
  static bool _isAlpha(int c) =>
      (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a);

  Iterable<Token> tokenize() sync* {
    final text = StringBuffer();
    var textStart = 0;

    Token? flushText() {
      if (text.isEmpty) return null;
      final t = TextToken(textStart, text.toString());
      text.clear();
      return t;
    }

    while (!_eof) {
      final c = src.codeUnitAt(_pos);
      if (c == 0x3c /* < */ ) {
        final tagStart = _pos;
        _dropped = false;
        final tag = _tryTag();
        if (_dropped) continue;
        if (tag == null) {
          if (text.isEmpty) textStart = tagStart;
          text.write('<');
          continue;
        }
        final pending = flushText();
        if (pending != null) yield pending;
        yield tag;
        if (tag is StartTagToken &&
            !tag.selfClosing &&
            (rawTextTags.contains(tag.name) || rcdataTags.contains(tag.name))) {
          final body = _rawText(
            tag.name,
            decode: rcdataTags.contains(tag.name),
          );
          if (body.data.isNotEmpty) yield body;
          if (_closedRaw) yield EndTagToken(_pos, tag.name);
        }
      } else if (c == 0x26 /* & */ ) {
        if (text.isEmpty) textStart = _pos;
        text.write(_charRef(inAttribute: false));
      } else {
        if (text.isEmpty) textStart = _pos;
        // Fast path: copy a run of plain characters at once.
        final start = _pos;
        while (!_eof) {
          final d = src.codeUnitAt(_pos);
          if (d == 0x3c || d == 0x26) break;
          _pos++;
        }
        text.write(src.substring(start, _pos));
      }
    }
    final pending = flushText();
    if (pending != null) yield pending;
  }

  bool _closedRaw = false;

  /// Set when a tag was truncated by EOF and must be dropped entirely.
  bool _dropped = false;

  /// Consumes content up to `</name` (case-insensitive) followed by
  /// whitespace, `/` or `>`.
  TextToken _rawText(String name, {required bool decode}) {
    final start = _pos;
    _closedRaw = false;
    var search = _pos;
    while (true) {
      final i = _indexOfEndTag(name, search);
      if (i < 0) {
        onError('eof-in-$name', start);
        _pos = src.length;
        final body = src.substring(start);
        return TextToken(start, decode ? _decodeAll(body) : body);
      }
      final after = i + 2 + name.length;
      // A tag name at EOF without `>` is not a complete end tag: keep the
      // text (`</script` at EOF is script data, not a closing tag).
      if (after < src.length &&
          (_isWs(src.codeUnitAt(after)) ||
              src.codeUnitAt(after) == 0x2f ||
              src.codeUnitAt(after) == 0x3e)) {
        final body = src.substring(start, i);
        _pos = after;
        // Skip to the closing '>'.
        while (!_eof && src.codeUnitAt(_pos) != 0x3e) {
          _pos++;
        }
        if (!_eof) _pos++;
        _closedRaw = true;
        return TextToken(start, decode ? _decodeAll(body) : body);
      }
      search = after;
    }
  }

  /// Index of `</name` (ASCII case-insensitive) at or after [from], or -1.
  int _indexOfEndTag(String name, int from) {
    var i = from;
    while (true) {
      i = src.indexOf('</', i);
      if (i < 0 || i + 2 + name.length > src.length) return -1;
      var match = true;
      for (var k = 0; k < name.length; k++) {
        if ((src.codeUnitAt(i + 2 + k) | 0x20) != name.codeUnitAt(k)) {
          match = false;
          break;
        }
      }
      if (match) return i;
      i += 2;
    }
  }

  String _decodeAll(String s) {
    if (!s.contains('&')) return s;
    final sub = HtmlTokenizer(s, onError: (_, _, [_]) {});
    final buf = StringBuffer();
    while (!sub._eof) {
      final c = s.codeUnitAt(sub._pos);
      if (c == 0x26) {
        buf.write(sub._charRef(inAttribute: false));
      } else {
        buf.writeCharCode(c);
        sub._pos++;
      }
    }
    return buf.toString();
  }

  /// At '<'. Returns a token, or null when '<' is literal text (in which
  /// case the position has advanced past '<').
  Token? _tryTag() {
    final start = _pos;
    _pos++; // <
    if (_eof) {
      onError('eof-before-tag-name', start);
      return null;
    }
    final c = src.codeUnitAt(_pos);
    if (c == 0x21 /* ! */ ) return _markupDeclaration(start);
    if (c == 0x2f /* / */ ) {
      _pos++;
      if (_eof) {
        onError('eof-before-tag-name', start);
        _pos = start + 1;
        return null;
      }
      final d = src.codeUnitAt(_pos);
      if (d == 0x3e) {
        onError('missing-end-tag-name', start);
        _pos++;
        return null;
      }
      if (!_isAlpha(d)) {
        onError('invalid-first-character-of-tag-name', start);
        return _bogusComment(start);
      }
      final name = _tagName();
      // End tags may not carry attributes; skip anything up to '>'.
      final attrs = _attributes(start);
      if (attrs.$1.isNotEmpty) onError('end-tag-with-attributes', start);
      if (attrs.$3) return EndTagToken(start, name);
      _dropped = true;
      return null;
    }
    if (c == 0x3f /* ? */ ) {
      onError('unexpected-question-mark-instead-of-tag-name', start);
      return _bogusComment(start);
    }
    if (!_isAlpha(c)) {
      onError('invalid-first-character-of-tag-name', start);
      return null;
    }
    final name = _tagName();
    final (attrs, selfClosing, closed) = _attributes(start);
    if (!closed) {
      _dropped = true;
      return null;
    }
    return StartTagToken(start, name, attrs, selfClosing: selfClosing);
  }

  String _tagName() {
    final start = _pos;
    while (!_eof) {
      final c = src.codeUnitAt(_pos);
      if (_isWs(c) || c == 0x2f || c == 0x3e) break;
      _pos++;
    }
    return src.substring(start, _pos).toLowerCase();
  }

  /// Returns (attributes, selfClosing, closedWithGt). When EOF is reached
  /// inside the tag, the whole tag is dropped (as the HTML spec does).
  (List<(String, String)>, bool, bool) _attributes(int tagStart) {
    final attrs = <(String, String)>[];
    final seen = <String>{};
    var selfClosing = false;
    while (true) {
      while (!_eof && _isWs(src.codeUnitAt(_pos))) {
        _pos++;
      }
      if (_eof) {
        onError('eof-in-tag', tagStart);
        return (attrs, false, false);
      }
      final c = src.codeUnitAt(_pos);
      if (c == 0x3e) {
        _pos++;
        return (attrs, selfClosing, true);
      }
      if (c == 0x2f) {
        _pos++;
        if (!_eof && src.codeUnitAt(_pos) == 0x3e) {
          selfClosing = true;
        } else {
          onError('unexpected-solidus-in-tag', _pos);
        }
        continue;
      }
      // Attribute name.
      final nameStart = _pos;
      if (c == 0x3d) {
        onError('unexpected-equals-sign-before-attribute-name', _pos);
        _pos++;
      }
      while (!_eof) {
        final d = src.codeUnitAt(_pos);
        if (_isWs(d) ||
            d == 0x2f ||
            d == 0x3e ||
            (d == 0x3d && _pos > nameStart))
          break;
        if (d == 0x22 || d == 0x27 || d == 0x3c) {
          onError('unexpected-character-in-attribute-name', _pos);
        }
        _pos++;
      }
      final name = src.substring(nameStart, _pos).toLowerCase();
      while (!_eof && _isWs(src.codeUnitAt(_pos))) {
        _pos++;
      }
      var value = '';
      if (!_eof && src.codeUnitAt(_pos) == 0x3d) {
        _pos++;
        while (!_eof && _isWs(src.codeUnitAt(_pos))) {
          _pos++;
        }
        if (_eof) {
          onError('eof-in-tag', tagStart);
          return (attrs, false, false);
        }
        final q = src.codeUnitAt(_pos);
        if (q == 0x22 || q == 0x27) {
          _pos++;
          final buf = StringBuffer();
          while (!_eof && src.codeUnitAt(_pos) != q) {
            if (src.codeUnitAt(_pos) == 0x26) {
              buf.write(_charRef(inAttribute: true));
            } else {
              buf.writeCharCode(src.codeUnitAt(_pos));
              _pos++;
            }
          }
          if (_eof) {
            onError('eof-in-tag', tagStart);
            return (attrs, false, false);
          }
          _pos++;
          value = buf.toString();
          if (!_eof) {
            final n = src.codeUnitAt(_pos);
            if (!_isWs(n) && n != 0x2f && n != 0x3e) {
              onError('missing-whitespace-between-attributes', _pos);
            }
          }
        } else if (q == 0x3e) {
          onError('missing-attribute-value', _pos);
        } else {
          final buf = StringBuffer();
          while (!_eof) {
            final d = src.codeUnitAt(_pos);
            if (_isWs(d) || d == 0x3e) break;
            if (d == 0x26) {
              buf.write(_charRef(inAttribute: true));
              continue;
            }
            if (d == 0x22 || d == 0x27 || d == 0x3c || d == 0x3d || d == 0x60) {
              onError('unexpected-character-in-unquoted-attribute-value', _pos);
            }
            buf.writeCharCode(d);
            _pos++;
          }
          value = buf.toString();
        }
      }
      if (name.isEmpty) continue;
      if (seen.add(name)) {
        attrs.add((name, value));
      } else {
        onError('duplicate-attribute', nameStart, name);
      }
    }
  }

  Token? _markupDeclaration(int start) {
    // At '!'.
    if (src.startsWith('!--', _pos)) {
      _pos += 3;
      final end = src.indexOf('-->', _pos);
      if (end < 0) {
        onError('eof-in-comment', start);
        final data = src.substring(_pos);
        _pos = src.length;
        return CommentToken(start, data);
      }
      final data = src.substring(_pos, end);
      _pos = end + 3;
      return CommentToken(start, data);
    }
    if (src.length - _pos >= 8 &&
        src.substring(_pos + 1, _pos + 8).toLowerCase() == 'doctype') {
      _pos += 8;
      final end = src.indexOf('>', _pos);
      final body = src.substring(_pos, end < 0 ? src.length : end).trim();
      _pos = end < 0 ? src.length : end + 1;
      if (end < 0) onError('eof-in-doctype', start);
      final nameMatch = RegExp(r'^([^\s>]+)').firstMatch(body);
      final name = nameMatch?.group(1)?.toLowerCase() ?? '';
      final rest = nameMatch == null
          ? ''
          : body.substring(nameMatch.end).trim();
      var publicId = '';
      var systemId = '';
      final public = RegExp(
        r'''^PUBLIC\s+(?:"([^"]*)"|'([^']*)')(?:\s+(?:"([^"]*)"|'([^']*)'))?''',
        caseSensitive: false,
      ).firstMatch(rest);
      if (public != null) {
        publicId = public.group(1) ?? public.group(2) ?? '';
        systemId = public.group(3) ?? public.group(4) ?? '';
      } else {
        final system = RegExp(
          r'''^SYSTEM\s+(?:"([^"]*)"|'([^']*)')''',
          caseSensitive: false,
        ).firstMatch(rest);
        if (system != null) systemId = system.group(1) ?? system.group(2) ?? '';
      }
      return DoctypeToken(start, name, publicId: publicId, systemId: systemId);
    }
    onError('incorrectly-opened-comment', start);
    return _bogusComment(start);
  }

  CommentToken _bogusComment(int start) {
    final end = src.indexOf('>', _pos);
    final data = src.substring(_pos, end < 0 ? src.length : end);
    _pos = end < 0 ? src.length : end + 1;
    return CommentToken(start, data);
  }

  /// At '&'. Returns the decoded text and advances.
  String _charRef({required bool inAttribute}) {
    final start = _pos;
    _pos++; // &
    if (_eof) return '&';
    if (src.codeUnitAt(_pos) == 0x23 /* # */ ) {
      _pos++;
      var hex = false;
      if (!_eof && (src.codeUnitAt(_pos) | 0x20) == 0x78 /* x */ ) {
        hex = true;
        _pos++;
      }
      final digitsStart = _pos;
      while (!_eof) {
        final d = src.codeUnitAt(_pos) | 0x20;
        final isDigit =
            (d >= 0x30 && d <= 0x39) || (hex && d >= 0x61 && d <= 0x66);
        if (!isDigit) break;
        _pos++;
      }
      if (_pos == digitsStart) {
        onError('absence-of-digits-in-numeric-character-reference', start);
        _pos = start + 1;
        return '&';
      }
      final digits = src.substring(digitsStart, _pos);
      if (!_eof && src.codeUnitAt(_pos) == 0x3b) {
        _pos++;
      } else {
        onError('missing-semicolon-after-character-reference', start);
      }
      final code = digits.length > 8
          ? 0x110000
          : int.parse(digits, radix: hex ? 16 : 10);
      if (code == 0 || code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff)) {
        onError('invalid-character-reference', start);
        return '�';
      }
      return String.fromCharCode(code);
    }
    final nameStart = _pos;
    while (!_eof && _pos - nameStart < 32) {
      final d = src.codeUnitAt(_pos);
      if (!_isAlpha(d) && !(d >= 0x30 && d <= 0x39)) break;
      _pos++;
    }
    final name = src.substring(nameStart, _pos);
    final hasSemicolon = !_eof && src.codeUnitAt(_pos) == 0x3b;

    if (hasSemicolon) {
      final value = namedEntities[name];
      if (value != null) {
        _pos++;
        return value;
      }
    }

    // No exact (possibly semicolon-terminated) match: use the longest legacy
    // prefix, as required by the named character reference state. In
    // attribute values a legacy reference followed by an alphanumeric or `=`
    // is not decoded.
    var prefixLength = name.length;
    while (prefixLength > 0 &&
        !legacyNamedEntities.containsKey(name.substring(0, prefixLength))) {
      prefixLength--;
    }
    if (prefixLength > 0) {
      final end = nameStart + prefixLength;
      final next = end < src.length ? src.codeUnitAt(end) : -1;
      final blocked =
          inAttribute &&
          (next == 0x3d ||
              (next >= 0x30 && next <= 0x39) ||
              (next >= 0x41 && next <= 0x5a) ||
              (next >= 0x61 && next <= 0x7a));
      if (blocked) {
        _pos = start + 1;
        return '&';
      }
      _pos = end;
      onError('missing-semicolon-after-character-reference', start);
      return legacyNamedEntities[name.substring(0, prefixLength)]!;
    }

    if (name.isNotEmpty && hasSemicolon) {
      onError('unknown-named-character-reference', start, name);
    }
    _pos = start + 1;
    return '&';
  }
}
