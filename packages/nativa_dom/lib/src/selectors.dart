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
  bool matches(Element e, [Element? scope]);
  Specificity get specificity;
}

class TypeSelector extends SimpleSelector {
  const TypeSelector(this.name);
  final String name;
  @override
  bool matches(Element e, [Element? scope]) => e.localName == name;
  @override
  Specificity get specificity => const Specificity(0, 0, 1);
}

class UniversalSelector extends SimpleSelector {
  const UniversalSelector();
  @override
  bool matches(Element e, [Element? scope]) => true;
  @override
  Specificity get specificity => Specificity.zero;
}

class IdSelector extends SimpleSelector {
  const IdSelector(this.id);
  final String id;
  @override
  bool matches(Element e, [Element? scope]) => e.getAttribute('id') == id;
  @override
  Specificity get specificity => const Specificity(1, 0, 0);
}

class ClassSelector extends SimpleSelector {
  const ClassSelector(this.name, {this.prefix = false});
  final String name;
  final bool prefix;
  @override
  bool matches(Element e, [Element? scope]) => prefix
      ? e.classList.any((c) => c.startsWith(name) && c.length > name.length)
      : e.classList.contains(name);
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
  bool matches(Element e, [Element? scope]) {
    var actual = e.getAttribute(name);
    if (actual == null) return false;
    if (op == null) return true;
    var v = value!;
    // The HTML `lang` attribute is matched case-insensitively.
    final langAttribute = name.toLowerCase() == 'lang';
    if (ignoreCase || langAttribute) {
      actual = actual.toLowerCase();
      v = v.toLowerCase();
    }
    switch (op) {
      case '=':
        return actual == v;
      case '~=':
        return v.isNotEmpty && actual.split(RegExp(r'\s+')).contains(v);
      case '|=':
        return actual == v || actual.startsWith('${v}-');
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
  const PseudoClassSelector(this.name,
      {this.a = 0,
      this.b = 0,
      this.inner,
      this.hasParts,
      this.arg,
      this.of});
  final String name;

  /// `an+b` for nth-* pseudo-classes.
  final int a;
  final int b;

  /// Argument of `:not()`, `:is()` or `:where()`.
  final SelectorList? inner;

  /// `:has()` arguments with their optional relative combinator.
  final List<(Combinator?, ComplexSelector)>? hasParts;

  /// Argument of `:dir()` / `:lang()`.
  final String? arg;

  /// `of S` filter for `:nth-child(An+B of S)`.
  final SelectorList? of;

  static const Set<String> supported = {
    'first-child', 'last-child', 'only-child', 'nth-child', 'nth-last-child',
    'first-of-type', 'last-of-type', 'empty', 'root', 'not', 'is', 'where',
    'has', 'checked', 'disabled', 'enabled', 'focus', 'focus-visible',
    'focus-within', 'dir', 'lang', 'heading', 'link', 'any-link', 'scope',
    'hover', 'active', 'target', 'visited', 'defined', 'open', 'modal',
    'required', 'optional', 'read-only', 'read-write', 'placeholder-shown',
    'valid', 'invalid', 'user-valid', 'user-invalid', 'in-range',
    'out-of-range', 'indeterminate', 'default', 'autofill', 'only-of-type',
    'nth-of-type', 'nth-last-of-type', 'first', 'popover-open', //
  };

  /// Pseudo-classes whose result depends on interaction state rather than
  /// the tree; changing that state must invalidate styles.
  static const Set<String> stateful = {
    'hover', 'active', 'focus', 'focus-visible', 'focus-within', 'target',
    'valid', 'invalid', 'user-valid', 'user-invalid', 'placeholder-shown',
    'checked', 'in-range', 'out-of-range', 'modal', //
  };

  bool _nth(int index1) {
    if (a == 0) return index1 == b;
    final n = (index1 - b) / a;
    return n >= 0 && n == n.truncateToDouble();
  }

  @override
  bool matches(Element e, [Element? scope]) {
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
        final siblings = parent.children
            .where((s) => of == null || of!.matches(s, scope))
            .toList();
        final i = siblings.indexOf(e);
        if (i < 0) return false;
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
        return !inner!.matches(e, scope);
      case 'is':
      case 'where':
        return inner!.matches(e, scope);
      case 'has':
        for (final (combinator, selector) in hasParts!) {
          switch (combinator) {
            case Combinator.child:
              if (e.children.any((c) => selector.matches(c, scope))) return true;
            case Combinator.nextSibling:
              final s = e.nextElementSibling;
              if (s != null && selector.matches(s, scope)) return true;
            case Combinator.subsequentSibling:
              for (var s = e.nextElementSibling;
                  s != null;
                  s = s.nextElementSibling) {
                if (selector.matches(s, scope)) return true;
              }
            case Combinator.descendant:
            case null:
              for (final d in e.descendants) {
                if (d is Element && selector.matches(d, scope)) return true;
              }
          }
        }
        return false;
      case 'focus-visible':
        return identical(e.ownerDocument.focusedElement, e);
      case 'focus-within':
        final active = e.ownerDocument.focusedElement;
        return active != null && (identical(active, e) || e.contains(active));
      case 'dir':
        return _direction(e) == (arg ?? 'ltr').toLowerCase();
      case 'lang':
        for (Element? n = e; n != null; n = n.parentElement) {
          final lang = n.getAttribute('lang');
          if (lang != null) {
            final wanted = (arg ?? '').toLowerCase();
            final actual = lang.toLowerCase();
            return actual == wanted || actual.startsWith('${wanted}-');
          }
        }
        return false;
      case 'heading':
        final m = RegExp(r'^h([1-6])$').firstMatch(e.localName);
        if (m == null) return false;
        if (arg == null || arg!.isEmpty) return true;
        return int.tryParse(arg!) == int.tryParse(m.group(1)!);
      case 'link':
      case 'any-link':
        return (e.localName == 'a' || e.localName == 'area') &&
            e.getAttribute('href') != null;
      case 'scope':
        return scope != null ? identical(e, scope) : identical(e.ownerDocument.documentElement, e);
      case 'checked':
        return (e.localName == 'input' && e.checked) ||
            (e.localName == 'option' &&
                identical(e.closest('select')?.selectedOption, e));
      case 'disabled':
        return e.hasAttribute('disabled') ||
            ((e.isFormControl || e.localName == 'button') && e.disabled);
      case 'enabled':
        return (e.isFormControl || e.localName == 'button' || e.localName == 'fieldset') &&
            !e.disabled;
      case 'focus':
        return identical(e.ownerDocument.focusedElement, e);
      case 'hover':
        final h = e.ownerDocument.hoverElement;
        return h != null && (identical(h, e) || e.contains(h));
      case 'active':
        final a = e.ownerDocument.pressedElement;
        return a != null && (identical(a, e) || e.contains(a));
      case 'target':
        final t = e.ownerDocument.targetId;
        return t != null && t.isNotEmpty && e.getAttribute('id') == t;
      case 'visited':
      case 'autofill':
      case 'popover-open':
      case 'first':
        return false;
      case 'defined':
        // Built-in elements are always defined. An autonomous custom element
        // is only defined after customElements.define(), including when it is
        // still an unknown element on the page (upgrade may happen later).
        final name = e.localName;
        return !name.contains('-') ||
            e.ownerDocument.definedCustomElements.contains(name);
      case 'open':
        return (e.localName == 'details' || e.localName == 'dialog') &&
            e.hasAttribute('open');
      case 'modal':
        return e.ownerDocument.modalElements.contains(e);
      case 'required':
        return e.isFormControl && e.hasAttribute('required');
      case 'optional':
        return e.isFormControl && !e.hasAttribute('required');
      case 'read-write':
        return _readWrite(e);
      case 'read-only':
        return !_readWrite(e);
      case 'placeholder-shown':
        return (e.localName == 'input' || e.localName == 'textarea') &&
            e.hasAttribute('placeholder') &&
            e.value.isEmpty;
      case 'valid':
        return e.willValidate && e.validity.valid;
      case 'invalid':
        if (e.willValidate) return !e.validity.valid;
        if (e.localName == 'fieldset') {
          for (final d in e.querySelectorAll('input, select, textarea, button')) {
            if (d.willValidate && !d.validity.valid) return true;
          }
        }
        return false;
      case 'user-valid':
        return e.userInteracted && e.willValidate && e.validity.valid;
      case 'user-invalid':
        return e.userInteracted && e.willValidate && !e.validity.valid;
      case 'in-range':
      case 'out-of-range':
        if (e.localName != 'input' ||
            !(e.hasAttribute('min') || e.hasAttribute('max'))) {
          return false;
        }
        final v = e.validity;
        final out = v.rangeUnderflow || v.rangeOverflow;
        return name == 'out-of-range' ? out : !out;
      case 'indeterminate':
        return e.localName == 'input' &&
            e.inputType == 'radio' &&
            !_radioGroupChecked(e);
      case 'default':
        return (e.localName == 'input' && e.hasAttribute('checked')) ||
            (e.localName == 'option' && e.hasAttribute('selected'));
      case 'only-of-type':
        final p = e.parentNode;
        return p != null &&
            p.children.where((s) => s.localName == e.localName).length == 1;
      case 'nth-of-type':
      case 'nth-last-of-type':
        final p = e.parentNode;
        if (p == null) return false;
        final same = p.children.where((s) => s.localName == e.localName).toList();
        final i = same.indexOf(e);
        return _nth(name == 'nth-of-type' ? i + 1 : same.length - i);
    }
    return false;
  }

  static bool _readWrite(Element e) {
    if (e.localName == 'textarea' ||
        (e.localName == 'input' &&
            !const {'checkbox', 'radio', 'button', 'submit', 'reset', 'image',
                    'hidden', 'range', 'color', 'file'}
                .contains(e.inputType))) {
      return !e.hasAttribute('readonly') && !e.disabled;
    }
    for (Element? n = e; n != null; n = n.parentElement) {
      final ce = n.getAttribute('contenteditable');
      if (ce != null) return ce != 'false';
    }
    return false;
  }

  static bool _radioGroupChecked(Element e) {
    final name = e.getAttribute('name');
    if (e.checked) return true;
    if (name == null) return false;
    final scope = e.closest('form') ?? e.ownerDocument.documentElement;
    return scope?.querySelectorAll('input[type=radio]').any(
            (r) => r.getAttribute('name') == name && r.checked) ??
        false;
  }

  String _direction(Element e) {
    for (Element? n = e; n != null; n = n.parentElement) {
      final dir = n.getAttribute('dir')?.toLowerCase();
      if (dir == 'rtl') return 'rtl';
      if (dir == 'ltr') return 'ltr';
    }
    return 'ltr';
  }

  @override
  Specificity get specificity {
    if (name == 'where') return Specificity.zero;
    if (name == 'not' || name == 'is') {
      if (inner!.selectors.isEmpty) return Specificity.zero;
      return inner!.selectors
          .map((s) => s.specificity)
          .reduce((x, y) => x.compareTo(y) >= 0 ? x : y);
    }
    if (name == 'has' && hasParts != null && hasParts!.isNotEmpty) {
      return hasParts!
          .map((p) => p.$2.specificity)
          .reduce((x, y) => x.compareTo(y) >= 0 ? x : y);
    }
    return const Specificity(0, 1, 0);
  }
}

/// A sequence of simple selectors with no combinator (`div.a#b:first-child`).
class CompoundSelector {
  const CompoundSelector(this.parts);
  final List<SimpleSelector> parts;

  bool matches(Element e, [Element? scope]) {
    for (final p in parts) {
      if (!p.matches(e, scope)) return false;
    }
    return true;
  }

  Specificity get specificity =>
      parts.fold(Specificity.zero, (s, p) => s + p.specificity);
}

/// A complex selector: compounds joined by combinators, stored right-to-left
/// for matching (`compounds[0]` is the subject).
class ComplexSelector {
  ComplexSelector(this.compounds, this.combinators, {this.pseudoElement})
      : specificity = compounds.fold(Specificity.zero, (s, c) => s + c.specificity) +
            (pseudoElement == null ? Specificity.zero : const Specificity(0, 0, 1));

  final List<CompoundSelector> compounds;

  /// `before`, `after`, `marker`, `placeholder`, ... for selectors ending in
  /// a pseudo-element. Such selectors never match elements themselves; the
  /// cascade uses [matchesPseudo].
  final String? pseudoElement;

  /// `combinators[i]` joins `compounds[i]` to `compounds[i + 1]` (leftwards).
  final List<Combinator> combinators;
  final Specificity specificity;

  /// The rightmost compound's ID/class/type, used by the cascade's rule index.
  CompoundSelector get subject => compounds.first;

  bool matches(Element e, [Element? scope]) => pseudoElement == null && _matchFrom(e, 0, scope);

  /// Whether this selector styles the [pseudo] pseudo-element of [e].
  bool matchesPseudo(Element e, String pseudo, [Element? scope]) =>
      pseudoElement == pseudo && _matchFrom(e, 0, scope);

  /// Whether the subject compound matches [e], ignoring any pseudo-element.
  bool matchesOriginating(Element e, [Element? scope]) => _matchFrom(e, 0, scope);

  bool _matchFrom(Element e, int index, [Element? scope]) {
    if (!compounds[index].matches(e, scope)) return false;
    if (index == compounds.length - 1) return true;
    switch (combinators[index]) {
      case Combinator.child:
        final p = e.parentElement;
        return p != null && _matchFrom(p, index + 1, scope);
      case Combinator.descendant:
        for (var p = e.parentElement; p != null; p = p.parentElement) {
          if (_matchFrom(p, index + 1, scope)) return true;
        }
        return false;
      case Combinator.nextSibling:
        final s = e.previousElementSibling;
        return s != null && _matchFrom(s, index + 1, scope);
      case Combinator.subsequentSibling:
        for (var s = e.previousElementSibling; s != null; s = s.previousElementSibling) {
          if (_matchFrom(s, index + 1, scope)) return true;
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

  bool matches(Element e, [Element? scope]) {
    for (final s in selectors) {
      if (s.matches(e, scope)) return true;
    }
    return false;
  }

  Element? first(Node root, [Element? scope]) {
    for (final n in root.descendants) {
      if (n is Element && matches(n, scope)) return n;
    }
    return null;
  }

  List<Element> all(Node root, [Element? scope]) => [
        for (final n in root.descendants)
          if (n is Element && matches(n, scope)) n,
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
        if (_done) { buf.writeCharCode(0xFFFD); break; }
        // Hex escape (up to 6 digits, optional trailing space) or literal.
        final hex = RegExp(r'^[0-9a-fA-F]{1,6}').stringMatch(src.substring(pos));
        if (hex != null) {
          var value = int.parse(hex, radix: 16);
          pos += hex.length;
          if (!_done && _isWs(_ch)) {
            if (_ch == '\r' && pos + 1 < src.length && src[pos + 1] == '\n') {
              pos += 2;
            } else {
              pos++;
            }
          }
          if (value == 0 || (value >= 0xD800 && value <= 0xDFFF) || value > 0x10FFFF) {
            value = 0xFFFD;
          }
          buf.write(String.fromCharCode(value));
        } else {
          if (_ch.codeUnitAt(0) == 0) {
            buf.writeCharCode(0xFFFD);
          } else {
            buf.write(_ch);
          }
          pos++;
        }
      } else if (c.codeUnitAt(0) == 0) {
        buf.writeCharCode(0xFFFD);
        pos++;
      } else if (_isNameChar(c)) {
        buf.write(c);
        pos++;
      } else {
        break;
      }
    }
    if (buf.isEmpty) _fail('expected a name at offset $pos');
    final ident = buf.toString();
    if (ident.length > 1 &&
        ident.startsWith('-') &&
        RegExp(r'^[0-9]').hasMatch(ident.substring(1))) {
      _fail('invalid identifier at offset $pos');
    }
    return ident;
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

  /// Set by [_compound] when it consumes a trailing pseudo-element.
  String? _pseudoElement;

  ComplexSelector _complex() {
    _pseudoElement = null;
    final compounds = <CompoundSelector>[_compound()];
    final combinators = <Combinator>[];
    while (true) {
      final start = pos;
      _skipWs();
      if (_done || _ch == ',' || _ch == ')') break;
      if (_pseudoElement != null) _fail('a pseudo-element must be last');
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
    final pseudo = _pseudoElement;
    _pseudoElement = null;
    return ComplexSelector(
        compounds.reversed.toList(), combinators.reversed.toList(),
        pseudoElement: pseudo);
  }

  static const Set<String> pseudoElements = {
    'before', 'after', 'marker', 'placeholder', 'backdrop', 'selection',
    'first-line', 'first-letter', 'file-selector-button', 'part', 'slotted',
    'cue', 'grammar-error', 'spelling-error', 'target-text', 'details-content', //
  };

  String _pseudoElementName() {
    final name = _ident().toLowerCase();
    if (!pseudoElements.contains(name) && !name.startsWith('-webkit-') &&
        !name.startsWith('-moz-')) {
      _fail('unsupported pseudo-element ::$name');
    }
    if (!_done && _ch == '(') {
      // ::part(x) / ::slotted(x): skip the argument; they never match here.
      var depth = 0;
      while (!_done) {
        if (_ch == '(') depth++;
        if (_ch == ')') {
          depth--;
          if (depth == 0) {
            pos++;
            break;
          }
        }
        pos++;
      }
    }
    return name;
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
        final name = _ident();
        var prefix = false;
        if (!_done && _ch == '*') {
          prefix = true;
          pos++;
        }
        parts.add(ClassSelector(name, prefix: prefix));
      } else if (c == '[') {
        pos++;
        parts.add(_attribute());
      } else if (c == ':') {
        if (_pseudoElement != null) {
          // User-action pseudo-classes after a pseudo-element
          // (`::before:hover`) are not supported.
          _fail('pseudo-class after a pseudo-element');
        }
        pos++;
        if (!_done && _ch == ':') {
          pos++;
          _pseudoElement = _pseudoElementName();
          continue;
        }
        // CSS2 single-colon pseudo-elements.
        final save = pos;
        final name = _ident().toLowerCase();
        if (const {'before', 'after', 'first-line', 'first-letter'}.contains(name)) {
          _pseudoElement = name;
          continue;
        }
        pos = save;
        parts.add(_pseudo());
      } else {
        break;
      }
    }
    if (parts.isEmpty) {
      if (_pseudoElement != null) return CompoundSelector(const [UniversalSelector()]);
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
    } else if (!_done && (_ch == 's' || _ch == 'S')) {
      ignoreCase = false;
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
    final functional = name == 'not' ||
        name == 'is' ||
        name == 'where' ||
        name == 'has' ||
        name == 'dir' ||
        name == 'lang' ||
        name == 'heading' ||
        name.startsWith('nth-');
    if (!functional || (name == 'heading' && (_done || _ch != '('))) {
      return PseudoClassSelector(name);
    }
    if (_done || _ch != '(') _fail(':$name requires arguments');
    pos++;
    _skipWs();
    if (name == 'not' || name == 'is' || name == 'where') {
      if (name == 'not') {
        final inner = parseList(nested: true);
        if (_done || _ch != ')') _fail('expected ")"');
        pos++;
        return PseudoClassSelector(name, inner: inner);
      }
      // :is()/:where() take a forgiving selector list: invalid arguments
      // are ignored and an empty list matches nothing.
      final selectors = <ComplexSelector>[];
      while (true) {
        _skipWs();
        if (_done || _ch == ')') {
          if (!_done) pos++;
          break;
        }
        final start = pos;
        try {
          selectors.add(_complex());
        } on DomException {
          pos = start;
          var depth = 0;
          while (!_done) {
            final c = _ch;
            if (c == '(') {
              depth++;
            } else if (c == ')') {
              if (depth == 0) break;
              depth--;
            } else if (c == ',' && depth == 0) {
              break;
            }
            pos++;
          }
        }
        _skipWs();
        if (_done) _fail('expected ")"');
        if (_ch == ',') {
          pos++;
          continue;
        }
        if (_ch == ')') {
          pos++;
          break;
        }
        _fail('unexpected "$_ch" in :$name()');
      }
      return PseudoClassSelector(name, inner: SelectorList(selectors));
    }
    if (name == 'has') {
      final parts = <(Combinator?, ComplexSelector)>[];
      while (true) {
        _skipWs();
        Combinator? combinator;
        if (!_done && (_ch == '>' || _ch == '+' || _ch == '~')) {
          combinator = switch (_ch) {
            '>' => Combinator.child,
            '+' => Combinator.nextSibling,
            _ => Combinator.subsequentSibling,
          };
          pos++;
          _skipWs();
        }
        parts.add((combinator, _complex()));
        _skipWs();
        if (_done) _fail('expected ")"');
        if (_ch == ',') {
          pos++;
          continue;
        }
        if (_ch == ')') {
          pos++;
          break;
        }
        _fail('unexpected "$_ch" in :has()');
      }
      return PseudoClassSelector(name, hasParts: parts);
    }
    if (name == 'heading') {
      _skipWs();
      final start = pos;
      while (!_done && _ch != ')') {
        pos++;
      }
      final value = src.substring(start, pos).trim();
      if (_done || _ch != ')') _fail('expected ")"');
      pos++;
      return PseudoClassSelector(name, arg: value);
    }
    if (name == 'dir' || name == 'lang') {
      String value;
      if (name == 'dir' && (_ch == '"' || _ch == "'")) {
        _fail('expected an ident');
      }
      if (!_done && (_ch == '"' || _ch == "'")) {
        final quote = _ch;
        pos++;
        final start = pos;
        while (!_done && _ch != quote) {
          pos++;
        }
        if (_done) _fail('unterminated string');
        value = src.substring(start, pos);
        pos++;
      } else {
        value = _ident();
      }
      _skipWs();
      if (_done || _ch != ')') _fail('expected ")"');
      pos++;
      return PseudoClassSelector(name, arg: value);
    }

    // nth-*: find the matching close parenthesis, then split `of S`.
    var depth = 1;
    final start = pos;
    var close = -1;
    while (pos < src.length) {
      final c = src[pos];
      if (c == '(') depth++;
      if (c == ')') {
        depth--;
        if (depth == 0) {
          close = pos;
          break;
        }
      }
      pos++;
    }
    if (close < 0) _fail('expected ")"');
    final argument = src.substring(start, close).trim().toLowerCase();
    pos = close + 1;
    var nthText = argument;
    SelectorList? of;
    final ofIndex = argument.indexOf(' of ');
    if (ofIndex >= 0) {
      nthText = argument.substring(0, ofIndex).trim();
      of = SelectorList.parse(argument.substring(ofIndex + 4).trim());
    }
    final (a, b) = _parseNth(nthText);
    return PseudoClassSelector(name, a: a, b: b, of: of);
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
