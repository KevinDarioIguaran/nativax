// Minimal include used by the validation subset (not upstream compareArray.js).
function compareArray(a, b) {
  if (b.length !== a.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!assert._isSameValue(b[i], a[i])) return false;
  }
  return true;
}
assert.compareArray = function (actual, expected, message) {
  if (!compareArray(actual, expected)) {
    throw new Test262Error((message ? message + " " : "") + "Expected arrays to be equal");
  }
};
