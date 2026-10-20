import 'dart:async';

import 'exceptions.dart';
import 'javascript_engine.dart';

const String _timerPrelude = r'''
(() => {
  const host = __nx.host;
  const callbacks = new Map();
  const schedule = (repeat) => (fn, delay, ...args) => {
    if (typeof fn !== 'function') {
      throw new TypeError('NativaX timers only accept functions');
    }
    const id = host('timer.schedule', Number(delay) || 0, repeat);
    callbacks.set(id, { fn, args, repeat });
    return id;
  };
  const clear = (id) => {
    if (!callbacks.delete(id)) return;
    host('timer.cancel', id);
  };
  globalThis.setTimeout = schedule(false);
  globalThis.setInterval = schedule(true);
  globalThis.clearTimeout = clear;
  globalThis.clearInterval = clear;
  globalThis.queueMicrotask = (fn) => {
    if (typeof fn !== 'function') throw new TypeError('not a function');
    Promise.resolve().then(fn);
  };
  Object.defineProperty(globalThis, '__nx_fireTimer', {
    value: (id) => {
      const entry = callbacks.get(id);
      if (!entry) return;
      if (!entry.repeat) callbacks.delete(id);
      entry.fn(...entry.args);
    },
    enumerable: false,
  });
})();
''';

/// Limits for [TimerHost].
class TimerLimits {
  const TimerLimits({
    this.maxActiveTimers = 1000,
    this.minIntervalMs = 4,
  });

  /// Scheduling beyond this raises `RangeError` in script code.
  final int maxActiveTimers;

  /// Intervals shorter than this are clamped, as browsers do for nested
  /// timers, so `setInterval(fn, 0)` cannot monopolize the UI thread.
  final int minIntervalMs;
}

/// Implements `setTimeout`, `setInterval`, their `clear*` counterparts and
/// `queueMicrotask` on top of Dart [Timer]s.
///
/// Semantics: each timer callback runs as one task in its own engine entry
/// (with its own execution budget) on the isolate's event loop; microtasks
/// are drained after every task. Timers never block the UI thread while
/// waiting. Ordering between timers with equal deadlines follows Dart's
/// timer ordering, which is FIFO in practice but not specified.
class TimerHost {
  TimerHost(
    this._engine, {
    this.limits = const TimerLimits(),
    this.onError,
    this.afterTask,
  }) {
    _engine.registerHostFunction('timer.schedule', _schedule);
    _engine.registerHostFunction('timer.cancel', _cancel);
    _engine.evaluate(_timerPrelude, filename: '<nativax:timers>');
  }

  final JavaScriptEngine _engine;
  final TimerLimits limits;

  /// Receives exceptions thrown by timer callbacks (they have no caller).
  final void Function(JavaScriptException error)? onError;

  /// Called after each timer task, for example to flush DOM mutations.
  final void Function()? afterTask;

  final Map<int, Timer> _timers = {};
  int _nextId = 1;
  bool _disposed = false;

  int get activeTimers => _timers.length;

  Object? _schedule(List<Object?> args) {
    if (_timers.length >= limits.maxActiveTimers) {
      throw JavaScriptHostError('RangeError', 'too many active timers');
    }
    final delay = (args[0] as num).toInt().clamp(0, 0x7fffffff);
    final repeat = args[1] == true;
    final id = _nextId++;
    if (repeat) {
      final period = Duration(
        milliseconds: delay < limits.minIntervalMs ? limits.minIntervalMs : delay,
      );
      _timers[id] = Timer.periodic(period, (_) => _fire(id, repeat: true));
    } else {
      _timers[id] = Timer(Duration(milliseconds: delay), () {
        _timers.remove(id);
        _fire(id, repeat: false);
      });
    }
    return id;
  }

  Object? _cancel(List<Object?> args) {
    _timers.remove((args[0] as num).toInt())?.cancel();
    return null;
  }

  void _fire(int id, {required bool repeat}) {
    if (_disposed || _engine.isDisposed) return;
    try {
      _engine.callGlobal('__nx_fireTimer', id);
    } on JavaScriptException catch (e) {
      onError?.call(e);
      // An interval whose callback timed out would time out again forever.
      if (repeat && e is JavaScriptTimeoutException) {
        _timers.remove(id)?.cancel();
      }
    }
    afterTask?.call();
  }

  /// Cancels all timers. Call before disposing the engine.
  void dispose() {
    _disposed = true;
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
  }
}
