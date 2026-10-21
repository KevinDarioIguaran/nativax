import 'package:nativa_dom/nativa_dom.dart';

import 'media_queries.dart';
import 'properties.dart';
import 'supports.dart';
import 'tokenizer.dart';
import 'values.dart';

/// One longhand declaration after shorthand expansion.
class Declaration {
  const Declaration(this.property, this.value, {this.important = false});
  final String property;
  final CssValue value;
  final bool important;

  @override
  String toString() => '$property: $value${important ? ' !important' : ''}';
}

/// Something the parser dropped, kept so authors can see why a rule or
/// declaration had no effect.
class CssWarning {
  const CssWarning(this.message, this.offset);
  final String message;
  final int offset;

  @override
  String toString() => '@$offset: $message';
}

sealed class CssRule {
  const CssRule();
}

class StyleRule extends CssRule {
  const StyleRule(this.selectorText, this.selectors, this.declarations);
  final String selectorText;
  final SelectorList selectors;
  final List<Declaration> declarations;
}

class MediaRule extends CssRule {
  const MediaRule(this.conditionText, this.media, this.rules);
  final String conditionText;
  final MediaQueryList media;
  final List<CssRule> rules;
}

/// One `@keyframes` step: offsets in 0..1 and its declarations.
class Keyframe {
  const Keyframe(this.offsets, this.declarations);
  final List<double> offsets;
  final List<Declaration> declarations;
}

class KeyframesRule extends CssRule {
  const KeyframesRule(this.name, this.frames);
  final String name;
  final List<Keyframe> frames;
}

class StyleSheet {
  StyleSheet(this.rules, this.warnings);
  final List<CssRule> rules;
  final List<CssWarning> warnings;

  static StyleSheet parse(String source) => CssParser(source).parseStyleSheet();
}

class CssParser {
  CssParser(this.source) : _tokens = CssTokenizer(source).tokenize();

  final String source;
  final List<CssToken> _tokens;
  final List<CssWarning> _warnings = [];
  int _i = 0;

  /// Nesting guard for `@media` blocks.
  static const int _maxNesting = 16;

  bool get _done => _i >= _tokens.length;
  CssToken get _peek => _tokens[_i];

  StyleSheet parseStyleSheet() {
    final rules = _ruleList(topLevel: true, depth: 0);
    return StyleSheet(rules, _warnings);
  }

  /// Parses an inline `style` attribute.
  (List<Declaration>, List<CssWarning>) parseDeclarationList() {
    final decls = _declarations(_tokens.length);
    return (decls, _warnings);
  }

  List<CssRule> _ruleList({required bool topLevel, required int depth}) {
    final rules = <CssRule>[];
    while (!_done) {
      final t = _peek;
      switch (t.type) {
        case CssTokenType.whitespace || CssTokenType.cdo || CssTokenType.cdc:
          _i++;
        case CssTokenType.rightBrace:
          if (topLevel) {
            _warnings.add(CssWarning('unexpected "}"', t.offset));
            _i++;
          } else {
            return rules;
          }
        case CssTokenType.atKeyword:
          _atRule(rules, depth);
        default:
          _qualifiedRule(rules);
      }
    }
    return rules;
  }

  /// Index of the token that ends a prelude ('{' or ';' at depth 0), or the
  /// token count.
  int _preludeEnd({bool stopAtSemicolon = false}) {
    var depth = 0;
    for (var j = _i; j < _tokens.length; j++) {
      final t = _tokens[j].type;
      if (t == CssTokenType.leftParen || t == CssTokenType.function || t == CssTokenType.leftBracket) {
        depth++;
      } else if (t == CssTokenType.rightParen || t == CssTokenType.rightBracket) {
        depth--;
      } else if (depth <= 0 && t == CssTokenType.leftBrace) {
        return j;
      } else if (depth <= 0 && stopAtSemicolon && t == CssTokenType.semicolon) {
        return j;
      }
    }
    return _tokens.length;
  }

  /// Index just past the '}' matching the '{' at [open].
  int _blockEnd(int open) {
    var depth = 0;
    for (var j = open; j < _tokens.length; j++) {
      final t = _tokens[j].type;
      if (t == CssTokenType.leftBrace) depth++;
      if (t == CssTokenType.rightBrace) {
        depth--;
        if (depth == 0) return j + 1;
      }
    }
    return _tokens.length;
  }

  String _text(int from, int to) {
    final start = _tokens[from].offset;
    final end = to < _tokens.length ? _tokens[to].offset : source.length;
    return source.substring(start, end).trim();
  }

  void _atRule(List<CssRule> out, int depth) {
    final at = _peek;
    final name = at.value.toLowerCase();
    _i++;
    final end = _preludeEnd(stopAtSemicolon: true);
    if (end >= _tokens.length || _tokens[end].type == CssTokenType.semicolon) {
      _warnings.add(CssWarning('unsupported at-rule @$name', at.offset));
      _i = end + 1;
      return;
    }
    if ((name == 'keyframes' || name == '-webkit-keyframes') && depth < _maxNesting) {
      final nameToks = _tokens.sublist(_i, end).where((t) => t.type != CssTokenType.whitespace).toList();
      final kfName = nameToks.isEmpty ? '' : nameToks.first.value;
      final blockEnd = _blockEnd(end);
      _i = end + 1;
      final frames = <Keyframe>[];
      while (_i < blockEnd - 1) {
        final t = _peek;
        if (t.type == CssTokenType.whitespace) {
          _i++;
          continue;
        }
        final selEnd = _preludeEnd();
        if (selEnd >= blockEnd) break;
        final offsets = <double>[];
        for (final part in _text(_i, selEnd).split(',')) {
          final p = part.trim().toLowerCase();
          if (p == 'from') {
            offsets.add(0);
          } else if (p == 'to') {
            offsets.add(1);
          } else if (p.endsWith('%')) {
            final v = double.tryParse(p.substring(0, p.length - 1));
            if (v != null) offsets.add((v / 100).clamp(0, 1).toDouble());
          }
        }
        final frameEnd = _blockEnd(selEnd);
        _i = selEnd + 1;
        final decls = _declarations(frameEnd - 1);
        _i = frameEnd;
        if (offsets.isNotEmpty) frames.add(Keyframe(offsets, decls));
      }
      _i = blockEnd;
      if (kfName.isNotEmpty) out.add(KeyframesRule(kfName, frames));
      return;
    }
    if (name == 'supports' && depth < _maxNesting) {
      final text = _text(_i, end);
      _i = end + 1;
      final rules = _ruleList(topLevel: false, depth: depth + 1);
      if (!_done) _i++; // '}'
      if (supportsCondition(text)) out.addAll(rules);
      return;
    }
    if (name == 'layer' && depth < _maxNesting) {
      // Cascade layers are flattened in source order.
      _i = end + 1;
      final rules = _ruleList(topLevel: false, depth: depth + 1);
      if (!_done) _i++;
      out.addAll(rules);
      return;
    }
    if (name == 'media' && depth < _maxNesting) {
      final prelude = _tokens.sublist(_i, end);
      final text = _text(_i, end);
      _i = end + 1;
      final rules = _ruleList(topLevel: false, depth: depth + 1);
      if (!_done) _i++; // '}'
      out.add(MediaRule(text, MediaQueryList.parse(prelude), rules));
      return;
    }
    _warnings.add(CssWarning('unsupported at-rule @$name', at.offset));
    _i = _blockEnd(end);
  }

  void _qualifiedRule(List<CssRule> out) {
    final start = _i;
    final end = _preludeEnd();
    if (end >= _tokens.length) {
      _warnings.add(CssWarning('rule without a block', _tokens[start].offset));
      _i = _tokens.length;
      return;
    }
    final selectorText = _text(start, end);
    final blockEnd = _blockEnd(end);
    _i = end + 1;
    final declarations = _declarations(blockEnd - 1);
    _i = blockEnd;
    final selectors = SelectorList.tryParse(selectorText);
    if (selectors == null) {
      _warnings.add(CssWarning('invalid or unsupported selector "$selectorText"',
          _tokens[start].offset));
      return;
    }
    out.add(StyleRule(selectorText, selectors, declarations));
  }

  /// Parses declarations from the current position up to token index [end].
  List<Declaration> _declarations(int end) {
    final out = <Declaration>[];
    while (_i < end) {
      final t = _tokens[_i];
      if (t.type == CssTokenType.whitespace || t.type == CssTokenType.semicolon) {
        _i++;
        continue;
      }
      // Find the end of this declaration (';' at depth 0 or [end]).
      var depth = 0;
      var j = _i;
      for (; j < end; j++) {
        final k = _tokens[j].type;
        if (k == CssTokenType.leftParen || k == CssTokenType.function ||
            k == CssTokenType.leftBrace || k == CssTokenType.leftBracket) {
          depth++;
        } else if (k == CssTokenType.rightParen || k == CssTokenType.rightBrace ||
            k == CssTokenType.rightBracket) {
          depth--;
        } else if (k == CssTokenType.semicolon && depth <= 0) {
          break;
        }
      }
      _declaration(_tokens.sublist(_i, j), out);
      _i = j + 1;
    }
    _i = end;
    return out;
  }

  void _declaration(List<CssToken> ts, List<Declaration> out) {
    if (ts.isEmpty) return;
    final nameTok = ts.first;
    if (nameTok.type != CssTokenType.ident) {
      _warnings.add(CssWarning('invalid declaration', nameTok.offset));
      return;
    }
    var k = 1;
    while (k < ts.length && ts[k].type == CssTokenType.whitespace) {
      k++;
    }
    if (k >= ts.length || ts[k].type != CssTokenType.colon) {
      _warnings.add(CssWarning('expected ":" after ${nameTok.value}', nameTok.offset));
      return;
    }
    var value = ts.sublist(k + 1);
    // Trailing `!important`.
    var important = false;
    final meaningful = [
      for (var x = 0; x < value.length; x++)
        if (value[x].type != CssTokenType.whitespace) x,
    ];
    if (meaningful.length >= 2 &&
        value[meaningful[meaningful.length - 2]].isDelim('!') &&
        value[meaningful.last].isIdent('important')) {
      important = true;
      value = value.sublist(0, meaningful[meaningful.length - 2]);
    }
    final name = nameTok.value.toLowerCase();
    final raw = value.map((t) => t.toString()).join().trim();
    if (name.startsWith('--')) {
      out.add(Declaration(name, RawValue(raw), important: important));
      return;
    }
    if (!isSupportedProperty(name)) {
      _warnings.add(CssWarning('unsupported property "$name"', nameTok.offset));
      return;
    }
    if (value.any((t) => t.type == CssTokenType.function &&
        const {'var', 'env', 'calc', 'min', 'max', 'clamp'}.contains(t.value.toLowerCase()))) {
      // Keep the declaration: variables are inherited and can only be
      // substituted while computing an element. The cascade resolves this
      // RawValue (and reports a warning if it still cannot be parsed).
      out.add(Declaration(name, RawValue(raw), important: important));
      return;
    }
    final expanded = expandDeclaration(name, value);
    if (expanded == null) {
      _warnings.add(CssWarning('invalid value for "$name"', nameTok.offset));
      return;
    }
    expanded.forEach((p, v) => out.add(Declaration(p, v, important: important)));
  }
}
