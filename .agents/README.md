# Nativa agent skills

This directory is the shared skill library for agents working on Nativa. It is
not a flat notes folder: every skill has a `SKILL.md` entry point and private
reference files that load only when the skill is used.

## How the two harnesses see it

- **OpenCode V2** discovers `.agents/skills/<id>/SKILL.md` as a project
  compatibility source. It advertises each skill by its directory ID and loads
  the body on demand.
- **Claude Code** discovers `.claude/skills/<id>/SKILL.md`. The directories
  under `.claude/skills` are symlinks to the canonical skills in
  `.agents/skills`, so there is one source of truth. Claude Code officially
  supports symlinked skill directories.
- `AGENTS.md` is the always-on entry instructions. It points
  here; the detailed references stay out of the context until a skill loads.

## Tree

```text
.agents/
├── README.md
└── skills/
    ├── nativa-project/
    │   ├── SKILL.md
    │   └── references/
    │       ├── context.md
    │       ├── requirements.md
    │       └── maturity.md
    ├── nativa-architecture/
    │   ├── SKILL.md
    │   └── references/
    │       └── overview.md
    ├── nativa-web-rendering/
    │   ├── SKILL.md
    │   └── references/
    │       └── rendering.md
    ├── nativa-conformance/
    │   ├── SKILL.md
    │   └── references/
    │       ├── conformance.md
    │       └── test-infrastructure.md
    ├── nativa-verification/
    │   ├── SKILL.md
    │   └── references/
    │       ├── working-method.md
    │       ├── quality-standards.md
    │       └── coding-standards.md
    ├── nativa-security/
    │   ├── SKILL.md
    │   └── references/
    │       └── security.md
    ├── nativa-performance/
    │   ├── SKILL.md
    │   └── references/
    │       └── performance.md
    └── nativa-docs/
        └── SKILL.md
```

## Skills

| Skill | Use it for |
|---|---|
| `nativa-project` | Product identity, hard requirements, maturity, platform status |
| `nativa-architecture` | Package boundaries, new modules, public APIs, cross-layer refactors |
| `nativa-web-rendering` | HTML, DOM, CSS, layout, painting, and no-WebView review |
| `nativa-conformance` | Test262, html5lib, URL, WPT DOM/CSS/tree runs and compatibility increments |
| `nativa-verification` | Acceptance criteria, TDD, analyze, `test_all.sh`, evidence |
| `nativa-security` | JS-Dart bridge, host APIs, limits, hostile inputs |
| `nativa-performance` | Benchmarks, memory/leaks, latency, and 7x claims |
| `nativa-docs` | Progress, status, reports, and public documentation |

## Quick rules

- NativaX renders its UI with its own runtime. It does not use WebView,
  Chromium, CEF, Electron, or a local HTTP server for presentation.
- Do not add HTML/CSS/JS compatibility without a conformance test or a minimal
  regression test.
- A conformance `SKIP` never counts as compatibility.
- Every functional change updates `progress/` in the same session.
- `dart analyze`/`flutter analyze` must be clean and tests must be green before
  saying something is done.
- Do not delete user files without checking whether they are work in progress.
- Never claim a compatibility rate, performance gain, or leak without
  reproducible evidence.
- `SKIP` is not compatibility; `INCONCLUSIVE` is not a leak; one RSS sample is
  not a leak.
- A test that cannot find a real failure is not maturity evidence. Include
  boundary conditions, not only the happy path.

## Maintenance

- Put task-specific instructions in a new `SKILL.md`; put long reference
  material in that skill's `references/` directory.
- Keep the frontmatter portable: `name` and `description` are enough. Harness
  extensions belong in the harness-specific directories only when needed.
- Keep directory IDs lowercase kebab-case and stable; the ID is how the skill
  is loaded.
- If a skill moves, update `AGENTS.md`, this README, and any agent-specific
  entry files that remain in the checkout.
- Prefer current, reproducible facts over historical prose. Live numbers belong
  in `progress/status.md`.
