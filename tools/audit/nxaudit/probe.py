"""JavaScript probe shared by both engines, plus the page instrumentation.

One source for NativaX and Chromium so the two measurements cannot drift.
The probe reads every element carrying `data-nx` (the structural JSON path
written by `compile.py`).
"""
from __future__ import annotations

import json

from .catalog import PROBED_PROPERTIES

# Injected first in <head> of every compiled page: script errors and an event
# log recorded identically in both engines.
INSTRUMENTATION = r"""
window.__nxErrors = [];
window.addEventListener('error', function (e) {
  window.__nxErrors.push(String(e && e.message || e));
});
window.__nxEvents = [];
['click', 'input', 'change', 'focusin', 'keydown', 'submit'].forEach(function (t) {
  document.addEventListener(t, function (e) {
    var el = e.target;
    window.__nxEvents.push(t + ':' + ((el && el.id) || '?'));
    if (t === 'submit' && e.preventDefault) e.preventDefault();
  }, true);
});
"""


def probe_source() -> str:
    props = json.dumps(PROBED_PROPERTIES)
    return r"""
globalThis.__nxProbe = function () {
  var PROPS = %s;
  var r1 = function (v) { return Math.round((v || 0) * 10) / 10; };
  var nodes = document.querySelectorAll('[data-nx]');
  var elements = [];
  for (var i = 0; i < nodes.length; i++) {
    var el = nodes[i];
    var r = el.getBoundingClientRect();
    var cs = getComputedStyle(el);
    var styles = {};
    for (var p = 0; p < PROPS.length; p++) {
      var v = cs.getPropertyValue(PROPS[p]);
      if (v !== null && v !== undefined && v !== '') styles[PROPS[p]] = String(v).trim();
    }
    var item = {
      id: el.id || null,
      nx: el.getAttribute('data-nx'),
      type: el.getAttribute('data-nx-type'),
      tag: el.tagName.toLowerCase(),
      rect: [r1(r.left), r1(r.top), r1(r.width), r1(r.height)],
      client: [el.clientWidth || 0, el.clientHeight || 0],
      scroll: [el.scrollWidth || 0, el.scrollHeight || 0],
      styles: styles,
      text: (el.children.length === 0 ? (el.textContent || '') : '').slice(0, 80)
    };
    if ('value' in el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.tagName === 'SELECT')) item.value = String(el.value);
    if (el.type === 'checkbox') item.checked = !!el.checked;
    elements.push(item);
  }
  var a = document.activeElement;
  var de = document.documentElement, b = document.body;
  return JSON.stringify({
    viewport: [window.innerWidth, window.innerHeight],
    document: [Math.max(de ? de.scrollWidth : 0, b ? b.scrollWidth : 0),
               Math.max(de ? de.scrollHeight : 0, b ? b.scrollHeight : 0)],
    focused: a && a.id ? a.id : null,
    events: (window.__nxEvents || []).slice(0, 200),
    errors: (window.__nxErrors || []).slice(0, 40),
    elements: elements
  });
};
""" % props
