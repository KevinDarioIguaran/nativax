import 'element.dart';
import 'layout_host.dart';
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

  /// Autonomous custom-element names registered by `customElements.define`.
  /// Selectors can match `:defined` without reaching into the JS registry.
  final Set<String> definedCustomElements = <String>{};
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

  /// The document's doctype node, if any.
  DocumentType? get doctype => rawChildren.whereType<DocumentType>().firstOrNull;

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

  DocumentType createDocumentType(String name, [String publicId = '', String systemId = '']) {
    if (name.contains(RegExp(r'[\s>]'))) {
      throw DomException('InvalidCharacterError', 'invalid name "$name"');
    }
    return DocumentType(this, name, publicId: publicId, systemId: systemId);
  }

  /// Removes [node] from its parent and moves it (and its descendants) into
  /// this document. Documents cannot be adopted.
  Node adoptNode(Node node) {
    if (node is Document) {
      throw DomException('NotSupportedError', 'a document cannot be adopted');
    }
    node.parentNode?.removeChild(node);
    if (!identical(node.ownerDocument, this)) node.adoptDocument(this);
    return node;
  }

  ProcessingInstruction createProcessingInstruction(String target, String data) {
    validateName(target);
    if (data.contains('?>')) {
      throw DomException('InvalidCharacterError', 'data contains "?>"');
    }
    return ProcessingInstruction(this, target, data);
  }

  // --- queries -------------------------------------------------------------

  Element? getElementById(String id) {
    if (id.isEmpty) return null;
    for (final n in descendants) {
      if (n is Element && n.getAttribute('id') == id) return n;
    }
    return null;
  }

  Element? querySelector(String selectors) =>
      SelectorList.parse(selectors).first(this, documentElement);

  List<Element> querySelectorAll(String selectors) =>
      SelectorList.parse(selectors).all(this, documentElement);

  List<Element> getElementsByTagName(String name) =>
      documentElement == null
          ? const []
          : [
              if (name == '*' || documentElement!.localName == name.toLowerCase())
                documentElement!,
              ...documentElement!.getElementsByTagName(name),
            ];

  List<Element> getElementsByClassName(String names) {
    final wanted = names.split(RegExp(r'[\t\n\f\r ]+')).where((s) => s.isNotEmpty).toList();
    if (wanted.isEmpty || documentElement == null) return const [];
    return [
      if (wanted.every(documentElement!.classList.contains)) documentElement!,
      ...documentElement!.getElementsByClassName(names),
    ];
  }

  // --- focus ---------------------------------------------------------------

  Element? get activeElement => _activeElement ?? body;

  /// The element that actually has focus (`:focus`), or null.
  Element? get focusedElement => _activeElement;

  /// Records that [element] gained focus (called by the renderer) and fires
  /// `blur`/`focus` events.
  void setFocusedElement(Element? element) {
    if (identical(element, _activeElement)) return;
    final previous = _activeElement;
    _activeElement = element;
    _stateChanged(previous, element);
    previous?.dispatchEvent(Event('blur')..isTrusted = true);
    element?.dispatchEvent(Event('focus')..isTrusted = true);
    if (previous != null) {
      previous.dispatchEvent(Event('focusout', bubbles: true)..isTrusted = true);
    }
    element?.dispatchEvent(Event('focusin', bubbles: true)..isTrusted = true);
  }

  // --- interaction state (:hover, :active, :target, :modal) ---------------

  Element? _hoverElement;
  Element? _pressedElement;
  String? _targetId;

  /// The innermost element under the pointer (`:hover` matches it and its
  /// ancestors).
  Element? get hoverElement => _hoverElement;
  set hoverElement(Element? element) {
    if (identical(element, _hoverElement)) return;
    final previous = _hoverElement;
    _hoverElement = element;
    _stateChanged(previous, element);
  }

  /// The element being pressed (`:active`).
  Element? get pressedElement => _pressedElement;
  set pressedElement(Element? element) {
    if (identical(element, _pressedElement)) return;
    final previous = _pressedElement;
    _pressedElement = element;
    _stateChanged(previous, element);
  }

  /// The fragment of the document URL (`:target`), without `#`.
  String? get targetId => _targetId;
  set targetId(String? id) {
    if (id == _targetId) return;
    final previous = _targetId == null ? null : getElementById(_targetId!);
    _targetId = id;
    _stateChanged(previous, id == null ? null : getElementById(id));
  }

  /// Layout queries and scrolling, provided by the renderer when mounted.
  LayoutHost? layoutHost;

  /// `<canvas>` 2D drawing, provided by the renderer when mounted. Commands
  /// recorded before a renderer exists are queued and replayed when one is
  /// attached.
  CanvasHost? get canvasHost => _canvasHost;
  CanvasHost? _canvasHost;
  set canvasHost(CanvasHost? host) {
    _canvasHost = host;
    if (host == null || _pendingCanvas.isEmpty) return;
    final pending = List.of(_pendingCanvas);
    _pendingCanvas.clear();
    for (final (el, w, h, ops) in pending) {
      host.draw(el, w, h, ops);
    }
  }

  final List<(Element, int, int, List<Object?>)> _pendingCanvas = [];
  int _pendingCanvasOps = 0;

  /// Sends canvas commands to the renderer, or queues them (bounded) until
  /// one is attached.
  void drawCanvas(Element canvas, int width, int height, List<Object?> ops) {
    final host = _canvasHost;
    if (host != null) {
      host.draw(canvas, width, height, ops);
      return;
    }
    // A reset makes earlier queued commands for this canvas irrelevant.
    if (ops.isNotEmpty && ops.first is List && (ops.first as List).firstOrNull == 'reset') {
      _pendingCanvas.removeWhere((p) => identical(p.$1, canvas));
    }
    _pendingCanvasOps += ops.length;
    if (_pendingCanvasOps > 500000) return;
    _pendingCanvas.add((canvas, width, height, ops));
  }

  /// When the user last interacted (trusted click, key or touch). Powerful
  /// APIs (clipboard writes, vibration) require a recent activation, like
  /// browsers' transient user activation.
  DateTime? lastUserActivation;

  /// Whether a trusted user gesture happened within the last 5 seconds.
  bool get hasTransientActivation {
    final t = lastUserActivation;
    return t != null && DateTime.now().difference(t) < const Duration(seconds: 5);
  }

  /// Dialogs opened with `showModal()`, in opening order (top last).
  final List<Element> modalElements = [];

  /// Notifies style listeners that state-dependent pseudo-classes may have
  /// changed for [a], [b] and their ancestors.
  void _stateChanged(Element? a, Element? b) {
    final seen = <Element>{};
    for (final start in [a, b]) {
      for (Element? e = start; e != null; e = e.parentElement) {
        if (!seen.add(e)) break;
      }
    }
    // Only ancestors that differ between the two chains change state; the
    // shared chain keeps :hover/:focus-within. Notify the topmost differing
    // elements (their subtrees are restyled).
    final shared = <Element>{};
    if (a != null && b != null) {
      for (Element? e = a; e != null; e = e.parentElement) {
        if (identical(e, b) || e.contains(b)) shared.add(e);
      }
    }
    for (final e in seen) {
      if (shared.contains(e)) continue;
      if (!e.isConnected) continue;
      notify(MutationRecord.property(e, ':state'));
    }
  }

  /// Signals that [element]'s state-dependent styles may have changed
  /// (validity, modal state).
  void notifyStateChanged(Element element) =>
      notify(MutationRecord.property(element, ':state'));

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
  Document cloneNode({bool deep = false}) {
    final copy = Document(limits: limits);
    if (deep) {
      for (final c in rawChildren) {
        copy.appendChild(c.cloneNode(deep: true));
      }
    }
    return copy;
  }

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
