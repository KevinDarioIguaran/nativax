import 'package:nativax_dom/nativax_dom.dart';

import 'parser_error.dart';
import 'token.dart';
import 'tokenizer.dart';

/// Elements allowed in `<head>` before `<body>` starts.
const Set<String> _headElements = {
  'title', 'meta', 'link', 'style', 'script', 'base', 'noscript', //
};

/// Start tags that implicitly close an open `<p>`.
const Set<String> _closesP = {
  'address', 'article', 'aside', 'blockquote', 'details', 'div', 'dl',
  'fieldset', 'figcaption', 'figure', 'footer', 'form', 'h1', 'h2', 'h3',
  'h4', 'h5', 'h6', 'header', 'hr', 'main', 'menu', 'nav', 'ol', 'p', 'pre',
  'section', 'table', 'ul', //
};

/// Elements that bound the search for an implicitly closed `li`, `dd`, `dt`
/// or `option`.
const Set<String> _listScopes = {'ul', 'ol', 'menu', 'dl', 'select', 'datalist'};

/// Result of a parse: the tree plus every recoverable error encountered.
class HtmlParseResult<T> {
  HtmlParseResult(this.value, this.errors, this.droppedErrors);
  final T value;
  final List<HtmlParseError> errors;

  /// Errors beyond [HtmlParserLimits.maxErrors] (counted, not stored).
  final int droppedErrors;
}

/// Builds a NativaX [Document] from HTML.
///
/// This is a simplified tree construction algorithm, not the full WHATWG
/// one. It implements implicit `html`/`head`/`body`, void elements, raw text
/// elements, implicit closing of `p`, `li`, `dd`, `dt` and `option`, and
/// recovery from unmatched end tags. It does not implement the adoption
/// agency algorithm (misnested formatting), foster parenting (tables),
/// `template`, foreign content (SVG/MathML) or quirks mode. See
/// docs/html-supported.md.
class HtmlParser {
  HtmlParser({this.limits = const HtmlParserLimits()});

  final HtmlParserLimits limits;

  HtmlParseResult<Document> parseDocument(
    String source, {
    DocumentLimits documentLimits = const DocumentLimits(),
  }) {
    final doc = Document(limits: documentLimits);
    final builder = _TreeBuilder(doc, source, limits, fragment: false);
    builder.run();
    doc.adoptParsed([builder.html]);
    return HtmlParseResult(doc, builder.errors, builder.dropped);
  }

  /// Parses [source] as the children of [context] (used by `innerHTML`).
  /// No implicit `html`/`head`/`body` are created. The returned fragment is
  /// owned by [context]'s document.
  HtmlParseResult<DocumentFragment> parseFragment(String source, Element context) {
    final doc = context.ownerDocument;
    final builder = _TreeBuilder(doc, source, limits, fragment: true);
    builder.run();
    final fragment = doc.createDocumentFragment();
    for (final n in List.of(builder.fragmentRoot.childNodes)) {
      fragment.appendParsed(n);
    }
    return HtmlParseResult(fragment, builder.errors, builder.dropped);
  }
}

class _TreeBuilder {
  _TreeBuilder(this.doc, this.source, this.limits, {required this.fragment});

  final Document doc;
  final String source;
  final HtmlParserLimits limits;
  final bool fragment;

  final List<HtmlParseError> errors = [];
  int dropped = 0;
  int _nodes = 0;
  List<int>? _lineStarts;

  late final Element html;
  late final Element head;
  late final Element body;
  late final Element fragmentRoot;
  bool _bodyStarted = false;
  bool _sawHtmlTag = false;

  /// Open elements; [0] is the root of insertion.
  final List<Element> _stack = [];

  Element get _current => _stack.last;

  void _error(String code, int offset, [String? detail]) {
    if (errors.length >= limits.maxErrors) {
      dropped++;
      return;
    }
    final (line, col) = _position(offset);
    errors.add(HtmlParseError(code, offset, line, col, detail));
  }

  (int, int) _position(int offset) {
    final starts = _lineStarts ??= [
      0,
      for (var i = 0; i < source.length; i++)
        if (source.codeUnitAt(i) == 0x0a) i + 1,
    ];
    var lo = 0, hi = starts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (starts[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return (lo + 1, offset - starts[lo] + 1);
  }

  void _countNode() {
    if (++_nodes > limits.maxNodes) {
      throw HtmlLimitException('document exceeds ${limits.maxNodes} nodes');
    }
  }

  void run() {
    if (source.length > limits.maxInputLength) {
      throw HtmlLimitException(
          'input of ${source.length} characters exceeds ${limits.maxInputLength}');
    }
    if (fragment) {
      fragmentRoot = doc.createElement('template');
      _stack.add(fragmentRoot);
    } else {
      html = doc.createElement('html');
      head = doc.createElement('head');
      body = doc.createElement('body');
      html.appendParsed(head);
      html.appendParsed(body);
      _nodes = 3;
      _stack.add(html);
      _stack.add(head);
    }
    final tokenizer = HtmlTokenizer(source, onError: _error);
    for (final token in tokenizer.tokenize()) {
      switch (token) {
        case StartTagToken t:
          _startTag(t);
        case EndTagToken t:
          _endTag(t);
        case TextToken t:
          _text(t);
        case CommentToken t:
          _countNode();
          _current.appendParsed(doc.createComment(t.data));
        case DoctypeToken t:
          if (t.name != 'html') _error('unsupported-doctype', t.offset, t.name);
      }
    }
  }

  void _enterBody() {
    if (fragment || _bodyStarted) return;
    _bodyStarted = true;
    // Close everything (head) and continue in body.
    _stack
      ..clear()
      ..add(html)
      ..add(body);
  }

  void _text(TextToken t) {
    var data = t.data;
    if (!fragment && !_bodyStarted && identical(_current, head)) {
      // Whitespace between head elements is dropped; other text starts body.
      if (data.trim().isEmpty) return;
      final firstNonWs = data.length - data.trimLeft().length;
      data = data.substring(firstNonWs);
      _enterBody();
    }
    final last = _current.lastChild;
    if (last is Text) {
      last.data = last.data + data;
      return;
    }
    _countNode();
    _current.appendParsed(doc.createTextNode(data));
  }

  void _startTag(StartTagToken t) {
    final name = t.name;
    if (!fragment) {
      if (name == 'html') {
        if (_sawHtmlTag) _error('duplicate-html-tag', t.offset);
        _sawHtmlTag = true;
        _mergeAttributes(html, t);
        return;
      }
      if (name == 'head') {
        if (_bodyStarted) _error('head-after-body', t.offset);
        _mergeAttributes(head, t);
        return;
      }
      if (name == 'body') {
        if (_bodyStarted) _error('duplicate-body-tag', t.offset);
        _enterBody();
        _mergeAttributes(body, t);
        return;
      }
      if (!_bodyStarted && !_headElements.contains(name)) _enterBody();
    } else if (name == 'html' || name == 'head' || name == 'body') {
      _error('unexpected-start-tag-in-fragment', t.offset, name);
      return;
    }

    if (_closesP.contains(name)) _closeIfOpen('p', t);
    if (name == 'li') _closeInListScope(const {'li'}, t);
    if (name == 'dd' || name == 'dt') _closeInListScope(const {'dd', 'dt'}, t);
    if (name == 'option') _closeIfCurrent('option');
    if (name.length == 2 && name[0] == 'h' && '123456'.contains(name[1])) {
      final cur = _current.localName;
      if (cur.length == 2 && cur[0] == 'h' && '123456'.contains(cur[1])) {
        _error('nested-heading', t.offset);
        _stack.removeLast();
      }
    }

    _countNode();
    final el = doc.createElement(name);
    for (final (k, v) in t.attributes) {
      try {
        el.setParsedAttribute(k, v);
      } on DomException {
        _error('invalid-attribute-name', t.offset, k);
      }
    }
    _current.appendParsed(el);

    final isVoid = voidElements.contains(name);
    if (t.selfClosing && !isVoid) {
      // HTML ignores "/>" on non-void elements; the element stays open.
      _error('non-void-html-element-start-tag-with-trailing-solidus', t.offset, name);
    }
    if (isVoid) return;
    if (_stack.length >= limits.maxDepth) {
      _error('nesting-too-deep', t.offset, name);
      return; // children of `el` become its siblings
    }
    _stack.add(el);
  }

  void _endTag(EndTagToken t) {
    final name = t.name;
    if (!fragment) {
      if (name == 'head') {
        if (!_bodyStarted && identical(_current, head)) return;
        _error('unexpected-end-tag', t.offset, name);
        return;
      }
      if (name == 'body' || name == 'html') {
        // Content after </body> still goes into body, as in HTML.
        return;
      }
    }
    if (name == 'br') {
      _error('end-tag-br', t.offset);
      _startTag(StartTagToken(t.offset, 'br', const []));
      return;
    }
    if (voidElements.contains(name)) {
      _error('end-tag-for-void-element', t.offset, name);
      return;
    }
    for (var i = _stack.length - 1; i >= (fragment ? 1 : 2); i--) {
      if (_stack[i].localName == name) {
        if (i != _stack.length - 1) {
          _error('unclosed-elements', t.offset,
              _stack.sublist(i + 1).map((e) => e.localName).join(','));
        }
        _stack.removeRange(i, _stack.length);
        return;
      }
    }
    if (name == 'p') {
      // "</p>" without an open <p> inserts an empty paragraph.
      _error('end-tag-p-without-open-p', t.offset);
      _countNode();
      _current.appendParsed(doc.createElement('p'));
      return;
    }
    _error('unexpected-end-tag', t.offset, name);
  }

  void _mergeAttributes(Element target, StartTagToken t) {
    for (final (k, v) in t.attributes) {
      target.setParsedAttribute(k, v);
    }
  }

  void _closeIfOpen(String name, StartTagToken t) {
    for (var i = _stack.length - 1; i >= 1; i--) {
      final n = _stack[i].localName;
      if (n == name) {
        _stack.removeRange(i, _stack.length);
        return;
      }
      // Do not close a <p> across these boundaries.
      if (n == 'button' || n == 'td' || n == 'th' || n == 'li' && name != 'li') {
        return;
      }
    }
  }

  void _closeInListScope(Set<String> names, StartTagToken t) {
    for (var i = _stack.length - 1; i >= 1; i--) {
      final n = _stack[i].localName;
      if (names.contains(n)) {
        _stack.removeRange(i, _stack.length);
        return;
      }
      if (_listScopes.contains(n)) return;
    }
  }

  void _closeIfCurrent(String name) {
    if (_current.localName == name) _stack.removeLast();
  }
}
