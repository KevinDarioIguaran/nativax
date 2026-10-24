import 'dart:collection';

import 'document.dart';
import 'element.dart';
import 'events.dart';
import 'exceptions.dart';
import 'mutation.dart';

enum NodeType {
  element(1),
  text(3),
  processingInstruction(7),
  comment(8),
  document(9),
  doctype(10),
  documentFragment(11);

  const NodeType(this.code);

  /// The numeric `nodeType` exposed to scripts.
  final int code;
}

/// Base of the NativaX document tree.
///
/// Tree mutations go through [insertBefore], [appendChild], [removeChild] and
/// [replaceChild], which enforce hierarchy rules and document limits and emit
/// [MutationRecord]s through the owner [Document].
abstract class Node extends EventTarget {
  Node(this._ownerDocument);

  Document? _ownerDocument;
  Node? _parent;
  final List<Node> _children = [];

  NodeType get nodeType;
  String get nodeName;

  /// The document that created this node. For a [Document] this is itself.
  Document get ownerDocument => _ownerDocument ?? (this as Document);

  Node? get parentNode => _parent;

  Element? get parentElement {
    final p = _parent;
    return p is Element ? p : null;
  }

  UnmodifiableListView<Node> get childNodes => UnmodifiableListView(_children);

  Iterable<Element> get children => _children.whereType<Element>();

  Node? get firstChild => _children.isEmpty ? null : _children.first;
  Node? get lastChild => _children.isEmpty ? null : _children.last;

  Node? get previousSibling {
    final p = _parent;
    if (p == null) return null;
    final i = p._children.indexOf(this);
    return i > 0 ? p._children[i - 1] : null;
  }

  Node? get nextSibling {
    final p = _parent;
    if (p == null) return null;
    final i = p._children.indexOf(this);
    return i + 1 < p._children.length ? p._children[i + 1] : null;
  }

  /// Index among the parent's child nodes, or -1 when detached.
  int get indexInParent => _parent?._children.indexOf(this) ?? -1;

  /// Nearest following sibling element, skipping text and comment nodes.
  Element? get nextElementSibling {
    for (var n = nextSibling; n != null; n = n.nextSibling) {
      if (n is Element) return n;
    }
    return null;
  }

  /// Nearest preceding sibling element, skipping text and comment nodes.
  Element? get previousElementSibling {
    for (var n = previousSibling; n != null; n = n.previousSibling) {
      if (n is Element) return n;
    }
    return null;
  }

  bool get isConnected {
    Node n = this;
    while (n._parent != null) {
      n = n._parent!;
    }
    return n is Document;
  }

  bool contains(Node? other) {
    for (Node? n = other; n != null; n = n._parent) {
      if (identical(n, this)) return true;
    }
    return false;
  }

  /// Concatenated text of all descendant text nodes.
  String get textContent {
    final buf = StringBuffer();
    void walk(Node n) {
      for (final c in n._children) {
        if (c is Text) {
          buf.write(c.data);
        } else if (c is Element) {
          walk(c);
        }
      }
    }

    walk(this);
    return buf.toString();
  }

  /// Replaces all children with a single text node (none when empty).
  set textContent(String value) {
    final old = List<Node>.of(_children);
    final incoming = <Node>[
      if (value.isNotEmpty) ownerDocument.createTextNode(value),
    ];
    for (final n in old) {
      n._parent = null;
      ownerDocument.onDetached(this, n);
    }
    _children.clear();
    for (final n in incoming) {
      _children.add(n);
      n._parent = this;
      n._adopt(ownerDocument);
      ownerDocument.onAttached(this, n);
    }
    if (old.isNotEmpty || incoming.isNotEmpty) {
      ownerDocument.notify(MutationRecord.childList(
        this,
        added: incoming,
        removed: old,
      ));
    }
  }

  // --- tree mutation -------------------------------------------------------

  Node appendChild(Node child) => insertBefore(child, null);

  Node insertBefore(Node child, Node? reference) {
    // Parent/ancestor checks precede the reference check; the child type
    // check comes after it (DOM insertBefore validation order).
    if (this is Text || this is Comment || this is ProcessingInstruction ||
        this is DocumentType) {
      throw DomException('HierarchyRequestError', '$nodeName nodes cannot have children');
    }
    if (child.contains(this)) {
      throw DomException('HierarchyRequestError', 'the new child contains the parent');
    }
    if (reference != null && !identical(reference._parent, this)) {
      throw DomException('NotFoundError', 'reference node is not a child of this node');
    }
    _checkDocumentOrder(child, reference);
    _checkInsertable(child, reference);
    if (child is DocumentFragment) {
      final moved = List<Node>.of(child._children);
      if (moved.isEmpty) return child;
      if (identical(child, reference)) reference = child.nextSibling;
      ownerDocument.checkCanAttach(this, child);
      final index =
          reference == null ? _children.length : _children.indexOf(reference);
      for (final n in moved) {
        n._parent = null;
      }
      child._children.clear();
      if (moved.isNotEmpty) {
        ownerDocument.notify(MutationRecord.childList(child, removed: moved));
      }
      _children.insertAll(index, moved);
      for (final n in moved) {
        n._parent = this;
        n._adopt(ownerDocument);
        ownerDocument.onAttached(this, n);
      }
      ownerDocument.notify(MutationRecord.childList(
        this,
        added: moved,
        previousSibling: index > 0 ? _children[index - 1] : null,
        nextSibling: index + moved.length < _children.length
            ? _children[index + moved.length]
            : null,
      ));
      return child;
    }
    if (identical(child, reference)) reference = child.nextSibling;
    ownerDocument.checkCanAttach(this, child);
    child._parent?.removeChild(child);
    final index =
        reference == null ? _children.length : _children.indexOf(reference);
    _children.insert(index, child);
    child._parent = this;
    child._adopt(ownerDocument);
    ownerDocument.onAttached(this, child);
    ownerDocument.notify(MutationRecord.childList(
      this,
      added: [child],
      previousSibling: index > 0 ? _children[index - 1] : null,
      nextSibling: index + 1 < _children.length ? _children[index + 1] : null,
    ));
    return child;
  }

  Node removeChild(Node child) {
    if (!identical(child._parent, this)) {
      throw DomException('NotFoundError', 'node is not a child of this node');
    }
    final index = _children.indexOf(child);
    _children.removeAt(index);
    child._parent = null;
    ownerDocument.onDetached(this, child);
    ownerDocument.notify(MutationRecord.childList(
      this,
      removed: [child],
      previousSibling: index > 0 ? _children[index - 1] : null,
      nextSibling: index < _children.length ? _children[index] : null,
    ));
    return child;
  }

  Node replaceChild(Node newChild, Node oldChild) {
    if (this is Text || this is Comment || this is ProcessingInstruction ||
        this is DocumentType) {
      throw DomException('HierarchyRequestError', '$nodeName nodes cannot have children');
    }
    if (newChild.contains(this)) {
      throw DomException('HierarchyRequestError', 'the new child contains the parent');
    }
    if (!identical(oldChild._parent, this)) {
      throw DomException('NotFoundError', 'node is not a child of this node');
    }
    if (identical(newChild, oldChild)) return oldChild;
    _checkDocumentOrder(newChild, oldChild);
    _checkInsertable(newChild, oldChild, replacing: oldChild);
    if (newChild is DocumentFragment) {
      final moved = List<Node>.of(newChild.rawChildren);
      newChild._children.clear();
      final index = _children.indexOf(oldChild);
      oldChild._parent = null;
      ownerDocument.onDetached(this, oldChild);
      _children.removeAt(index);
      for (final n in moved) {
        n._parent = null;
      }
      _children.insertAll(index, moved);
      for (final n in moved) {
        n._parent = this;
        n._adopt(ownerDocument);
        ownerDocument.onAttached(this, n);
      }
      ownerDocument.notify(MutationRecord.childList(
        this,
        added: moved,
        removed: [oldChild],
        previousSibling: index > 0 ? _children[index - 1] : null,
        nextSibling: index + moved.length < _children.length
            ? _children[index + moved.length]
            : null,
      ));
      return oldChild;
    }
    newChild._parent?.removeChild(newChild);
    final index = _children.indexOf(oldChild);
    final prev = index > 0 ? _children[index - 1] : null;
    final next = index + 1 < _children.length ? _children[index + 1] : null;
    oldChild._parent = null;
    ownerDocument.onDetached(this, oldChild);
    _children.removeAt(index);
    final at = prev == null ? 0 : _children.indexOf(prev) + 1;
    _children.insert(at, newChild);
    newChild._parent = this;
    newChild._adopt(ownerDocument);
    ownerDocument.onAttached(this, newChild);
    ownerDocument.notify(MutationRecord.childList(
      this,
      added: [newChild],
      removed: [oldChild],
      previousSibling: prev,
      nextSibling: next,
    ));
    return oldChild;
  }

  void replaceChildren(Iterable<Node> nodes) {
    final incoming = <Node>[];
    for (final n in nodes) {
      if (n is DocumentFragment) {
        incoming.addAll(n.rawChildren);
      } else {
        incoming.add(n);
      }
    }
    final old = List<Node>.of(_children);
    for (final n in old) {
      n._parent = null;
      ownerDocument.onDetached(this, n);
    }
    _children.clear();
    for (final n in incoming) {
      if (n._parent != null) n._parent!.removeChild(n);
      _checkInsertable(n, null);
      _children.add(n);
      n._parent = this;
      n._adopt(ownerDocument);
      ownerDocument.onAttached(this, n);
    }
    if (old.isNotEmpty || incoming.isNotEmpty) {
      ownerDocument.notify(MutationRecord.childList(
        this,
        added: incoming,
        removed: old,
      ));
    }
  }

  void remove() => _parent?.removeChild(this);

  void _checkDocumentOrder(Node child, Node? reference) {
    if (this is! Document) return;
    final refIndex = reference == null ? _children.length : _children.indexOf(reference);
    final elementIndex = _children.indexWhere((n) => n is Element);
    final doctypeIndex = _children.indexWhere((n) => n is DocumentType);
    final incomingElement = child is Element ||
        (child is DocumentFragment && child.children.isNotEmpty);
    final incomingDoctype = child is DocumentType ||
        (child is DocumentFragment &&
            child.rawChildren.whereType<DocumentType>().isNotEmpty);
    if (incomingElement && doctypeIndex >= 0 && refIndex <= doctypeIndex) {
      throw DomException('HierarchyRequestError',
          'a document element must follow the doctype');
    }
    if (incomingDoctype && elementIndex >= 0 && refIndex > elementIndex) {
      throw DomException('HierarchyRequestError',
          'a doctype must precede the document element');
    }
  }

  void _checkInsertable(Node child, Node? reference, {Node? replacing}) {
    if (child is Document) {
      throw DomException('HierarchyRequestError', 'cannot insert a document');
    }
    if (this is Text || this is Comment || this is ProcessingInstruction) {
      throw DomException(
          'HierarchyRequestError', '$nodeName nodes cannot have children');
    }
    if (this is Document && child is Text) {
      throw DomException(
          'HierarchyRequestError', 'a document cannot contain text nodes');
    }
    if (this is Document && child is DocumentFragment &&
        child.rawChildren.any((c) => c is Text)) {
      throw DomException(
          'HierarchyRequestError', 'a document cannot contain text nodes');
    }
    if (this is DocumentType) {
      throw DomException(
          'HierarchyRequestError', 'a doctype cannot have children');
    }
    if (child is DocumentType && this is! Document) {
      throw DomException(
          'HierarchyRequestError', 'a doctype can only be a document child');
    }
    if (this is Document) {
      var incomingElements = 0;
      var incomingDoctypes = 0;
      if (child is Element) {
        incomingElements = 1;
      } else if (child is DocumentFragment) {
        incomingElements = child.children.length;
        incomingDoctypes = child.rawChildren.whereType<DocumentType>().length;
      } else if (child is DocumentType) {
        incomingDoctypes = 1;
      }
      final elements = children
          .where((c) => !identical(c, child) && !identical(c, replacing))
          .length;
      final doctypes = rawChildren
          .whereType<DocumentType>()
          .where((d) => !identical(d, child) && !identical(d, replacing))
          .length;
      if (elements + incomingElements > 1) {
        throw DomException(
            'HierarchyRequestError', 'a document can only have one element child');
      }
      if (doctypes + incomingDoctypes > 1) {
        throw DomException(
            'HierarchyRequestError', 'a document can only have one doctype');
      }
      if (child is DocumentType && replacing == null &&
          children.isNotEmpty) {
        throw DomException(
            'HierarchyRequestError', 'a doctype must precede the document element');
      }
    }
    if (child.contains(this)) {
      throw DomException(
          'HierarchyRequestError', 'the new child contains the parent');
    }
    if (reference != null && !identical(reference._parent, this)) {
      throw DomException(
          'NotFoundError', 'reference node is not a child of this node');
    }
  }

  /// Updates this subtree's node document after insertion into another
  /// document, or after [Document.adoptNode].
  void adoptDocument(Document doc) {
    _ownerDocument = doc;
    for (final c in _children) {
      c.adoptDocument(doc);
    }
  }

  void _adopt(Document doc) => adoptDocument(doc);

  /// Deep or shallow copy owned by the same document. Listeners are not
  /// copied, matching the DOM.
  Node cloneNode({bool deep = false});

  /// Pre-order traversal of descendants (excluding this node).
  Iterable<Node> get descendants sync* {
    for (final c in _children) {
      yield c;
      yield* c.descendants;
    }
  }

  @override
  EventTarget? get parentEventTarget => _parent;

  static const _activationEvents = {
    'click', 'keydown', 'keyup', 'mousedown', 'mouseup', 'pointerdown', 'pointerup', 'touchend', 'contextmenu',
  };

  @override
  void willDispatch(Event event) {
    if (event.isTrusted && _activationEvents.contains(event.type)) {
      ownerDocument.lastUserActivation = DateTime.now();
    }
  }

  @override
  ListenerErrorHandler? get listenerErrorHandler =>
      ownerDocument.onListenerError;

  /// Appends a child without mutation records or limit checks. Only for
  /// parsers building a fresh, detached tree; see [Document.adoptParsed].
  void appendParsed(Node child) {
    _children.add(child);
    child._parent = this;
  }
}

/// Internal accessors shared with other files of this library.
extension NodeInternals on Node {
  List<Node> get rawChildren => _children;
}

class Text extends Node {
  Text(Document doc, this._data) : super(doc);

  String _data;

  String get data => _data;
  set data(String value) {
    final old = _data;
    _data = value;
    ownerDocument.notify(MutationRecord.characterData(this, old));
  }

  @override
  NodeType get nodeType => NodeType.text;

  @override
  String get nodeName => '#text';

  @override
  String get textContent => _data;

  @override
  set textContent(String value) => data = value;

  /// Concatenated data of adjacent [Text] siblings (including this node).
  String get wholeText {
    final buf = StringBuffer();
    Node first = this;
    while (first.previousSibling is Text) {
      first = first.previousSibling!;
    }
    for (Node? n = first; n is Text; n = n.nextSibling) {
      buf.write(n.data);
    }
    return buf.toString();
  }

  /// Splits this node at [offset], returning the new text node inserted after
  /// it. Mutates this node's data and the tree like the DOM.
  Text splitText(int offset) {
    if (offset < 0 || offset > _data.length) {
      throw DomException('IndexSizeError', 'offset out of range');
    }
    final rest = _data.substring(offset);
    data = _data.substring(0, offset);
    final tail = Text(ownerDocument, rest);
    final parent = _parent;
    if (parent != null) {
      parent.insertBefore(tail, nextSibling);
    }
    return tail;
  }

  @override
  Text cloneNode({bool deep = false}) => Text(ownerDocument, _data);
}

class Comment extends Node {
  Comment(Document doc, this._data) : super(doc);

  String _data;

  String get data => _data;
  set data(String value) {
    final old = _data;
    _data = value;
    ownerDocument.notify(MutationRecord.characterData(this, old));
  }

  @override
  NodeType get nodeType => NodeType.comment;

  @override
  String get nodeName => '#comment';

  @override
  String get textContent => _data;

  @override
  set textContent(String value) => data = value;

  @override
  Comment cloneNode({bool deep = false}) => Comment(ownerDocument, _data);
}

/// An XML processing instruction (`<?target data?>`).
class ProcessingInstruction extends Node {
  ProcessingInstruction(Document doc, this.target, this._data) : super(doc);

  final String target;
  String _data;

  String get data => _data;
  set data(String value) {
    final old = _data;
    _data = value;
    ownerDocument.notify(MutationRecord.characterData(this, old));
  }

  @override
  NodeType get nodeType => NodeType.processingInstruction;

  @override
  String get nodeName => target;

  @override
  String get textContent => _data;

  @override
  set textContent(String value) => data = value;

  @override
  ProcessingInstruction cloneNode({bool deep = false}) =>
      ProcessingInstruction(ownerDocument, target, data);
}

/// A `<!DOCTYPE ...>` node. NativaX keeps it outside the element tree.
class DocumentType extends Node {
  DocumentType(Document doc, this.name, {this.publicId = '', this.systemId = ''})
      : super(doc);

  final String name;
  final String publicId;
  final String systemId;

  @override
  NodeType get nodeType => NodeType.doctype;

  @override
  String get nodeName => name;

  @override
  String get textContent => '';

  @override
  set textContent(String value) {}

  @override
  DocumentType cloneNode({bool deep = false}) =>
      DocumentType(ownerDocument, name, publicId: publicId, systemId: systemId);
}

class DocumentFragment extends Node {
  DocumentFragment(Document super.doc);

  @override
  NodeType get nodeType => NodeType.documentFragment;

  @override
  String get nodeName => '#document-fragment';

  @override
  DocumentFragment cloneNode({bool deep = false}) {
    final copy = DocumentFragment(ownerDocument);
    if (deep) {
      for (final c in rawChildren) {
        copy.appendParsed(c.cloneNode(deep: true));
      }
    }
    return copy;
  }
}
