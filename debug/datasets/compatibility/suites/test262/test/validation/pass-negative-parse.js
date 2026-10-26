/*---
description: "`var = 1` is a SyntaxError (ECMA-262 14.3.2 grammar)."
negative:
  phase: parse
  type: SyntaxError
---*/
$DONOTEVALUATE();
var = 1;
