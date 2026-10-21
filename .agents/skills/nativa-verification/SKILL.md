---
name: nativa-verification
description: Use before declaring a Nativa change done, planning tests, running analyze or test_all, or writing reproducible evidence for a change.
---

# Nativa verification

Read `references/working-method.md`, `references/quality-standards.md`, and
`references/coding-standards.md` before starting a non-trivial change.

## Workflow

1. Write the acceptance criterion: behavior, test, command, metric, and
   out-of-scope items.
2. Write the failing test or minimal fixture first.
3. Implement the smallest reversible change.
4. Run focused tests, then the full suite:

```bash
./tools/test_all.sh
```

Run it with the game closed. The script runs pure Dart packages from their own
directories, Flutter packages from theirs, examples with tests, and the
tooling analyzers.

5. Run `dart analyze`/`flutter analyze` on touched packages.
6. Check for regressions in conformance, benchmarks, and leaks when relevant.
7. Update `progress/` and docs in the same change.
8. Report exact commands and real results. Never use "should work" as evidence.

## Definition of done

- acceptance criterion written,
- new and existing tests pass,
- analyze is clean,
- affected conformance measured,
- benchmarks/leaks measured when relevant,
- documentation and progress updated,
- limitations stated,
- no invented numbers,
- next step clear.

Do not skip steps because the change looks obvious.
