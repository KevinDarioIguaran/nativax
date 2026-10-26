/*---
description: A resolved promise reaction runs and calls $DONE without an error.
flags: [async]
---*/
Promise.resolve(41).then(function (v) {
  if (v + 1 !== 42) throw new Test262Error("wrong value");
}).then($DONE, $DONE);
