/*---
description: Uses an include from the harness directory.
includes: [compareArray.js]
---*/
assert.compareArray([1, 2, 3].map(function (x) { return x * 2; }), [2, 4, 6]);
