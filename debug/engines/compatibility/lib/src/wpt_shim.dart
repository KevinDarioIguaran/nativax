/// Minimal testharness.js-compatible shim.
///
/// WPT tests are written against the real `testharness.js`. Running that file
/// inside NativaX would require a much larger browser surface, so the runner
/// provides the commonly used subset (test/async_test/promise_test and the
/// assertion helpers) and reports any test that depends on an API the shim
/// does not implement as SKIP.
const wptShim = r'''
(() => {
'use strict';
const host = __nx.host;
const state = { pending: 0, tests: [], done: false };
Object.defineProperty(globalThis, '__wpt', { value: state, enumerable: false });

class AssertionError extends Error {
  constructor(message) { super(message || 'assertion failed'); this.name = 'AssertionError'; }
}
class PreconditionError extends Error {
  constructor(message) { super(message || 'precondition failed'); this.name = 'PreconditionError'; }
}
globalThis.AssertionError = AssertionError;

const report = (name, status, message) => {
  state.tests.push({ name: String(name), status, message: message || '' });
  host('wpt.result', String(name), status, message || '');
};
const finishIfDone = () => {
  if (!state.done && state.pending === 0) {
    state.done = true;
    host('wpt.done');
  }
};
// testharness.js uses (func, name, properties); the older form
// (name, func) still appears in a few tests. Normalize both.
const normal = (a, b) => typeof a === 'function'
  ? { fn: a, name: typeof b === 'string' ? b : '' }
  : { fn: b, name: typeof a === 'string' ? a : '' };
const runSync = (name, fn) => {
  const cleanups = [];
  let stepError = null;
  const t = {
    add_cleanup(f) { if (typeof f === 'function') cleanups.push(f); },
    step(f) { try { f(); } catch (e) { stepError = e; throw e; } },
    step_func(f) { return (...args) => { try { return f.apply(this, args); } catch (e) { stepError = e; throw e; } }; },
    step_func_done(f) { return (...args) => { try { if (f) f.apply(this, args); } catch (e) { stepError = e; throw e; } }; },
    unreached_func(desc) { return () => { throw new AssertionError(desc || 'unreachable'); }; },
    step_timeout(f, ms) { setTimeout(() => { try { f(); } catch (e) { stepError = e; } }, ms); },
  };
  try {
    fn.call(t, t);
    if (stepError) throw stepError;
    report(name, 'PASS');
  } catch (e) {
    if (e instanceof PreconditionError) report(name, 'SKIP', e.message);
    else report(name, 'FAIL', e && e.message ? String(e.message) + (e.stack ? '\n' + e.stack : '') : (e && e.stack ? e.stack : String(e)));
  } finally {
    for (let i = cleanups.length - 1; i >= 0; i--) {
      try { cleanups[i](); } catch (_) {}
    }
  }
};

globalThis.test = (a, b) => {
  const { fn, name } = normal(a, b);
  if (typeof fn !== 'function') return report(name, 'FAIL', 'test() without a function');
  runSync(name, fn);
};

globalThis.generate_tests = (fn, tests) => {
  for (const item of tests) {
    if (!Array.isArray(item)) continue;
    const name = item[0];
    const args = item.slice(1);
    if (typeof fn === 'function') runSync(String(name), () => fn(...args));
  }
};
globalThis.promise_test = (a, b) => {
  const { fn, name } = normal(a, b);
  state.pending++;
  const cleanups = [];
  let finished = false;
  const finish = (kind, e) => {
    if (finished) return;
    finished = true;
    for (let i = cleanups.length - 1; i >= 0; i--) {
      try { cleanups[i](); } catch (_) {}
    }
    if (kind === 'PASS') report(name, 'PASS');
    else if (e instanceof PreconditionError) report(name, 'SKIP', e.message);
    else report(name, 'FAIL', e && e.message ? String(e.message) + (e.stack ? '\n' + e.stack : '') : (e && e.stack ? e.stack : String(e)));
    state.pending--;
    finishIfDone();
  };
  const t = {
    add_cleanup(f) { if (typeof f === 'function') cleanups.push(f); },
    step(f) { try { f(); } catch (e) { finish('FAIL', e); throw e; } },
    step_func(f) { return (...args) => t.step(() => f.apply(this, args)); },
    unreached_func(desc) { return () => { throw new AssertionError(desc || 'unreachable'); }; },
    step_timeout(f, ms) { setTimeout(() => t.step(f), ms); },
  };
  Promise.resolve().then(() => fn.call(t, t)).then(
    () => finish('PASS'),
    (e) => finish('FAIL', e),
  );
};

globalThis.async_test = (a, b) => {
  const { fn, name } = normal(a, b);
  state.pending++;
  let finished = false;
  const cleanups = [];
  const t = {
    add_cleanup(f) { if (typeof f === 'function') cleanups.push(f); },
    step(f) {
      try { f(); } catch (e) { t.fail(e); }
    },
    step_func(f) { return (...args) => t.step(() => f.apply(this, args)); },
    unreached_func(desc) { return () => { throw new AssertionError(desc || 'unreachable'); }; },
    step_func_done(f) { return (...args) => { try { if (f) f.apply(this, args); t.done(); } catch (e) { t.fail(e); } }; },
    step_timeout(f, ms) { setTimeout(() => t.step(f), ms); },
    done() {
      if (finished) return;
      finished = true;
      for (let i = cleanups.length - 1; i >= 0; i--) {
        try { cleanups[i](); } catch (_) {}
      }
      report(name, 'PASS');
      state.pending--;
      finishIfDone();
    },
    fail(e) {
      if (finished) return;
      finished = true;
      if (e instanceof PreconditionError) report(name, 'SKIP', e.message);
      else report(name, 'FAIL', e && e.message ? String(e.message) + (e.stack ? '\n' + e.stack : '') : (e && e.stack ? e.stack : String(e)));
      state.pending--;
      finishIfDone();
    },
  };
  if (typeof fn === 'function') { try { fn.call(t, t); } catch (e) { t.fail(e); } }
  return t;
};

globalThis.setup = (arg) => {
  if (typeof arg === 'function') {
    try { arg(); } catch (e) { report('setup', 'FAIL', String(e)); }
  }
  // setup({explicit_done, single_test, ...}) options are accepted and ignored.
};
globalThis.done = () => finishIfDone();
globalThis.add_completion_callback = () => {};
globalThis.step_func = (fn) => () => fn();
globalThis.step_timeout = (fn, ms) => setTimeout(fn, ms);

const assert = (ok, message) => { if (!ok) throw new AssertionError(message); };
const same = (a, b) => Object.is(a, b) || (a === b);
globalThis.assert_true = (v, m) => assert(v === true, m || `expected true, got ${v}`);
globalThis.assert_false = (v, m) => assert(v === false, m || `expected false, got ${v}`);
globalThis.assert_equals = (a, b, m) => {
  if (!same(a, b)) throw new AssertionError(`${m || 'assert_equals'}: expected ${String(b)}, got ${String(a)}`);
};
globalThis.assert_not_equals = (a, b, m) => {
  if (same(a, b)) throw new AssertionError(`${m || 'assert_not_equals'}: both are ${String(a)}`);
};
globalThis.assert_array_equals = (a, b, m) => {
  assert(a.length === b.length, `${m || 'assert_array_equals'}: length ${a.length} != ${b.length}`);
  for (let i = 0; i < a.length; i++) {
    if (!same(a[i], b[i])) throw new AssertionError(`${m || 'assert_array_equals'}[${i}]: ${String(a[i])} != ${String(b[i])}`);
  }
};
globalThis.assert_object_equals = (a, b, m) => {
  const ja = JSON.stringify(a), jb = JSON.stringify(b);
  assert(ja === jb, `${m || 'assert_object_equals'}: ${ja} != ${jb}`);
};
globalThis.assert_in_array = (v, a, m) => assert(a.indexOf(v) >= 0, m || `${String(v)} not in array`);
globalThis.assert_not_in_array = (v, a, m) => assert(a.indexOf(v) < 0, m || `${String(v)} unexpectedly in array`);
globalThis.assert_exists = (v, m) => assert(v !== undefined && v !== null, m || 'value does not exist');
globalThis.assert_own_property = (o, p, m) => assert(Object.prototype.hasOwnProperty.call(o, p), m || `missing own property ${p}`);
globalThis.assert_inherits = (o, p, m) => assert(p in o, m || `missing inherited property ${p}`);
globalThis.assert_readonly = (o, p, m) => {
  const d = Object.getOwnPropertyDescriptor(o, p);
  assert(d && !d.writable && !d.set, m || `${p} is not readonly`);
};
globalThis.assert_unreached = (m) => { throw new AssertionError(m || 'unreached'); };
globalThis.assert_implements = (v, m) => assert(!!v, m || 'required feature is not implemented');
// testharness.js reports PRECONDITION_FAILED here; the runner maps it to SKIP.
globalThis.assert_implements_optional = (v, m) => { if (!v) throw new PreconditionError(m || 'optional feature is not implemented'); };
globalThis.assert_precondition = (v, m) => { if (!v) throw new PreconditionError(m); };
globalThis.assert_throws_js = (ctor, fn, m) => {
  try { fn(); } catch (e) {
    if (e instanceof ctor) return;
    throw new AssertionError(`${m || 'assert_throws_js'}: expected ${ctor.name}, got ${e && e.name}`);
  }
  throw new AssertionError(`${m || 'assert_throws_js'}: did not throw`);
};
const exceptionNames = {
  INDEX_SIZE_ERR: 'IndexSizeError',
  DOMSTRING_SIZE_ERR: 'DOMStringSizeError',
  HIERARCHY_REQUEST_ERR: 'HierarchyRequestError',
  WRONG_DOCUMENT_ERR: 'WrongDocumentError',
  INVALID_CHARACTER_ERR: 'InvalidCharacterError',
  NO_DATA_ALLOWED_ERR: 'NoDataAllowedError',
  NO_MODIFICATION_ALLOWED_ERR: 'NoModificationAllowedError',
  NOT_FOUND_ERR: 'NotFoundError',
  NOT_SUPPORTED_ERR: 'NotSupportedError',
  INUSE_ATTRIBUTE_ERR: 'InUseAttributeError',
  INVALID_STATE_ERR: 'InvalidStateError',
  SYNTAX_ERR: 'SyntaxError',
  INVALID_MODIFICATION_ERR: 'InvalidModificationError',
  NAMESPACE_ERR: 'NamespaceError',
  INVALID_ACCESS_ERR: 'InvalidAccessError',
  VALIDATION_ERR: 'ValidationError',
  TYPE_MISMATCH_ERR: 'TypeMismatchError',
  SECURITY_ERR: 'SecurityError',
  NETWORK_ERR: 'NetworkError',
  ABORT_ERR: 'AbortError',
  URL_MISMATCH_ERR: 'URLMismatchError',
  QUOTA_EXCEEDED_ERR: 'QuotaExceededError',
  TIMEOUT_ERR: 'TimeoutError',
  INVALID_NODE_TYPE_ERR: 'InvalidNodeTypeError',
  DATA_CLONE_ERR: 'DataCloneError',
};
globalThis.assert_throws_dom = (name, fn, m) => {
  const expected = exceptionNames[name] || name;
  try { fn(); } catch (e) {
    if (e && e.name === expected) return;
    throw new AssertionError(`${m || 'assert_throws_dom'}: expected ${name}, got ${e && e.name}`);
  }
  throw new AssertionError(`${m || 'assert_throws_dom'}: did not throw`);
};
globalThis.assert_throws_exactly = (expected, fn, m) => {
  try { fn(); } catch (e) { assert(e === expected, m || 'wrong exception'); return; }
  throw new AssertionError(`${m || 'assert_throws_exactly'}: did not throw`);
};
globalThis.promise_rejects_js = (ctor, promise, m) => promise.then(
  () => { throw new AssertionError(`${m || 'promise_rejects_js'}: resolved`); },
  (e) => { if (!(e instanceof ctor)) throw new AssertionError(`${m || 'promise_rejects_js'}: wrong rejection`); },
);
globalThis.promise_rejects_dom = (name, promise, m) => promise.then(
  () => { throw new AssertionError(`${m || 'promise_rejects_dom'}: resolved`); },
  (e) => { if (!(e && e.name === name)) throw new AssertionError(`${m || 'promise_rejects_dom'}: wrong rejection`); },
);
globalThis.assert_greater_than = (a, b, m) => assert(a > b, m || `${a} is not greater than ${b}`);
globalThis.assert_greater_than_equal = (a, b, m) => assert(a >= b, m || `${a} is not greater than or equal to ${b}`);
globalThis.assert_less_than = (a, b, m) => assert(a < b, m || `${a} is not less than ${b}`);
globalThis.assert_less_than_equal = (a, b, m) => assert(a <= b, m || `${a} is not less than or equal to ${b}`);
globalThis.assert_approx_equals = (a, b, eps, m) => assert(Math.abs(a - b) <= eps, m || `${a} is not approximately ${b}`);
globalThis.promise_rejects_exactly = (expected, promise, m) => promise.then(
  () => { throw new AssertionError(`${m || 'promise_rejects_exactly'}: resolved`); },
  (e) => { if (e !== expected) throw new AssertionError(`${m || 'promise_rejects_exactly'}: wrong rejection`); },
);
globalThis.assert_regexp_match = (actual, regex, m) => assert(regex.test(String(actual)), m || `${actual} does not match ${regex}`);
globalThis.format_value = (v) => {
  try { return JSON.stringify(v); } catch (e) { return String(v); }
};

const checkDone = () => finishIfDone();
Object.defineProperty(globalThis, '__wptCheckDone', { value: checkDone, enumerable: false });
})();
''';
