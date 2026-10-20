/// Selector parsing and matching (Selectors Level 3 subset plus `:not()` with
/// selector lists), shared by `querySelector*`, `matches`, `closest` and the
/// CSS cascade.
library;

import 'element.dart';
import 'exceptions.dart';
import 'node.dart';

/// (a, b, c) = (ids, classes/attributes/pseudo-classes, types).
class Specificity implements Comparable<Specificity> {
  const Specificity(this.a, this.b, this.c);
  static const zero = Specificity(0, 0, 0);

  final int a;
  final int b;
  final int c;

  Specificity operator +(Specificity o) => Specificity(a + o.a, b + o.b, c + o.c);

  @override
  int compareTo(Specificity o) =>
      a != o.a ? a - o.a : (b != o.b ? b - o.b : c - o.c);

  @override
  bool operator ==(Object o) =>
      o is Specificity && a == o.a && b == o.b && c == o.c;

  @override
  int get hashCode => Object.hash(a, b, c);

  @override
  String toString() => '($a,$b,$c)';
}

enum Combinator { descendant, child, nextSibling, subsequentSibling }

sealed class SimpleSelector {
  const SimpleSelector();
  bool matches(Element e);
  Specificity get specificity;
}

class TypeSelector extends SimpleSelector {
  const TypeSelector(this.name);
  final String name;
  @override
  bool matches(Element e) => e.localName == name;
  @override
  Specificity get specificity => const Specificity(0, 0, 1);
}

class UniversalSelector extends SimpleSelector {
  const UniversalSelector();
  @override
  bool matches(Element e) => true;
  @override
  Specificity get specificity => Specificity.zero;
}

class IdSelector extends SimpleSelector {
  const IdSelector(this.id);
  final String id;
  @override
  bool matches(Element e) => e.getAttribute('id') == id;
  @override
  Specificity get specificity => const Specificity(1, 0, 0);
}

class ClassSelector extends SimpleSelector {
  const ClassSelector(this.name);
  final String name;
  @override
  bool matches(Element e) => e.classList.contains(name);
  @override
  Specificity get specificity => const Specificity(0, 1, 0);
}

class AttributeSelector extends SimpleSelector {
  const AttributeSelector(this.name, this.op, this.value, {this.ignoreCase = false});
  final String name;

  /// null (presence), `=`, `~=`, `|=`, `^=`, `$=`, `*=`.
  final String? op;
  final String? value;
  final bool ignoreCase;

  @override
  bool matches(Element e) {
    var actual = e.getAttribute(name);
    if (actual == null) return false;
    if (op == null) return true;
    var v = value!;
    if (ignoreCase) {
      actual = actual.toLowerCase();
      v = v.toLowerCase();
    }
    switch (op) {
      case '=':
        return actual == v;
      case '~=':
        return v.isNotEmpty && actual.split(RegExp(r'\s+')).contains(v);
      case '|=':
        return actual == v || actual.startsWith('$v-');
      case '^=':
        return v.isNotEmpty && actual.startsWith(v);
      case r'$=':
        return v.isNotEmpty && actual.endsWith(v);
      case '*=':
        return v.isNotEmpty && actual.contains(v);
    }
    return false;
  }

  @override
  Specificity get specificity => const Specificity(0, 1, 0);
}

class PseudoClassSelector extends SimpleSelector {
  const PseudoClassSelector(this.name, {this.a = 0, this.b = 0, this.inner});
  final String name;

  /// `an+b` for nth-* pseudo-classes.
  final int a;
  final int b;

  /// Argument of `:not()`.
  final SelectorList? inner;

  static const Set<String> supported = {
    'first-child', 'last-child', 'only-child', 'nth-child', 'nth-last-child',
    'first-of-type', 'last-of-type', 'empty', 'root', 'not', 'checked',
    'disabled', 'enabled', 'focus', //
  };

  bool _nth(int index1) {
    if (a == 0) return index1 == b;
    final n = (index1 - b) / a;
    return n >= 0 && n == n.truncateToDouble();
  }

  @override
  bool matches(Element e) {
    switch (name) {
      case 'first-child':
        return e.parentNode != null && e.previousElementSibling == null;
      case 'last-child':
        return e.parentNode != null && e.nextElementSibling == null;
      case 'only-child':
        return e.parentNode != null &&
            e.previousElementSibling == null &&
            e.nextElementSibling == null;
      case 'nth-child':
      case 'nth-last-child':
        final parent = e.parentNode;
        if (parent == null) return false;
        final siblings = parent.children.toList();
        final i = siblings.indexOf(e);
        return _nth(name == 'nth-child' ? i + 1 : siblings.length - i);
      case 'first-of-type':
        return e.parentNode != null &&
            e.parentNode!.children.firstWhere((s) => s.localName == e.localName) ==
                e;
      case 'last-of-type':
        return e.parentNode != null &&
            e.parentNode!.children.lastWhere((s) => s.localName == e.localName) ==
                e;
      case 'empty':
        return e.rawChildren.every((c) => c is! Element && (c is! Text || c.data.isEmpty));
      case 'root':
        return identical(e.ownerDocument.documentElement, e);
      case 'not':
        return !inner!.matches(e);
      case 'checked':
        return (e.localName == 'input' && e.checked) ||
            (e.localName == 'option' &&
                identical(e.closest('select')?.selectedOption, e));
      case 'disabled':
        return e.isFormControl || e.localName == 'button' ? e.disabled : false;
      case 'enabled':
        return (e.isFormControl || e.localName == 'button') && !e.disabled;
      case 'focus':
        return identical(e.ownerDocument.activeElement, e);
    }
    return false;
  }

  @override
  Specificity get specificity => name == 'not'
      ? inner!.selectors
          .map((s) => s.specificity)
          .reduce((x, y) => x.compareTo(y) >= 0 ? x : y)
      : const Specificity(0, 1, 0);
}

/// A sequence of simple selectors with no combinator (`div.a#b:first-child`).
class CompoundSelector {
  const CompoundSelector(this.parts);
  final List<SimpleSelector> parts;

  bool matches(Element e) {
    for (final p in parts) {
      if (!p.matches(e)) return false;
    }
    return true;
  }

  Specificity get specificity =>
      parts.fold(Specificity.zero, (s, p) => s + p.specificity);
}

/// A complex selector: compounds joined by combinators, stored right-to-left
/// for matching (`compounds[0]` is the subject).
class ComplexSelector {
  ComplexSelector(this.compounds, this.combinators)
      : specificity =
            compounds.fold(Specificity.zero, (s, c) => s + c.specificity);

  final List<CompoundSelector> compounds;

  /// `combinators[i]` joins `compounds[i]` to `compounds[i + 1]` (leftwards).
  final List<Combinator> combinators;
  final Specificity specificity;

  /// The rightmost compound's ID/class/type, used by the cascade's rule index.
  CompoundSelector get subject => compounds.first;

  bool matches(Element e) => _matchFrom(e, 0);

  bool _matchFrom(Element e, int index) {
    if (!compounds[index].matches(e)) return false;
    if (index == compounds.length - 1) return true;
    switch (combinators[index]) {
      case Combinator.child:
        final p = e.parentElement;
        return p != null && _matchFrom(p, index + 1);
      case Combinator.descendant:
        for (var p = e.parentElement; p != null; p = p.parentElement) {
          if (_matchFrom(p, index + 1)) return true;
        }
        return false;
      case Combinator.nextSibling:
        final s = e.previousElementSibling;
        return s != null && _matchFrom(s, index + 1);
      case Combinator.subsequentSibling:
        for (var s = e.previousElementSibling; s != null; s = s.previousElementSibling) {
          if (_matchFrom(s, index + 1)) return true;
        }
        return false;
    }
  }
}

class SelectorList {
  SelectorList(this.selectors);

  final List<ComplexSelector> selectors;

  static final Map<String, SelectorList> _cache = {};

  /// Parses [source], throwing [DomException] `SyntaxError` when invalid.
  /// Results are cached (bounded) because scripts repeat the same queries.
  factory SelectorList.parse(String source) {
    final cached = _cache[source];
    if (cached != null) return cached;
    final list = _SelectorParser(source).parseList();
    if (_cache.length > 512) _cache.clear();
    return _cache[source] = list;
  }

  /// Like [SelectorList.parse] but returns null on syntax errors (CSS drops
  /// rules with invalid selectors).
  static SelectorList? tryParse(String source) {
    try {
      return SelectorList.parse(source);
    } on DomException {
      return null;
    }
  }

  bool matches(Element e) {
    for (final s in selectors) {
      if (s.matches(e)) return true;
    }
    return false;
  }

  Element? first(Node root) {
    for (final n in root.descendants) {
      if (n is Element && matches(n)) return n;
    }
    return null;
  }

  List<Element> all(Node root) => [
        for (final n in root.descendants)
          if (n is Element && matches(n)) n,
      ];
}

class _SelectorParser {
  _SelectorParser(this.src);
  final String src;
  int pos = 0;

  Never _fail(String why) =>
      throw DomException('SyntaxError', '"$src" is not a valid selector: $why');

  bool get _done => pos >= src.length;
  String get _ch => src[pos];

  void _skipWs() {
    while (!_done && _isWs(_ch)) {
      pos++;
    }
  }

  static bool _isWs(String c) => c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f';

  static bool _isNameChar(String c) {
    final u = c.codeUnitAt(0);
    return (u >= 0x30 && u <= 0x39) ||
        (u >= 0x41 && u <= 0x5a) ||
        (u >= 0x61 && u <= 0x7a) ||
        c == '-' ||
        c == '_' ||
        u >= 0x80;
  }

  String _ident() {
    final buf = StringBuffer();
    while (!_done) {
      final c = _ch;
      if (c == r'\') {
        pos++;
        if (_done) _fail('dangling escape');
        // Hex escape (up to 6 digits, optional trailing space) or literal.
        final hex = RegExp(r'^[0-9a-fA-F]{1,6}').stringMatch(src.substring(pos));
        if (hex != null) {
          buf.writeCharCode(int.parse(hex, radix: 16));
          pos += hex.length;
          if (!_done && _isWs(_ch)) pos++;
        } else {
          buf.write(_ch);
          pos++;
        }
      } else if (_isNameChar(c)) {
        buf.write(c);
        pos++;
      } else {
        break;
      }
    }
    if (buf.isEmpty) _fail('expected a name at offset $pos');
    return buf.toString();
  }

  SelectorList parseList({bool nested = false}) {
    final list = <ComplexSelector>[];
    while (true) {
      _skipWs();
      list.add(_complex());
      _skipWs();
      if (_done) break;
      if (_ch == ',') {
        pos++;
        continue;
      }
      if (nested && _ch == ')') break;
      _fail('unexpected "${_ch}" at offset $pos');
    }
    return SelectorList(list);
  }

  ComplexSelector _complex() {
    final compounds = <CompoundSelector>[_compound()];
    final combinators = <Combinator>[];
    while (true) {
      final start = pos;
      _skipWs();
      if (_done || _ch == ',' || _ch == ')') break;
      Combinator comb;
      switch (_ch) {
        case '>':
          comb = Combinator.child;
          pos++;
        case '+':
          comb = Combinator.nextSibling;
          pos++;
        case '~':
          comb = Combinator.subsequentSibling;
          pos++;
        default:
          if (pos == start) _fail('unexpected "${_ch}" at offset $pos');
          comb = Combinator.descendant;
      }
      _skipWs();
      combinators.add(comb);
      compounds.add(_compound());
    }
    return ComplexSelector(
        compounds.reversed.toList(), combinators.reversed.toList());
  }

  CompoundSelector _compound() {
    final parts = <SimpleSelector>[];
    if (!_done && _ch == '*') {
      pos++;
      parts.add(const UniversalSelector());
    } else if (!_done && (_isNameChar(_ch) || _ch == r'\')) {
      parts.add(TypeSelector(_ident().toLowerCase()));
    }
    while (!_done) {
      final c = _ch;
      if (c == '#') {
        pos++;
        parts.add(IdSelector(_ident()));
      } else if (c == '.') {
        pos++;
        parts.add(ClassSelector(_ident()));
      } else if (c == '[') {
        pos++;
        parts.add(_attribute());
      } else if (c == ':') {
        pos++;
        if (!_done && _ch == ':') _fail('pseudo-elements are not supported');
        parts.add(_pseudo());
      } else {
        break;
      }
    }
    if (parts.isEmpty) {
      _fail(_done ? 'unexpected end' : 'unexpected "${_ch}" at offset $pos');
    }
    return CompoundSelector(parts);
  }

  AttributeSelector _attribute() {
    _skipWs();
    final name = _ident().toLowerCase();
    _skipWs();
    if (_done) _fail('unterminated attribute selector');
    if (_ch == ']') {
      pos++;
      return AttributeSelector(name, null, null);
    }
    String op;
    if (_ch == '=') {
      op = '=';
      pos++;
    } else if (pos + 1 < src.length && src[pos + 1] == '=' && '~|^\$*'.contains(_ch)) {
      op = '${_ch}=';
      pos += 2;
    } else {
      _fail('bad attribute operator at offset $pos');
    }
    _skipWs();
    if (_done) _fail('missing attribute value');
    String value;
    if (_ch == '"' || _ch == "'") {
      final quote = _ch;
      pos++;
      final buf = StringBuffer();
      while (!_done && _ch != quote) {
        if (_ch == r'\' && pos + 1 < src.length) pos++;
        buf.write(_ch);
        pos++;
      }
      if (_done) _fail('unterminated string');
      pos++;
      value = buf.toString();
    } else {
      value = _ident();
    }
    _skipWs();
    var ignoreCase = false;
    if (!_done && (_ch == 'i' || _ch == 'I')) {
      ignoreCase = true;
      pos++;
      _skipWs();
    }
    if (_done || _ch != ']') _fail('expected "]"');
    pos++;
    return AttributeSelector(name, op, value, ignoreCase: ignoreCase);
  }

  PseudoClassSelector _pseudo() {
    final name = _ident().toLowerCase();
    if (!PseudoClassSelector.supported.contains(name)) {
      _fail('unsupported pseudo-class :$name');
    }
    final functional = name == 'not' || name.startsWith('nth-');
    if (!functional) return PseudoClassSelector(name);
    if (_done || _ch != '(') _fail(':$name requires arguments');
    pos++;
    _skipWs();
    if (name == 'not') {
      final inner = parseList(nested: true);
      if (_done || _ch != ')') _fail('expected ")"');
      pos++;
      return PseudoClassSelector(name, inner: inner);
    }
    final close = src.indexOf(')', pos);
    if (close < 0) _fail('expected ")"');
    final (a, b) = _parseNth(src.substring(pos, close).trim().toLowerCase());
    pos = close + 1;
    return PseudoClassSelector(name, a: a, b: b);
  }

  (int, int) _parseNth(String s) {
    if (s == 'odd') return (2, 1);
    if (s == 'even') return (2, 0);
    final m = RegExp(r'^([+-]?\d*)n\s*(?:([+-])\s*(\d+))?$').firstMatch(s);
    if (m != null) {
      final aText = m[1]!;
      final a = aText.isEmpty || aText == '+'
          ? 1
          : aText == '-'
              ? -1
              : int.parse(aText);
      final b = m[2] == null ? 0 : int.parse(m[3]!) * (m[2] == '-' ? -1 : 1);
      return (a, b);
    }
    final n = int.tryParse(s);
    if (n == null) _fail('bad an+b expression "$s"');
    return (0, n);
  }
}
