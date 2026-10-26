// Minimal Test262 assertion helpers written for the NativaX runner
// validation subset. Not a copy of upstream harness/assert.js.
function assert(value, message) {
  if (value !== true) {
    throw new Test262Error(message || "Expected true but got " + String(value));
  }
}
assert._isSameValue = function (a, b) {
  if (a === b) return a !== 0 || 1 / a === 1 / b;
  return a !== a && b !== b;
};
assert.sameValue = function (actual, expected, message) {
  if (!assert._isSameValue(actual, expected)) {
    throw new Test262Error((message ? message + " " : "") +
      "Expected SameValue(" + String(actual) + ", " + String(expected) + ") to be true");
  }
};
assert.notSameValue = function (actual, unexpected, message) {
  if (assert._isSameValue(actual, unexpected)) {
    throw new Test262Error((message ? message + " " : "") +
      "Expected SameValue(" + String(actual) + ", " + String(unexpected) + ") to be false");
  }
};
assert.throws = function (expectedErrorConstructor, func, message) {
  try {
    func();
  } catch (thrown) {
    if (typeof thrown !== "object" || thrown === null || thrown.constructor !== expectedErrorConstructor) {
      throw new Test262Error((message ? message + " " : "") +
        "Expected a " + expectedErrorConstructor.name + " but got a different error");
    }
    return;
  }
  throw new Test262Error((message ? message + " " : "") +
    "Expected a " + expectedErrorConstructor.name + " to be thrown but no exception was thrown at all");
};
