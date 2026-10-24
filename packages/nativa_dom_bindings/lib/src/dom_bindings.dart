import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_dom/nativa_dom.dart';
import 'package:nativa_html/nativa_html.dart';
import 'package:nativa_js/nativa_js.dart';

import 'environment.dart';
import 'inline_style.dart';
import 'messaging.dart';
import 'worker_runtime.dart';
import 'network.dart';
import 'prelude.dart';

part 'web_ops.dart';

/// Dart handler callable from script as `nativax.invoke(name, ...args)`.
typedef AppHandler = Object? Function(List<Object?> args);

/// The window: an event target above the document in propagation.
class WindowTarget extends EventTarget {
  @override
  EventTarget? get parentEventTarget => null;

  /// Where listener exceptions go (reported like uncaught script errors).
  ListenerErrorHandler? onListenerError;

  @override
  ListenerErrorHandler? get listenerErrorHandler => onListenerError;
}

/// A `matchMedia()` result; fires `change` when its result flips.
class _MediaQueryTarget extends EventTarget {
  _MediaQueryTarget(this.query, this.list, this.matches);
  final String query;
  final MediaQueryList list;
  bool matches;

  @override
  EventTarget? get parentEventTarget => null;
}

/// Exposes a [Document] and browser-style APIs to a [JavaScriptEngine].
///
/// Script code only ever sees numeric ids; every operation is validated
/// here. Listener callbacks stay in the engine and are invoked by id.
/// Mutation records are captured as node references and materialised only
/// when script calls `takeRecords()`. A removed node's wrapper may otherwise
/// be released between the mutation and the microtask that delivers it.
class _PendingMutation {
  _PendingMutation({
    required this.type,
    required this.target,
    required this.addedNodes,
    required this.removedNodes,
    required this.previousSibling,
    required this.nextSibling,
    required this.attributeName,
    required this.attributeNamespace,
    required this.oldValue,
  });

  final String type;
  final Node target;
  final List<Node> addedNodes;
  final List<Node> removedNodes;
  final Node? previousSibling;
  final Node? nextSibling;
  final String? attributeName;
  final String? attributeNamespace;
  final String? oldValue;
}

class DomBindings {
  DomBindings({
    required this.engine,
    required this.document,
    required this.environment,
    HtmlParser? htmlParser,
    Map<String, AppHandler> appHandlers = const {},
    this.onScriptError,
    this.styleEngine,
    String documentUrl = 'about:blank',
    this.network = const DeniedNetwork(),
    this.services = const PlatformServices(),
    NativaXMessaging? messaging,
    this.workerScope,
  })  : messaging = messaging ?? RouterMessaging.local(launcher: InProcessWorkerLauncher(network: network)),
        _html = htmlParser ?? HtmlParser(),
        _appHandlers = Map.of(appHandlers),
        _url = Uri.tryParse(documentUrl) ?? Uri.parse('about:blank');

  /// Computed styles for `getComputedStyle()`; null reports empty styles.
  final StyleEngine? styleEngine;

  /// `fetch`, `XMLHttpRequest` and `WebSocket` go through this policy.
  final NativaXNetwork network;

  /// `MessagePort`s and dedicated workers.
  final NativaXMessaging messaging;

  /// Set when these bindings back a worker's global scope instead of a
  /// window: no `window`/`document` globals, `self.postMessage` on the
  /// worker's implicit port.
  final WorkerScopeInfo? workerScope;
  final PlatformServices services;

  Uri _url;
  final List<(Uri, Object?)> _history = [];
  int _historyIndex = 0;
  final Stopwatch _clock = Stopwatch()..start();
  final int _timeOrigin = DateTime.now().millisecondsSinceEpoch;
  final math.Random _random = math.Random.secure();
  final Map<int, List<_Observation>> _observers = {};
  final Map<int, List<_PendingMutation>> _pendingRecords = {};
  final Map<int, NetworkSocket> _sockets = {};
  final Set<int> _aborted = {};

  /// GL surfaces owned by canvas elements of this document.
  final Set<int> _surfaces = {};

  /// The document URL (`location.href`).
  Uri get url => _url;

  final JavaScriptEngine engine;
  final Document document;
  final HostEnvironment environment;
  final HtmlParser _html;
  final Map<String, AppHandler> _appHandlers;

  /// Receives exceptions thrown by script listeners.
  final void Function(Object error)? onScriptError;

  final WindowTarget window = WindowTarget();
  final Map<int, EventTarget> _targets = {};
  final Expando<int> _ids = Expando('nativax.id');
  int _nextId = 1;

  final Map<int, Event> _events = {};
  final Expando<int> _eventIds = Expando('nativax.event');
  int _nextEventId = 1;

  final Map<int, int> _listenerRefs = {};
  final List<_MediaQueryTarget> _mediaQueries = [];
  MediaContext? _lastMedia;
  ThemeSnapshot? _lastTheme;
  List<String>? _lastLanguages;
  bool _installed = false;
  bool _disposed = false;
  String readyState = 'loading';

  /// Live node wrappers, for diagnostics and leak tests.
  int get registeredTargets => _targets.length;
  int get activeEvents => _events.length;
  int get liveListeners => _listenerRefs.length;

  void registerHandler(String name, AppHandler handler) => _appHandlers[name] = handler;

  /// Removes the raw host-function bridge from script globals.
  ///
  /// The DOM/console/timer preludes close over `host`, so they keep working.
  /// Call this only after every prelude that needs `__nx.host` has been
  /// installed (the public runtime does it before executing document
  /// scripts). Scripts then cannot invoke internal host operations by name.
  void harden() {
    if (_disposed) return;
    try {
      engine.evaluate('delete globalThis.__nx;', filename: '<nativax:harden>');
    } on JavaScriptException {
      // A script cannot reach this point before installation; keep the host
      // bridge if the engine refuses deletion rather than breaking the app.
    }
  }

  void install() {
    if (_installed) return;
    _installed = true;
    document.eventParent = window;
    _idFor(window);
    void report(Object error, StackTrace stack) => onScriptError?.call(error);
    document.onListenerError ??= report;
    window.onListenerError ??= report;
    _history.add((_url, null));
    _setUrl(_url);
    final external = document.onNavigate;
    document.onNavigate = (href, anchor) {
      final Uri next;
      try {
        next = _url.resolve(href);
      } on FormatException {
        return;
      }
      if (!_navigate(next, replace: false, push: true)) external?.call(href, anchor);
    };
    document.addMutationListener(_observe);
    final ops = {..._ops(), ...webOps()};
    ops.forEach(engine.registerHostFunction);
    messaging.attach(
      deliver: (port, wire) {
        if (_disposed || engine.isDisposed) return;
        try {
          engine.callGlobal('__nx_port', {'id': port, 'wire': wire});
        } on JavaScriptException catch (e) {
          onScriptError?.call(e);
        }
      },
      workerEvent: (worker, event) {
        if (_disposed || engine.isDisposed) return;
        try {
          engine.callGlobal('__nx_worker', {'id': worker, ...event});
        } on JavaScriptException catch (e) {
          onScriptError?.call(e);
        }
      },
    );
    final scope = workerScope;
    if (scope != null) {
      engine.evaluate('globalThis.__nx_scope = ${jsonEncode(scope.toJson())};', filename: '<nativax:scope>');
    }
    engine.evaluate(domPrelude, filename: '<nativax:dom>');
    _lastMedia = environment.media;
    _lastTheme = environment.theme;
    _lastLanguages = List.of(environment.languages);
  }

  // --- identity ----------------------------------------------------------------

  int _idFor(EventTarget t) {
    final existing = _ids[t];
    if (existing != null && identical(_targets[existing], t)) return existing;
    final id = _nextId++;
    _ids[t] = id;
    _targets[id] = t;
    return id;
  }

  /// `[id, nodeType, localName]`, or null.
  List<Object?>? describe(EventTarget? t) {
    if (t == null) return null;
    final id = _idFor(t);
    return switch (t) {
      Element e => [id, 1, e.localName, e.isConnected],
      DocumentType d => [id, 10, d.name, d.isConnected],
      Document _ => [id, 9, null],
      Node n => [id, n.nodeType.code, null, n.isConnected],
      _MediaQueryTarget _ => [id, 100, null],
      _ => [id, 0, null],
    };
  }

  EventTarget _target(Object? id) {
    final t = id is num ? _targets[id.toInt()] : null;
    if (t == null) throw JavaScriptHostError('TypeError', 'invalid or released node');
    return t;
  }

  Node _node(Object? id) {
    final t = _target(id);
    if (t is! Node) throw JavaScriptHostError('TypeError', 'not a node');
    return t;
  }

  Element _element(Object? id) {
    final t = _target(id);
    if (t is! Element) throw JavaScriptHostError('TypeError', 'not an element');
    return t;
  }

  Document _document(Object? id) {
    final t = _target(id);
    if (t is! Document) throw JavaScriptHostError('TypeError', 'not a document');
    return t;
  }

  static String _str(Object? v) => v is String ? v : throw JavaScriptHostError('TypeError', 'expected a string');

  /// Runs [body], translating DOM exceptions into script exceptions.
  static Object? _dom(Object? Function() body) {
    try {
      return body();
    } on DomException catch (e) {
      throw JavaScriptHostError(e.name, e.message);
    } on HtmlLimitException catch (e) {
      throw JavaScriptHostError('QuotaExceededError', e.message);
    }
  }

  // --- MutationObserver delivery -----------------------------------------------

  // --- wrapper retention ------------------------------------------------------

  final Set<int> _attach = {};
  final Set<int> _detach = {};
  bool _connScheduled = false;

  /// Tracks nodes entering or leaving the document so the prelude can hold
  /// connected wrappers strongly and release detached ones.
  void _trackConnection(MutationRecord r) {
    if (r.type != MutationType.childList) return;
    void visit(Node n, Set<int> into, Set<int> other) {
      final id = _ids[n];
      if (id != null && identical(_targets[id], n)) {
        into.add(id);
        other.remove(id);
      }
      for (final c in n.childNodes) {
        visit(c, into, other);
      }
    }

    for (final n in r.removedNodes) {
      if (!n.isConnected) visit(n, _detach, _attach);
    }
    for (final n in r.addedNodes) {
      if (n.isConnected) visit(n, _attach, _detach);
    }
    if ((_attach.isNotEmpty || _detach.isNotEmpty) && !_connScheduled) {
      _connScheduled = true;
      scheduleMicrotask(_flushConnections);
    }
  }

  void _flushConnections() {
    _connScheduled = false;
    if (_disposed || engine.isDisposed) return;
    final msg = {'attach': _attach.toList(), 'detach': _detach.toList()};
    _attach.clear();
    _detach.clear();
    try {
      engine.callGlobal('__nx_conn', msg);
    } on JavaScriptException catch (e) {
      onScriptError?.call(e);
    }
  }

  void _observe(MutationRecord r) {
    _trackConnection(r);
    if (_observers.isEmpty || r.type == MutationType.property) return;
    for (final entry in _observers.entries) {
      final t = r.target;
      var matched = false;
      var withOld = false;
      for (final o in entry.value) {
        if (!(identical(o.target, t) || (o.subtree && o.target.contains(t)))) continue;
        switch (r.type) {
          case MutationType.childList:
            if (!o.childList) continue;
          case MutationType.attributes:
            if (!o.attributes) continue;
            final filter = o.attributeFilter;
            if (filter != null && !filter.contains(r.name)) continue;
          case MutationType.characterData:
            if (!o.characterData) continue;
          case MutationType.property:
            continue;
        }
        matched = true;
        if (r.type == MutationType.attributes && o.options['attributeOldValue'] == true) {
          withOld = true;
        }
        if (r.type == MutationType.characterData && o.options['characterDataOldValue'] == true) {
          withOld = true;
        }
      }
      if (!matched) continue;
      _pendingRecords.putIfAbsent(entry.key, () => []).add(_PendingMutation(
            type: r.type.name,
            target: t,
            addedNodes: List.of(r.addedNodes),
            removedNodes: List.of(r.removedNodes),
            previousSibling: r.previousSibling,
            nextSibling: r.nextSibling,
            attributeName: r.type == MutationType.attributes ? r.name : null,
            attributeNamespace: r.type == MutationType.attributes ? r.namespace : null,
            oldValue: withOld ? r.oldValue : null,
          ));
    }
    if (_pendingRecords.isNotEmpty) {
      try {
        engine.callGlobal('__nx_queue_mo', _pendingRecords.keys.toList());
      } on JavaScriptException catch (e) {
        onScriptError?.call(e);
      }
    }
  }

  // --- events ------------------------------------------------------------------

  int _eventId(Event e) {
    final existing = _eventIds[e];
    if (existing != null && _events.containsKey(existing)) return existing;
    final id = _nextEventId++;
    _eventIds[e] = id;
    _events[id] = e;
    // Trusted events are dispatched from Dart; forget them once the current
    // synchronous dispatch has finished.
    scheduleMicrotask(() {
      if (_events.remove(id) != null && !_disposed && !engine.isDisposed) {
        try {
          engine.callGlobal('__nx_eventDone', id);
        } on JavaScriptException catch (e) {
          onScriptError?.call(e);
        }
      }
    });
    return id;
  }

  Map<String, Object?> _describeEvent(Event e) => {
        'id': _eventId(e),
        'type': e.type,
        'bubbles': e.bubbles,
        'cancelable': e.cancelable,
        'isTrusted': e.isTrusted,
        'timeStamp': DateTime.now().millisecondsSinceEpoch,
        'detail': e.detail,
      };

  void _invokeListener(int listenerId, Event event) {
    engine.callGlobal('__nx_dispatch', {
      'listener': listenerId,
      'event': _describeEvent(event),
      'currentTarget': describe(event.currentTarget),
    });
  }

  void _releaseListener(int id) {
    final n = (_listenerRefs[id] ?? 1) - 1;
    if (n > 0) {
      _listenerRefs[id] = n;
      return;
    }
    _listenerRefs.remove(id);
    if (_disposed || engine.isDisposed) return;
    engine.callGlobal('__nx_releaseListener', id);
  }

  // --- environment ----------------------------------------------------------------

  /// Call after the [HostEnvironment] changed (resize, theme, locale). Fires
  /// `resize`, `change` on affected `matchMedia` lists, `nativax:themechange`
  /// and `languagechange` as appropriate.
  void environmentChanged() {
    if (_disposed) return;
    final media = environment.media;
    final theme = environment.theme;
    final langs = environment.languages;
    if (_lastMedia != null &&
        (media.width != _lastMedia!.width || media.height != _lastMedia!.height)) {
      window.dispatchEvent(Event('resize')..isTrusted = true);
    }
    for (final mq in List.of(_mediaQueries)) {
      final now = mq.list.evaluate(media);
      if (now != mq.matches) {
        mq.matches = now;
        mq.dispatchEvent(Event('change', detail: {'matches': now, 'media': mq.query})..isTrusted = true);
      }
    }
    if (_lastTheme != null && theme != _lastTheme) {
      window.dispatchEvent(Event('nativax:themechange', detail: theme.toJson())..isTrusted = true);
    }
    if (_lastLanguages != null && _lastLanguages!.join(',') != langs.join(',')) {
      window.dispatchEvent(Event('languagechange')..isTrusted = true);
    }
    _lastMedia = media;
    _lastTheme = theme;
    _lastLanguages = List.of(langs);
  }

  /// Delivers a message from Dart to script listeners of
  /// `nativax.addEventListener('message', ...)`; available as `event.data`.
  void postMessage(Object? data) {
    window.dispatchEvent(Event('nativax:message', detail: {'data': data})..isTrusted = true);
  }

  /// Runs the platform's own "document parsed" steps (inline `on*`
  /// attributes, media and image error reporting). Call once, before
  /// `DOMContentLoaded`.
  void documentReady() {
    if (_disposed || engine.isDisposed) return;
    try {
      engine.callGlobal('__nx_ready');
    } on JavaScriptException catch (e) {
      onScriptError?.call(e);
    }
  }

  /// Fires `DOMContentLoaded` (document, bubbling to window) and `load`
  /// (window) once document scripts have run.
  void fireLoadEvents() {
    documentReady();
    readyState = 'interactive';
    document.dispatchEvent(Event('DOMContentLoaded', bubbles: true)..isTrusted = true);
    readyState = 'complete';
    window.dispatchEvent(Event('load')..isTrusted = true);
  }

  // --- host operations ------------------------------------------------------------

  Map<String, HostFunction> _ops() => {
    'custom.define': (a) {
      final name = '${a[0]}';
      if (document.definedCustomElements.add(name)) {
        styleEngine?.invalidateAll();
        final root = document.documentElement;
        if (root != null) document.notifyStateChanged(root);
      }
      return null;
    },
        'node.release': (a) {
          final id = (a[0] as num).toInt();
          final t = _targets[id];
          if (t != null && !identical(t, window) && !identical(t, document)) {
            // A wrapper can be collected while its DOM node is still connected
            // and reachable from the document. In that case listeners belong
            // to the node and must survive; only a detached node with no JS
            // reference can release them safely.
            if (t is Node && !t.isConnected) {
              t.removeAllEventListeners();
            }
            _targets.remove(id);
          }
          return null;
        },
        'win.desc': (a) => describe(window),
        'doc.desc': (a) => describe(document),

        // Node
        'node.get': (a) {
          final n = _node(a[0]);
          final name = _str(a[1]);
          return _dom(() => _nodeGet(n, name));
        },
        'node.set': (a) {
          final n = _node(a[0]);
          final name = _str(a[1]);
          return _dom(() => _nodeSet(n, name, a[2]));
        },
        'node.insertBefore': (a) => _dom(() {
              final parent = _node(a[0]);
              parent.insertBefore(_node(a[1]), a[2] == null ? null : _node(a[2]));
              return null;
            }),
        'node.removeChild': (a) => _dom(() {
              _node(a[0]).removeChild(_node(a[1]));
              return null;
            }),
        'node.replaceChild': (a) => _dom(() {
              _node(a[0]).replaceChild(_node(a[1]), _node(a[2]));
              return null;
            }),
        'node.replaceChildren': (a) => _dom(() {
              final n = _node(a[0]);
              n.replaceChildren([for (final id in a[1] as List) _node(id)]);
              return null;
            }),
        'node.remove': (a) => _dom(() {
              _node(a[0]).remove();
              return null;
            }),
        'node.contains': (a) => _node(a[0]).contains(_node(a[1])),
        'node.clone': (a) => _dom(() => describe(_node(a[0]).cloneNode(deep: a[1] == true))),
        'node.splitText': (a) => _dom(() {
              final n = _node(a[0]);
              if (n is! Text) throw JavaScriptHostError('TypeError', 'not a Text node');
              return describe(n.splitText((a[1] as num).toInt()));
            }),

        // Attributes and classes
        'attr.get': (a) => _element(a[0]).getAttribute(_str(a[1])),
        'attr.set': (a) => _dom(() {
              _element(a[0]).setAttribute(_str(a[1]), _str(a[2]));
              return null;
            }),
        'attr.remove': (a) {
          _element(a[0]).removeAttribute(_str(a[1]));
          return null;
        },
        'attr.namespaces': (a) => Map.of(_element(a[0]).attributeNamespaces),
        'attr.entries': (a) => _element(a[0]).attributeEntries,
        'attr.getNS': (a) => _element(a[0]).getAttributeNS(a[1] as String?, _str(a[2])),
        'attr.setNS': (a) {
          _element(a[0]).setAttributeNS(a[1] as String?, _str(a[2]), _str(a[3]));
          return null;
        },
        'attr.removeNS': (a) {
          _element(a[0]).removeAttributeNS(a[1] as String?, _str(a[2]));
          return null;
        },
        'attr.toggle': (a) => _dom(() => _element(a[0]).toggleAttribute(_str(a[1]), a[2] as bool?)),
        'cl.list': (a) => _element(a[0]).classList.toList(),
        'cl.add': (a) => _dom(() {
              _element(a[0]).classList.add((a[1] as List).cast<String>());
              return null;
            }),
        'cl.remove': (a) => _dom(() {
              _element(a[0]).classList.remove((a[1] as List).cast<String>());
              return null;
            }),
        'cl.toggle': (a) => _dom(() => _element(a[0]).classList.toggle(_str(a[1]), a[2] as bool?)),
        'cl.replace': (a) => _dom(() => _element(a[0]).classList.replace(_str(a[1]), _str(a[2]))),

        // Inline style
        'style.get': (a) => InlineStyle(_element(a[0])).getPropertyValue(_str(a[1])),
        'style.priority': (a) => InlineStyle(_element(a[0])).getPropertyPriority(_str(a[1])),
        'style.set': (a) {
          InlineStyle(_element(a[0])).setProperty(_str(a[1]), _str(a[2]), _str(a[3]));
          return null;
        },
        'style.remove': (a) => InlineStyle(_element(a[0])).removeProperty(_str(a[1])),
        'style.cssText': (a) {
          InlineStyle(_element(a[0])).cssText = _str(a[1]);
          return null;
        },
        'style.names': (a) => InlineStyle(_element(a[0])).propertyNames,

        // Queries
        'q.one': (a) => _dom(() => describe(_queryRoot(a[0]).$1(_str(a[1])))),
        'q.all': (a) => _dom(() => [for (final e in _queryRoot(a[0]).$2(_str(a[1]))) describe(e)]),
        'q.tag': (a) {
          final n = _node(a[0]);
          final name = _str(a[1]);
          final list = n is Document ? n.getElementsByTagName(name) : (n as Element).getElementsByTagName(name);
          return [for (final e in list) describe(e)];
        },
        'q.class': (a) {
          final n = _node(a[0]);
          final name = _str(a[1]);
          final list = n is Document ? n.getElementsByClassName(name) : (n as Element).getElementsByClassName(name);
          return [for (final e in list) describe(e)];
        },
        'q.matches': (a) => _dom(() => _element(a[0]).matches(_str(a[1]))),
        'q.closest': (a) => _dom(() => describe(_element(a[0]).closest(_str(a[1])))),

        // Element behavior
        'el.focus': (a) {
          final e = _element(a[0]);
          document.requestFocus(e);
          return null;
        },
        'el.blur': (a) {
          final e = _element(a[0]);
          if (identical(document.activeElement, e)) document.requestFocus(null);
          return null;
        },
        'el.click': (a) {
          _element(a[0]).click();
          return null;
        },
        'el.outerHTML': (a) => _dom(() {
              final e = _element(a[0]);
              final parent = e.parentElement;
              if (parent == null) return null;
              final fragment = _html.parseFragment(_str(a[1]), parent).value;
              final nodes = fragment.childNodes.toList();
              if (nodes.length == 1) {
                parent.replaceChild(nodes.single, e);
              } else {
                parent.insertBefore(fragment, e);
                parent.removeChild(e);
              }
              return null;
            }),
        'el.insertAdjacentHTML': (a) => _dom(() {
              final e = _element(a[0]);
              final pos = _str(a[1]).toLowerCase();
              final ctx = (pos == 'beforebegin' || pos == 'afterend') ? e.parentElement : e;
              if (ctx == null) throw DomException('NoModificationAllowedError', 'element has no parent');
              final fragment = _html.parseFragment(_str(a[2]), ctx).value;
              switch (pos) {
                case 'beforebegin':
                  e.parentNode!.insertBefore(fragment, e);
                case 'afterbegin':
                  e.insertBefore(fragment, e.firstChild);
                case 'beforeend':
                  e.appendChild(fragment);
                case 'afterend':
                  e.parentNode!.insertBefore(fragment, e.nextSibling);
                default:
                  throw DomException('SyntaxError', 'invalid position "$pos"');
              }
              return null;
            }),

        // Document
        'doc.new': (a) => describe(Document()),
        'doc.createElement': (a) => _dom(() => describe(_document(a[0]).createElement(_str(a[1])))),
        'doc.adoptNode': (a) => _dom(() => describe(_document(a[0]).adoptNode(_node(a[1])))),
        'doc.createText': (a) => describe(_document(a[0]).createTextNode(_str(a[1]))),
        'doc.createComment': (a) => describe(_document(a[0]).createComment(_str(a[1]))),
        'doc.createPI': (a) => _dom(() =>
            describe(_document(a[0]).createProcessingInstruction(_str(a[1]), _str(a[2])))),
        'doc.createDoctype': (a) => _dom(() => describe(_document(a[0]).createDocumentType(
            _str(a[1]), _str(a[2]), _str(a[3])))),
        'doc.createFragment': (a) => describe(_document(a[0]).createDocumentFragment()),
        'doc.byId': (a) => _dom(() => describe(_document(a[0]).getElementById(_str(a[1])))),
        'doc.get': (a) {
          final d = _document(a[0]);
          return switch (_str(a[1])) {
            'documentElement' => describe(d.documentElement),
            'head' => describe(d.head),
            'body' => describe(d.body),
            'activeElement' => describe(d.activeElement),
            'title' => d.title,
            'readyState' => readyState,
            'doctype' => describe(d.doctype),
            _ => throw JavaScriptHostError('TypeError', 'unknown document property'),
          };
        },
        'doc.setTitle': (a) => _dom(() {
              final d = _document(a[0]);
              final head = d.head;
              if (head == null) return null;
              var title = d.querySelector('title');
              if (title == null) {
                title = d.createElement('title');
                head.appendChild(title);
              }
              title.textContent = _str(a[1]);
              return null;
            }),

        // URL (WHATWG fixture). Dart's Uri is not a complete WHATWG parser,
        // but it covers the common schemes and keeps the JS surface honest.
        'url.parse': (a) => _parseUrl(
              _str(a[0]),
              a.length > 1 && a[1] != null ? _str(a[1]) : null,
            ),

        // Events
        'ev.add': (a) {
          final t = _target(a[0]);
          final id = (a[2] as num).toInt();
          final listener = _JsListener(this, id);
          final before = t.eventListenerCount;
          t.addEventListener(_str(a[1]), listener, capture: a[3] == true, once: a[4] == true);
          if (t.eventListenerCount > before) _listenerRefs[id] = (_listenerRefs[id] ?? 0) + 1;
          return null;
        },
        'ev.remove': (a) {
          _target(a[0]).removeEventListener(_str(a[1]), _JsListener(this, (a[2] as num).toInt()),
              capture: a[3] == true);
          return null;
        },
        'event.create': (a) {
          final e = Event(_str(a[0]), bubbles: a[1] == true, cancelable: a[2] == true);
          final id = _nextEventId++;
          _eventIds[e] = id;
          _events[id] = e;
          return id;
        },
        'ev.dispatch': (a) {
          final t = _target(a[0]);
          final id = (a[1] as num).toInt();
          final e = _events[id];
          if (e == null) throw JavaScriptHostError('TypeError', 'unknown event');
          try {
            return t.dispatchEvent(e);
          } on StateError catch (err) {
            throw JavaScriptHostError('InvalidStateError', err.message);
          } finally {
            _events.remove(id);
          }
        },
        'event.get': (a) {
          final e = _events[(a[0] as num).toInt()];
          if (e == null) return null;
          return switch (_str(a[1])) {
            'target' => describe(e.target),
            'currentTarget' => describe(e.currentTarget),
            'eventPhase' => e.eventPhase.index,
            'defaultPrevented' => e.defaultPrevented,
            _ => null,
          };
        },
        'event.call': (a) {
          final e = _events[(a[0] as num).toInt()];
          if (e == null) return null;
          switch (_str(a[1])) {
            case 'preventDefault':
              e.preventDefault();
            case 'stopPropagation':
              e.stopPropagation();
            case 'stopImmediatePropagation':
              e.stopImmediatePropagation();
          }
          return null;
        },

        // Environment
        'env.get': (a) {
          final m = environment.media;
          return {
            'languages': environment.languages,
            'platform': environment.platform,
            'width': m.width,
            'height': m.height,
            'dpr': m.devicePixelRatio,
          };
        },
        'mql.create': (a) {
          final query = _str(a[0]);
          final list = MediaQueryList.parse(CssTokenizer(query).tokenize());
          final target = _MediaQueryTarget(query, list, list.evaluate(environment.media));
          _mediaQueries.add(target);
          if (_mediaQueries.length > 256) _mediaQueries.removeAt(0);
          return describe(target);
        },
        'mql.matches': (a) => MediaQueryList.parse(CssTokenizer(_str(a[0])).tokenize())
            .evaluate(environment.media),
        'theme.get': (a) => environment.theme.toJson(),
        'theme.setMode': (a) {
          final mode = ThemeModeRequest.values.asNameMap()[_str(a[0])];
          if (mode == null) throw JavaScriptHostError('TypeError', 'mode must be light, dark or system');
          return environment.requestThemeMode(mode);
        },
        'storage.available': (a) => environment.localStorage != null,
        'storage.get': (a) => _storage.getItem(_str(a[0])),
        'storage.set': (a) {
          try {
            _storage.setItem(_str(a[0]), _str(a[1]));
          } on StorageQuotaExceeded {
            throw JavaScriptHostError('QuotaExceededError', 'localStorage quota exceeded');
          }
          return null;
        },
        'storage.remove': (a) {
          _storage.removeItem(_str(a[0]));
          return null;
        },
        'storage.clear': (a) {
          _storage.clear();
          return null;
        },
        'storage.keys': (a) => _storage.keys(),
        'app.invoke': (a) {
          final handler = _appHandlers[_str(a[0])];
          if (handler == null) throw JavaScriptHostError('TypeError', 'no handler named "${a[0]}"');
          return handler((a[1] as List).cast<Object?>());
        },
      };

  KeyValueStorage get _storage =>
      environment.localStorage ?? (throw JavaScriptHostError('TypeError', 'localStorage is not available'));

  (Element? Function(String), List<Element> Function(String)) _queryRoot(Object? id) {
    final n = _node(id);
    return switch (n) {
      Document d => (d.querySelector, d.querySelectorAll),
      Element e => (e.querySelector, e.querySelectorAll),
      _ => (
          (s) => SelectorList.parse(s).first(n),
          (s) => SelectorList.parse(s).all(n),
        ),
    };
  }

  static const _defaultPorts = {
    'http': 80,
    'https': 443,
    'ws': 80,
    'wss': 443,
    'ftp': 21,
  };

  Map<String, Object?>? _parseUrl(String input, String? base) {
    String clean(String value) => value
        .replaceAll(RegExp(r'[\t\n\r]'), '')
        .replaceAll(RegExp(r'^[\u0000-\u0020]+|[\u0000-\u0020]+$'), '');
    var text = clean(input);
    var baseText = base == null ? null : clean(base);
    // A special scheme without `//` and without a base can still denote an
    // authority (`http:example.com`), not a relative reference.
    if (baseText == null) {
      final noSlash = RegExp(r'^(https?|wss?|ftp):(?!//)(.*)$',
              caseSensitive: false)
          .firstMatch(text);
      if (noSlash != null) {
        final scheme = noSlash.group(1)!.toLowerCase();
        var rest = noSlash.group(2)!.replaceAll('\\', '/');
        if (rest.startsWith('/')) {
          final without = rest.replaceFirst(RegExp(r'^/+'), '');
          if (without.isNotEmpty && RegExp(r'[@.:]').hasMatch(without)) {
            text = '$scheme://$without';
          }
        } else if (rest.startsWith('@') ||
            (rest.contains('@') && !rest.startsWith(':')) ||
            RegExp(r'[.:@]').hasMatch(rest)) {
          text = '$scheme://$rest';
        }
      }
    }
    final isData = text.toLowerCase().startsWith('data:');
    try {
      // WHATWG treats a special scheme without `//` as a relative reference or
      // an authority depending on the remainder. Dart's Uri is stricter, so
      // normalize the common forms before parsing.
      if (baseText != null) {
        if (text.startsWith(':')) text = './$text';
        final match = RegExp(r'^(https?|wss?|ftp):(?!//)(.*)$',
                caseSensitive: false)
            .firstMatch(text);
        if (match != null) {
          final scheme = match.group(1)!.toLowerCase();
          final rest = match.group(2)!.replaceAll('\\', '/');
          final baseUri = Uri.parse(baseText);
          if (rest.startsWith('/')) {
            final without = rest.replaceFirst(RegExp(r'^/+'), '');
            if (without.isEmpty) {
              text = baseUri
                  .replace(scheme: scheme, path: '/', query: null, fragment: null)
                  .toString();
            } else if (RegExp(r'[@.:]').hasMatch(without)) {
              text = '$scheme://$without';
            } else {
              text = baseUri
                  .resolve(without)
                  .replace(scheme: scheme)
                  .toString();
            }
          } else if (rest.startsWith('@') ||
              (rest.contains('@') && !rest.startsWith(':')) ||
              (scheme != baseUri.scheme.toLowerCase() &&
                  RegExp(r'[.:@]').hasMatch(rest))) {
            text = '$scheme://$rest';
          } else {
            final relative = rest.startsWith(':') || rest.startsWith('[')
                ? './$rest'
                : rest;
            text = baseUri
                .resolve(relative)
                .replace(scheme: scheme)
                .toString();
          }
          baseText = null;
        }
      }

      final authority = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://([^/?#]*)')
          .firstMatch(text);
      if (authority != null &&
          RegExp(r'\s').hasMatch(authority.group(1) ?? '')) {
        return null;
      }
      final candidate = isData
          ? Uri.parse('http${text.substring(4)}')
          : Uri.parse(text);
      final baseUri = baseText == null ? null : Uri.parse(baseText);
      final resolved = baseUri == null ? candidate : baseUri.resolveUri(candidate);
      final scheme = isData ? 'data' : resolved.scheme.toLowerCase();
      if (baseUri != null &&
          !_defaultPorts.containsKey(baseUri.scheme) &&
          !baseUri.hasAuthority &&
          !candidate.hasScheme) {
        return null;
      }
      if (scheme.isEmpty) return null;
      final special = _defaultPorts.containsKey(scheme);
      var port = resolved.hasPort ? resolved.port : null;
      if (isData) {
        final authorityMatch =
            RegExp(r'^data://([^/?#]*)').firstMatch(text);
        final authority = authorityMatch?.group(1) ?? '';
        final hasExplicitPort = authority.contains(':') &&
            !(authority.startsWith('[') && authority.contains(']:'));
        if (!hasExplicitPort) port = null;
      }
      if (port != null && (port < 0 || port > 65535)) return null;
      if (scheme == 'file' && resolved.hasPort) return null;
      if (special && resolved.host.isEmpty) return null;
      final hasAuthority = resolved.hasAuthority;
      final defaultPort = _defaultPorts[scheme];
      var hostname = resolved.host;
      if (scheme == 'file' && hostname.toLowerCase() == 'localhost') {
        hostname = '';
      }
      if (hostname.contains('%') || hostname.contains('\\')) return null;
      final authorityText = authority?.group(1) ?? '';
      if (hasAuthority &&
          hostname.isEmpty &&
          (authorityText.contains('@') || authorityText.contains(':'))) {
        return null;
      }
      final hostForIp = hostname.endsWith('.')
          ? hostname.substring(0, hostname.length - 1)
          : hostname;
      final parts = hostForIp.split('.');
      final last = parts.isEmpty ? '' : parts.last;
      final looksNumeric = RegExp(r'^(?:0x[0-9a-fA-F]*|[0-9]+)$')
          .hasMatch(last);
      if (looksNumeric) {
        if (parts.length > 4) return null;
        for (var i = 0; i < parts.length; i++) {
          final part = parts[i];
          final isLast = i == parts.length - 1;
          int? value;
          if (RegExp(r'^0x[0-9a-fA-F]+$').hasMatch(part)) {
            value = int.tryParse(part.substring(2), radix: 16);
          } else if (RegExp(r'^0[0-7]+$').hasMatch(part)) {
            value = int.tryParse(part.substring(1), radix: 8);
          } else if (RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(part)) {
            value = int.tryParse(part);
          }
          if (value == null || value < 0) return null;
          if (isLast) {
            final maxLast = i == 3 ? 255 : (1 << (8 * (4 - i))) - 1;
            if (value > maxLast) return null;
          } else if (value > 255) {
            return null;
          }
        }
      }
      BigInt? numericHost;
      if (RegExp(r'^\d+$').hasMatch(hostname)) {
        numericHost = BigInt.tryParse(hostname);
      } else if (RegExp(r'^0x[0-9a-f]+$', caseSensitive: false)
          .hasMatch(hostname)) {
        numericHost = BigInt.tryParse(hostname.substring(2), radix: 16);
      }
      if (numericHost != null && numericHost > BigInt.from(0xffffffff)) {
        return null;
      }
      final displayHost =
          hostname.contains(':') ? '[$hostname]' : hostname;
      final host = displayHost.isEmpty
          ? ''
          : (port != null && port != defaultPort
              ? '$displayHost:$port'
              : displayHost);
      final userInfo = resolved.userInfo;
      final colon = userInfo.indexOf(':');
      final username = colon < 0 ? userInfo : userInfo.substring(0, colon);
      final password = colon < 0 ? '' : userInfo.substring(colon + 1);
      final path = resolved.path.isEmpty && hasAuthority && special
          ? '/'
          : resolved.path;
      final search = resolved.hasQuery && resolved.query.isNotEmpty
          ? '?${resolved.query}'
          : '';
      final hash = resolved.hasFragment && resolved.fragment.isNotEmpty
          ? '#${resolved.fragment}'
          : '';
      String? origin;
      if (special && hostname.isNotEmpty) {
        origin = '$scheme://$displayHost'
            '${port != null && port != defaultPort ? ':$port' : ''}';
      } else if (scheme == 'blob') {
        final inner = _parseUrl(resolved.path, null);
        origin = inner?['origin'] as String?;
      }
      final normalizedUserInfo = password.isEmpty
          ? username
          : (username.isEmpty ? ':$password' : '$username:$password');
      var hrefUri = resolved.replace(userInfo: normalizedUserInfo, scheme: scheme);
      if (scheme == 'file' && resolved.host.toLowerCase() == 'localhost') {
        hrefUri = hrefUri.replace(host: '');
      }
      var href = hrefUri.toString();
      if (!hasAuthority && !special && !isData) {
        // Opaque paths keep their raw spaces/backslashes, matching the fixture
        // input more closely than Dart's percent-encoder.
        href = text;
        final hashIndex = text.indexOf('#');
        if (hashIndex >= 0) {
          final fragment = text
              .substring(hashIndex + 1)
              .replaceAll(' ', '%20');
          href = '${text.substring(0, hashIndex + 1)}$fragment';
        }
      } else {
        final hashIndex = href.indexOf('#');
        if (hashIndex >= 0) {
          final fragment = href
              .substring(hashIndex + 1)
              .replaceAll('%23', '#')
              .replaceAll('%5C', '\\');
          href = '${href.substring(0, hashIndex + 1)}$fragment';
        }
      }
      if (hasAuthority && resolved.path.isEmpty && special && !href.endsWith('/')) {
        href = '$href/';
      }
      return {
        'href': href,
        'origin': origin,
        'protocol': '$scheme:',
        'username': username,
        'password': password,
        'host': host,
        'hostname': displayHost,
        'port': port == null || port == defaultPort ? '' : '$port',
        'pathname': path,
        'search': search,
        'hash': hash,
      };
    } catch (error) {
      return null;
    }
  }

  Object? _nodeGet(Node n, String name) {
    switch (name) {
      case 'nodeType':
        return n.nodeType.code;
      case 'nodeName':
        return n.nodeName;
      case 'isConnected':
        return n.isConnected;
      case 'parentNode':
        return describe(n.parentNode);
      case 'parentElement':
        return describe(n.parentElement);
      case 'firstChild':
        return describe(n.firstChild);
      case 'lastChild':
        return describe(n.lastChild);
      case 'nextSibling':
        return describe(n.nextSibling);
      case 'previousSibling':
        return describe(n.previousSibling);
      case 'childNodes':
        return [for (final c in n.childNodes) describe(c)];
      case 'childCount':
        return n.childNodes.length;
      case 'children':
        return [for (final c in n.children) describe(c)];
      case 'firstElementChild':
        return describe(n.children.firstOrNull);
      case 'lastElementChild':
        return describe(n.children.lastOrNull);
      case 'textContent':
        return n is Document || n is DocumentType ? null : n.textContent;
      case 'ownerDocument':
        return describe(n is Document ? null : n.ownerDocument);
    }
    if (name == 'nextElementSibling') return describe(n.nextElementSibling);
    if (name == 'previousElementSibling') return describe(n.previousElementSibling);
    if (n is ProcessingInstruction) {
      return switch (name) {
        'target' => n.target,
        _ => throw JavaScriptHostError('TypeError', 'unknown property "$name"'),
      };
    }
    if (n is DocumentType) {
      return switch (name) {
        'name' => n.name,
        'publicId' => n.publicId,
        'systemId' => n.systemId,
        _ => throw JavaScriptHostError('TypeError', 'unknown property "$name"'),
      };
    }
    if (n is! Element) throw JavaScriptHostError('TypeError', '"$name" is not available on ${n.nodeName}');
    return switch (name) {
      'tagName' => n.tagName,
      'localName' => n.localName,
      'nextElementSibling' => describe(n.nextElementSibling),
      'previousElementSibling' => describe(n.previousElementSibling),
      'innerHTML' => n.innerHtml,
      'outerHTML' => n.outerHtml,
      'value' => n.value,
      'checked' => n.checked,
      'selectedIndex' => n.selectedIndex,
      'selectedOption' => describe(n.selectedOption),
      'options' => [for (final o in n.options) describe(o)],
      'attributes' => Map.of(n.attributes),
      'styleText' => n.getAttribute('style') ?? '',
      'optionSelected' => n.optionSelected,
      'returnValue' => n.returnValue,
      _ => throw JavaScriptHostError('TypeError', 'unknown property "$name"'),
    };
  }

  Object? _nodeSet(Node n, String name, Object? value) {
    if (name == 'textContent') {
      if (n is! Document) n.textContent = value == null ? '' : value.toString();
      return null;
    }
    if (n is! Element) throw JavaScriptHostError('TypeError', 'cannot set "$name" on ${n.nodeName}');
    switch (name) {
      case 'innerHTML':
        final fragment = _html.parseFragment(_str(value), n).value;
        n.replaceChildren(List.of(fragment.childNodes));
      case 'value':
        n.value = value?.toString() ?? '';
      case 'checked':
        n.checked = value == true;
      case 'selectedIndex':
        n.selectedIndex = (value is num) ? value.toInt() : -1;
      case 'returnValue':
        n.returnValue = value?.toString() ?? '';
      default:
        throw JavaScriptHostError('TypeError', 'cannot set "$name"');
    }
    return null;
  }

  /// Releases every listener and wrapper. The engine may be disposed after.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    document.removeMutationListener(_observe);
    for (final s in _sockets.values) {
      s.close();
    }
    _sockets.clear();
    messaging.dispose();
    for (final s in _surfaces) {
      GlSurfaces.release(s);
    }
    _surfaces.clear();
    _observers.clear();
    window.removeAllEventListeners();
    for (final mq in _mediaQueries) {
      mq.removeAllEventListeners();
    }
    _mediaQueries.clear();
    document.dispose();
    _targets.clear();
    _events.clear();
    _listenerRefs.clear();
  }
}

/// Identity of a worker global scope (see [DomBindings.workerScope]).
class WorkerScopeInfo {
  const WorkerScopeInfo({required this.port, this.name = '', this.type = 'classic', this.onClose, this.importScript});

  /// The worker's side of the channel to the page that created it.
  final int port;
  final String name;
  final String type;

  /// `self.close()`.
  final void Function()? onClose;

  /// Synchronous source of `importScripts(url)` (null fails with
  /// NetworkError). Only sources available without waiting can be served.
  final String? Function(String url)? importScript;

  Map<String, Object?> toJson() => {'port': port, 'name': name, 'type': type};
}

/// A script listener, identified by the id the prelude assigned to the
/// callback. Equal ids mean the same callback, so the DOM's duplicate
/// detection works across calls.
final class _JsListener implements RemovalAwareListener {
  _JsListener(this._bindings, this.id);
  final DomBindings _bindings;
  final int id;

  @override
  void handleEvent(Event event) => _bindings._invokeListener(id, event);

  @override
  void onRemoved() => _bindings._releaseListener(id);

  @override
  bool operator ==(Object other) => other is _JsListener && other.id == id && identical(other._bindings, _bindings);

  @override
  int get hashCode => id.hashCode;
}
