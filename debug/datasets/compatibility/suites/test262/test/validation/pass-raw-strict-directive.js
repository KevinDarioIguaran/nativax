'use strict';
var public = 1;
/*---
description: >
  `public` is a reserved word in strict mode code (ECMA-262 12.7.2). The
  directive is the first statement, so a raw test must be evaluated without
  any prefix for the SyntaxError to occur.
flags: [raw]
negative:
  phase: parse
  type: SyntaxError
---*/
