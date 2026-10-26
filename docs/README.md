# NativaX documentation

This is the canonical documentation for **NativaX**, an experimental UI runtime
written in Dart that interprets a documented subset of HTML, CSS, and JavaScript
and renders it with native Flutter widgets. NativaX is part of the larger
[Nativa family](nativa-family.md).

The repository, not this prose, is the source of truth. Every page states what
the code implements, what has been measured, and what remains unverified. When
documentation and code disagree, the code and its tests win; please fix the page
in the same change.

- Current status and known gaps: [`status.md`](status.md), [`../progress/status.md`](../progress/status.md)
- Last recorded conformance baselines: [`../progress/conformance.md`](../progress/conformance.md)
- Generated evidence and reports: [`../progress/reports/`](../progress/reports/)
- Agent instructions: [`../AGENTS.md`](../AGENTS.md), [`../.agents/`](../.agents/README.md), [`agents.md`](agents.md)
- Repository layout and file roles: [`reference/repository-map.md`](reference/repository-map.md)

## Start here

| If you want to… | Read |
|---|---|
| Understand the project in ten minutes | [`getting-started.md`](getting-started.md) |
| Embed a document in a Flutter app | [`guides/embedding.md`](guides/embedding.md) |
| Load assets, images, fonts, and network data safely | [`guides/resources-and-images.md`](guides/resources-and-images.md) |
| Use the public Dart API | [`reference/public-api.md`](reference/public-api.md) |
| Change runtime configuration or limits | [`reference/configuration.md`](reference/configuration.md) |
| Know which HTML, CSS, DOM, and JavaScript features exist | [`html-supported.md`](html-supported.md), [`css-supported.md`](css-supported.md), [`javascript-supported.md`](javascript-supported.md) |
| Understand how a document becomes pixels | [`architecture/README.md`](architecture/README.md), [`internals/README.md`](internals/README.md) |
| Run or add tests | [`testing.md`](testing.md) |
| Reproduce a benchmark, visual diff, leak run, or conformance number | [`debugging.md`](debugging.md), [`benchmarks.md`](benchmarks.md) |
| Work on the codebase as an agent | [`agents.md`](agents.md), [`contributing.md`](contributing.md) |
| Check platform support honestly | [`architecture/platform-support.md`](architecture/platform-support.md) |
| Find a term or a confusing behavior | [`glossary.md`](glossary.md), [`faq.md`](faq.md) |

## Status vocabulary

These words have a narrow meaning throughout the documentation. They are not
marketing labels.

| Label | Meaning |
|---|---|
| **Verified** | A reproducible command produced the stated result on a named platform, date, and commit. The evidence is linked or on disk. |
| **Implemented** | Code exists and is covered by focused tests, but not necessarily by a standards suite or on every platform. |
| **Partial** | A documented subset works; important cases, APIs, or standards behavior are missing. |
| **Experimental** | It runs in a specific harness or configuration, but is not a stable product contract. |
| **Planned** | A design or requirement exists; no supported implementation is claimed. |
| **Unsupported** | The capability is absent or intentionally a no-op. |
| **Unknown** | There is no trustworthy evidence. “Unknown” is never converted to “PASS”. |

A conformance `SKIP` is not compatibility. A visual `PASS` is not standards
conformance. A benchmark result is not an FPS promise. See
[`information-architecture.md`](information-architecture.md) for the evidence
formats.

## Language policy

As of **2026-10-26**, maintained first-party documentation is written in
**English**. This supersedes the earlier convention that product pages remained
in Spanish.

- Historical Spanish material is kept verbatim under
  [`archive/legacy-es/`](archive/legacy-es/README.md),
  [`../progress/history/`](../progress/history/), and
  [`../debug/archive/`](../debug/archive/README.md).
- Archived pages are labelled historical, are excluded from maintained-link and
  language checks, and must not be used as current behavior.
- The audit report
  ([`../progress/reports/docs-audit-latest.md`](../progress/reports/docs-audit-latest.md))
  records the exclusions and lists every maintained page that was checked.
- Code identifiers, API names, quoted diagnostics, and third-party names remain
  in their original form.

## Documentation map

### Guides and reference

| Path | Subject | Status |
|---|---|---|
| [`getting-started.md`](getting-started.md) | Build, run, first view, mental model | canonical |
| [`guides/embedding.md`](guides/embedding.md) | `NativaXView`, `NativaXRuntime`, configuration, lifecycle | canonical |
| [`guides/resources-and-images.md`](guides/resources-and-images.md) | Resource loaders, images, fonts, network policy | canonical |
| [`guides/forms-and-navigation.md`](guides/forms-and-navigation.md) | Forms, validation, dialogs, navigation, platform services | canonical |
| [`guides/templates.md`](guides/templates.md) | `NativaXTemplateEngine` contract | canonical |
| [`guides/examples.md`](guides/examples.md) | The examples and their real scope | canonical |
| [`reference/public-api.md`](reference/public-api.md) | Exported symbols and signatures | canonical |
| [`reference/configuration.md`](reference/configuration.md) | `NativaXRuntimeConfig`, limits, engine selection | canonical |
| [`reference/environment-variables.md`](reference/environment-variables.md) | Runtime, tracing, benchmark, and example variables | canonical |
| [`reference/repository-map.md`](reference/repository-map.md) | Directories, packages, entry points, tests | canonical |
| [`html-supported.md`](html-supported.md) | HTML parsing subset and limits | canonical |
| [`css-supported.md`](css-supported.md) | Selectors, cascade, properties, layout, painting | canonical |
| [`javascript-supported.md`](javascript-supported.md) | JavaScript engines, event loop, web APIs, limits | canonical |
| [`hot-reload.md`](hot-reload.md) | Document hot reload workflow | canonical |
| [`nativa-family.md`](nativa-family.md) | Family names, package boundaries, extraction rules | canonical |

### Architecture and internals

| Path | Subject | Status |
|---|---|---|
| [`architecture/README.md`](architecture/README.md) | System map and data flow | canonical |
| [`architecture/runtime-lifecycle.md`](architecture/runtime-lifecycle.md) | Parse, install, execute, mutate, dispose | canonical |
| [`architecture/rendering.md`](architecture/rendering.md) | CSS layout and Flutter rendering | canonical |
| [`architecture/javascript-engines.md`](architecture/javascript-engines.md) | V8/QuickJS selection, fallback, bridge | canonical |
| [`architecture/workers-and-resources.md`](architecture/workers-and-resources.md) | Workers, modules, fetch, storage | canonical |
| [`architecture/platform-support.md`](architecture/platform-support.md) | Measured vs unverified platforms | canonical |
| [`internals/html-dom-css.md`](internals/html-dom-css.md) | Parser, DOM, cascade internals | canonical |
| [`internals/renderer.md`](internals/renderer.md) | Render objects, invalidation, virtualization | canonical |
| [`internals/javascript-bridge.md`](internals/javascript-bridge.md) | Host bridge, serialization, hardening | canonical |
| [`internals/limits-and-memory.md`](internals/limits-and-memory.md) | Limits, memory, lifecycle risks | canonical |
| [`internals/diagnostics.md`](internals/diagnostics.md) | Tracing, profiling, diagnostics | canonical |
| [`chromium-mapping.md`](chromium-mapping.md) | Chromium subsystem map for the owned runtime | reference |

### Quality and evidence

| Path | Subject | Status |
|---|---|---|
| [`status.md`](status.md) | Maturity matrix, current evidence, gaps | canonical |
| [`testing.md`](testing.md) | Test layers, commands, known failures | canonical |
| [`debugging.md`](debugging.md) | Diagnostic engines, artifacts, context commands | canonical |
| [`benchmarks.md`](benchmarks.md) | Microbenchmarks, leaks, security, manifests | canonical |
| [`performance-suite.md`](performance-suite.md) | Headless UI/scroll/memory suite and panel | canonical |
| [`visual-fidelity.md`](visual-fidelity.md) | Chromium-vs-NativaX visual judge | canonical |
| [`information-architecture.md`](information-architecture.md) | Evidence formats, indexes, context budgets | canonical |
| [`security/threat-model.md`](security/threat-model.md) | Assets, adversaries, trust boundaries | canonical |
| [`security/audit.md`](security/audit.md) | Current security results and open findings | canonical |
| [`security/test-plan.md`](security/test-plan.md) | Security case matrix and limits | canonical |
| [`security/platform-matrix.md`](security/platform-matrix.md) | Per-platform security verification | canonical |
| [`contributing.md`](contributing.md) | Change workflow, evidence, commit rules | canonical |
| [`agents.md`](agents.md) | Agent context, skills, boundaries | canonical |
| [`glossary.md`](glossary.md) | Terms used by the code and docs | canonical |
| [`faq.md`](faq.md) | Short answers to recurring questions | canonical |

## Canonical evidence locations

| Information | Canonical location | Derived presentation |
|---|---|---|
| Current state and next step | [`../progress/status.md`](../progress/status.md) | [`status.md`](status.md) is the stable maturity view |
| Chronological work log | [`../progress/log.md`](../progress/log.md) | English summary; older Spanish logs are archived |
| Conformance baseline | [`../progress/conformance.md`](../progress/conformance.md) | latest Markdown reports under `progress/reports/` |
| Documentation audit | [`../progress/reports/docs-audit-latest.md`](../progress/reports/docs-audit-latest.md) | `tools/check_docs.py --write` |
| Per-test conformance rows | `debug/artifacts/conformance/results/*.jsonl` | `*.summary.json` metadata |
| Benchmark/leak/security runs | `debug/benchmarks/<area>/<run_id>/manifest.json` | `debug/artifacts/index/runs.jsonl` |
| Immutable engine runs | `debug/artifacts/runs/<area>/<run_id>/` | `debug/artifacts/index/runs.jsonl` |
| Generated artifacts | `debug/artifacts/` (gitignored) | reports under `progress/reports/` |
| Agent skills | [`../AGENTS.md`](../AGENTS.md), [`../.agents/skills/`](../.agents/skills) | [`agents.md`](agents.md) |

## Maintenance rules

1. Update the canonical page and the code/tests in the same change.
2. Link evidence with a date. Do not copy a number without its command and
   environment.
3. Mark status explicitly; do not let a plan read like an implementation.
4. Keep `docs/` free of generated reports. Put evidence in `progress/` and
   `debug/`, link to it, and do not duplicate it.
5. Run `python3 tools/check_docs.py --write` after documentation work. It checks
   local links, language, source references, shell command paths, and public API
   coverage, then writes `progress/reports/docs-audit-latest.{json,md}`.
6. Update [`information-architecture.md`](information-architecture.md) when the
   documentation structure or context policy changes.

## Historical documentation

The original Spanish master prompt, session status, JIT plan/spike, performance
audit, and scratch notes are archived under
[`archive/legacy-es/`](archive/legacy-es/README.md). The detailed Spanish
changelog, earlier phase checklist, and phase-0 measurements are under
[`../progress/history/`](../progress/history/). The pre-consolidation engine
inventory and diagnostic-system snapshot are under
[`../debug/archive/`](../debug/archive/README.md). They are evidence, not
current documentation.
