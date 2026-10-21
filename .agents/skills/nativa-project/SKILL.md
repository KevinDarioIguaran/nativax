---
name: nativa-project
description: Use when starting or scoping a Nativa task, checking product constraints, reviewing maturity or platform status, or deciding whether a change is acceptable.
---

# Nativa project context

Read the references in this order before making product or scope decisions:

1. `references/context.md` — what NativaX is and is not.
2. `references/requirements.md` — hard identity, conformance, performance,
   memory, quality, evidence, and security requirements.
3. `references/maturity.md` — the ten quality areas and the four maturity
   levels.

## What to apply immediately

- NativaX is the platform; NativaJS, NativaWeb, NativaRender, NativaFlow,
  NativaForge, NativaShield, and NativaBench are the other family names.
- NativaX renders with its own runtime. It never uses WebView, Chromium, CEF,
  Electron, or a local HTTP server for presentation.
- The public languages remain HTML, CSS, and JavaScript. Dart and Flutter are
  implementation details.
- JavaScript is real QuickJS-ng, without JIT. Do not replace it with a text
  interpreter.
- Do not promise compatibility, performance, maturity, or platform support that
  has not been measured.

## Output

When this skill is used for planning, return:

- the constraint that governs the task,
- the acceptance criterion,
- what is explicitly out of scope,
- the evidence that will prove completion.

If a request conflicts with these constraints, stop and report the conflict
instead of finding a shortcut.
