# Working with agents

NativaX is developed with coding agents. The repository carries an always-on
instruction file and a shared skill library so an agent can load only the
knowledge needed for a task instead of guessing from stale prose.

This page explains the system for humans and agents. The files are authoritative.

## Entry instructions

| File | Used by | Contents |
|---|---|---|
| `AGENTS.md` | OpenCode and other agents | Binding project rules, commands, skill map, references |
| `CLAUDE.md` | Claude Code | Equivalent always-on entry point |
| `.agents/README.md` | All agents | Skill library layout and maintenance |
| `.agents/skills/<id>/SKILL.md` | OpenCode | Loadable workflow/reference skill |
| `.claude/skills/<id>` | Claude Code | Symlink to the canonical `.agents` skill |

A skill is loaded only when its task matches. Do not load the entire library
into context; the `SKILL.md` frontmatter describes when it applies, and private
`references/` stay unloaded until needed.

## Current skills

| Skill | Load when |
|---|---|
| `nativa-project` | Scoping, product constraints, maturity, platform status |
| `nativa-architecture` | Package boundaries, new modules, public APIs, cross-layer refactors |
| `nativa-web-rendering` | HTML, DOM, CSS, layout, painting, no-WebView review |
| `nativa-conformance` | Test262, html5lib, URL, WPT DOM/CSS/tree, compatibility increments |
| `nativa-verification` | Acceptance criteria, TDD, analyze, `test_all.sh`, evidence |
| `nativa-security` | JS-Dart bridge, host APIs, limits, hostile HTML/CSS/JS |
| `nativa-performance` | Benchmarks, memory/leaks, latency, 7x claims |
| `nativa-docs` | Progress, status, reports, public docs, language/evidence policy |

The `ponytail`/`impeccable`/`report`/`opencode` skills in the harness are
general tools, not Nativa project knowledge. Use them only when their task
applies; they do not override `AGENTS.md`.

## Hard rules an agent must not miss

- Owned rendering chain only; no WebView/Chromium/CEF/Electron/`HtmlElementView`
  or local HTTP server for presentation.
- JavaScript on a real engine; QuickJS-ng default, optional V8 desktop backend.
- Scripts receive only ids/scalars/JSON.
- Every feature needs a test; `SKIP` never counts as compatibility.
- No invented compatibility, performance, platform, maturity, or leak claims.
- Preserve user WIP; do not push/reset/rewrite unless asked.
- Owner-only commits; no AI co-author or "Generated with" attribution.
- Do not modify game code/assets unless explicitly asked.

## Suggested agent loop

1. Read `AGENTS.md` and load the matching skill.
2. Search the source, tests, and limits before writing.
3. State the acceptance criterion and out-of-scope items.
4. Write the failing focused test.
5. Make the smallest change.
6. Run focused tests and analyze.
7. Run `./tools/test_all.sh` where feasible; report the exact result. It is
   currently flaky at `game_play_test.dart` (both `exit 0` and SIGABRT were
   observed on 2026-10-26), so one pass is not a gate and there is no CI.
8. Measure affected conformance/perf/leaks.
9. Update `progress/` and docs in the same change.
10. Report exact commands, results, skips, and unmeasured areas.

Do not stop after "the code looks right". Evidence or an explicit unverified
label is required.

## Bounded context

Large repositories overflow an agent context. Use the context commands instead
of pasting files:

```bash
python3 debug/run.py context brief --budget 2000
python3 debug/run.py context inventory
python3 debug/run.py context runs --area visual
python3 debug/run.py context conformance
python3 debug/run.py context docs
python3 debug/run.py context measure --path docs/README.md
python3 debug/run.py context index
```

- `brief` is budgeted and the best starting point.
- `runs`/`conformance`/`docs` are metadata projections; canonical JSONL and
  manifests remain authoritative.
- `index` writes `debug/artifacts/index/*.jsonl` (gitignored), not a database.
- Token counts are estimates (`estimate:utf8_bytes/4`) because `tiktoken`,
  `tokenizers`, and `transformers` are not installed. Do not quote them as exact.

The full information model is in [`information-architecture.md`](information-architecture.md).

## Status vocabulary

Agents must use the definitions in [`README.md`](README.md):

- **implemented and verified** — source + reproducible test/measurement;
- **implemented, insufficiently verified** — source exists, evidence incomplete;
- **partial** — some behavior works, documented gaps;
- **experimental** — exists but not product-stable;
- **planned** — design only, no implementation;
- **unsupported** — deliberately absent;
- **unknown** — no source/evidence assessment.

A test file is not verification; a skipped test is not verification; a visual
percentage is not CSS compatibility.

## Documentation rules for agents

- English is the maintained language. Spanish historical pages belong in
  `docs/archive/legacy-es/`.
- Do not recreate archived paths as maintained docs.
- Do not fabricate totals, command output, dates, or platform results.
- Do not edit `progress/reports/*-latest.md` by hand; rerun the engine.
- Update `progress/status.md` compactly and append history to `progress/log.md`.
- Use real relative links; run `python3 tools/check_docs.py`.

## Review checklist

An agent review should check:

- logic correctness and failure paths;
- security boundaries (host functions, ids, paths, network, memory);
- behavior under load (large DOM, timers, workers, disposal);
- tests for the risky path;
- performance impact and measured evidence;
- every line needed (no speculative abstractions);
- product boundary compliance;
- docs/progress consistency with the diff.

## Related

- [`../AGENTS.md`](../AGENTS.md)
- [`contributing.md`](contributing.md)
- [`information-architecture.md`](information-architecture.md)
- [`../.agents/README.md`](../.agents/README.md)
- [`debugging.md`](debugging.md)
