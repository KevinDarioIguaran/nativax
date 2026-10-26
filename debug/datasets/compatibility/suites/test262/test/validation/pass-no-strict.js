/*---
description: The with statement is allowed in sloppy mode code (ECMA-262 14.11).
flags: [noStrict]
---*/
var o = { v: 3 };
var seen;
with (o) { seen = v; }
assert.sameValue(seen, 3);
