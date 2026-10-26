---
name: nativa-security
description: Use when adding or reviewing host APIs, parser or runtime limits, JS-Dart bridge code, storage, workers, or handling of hostile HTML, CSS, and JavaScript.
---

# Nativa security

Read `references/security.md` before changing a trust boundary or resource
limit.

## Workflow

1. Identify the asset and the hostile input: process/UI, memory, stack, DOM,
   parser, storage, host, or events.
2. Verify the configured limit and what happens when it is exceeded.
3. For bridge changes, confirm:
   - scripts receive only numeric ids, scalars, and JSON;
   - arguments and results are validated;
   - host errors are generic and contain no Dart paths or stacks;
   - `app.invoke` handlers treat arguments as untrusted.
4. Add or update an abuse test in `debug/engines/security` for every new limit or host
   API.
5. State what is not protected. There is no OS sandbox, document isolation, CSP,
   or origin policy.

## Rules

- Never add an API that reads host paths, environment variables, or host memory.
- Never expose Dart objects or `JSValue` to scripts.
- Never run destructive tests by default without limits.
- Never claim isolation that the runtime does not provide.
- A same-thread timeout is not a guarantee against every infinite loop.

## Verification

Run the security suite and the affected package tests, then record the exact
command and result in `progress/` or the security audit.
