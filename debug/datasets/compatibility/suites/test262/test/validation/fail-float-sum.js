/*---
description: >
  Deliberately wrong expectation. 0.1 + 0.2 is 0.30000000000000004 in IEEE 754
  binary64 (ECMA-262 6.1.6.1), so this assertion must fail.
---*/
assert.sameValue(0.1 + 0.2, 0.3);
