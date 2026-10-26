# Contributing

NativaX is an experimental runtime. The contribution rules are strict because a
small browser shortcut would invalidate the product. Read
[`../AGENTS.md`](../AGENTS.md) first; it is binding.

## Product invariants

1. Rendering stays in the owned chain: HTML → DOM → CSS → `nativa_render` →
   Flutter widgets/render objects.
2. Never add `webview_flutter`, `flutter_inappwebview`, `HtmlElementView`,
   Chromium/CEF/Electron, or a local HTTP server for presentation.
3. JavaScript runs on a real engine. QuickJS-ng is the portable default; V8 is
   the optional desktop backend. No toy interpreter or text search.
4. Scripts receive ids, scalars, and JSON only; never Dart objects or `JSValue`.
5. Every new feature has a test. A conformance `SKIP` is not compatibility.
6. Do not claim compatibility, speed, maturity, platform support, or no-leak
   without reproducible evidence.
7. Preserve stable defaults: DPR 1.0, `backdrop-filter` enabled, `GlSurfaceView`
   + `RawImage`, metrics opt-in.
8. Do not modify game code or `examples/game-player/assets/game/**` unless the
   owner explicitly asks. Import-path updates from a package rename are allowed
   when needed to keep the build green.
9. Do not push, reset, or rewrite user work unless explicitly asked.
10. Commits/PRs are authored only by the repository owner
    (KevinDarioIguaran). Never add AI co-author trailers or "Generated with"
    attribution.

## Before coding

Write the acceptance criterion in the change description or a scratch note:

- behavior to add/fix;
- test file and assertion;
- exact command to run;
- metric (compatibility, time, memory, visual) if relevant;
- out-of-scope items;
- whether it changes architecture, public API, or a stable default.

Prefer the smallest reversible change. Write the failing focused test first.
Compatibility work is incremental: keep each real ~1 % gain as its own commit
and do not mix it with a structural refactor. A harness/adapter correction is not
a product compatibility gain.

## Package boundaries

| Layer | May depend on | Must not |
|---|---|---|
| `nativa_js` | Dart/FFI/native | Flutter, DOM, renderer |
| `nativa_html` | `nativa_dom` | Flutter, JS, renderer |
| `nativa_dom` | pure Dart | Flutter, JS, renderer |
| `nativa_css` | `nativa_dom` | Flutter, JS, renderer |
| `nativa_dom_bindings` | DOM/CSS/JS | Flutter, renderer widgets |
| `nativa_render` | DOM/CSS/Flutter | JS engine, browser widget |
| `nativax` | all of the above | A second rendering path |

`tools/test_architecture.py` and `tools/check_purity.py` guard parts of this.
A new public API needs a consumer, a test, and documentation. Do not create a
package for a name in the Nativa family without an independent development cycle.

## Workflow

```bash
git status --short
# create a focused branch/commit scope; never reset user WIP
```

1. Inspect the existing contract, tests, limits, and relevant skills.
2. Add the failing test.
3. Make the smallest implementation change.
4. Run the focused test.
5. Run `dart analyze` or `flutter analyze` for touched packages.
6. Run `./tools/test_all.sh` with the game closed. It is currently flaky at
   `game_play_test.dart`; see the caveat below.
7. Measure conformance/benchmarks/leaks when relevant.
8. Update `progress/` and docs in the same change.
9. Review the diff and report exact commands/results.

Package test commands are in [`testing.md`](testing.md). Do not use
`flutter test packages/...` from the root; native assets resolve per package.

### Current suite result: flaky

`packages/nativax/test/game_play_test.dart` produced both `exit 0` and
`TestDeviceException(Shell subprocess crashed with SIGABRT (-6))` across
repeated 2026-10-26 runs; the final run failed. The same failure occurred at
clean `HEAD` `f47240e`. Do not hide it, delete the test, or call the suite
green; root cause is not established and there is no CI.

## What a good change looks like

- Focused diff; no drive-by formatting of unrelated code.
- Test covers denial/limit/disposal, not only the happy path.
- A host API validates ids, sizes, schemes, and paths.
- A CSS/HTML change updates the support page and conformance/regression evidence.
- A renderer change has a widget test or a visual probe, not just a screenshot.
- An engine change preserves the `JavaScriptEngine` contract and states which
  backend was actually exercised.
- A performance claim includes command, machine, commit, flags, metric, and
  noise/uncertainty. A single RSS sample is not a leak.
- A docs change links to real files and does not invent numbers.

## Interface changes

- Public API changes: update [`reference/public-api.md`](reference/public-api.md),
  tests, and migration notes.
- Config/limits: update [`reference/configuration.md`](reference/configuration.md)
  and [`internals/limits-and-memory.md`](internals/limits-and-memory.md).
- Environment variables: update
  [`reference/environment-variables.md`](reference/environment-variables.md) and
  the actual consumer.
- Supported HTML/CSS/JS: update `html-supported.md`, `css-supported.md`,
  `javascript-supported.md`, and the conformance baseline if measured.
- Platform claims: update
  [`architecture/platform-support.md`](architecture/platform-support.md),
  `progress/`, and the security platform matrix with evidence.

## Documentation

- English is the maintained documentation language. Historical material is
  archived under `docs/archive/legacy-es/`, `progress/history/`, and
  `debug/archive/`, and must not be treated as current.
- Docs are source-backed; link to commands/files that exist.
- Status vocabulary is defined in [`README.md`](README.md): implemented/verified,
  implemented-but-insufficiently-verified, partial, experimental, planned,
  unsupported, unknown.
- Distinguish intended architecture from current implementation.
- Do not add placeholder pages or empty "TBD" sections; a page either has
  substantive, accurate content or it does not exist.
- Run the docs checks before declaring the change complete:

```bash
python3 tools/check_docs.py
python3 tools/test_check_docs.py
python3 -m unittest discover -s debug/logic -p 'test_*.py'
```

## Commit and review

- Owner-only authorship; no AI co-author/attribution.
- No `git push`, `git reset`, or history rewrite unless the owner asks.
- Compat increments are isolated: one measured gain per commit.
- Let the owner review uncommitted work before committing.
- In the handoff, state: files changed, commands run, actual results, skipped
  tests, known failures, and what could not be measured.

## Definition of done

- Acceptance test passes (or is honestly blocked with evidence).
- Focused tests + analyze pass for touched packages.
- Full suite status reported; known failures not hidden.
- Docs/progress updated.
- No new browser fallback, no leaked native handle, no unvalidated host API.
- Claims are traceable to a command, run id, or source file.

## Related

- [`../AGENTS.md`](../AGENTS.md)
- [`testing.md`](testing.md)
- [`agents.md`](agents.md)
- [`information-architecture.md`](information-architecture.md)
- [`../.agents/README.md`](../.agents/README.md)
