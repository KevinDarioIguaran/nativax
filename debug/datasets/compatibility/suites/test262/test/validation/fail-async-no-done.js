/*---
description: Deliberately never calls $DONE; the runner must time out and report FAIL.
flags: [async]
---*/
Promise.resolve();
