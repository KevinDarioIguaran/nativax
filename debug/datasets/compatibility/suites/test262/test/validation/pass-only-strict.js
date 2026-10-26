/*---
description: >
  Assigning to an unresolvable reference throws a ReferenceError in strict
  mode code (ECMA-262 6.2.5.6 PutValue step 3.a). Only passes if the runner
  really runs the test as strict mode code.
flags: [onlyStrict]
---*/
assert.throws(ReferenceError, function () {
  nativaxValidationUndeclared = 1;
});
