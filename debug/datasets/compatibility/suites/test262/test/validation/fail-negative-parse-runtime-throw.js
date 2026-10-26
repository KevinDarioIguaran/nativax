/*---
description: >
  Deliberately wrong test: it expects a parse-phase SyntaxError but the source
  is valid and only throws a SyntaxError at runtime. A runtime throw does not
  satisfy a parse-phase negative expectation, so the runner must report FAIL.
negative:
  phase: parse
  type: SyntaxError
---*/
throw new SyntaxError("thrown at runtime");
