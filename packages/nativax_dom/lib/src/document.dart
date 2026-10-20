import 'element.dart';
import 'events.dart';
import 'exceptions.dart';
import 'mutation.dart';
import 'node.dart';
import 'selectors.dart';

/// Resource limits for one document, enforced on every tree insertion.
class DocumentLimits {
  const DocumentLimits({this.maxNodes = 100000, this.maxDepth = 256});

  /// Maximum nodes connected to the document at once.
  final int maxNodes;

  /// Maximum nesting depth (the document node is depth 0). Bounds recursion in
  /// the style resolver and renderer.
  final int maxDepth;
}

class Document extends Node {
  Document({this.limits = const DocumentLimits()}) : super(null);

  final DocumentLimits limits;
  final List<MutationListener> _mutationListeners = [];
  int _connectedNodes = 1;
  Element? _activeElement;

  /// Receives exceptions thrown by event listeners during dispatch.
  ListenerErrorHandler? onListenerError;

  /// Where events go after the document while propagating (the window).
  EventTarget? eventParent;

  /// Called when a form is submitted and no listener prevented it. There is
  /// no navigation: the embedder decides what submission means.
  void Function(Element form)? onSubmit;

  /// Called when a link is activated. NativaX never navigates on its own.
  void Function(String href, Element anchor)? onNavigate;

  @override
  EventTarget? get parentEventTarget => eventParent;

  /// Called when script or Dart code requests focus changes (`el.focus()`),
  /// so a renderer can move real input focus.
  void Function(Element? element)? onFocusRequest;

  @override
  NodeType get nodeType => NodeType.document;

  @override
  String get nodeName => '#document';

  int get connectedNodeCount => _connectedNodes;

  Element? get documentElement => children.firstOrNull;

  Element? _childOfRoot(String name) {
    final root = documentElement;
    if (root == null) return null;
    for (final c in root.children) {
      if (c.localName == name) return c;
    }
    return null;
  }

  Element? get head => _childOfRoot('head');
  Element? get body => _childOfRoot('body');

  String get title =>
      querySelector('title')?.textContent.trim().replaceAll(RegExp(r'\s+'), ' ') ??
      '';

  // --- factories -----------------------------------------------------------

  Element createElement(String localName) {
    validateName(localName);
    return Element(this, localName);
  }

  Text createTextNode(String data) => Text(this, data);
  Comment createComment(String data) => Comment(this, data);
  DocumentFragment createDocumentFragment() => DocumentFragment(this);

  // --- queries -------------------------------------------------------------

  Element? getElementById(String id) {
    if (id.isEmpty) return null;
    for (final n in descendants) {
      if (n is Element && n.getAttribute('id') == id) return n;
    }
    return null;
  }

  Element? querySelector(String selectors) =>
      SelectorList.parse(selectors).first(this);

  List<Element> querySelectorAll(String selectors) =>
      SelectorList.parse(selectors).all(this);

  List<Element> getElementsByTagName(String name) =>
      documentElement == null
          ? const []
          : [
              if (name == '*' || documentElement!.localName == name.toLowerCase())
                documentElement!,
              ...documentElement!.getElementsByTagName(name),
            ];

  List<Element> getElementsByClassName(String names) =>
      documentElement == null
          ? const []
          : [
              if (names
                  .split(RegExp(r'\s+'))
                  .where((s) => s.isNotEmpty)
                  .every(documentElement!.classList.contains))
                documentElement!,
              ...documentElement!.getElementsByClassName(names),
            ];

  // --- focus ---------------------------------------------------------------

  Element? get activeElement => _activeElement ?? body;

  /// Records that [element] gained focus (called by the renderer) and fires
  /// `blur`/`focus` events.
  void setFocusedElement(Element? element) {
    if (identical(element, _activeElement)) return;
    final previous = _activeElement;
    _activeElement = element;
    previous?.dispatchEvent(Event('blur')..isTrusted = true);
    element?.dispatchEvent(Event('focus')..isTrusted = true);
  }

  void requestFocus(Element? element) => onFocusRequest?.call(element);

  // --- mutations -----------------------------------------------------------

  void addMutationListener(MutationListener listener) =>
      _mutationListeners.add(listener);

  void removeMutationListener(MutationListener listener) =>
      _mutationListeners.remove(listener);

  void notify(MutationRecord record) {
    for (final l in List.of(_mutationListeners)) {
      l(record);
    }
  }

  /// Throws `QuotaExceededError` when attaching [child] under [parent] would
  /// exceed [limits].
  void checkCanAttach(Node parent, Node child) {
    var depth = 0;
    for (Node? n = parent; n != null; n = n.parentNode) {
      depth++;
    }
    if (depth + _height(child) > limits.maxDepth + 1) {
      throw DomException('QuotaExceededError',
          'document depth would exceed ${limits.maxDepth}');
    }
    if (parent.isConnected && !child.isConnected) {
      final size = subtreeSize(child);
      if (_connectedNodes + size > limits.maxNodes) {
        throw DomException('QuotaExceededError',
            'document would exceed ${limits.maxNodes} nodes');
      }
    }
  }

  void onAttached(Node parent, Node child) {
    if (parent.isConnected) _connectedNodes += subtreeSize(child);
  }

  void onDetached(Node parent, Node child) {
    if (parent.isConnected) {
      _connectedNodes -= subtreeSize(child);
      final active = _activeElement;
      if (active != null && child.contains(active)) _activeElement = null;
    }
  }

  /// Attaches a parser-built tree as this document's children, validating
  /// limits once for the whole tree.
  void adoptParsed(List<Node> roots) {
    var size = 0;
    var height = 0;
    for (final r in roots) {
      size += subtreeSize(r);
      final h = _height(r);
      if (h > height) height = h;
    }
    if (height > limits.maxDepth) {
      throw DomException('QuotaExceededError',
          'document depth would exceed ${limits.maxDepth}');
    }
    if (_connectedNodes + size > limits.maxNodes) {
      throw DomException(
          'QuotaExceededError', 'document would exceed ${limits.maxNodes} nodes');
    }
    for (final r in roots) {
      appendParsed(r);
    }
    _connectedNodes += size;
  }

  @override
  Document cloneNode({bool deep = false}) =>
      throw DomException('NotSupportedError', 'documents cannot be cloned');

  /// Removes every listener in the tree and detaches mutation listeners.
  void dispose() {
    _mutationListeners.clear();
    removeAllEventListeners();
    for (final n in descendants) {
      n.removeAllEventListeners();
    }
    onFocusRequest = null;
    onListenerError = null;
    onSubmit = null;
    onNavigate = null;
    eventParent = null;
  }
}

int subtreeSize(Node node) {
  var count = 1;
  for (final c in node.rawChildren) {
    count += subtreeSize(c);
  }
  return count;
}

/// Height of [node]'s subtree; a leaf has height 1. Iterative, so hostile
/// trees cannot overflow the stack here.
int _height(Node node) {
  var max = 0;
  final stack = <(Node, int)>[(node, 1)];
  while (stack.isNotEmpty) {
    final (n, d) = stack.removeLast();
    if (d > max) max = d;
    for (final c in n.rawChildren) {
      stack.add((c, d + 1));
    }
  }
  return max;
}
