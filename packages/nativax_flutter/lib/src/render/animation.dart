import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:nativax_css/nativax_css.dart';
import 'package:nativax_dom/nativax_dom.dart' as dom;

/// Interpolates two computed values at [t] (0..1), or returns null when
/// they are not interpolable (the caller then flips discretely at 50%).
CssValue? lerpCssValue(CssValue a, CssValue b, double t) {
  if (a == b) return a;
  if (a is Length && b is Length) {
    if (a.unit == b.unit) return Length(lerpDouble(a.value, b.value, t)!, a.unit);
    if (a.value == 0) return Length(b.value * t, b.unit);
    if (b.value == 0) return Length(a.value * (1 - t), a.unit);
    return null;
  }
  if (a is NumberValue && b is NumberValue) return NumberValue(lerpDouble(a.value, b.value, t)!);
  if (a is ColorValue && b is ColorValue && a.color != null && b.color != null) {
    final x = a.color!.argb, y = b.color!.argb;
    int ch(int shift) => (lerpDouble(((x >> shift) & 0xff).toDouble(), ((y >> shift) & 0xff).toDouble(), t)!.round()).clamp(0, 255);
    return ColorValue(CssColor((ch(24) << 24) | (ch(16) << 16) | (ch(8) << 8) | ch(0)));
  }
  if (a is TransformValue || b is TransformValue) {
    final fa = a is TransformValue ? a.functions : <TransformFunction>[];
    final fb = b is TransformValue ? b.functions : <TransformFunction>[];
    final from = fa.isEmpty ? [for (final f in fb) _identity(f)] : fa;
    final to = fb.isEmpty ? [for (final f in fa) _identity(f)] : fb;
    if (from.length != to.length) return null;
    final out = <TransformFunction>[];
    for (var i = 0; i < from.length; i++) {
      final x = from[i], y = to[i];
      if (x.name != y.name || x.args.length != y.args.length) return null;
      final args = <CssValue>[];
      for (var k = 0; k < x.args.length; k++) {
        final v = lerpCssValue(x.args[k], y.args[k], t);
        if (v == null) return null;
        args.add(v);
      }
      out.add(TransformFunction(x.name, args));
    }
    return TransformValue(out);
  }
  if (a is ShadowValue && b is ShadowValue && a.shadows.length == b.shadows.length) {
    Length l(Length p, Length q) => Length.px(lerpDouble(p.value, q.value, t)!);
    return ShadowValue([
      for (var i = 0; i < a.shadows.length; i++)
        CssShadow(
          l(a.shadows[i].x, b.shadows[i].x),
          l(a.shadows[i].y, b.shadows[i].y),
          l(a.shadows[i].blur, b.shadows[i].blur),
          l(a.shadows[i].spread, b.shadows[i].spread),
          (lerpCssValue(a.shadows[i].color, b.shadows[i].color, t) as ColorValue?) ?? b.shadows[i].color,
          inset: b.shadows[i].inset,
        ),
    ]);
  }
  return null;
}

TransformFunction _identity(TransformFunction f) {
  final scale = f.name.startsWith('scale');
  return TransformFunction(f.name, [
    for (final a in f.args) a is Length ? Length(0, a.unit) : NumberValue(scale ? 1 : 0),
  ]);
}

/// Longhands affected by a `transition-property` name.
List<String> transitionLonghands(String name) {
  const sides = ['top', 'right', 'bottom', 'left'];
  const corners = ['top-left', 'top-right', 'bottom-right', 'bottom-left'];
  return switch (name) {
    'background' => const ['background-color'],
    'margin' => [for (final s in sides) 'margin-$s'],
    'padding' => [for (final s in sides) 'padding-$s'],
    'border-color' => [for (final s in sides) 'border-$s-color'],
    'border-width' => [for (final s in sides) 'border-$s-width'],
    'border' => [for (final s in sides) ...['border-$s-color', 'border-$s-width']],
    'border-radius' => [for (final c in corners) 'border-$c-radius'],
    'inset' => sides,
    'outline' => const ['outline-color', 'outline-width', 'outline-offset'],
    'gap' => const ['row-gap', 'column-gap'],
    'font' => const ['font-size', 'font-weight', 'line-height'],
    'flex' => const ['flex-grow', 'flex-shrink', 'flex-basis'],
    _ => longhands.containsKey(name) ? [name] : const [],
  };
}

/// Properties never transitioned with `transition-property: all`.
const _notAnimatable = {
  'display', 'position', 'content', 'transition-property', 'transition-duration', 'transition-delay',
  'transition-timing-function', 'animation-name', 'animation-duration', 'animation-delay',
  'animation-timing-function', 'animation-iteration-count', 'animation-direction', 'animation-fill-mode',
  'animation-play-state', 'font-family', 'grid-template-areas', 'grid-template-columns', 'grid-template-rows',
};

class _Running {
  _Running(this.from, this.to, this.start, this.duration, this.delay, this.easing);
  final CssValue from;
  final CssValue to;
  final Duration start;
  final double duration; // ms
  final double delay; // ms
  final CssEasing easing;
  bool started = false;

  double progress(Duration now) {
    final elapsed = (now - start).inMicroseconds / 1000 - delay;
    if (elapsed <= 0) return 0;
    if (duration <= 0) return 1;
    return (elapsed / duration).clamp(0.0, 1.0);
  }

  CssValue valueAt(Duration now) {
    final p = easing.transform(progress(now));
    return lerpCssValue(from, to, p) ?? (p < 0.5 ? from : to);
  }

  bool done(Duration now) => progress(now) >= 1;
}

class _Animation {
  _Animation(this.spec, this.start, this.frames);
  final CssAnimation spec;
  final Duration start;

  /// (offset, values, easing) sorted by offset.
  final List<(double, Map<String, CssValue>, CssEasing?)> frames;
  int reportedIteration = 0;
  bool started = false;
  bool ended = false;
}

/// Runs CSS transitions and `@keyframes` animations for one element and
/// rebuilds its box with the interpolated style.
class CssAnimatedBox extends StatefulWidget {
  const CssAnimatedBox({
    super.key,
    required this.element,
    required this.style,
    required this.styleEngine,
    required this.builder,
  });

  final dom.Element element;
  final ComputedStyle style;
  final StyleEngine styleEngine;
  final Widget Function(ComputedStyle style) builder;

  @override
  State<CssAnimatedBox> createState() => _CssAnimatedBoxState();
}

class _CssAnimatedBoxState extends State<CssAnimatedBox> with SingleTickerProviderStateMixin {
  Ticker? _ticker;

  /// Animation time: advances only while the ticker runs, so idle periods do
  /// not count (animations start relative to it).
  Duration _now = Duration.zero;
  Duration _offset = Duration.zero;
  final Map<String, _Running> _transitions = {};
  List<_Animation> _animations = const [];

  @override
  void initState() {
    super.initState();
    _startAnimations(widget.style.animations, const []);
  }

  @override
  void didUpdateWidget(covariant CssAnimatedBox old) {
    super.didUpdateWidget(old);
    _startTransitions(old.style, widget.style);
    final before = old.style.animations;
    final after = widget.style.animations;
    if (!_sameAnimations(before, after)) _startAnimations(after, before);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  bool _sameAnimations(List<CssAnimation> a, List<CssAnimation> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].name != b[i].name || a[i].duration != b[i].duration || a[i].iterations != b[i].iterations) return false;
    }
    return true;
  }

  Duration get _clock => _now;

  void _ensureTicking() {
    _ticker ??= createTicker(_tick);
    if (!_ticker!.isActive) {
      _offset = _now;
      _ticker!.start();
    }
  }

  void _fire(String type, Map<String, Object?> detail) {
    final element = widget.element;
    scheduleMicrotask(() {
      if (!element.isConnected) return;
      element.dispatchEvent(dom.Event(type, bubbles: true, detail: detail)..isTrusted = true);
    });
  }

  // --- transitions -------------------------------------------------------------

  void _startTransitions(ComputedStyle before, ComputedStyle after) {
    final specs = after.transitions;
    if (specs.isEmpty) {
      _transitions.clear();
      return;
    }
    final props = <String, CssTransition>{};
    for (final t in specs) {
      if (t.property == 'all') {
        for (final p in longhands.keys) {
          if (!_notAnimatable.contains(p)) props[p] = t;
        }
      } else {
        for (final p in transitionLonghands(t.property)) {
          props[p] = t;
        }
      }
    }
    final now = _clock;
    for (final e in props.entries) {
      final p = e.key;
      final to = after[p];
      final running = _transitions[p];
      final from = running != null ? running.valueAt(now) : before[p];
      if (from == to) {
        if (running != null && running.to != to) _transitions.remove(p);
        continue;
      }
      if (running != null && running.to == to) continue;
      final spec = e.value;
      if (spec.duration <= 0 || lerpCssValue(from, to, 0.5) == null) {
        _transitions.remove(p);
        continue;
      }
      _transitions[p] = _Running(from, to, now, spec.duration, spec.delay, spec.easing);
      _fire('transitionrun', {'propertyName': p, 'elapsedTime': 0});
    }
    if (_transitions.isNotEmpty) _ensureTicking();
  }

  // --- animations ---------------------------------------------------------------

  void _startAnimations(List<CssAnimation> specs, List<CssAnimation> previous) {
    final now = _clock;
    final list = <_Animation>[];
    for (final spec in specs) {
      final kf = widget.styleEngine.keyframes(spec.name);
      if (kf == null) continue;
      // Keep animations that were already running under the same name.
      final existing = _animations.where((a) => a.spec.name == spec.name).firstOrNull;
      if (existing != null) {
        list.add(_Animation(spec, existing.start, existing.frames)
          ..started = existing.started
          ..reportedIteration = existing.reportedIteration);
        continue;
      }
      final frames = <(double, Map<String, CssValue>, CssEasing?)>[];
      final base = widget.style;
      for (final f in kf.frames) {
        final s = widget.styleEngine.styleWithDeclarations(widget.element, f.declarations);
        final values = <String, CssValue>{};
        final declared = <String>{};
        var raw = false;
        CssEasing? easing;
        for (final d in f.declarations) {
          if (d.property == 'animation-timing-function') {
            final v = d.value;
            if (v is ListValue && v.items.isNotEmpty) easing = v.items.first as CssEasing;
            continue;
          }
          if (longhands.containsKey(d.property)) {
            declared.add(d.property);
          } else {
            raw = true;
          }
        }
        if (raw) {
          for (final p in longhands.keys) {
            if (!_notAnimatable.contains(p) && s[p] != base[p]) declared.add(p);
          }
        }
        for (final p in declared) {
          if (!_notAnimatable.contains(p)) values[p] = s[p];
        }
        for (final o in f.offsets) {
          frames.add((o, values, easing));
        }
      }
      frames.sort((a, b) => a.$1.compareTo(b.$1));
      list.add(_Animation(spec, now, frames));
    }
    _animations = list;
    if (_animations.isNotEmpty) _ensureTicking();
  }

  /// The animated values of [a] at [now], or null when it has no effect.
  Map<String, CssValue>? _sample(_Animation a, Duration now, ComputedStyle base) {
    final spec = a.spec;
    var elapsed = (now - a.start).inMicroseconds / 1000 - spec.delay;
    final dur = spec.duration;
    final total = spec.iterations.isInfinite ? double.infinity : dur * spec.iterations;
    final fillBackwards = spec.fill == 'backwards' || spec.fill == 'both';
    final fillForwards = spec.fill == 'forwards' || spec.fill == 'both';
    double iterationProgress;
    int iteration;
    if (elapsed < 0) {
      if (!fillBackwards) return null;
      iteration = 0;
      iterationProgress = 0;
    } else if (elapsed >= total) {
      if (!a.ended) {
        a.ended = true;
        _fire('animationend', {'animationName': spec.name, 'elapsedTime': total / 1000});
      }
      if (!fillForwards) return null;
      iteration = (spec.iterations.ceil() - 1).clamp(0, 1 << 30);
      final frac = spec.iterations - spec.iterations.floor();
      iterationProgress = frac == 0 ? 1 : frac;
    } else {
      if (!a.started) {
        a.started = true;
        _fire('animationstart', {'animationName': spec.name, 'elapsedTime': 0});
      }
      if (dur <= 0) {
        iteration = 0;
        iterationProgress = 1;
      } else {
        iteration = (elapsed / dur).floor();
        iterationProgress = (elapsed - iteration * dur) / dur;
        if (iteration > a.reportedIteration) {
          a.reportedIteration = iteration;
          _fire('animationiteration', {'animationName': spec.name, 'elapsedTime': iteration * dur / 1000});
        }
      }
    }
    final reverse = switch (spec.direction) {
      'reverse' => true,
      'alternate' => iteration.isOdd,
      'alternate-reverse' => iteration.isEven,
      _ => false,
    };
    var p = reverse ? 1 - iterationProgress : iterationProgress;
    // Implicit 0% / 100% keyframes use the underlying values.
    final frames = [...a.frames];
    final props = <String>{for (final f in frames) ...f.$2.keys};
    if (frames.isEmpty || frames.first.$1 > 0) frames.insert(0, (0.0, {for (final k in props) k: base[k]}, null));
    if (frames.last.$1 < 1) frames.add((1.0, {for (final k in props) k: base[k]}, null));
    var i = 0;
    while (i < frames.length - 2 && frames[i + 1].$1 <= p) {
      i++;
    }
    final f0 = frames[i], f1 = frames[i + 1];
    final span = f1.$1 - f0.$1;
    final local = span <= 0 ? 1.0 : ((p - f0.$1) / span).clamp(0.0, 1.0);
    final eased = (f0.$3 ?? spec.easing).transform(local);
    p = eased;
    final out = <String, CssValue>{};
    for (final k in props) {
      final a0 = f0.$2[k] ?? base[k];
      final a1 = f1.$2[k] ?? base[k];
      out[k] = lerpCssValue(a0, a1, p) ?? (p < 0.5 ? a0 : a1);
    }
    return out;
  }

  void _tick(Duration tickerElapsed) {
    final elapsed = _offset + tickerElapsed;
    _now = elapsed;
    final finished = <String>[];
    _transitions.forEach((p, t) {
      if (!t.started && t.progress(elapsed) > 0) {
        t.started = true;
        _fire('transitionstart', {'propertyName': p, 'elapsedTime': 0});
      }
      if (t.done(elapsed)) finished.add(p);
    });
    for (final p in finished) {
      final t = _transitions.remove(p)!;
      _fire('transitionend', {'propertyName': p, 'elapsedTime': t.duration / 1000});
    }
    final animating = _animations.any((a) => !a.ended && !a.spec.paused);
    if (_transitions.isEmpty && !animating) {
      _ticker?.stop();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.style;
    if (_transitions.isEmpty && _animations.isEmpty) return widget.builder(base);
    final values = Map<String, CssValue>.of(base.values);
    _transitions.forEach((p, t) => values[p] = t.valueAt(_now));
    for (final a in _animations) {
      final v = _sample(a, _now, base);
      if (v != null) values.addAll(v);
    }
    return widget.builder(ComputedStyle(values, customProperties: base.customProperties));
  }
}
