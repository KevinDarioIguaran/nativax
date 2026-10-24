import 'package:html/dom.dart' as html5;
import 'package:html/parser.dart' as html5_parser;
import 'package:nativa_dom/nativa_dom.dart';

import 'parser_error.dart';
import 'token.dart';
import 'tokenizer.dart';

/// Elements allowed in `<head>` before `<body>` starts.
const Set<String> _headElements = {
  'title', 'meta', 'link', 'style', 'script', 'base', 'noscript', 'template', //
};

/// Start tags that implicitly close an open `<p>`.
const Set<String> _closesP = {
  'address', 'article', 'aside', 'blockquote', 'center', 'details', 'dialog',
  'dir', 'div', 'dl', 'fieldset', 'figcaption', 'figure', 'footer', 'form',
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'header', 'hgroup', 'hr', 'listing',
  'main', 'menu', 'nav', 'ol', 'p', 'plaintext', 'pre', 'search', 'section',
  'summary', 'table', 'ul', //
};

/// Elements that bound the search for an implicitly closed `li`, `dd`, `dt`
/// or `option`.
const Set<String> _listScopes = {
  'ul',
  'ol',
  'menu',
  'dl',
  'select',
  'datalist',
};

/// Formatting elements tracked by the (simplified) adoption agency.
const Set<String> _formattingTags = {
  'a',
  'b',
  'big',
  'code',
  'em',
  'font',
  'i',
  'nobr',
  's',
  'small',
  'strike',
  'strong',
  'tt',
  'u',
};

/// Elements that can be the "furthest block" in the adoption agency.
const Set<String> _specialElements = {
  'address', 'applet', 'area', 'article', 'aside', 'base', 'basefont',
  'bgsound', 'blockquote', 'body', 'br', 'button', 'caption', 'center', 'col',
  'colgroup', 'dd', 'details', 'dir', 'div', 'dl', 'dt', 'embed', 'fieldset',
  'figcaption', 'figure', 'footer', 'form', 'frame', 'frameset', 'h1', 'h2',
  'h3', 'h4', 'h5', 'h6', 'head', 'header', 'hgroup', 'hr', 'html', 'iframe',
  'img', 'input', 'keygen', 'li', 'link', 'listing', 'main', 'marquee', 'menu',
  'meta', 'nav', 'noembed', 'noframes', 'noscript', 'object', 'ol', 'p',
  'param', 'plaintext', 'pre', 'script', 'section', 'select', 'source', 'style',
  'summary', 'table', 'tbody', 'td', 'template', 'textarea', 'tfoot', 'th',
  'thead', 'title', 'tr', 'ul', 'wbr', 'xmp',
};

bool _isSpecial(Element e) => _specialElements.contains(e.localName);

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
/// `template` contents or quirks mode. Foreign content (SVG/MathML) honors
/// self-closing tags and HTML breakout tags. See
/// docs/html-supported.md.
class HtmlParser {
  HtmlParser({this.limits = const HtmlParserLimits()});

  final HtmlParserLimits limits;

  HtmlParseResult<Document> parseDocument(
    String source, {
    DocumentLimits documentLimits = const DocumentLimits(),
  }) {
    final errorDoc = Document(limits: documentLimits);
    final builder = _TreeBuilder(errorDoc, source, limits, fragment: false);
    builder.run();
    if (limits.maxDepth != const HtmlParserLimits().maxDepth) {
      errorDoc.adoptParsed([...builder.topLevel, builder.html]);
      return HtmlParseResult(errorDoc, builder.errors, builder.dropped);
    }
    final parsed = html5_parser.parse(source);
    final doc = _convertHtml5Document(parsed, documentLimits, limits);
    return HtmlParseResult(doc, builder.errors, builder.dropped);
  }

  /// Parses [source] as the children of [context] (used by `innerHTML`).
  /// No implicit `html`/`head`/`body` are created. The returned fragment is
  /// owned by [context]'s document.
  HtmlParseResult<DocumentFragment> parseFragment(
    String source,
    Element context,
  ) {
    final doc = context.ownerDocument;
    final errorBuilder = _TreeBuilder(doc, source, limits, fragment: true);
    errorBuilder.run();
    if (limits.maxDepth != const HtmlParserLimits().maxDepth) {
      final fragment = doc.createDocumentFragment();
      for (final n in List.of(errorBuilder.fragmentRoot.childNodes)) {
        fragment.appendParsed(n);
      }
      return HtmlParseResult(fragment, errorBuilder.errors, errorBuilder.dropped);
    }
    final parsed = html5_parser.parseFragment(source,
        container: context.localName.isEmpty ? 'div' : context.localName);
    final fragment = doc.createDocumentFragment();
    var nodes = 0;
    void add(html5.Node n, Node parent) {
      if (++nodes > limits.maxNodes) {
        throw HtmlLimitException('document exceeds ${limits.maxNodes} nodes');
      }
      if (n is html5.Text) {
        parent.appendChild(doc.createTextNode(n.data));
      } else if (n is html5.Comment) {
        parent.appendChild(doc.createComment(n.data ?? ''));
      } else if (n is html5.Element) {
        final e = doc.createElement(n.localName ?? '');
        _copyHtml5Attributes(n, e);
        parent.appendChild(e);
        for (final c in n.nodes) {
          add(c, e);
        }
      } else if (n is html5.DocumentType) {
        parent.appendChild(doc.createDocumentType(
          n.name ?? '',
          n.publicId ?? '',
          n.systemId ?? '',
        ));
      } else {
        for (final c in n.nodes) {
          add(c, parent);
        }
      }
    }
    for (final n in parsed.nodes) {
      add(n, fragment);
    }
    return HtmlParseResult(fragment, errorBuilder.errors, errorBuilder.dropped);
  }
}

void _copyHtml5Attributes(html5.Element source, Element target) {
  for (final entry in source.attributes.entries) {
    final name = entry.key is html5.AttributeName
        ? (entry.key as html5.AttributeName).toString()
        : entry.key.toString();
    target.setParsedAttribute(name, entry.value);
  }
}

Document _convertHtml5Document(
  html5.Document source,
  DocumentLimits documentLimits,
  HtmlParserLimits limits,
) {
  final doc = Document(limits: documentLimits);
  var nodes = 0;
  void add(html5.Node n, Node parent) {
    if (++nodes > limits.maxNodes) {
      throw HtmlLimitException('document exceeds ${limits.maxNodes} nodes');
    }
    if (n is html5.Element) {
      final e = doc.createElement(n.localName ?? '');
      _copyHtml5Attributes(n, e);
      parent.appendChild(e);
      for (final c in n.nodes) {
        add(c, e);
      }
    } else if (n is html5.Text) {
      parent.appendChild(doc.createTextNode(n.data));
    } else if (n is html5.Comment) {
      parent.appendChild(doc.createComment(n.data ?? ''));
    } else if (n is html5.DocumentType) {
      parent.appendChild(doc.createDocumentType(
        n.name ?? '',
        n.publicId ?? '',
        n.systemId ?? '',
      ));
    } else {
      for (final c in n.nodes) {
        add(c, parent);
      }
    }
  }
  for (final n in source.nodes) {
    add(n, doc);
  }
  return doc;
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

  DocumentType? doctype;
  final List<Node> topLevel = [];
  bool _beforeFirstStart = true;
  late final Element html;
  late final Element head;
  late final Element body;
  late final Element fragmentRoot;
  bool _bodyStarted = false;
  bool _sawHtmlTag = false;

  /// Open elements; [0] is the root of insertion.
  final List<Element> _stack = [];

  /// Active formatting elements in insertion order. `null` is a scope marker.
  final List<Element?> _formatting = [];

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
        'input of ${source.length} characters exceeds ${limits.maxInputLength}',
      );
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
          _beforeFirstStart = false;
          _startTag(t);
        case EndTagToken t:
          _endTag(t);
        case TextToken t:
          _text(t);
        case CommentToken t:
          _countNode();
          if (!fragment && _beforeFirstStart) {
            topLevel.add(doc.createComment(t.data));
          } else {
            _current.appendParsed(doc.createComment(t.data));
          }
        case DoctypeToken t:
          if (!fragment && doctype == null) {
            _countNode();
            doctype = DocumentType(
              doc,
              t.name,
              publicId: t.publicId,
              systemId: t.systemId,
            );
            topLevel.add(doctype!);
          } else {
            _error('unexpected-doctype', t.offset, t.name);
          }
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
    if (!fragment && data.trim().isNotEmpty) _beforeFirstStart = false;
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
      if (!_bodyStarted &&
          !_headElements.contains(name) &&
          !_stack.any((e) => e.localName == 'template')) {
        _enterBody();
      }
    } else if (name == 'html' || name == 'head' || name == 'body') {
      _error('unexpected-start-tag-in-fragment', t.offset, name);
      return;
    }

    // Foreign content (SVG/MathML): no HTML implicit rules, `/>` closes the
    // element, and HTML "breakout" tags close the foreign subtree first.
    if (_inForeign) {
      if (_breakout.contains(name) ||
          (name == 'font' &&
              t.attributes.any(
                (a) => const {'color', 'face', 'size'}.contains(a.$1),
              ))) {
        _error('html-start-tag-in-foreign-content', t.offset, name);
        while (_inForeign && _stack.length > (fragment ? 1 : 2)) {
          _stack.removeLast();
        }
      } else {
        _countNode();
        final el = Element(doc, name);
        for (final (k, v) in t.attributes) {
          try {
            el.setParsedAttribute(k, v);
          } on DomException {
            _error('invalid-attribute-name', t.offset, k);
          }
        }
        _current.appendParsed(el);
        if (t.selfClosing) return;
        if (_stack.length >= limits.maxDepth) {
          _error('nesting-too-deep', t.offset, name);
          return;
        }
        _stack.add(el);
        return;
      }
    }

    if (name == 'a' && _formatting.any((e) => e != null && e.localName == 'a')) {
      // A new <a> closes the previous active formatting <a>.
      _error('nested-a', t.offset);
      _closeFormatting(EndTagToken(t.offset, 'a'));
    }
    if (name == 'form' &&
        !_stack.any((e) => e.localName == 'template') &&
        _stack.any((e) => e.localName == 'form')) {
      _error('nested-form', t.offset);
      return;
    }
    if (!fragment && name == 'frame') {
      // <frame> is only valid in a frameset; in body it is ignored.
      _error('unexpected-start-tag', t.offset, name);
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

    _tableContext(name, t);
    _countNode();
    final el = Element(doc, name);
    for (final (k, v) in t.attributes) {
      try {
        el.setParsedAttribute(k, v);
      } on DomException {
        _error('invalid-attribute-name', t.offset, k);
      }
    }
    _current.appendParsed(el);

    final isVoid = voidElements.contains(name);
    if (t.selfClosing && (name == 'svg' || name == 'math')) return;
    if (t.selfClosing && !isVoid) {
      // HTML ignores "/>" on non-void elements; the element stays open.
      _error(
        'non-void-html-element-start-tag-with-trailing-solidus',
        t.offset,
        name,
      );
    }
    if (isVoid) return;
    if (_stack.length >= limits.maxDepth) {
      _error('nesting-too-deep', t.offset, name);
      return; // children of `el` become its siblings
    }
    _stack.add(el);
    if (_formattingTags.contains(name)) _formatting.add(el);
  }

  /// Whether the insertion point is inside `<svg>`/`<math>` and not inside an
  /// HTML integration point (`foreignObject`, `desc`, `title`,
  /// `annotation-xml`).
  bool get _inForeign {
    for (var i = _stack.length - 1; i >= 0; i--) {
      final n = _stack[i].localName;
      if (n == 'foreignobject' || n == 'annotation-xml') return false;
      if ((n == 'desc' || n == 'title') && i > 0 && _stackHasSvgBelow(i))
        return false;
      if (n == 'svg' || n == 'math') return true;
    }
    return false;
  }

  bool _stackHasSvgBelow(int index) {
    for (var i = index - 1; i >= 0; i--) {
      if (_stack[i].localName == 'svg') return true;
    }
    return false;
  }

  static const _breakout = {
    'b',
    'big',
    'blockquote',
    'body',
    'br',
    'center',
    'code',
    'dd',
    'div',
    'dl',
    'dt',
    'em',
    'embed',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'head',
    'hr',
    'i',
    'img',
    'li',
    'listing',
    'menu',
    'meta',
    'nobr',
    'ol',
    'p',
    'pre',
    'ruby',
    's',
    'small',
    'span',
    'strong',
    'strike',
    'sub',
    'sup',
    'table',
    'tt',
    'u',
    'ul',
    'var',
  };

  void _endTag(EndTagToken t) {
    final name = t.name;
    if (_inForeign) {
      for (var i = _stack.length - 1; i >= (fragment ? 1 : 2); i--) {
        if (_stack[i].localName == name) {
          _stack.removeRange(i, _stack.length);
          return;
        }
        if (_stack[i].localName == 'svg' || _stack[i].localName == 'math')
          break;
      }
      if (name != 'br' && name != 'p') {
        _error('unexpected-end-tag-in-foreign-content', t.offset, name);
        return;
      }
    }
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
    if (name == 'form' && !fragment) {
      // The form element is removed from the stack without closing its
      // descendants; a following block stays inside the open child.
      final index = _stack.lastIndexWhere((e) => e.localName == 'form');
      if (index >= 0) {
        _stack.removeAt(index);
        return;
      }
    }
    if (name == 'p' && !_bodyStarted && !fragment) {
      // A stray </p> before the body cannot create a paragraph in <head>.
      _error('end-tag-p-before-body', t.offset);
      return;
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
    if (_formattingTags.contains(name)) {
      _closeFormatting(t);
      return;
    }
    for (var i = _stack.length - 1; i >= (fragment ? 1 : 2); i--) {
      if (_stack[i].localName == name) {
        if (i != _stack.length - 1) {
          _error(
            'unclosed-elements',
            t.offset,
            _stack.sublist(i + 1).map((e) => e.localName).join(','),
          );
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

  /// Adoption agency algorithm (WHATWG), adapted to the simplified tree
  /// builder. Misnested formatting elements are cloned into the current block
  /// instead of remaining as ancestors.
  void _closeFormatting(EndTagToken t) {
    final subject = t.name;
    var outerLoopCounter = 0;
    while (outerLoopCounter < 8) {
      outerLoopCounter++;

      var feIndex = -1;
      for (var i = _formatting.length - 1; i >= 0; i--) {
        final e = _formatting[i];
        if (e == null) break;
        if (e.localName == subject) {
          feIndex = i;
          break;
        }
      }
      if (feIndex < 0) {
        _error('unexpected-end-tag', t.offset, subject);
        return;
      }
      final formattingElement = _formatting[feIndex]!;
      if (!_stack.contains(formattingElement)) {
        _formatting.removeAt(feIndex);
        continue;
      }
      if (!identical(_current, formattingElement)) {
        _error('adoption-agency-1.3', t.offset);
      }
      final feStackIndex = _stack.indexOf(formattingElement);
      Element? furthestBlock;
      for (var i = feStackIndex; i < _stack.length; i++) {
        if (_isSpecial(_stack[i])) furthestBlock = _stack[i];
      }
      if (furthestBlock == null) {
        while (true) {
          final el = _stack.removeLast();
          if (identical(el, formattingElement)) break;
        }
        _formatting.remove(formattingElement);
        return;
      }
      final commonAncestor = _stack[feStackIndex - 1];
      var bookmark = feIndex;
      Element? lastNode = furthestBlock;
      var nodeStackIndex = _stack.indexOf(furthestBlock);
      var inner = 0;
      while (inner < 3) {
        inner++;
        nodeStackIndex -= 1;
        if (nodeStackIndex <= feStackIndex) break;
        final node = _stack[nodeStackIndex];
        if (!_formatting.contains(node)) {
          _stack.removeAt(nodeStackIndex);
          continue;
        }
        if (identical(node, formattingElement)) break;
        if (identical(lastNode, furthestBlock)) {
          bookmark = _formatting.indexOf(node) + 1;
        }
        final clone = node.cloneNode(deep: false);
        final afIndex = _formatting.indexOf(node);
        if (afIndex >= 0) _formatting[afIndex] = clone;
        final nsIndex = _stack.indexOf(node);
        if (nsIndex >= 0) _stack[nsIndex] = clone;
        lastNode?.remove();
        clone.appendParsed(lastNode!);
        lastNode = clone;
      }

      // Foster-parent lastNode when the common ancestor is a table element.
      lastNode?.remove();
      if (const {'table', 'tbody', 'tfoot', 'thead', 'tr'}
          .contains(commonAncestor.localName)) {
        final parent = commonAncestor.parentNode;
        if (parent != null) {
          parent.insertBefore(lastNode!, commonAncestor);
        } else {
          commonAncestor.appendParsed(lastNode!);
        }
      } else {
        commonAncestor.appendParsed(lastNode!);
      }

      final feClone = formattingElement.cloneNode(deep: false);
      // Reparent all children of the furthest block into the clone.
      for (final c in List<Node>.of(furthestBlock.childNodes)) {
        c.remove();
        feClone.appendParsed(c);
      }
      furthestBlock.appendParsed(feClone);

      _formatting.remove(formattingElement);
      if (bookmark > _formatting.length) bookmark = _formatting.length;
      _formatting.insert(bookmark, feClone);

      final feIdx = _stack.indexOf(formattingElement);
      if (feIdx >= 0) _stack.removeAt(feIdx);
      final fIndex = _stack.indexOf(furthestBlock);
      final insertIndex = fIndex >= 0 ? fIndex + 1 : _stack.length;
      if (insertIndex > _stack.length) {
        _stack.add(feClone);
      } else {
        _stack.insert(insertIndex, feClone);
      }
      // Keep the furthest block as the current node for following content.
      while (_stack.isNotEmpty && !identical(_stack.last, furthestBlock)) {
        _stack.removeLast();
      }
      if (!_stack.contains(furthestBlock)) _stack.add(furthestBlock);
      return;
    }
  }

  /// Minimal table insertion modes: implicit tbody/tr and cell placement.
  void _tableContext(String name, StartTagToken t) {
    if (!{
      'tbody',
      'thead',
      'tfoot',
      'tr',
      'td',
      'th',
      'caption',
      'colgroup',
    }.contains(name)) {
      return;
    }
    final tableIndex = _stack.lastIndexWhere((e) => e.localName == 'table');
    if (tableIndex < 0) return;
    Element? section;
    Element? row;
    for (var i = tableIndex + 1; i < _stack.length; i++) {
      final n = _stack[i].localName;
      if (n == 'tbody' || n == 'thead' || n == 'tfoot') section = _stack[i];
      if (n == 'tr') row = _stack[i];
    }
    if (section == null && (name == 'tr' || name == 'td' || name == 'th')) {
      _stack.removeRange(tableIndex + 1, _stack.length);
      final el = doc.createElement('tbody');
      _current.appendParsed(el);
      _stack.add(el);
      section = el;
    }
    if (section != null && (name == 'td' || name == 'th')) {
      if (row == null) {
        _stack.removeRange(_stack.indexOf(section) + 1, _stack.length);
        final el = doc.createElement('tr');
        _current.appendParsed(el);
        _stack.add(el);
        row = el;
      } else {
        _stack.removeRange(_stack.indexOf(row) + 1, _stack.length);
      }
    }
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
      if (n == 'button' ||
          n == 'td' ||
          n == 'th' ||
          n == 'li' && name != 'li') {
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
