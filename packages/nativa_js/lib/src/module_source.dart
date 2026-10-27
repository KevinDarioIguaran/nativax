import 'dart:convert';

/// ES module support for engines without a module loader (JavaScriptCore's
/// C API). A lexical tokenizer (it skips strings, comments, template
/// literals and regular expressions) finds `import`/`export` declarations,
/// `import(...)` and `import.meta`; [ModuleTransform] rewrites a module into
/// an async function run by the module registry in `JscEngine`.
final class ModuleSourceScan {
  ModuleSourceScan._(this.tokens, this.importMetaRanges, this.declarations);

  /// Significant tokens of the source.
  final List<JsToken> tokens;

  /// `[start, end)` offsets of each `import.meta` expression.
  final List<(int, int)> importMetaRanges;

  /// Token indexes of `import`/`export` declarations and `import(...)`.
  final List<int> declarations;

  /// Whether the module imports or exports anything (static or dynamic).
  bool get linksModules => declarations.isNotEmpty;

  /// [source] with every `import.meta` replaced by [name].
  String replaceImportMeta(String source, String name) {
    if (importMetaRanges.isEmpty) return source;
    final out = StringBuffer();
    var last = 0;
    for (final (start, end) in importMetaRanges) {
      out
        ..write(source.substring(last, start))
        ..write(name);
      last = end;
    }
    out.write(source.substring(last));
    return out.toString();
  }

  static ModuleSourceScan of(String source) {
    final tokens = JsTokenizer(source).run();
    final metas = <(int, int)>[];
    final declarations = <int>[];
    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (t.kind != JsTokenKind.word) continue;
      if (t.text != 'import' && t.text != 'export') continue;
      // `a.import`, `a?.export`: property names.
      if (i > 0 && tokens[i - 1].isPunct('.')) continue;
      final next = i + 1 < tokens.length ? tokens[i + 1] : null;
      if (t.text == 'import' && next != null && next.isPunct('.')) {
        final meta = i + 2 < tokens.length ? tokens[i + 2] : null;
        if (meta != null && meta.isWord('meta')) {
          metas.add((t.start, meta.end));
          i += 2;
        }
        continue;
      }
      // `{import: 1}`: a property name.
      if (next != null && next.isPunct(':')) continue;
      declarations.add(i);
    }
    return ModuleSourceScan._(tokens, metas, declarations);
  }
}

enum JsTokenKind { word, punct, string, template, regex, number }

final class JsToken {
  JsToken(
    this.kind,
    this.start,
    this.end,
    this.text,
    this.depth,
    this.newlineBefore,
  );

  final JsTokenKind kind;
  final int start;
  final int end;
  final String text;

  /// Nesting of `()`, `[]` and `{}` (including template substitutions)
  /// before this token.
  final int depth;
  final bool newlineBefore;

  bool isPunct(String p) => kind == JsTokenKind.punct && text == p;
  bool isWord(String w) => kind == JsTokenKind.word && text == w;

  /// The value of a string literal token (simple escapes).
  String get stringValue {
    final raw = text.substring(1, text.length - 1);
    final out = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      final c = raw[i];
      if (c != r'\' || i + 1 >= raw.length) {
        out.write(c);
        continue;
      }
      final n = raw[++i];
      out.write(switch (n) {
        'n' => '\n',
        't' => '\t',
        'r' => '\r',
        '0' => '\x00',
        _ => n,
      });
    }
    return out.toString();
  }
}

// Keywords after which `/` starts a regular expression, not a division.
const _regexAfterKeyword = {
  'return', 'typeof', 'instanceof', 'in', 'of', 'new', 'delete', 'void',
  'throw', 'case', 'do', 'else', 'yield', 'await', 'extends',
};

/// Splits JavaScript source into significant tokens. Whitespace and
/// comments are dropped; template literals give one token per text segment.
final class JsTokenizer {
  JsTokenizer(this.s);

  final String s;
  int i = 0;
  final tokens = <JsToken>[];
  int depth = 0;
  bool newline = false;
  // Depth at which each open template substitution started.
  final templateDepths = <int>[];

  List<JsToken> run() {
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (_isSpace(c)) {
        if (c == 0x0A || c == 0x0D || c == 0x2028 || c == 0x2029) {
          newline = true;
        }
        i++;
      } else if (c == 0x2F && _peek(1) == 0x2F) {
        while (i < s.length && s.codeUnitAt(i) != 0x0A) {
          i++;
        }
      } else if (c == 0x2F && _peek(1) == 0x2A) {
        final end = s.indexOf('*/', i + 2);
        final stop = end < 0 ? s.length : end + 2;
        if (s.substring(i, stop).contains('\n')) newline = true;
        i = stop;
      } else if (c == 0x27 || c == 0x22) {
        final start = i;
        _skipString(c);
        _add(JsTokenKind.string, start);
      } else if (c == 0x60) {
        final start = i;
        i++;
        _template(start);
      } else if (c == 0x2F) {
        final start = i;
        if (_regexAllowed()) {
          _skipRegex();
          _add(JsTokenKind.regex, start);
        } else {
          i++;
          if (i < s.length && s.codeUnitAt(i) == 0x3D) i++;
          _add(JsTokenKind.punct, start);
        }
      } else if (_isIdentStart(c)) {
        final start = i;
        while (i < s.length && _isIdentPart(s.codeUnitAt(i))) {
          i++;
        }
        _add(JsTokenKind.word, start);
      } else if (_isDigit(c) || (c == 0x2E && _isDigit(_peek(1)))) {
        final start = i;
        _skipNumber();
        _add(JsTokenKind.number, start);
      } else if (c == 0x2E && _peek(1) == 0x2E && _peek(2) == 0x2E) {
        final start = i;
        i += 3;
        _add(JsTokenKind.punct, start);
      } else if (c == 0x28 || c == 0x5B || c == 0x7B) {
        final start = i++;
        _add(JsTokenKind.punct, start);
        depth++;
      } else if (c == 0x29 || c == 0x5D || c == 0x7D) {
        if (c == 0x7D &&
            templateDepths.isNotEmpty &&
            templateDepths.last == depth) {
          templateDepths.removeLast();
          depth--;
          final start = i;
          i++;
          _template(start);
        } else {
          depth--;
          final start = i++;
          _add(JsTokenKind.punct, start);
        }
      } else if (c == 0x3F && _peek(1) == 0x2E && !_isDigit(_peek(2))) {
        // Optional chaining `?.` counts as `.` for member access.
        final start = i;
        i += 2;
        tokens.add(JsToken(JsTokenKind.punct, start, i, '.', depth, newline));
        newline = false;
      } else {
        final start = i++;
        _add(JsTokenKind.punct, start);
      }
    }
    return tokens;
  }

  void _add(JsTokenKind kind, int start) {
    tokens.add(JsToken(kind, start, i, s.substring(start, i), depth, newline));
    newline = false;
  }

  int _peek(int offset) =>
      i + offset < s.length ? s.codeUnitAt(i + offset) : -1;

  bool _regexAllowed() {
    if (tokens.isEmpty) return true;
    final prev = tokens.last;
    switch (prev.kind) {
      case JsTokenKind.word:
        return _regexAfterKeyword.contains(prev.text);
      case JsTokenKind.string:
      case JsTokenKind.number:
      case JsTokenKind.regex:
        return false;
      case JsTokenKind.template:
        // A finished template (closing backtick) ends an expression; a
        // segment ending in `${` starts one.
        return prev.text.endsWith(r'${');
      case JsTokenKind.punct:
        // After `)`/`]` the slash divides. After `}` it starts a statement
        // (block end), the common case in bundles.
        return prev.text != ')' && prev.text != ']';
    }
  }

  // Template characters after a backtick or the `}` closing a
  // substitution; stops after the closing backtick or inside `${`.
  void _template(int start) {
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (c == 0x5C) {
        i += 2;
      } else if (c == 0x60) {
        i++;
        _add(JsTokenKind.template, start);
        return;
      } else if (c == 0x24 && _peek(1) == 0x7B) {
        i += 2;
        _add(JsTokenKind.template, start);
        depth++;
        templateDepths.add(depth);
        return;
      } else {
        i++;
      }
    }
    _add(JsTokenKind.template, start);
  }

  void _skipString(int quote) {
    i++;
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (c == 0x5C) {
        i += 2;
      } else if (c == quote || c == 0x0A) {
        i++;
        return;
      } else {
        i++;
      }
    }
  }

  void _skipRegex() {
    i++;
    var inClass = false;
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (c == 0x5C) {
        i += 2;
        continue;
      }
      if (c == 0x0A) break;
      i++;
      if (inClass) {
        if (c == 0x5D) inClass = false;
      } else if (c == 0x5B) {
        inClass = true;
      } else if (c == 0x2F) {
        break;
      }
    }
    while (i < s.length && _isIdentPart(s.codeUnitAt(i))) {
      i++;
    }
  }

  void _skipNumber() {
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (_isIdentPart(c) || c == 0x2E) {
        i++;
      } else if ((c == 0x2B || c == 0x2D) &&
          (s.codeUnitAt(i - 1) | 0x20) == 0x65 &&
          !(s.startsWith('0x', i - 2) || s.startsWith('0X', i - 2))) {
        i++;
      } else {
        break;
      }
    }
  }

  static bool _isSpace(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0B ||
      c == 0x0C || c == 0xA0 || c == 0xFEFF || c == 0x2028 || c == 0x2029;

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  static bool _isIdentStart(int c) =>
      (c >= 0x61 && c <= 0x7A) ||
      (c >= 0x41 && c <= 0x5A) ||
      c == 0x24 ||
      c == 0x5F ||
      c == 0x5C ||
      c > 0x7F;

  static bool _isIdentPart(int c) => _isIdentStart(c) || _isDigit(c);
}

/// A module that cannot be rewritten (an unsupported export form).
final class ModuleTransformException implements Exception {
  ModuleTransformException(this.message);
  final String message;
  @override
  String toString() => 'SyntaxError: $message';
}

/// Rewrites an ES module into the source of an async function
/// `(__nx_import, __nx_export, __nx_import_meta, __nx_dynamic, __nx_star)`
/// for the module registry in `JscEngine`:
///
/// - `export` declarations become plain declarations; every export is
///   registered first as a getter on the namespace (live bindings).
/// - `import` declarations are hoisted: each dependency is awaited and its
///   bindings are copied (a snapshot, not a live binding).
/// - `import(x)` calls `__nx_dynamic(x)`; `import.meta` is
///   `__nx_import_meta`.
///
/// Removed text is replaced by its newlines, so line numbers stay.
final class ModuleTransform {
  ModuleTransform._(this.source, this.scan);

  final String source;
  final ModuleSourceScan scan;
  final _edits = <(int, int, String)>[];
  final _exports = <String, String>{}; // exported name -> getter body
  final _header = StringBuffer();
  int _modules = 0;

  static String transform(String source) {
    final scan = ModuleSourceScan.of(source);
    return ModuleTransform._(source, scan)._run();
  }

  List<JsToken> get _t => scan.tokens;

  String _run() {
    for (final (start, end) in scan.importMetaRanges) {
      _edits.add((start, end, '__nx_import_meta'));
    }
    for (final index in scan.declarations) {
      if (_t[index].text == 'import') {
        _import(index);
      } else {
        _export(index);
      }
    }
    _edits.sort((a, b) => a.$1.compareTo(b.$1));
    final body = StringBuffer();
    var last = 0;
    for (final (start, end, text) in _edits) {
      if (start < last) continue;
      body
        ..write(source.substring(last, start))
        ..write(text);
      last = end;
    }
    body.write(source.substring(last));
    final getters = _exports.entries
        .map((e) => '${jsonEncode(e.key)}: () => ${e.value}')
        .join(', ');
    return '(async function (__nx_import, __nx_export, __nx_import_meta, '
        "__nx_dynamic, __nx_star) {'use strict'; __nx_export({$getters}); "
        '$_header\n$body\n})';
  }

  JsToken? _at(int i) => i >= 0 && i < _t.length ? _t[i] : null;

  // Replaces [start, end) by its newlines only.
  void _remove(int start, int end) {
    final removed = source.substring(start, end);
    _edits.add((start, end, '\n' * '\n'.allMatches(removed).length));
  }

  String _module(String specifier) {
    final name = '__nx_m${_modules++}';
    _header.write(
      'const $name = await __nx_import(${jsonEncode(specifier)}); ',
    );
    return name;
  }

  Never _fail(int index, String what) => throw ModuleTransformException(
    '$what at offset ${_t[index].start} is not supported',
  );

  // End offset of a declaration whose last token is before [index]; a `;`
  // at [index] is included.
  int _endOfStatement(int index) {
    final t = _at(index);
    if (t != null && t.isPunct(';')) return t.end;
    return _t[index - 1].end;
  }

  String _name(JsToken t) =>
      t.kind == JsTokenKind.string ? t.stringValue : t.text;

  void _import(int index) {
    if (_at(index + 1)?.isPunct('(') ?? false) {
      _edits.add((_t[index].start, _t[index].end, '__nx_dynamic'));
      return;
    }
    var i = index + 1;
    // import 'spec';
    if (_at(i)?.kind == JsTokenKind.string) {
      _module(_t[i].stringValue);
      i = _skipAttributes(i + 1);
      _remove(_t[index].start, _endOfStatement(i));
      return;
    }
    final bindings = <(String, String)>[]; // (imported, local)
    String? namespace;
    final first = _at(i);
    if (first != null &&
        first.kind == JsTokenKind.word &&
        !first.isWord('from')) {
      bindings.add(('default', first.text));
      i++;
      if (_at(i)?.isPunct(',') ?? false) i++;
    }
    if (_at(i)?.isPunct('*') ?? false) {
      if (!(_at(i + 1)?.isWord('as') ?? false)) _fail(index, 'import *');
      namespace = _t[i + 2].text;
      i += 3;
    } else if (_at(i)?.isPunct('{') ?? false) {
      i++;
      while (i < _t.length && !_t[i].isPunct('}')) {
        final imported = _name(_t[i]);
        var local = imported;
        i++;
        if (_at(i)?.isWord('as') ?? false) {
          local = _t[i + 1].text;
          i += 2;
        }
        bindings.add((imported, local));
        if (_at(i)?.isPunct(',') ?? false) i++;
      }
      i++;
    }
    if (!(_at(i)?.isWord('from') ?? false) ||
        _at(i + 1)?.kind != JsTokenKind.string) {
      _fail(index, 'import clause');
    }
    final specifier = _t[i + 1].stringValue;
    final module = _module(specifier);
    if (namespace != null) _header.write('const $namespace = $module; ');
    for (final (imported, local) in bindings) {
      _header.write(
        'const $local = __nx_import.binding($module, ${jsonEncode(imported)}, '
        '${jsonEncode(specifier)}); ',
      );
    }
    i = _skipAttributes(i + 2);
    _remove(_t[index].start, _endOfStatement(i));
  }

  // `with { type: 'json' }` / `assert {...}` after a specifier.
  int _skipAttributes(int i) {
    final t = _at(i);
    if (t != null &&
        (t.isWord('with') || t.isWord('assert')) &&
        (_at(i + 1)?.isPunct('{') ?? false)) {
      final depth = _t[i + 1].depth;
      i += 2;
      while (i < _t.length && !(_t[i].isPunct('}') && _t[i].depth == depth)) {
        i++;
      }
      return i + 1;
    }
    return i;
  }

  void _export(int index) {
    final start = _t[index].start;
    var i = index + 1;
    final t = _at(i);
    if (t == null) _fail(index, 'export');
    // export * from 'm' / export * as ns from 'm'
    if (t.isPunct('*')) {
      i++;
      String? alias;
      if (_at(i)?.isWord('as') ?? false) {
        alias = _name(_t[i + 1]);
        i += 2;
      }
      if (!(_at(i)?.isWord('from') ?? false) ||
          _at(i + 1)?.kind != JsTokenKind.string) {
        _fail(index, 'export *');
      }
      final module = _module(_t[i + 1].stringValue);
      if (alias == null) {
        _header.write('__nx_star($module); ');
      } else {
        _exports[alias] = module;
      }
      _remove(start, _endOfStatement(_skipAttributes(i + 2)));
      return;
    }
    // export { a, b as c } [from 'm']
    if (t.isPunct('{')) {
      final pairs = <(String, String)>[]; // (local or imported, exported)
      i++;
      while (i < _t.length && !_t[i].isPunct('}')) {
        final local = _name(_t[i]);
        var exported = local;
        i++;
        if (_at(i)?.isWord('as') ?? false) {
          exported = _name(_t[i + 1]);
          i += 2;
        }
        pairs.add((local, exported));
        if (_at(i)?.isPunct(',') ?? false) i++;
      }
      i++;
      if ((_at(i)?.isWord('from') ?? false) &&
          _at(i + 1)?.kind == JsTokenKind.string) {
        final module = _module(_t[i + 1].stringValue);
        for (final (imported, exported) in pairs) {
          _exports[exported] = '$module[${jsonEncode(imported)}]';
        }
        i = _skipAttributes(i + 2);
      } else {
        for (final (local, exported) in pairs) {
          _exports[exported] = local;
        }
      }
      _remove(start, _endOfStatement(i));
      return;
    }
    // export default ...
    if (t.isWord('default')) {
      var j = i + 1;
      if ((_at(j)?.isWord('async') ?? false) &&
          (_at(j + 1)?.isWord('function') ?? false)) {
        j++;
      }
      final isFunction = _at(j)?.isWord('function') ?? false;
      final isClass = _at(j)?.isWord('class') ?? false;
      if (isFunction || isClass) {
        var k = j + 1;
        if (_at(k)?.isPunct('*') ?? false) k++;
        final name = _at(k);
        if (name != null &&
            name.kind == JsTokenKind.word &&
            !name.isWord('extends')) {
          // `export default function f() {}` declares `f`.
          _edits.add((start, _t[i + 1].start, ''));
          _exports['default'] = name.text;
          return;
        }
      }
      // An expression (or anonymous function/class): bind it to a const.
      _edits.add((start, _t[i + 1].start, 'const __nx_default = '));
      _exports['default'] = '__nx_default';
      if (isFunction || isClass) _terminateBody(j);
      return;
    }
    // export function / async function / function* / class
    if (t.isWord('function') ||
        t.isWord('class') ||
        (t.isWord('async') && (_at(i + 1)?.isWord('function') ?? false))) {
      var k = t.isWord('async') ? i + 2 : i + 1;
      if (_at(k)?.isPunct('*') ?? false) k++;
      _exports[_t[k].text] = _t[k].text;
      _edits.add((start, t.start, ''));
      return;
    }
    // export const/let/var
    if (t.isWord('const') || t.isWord('let') || t.isWord('var')) {
      for (final name in _declaredNames(i + 1, t.depth)) {
        _exports[name] = name;
      }
      _edits.add((start, t.start, ''));
      return;
    }
    _fail(index, 'export ${t.text}');
  }

  // Adds `;` after the body of an anonymous default function or class that
  // became an expression, so a following `(` or `[` does not call it.
  void _terminateBody(int keyword) {
    var k = keyword;
    final depth = _t[keyword].depth;
    // The body is the first `{` at the keyword's depth after the parameter
    // list (or the `extends` clause).
    while (k < _t.length && !(_t[k].isPunct('{') && _t[k].depth == depth)) {
      k++;
    }
    k++;
    while (k < _t.length && !(_t[k].isPunct('}') && _t[k].depth == depth)) {
      k++;
    }
    if (k < _t.length) _edits.add((_t[k].end, _t[k].end, ';'));
  }

  // Names bound by `const|let|var <declarators>` starting at token [i].
  List<String> _declaredNames(int i, int depth) {
    final names = <String>[];
    while (i < _t.length) {
      final t = _t[i];
      if (t.kind == JsTokenKind.word) {
        names.add(t.text);
      } else if (t.isPunct('{') || t.isPunct('[')) {
        i = _patternNames(i, names);
      } else {
        throw ModuleTransformException(
          'unsupported export declarator at offset ${t.start}',
        );
      }
      // Skip the initializer to the next declarator or the end.
      i++;
      while (i < _t.length) {
        final u = _t[i];
        if (u.depth < depth) return names;
        if (u.depth == depth) {
          if (u.isPunct(',')) break;
          if (u.isPunct(';')) return names;
          if (u.newlineBefore &&
              u.kind == JsTokenKind.word &&
              _statementStarts.contains(u.text)) {
            return names;
          }
        }
        i++;
      }
      if (i >= _t.length) return names;
      i++; // the comma
    }
    return names;
  }

  // Binding names of a destructuring pattern starting at `{` or `[`;
  // returns the index of its closing token.
  int _patternNames(int i, List<String> names) {
    final depth = _t[i].depth;
    final isObject = _t[i].isPunct('{');
    i++;
    while (i < _t.length) {
      final t = _t[i];
      if (t.depth == depth && (t.isPunct('}') || t.isPunct(']'))) return i;
      if (t.depth != depth + 1) {
        i++;
        continue;
      }
      if (t.isPunct('{') || t.isPunct('[')) {
        i = _patternNames(i, names) + 1;
        continue;
      }
      if (t.kind == JsTokenKind.word) {
        if (isObject && (_at(i + 1)?.isPunct(':') ?? false)) {
          i += 2;
          continue;
        }
        names.add(t.text);
        i++;
        if (_at(i)?.isPunct('=') ?? false) {
          // Skip the default value.
          i++;
          while (i < _t.length &&
              !(_t[i].depth == depth + 1 && _t[i].isPunct(',')) &&
              _t[i].depth > depth) {
            i++;
          }
        }
        continue;
      }
      i++;
    }
    return i;
  }

  static const _statementStarts = {
    'const', 'let', 'var', 'function', 'class', 'if', 'for', 'while', 'do',
    'return', 'export', 'import', 'switch', 'try', 'throw', 'async',
  };
}
