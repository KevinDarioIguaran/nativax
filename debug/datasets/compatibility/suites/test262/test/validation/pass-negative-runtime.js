/*---
description: Reading a property of null throws a TypeError (ECMA-262 7.1.18 ToObject).
negative:
  phase: runtime
  type: TypeError
---*/
null.x;
