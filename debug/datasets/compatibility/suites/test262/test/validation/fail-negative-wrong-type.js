/*---
description: Deliberately wrong test; a RangeError is thrown where a TypeError is expected.
negative:
  phase: runtime
  type: TypeError
---*/
throw new RangeError("wrong type");
