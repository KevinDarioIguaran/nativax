/// DOM event model: capture, target and bubble phases, `stopPropagation`,
/// `stopImmediatePropagation` and `preventDefault`.
library;

enum EventPhase { none, capturing, atTarget, bubbling }

class Event {
  Event(
    this.type, {
    this.bubbles = false,
    this.cancelable = false,
    Map<String, Object?>? detail,
  }) : detail = detail ?? const {};

  final String type;
  final bool bubbles;
  final bool cancelable;

  /// Event-specific data (for example `key` for keyboard events or `value`
  /// for input events). Must be JSON-compatible so bindings can forward it.
  final Map<String, Object?> detail;

  EventTarget? target;
  EventTarget? currentTarget;
  EventPhase eventPhase = EventPhase.none;
  bool isTrusted = false;

  bool _defaultPrevented = false;
  bool _stopped = false;
  bool _stoppedImmediately = false;
  bool _dispatching = false;

  bool get defaultPrevented => _defaultPrevented;
  bool get propagationStopped => _stopped;

  void preventDefault() {
    if (cancelable) _defaultPrevented = true;
  }

  void stopPropagation() => _stopped = true;

  void stopImmediatePropagation() {
    _stopped = true;
    _stoppedImmediately = true;
  }
}

/// A listener. Implementations used from bindings must define `==` and
/// `hashCode` so that registering the same callback twice is a no-op, as in
/// the DOM.
abstract interface class EventListener {
  void handleEvent(Event event);
}

/// Optionally implemented by listeners that hold external resources (for
/// example a script callback) so they can release them once no target
/// references them any more.
abstract interface class RemovalAwareListener implements EventListener {
  void onRemoved();
}

/// Adapts a Dart closure. Two adapters are equal only if they wrap the same
/// closure instance.
final class CallbackListener implements EventListener {
  const CallbackListener(this.callback);
  final void Function(Event event) callback;

  @override
  void handleEvent(Event event) => callback(event);

  @override
  bool operator ==(Object other) =>
      other is CallbackListener && other.callback == callback;

  @override
  int get hashCode => callback.hashCode;
}

class _Registration {
  _Registration(this.listener, this.capture, this.once);
  final EventListener listener;
  final bool capture;
  final bool once;
  bool removed = false;
}

/// Reports an exception thrown by a listener. Dispatch continues with the
/// next listener, as browsers do.
typedef ListenerErrorHandler = void Function(Object error, StackTrace stack);

abstract class EventTarget {
  final Map<String, List<_Registration>> _listeners = {};

  /// Parent in the propagation path, or null at the root.
  EventTarget? get parentEventTarget;

  /// Where listener exceptions go. Set by the owning document.
  ListenerErrorHandler? get listenerErrorHandler => null;

  void addEventListener(
    String type,
    EventListener listener, {
    bool capture = false,
    bool once = false,
  }) {
    final list = _listeners.putIfAbsent(type, () => []);
    for (final r in list) {
      if (r.capture == capture && r.listener == listener) return;
    }
    list.add(_Registration(listener, capture, once));
  }

  void removeEventListener(
    String type,
    EventListener listener, {
    bool capture = false,
  }) {
    final list = _listeners[type];
    if (list == null) return;
    list.removeWhere((r) {
      final match = r.capture == capture && r.listener == listener;
      if (match) {
        r.removed = true;
        final l = r.listener;
        if (l is RemovalAwareListener) l.onRemoved();
      }
      return match;
    });
    if (list.isEmpty) _listeners.remove(type);
  }

  /// Removes every listener; used when tearing down a document.
  void removeAllEventListeners() {
    for (final list in _listeners.values) {
      for (final r in list) {
        r.removed = true;
        final l = r.listener;
        if (l is RemovalAwareListener) l.onRemoved();
      }
    }
    _listeners.clear();
  }

  bool hasEventListeners(String type) => _listeners[type]?.isNotEmpty ?? false;

  int get eventListenerCount =>
      _listeners.values.fold(0, (sum, l) => sum + l.length);

  /// Dispatches [event] along the propagation path. Returns false when a
  /// listener called `preventDefault` on a cancelable event.
  /// Called before [event] is dispatched with this as its target.
  void willDispatch(Event event) {}

  bool dispatchEvent(Event event) {
    if (event._dispatching) {
      throw StateError('event "${event.type}" is already being dispatched');
    }
    willDispatch(event);
    event._dispatching = true;
    event.target = this;
    final path = <EventTarget>[];
    for (EventTarget? t = parentEventTarget; t != null; t = t.parentEventTarget) {
      path.add(t);
    }
    final onError = listenerErrorHandler;
    try {
      event.eventPhase = EventPhase.capturing;
      for (final t in path.reversed) {
        t._invoke(event, capturePhase: true, onError: onError);
        if (event._stopped) return !event._defaultPrevented;
      }
      event.eventPhase = EventPhase.atTarget;
      _invoke(event, capturePhase: null, onError: onError);
      if (event._stopped || !event.bubbles) return !event._defaultPrevented;
      event.eventPhase = EventPhase.bubbling;
      for (final t in path) {
        t._invoke(event, capturePhase: false, onError: onError);
        if (event._stopped) break;
      }
      return !event._defaultPrevented;
    } finally {
      event._dispatching = false;
      event.eventPhase = EventPhase.none;
      event.currentTarget = null;
    }
  }

  /// [capturePhase] null means "at target": capture listeners run first,
  /// then non-capture ones.
  void _invoke(
    Event event, {
    required bool? capturePhase,
    ListenerErrorHandler? onError,
  }) {
    final list = _listeners[event.type];
    if (list == null || list.isEmpty) return;
    event.currentTarget = this;
    final snapshot = List<_Registration>.of(list);
    final ordered = capturePhase == null
        ? [
            ...snapshot.where((r) => r.capture),
            ...snapshot.where((r) => !r.capture),
          ]
        : snapshot.where((r) => r.capture == capturePhase);
    for (final r in ordered) {
      if (r.removed) continue;
      if (r.once) {
        // Unregister before invoking (so re-entrant dispatch skips it), but
        // notify removal-aware listeners only after they have run.
        r.removed = true;
        list.remove(r);
        if (list.isEmpty) _listeners.remove(event.type);
      }
      try {
        r.listener.handleEvent(event);
      } catch (error, stack) {
        if (onError == null) rethrow;
        onError(error, stack);
      } finally {
        final l = r.listener;
        if (r.once && l is RemovalAwareListener) l.onRemoved();
      }
      if (event._stoppedImmediately) return;
    }
  }
}
