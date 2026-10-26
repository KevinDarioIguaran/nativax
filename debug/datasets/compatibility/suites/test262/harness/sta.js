// Minimal Test262 harness written for the NativaX runner validation subset.
// Not a copy of upstream harness/sta.js; it provides the same names.
function Test262Error(message) {
  this.message = message || "";
}
Test262Error.prototype.name = "Test262Error";
Test262Error.prototype.toString = function () {
  return "Test262Error: " + this.message;
};
Test262Error.thrower = function (message) {
  throw new Test262Error(message);
};
function $DONOTEVALUATE() {
  throw "Test262: This statement should not be evaluated.";
}
