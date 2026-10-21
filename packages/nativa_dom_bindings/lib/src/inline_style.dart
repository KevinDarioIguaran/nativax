import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_dom/nativa_dom.dart';

/// Text-level editing of an element's `style` attribute, backing
/// `element.style` in scripts.
///
/// Properties are kept as written (shorthands are not expanded into
/// longhands here), so `style.margin = "4px"` round-trips as `margin: 4px`.
/// Reading a longhand that was set through a shorthand returns "" — a
/// documented difference from browsers.
class InlineStyle {
  InlineStyle(this.element);
  final Element element;

  List<(String, String, bool)> _entries() {
    final text = element.getAttribute('style') ?? '';
    final out = <(String, String, bool)>[];
    // Split on top-level semicolons using the CSS tokenizer so that
    // semicolons in strings or url() are respected.
    final tokens = CssTokenizer(text).tokenize();
    var start = 0;
    var depth = 0;
    void flush(int endOffset) {
      final decl = text.substring(start, endOffset);
      final colon = decl.indexOf(':');
      if (colon > 0) {
        final name = decl.substring(0, colon).trim().toLowerCase();
        var value = decl.substring(colon + 1).trim();
        var important = false;
        final m = RegExp(r'!\s*important\s*$', caseSensitive: false).firstMatch(value);
        if (m != null) {
          important = true;
          value = value.substring(0, m.start).trim();
        }
        if (name.isNotEmpty && value.isNotEmpty) {
          out.removeWhere((e) => e.$1 == name);
          out.add((name, value, important));
        }
      }
    }

    for (final t in tokens) {
      if (t.type == CssTokenType.function || t.type == CssTokenType.leftParen) depth++;
      if (t.type == CssTokenType.rightParen) depth--;
      if (t.type == CssTokenType.semicolon && depth <= 0) {
        flush(t.offset);
        start = t.offset + 1;
      }
    }
    flush(text.length);
    return out;
  }

  void _write(List<(String, String, bool)> entries) {
    if (entries.isEmpty) {
      element.removeAttribute('style');
      return;
    }
    element.setAttribute(
      'style',
      entries.map((e) => '${e.$1}: ${e.$2}${e.$3 ? ' !important' : ''};').join(' '),
    );
  }

  String getPropertyValue(String name) {
    final n = name.toLowerCase();
    for (final e in _entries()) {
      if (e.$1 == n) return e.$2;
    }
    return '';
  }

  String getPropertyPriority(String name) {
    final n = name.toLowerCase();
    for (final e in _entries()) {
      if (e.$1 == n) return e.$3 ? 'important' : '';
    }
    return '';
  }

  /// Sets a property; an empty value removes it. Invalid or unsupported
  /// values are ignored, as browsers ignore them.
  void setProperty(String name, String value, [String priority = '']) {
    final n = name.toLowerCase().trim();
    final v = value.trim();
    if (v.isEmpty) {
      removeProperty(n);
      return;
    }
    if (expandDeclaration(n, CssTokenizer(v).tokenize()) == null) return;
    final entries = _entries()..removeWhere((e) => e.$1 == n);
    entries.add((n, v, priority.toLowerCase() == 'important'));
    _write(entries);
  }

  String removeProperty(String name) {
    final n = name.toLowerCase();
    final entries = _entries();
    final old = getPropertyValue(n);
    final before = entries.length;
    entries.removeWhere((e) => e.$1 == n);
    if (entries.length != before) _write(entries);
    return old;
  }

  String get cssText => element.getAttribute('style') ?? '';
  set cssText(String text) =>
      text.trim().isEmpty ? element.removeAttribute('style') : element.setAttribute('style', text);

  int get length => _entries().length;
  List<String> get propertyNames => [for (final e in _entries()) e.$1];
}
