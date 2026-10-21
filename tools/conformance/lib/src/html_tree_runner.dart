import 'dart:convert';
import 'dart:io';

import 'package:nativax_dom/nativax_dom.dart' as dom;
import 'package:nativax_html/nativax_html.dart';
import 'package:path/path.dart' as p;

import 'result.dart';

class HtmlTreeRunOptions {
  const HtmlTreeRunOptions({
    required this.suitePath,
    this.limit,
    this.verbose = false,
  });
  final String suitePath;
  final int? limit;
  final bool verbose;
}

/// Runs the WHATWG tree-construction fixtures that ship with WPT under
/// `html/syntax/parsing/resources/*.dat` (the successor of html5lib's
/// tree-construction directory).
class HtmlTreeRunner {
  HtmlTreeRunner(this.options);

  final HtmlTreeRunOptions options;

  Future<RunSummary> run() async {
    final started = DateTime.now();
    final clock = Stopwatch()..start();
    final resources =
        Directory(p.join(options.suitePath, 'html', 'syntax', 'parsing', 'resources'));
    if (!resources.existsSync()) {
      throw StateError('tree-construction fixtures not found at ${resources.path}');
    }
    final files = resources
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dat'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    final results = <TestResult>[];
    for (final file in files) {
      final cases = _parse(file.readAsStringSync());
      for (var i = 0; i < cases.length; i++) {
        if (options.limit != null && results.length >= options.limit!) break;
        results.add(_runCase('${p.basename(file.path)}#$i', cases[i]));
      }
    }
    clock.stop();
    return RunSummary(
      suite: 'wpt-html-tree',
      startedAt: started,
      durationMs: clock.elapsedMilliseconds,
      results: results,
      command:
          'run_html_tree${options.limit == null ? '' : ' --limit ${options.limit}'}',
    );
  }

  TestResult _runCase(String id, _Case test) {
    if (test.scriptOff) {
      return TestResult(
        suite: 'wpt-html-tree',
        id: id,
        status: ResultStatus.skip,
        reason: 'script-off fixtures need a scripting flag; the parser has no '
            'flag',
        features: const ['html-parser'],
      );
    }
    final fragment = test.fragmentContext;
    if (fragment != null &&
        (fragment.contains(' ') ||
            fragment == 'svg' ||
            fragment == 'math' ||
            fragment == 'template')) {
      return TestResult(
        suite: 'wpt-html-tree',
        id: id,
        status: ResultStatus.skip,
        reason: 'fragment context "$fragment" needs foreign content or '
            'template support',
        features: const ['html-parser'],
      );
    }
    try {
      final parser = HtmlParser();
      final List<dom.Node> actual;
      if (test.fragmentContext != null) {
        final doc = dom.Document();
        final context = doc.createElement(test.fragmentContext!);
        final parsed = parser.parseFragment(test.data, context);
        actual = parsed.value.childNodes.toList();
      } else {
        final parsed = parser.parseDocument(test.data);
        actual = parsed.value.childNodes.toList();
      }
      final normalized = _normalize(actual);
      if (_same(normalized, test.expected)) {
        return TestResult(
          suite: 'wpt-html-tree',
          id: id,
          status: ResultStatus.pass,
          features: const ['html-parser'],
        );
      }
      return TestResult(
        suite: 'wpt-html-tree',
        id: id,
        status: ResultStatus.fail,
        reason: 'DOM tree differs from the fixture',
        detail: 'input: ${jsonEncode(test.data)}\n'
            'expected: ${_render(test.expected)}\n'
            'actual:   ${_render(normalized)}',
        features: const ['html-parser'],
      );
    } catch (error) {
      return TestResult(
        suite: 'wpt-html-tree',
        id: id,
        status: ResultStatus.error,
        reason: 'runner/parser failure: $error',
        features: const ['html-parser'],
      );
    }
  }
}

class _Case {
  _Case({
    required this.data,
    required this.expected,
    this.fragmentContext,
    this.scriptOff = false,
  });
  final String data;
  final List<Object> expected;
  final String? fragmentContext;
  final bool scriptOff;
}

List<_Case> _parse(String source) {
  final lines = const LineSplitter().convert(source);
  final cases = <_Case>[];
  var i = 0;
  while (i < lines.length) {
    if (lines[i] != '#data') {
      i++;
      continue;
    }
    i++;
    final data = StringBuffer();
    while (i < lines.length && !lines[i].startsWith('#')) {
      if (data.isNotEmpty) data.write('\n');
      data.write(lines[i]);
      i++;
    }
    String? fragment;
    var scriptOff = false;
    List<Object> expected = [];
    while (i < lines.length && !lines[i].startsWith('#data')) {
      final marker = lines[i];
      i++;
      if (marker == '#document-fragment') {
        fragment = lines[i].trim();
        i++;
      } else if (marker == '#script-off') {
        scriptOff = true;
      } else if (marker == '#document') {
        final tree = <String>[];
        while (i < lines.length &&
            lines[i].startsWith('|') &&
            lines[i].trim().isNotEmpty) {
          tree.add(lines[i]);
          i++;
        }
        expected = _parseTree(tree);
      }
    }
    cases.add(_Case(
      data: data.toString(),
      expected: expected,
      fragmentContext: fragment,
      scriptOff: scriptOff,
    ));
  }
  return cases;
}

List<Object> _parseTree(List<String> lines) {
  final root = <Object>[];
  final stack = <(int, List<Object>)>[(0, root)];
  for (final line in lines) {
    final content = line.substring(2); // skip "| "
    final indent = content.length - content.trimLeft().length;
    final text = content.trim();
    while (stack.length > 1 && stack.last.$1 >= indent) {
      stack.removeLast();
    }
    final parent = stack.last.$2;
    final node = _parseNode(text);
    if (node == null) continue;
    parent.add(node);
    if (node is _Element && !node.selfClosing) {
      stack.add((indent + 1, node.children));
    }
  }
  return root;
}

Object? _parseNode(String text) {
  if (text.startsWith('"') && text.length >= 2) {
    try {
      return _TextNode(jsonDecode(text) as String);
    } on FormatException {
      return _TextNode(text.substring(1, text.length - 1));
    }
  }
  if (text.startsWith('<!--') && text.endsWith('-->')) {
    return _Comment(text.substring(4, text.length - 3));
  }
  if (text.startsWith('<?') && text.endsWith('>')) {
    return _Comment(text.substring(2, text.length - 1));
  }
  if (text.startsWith('<!DOCTYPE')) {
    final inner = text.substring(9, text.length - 1).trim();
    final nameMatch = RegExp(r'^([^\s]+)').firstMatch(inner);
    final name = nameMatch?.group(1) ?? '';
    final rest = nameMatch == null ? '' : inner.substring(nameMatch.end).trim();
    final strings = RegExp(r'''"([^"]*)"|'([^']*)' ''')
        .allMatches(rest)
        .map((m) => m.group(1) ?? m.group(2) ?? '')
        .toList();
    return _Doctype(
      name,
      strings.isNotEmpty ? strings[0] : '',
      strings.length > 1 ? strings[1] : '',
    );
  }
  if (text.startsWith('<') && text.endsWith('>')) {
    var inner = text.substring(1, text.length - 1).trim();
    if (inner.endsWith('/')) inner = inner.substring(0, inner.length - 1).trim();
    final space = inner.indexOf(RegExp(r'\s'));
    final name = (space < 0 ? inner : inner.substring(0, space)).toLowerCase();
    final attrs = <String, String>{};
    if (space >= 0) {
      final re = RegExp(r'([^\s=]+)="([^"]*)"');
      for (final match in re.allMatches(inner.substring(space))) {
        attrs[match.group(1)!] = match.group(2)!;
      }
    }
    return _Element(name, attrs);
  }
  return null;
}

class _Element {
  _Element(this.name, this.attributes);
  final String name;
  final Map<String, String> attributes;
  final List<Object> children = [];
  bool selfClosing = false;
}

class _TextNode {
  const _TextNode(this.text);
  final String text;
}

class _Comment {
  const _Comment(this.text);
  final String text;
}

class _Doctype {
  const _Doctype(this.name, this.publicId, this.systemId);
  final String name;
  final String publicId;
  final String systemId;
}

List<Object> _normalize(List<dom.Node> nodes) {
  final out = <Object>[];
  for (final node in nodes) {
    if (node is dom.Text) {
      if (node.data.isEmpty) continue;
      if (out.isNotEmpty && out.last is _TextNode) {
        final previous = out.removeLast() as _TextNode;
        out.add(_TextNode(previous.text + node.data));
      } else {
        out.add(_TextNode(node.data));
      }
    } else if (node is dom.Comment) {
      out.add(_Comment(node.data));
    } else if (node is dom.DocumentType) {
      out.add(_Doctype(node.name, node.publicId, node.systemId));
    } else if (node is dom.Element) {
      final element = _Element(node.localName, Map.of(node.attributes));
      element.children.addAll(_normalize(node.childNodes.toList()));
      out.add(element);
    }
  }
  return out;
}

bool _same(Object? a, Object? b) {
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_same(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is _TextNode && b is _TextNode) return a.text == b.text;
  if (a is _Comment && b is _Comment) {
    if (a.text == b.text) return true;
    // html5lib .dat writes processing instructions as `<?target ?>`, while
    // the HTML DOM represents them as comments with data `?target`.
    if (b.text.endsWith(' ?') && a.text.startsWith('?')) {
      return b.text.substring(0, b.text.length - 2) == a.text.substring(1);
    }
    return false;
  }
  if (a is _Doctype && b is _Doctype) {
    return a.name == b.name &&
        a.publicId == b.publicId &&
        a.systemId == b.systemId;
  }
  if (a is _Element && b is _Element) {
    if (a.name != b.name || a.attributes.length != b.attributes.length) {
      return false;
    }
    for (final e in a.attributes.entries) {
      if (b.attributes[e.key] != e.value) return false;
    }
    if (a.children.length != b.children.length) return false;
    for (var i = 0; i < a.children.length; i++) {
      if (!_same(a.children[i], b.children[i])) return false;
    }
    return true;
  }
  return false;
}

String _render(List<Object> nodes, [String indent = '']) {
  final out = StringBuffer();
  for (final node in nodes) {
    switch (node) {
      case _TextNode(:final text):
        out.writeln('$indent"${text.replaceAll('\n', r'\n')}"');
      case _Comment(:final text):
        out.writeln('$indent<!--$text-->');
      case _Doctype(:final name, :final publicId, :final systemId):
        out.writeln('$indent<!DOCTYPE $name'
            '${publicId.isEmpty && systemId.isEmpty ? '' : ' "$publicId" "$systemId"'}'
            '>');
      case _Element(:final name, :final attributes, :final children):
        out.writeln('$indent<$name${attributes.isEmpty ? '' : ' $attributes'}>');
        out.write(_render(children, '$indent  '));
      default:
        out.writeln('$indent$node');
    }
  }
  return out.toString();
}
