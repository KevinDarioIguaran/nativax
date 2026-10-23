/// A small Jinja2-like template engine for NativaX.
///
/// Supports the subset used by the Torah+ templates: variables, attribute/
/// index access, filters, `{% if %}`, `{% for %}`, `{% set %}`, `{% include %}`,
/// `{% macro %}`/`{% call %}`, `{% trans %}` and `{% raw %}`. Templates are
/// loaded through a caller-provided [loader] so they can come from assets,
/// disk (Django-style `templates/`) or memory.
library;

import 'dart:async';

/// Loads a template source by name (relative to the templates root).
typedef NativaXTemplateLoader = Future<String?> Function(String name);

class NativaXTemplateEngine {
  NativaXTemplateEngine({
    required this.loader,
    Map<String, dynamic>? globals,
  }) : globals = globals ?? <String, dynamic>{};

  final NativaXTemplateLoader loader;
  final Map<String, dynamic> globals;

  final Map<String, _Template> _cache = <String, _Template>{};

  Future<String> render(String name, [Map<String, dynamic>? context]) async {
    final tpl = await _load(name);
    final scope = <String, dynamic>{...globals, ...?context};
    _injectBuiltins(scope, this);
    final buf = StringBuffer();
    await tpl.render(this, scope, buf);
    return buf.toString();
  }

  Future<String> renderString(String source,
      [Map<String, dynamic>? context, String? name]) async {
    final tpl = _Template.parse(source, name: name);
    final scope = <String, dynamic>{...globals, ...?context};
    _injectBuiltins(scope, this);
    final buf = StringBuffer();
    await tpl.render(this, scope, buf);
    return buf.toString();
  }

  Future<_Template> _load(String name) async {
    final cached = _cache[name];
    if (cached != null) return cached;
    final src = await loader(name);
    if (src == null) {
      throw StateError('template not found: $name');
    }
    final tpl = _Template.parse(src, name: name);
    _cache[name] = tpl;
    return tpl;
  }
}

void _injectBuiltins(Map<String, dynamic> scope, NativaXTemplateEngine engine) {
  if (!scope.containsKey('range')) scope['range'] = _Callable((a, k) => _builtinRange(a, k));
  if (!scope.containsKey('av')) scope['av'] = _Callable((a, k) => a.isNotEmpty ? a.first.toString() : '');
  if (!scope.containsKey('len')) scope['len'] = _Callable((a, k) => _len(a.isNotEmpty ? a.first : null));
  if (!scope.containsKey('_')) {
    // default passthrough translator
    scope['_'] = (Object? s) => s?.toString() ?? '';
  }
}

// ---------------------------------------------------------------------------
// Undefined sentinel
// ---------------------------------------------------------------------------

class _Undefined {
  const _Undefined._();
  @override
  String toString() => '';
}

// ---------------------------------------------------------------------------
// Callable wrappers
// ---------------------------------------------------------------------------

class _Callable {
  _Callable(this.fn);
  final dynamic Function(List<dynamic>, Map<String, dynamic>) fn;
  dynamic call(List<dynamic> a, Map<String, dynamic> k) => fn(a, k);
}

class _MacroCallable {
  _MacroCallable(this.engine, this.params, this.body, this.closure);
  final NativaXTemplateEngine engine;
  final List<String> params;
  final List<_Node> body;
  final Map<String, dynamic> closure;
  Future<String> call(List<dynamic> args, Map<String, dynamic> kwargs,
      {String Function()? caller}) async {
    final child = Map<String, dynamic>.from(closure);
    for (var i = 0; i < params.length; i++) {
      final p = params[i];
      if (i < args.length) {
        child[p] = args[i];
      } else if (kwargs.containsKey(p)) {
        child[p] = kwargs[p];
      } else {
        child[p] = const _Undefined._();
      }
    }
    if (caller != null) child['caller'] = _Callable((a, k) => caller());
    final buf = StringBuffer();
    for (final n in body) {
      await n.render(engine, child, buf);
    }
    return buf.toString();
  }
}

// ---------------------------------------------------------------------------
// AST nodes
// ---------------------------------------------------------------------------

abstract class _Node {
  Future<void> render(NativaXTemplateEngine engine, Map<String, dynamic> scope,
      StringBuffer out);
}

class _TextNode extends _Node {
  _TextNode(this.text);
  final String text;
  @override
  Future<void> render(NativaXTemplateEngine engine, Map<String, dynamic> scope,
      StringBuffer out) async {
    out.write(text);
  }
}

class _PrintNode extends _Node {
  _PrintNode(this.expr, this.filters);
  final String expr;
  final List<_Filter> filters;
  @override
  Future<void> render(NativaXTemplateEngine engine, Map<String, dynamic> scope,
      StringBuffer out) async {
    final eval = _ExprEvaluator(engine, scope);
    dynamic value = await eval.eval(expr);
    for (final f in filters) {
      value = await f.apply(engine, scope, value, eval);
    }
    if (value == null || value is _Undefined) return;
    if (value is bool) {
      out.write(value ? 'True' : 'False');
    } else {
      out.write(value);
    }
  }
}

class _Filter {
  _Filter(this.name, this.args, this.kwargs);
  final String name;
  final List<String> args;
  final Map<String, String> kwargs;
  Future<dynamic> apply(NativaXTemplateEngine engine, Map<String, dynamic> scope,
      dynamic value, _ExprEvaluator eval) async {
    final a = <dynamic>[];
    for (final e in args) a.add(await eval.eval(e));
    final k = <String, dynamic>{};
    for (final entry in kwargs.entries) {
      k[entry.key] = await eval.eval(entry.value);
    }
    return _applyFilter(name, value, a, k);
  }
}

class _Branch {
  _Branch(this.condition, this.nodes);
  final String condition;
  final List<_Node> nodes;
}

class _IfNode extends _Node {
  _IfNode(this.branches, this.elseBranch);
  final List<_Branch> branches;
  final List<_Node>? elseBranch;
  @override
  Future<void> render(NativaXTemplateEngine engine, Map<String, dynamic> scope,
      StringBuffer out) async {
    for (final b in branches) {
      final ev = _ExprEvaluator(engine, scope);
      if (_truthy(await ev.eval(b.condition))) {
        for (final n in b.nodes) {
          await n.render(engine, scope, out);
        }
        return;
      }
    }
    if (elseBranch != null) {
      for (final n in elseBranch!) {
        await n.render(engine, scope, out);
      }
    }
  }
}

class _ForNode extends _Node {
  _ForNode(this.varName, this.iterableExpr, this.body, this.elseBody,
      {this.secondVar});
  final String varName;
  final String? secondVar;
  final String iterableExpr;
  final List<_Node> body;
  final List<_Node>? elseBody;
  @override
  Future<void> render(NativaXTemplateEngine engine, Map<String, dynamic> scope,
      StringBuffer out) async {
    final ev = _ExprEvaluator(engine, scope);
    final iterable = await ev.eval(iterableExpr);
    final items = _asIterable(iterable);
    if (items.isEmpty) {
      if (elseBody != null) {
        for (final n in elseBody!) await n.render(engine, scope, out);
      }
      return;
    }
    var index = 0;
    for (final item in items) {
      final child = Map<String, dynamic>.from(scope);
      if (secondVar != null && item is List && item.length >= 2) {
        child[varName] = item[0];
        child[secondVar!] = item[1];
      } else {
        child[varName] = item;
      }
      child['loop'] = _LoopProxy(index, items.length);
      index++;
      for (final n in body) {
        await n.render(engine, child, out);
      }
    }
  }
}

class _LoopProxy {
  _LoopProxy(this.index0, this.length);
  final int index0;
  final int length;
  int get index => index0 + 1;
  bool get first => index0 == 0;
  bool get last => index0 == length - 1;
}

class _SetNode extends _Node {
  _SetNode(this.name, this.expr);
  final String name;
  final String expr;
  @override
  Future<void> render(NativaXTemplateEngine engine, Map<String, dynamic> scope,
      StringBuffer out) async {
    final ev = _ExprEvaluator(engine, scope);
    scope[name] = await ev.eval(expr);
  }
}

class _IncludeNode extends _Node {
  _IncludeNode(this.nameExpr);
  final String nameExpr;
  @override
  Future<void> render(NativaXTemplateEngine engine, Map<String, dynamic> scope,
      StringBuffer out) async {
    final ev = _ExprEvaluator(engine, scope);
    final name = await ev.eval(nameExpr);
    if (name is _Undefined) return;
    final src = await engine.loader(name.toString());
    if (src == null) return;
    final tpl = _Template.parse(src, name: name.toString());
    await tpl.render(engine, Map<String, dynamic>.from(scope), out);
  }
}

class _MacroNode extends _Node {
  _MacroNode(this.name, this.params, this.body);
  final String name;
  final List<String> params;
  final List<_Node> body;
  @override
  Future<void> render(NativaXTemplateEngine engine, Map<String, dynamic> scope,
      StringBuffer out) async {
    scope[name] = _MacroCallable(engine, params, body, scope);
  }
}

class _CallNode extends _Node {
  _CallNode(this.callExpr, this.body);
  final String callExpr;
  final List<_Node> body;
  @override
  Future<void> render(NativaXTemplateEngine engine, Map<String, dynamic> scope,
      StringBuffer out) async {
    final ev = _ExprEvaluator(engine, scope);
    final macro = await ev.eval(callExpr);
    if (macro is _MacroCallable) {
      final bodyBuf = StringBuffer();
      for (final n in body) {
        await n.render(engine, scope, bodyBuf);
      }
      final bodyStr = bodyBuf.toString();
      final result = await macro.call(<dynamic>[], <String, dynamic>{},
          caller: () => bodyStr);
      out.write(result);
    } else {
      for (final n in body) {
        await n.render(engine, scope, out);
      }
    }
  }
}

class _TransNode extends _Node {
  _TransNode(this.body);
  final List<_Node> body;
  @override
  Future<void> render(NativaXTemplateEngine engine, Map<String, dynamic> scope,
      StringBuffer out) async {
    final buf = StringBuffer();
    for (final n in body) {
      await n.render(engine, scope, buf);
    }
    final text = buf.toString().trim();
    final translator = scope['_'];
    if (translator is Function) {
      try {
        out.write(Function.apply(translator, [text]));
      } catch (_) {
        out.write(text);
      }
    } else if (translator is _Callable) {
      out.write(translator.call([text], const {}));
    } else {
      out.write(text);
    }
  }
}

class _RawNode extends _Node {
  _RawNode(this.text);
  final String text;
  @override
  Future<void> render(NativaXTemplateEngine engine, Map<String, dynamic> scope,
      StringBuffer out) async {
    out.write(text);
  }
}

class _Template {
  _Template(this.nodes, this.name);
  final List<_Node> nodes;
  final String? name;
  static _Template parse(String source, {String? name}) {
    final tokens = _tokenizeTemplate(source);
    final parser = _Parser(tokens);
    final nodes = parser.parse();
    return _Template(nodes, name);
  }

  Future<void> render(NativaXTemplateEngine engine, Map<String, dynamic> scope,
      StringBuffer out) async {
    for (final n in nodes) {
      await n.render(engine, scope, out);
    }
  }
}

// ---------------------------------------------------------------------------
// Template tokenizer
// ---------------------------------------------------------------------------

enum _TokType { text, variable, tag }

class _Tok {
  _Tok(this.type, this.value);
  final _TokType type;
  final String value;
}

List<_Tok> _tokenizeTemplate(String source) {
  final tokens = <_Tok>[];
  var i = 0;
  final buf = StringBuffer();
  var skipWs = false;
  void flushText() {
    if (buf.isNotEmpty) {
      tokens.add(_Tok(_TokType.text, buf.toString()));
      buf.clear();
    }
  }

  void trimLastText() {
    if (buf.isNotEmpty) {
      final s = buf.toString();
      buf.clear();
      buf.write(s.trimRight());
    } else if (tokens.isNotEmpty && tokens.last.type == _TokType.text) {
      final last = tokens.removeLast();
      tokens.add(_Tok(_TokType.text, last.value.trimRight()));
    }
  }

  while (i < source.length) {
    if (source.startsWith('{{', i)) {
      var j = i + 2;
      var trimLeft = false;
      if (j < source.length && source[j] == '-') {
        trimLeft = true;
        j++;
      }
      final end = source.indexOf('}}', j);
      if (end == -1) {
        buf.write(source.substring(i));
        i = source.length;
        continue;
      }
      var content = source.substring(j, end);
      var trimRight = false;
      if (content.trimRight().endsWith('-')) {
        trimRight = true;
        content = content.trimRight();
        content = content.substring(0, content.length - 1);
      }
      if (trimLeft) trimLastText();
      flushText();
      tokens.add(_Tok(_TokType.variable, content.trim()));
      i = end + 2;
      if (trimRight) skipWs = true;
      continue;
    }
    if (source.startsWith('{%', i)) {
      var j = i + 2;
      var trimLeft = false;
      if (j < source.length && source[j] == '-') {
        trimLeft = true;
        j++;
      }
      final end = source.indexOf('%}', j);
      if (end == -1) {
        buf.write(source.substring(i));
        i = source.length;
        continue;
      }
      var content = source.substring(j, end);
      var trimRight = false;
      if (content.trimRight().endsWith('-')) {
        trimRight = true;
        content = content.trimRight();
        content = content.substring(0, content.length - 1);
      }
      if (trimLeft) trimLastText();
      flushText();
      tokens.add(_Tok(_TokType.tag, content.trim()));
      i = end + 2;
      if (trimRight) skipWs = true;
      continue;
    }
    if (source.startsWith('{#', i)) {
      final end = source.indexOf('#}', i + 2);
      if (end == -1) {
        i = source.length;
        continue;
      }
      i = end + 2;
      continue;
    }
    if (skipWs && _isWs(source[i])) {
      i++;
      continue;
    }
    skipWs = false;
    buf.write(source[i]);
    i++;
  }
  flushText();
  return tokens;
}

bool _isWs(String c) => c == ' ' || c == '\t' || c == '\n' || c == '\r';

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

class _Parser {
  _Parser(this.tokens);
  final List<_Tok> tokens;
  int i = 0;

  List<_Node> parse() => parseNodes(const <String>{});

  List<_Node> parseNodes(Set<String> stop) {
    final nodes = <_Node>[];
    while (i < tokens.length) {
      final t = tokens[i];
      if (t.type == _TokType.text) {
        nodes.add(_TextNode(t.value));
        i++;
        continue;
      }
      if (t.type == _TokType.variable) {
        final parsed = _parseVariable(t.value);
        nodes.add(_PrintNode(parsed.$1, parsed.$2));
        i++;
        continue;
      }
      if (t.type == _TokType.tag) {
        final name = _tagName(t.value);
        if (stop.contains(name)) return nodes;
        final node = parseTag();
        if (node != null) nodes.add(node);
        continue;
      }
      i++;
    }
    return nodes;
  }

  _Node? parseTag() {
    final t = tokens[i];
    final name = _tagName(t.value);
    switch (name) {
      case 'if':
        {
          final cond0 = _stripKeyword(t.value, 'if');
          i++;
          final thenBody = parseNodes(const {'elif', 'else', 'endif'});
          final branches = <_Branch>[_Branch(cond0, thenBody)];
          List<_Node>? elseBody;
          while (i < tokens.length && tokens[i].type == _TokType.tag) {
            final n = _tagName(tokens[i].value);
            if (n == 'elif') {
              final c = _stripKeyword(tokens[i].value, 'elif');
              i++;
              final b = parseNodes(const {'elif', 'else', 'endif'});
              branches.add(_Branch(c, b));
            } else if (n == 'else') {
              i++;
              elseBody = parseNodes(const {'endif'});
            } else if (n == 'endif') {
              i++;
              break;
            } else {
              break;
            }
          }
          return _IfNode(branches, elseBody);
        }
      case 'for':
        {
          final header = _stripKeyword(t.value, 'for');
          final inIdx = header.indexOf(' in ');
          final varsPart = header.substring(0, inIdx).trim();
          final expr = header.substring(inIdx + 4).trim();
          String varName;
          String? second;
          if (varsPart.contains(',')) {
            final parts = varsPart.split(',').map((s) => s.trim()).toList();
            varName = parts[0];
            second = parts.length > 1 ? parts[1] : null;
          } else {
            varName = varsPart;
          }
          i++;
          final body = parseNodes(const {'else', 'endfor'});
          List<_Node>? elseBody;
          if (i < tokens.length &&
              tokens[i].type == _TokType.tag &&
              _tagName(tokens[i].value) == 'else') {
            i++;
            elseBody = parseNodes(const {'endfor'});
          }
          if (i < tokens.length &&
              tokens[i].type == _TokType.tag &&
              _tagName(tokens[i].value) == 'endfor') {
            i++;
          }
          return _ForNode(varName, expr, body, elseBody, secondVar: second);
        }
      case 'set':
        {
          final rest = _stripKeyword(t.value, 'set');
          final eq = rest.indexOf('=');
          final name = rest.substring(0, eq).trim();
          final expr = rest.substring(eq + 1).trim();
          i++;
          return _SetNode(name, expr);
        }
      case 'include':
        {
          final expr = t.value.trim().substring('include'.length).trim();
          i++;
          return _IncludeNode(expr);
        }
      case 'macro':
        {
          final rest = _stripKeyword(t.value, 'macro');
          final paren = rest.indexOf('(');
          final name = rest.substring(0, paren).trim();
          final paramsStr = rest.substring(paren + 1, rest.lastIndexOf(')')).trim();
          final params = paramsStr.isEmpty
              ? <String>[]
              : paramsStr.split(',').map((s) => s.trim()).toList();
          i++;
          final body = parseNodes(const {'endmacro'});
          if (i < tokens.length && _tagName(tokens[i].value) == 'endmacro') i++;
          return _MacroNode(name, params, body);
        }
      case 'call':
        {
          final rest = _stripKeyword(t.value, 'call');
          i++;
          final body = parseNodes(const {'endcall'});
          if (i < tokens.length && _tagName(tokens[i].value) == 'endcall') i++;
          return _CallNode(rest.trim(), body);
        }
      case 'trans':
        {
          i++;
          final body = parseNodes(const {'endtrans'});
          if (i < tokens.length && _tagName(tokens[i].value) == 'endtrans') i++;
          return _TransNode(body);
        }
      case 'raw':
        {
          i++;
          final body = parseNodes(const {'endraw'});
          if (i < tokens.length && _tagName(tokens[i].value) == 'endraw') i++;
          final buf = StringBuffer();
          for (final n in body) {
            if (n is _TextNode) buf.write(n.text);
          }
          return _RawNode(buf.toString());
        }
      default:
        i++;
        return null;
    }
  }
}

(String, List<_Filter>) _parseVariable(String content) {
  // split off filters at top level (not inside parens/brackets)
  final filters = <_Filter>[];
  // find first '|' at depth 0
  var depth = 0;
  var inStr = false;
  String strChar = '';
  var i = 0;
  final buf = StringBuffer();
  while (i < content.length) {
    final c = content[i];
    if (inStr) {
      buf.write(c);
      if (c == strChar) inStr = false;
      i++;
      continue;
    }
    if (c == '"' || c == "'") {
      inStr = true;
      strChar = c;
      buf.write(c);
      i++;
      continue;
    }
    if (c == '(' || c == '[' || c == '{') {
      depth++;
      buf.write(c);
      i++;
      continue;
    }
    if (c == ')' || c == ']' || c == '}') {
      depth--;
      buf.write(c);
      i++;
      continue;
    }
    if (c == '|' && depth == 0) {
      // filter follows
      final expr = buf.toString().trim();
      buf.clear();
      // parse filter name + args
      // rest of content from i+1
      final rest = content.substring(i + 1).trim();
      // split multiple filters recursively by calling _parseVariable on rest? Simpler: parse one filter then remainder handled by loop
      // We'll handle only one filter per call by returning early? Instead accumulate.
      // Parse filter:
      final m = RegExp(r'^([a-zA-Z_][a-zA-Z0-9_]*)\s*(.*)$').firstMatch(rest);
      final fname = m?.group(1) ?? rest;
      var argsStr = m?.group(2)?.trim() ?? '';
      // split args at commas depth 0
      final args = <String>[];
      final kwargs = <String, String>{};
      if (argsStr.isNotEmpty && argsStr.startsWith('(') && argsStr.endsWith(')')) {
        argsStr = argsStr.substring(1, argsStr.length - 1);
        // split
        final parts = _splitTopLevel(argsStr);
        for (final p in parts) {
          final t = p.trim();
          if (t.isEmpty) continue;
          final eq = _topLevelEquals(t);
          if (eq != null) {
            kwargs[eq.$1] = eq.$2;
          } else {
            args.add(t);
          }
        }
      } else if (argsStr.isNotEmpty) {
        // filter with single arg without parens (e.g. | default: 'x') Jinja uses colon
        // handle colon syntax
        final colon = _topLevelColon(argsStr);
        if (colon != null) {
          // arg value is rest
          args.add(colon.trim());
        }
      }
      filters.add(_Filter(fname, args, kwargs));
      // done; ignore further filters for simplicity (could recurse)
      return (expr, filters);
    }
    buf.write(c);
    i++;
  }
  return (buf.toString().trim(), filters);
}

(String, String)? _topLevelEquals(String s) {
  // key=value
  var depth = 0;
  var inStr = false;
  String sc = '';
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (inStr) {
      if (c == sc) inStr = false;
      continue;
    }
    if (c == '"' || c == "'") {
      inStr = true;
      sc = c;
      continue;
    }
    if (c == '(' || c == '[' || c == '{') {
      depth++;
      continue;
    }
    if (c == ')' || c == ']' || c == '}') {
      depth--;
      continue;
    }
    if (c == '=' && depth == 0) {
      return (s.substring(0, i).trim(), s.substring(i + 1).trim());
    }
  }
  return null;
}

String? _topLevelColon(String s) {
  // for filter: default: 'x'
  var depth = 0;
  var inStr = false;
  String sc = '';
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (inStr) {
      if (c == sc) inStr = false;
      continue;
    }
    if (c == '"' || c == "'") {
      inStr = true;
      sc = c;
      continue;
    }
    if (c == '(' || c == '[' || c == '{') {
      depth++;
      continue;
    }
    if (c == ')' || c == ']' || c == '}') {
      depth--;
      continue;
    }
    if (c == ':' && depth == 0) {
      return s.substring(i + 1);
    }
  }
  return null;
}

List<String> _splitTopLevel(String s) {
  final parts = <String>[];
  var depth = 0;
  var inStr = false;
  String sc = '';
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (inStr) {
      buf.write(c);
      if (c == sc) inStr = false;
      continue;
    }
    if (c == '"' || c == "'") {
      inStr = true;
      sc = c;
      buf.write(c);
      continue;
    }
    if (c == '(' || c == '[' || c == '{') {
      depth++;
      buf.write(c);
      continue;
    }
    if (c == ')' || c == ']' || c == '}') {
      depth--;
      buf.write(c);
      continue;
    }
    if (c == ',' && depth == 0) {
      parts.add(buf.toString());
      buf.clear();
      continue;
    }
    buf.write(c);
  }
  if (buf.isNotEmpty) parts.add(buf.toString());
  return parts;
}

String _tagName(String tagContent) {
  final trimmed = tagContent.trim();
  final m = RegExp(r'^([a-zA-Z_][a-zA-Z0-9_]*)').firstMatch(trimmed);
  return m?.group(1) ?? '';
}

String _stripKeyword(String tagContent, String keyword) {
  final trimmed = tagContent.trim();
  if (trimmed.toLowerCase().startsWith(keyword.toLowerCase())) {
    return trimmed.substring(keyword.length).trim();
  }
  return trimmed;
}

// ---------------------------------------------------------------------------
// Expression evaluator
// ---------------------------------------------------------------------------

class _ExprEvaluator {
  _ExprEvaluator(this.engine, this.scope);
  final NativaXTemplateEngine engine;
  final Map<String, dynamic> scope;
  List<_ETok> toks = const [];
  int pos = 0;

  Future<dynamic> eval(String expr) async {
    toks = _tokenizeExpr(expr);
    pos = 0;
    if (toks.isEmpty) return null;
    return await parseTernary();
  }

  _ETok? peek() => pos < toks.length ? toks[pos] : null;
  _ETok? next() => pos < toks.length ? toks[pos++] : null;

  bool match(String type, [String? value]) {
    final t = peek();
    if (t == null || t.type != type) return false;
    if (value != null && t.value != value) return false;
    return true;
  }

  Future<dynamic> parseTernary() async {
    final left = await parseOr();
    if (match('id', 'if')) {
      next();
      final cond = await parseOr();
      if (!match('id', 'else')) throw FormatException('expected else');
      next();
      final right = await parseTernary();
      return _truthy(cond) ? left : right;
    }
    return left;
  }

  Future<dynamic> parseOr() async {
    var v = await parseAnd();
    while (match('id', 'or')) {
      next();
      final r = await parseAnd();
      v = _truthy(v) ? v : r;
    }
    return v;
  }

  Future<dynamic> parseAnd() async {
    var v = await parseNot();
    while (match('id', 'and')) {
      next();
      final r = await parseNot();
      v = _truthy(v) && _truthy(r);
    }
    return v;
  }

  Future<dynamic> parseNot() async {
    if (match('id', 'not')) {
      next();
      return !_truthy(await parseNot());
    }
    return await parseCompare();
  }

  Future<dynamic> parseCompare() async {
    var v = await parseAdd();
    while (true) {
      final t = peek();
      if (t == null) break;
      if (t.type == 'op' &&
          (t.value == '==' ||
              t.value == '!=' ||
              t.value == '<' ||
              t.value == '>' ||
              t.value == '<=' ||
              t.value == '>=')) {
        next();
        final r = await parseAdd();
        switch (t.value) {
          case '==':
            v = _equals(v, r);
            break;
          case '!=':
            v = !_equals(v, r);
            break;
          case '<':
            v = _compare(v, r) < 0;
            break;
          case '>':
            v = _compare(v, r) > 0;
            break;
          case '<=':
            v = _compare(v, r) <= 0;
            break;
          case '>=':
            v = _compare(v, r) >= 0;
            break;
        }
      } else if (t.type == 'id' && t.value == 'in') {
        next();
        final r = await parseAdd();
        v = _contains(r, v);
      } else if (t.type == 'id' && t.value == 'not' && pos + 1 < toks.length && toks[pos + 1].value == 'in') {
        next();
        next();
        final r = await parseAdd();
        v = !_contains(r, v);
      } else if (t.type == 'id' && t.value == 'is') {
        next();
        bool neg = false;
        if (match('id', 'not')) {
          neg = true;
          next();
        }
        final nameTok = next();
        final testName = nameTok?.value ?? '';
        List<dynamic> args = <dynamic>[];
        Map<String, dynamic> kwargs = <String, dynamic>{};
        if (match('op', '(')) {
          next();
          final parsed = await parseCallArgs();
          args = parsed.$1;
          kwargs = parsed.$2;
          if (!match('op', ')')) throw FormatException('expected )');
          next();
        }
        final res = _applyTest(testName, v, args, kwargs, scope);
        v = neg ? !res : res;
      } else {
        break;
      }
    }
    return v;
  }

  Future<dynamic> parseAdd() async {
    var v = await parseMul();
    while (match('op', '+') || match('op', '-')) {
      final op = next()!.value;
      final r = await parseMul();
      if (op == '+') {
        if (v is String || r is String) {
          v = '${v == null || v is _Undefined ? '' : v}${r == null || r is _Undefined ? '' : r}';
        } else if (v is num && r is num) {
          v = v + r;
        } else {
          v = null;
        }
      } else {
        if (v is num && r is num) {
          v = v - r;
        } else {
          v = null;
        }
      }
    }
    return v;
  }

  Future<dynamic> parseMul() async {
    var v = await parseUnary();
    while (true) {
      final t = peek();
      if (t != null &&
          t.type == 'op' &&
          (t.value == '*' ||
              t.value == '/' ||
              t.value == '//' ||
              t.value == '%' ||
              t.value == '**')) {
        next();
        final op = t.value;
        final r = await parseUnary();
        if (op == '*') {
          if (v is num && r is num) v = v * r;
          else if (v is String && r is int) v = v * r;
          else v = null;
        } else if (op == '/') {
          v = (v is num && r is num) ? v / r : null;
        } else if (op == '//') {
          v = (v is num && r is num) ? (v / r).floor() : null;
        } else if (op == '%') {
          v = (v is num && r is num) ? v % r : null;
        } else if (op == '**') {
          v = _pow(v, r);
        }
      } else {
        break;
      }
    }
    return v;
  }

  Future<dynamic> parseUnary() async {
    if (match('op', '+')) {
      next();
      return await parseUnary();
    }
    if (match('op', '-')) {
      next();
      final v = await parseUnary();
      return (v is num) ? -v : null;
    }
    return parsePostfix();
  }

  Future<dynamic> parsePostfix() async {
    var v = await parsePrimary();
    while (true) {
      final t = peek();
      if (t == null) break;
      if (t.type == 'op' && t.value == '.') {
        next();
        final attr = next();
        final name = attr?.value ?? '';
        v = _getAttribute(v, name);
        if (match('op', '(')) {
          next();
          final args = await parseCallArgs();
          if (!match('op', ')')) throw FormatException('expected )');
          next();
          v = await _call(v, args.$1, args.$2);
        }
      } else if (t.type == 'op' && t.value == '[') {
        next();
        dynamic start;
        if (!match('op', ':')) {
          start = await parseTernary();
        }
        if (match('op', ':')) {
          next();
          dynamic end;
          if (!match('op', ']')) {
            end = await parseTernary();
          }
          dynamic step;
          if (match('op', ':')) {
            next();
            if (!match('op', ']')) step = await parseTernary();
          }
          if (!match('op', ']')) throw FormatException('expected ]');
          next();
          v = _slice(v, start, end, step);
        } else {
          if (!match('op', ']')) throw FormatException('expected ]');
          next();
          v = _getIndex(v, start);
        }
      } else if (t.type == 'op' && t.value == '(') {
        next();
        final args = await parseCallArgs();
        if (!match('op', ')')) throw FormatException('expected )');
        next();
        v = await _callByName(v, args.$1, args.$2, scope);
      } else if (t.type == 'op' && t.value == '|') {
        next();
        final fTok = next();
        final fName = fTok?.value ?? '';
        List<dynamic> fArgs = <dynamic>[];
        Map<String, dynamic> fKwargs = <String, dynamic>{};
        if (match('op', '(')) {
          next();
          final parsed = await parseCallArgs();
          fArgs = parsed.$1;
          fKwargs = parsed.$2;
          if (!match('op', ')')) throw FormatException('expected )');
          next();
        } else {
          // colon-style argument: | default: 'x'
          // already consumed filter name; check for ':'? Our tokenizer keeps ':' as op.
          if (match('op', ':')) {
            next();
            fArgs.add(await parseTernary());
          }
        }
        v = _applyFilter(fName, v, fArgs, fKwargs);
      } else {
        break;
      }
    }
    return v;
  }

  Future<dynamic> parsePrimary() async {
    final t = peek();
    if (t == null) return null;
    if (t.type == 'num') {
      next();
      final s = t.value;
      if (s.contains('.')) return double.tryParse(s);
      return int.tryParse(s) ?? double.tryParse(s);
    }
    if (t.type == 'str') {
      next();
      return t.value;
    }
    if (t.type == 'op' && t.value == '(') {
      next();
      final v = await parseTernary();
      if (!match('op', ')')) throw FormatException('expected )');
      next();
      return v;
    }
    if (t.type == 'op' && t.value == '[') {
      next();
      final list = <dynamic>[];
      while (!match('op', ']')) {
        list.add(await parseTernary());
        if (match('op', ',')) next();
      }
      next();
      return list;
    }
    if (t.type == 'op' && t.value == '{') {
      next();
      final map = <String, dynamic>{};
      while (!match('op', '}')) {
        final keyTok = next();
        String key;
        if (keyTok?.type == 'str') {
          key = keyTok!.value;
        } else {
          key = keyTok?.value ?? '';
        }
        if (!match('op', ':')) throw FormatException('expected :');
        next();
        map[key] = await parseTernary();
        if (match('op', ',')) next();
      }
      next();
      return map;
    }
    if (t.type == 'id') {
      next();
      final name = t.value;
      if (name == 'true' || name == 'True') return true;
      if (name == 'false' || name == 'False') return false;
      if (name == 'none' || name == 'null' || name == 'None' || name == 'nil') {
        return null;
      }
      if (name == 'undefined') return const _Undefined._();
      return _resolveName(name);
    }
    next();
    return null;
  }

  Future<(List<dynamic>, Map<String, dynamic>)> parseCallArgs() async {
    final args = <dynamic>[];
    final kwargs = <String, dynamic>{};
    if (match('op', ')')) return (args, kwargs);
    while (true) {
      // parse key=value if possible
      // peek ahead: id followed by '='
      if (peek()?.type == 'id' && pos + 1 < toks.length && toks[pos + 1].value == '=') {
        final key = next()!.value;
        next(); // =
        kwargs[key] = await parseTernary();
      } else {
        args.add(await parseTernary());
      }
      if (match('op', ',')) {
        next();
        continue;
      }
      break;
    }
    return (args, kwargs);
  }

  dynamic _resolveName(String name) {
    if (scope.containsKey(name)) return scope[name];
    // builtins
    final b = _builtinsMap(engine);
    if (b.containsKey(name)) return b[name];
    return const _Undefined._();
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Map<String, dynamic> _builtinsMap(NativaXTemplateEngine engine) {
  return <String, dynamic>{
    'range': _Callable((a, k) => _builtinRange(a, k)),
    'av': _Callable((a, k) => a.isNotEmpty ? a.first.toString() : ''),
    'len': _Callable((a, k) => _len(a.isNotEmpty ? a.first : null)),
    'lipsum': _Callable((a, k) => ''),
  };
}

List<dynamic> _builtinRange(List<dynamic> args, Map<String, dynamic> kwargs) {
  int start = 0;
  int stop = 0;
  int step = 1;
  if (args.length == 1) {
    stop = _toInt(args[0]);
  } else if (args.length >= 2) {
    start = _toInt(args[0]);
    stop = _toInt(args[1]);
    if (args.length >= 3) step = _toInt(args[2]);
  }
  if (kwargs.containsKey('start')) start = _toInt(kwargs['start']);
  if (kwargs.containsKey('stop')) stop = _toInt(kwargs['stop']);
  if (kwargs.containsKey('step')) step = _toInt(kwargs['step']);
  if (step == 0) return <dynamic>[];
  final out = <dynamic>[];
  if (step > 0) {
    for (var v = start; v < stop; v += step) out.add(v);
  } else {
    for (var v = start; v > stop; v += step) out.add(v);
  }
  return out;
}

int _toInt(dynamic v) {
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is bool) return v ? 1 : 0;
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

int _len(dynamic v) {
  if (v == null || v is _Undefined) return 0;
  if (v is String) return v.length;
  if (v is List) return v.length;
  if (v is Map) return v.length;
  if (v is Set) return v.length;
  return 0;
}

dynamic _pow(dynamic a, dynamic b) {
  if (a is num && b is num) {
    var r = 1.0;
    for (var i = 0; i < b.toInt(); i++) r *= a;
    if (a is int && b is int) return r.toInt();
    return r;
  }
  return null;
}

List<dynamic> _asIterable(dynamic v) {
  if (v == null || v is _Undefined) return <dynamic>[];
  if (v is List) return v;
  if (v is Set) return v.toList();
  if (v is Map) return v.entries.map((e) => [e.key, e.value]).toList();
  if (v is String) return v.split('');
  if (v is Iterable) return v.toList();
  return <dynamic>[];
}

bool _truthy(dynamic v) {
  if (v == null || v is _Undefined) return false;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v.isNotEmpty;
  if (v is List || v is Map || v is Set) {
    return (v as dynamic).isNotEmpty as bool;
  }
  return true;
}

bool _equals(dynamic a, dynamic b) {
  if (a is _Undefined && b is _Undefined) return true;
  if (a is _Undefined || b is _Undefined) return false;
  if (a == null || b == null) return a == b;
  return a == b;
}

int _compare(dynamic a, dynamic b) {
  if (a is num && b is num) return a.compareTo(b);
  if (a is String && b is String) return a.compareTo(b);
  return 0;
}

bool _contains(dynamic container, dynamic value) {
  if (container is String) return container.contains(value?.toString() ?? '');
  if (container is List) return container.contains(value);
  if (container is Map) return container.containsKey(value) || container.containsValue(value);
  if (container is Set) return container.contains(value);
  return false;
}

dynamic _getIndex(dynamic v, dynamic index) {
  if (v is _Undefined || v == null) return const _Undefined._();
  if (v is List) {
    final i = _toInt(index);
    final idx = i < 0 ? v.length + i : i;
    if (idx < 0 || idx >= v.length) return const _Undefined._();
    return v[idx];
  }
  if (v is Map) {
    final key = index is String ? index : index.toString();
    return v.containsKey(key) ? v[key] : const _Undefined._();
  }
  if (v is String) {
    final i = _toInt(index);
    final idx = i < 0 ? v.length + i : i;
    if (idx < 0 || idx >= v.length) return const _Undefined._();
    return v[idx];
  }
  return const _Undefined._();
}

dynamic _slice(dynamic v, dynamic start, dynamic end, dynamic step) {
  if (v is List) {
    final s = (start == null || start is _Undefined) ? null : _toInt(start);
    final e = (end == null || end is _Undefined) ? null : _toInt(end);
    final st = (step == null || step is _Undefined) ? 1 : _toInt(step);
    if (st == 0) return <dynamic>[];
    final len = v.length;
    int norm(int? x, int def) {
      if (x == null) return def;
      if (x < 0) {
        final r = len + x;
        return r < 0 ? (st > 0 ? 0 : -1) : r;
      }
      if (x > len) return len;
      return x;
    }
    final res = <dynamic>[];
    if (st > 0) {
      var i = norm(s, 0);
      final stop = norm(e, len);
      while (i < stop) {
        if (i >= 0 && i < len) res.add(v[i]);
        i += st;
      }
    } else {
      var i = norm(s, len - 1);
      if (s == null) i = len - 1;
      final stop = norm(e, -1);
      while (i > stop) {
        if (i >= 0 && i < len) res.add(v[i]);
        i += st;
      }
    }
    return res;
  }
  if (v is String) {
    final list = v.split('');
    final sliced = _slice(list, start, end, step) as List<dynamic>;
    return sliced.join();
  }
  return const _Undefined._();
}

dynamic _getAttribute(dynamic v, String name) {
  if (v == null || v is _Undefined) return const _Undefined._();
  if (v is Map) {
    if (v.containsKey(name)) return v[name];
    return const _Undefined._();
  }
  if (v is _MacroCallable) {
    // macro attributes not supported
    return const _Undefined._();
  }
  if (v is _LoopProxy) {
    switch (name) {
      case 'index':
        return v.index;
      case 'index0':
        return v.index0;
      case 'first':
        return v.first;
      case 'last':
        return v.last;
      case 'length':
        return v.length;
    }
  }
  // try property via toString? no.
  return const _Undefined._();
}

Future<dynamic> _call(dynamic value, List<dynamic> args, Map<String, dynamic> kwargs) async {
  if (value is _Callable) return value.call(args, kwargs);
  if (value is _MacroCallable) {
    return await value.call(args, kwargs);
  }
  if (value is Function) {
    try {
      return Function.apply(value, [args, kwargs]);
    } catch (_) {
      try {
        return Function.apply(value, args);
      } catch (_) {
        return null;
      }
    }
  }
  return null;
}

Future<dynamic> _callByName(dynamic value, List<dynamic> args, Map<String, dynamic> kwargs,
    Map<String, dynamic> scope) async {
  return _call(value, args, kwargs);
}

dynamic _applyFilter(String name, dynamic value, List<dynamic> args,
    Map<String, dynamic> kwargs) {
  switch (name) {
    case 'default':
    case 'd':
      if (value == null || value is _Undefined || (value is String && value.isEmpty) && args.isNotEmpty) {
        // Jinja default only replaces undefined by default; keep simple: replace null/undefined/empty
      }
      if (value == null || value is _Undefined) {
        return args.isNotEmpty ? args.first : '';
      }
      if (value is String && value.isEmpty && (kwargs['boolean'] == true)) {
        return args.isNotEmpty ? args.first : value;
      }
      return value;
    case 'length':
    case 'count':
      return _len(value);
    case 'string':
      if (value == null || value is _Undefined) return '';
      return value.toString();
    case 'int':
      return _toInt(value);
    case 'float':
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0.0;
    case 'trim':
      return value?.toString().trim();
    case 'lower':
      return value?.toString().toLowerCase();
    case 'upper':
      return value?.toString().toUpperCase();
    case 'capitalize':
      {
        final s = value?.toString() ?? '';
        if (s.isEmpty) return s;
        return s[0].toUpperCase() + s.substring(1).toLowerCase();
      }
    case 'title':
      {
        final s = value?.toString() ?? '';
        return s.split(' ').map((w) {
          if (w.isEmpty) return w;
          return w[0].toUpperCase() + w.substring(1).toLowerCase();
        }).join(' ');
      }
    case 'first':
      {
        if (value is List && value.isNotEmpty) return value.first;
        if (value is String && value.isNotEmpty) return value[0];
        return null;
      }
    case 'last':
      {
        if (value is List && value.isNotEmpty) return value.last;
        if (value is String && value.isNotEmpty) return value[value.length - 1];
        return null;
      }
    case 'join':
      {
        final sep = args.isNotEmpty ? args.first.toString() : '';
        if (value is List) return value.map((e) => e?.toString() ?? '').join(sep);
        return value?.toString() ?? '';
      }
    case 'reverse':
      {
        if (value is List) return value.reversed.toList();
        if (value is String) return value.split('').reversed.join();
        return value;
      }
    case 'sort':
      {
        if (value is List) {
          final copy = List<dynamic>.from(value);
          copy.sort((a, b) => a.toString().compareTo(b.toString()));
          return copy;
        }
        return value;
      }
    case 'list':
      {
        if (value is String) return value.split('');
        if (value is List) return List<dynamic>.from(value);
        return <dynamic>[value];
      }
    case 'tojson':
      {
        // simple JSON encoding
        return _simpleJson(value);
      }
    case 'safe':
    case 'e':
    case 'escape':
      return value;
    case 'abs':
      {
        if (value is num) return value.abs();
        return value;
      }
    case 'round':
      {
        if (value is num) {
          final precision = args.isNotEmpty ? _toInt(args.first) : 0;
          final f = _pow(10, precision).toDouble();
          return (value * f).round() / f;
        }
        return value;
      }
    case 'replace':
      {
        final s = value?.toString() ?? '';
        if (args.length >= 2) {
          return s.replaceAll(args[0].toString(), args[1].toString());
        }
        return s;
      }
    case 'truncate':
      {
        final s = value?.toString() ?? '';
        final length = args.isNotEmpty ? _toInt(args.first) : 255;
        if (s.length <= length) return s;
        return '${s.substring(0, length)}...';
      }
    case 'attr':
      {
        final name = args.isNotEmpty ? args.first.toString() : '';
        return _getAttribute(value, name);
      }
    case 'items':
      {
        if (value is Map) return value.entries.map((e) => [e.key, e.value]).toList();
        return value;
      }
    default:
      return value;
  }
}

String _simpleJson(dynamic v) {
  if (v == null) return 'null';
  if (v is bool) return v.toString();
  if (v is num) return v.toString();
  if (v is String) return '"${v.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
  if (v is List) return '[${v.map(_simpleJson).join(',')}]';
  if (v is Map) {
    return '{${v.entries.map((e) => '${_simpleJson(e.key.toString())}:${_simpleJson(e.value)}').join(',')}}';
  }
  return '"${v.toString()}"';
}

dynamic _applyTest(String name, dynamic value, List<dynamic> args,
    Map<String, dynamic> kwargs, Map<String, dynamic> scope) {
  switch (name) {
    case 'defined':
      return !(value is _Undefined);
    case 'undefined':
      return value is _Undefined;
    case 'none':
      return value == null;
    case 'true':
      return value == true;
    case 'false':
      return value == false;
    case 'string':
      return value is String;
    case 'number':
    case 'integer':
    case 'int':
      return value is int;
    case 'float':
      return value is double;
    case 'iterable':
    case 'sequence':
      return value is List || value is String || value is Set;
    case 'mapping':
      return value is Map;
    case 'odd':
      return value is int && value.isOdd;
    case 'even':
      return value is int && value.isEven;
    case 'divisibleby':
      {
        final n = args.isNotEmpty ? _toInt(args.first) : 1;
        if (value is num && n != 0) return (value % n) == 0;
        return false;
      }
    case 'sameas':
      return identical(value, args.isNotEmpty ? args.first : null);
    case 'in':
      return _contains(value, args.isNotEmpty ? args.first : null);
    case 'lower':
      return value is String && value == value.toLowerCase();
    case 'upper':
      return value is String && value == value.toUpperCase();
    default:
      return false;
  }
}

// ---------------------------------------------------------------------------
// Expression tokenizer
// ---------------------------------------------------------------------------

class _ETok {
  _ETok(this.type, this.value);
  final String type;
  final String value;
}

List<_ETok> _tokenizeExpr(String s) {
  final toks = <_ETok>[];
  var i = 0;
  while (i < s.length) {
    if (_isWs(s[i])) {
      i++;
      continue;
    }
    if (s[i] == '"' || s[i] == "'") {
      final quote = s[i];
      var j = i + 1;
      final buf = StringBuffer();
      while (j < s.length && s[j] != quote) {
        if (s[j] == '\\') {
          j++;
          if (j < s.length) buf.write(s[j]);
          j++;
          continue;
        }
        buf.write(s[j]);
        j++;
      }
      toks.add(_ETok('str', buf.toString()));
      i = j + 1;
      continue;
    }
    if (_isDigit(s[i]) || (s[i] == '.' && i + 1 < s.length && _isDigit(s[i + 1]))) {
      var j = i;
      while (j < s.length && (_isDigit(s[j]) || s[j] == '.')) j++;
      toks.add(_ETok('num', s.substring(i, j)));
      i = j;
      continue;
    }
    if (_isIdentStart(s[i])) {
      var j = i;
      while (j < s.length && _isIdentPart(s[j])) j++;
      toks.add(_ETok('id', s.substring(i, j)));
      i = j;
      continue;
    }
    // multi-char ops
    if (i + 1 < s.length) {
      final two = s.substring(i, i + 2);
      if (two == '==' ||
          two == '!=' ||
          two == '<=' ||
          two == '>=' ||
          two == '//' ||
          two == '**') {
        toks.add(_ETok('op', two));
        i += 2;
        continue;
      }
    }
    toks.add(_ETok('op', s[i]));
    i++;
  }
  return toks;
}

bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
bool _isIdentStart(String c) {
  final u = c.codeUnitAt(0);
  return (u >= 65 && u <= 90) || (u >= 97 && u <= 122) || c == '_';
}

bool _isIdentPart(String c) {
  return _isIdentStart(c) || _isDigit(c);
}
