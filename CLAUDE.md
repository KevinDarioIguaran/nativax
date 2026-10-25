@AGENTS.md

## Claude Code

- The shared skills live in `.agents/skills`; `.claude/skills` contains
  symlinks to the same directories, so there is one source of truth.
- Load a skill with `/nativa-project`, `/nativa-architecture`,
  `/nativa-web-rendering`, `/nativa-conformance`, `/nativa-verification`,
  `/nativa-security`, `/nativa-performance`, or `/nativa-docs`. Claude may also
  load them automatically from their descriptions.
- Read `.agents/README.md` for the skill map. Do not duplicate skill bodies into
  this file.
- Use plan mode for cross-package changes and for anything touching the JS
  bridge, parser, renderer, or security limits.
- Keep compatibility commits separate from refactors and game changes.
- Never add `Co-Authored-By: Claude` trailers or "Generated with Claude Code"
  lines: commits and PRs are only in the owner's name.
