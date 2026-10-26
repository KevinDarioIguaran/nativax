/*---
description: Proper tail calls are an explicit QuickJS-ng engine gap.
features: [tail-call-optimization]
---*/
function f(n) { "use strict"; return n === 0 ? 0 : f(n - 1); }
f(10);
