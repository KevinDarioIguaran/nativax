/*---
description: Deliberately calls $DONE with an error.
flags: [async]
---*/
Promise.resolve().then(function () {
  $DONE(new Test262Error("deliberate async failure"));
});
