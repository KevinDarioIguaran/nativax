import 'dart:async';

import 'package:nativax_css/nativax_css.dart';
import 'package:nativax_dom/nativax_dom.dart';
import 'package:nativax_html/nativax_html.dart';
import 'package:nativax_js/nativax_js.dart';

import 'environment.dart';
import 'inline_style.dart';
import 'prelude.dart';

/// Dart handler callable from script as `nativax.invoke(name, ...args)`.
typedef AppHandler = Object? Function(List<Object?> args);

/// The window: an event target above the document in propagation.
class WindowTarget extends EventTarget {
  @override
  EventTarget? get parentEventTarget => null;
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
class DomBindings {
  DomBindings({
    required this.engine,
    required this.document,
    required this.environment,
    HtmlParser? htmlParser,
    Map<String, AppHandler> appHandlers = const {},
    this.onScriptError,
  })  : _html = htmlParser ?? HtmlParser(),
        _appHandlers = Map.of(appHandlers);

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

  void install() {
    if (_installed) return;
    _installed = true;
    document.eventParent = window;
    _idFor(window);
    final ops = _ops();
    ops.forEach(engine.registerHostFunction);
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
      Element e => [id, 1, e.localName],
      Node n => [id, n.nodeType.code, null],
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

  /// Fires `DOMContentLoaded` (document, bubbling to window) and `load`
  /// (window) once document scripts have run.
  void fireLoadEvents() {
    readyState = 'interactive';
    document.dispatchEvent(Event('DOMContentLoaded', bubbles: true)..isTrusted = true);
    readyState = 'complete';
    window.dispatchEvent(Event('load')..isTrusted = true);
  }

  // --- host operations ------------------------------------------------------------

  Map<String, HostFunction> _ops() => {
        'node.release': (a) {
          final id = (a[0] as num).toInt();
          final t = _targets[id];
          if (t != null && !identical(t, window) && !identical(t, document)) {
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
        'doc.createElement': (a) => _dom(() => describe(document.createElement(_str(a[0])))),
        'doc.createText': (a) => describe(document.createTextNode(_str(a[0]))),
        'doc.createComment': (a) => describe(document.createComment(_str(a[0]))),
        'doc.createFragment': (a) => describe(document.createDocumentFragment()),
        'doc.byId': (a) => describe(document.getElementById(_str(a[0]))),
        'doc.get': (a) => switch (_str(a[0])) {
              'documentElement' => describe(document.documentElement),
              'head' => describe(document.head),
              'body' => describe(document.body),
              'activeElement' => describe(document.activeElement),
              'title' => document.title,
              'readyState' => readyState,
              _ => throw JavaScriptHostError('TypeError', 'unknown document property'),
            },
        'doc.setTitle': (a) => _dom(() {
              final head = document.head;
              if (head == null) return null;
              var title = document.querySelector('title');
              if (title == null) {
                title = document.createElement('title');
                head.appendChild(title);
              }
              title.textContent = _str(a[0]);
              return null;
            }),

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
        return n is Document ? null : n.textContent;
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
      _ => throw JavaScriptHostError('TypeError', 'unknown property "$name"'),
    };
  }

  Object? _nodeSet(Node n, String name, Object? value) {
    if (name == 'textContent') {
      if (n is! Document) n.textContent = value is String ? value : '';
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
      default:
        throw JavaScriptHostError('TypeError', 'cannot set "$name"');
    }
    return null;
  }

  /// Releases every listener and wrapper. The engine may be disposed after.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
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
