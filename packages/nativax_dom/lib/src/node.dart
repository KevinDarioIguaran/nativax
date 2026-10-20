import 'dart:collection';

import 'document.dart';
import 'element.dart';
import 'events.dart';
import 'exceptions.dart';
import 'mutation.dart';

enum NodeType {
  element(1),
  text(3),
  comment(8),
  document(9),
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
    replaceChildren([if (value.isNotEmpty) ownerDocument.createTextNode(value)]);
  }

  // --- tree mutation -------------------------------------------------------

  Node appendChild(Node child) => insertBefore(child, null);

  Node insertBefore(Node child, Node? reference) {
    _checkInsertable(child, reference);
    if (child is DocumentFragment) {
      final moved = List<Node>.of(child._children);
      for (final n in moved) {
        insertBefore(n, reference);
      }
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
    if (!identical(oldChild._parent, this)) {
      throw DomException('NotFoundError', 'node is not a child of this node');
    }
    if (identical(newChild, oldChild)) return oldChild;
    _checkInsertable(newChild, oldChild);
    final next = oldChild.nextSibling;
    removeChild(oldChild);
    insertBefore(newChild, identical(next, newChild) ? newChild.nextSibling : next);
    return oldChild;
  }

  void replaceChildren(Iterable<Node> nodes) {
    final incoming = List<Node>.of(nodes);
    for (final n in incoming) {
      _checkInsertable(n, null);
    }
    while (_children.isNotEmpty) {
      removeChild(_children.last);
    }
    for (final n in incoming) {
      appendChild(n);
    }
  }

  void remove() => _parent?.removeChild(this);

  void _checkInsertable(Node child, Node? reference) {
    if (child is Document) {
      throw DomException('HierarchyRequestError', 'cannot insert a document');
    }
    if (this is Text || this is Comment) {
      throw DomException(
          'HierarchyRequestError', '$nodeName nodes cannot have children');
    }
    if (child.contains(this)) {
      throw DomException(
          'HierarchyRequestError', 'the new child contains the parent');
    }
    if (reference != null && !identical(reference._parent, this)) {
      throw DomException(
          'NotFoundError', 'reference node is not a child of this node');
    }
    if (!identical(child.ownerDocument, ownerDocument)) {
      throw DomException('WrongDocumentError',
          'node belongs to another document; import it first');
    }
  }

  void _adopt(Document doc) {
    _ownerDocument = doc;
  }

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
    if (value == _data) return;
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

  @override
  Text cloneNode({bool deep = false}) => Text(ownerDocument, _data);
}

class Comment extends Node {
  Comment(Document doc, this.data) : super(doc);

  String data;

  @override
  NodeType get nodeType => NodeType.comment;

  @override
  String get nodeName => '#comment';

  @override
  String get textContent => data;

  @override
  set textContent(String value) => data = value;

  @override
  Comment cloneNode({bool deep = false}) => Comment(ownerDocument, data);
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
