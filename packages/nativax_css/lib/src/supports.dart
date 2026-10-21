import 'package:nativax_dom/nativax_dom.dart';

import 'properties.dart';
import 'tokenizer.dart';

/// Evaluates an `@supports` / `CSS.supports()` condition:
/// `(prop: value)`, `not`, `and`, `or` and `selector(...)`.
bool supportsCondition(String text) {
  final t = text.trim();
  if (t.isEmpty) return false;
  if (t.toLowerCase().startsWith('not ')) return !supportsCondition(t.substring(4));
  final parts = <String>[];
  var depth = 0, start = 0;
  String? op;
  for (var i = 0; i < t.length; i++) {
    final c = t[i];
    if (c == '(') depth++;
    if (c == ')') depth--;
    if (depth == 0) {
      for (final word in const [' and ', ' or ']) {
        if (t.toLowerCase().startsWith(word, i)) {
          parts.add(t.substring(start, i));
          op = word.trim();
          start = i + word.length;
        }
      }
    }
  }
  if (parts.isNotEmpty) {
    parts.add(t.substring(start));
    return op == 'and' ? parts.every(supportsCondition) : parts.any(supportsCondition);
  }
  if (t.toLowerCase().startsWith('selector(') && t.endsWith(')')) {
    return SelectorList.tryParse(t.substring(9, t.length - 1)) != null;
  }
  if (t.startsWith('(') && t.endsWith(')')) {
    final inner = t.substring(1, t.length - 1).trim();
    if (inner.startsWith('(') || inner.toLowerCase().startsWith('not ') || inner.toLowerCase().startsWith('selector(')) {
      return supportsCondition(inner);
    }
    final colon = inner.indexOf(':');
    if (colon <= 0) return false;
    return supportsDeclaration(inner.substring(0, colon), inner.substring(colon + 1));
  }
  final colon = t.indexOf(':');
  return colon > 0 && supportsDeclaration(t.substring(0, colon), t.substring(colon + 1));
}

/// Whether `prop: value` would be accepted by the cascade.
bool supportsDeclaration(String prop, String value) {
  final p = prop.trim().toLowerCase();
  if (p.startsWith('--')) return true;
  if (!isSupportedProperty(p)) return false;
  final tokens = CssTokenizer(value.trim()).tokenize();
  if (tokens.any((t) => t.type == CssTokenType.function && t.value.toLowerCase() == 'var')) return true;
  return expandDeclaration(p, tokens) != null;
}
