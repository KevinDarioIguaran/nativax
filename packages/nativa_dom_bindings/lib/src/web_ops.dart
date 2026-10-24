part of 'dom_bindings.dart';

/// One `MutationObserver.observe()` registration.
class _Observation {
  _Observation(this.target, this.options);
  final Node target;
  final Map<String, Object?> options;

  bool get subtree => options['subtree'] == true;
  bool get childList => options['childList'] == true;
  bool get attributes =>
      options['attributes'] == true ||
      options['attributeOldValue'] == true ||
      options['attributeFilter'] != null;
  bool get characterData =>
      options['characterData'] == true ||
      options['characterDataOldValue'] == true;
  List<String>? get attributeFilter =>
      (options['attributeFilter'] as List?)?.cast<String>();
}

/// Serializes a computed value the way `getComputedStyle()` reports it.
String cssValueText(CssValue v) {
  String num(double d) {
    if (d == d.roundToDouble()) return d.toInt().toString();
    return double.parse(d.toStringAsFixed(4)).toString();
  }

  String color(CssColor c) {
    final a = c.alpha;
    final r = (c.argb >> 16) & 0xff,
        g = (c.argb >> 8) & 0xff,
        b = c.argb & 0xff;
    if (a == 255) return 'rgb($r, $g, $b)';
    return 'rgba($r, $g, $b, ${num(a / 255)})';
  }

  return switch (v) {
    Length l =>
      l.unit == LengthUnit.percent ? '${num(l.value)}%' : '${num(l.value)}px',
    NumberValue n => num(n.value),
    ColorValue c => c.color == null ? 'currentcolor' : color(c.color!),
    Keyword k => k.name,
    FontFamilyValue f =>
      f.families.map((x) => x.contains(' ') ? '"$x"' : x).join(', '),
    UrlValue u => 'url("${u.url}")',
    ShadowValue s =>
      s.shadows
          .map(
            (x) =>
                '${x.color.color == null ? 'currentcolor' : color(x.color.color!)} ${num(x.x.value)}px ${num(x.y.value)}px ${num(x.blur.value)}px ${num(x.spread.value)}px${x.inset ? ' inset' : ''}',
          )
          .join(', '),
    ContentValue c =>
      c.parts.isEmpty ? '""' : c.parts.map((p) => '"$p"').join(' '),
    _ => v.toString(),
  };
}

const bool _traceHost = bool.fromEnvironment(
  'NATIVAX_TRACE_HOST',
  defaultValue: false,
);

extension _WebOps on DomBindings {
  Map<String, HostFunction> webOps() => {
    // --- timing and randomness ------------------------------------------
    'perf.now': (a) => _clock.elapsedMicroseconds / 1000,
    'perf.origin': (a) => _timeOrigin.toDouble(),
    'crypto.random': (a) {
      final n = ((a[0] as num?) ?? 0).toInt();
      if (n < 0 || n > 65536)
        throw JavaScriptHostError('QuotaExceededError', 'at most 65536 bytes');
      return [for (var i = 0; i < n; i++) _random.nextInt(256)];
    },

    // --- CSS ------------------------------------------------------------------
    'css.supports': (a) {
      if (a.length >= 2 && a[1] != null) {
        final prop = DomBindings._str(a[0]).trim().toLowerCase();
        final value = DomBindings._str(a[1]);
        if (prop.startsWith('--')) return true;
        if (!isSupportedProperty(prop)) return false;
        final tokens = CssTokenizer(value).tokenize();
        if (tokens.any(
          (t) =>
              t.type == CssTokenType.function && t.value.toLowerCase() == 'var',
        ))
          return true;
        return expandDeclaration(prop, tokens) != null;
      }
      return _supportsCondition(DomBindings._str(a[0]));
    },
    'css.computed': (a) {
      final engine = styleEngine;
      final e = _element(a[0]);
      if (engine == null) return <String, String>{};
      final pseudo = a.length > 1 && a[1] is String
          ? (a[1] as String).replaceAll(':', '')
          : null;
      final style = pseudo == null || pseudo.isEmpty
          ? engine.styleOf(e)
          : engine.pseudoStyleOf(e, pseudo);
      if (style == null) return <String, String>{};
      final out = <String, String>{};
      for (final name in longhands.keys) {
        final v = style[name];
        if (v is RawValue) continue;
        out[name] = cssValueText(v);
      }
      // Common shorthands that scripts read back.
      String side(String p) => out[p] ?? '';
      out['margin'] = [
        for (final s in const ['top', 'right', 'bottom', 'left'])
          side('margin-$s'),
      ].join(' ');
      out['padding'] = [
        for (final s in const ['top', 'right', 'bottom', 'left'])
          side('padding-$s'),
      ].join(' ');
      out['border-radius'] = side('border-top-left-radius');
      out['gap'] = '${side('row-gap')} ${side('column-gap')}';
      out['background'] = side('background-color');
      out['font'] =
          '${side('font-style')} ${side('font-weight')} ${side('font-size')} ${side('font-family')}';
      final box = document.layoutHost?.boxOf(e);
      if (box != null && pseudo == null) {
        if (out['width'] == 'auto') out['width'] = '${box.width}px';
        if (out['height'] == 'auto') out['height'] = '${box.height}px';
      }
      style.customProperties.forEach((k, v) => out[k] = v);
      return out;
    },

    // --- layout ----------------------------------------------------------------
    'layout.box': (a) => document.layoutHost?.boxOf(_element(a[0]))?.toJson(),
    'layout.scrollIntoView': (a) {
      document.layoutHost?.scrollIntoView(
        _element(a[0]),
        smooth: a.length > 1 && a[1] == true,
      );
      return null;
    },
    'layout.elementFromPoint': (a) => describe(
      document.layoutHost?.elementFromPoint(
        ((a[0] as num?) ?? 0).toDouble(),
        ((a[1] as num?) ?? 0).toDouble(),
      ),
    ),
    'layout.elementsFromPoint': (a) => [
      for (final e
          in document.layoutHost?.elementsFromPoint(
                ((a[0] as num?) ?? 0).toDouble(),
                ((a[1] as num?) ?? 0).toDouble(),
              ) ??
              const <Element>[])
        describe(e),
    ],
    'layout.viewport': (a) {
      final h = document.layoutHost;
      final m = environment.media;
      return {
        'scrollX': h?.scrollX ?? 0,
        'scrollY': h?.scrollY ?? 0,
        'width': h?.viewportWidth ?? m.width,
        'height': h?.viewportHeight ?? m.height,
        'documentHeight': h?.documentHeight ?? m.height,
      };
    },
    'layout.scrollTo': (a) {
      document.layoutHost?.scrollTo(
        ((a[0] as num?) ?? 0).toDouble(),
        ((a[1] as num?) ?? 0).toDouble(),
        smooth: a.length > 2 && a[2] == true,
      );
      return null;
    },

    // --- elements: forms, dialogs, details ----------------------------------------
    'el.call': (a) => DomBindings._dom(() {
      final e = _element(a[0]);
      final args = a.length > 2 && a[2] is List ? a[2] as List : const [];
      switch (DomBindings._str(a[1])) {
        case 'checkValidity':
          return e.checkValidity();
        case 'reportValidity':
          final ok = e.checkValidity();
          if (!ok) {
            for (final c in [e, ...e.descendants.whereType<Element>()]) {
              if (c.willValidate) c.userInteracted = true;
              document.notifyStateChanged(c);
            }
          }
          return ok;
        case 'setCustomValidity':
          e.customValidity = args.isEmpty ? '' : '${args[0]}';
          document.notifyStateChanged(e);
          return null;
        case 'requestSubmit':
          final submitter = args.isNotEmpty && args[0] != null
              ? _element(args[0])
              : null;
          if (e.localName != 'form') return null;
          final novalidate =
              e.hasAttribute('novalidate') ||
              (submitter?.hasAttribute('formnovalidate') ?? false);
          for (final c in e.descendants.whereType<Element>()) {
            if (c.willValidate) c.userInteracted = true;
          }
          if (!novalidate && !e.checkValidity()) {
            for (final c in e.descendants.whereType<Element>()) {
              document.notifyStateChanged(c);
            }
            return false;
          }
          e.requestSubmit(trusted: false);
          return true;
        case 'submit':
          if (e.localName == 'form') document.onSubmit?.call(e);
          return null;
        case 'reset':
          e.reset();
          return null;
        case 'show':
          e.show();
          return null;
        case 'showModal':
          e.showModal();
          return null;
        case 'close':
          e.close(args.isEmpty || args[0] == null ? null : '${args[0]}');
          return null;
        case 'requestClose':
          e.requestCancel();
          return null;
        case 'select':
          return null;
        case 'setOptionSelected':
          e.optionSelected = args.isNotEmpty && args[0] == true;
          return null;
        case 'markInteracted':
          e.userInteracted = true;
          document.notifyStateChanged(e);
          return null;
      }
      throw JavaScriptHostError('TypeError', 'unknown element method');
    }),
    'el.validity': (a) {
      final e = _element(a[0]);
      final v = e.validity;
      return {
        'valueMissing': v.valueMissing,
        'typeMismatch': v.typeMismatch,
        'patternMismatch': v.patternMismatch,
        'tooLong': v.tooLong,
        'tooShort': v.tooShort,
        'rangeUnderflow': v.rangeUnderflow,
        'rangeOverflow': v.rangeOverflow,
        'stepMismatch': v.stepMismatch,
        'badInput': v.badInput,
        'customError': v.customError,
        'valid': v.valid,
        'willValidate': e.willValidate,
        'validationMessage': e.validationMessage,
      };
    },
    'el.formControls': (a) {
      final form = _element(a[0]);
      bool listed(Element c) =>
          c.isFormControl ||
          c.localName == 'button' ||
          c.localName == 'fieldset' ||
          c.localName == 'output' ||
          c.localName == 'object';
      final out = <List<Object?>?>[];
      for (final c in form.descendants.whereType<Element>()) {
        if (listed(c)) out.add(describe(c));
      }
      // Controls associated with form="id" outside the form.
      final id = form.getAttribute('id');
      if (id != null && id.isNotEmpty) {
        for (final c in document.querySelectorAll('[form]')) {
          if (c.getAttribute('form') == id && !form.contains(c) && listed(c))
            out.add(describe(c));
        }
      }
      return out;
    },
    'el.selectedOptions': (a) {
      final e = _element(a[0]);
      return [
        for (final o in e.options)
          if (o.optionSelected) describe(o),
      ];
    },

    // --- location and history ------------------------------------------------------
    'loc.get': (a) => _url.toString(),
    'loc.set': (a) {
      final href = DomBindings._str(a[0]);
      final replace = a.length > 1 && a[1] == true;
      final next = _url.resolve(href);
      return _navigate(next, replace: replace, push: !replace);
    },
    'hist.push': (a) {
      final url = a.length > 2 && a[2] != null
          ? _url.resolve(DomBindings._str(a[2]))
          : _url;
      final replace = a[0] == true;
      if (replace) {
        if (_history.isNotEmpty) _history[_historyIndex] = (url, a[1]);
      } else {
        _history.removeRange(_historyIndex + 1, _history.length);
        _history.add((url, a[1]));
        _historyIndex = _history.length - 1;
      }
      _setUrl(url);
      return null;
    },
    'hist.state': (a) => _history.isEmpty ? null : _history[_historyIndex].$2,
    'hist.length': (a) => _history.length,
    'hist.go': (a) {
      final delta = ((a[0] as num?) ?? 0).toInt();
      final target = _historyIndex + delta;
      if (delta == 0 || target < 0 || target >= _history.length) return null;
      scheduleMicrotask(() {
        if (_disposed) return;
        final oldUrl = _url;
        _historyIndex = target;
        final (url, state) = _history[target];
        _setUrl(url);
        window.dispatchEvent(
          Event('popstate', detail: {'state': state})..isTrusted = true,
        );
        if (oldUrl.removeFragment() == url.removeFragment() &&
            oldUrl.fragment != url.fragment) {
          _hashChanged(oldUrl, url);
        }
      });
      return null;
    },

    // --- MutationObserver ------------------------------------------------------------
    'mo.observe': (a) {
      final id = (a[0] as num).toInt();
      final target = _node(a[1]);
      final options = Map<String, Object?>.from(a[2] as Map);
      final list = _observers.putIfAbsent(id, () => []);
      list.add(_Observation(target, options));
      return null;
    },
    'mo.disconnect': (a) {
      final id = (a[0] as num).toInt();
      _observers.remove(id);
      _pendingRecords.remove(id);
      return null;
    },
    'mo.queuedDone': (a) {
      if (_pendingRecords.isNotEmpty) {
        try {
          engine.callGlobal('__nx_queue_mo', _pendingRecords.keys.toList());
        } on JavaScriptException catch (e) {
          onScriptError?.call(e);
        }
      }
      return null;
    },
    'mo.take': (a) {
      final records =
          _pendingRecords.remove((a[0] as num).toInt()) ??
          const <_PendingMutation>[];
      return [
        for (final r in records)
          {
            'type': r.type,
            'target': describe(r.target),
            'addedNodes': [for (final n in r.addedNodes) describe(n)],
            'removedNodes': [for (final n in r.removedNodes) describe(n)],
            'previousSibling': describe(r.previousSibling),
            'nextSibling': describe(r.nextSibling),
            'attributeName': r.attributeName,
            'attributeNamespace': r.attributeNamespace,
            'oldValue': r.oldValue,
          },
      ];
    },

    // --- network ---------------------------------------------------------------------
    'net.fetch': (a) {
      final id = (a[0] as num).toInt();
      final r = Map<String, Object?>.from(a[1] as Map);
      final Uri url;
      try {
        url = _url.resolve(DomBindings._str(r['url']));
      } on FormatException {
        _asyncDone(id, error: 'Invalid URL');
        return null;
      }
      final bodyId = r['body'] as num?;
      final request = NetworkRequest(
        url: url,
        method: (r['method'] as String? ?? 'GET').toUpperCase(),
        headers: [
          for (final h in (r['headers'] as List? ?? const []))
            ('${(h as List)[0]}', '${h[1]}'),
        ],
        body: bodyId == null ? null : NativeBuffers.take(bodyId.toInt()),
        timeout: r['timeout'] is num && (r['timeout'] as num) > 0
            ? Duration(milliseconds: (r['timeout'] as num).toInt())
            : null,
      );
      if (_traceHost) {
        // ignore: avoid_print
        print('HOST_FETCH start id=$id url=$url method=${request.method}');
      }
      network
          .fetch(request)
          .then(
            (res) {
              if (_traceHost) {
                // ignore: avoid_print
                print(
                  'HOST_FETCH end id=$id status=${res.status} '
                  'bytes=${res.body.length} url=$url',
                );
              }
              if (_aborted.remove(id)) return;
              _asyncDone(
                id,
                ok: {
                  'status': res.status,
                  'statusText': res.statusText,
                  'headers': [
                    for (final (k, v) in res.headers) [k, v],
                  ],
                  'body': NativeBuffers.put(res.body),
                  'url': res.url.toString(),
                  'redirected': res.redirected,
                },
              );
            },
            onError: (Object e) {
              if (_traceHost) {
                // ignore: avoid_print
                print('HOST_FETCH error id=$id url=$url error=$e');
              }
              if (_aborted.remove(id)) return;
              _asyncDone(
                id,
                error: e is TimeoutException ? 'timeout' : e.toString(),
              );
            },
          );
      return null;
    },
    'net.abort': (a) {
      _aborted.add((a[0] as num).toInt());
      return null;
    },
    'ws.open': (a) {
      final id = (a[0] as num).toInt();
      final Uri url;
      try {
        url = Uri.parse(DomBindings._str(a[1]));
      } on FormatException {
        throw JavaScriptHostError('SyntaxError', 'invalid WebSocket URL');
      }
      if (!(url.isScheme('ws') || url.isScheme('wss'))) {
        throw JavaScriptHostError(
          'SyntaxError',
          "The URL's scheme must be either 'ws' or 'wss'.",
        );
      }
      final protocols = [for (final p in (a[2] as List? ?? const [])) '$p'];
      network
          .connect(url, protocols)
          .then(
            (socket) {
              if (_disposed) {
                socket.close();
                return;
              }
              _sockets[id] = socket;
              _socketEvent(id, {'type': 'open', 'protocol': socket.protocol});
              socket.messages.listen(
                (m) => _socketEvent(
                  id,
                  m is String
                      ? {'type': 'message', 'data': m}
                      : {
                          'type': 'message',
                          'binary': base64Bytes(m as Uint8List),
                        },
                ),
                onDone: () {
                  _sockets.remove(id);
                  _socketEvent(id, {
                    'type': 'close',
                    'code': socket.closeCode ?? 1005,
                    'reason': socket.closeReason ?? '',
                    'wasClean': socket.closeCode != null,
                  });
                },
                onError: (Object e) =>
                    _socketEvent(id, {'type': 'error', 'message': '$e'}),
              );
            },
            onError: (Object e) {
              _socketEvent(id, {'type': 'error', 'message': '$e'});
              _socketEvent(id, {
                'type': 'close',
                'code': 1006,
                'reason': '',
                'wasClean': false,
              });
            },
          );
      return null;
    },
    'ws.send': (a) {
      final s = _sockets[(a[0] as num).toInt()];
      if (s == null)
        throw JavaScriptHostError('InvalidStateError', 'WebSocket is not open');
      final data = a[1];
      if (a.length > 2 && a[2] == true) {
        s.send(bytesFromBase64(data as String));
      } else {
        s.send('$data');
      }
      return null;
    },
    'ws.close': (a) {
      final s = _sockets[(a[0] as num).toInt()];
      s?.close(
        a.length > 1 && a[1] is num ? (a[1] as num).toInt() : null,
        a.length > 2 ? a[2] as String? : null,
      );
      return null;
    },

    // --- canvas 2D ---------------------------------------------------------------------
    'canvas.draw': (a) {
      final el = _element(a[0]);
      final ops = a[3] is List ? a[3] as List<Object?> : const <Object?>[];
      if (ops.length > 200000)
        throw JavaScriptHostError(
          'QuotaExceededError',
          'too many canvas commands in one frame',
        );
      document.drawCanvas(
        el,
        ((a[1] as num?) ?? 300).toInt(),
        ((a[2] as num?) ?? 150).toInt(),
        ops,
      );
      return null;
    },
    'canvas.measure': (a) {
      final font = DomBindings._str(a[0]);
      final text = DomBindings._str(a[1]);
      final host = document.canvasHost;
      if (host != null) return host.measureText(font, text);
      final size =
          double.tryParse(
            RegExp(r'([\d.]+)px').firstMatch(font)?.group(1) ?? '',
          ) ??
          10;
      return {
        'width': text.length * size * 0.55,
        'ascent': size * 0.8,
        'descent': size * 0.2,
      };
    },

    // --- WebGL canvases ------------------------------------------------------------------
    'canvas.surface': (a) {
      final element = _node(a[0]);
      if (element is! Element || element.localName != 'canvas') {
        throw JavaScriptHostError('TypeError', 'not a canvas');
      }
      final surface = (a[1] as num).toInt();
      final previous = canvasSurfaces[element];
      if (previous != null) GlSurfaces.release(previous);
      canvasSurfaces[element] = surface;
      _surfaces.add(surface);
      document.notify(MutationRecord.property(element, 'surface'));
      return null;
    },

    // --- message ports and dedicated workers -------------------------------------------
    'port.pair': (a) {
      final (x, y) = messaging.pair();
      return [x, y];
    },
    'port.post': (a) {
      messaging.post((a[0] as num).toInt(), DomBindings._str(a[1]), [
        for (final p in (a.length > 2 ? a[2] as List? ?? const [] : const []))
          (p as num).toInt(),
      ]);
      return null;
    },
    'port.adopt': (a) {
      messaging.adopt((a[0] as num).toInt());
      return null;
    },
    'port.close': (a) {
      messaging.close((a[0] as num).toInt());
      return null;
    },
    'worker.create': (a) {
      final o = Map<String, Object?>.from(a[1] as Map? ?? const {});
      try {
        final (id, port) = messaging.startWorker(
          WorkerRequest(
            url: DomBindings._str(a[0]),
            type: o['type'] == 'module' ? 'module' : 'classic',
            name: o['name'] is String ? o['name'] as String : '',
            source: o['source'] as String?,
          ),
        );
        return [id, port];
      } on UnsupportedError catch (e) {
        throw JavaScriptHostError(
          'NotSupportedError',
          e.message ?? 'workers are not available',
        );
      }
    },
    'worker.terminate': (a) {
      messaging.terminateWorker((a[0] as num).toInt());
      return null;
    },
    'worker.selfClose': (a) {
      workerScope?.onClose?.call();
      return null;
    },
    'worker.importScript': (a) =>
        workerScope?.importScript?.call(DomBindings._str(a[0])),

    // --- platform services -------------------------------------------------------------
    'clip.write': (a) {
      final id = (a[0] as num).toInt();
      final write = services.writeClipboard;
      if (!document.hasTransientActivation) {
        _asyncDone(
          id,
          error: 'NotAllowedError: clipboard writes require a user gesture',
        );
      } else if (write == null) {
        _asyncDone(id, error: 'NotAllowedError: clipboard is not available');
      } else {
        write(DomBindings._str(a[1])).then(
          (_) => _asyncDone(id, ok: true),
          onError: (Object e) => _asyncDone(id, error: '$e'),
        );
      }
      return null;
    },
    'clip.read': (a) {
      final id = (a[0] as num).toInt();
      final read = services.readClipboard;
      if (read == null) {
        _asyncDone(id, error: 'NotAllowedError: clipboard is not available');
      } else {
        read().then(
          (t) => _asyncDone(id, ok: t ?? ''),
          onError: (Object e) => _asyncDone(id, error: '$e'),
        );
      }
      return null;
    },
    'nav.vibrate': (a) {
      final f = services.vibrate;
      if (f == null || !document.hasTransientActivation) return false;
      final pattern = a[0];
      return f(
        pattern is List
            ? [for (final p in pattern) (p as num).toInt()]
            : [((pattern as num?) ?? 0).toInt()],
      );
    },
    'nav.alert': (a) {
      services.alert?.call(a.isEmpty ? '' : '${a[0]}');
      return null;
    },
    'nav.capabilities': (a) => {
      'clipboard': services.writeClipboard != null,
      'vibrate': services.vibrate != null,
      'network': network is! DeniedNetwork,
    },
  };

  bool _supportsCondition(String text) {
    var t = text.trim();
    if (t.startsWith('(') && t.endsWith(')')) {
      // Single parenthesized declaration: (prop: value)
      final inner = t.substring(1, t.length - 1);
      if (!inner.contains('(') && inner.contains(':')) {
        final colon = inner.indexOf(':');
        return _supportsDecl(
          inner.substring(0, colon),
          inner.substring(colon + 1),
        );
      }
    }
    if (t.toLowerCase().startsWith('not '))
      return !_supportsCondition(t.substring(4));
    // `a and b` / `a or b` at the top level.
    final parts = <String>[];
    var depth = 0, start = 0;
    String? op;
    for (var i = 0; i < t.length; i++) {
      final c = t[i];
      if (c == '(') depth++;
      if (c == ')') depth--;
      if (depth == 0) {
        for (final word in const [' and ', ' or ']) {
          if (t.startsWith(word, i)) {
            parts.add(t.substring(start, i));
            op = word.trim();
            start = i + word.length;
          }
        }
      }
    }
    if (parts.isEmpty) {
      if (t.startsWith('selector(') && t.endsWith(')')) {
        return SelectorList.tryParse(t.substring(9, t.length - 1)) != null;
      }
      final colon = t.indexOf(':');
      return colon > 0 &&
          _supportsDecl(t.substring(0, colon), t.substring(colon + 1));
    }
    parts.add(t.substring(start));
    return op == 'and'
        ? parts.every(_supportsCondition)
        : parts.any(_supportsCondition);
  }

  bool _supportsDecl(String prop, String value) {
    final p = prop.trim().toLowerCase();
    if (p.startsWith('--')) return true;
    if (!isSupportedProperty(p)) return false;
    return expandDeclaration(p, CssTokenizer(value.trim()).tokenize()) != null;
  }

  void _asyncDone(int id, {Object? ok, String? error}) {
    if (_disposed || engine.isDisposed) return;
    try {
      engine.callGlobal('__nx_async', {
        'id': id,
        if (error != null) 'error': error else 'ok': ok,
      });
    } on JavaScriptException catch (e) {
      onScriptError?.call(e);
    }
  }

  void _socketEvent(int id, Map<String, Object?> event) {
    if (_disposed || engine.isDisposed) return;
    try {
      engine.callGlobal('__nx_ws', {'id': id, ...event});
    } on JavaScriptException catch (e) {
      onScriptError?.call(e);
    }
  }

  void _setUrl(Uri url) {
    _url = url;
    final f = url.fragment;
    document.targetId = f.isEmpty ? null : Uri.decodeComponent(f);
  }

  void _hashChanged(Uri oldUrl, Uri newUrl) {
    window.dispatchEvent(
      Event(
        'hashchange',
        detail: {'oldURL': oldUrl.toString(), 'newURL': newUrl.toString()},
      )..isTrusted = true,
    );
  }

  /// Same-document (fragment) navigation updates the URL, `:target`, history
  /// and scroll position and fires `hashchange`; anything else is handed to
  /// the embedder. Returns whether the navigation stayed in the document.
  bool _navigate(Uri next, {required bool replace, required bool push}) {
    final current = _url;
    if (next.removeFragment() == current.removeFragment() && next.hasFragment) {
      if (push && next != current) {
        _history.removeRange(_historyIndex + 1, _history.length);
        _history.add((next, null));
        _historyIndex = _history.length - 1;
      } else if (_history.isNotEmpty) {
        _history[_historyIndex] = (next, _history[_historyIndex].$2);
      }
      _setUrl(next);
      final id = document.targetId;
      final target = id == null
          ? null
          : (document.getElementById(id) ??
                document.querySelector('a[name="${id.replaceAll('"', '')}"]'));
      if (target != null) {
        document.layoutHost?.scrollIntoView(target);
      } else if (next.fragment.isEmpty || next.fragment == 'top') {
        document.layoutHost?.scrollTo(0, 0);
      }
      if (next.fragment != current.fragment) {
        scheduleMicrotask(() {
          if (!_disposed) _hashChanged(current, next);
        });
      }
      return true;
    }
    services.openUrl?.call(next);
    return false;
  }
}
