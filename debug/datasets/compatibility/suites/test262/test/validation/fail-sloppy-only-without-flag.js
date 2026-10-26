/*---
description: >
  Deliberately missing noStrict flag. `with` is an early SyntaxError in strict
  mode code (ECMA-262 14.11.1), and a test without flags must run in both
  modes, so the strict run must fail.
---*/
var o = { v: 3 };
with (o) { v; }
