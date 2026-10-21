# Coding standards

## Dart

- SDK `^3.10.0`, strict null safety.
- Prefer `final`, `const`, patterns, and exhaustive `switch`.
- Public APIs use `///`; internal details live in `lib/src/`.
- Domain errors use dedicated types (`DomException`, `JavaScriptException`,
  `HtmlLimitException`). Do not throw generic `Exception('...')` from public
  APIs.
- Avoid `dynamic` except at JSON/FFI boundaries, and convert it immediately.
- Limits (nodes, depth, memory, time) are part of the contract, not hidden
  options.

## FFI and C

- Only scalars, pointers, and UTF-8 buffers cross the boundary.
- Never expose `JSValue` to Dart.
- Every buffer returned by C is released with `nx_free`, including on error
  paths.
- The host callback must not throw through C: catch and convert failures into a
  JSON error.
- Use `-O3`, `-DNDEBUG`, and hidden visibility by default; bridge symbols are
  exported explicitly with `NX_EXPORT`.

## Flutter

- Use custom `RenderObject`s with `parentUsesSize: true` when measuring a child.
- `computeDryLayout` must be equivalent to `performLayout` without side effects.
- Recreate and dispose `TextSpan`s with `TapGestureRecognizer` on rebuild.
- Release `ValueNotifier`s and listeners in `dispose`.
- Keep JavaScript logic out of widgets.

## Tests

- Test names are in English and are complete sentences.
- One test = one behavior; use `group` to organize related tests.
- Conformance tests do not mix with unit tests.
- Failures must be reproducible with a documented command.

## Documentation

- `STATUS.md` is the session summary; `progress/` is the source of truth.
- ADRs belong in `docs/adr/` (pending) and are linked from `.agents/`.
- Every new limitation is documented the same day.
