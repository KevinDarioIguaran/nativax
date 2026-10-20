/// CSS tokenizer following the structure of CSS Syntax Level 3 (§4), with
/// simplified escape handling and no `unicode-range` tokens.
library;

enum CssTokenType {
  ident,
  function, // value = name, '(' consumed
  atKeyword,
  hash,
  string,
  url,
  number,
  percentage,
  dimension,
  whitespace,
  delim,
  colon,
  semicolon,
  comma,
  leftBracket,
  rightBracket,
  leftParen,
  rightParen,
  leftBrace,
  rightBrace,
  cdo,
  cdc,
  badString,
  badUrl,
}

class CssToken {
  const CssToken(this.type, this.offset, {this.value = '', this.number = 0, this.unit = ''});
  final CssTokenType type;
  final int offset;

  /// Identifier/function/at-keyword/hash name, string or url contents, or the
  /// delimiter character.
  final String value;

  /// Numeric value for number/percentage/dimension.
  final double number;

  /// Lower-cased unit for dimensions.
  final String unit;

  bool isDelim(String c) => type == CssTokenType.delim && value == c;
  bool isIdent(String name) =>
      type == CssTokenType.ident && value.toLowerCase() == name;

  @override
  String toString() => switch (type) {
        CssTokenType.ident || CssTokenType.delim => value,
        CssTokenType.function => '$value(',
        CssTokenType.atKeyword => '@$value',
        CssTokenType.hash => '#$value',
        CssTokenType.string => '"$value"',
        CssTokenType.url => 'url($value)',
        CssTokenType.number => _num(number),
        CssTokenType.percentage => '${_num(number)}%',
        CssTokenType.dimension => '${_num(number)}$unit',
        CssTokenType.whitespace => ' ',
        CssTokenType.colon => ':',
        CssTokenType.semicolon => ';',
        CssTokenType.comma => ',',
        CssTokenType.leftBracket => '[',
        CssTokenType.rightBracket => ']',
        CssTokenType.leftParen => '(',
        CssTokenType.rightParen => ')',
        CssTokenType.leftBrace => '{',
        CssTokenType.rightBrace => '}',
        _ => '',
      };

  static String _num(double n) =>
      n == n.truncateToDouble() ? n.toInt().toString() : n.toString();
}

class CssTokenizer {
  CssTokenizer(this.src);
  final String src;
  int _pos = 0;

  bool get _eof => _pos >= src.length;
  int _at(int i) => i < src.length ? src.codeUnitAt(i) : -1;

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
  static bool _isHex(int c) => _isDigit(c) || (c | 0x20) >= 0x61 && (c | 0x20) <= 0x66;
  static bool _isNameStart(int c) =>
      (c | 0x20) >= 0x61 && (c | 0x20) <= 0x7a || c == 0x5f || c >= 0x80;
  static bool _isName(int c) => _isNameStart(c) || _isDigit(c) || c == 0x2d;
  static bool _isWs(int c) => c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0c || c == 0x0d;

  bool _validEscape(int i) => _at(i) == 0x5c && _at(i + 1) != 0x0a && _at(i + 1) != -1;

  bool _startsIdent(int i) {
    final c = _at(i);
    if (c == 0x2d) {
      final n = _at(i + 1);
      return _isNameStart(n) || n == 0x2d || _validEscape(i + 1);
    }
    return _isNameStart(c) || _validEscape(i);
  }

  bool _startsNumber(int i) {
    final c = _at(i);
    if (c == 0x2b || c == 0x2d) {
      return _isDigit(_at(i + 1)) || (_at(i + 1) == 0x2e && _isDigit(_at(i + 2)));
    }
    if (c == 0x2e) return _isDigit(_at(i + 1));
    return _isDigit(c);
  }

  List<CssToken> tokenize() {
    final out = <CssToken>[];
    while (true) {
      final t = _next();
      if (t == null) break;
      out.add(t);
    }
    return out;
  }

  CssToken? _next() {
    // Comments.
    while (_at(_pos) == 0x2f && _at(_pos + 1) == 0x2a) {
      final end = src.indexOf('*/', _pos + 2);
      _pos = end < 0 ? src.length : end + 2;
    }
    if (_eof) return null;
    final start = _pos;
    final c = src.codeUnitAt(_pos);
    if (_isWs(c)) {
      while (!_eof && _isWs(src.codeUnitAt(_pos))) {
        _pos++;
      }
      return CssToken(CssTokenType.whitespace, start);
    }
    if (c == 0x22 || c == 0x27) return _string(c);
    if (c == 0x23) {
      if (_isName(_at(_pos + 1)) || _validEscape(_pos + 1)) {
        _pos++;
        return CssToken(CssTokenType.hash, start, value: _name());
      }
    }
    if (_startsNumber(_pos)) return _numeric();
    if (c == 0x2d && _at(_pos + 1) == 0x2d && _at(_pos + 2) == 0x3e) {
      _pos += 3;
      return CssToken(CssTokenType.cdc, start);
    }
    if (_startsIdent(_pos)) return _identLike();
    if (c == 0x40 && _startsIdent(_pos + 1)) {
      _pos++;
      return CssToken(CssTokenType.atKeyword, start, value: _name());
    }
    if (c == 0x3c && src.startsWith('<!--', _pos)) {
      _pos += 4;
      return CssToken(CssTokenType.cdo, start);
    }
    _pos++;
    return switch (c) {
      0x3a => CssToken(CssTokenType.colon, start),
      0x3b => CssToken(CssTokenType.semicolon, start),
      0x2c => CssToken(CssTokenType.comma, start),
      0x5b => CssToken(CssTokenType.leftBracket, start),
      0x5d => CssToken(CssTokenType.rightBracket, start),
      0x28 => CssToken(CssTokenType.leftParen, start),
      0x29 => CssToken(CssTokenType.rightParen, start),
      0x7b => CssToken(CssTokenType.leftBrace, start),
      0x7d => CssToken(CssTokenType.rightBrace, start),
      _ => CssToken(CssTokenType.delim, start, value: String.fromCharCode(c)),
    };
  }

  String _escape() {
    _pos++; // backslash
    final c = _at(_pos);
    if (_isHex(c)) {
      final start = _pos;
      while (_pos - start < 6 && _isHex(_at(_pos))) {
        _pos++;
      }
      final code = int.parse(src.substring(start, _pos), radix: 16);
      if (_isWs(_at(_pos))) _pos++;
      if (code == 0 || code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff)) {
        return '�';
      }
      return String.fromCharCode(code);
    }
    _pos++;
    return String.fromCharCode(c);
  }

  String _name() {
    final buf = StringBuffer();
    while (!_eof) {
      final c = src.codeUnitAt(_pos);
      if (_isName(c)) {
        buf.writeCharCode(c);
        _pos++;
      } else if (_validEscape(_pos)) {
        buf.write(_escape());
      } else {
        break;
      }
    }
    return buf.toString();
  }

  CssToken _string(int quote) {
    final start = _pos;
    _pos++;
    final buf = StringBuffer();
    while (!_eof) {
      final c = src.codeUnitAt(_pos);
      if (c == quote) {
        _pos++;
        return CssToken(CssTokenType.string, start, value: buf.toString());
      }
      if (c == 0x0a) {
        return CssToken(CssTokenType.badString, start);
      }
      if (c == 0x5c) {
        if (_at(_pos + 1) == 0x0a) {
          _pos += 2;
        } else if (_at(_pos + 1) == -1) {
          _pos++;
        } else {
          buf.write(_escape());
        }
        continue;
      }
      buf.writeCharCode(c);
      _pos++;
    }
    return CssToken(CssTokenType.string, start, value: buf.toString());
  }

  CssToken _numeric() {
    final start = _pos;
    if (_at(_pos) == 0x2b || _at(_pos) == 0x2d) _pos++;
    while (_isDigit(_at(_pos))) {
      _pos++;
    }
    if (_at(_pos) == 0x2e && _isDigit(_at(_pos + 1))) {
      _pos++;
      while (_isDigit(_at(_pos))) {
        _pos++;
      }
    }
    if ((_at(_pos) | 0x20) == 0x65) {
      final n = _at(_pos + 1);
      final signed = n == 0x2b || n == 0x2d;
      if (_isDigit(signed ? _at(_pos + 2) : n)) {
        _pos += signed ? 2 : 1;
        while (_isDigit(_at(_pos))) {
          _pos++;
        }
      }
    }
    final value = double.parse(src.substring(start, _pos));
    if (_startsIdent(_pos)) {
      return CssToken(CssTokenType.dimension, start,
          number: value, unit: _name().toLowerCase());
    }
    if (_at(_pos) == 0x25) {
      _pos++;
      return CssToken(CssTokenType.percentage, start, number: value);
    }
    return CssToken(CssTokenType.number, start, number: value);
  }

  CssToken _identLike() {
    final start = _pos;
    final name = _name();
    if (name.toLowerCase() == 'url' && _at(_pos) == 0x28) {
      _pos++;
      while (_isWs(_at(_pos))) {
        _pos++;
      }
      final q = _at(_pos);
      if (q == 0x22 || q == 0x27) {
        return CssToken(CssTokenType.function, start, value: name);
      }
      return _url(start);
    }
    if (_at(_pos) == 0x28) {
      _pos++;
      return CssToken(CssTokenType.function, start, value: name);
    }
    return CssToken(CssTokenType.ident, start, value: name);
  }

  CssToken _url(int start) {
    final buf = StringBuffer();
    while (!_eof) {
      final c = src.codeUnitAt(_pos);
      if (c == 0x29) {
        _pos++;
        return CssToken(CssTokenType.url, start, value: buf.toString());
      }
      if (_isWs(c)) {
        while (_isWs(_at(_pos))) {
          _pos++;
        }
        if (_at(_pos) == 0x29 || _eof) continue;
        break;
      }
      if (c == 0x22 || c == 0x27 || c == 0x28) break;
      if (c == 0x5c) {
        if (!_validEscape(_pos)) break;
        buf.write(_escape());
        continue;
      }
      buf.writeCharCode(c);
      _pos++;
    }
    // Bad URL: consume the remnants up to ')'.
    while (!_eof && src.codeUnitAt(_pos) != 0x29) {
      _pos++;
    }
    if (!_eof) _pos++;
    return CssToken(CssTokenType.badUrl, start);
  }
}
