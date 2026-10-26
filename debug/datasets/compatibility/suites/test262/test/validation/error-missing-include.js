/*---
description: >
  The include does not exist in the harness directory. This is a harness
  problem, not an engine result, so the runner must report ERROR.
includes: [doesNotExist.js]
---*/
assert.sameValue(1, 1);
