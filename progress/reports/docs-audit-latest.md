# Documentation audit

- Generated: `2026-10-26T10:24:31+00:00`
- Command: `python3 tools/check_docs.py --write`
- Result: **PASS**
- Maintained files: **100**
- Archived files excluded: **14**
- Issues: **0**

## Checks

| Check | Issues |
|---|---:|
| `broken-link` | 0 |
| `broken-reference` | 0 |
| `language` | 0 |
| `source-path` | 0 |
| `command-path` | 0 |
| `public-api` | 0 |

Scope: root `README.md`, `AGENTS.md`, `COMPAT.md`, `docs/` (except `docs/archive/legacy-es/`), `progress/*.md`, maintained `debug/` and `examples/` READMEs, and `.agents/` documentation.

Excluded: archived Spanish evidence (`docs/archive/`, `progress/history/`), generated reports/artifacts, and third-party copied documentation listed in the JSON report. Exclusions are not silent passes; they are listed in the JSON `excluded` field.

## Issues

No issues.

## Reproduce

```bash
python3 tools/check_docs.py --write
python3 tools/test_check_docs.py
```

A pass means these mechanical checks pass. It does not prove every claim is complete or current; source review and focused tests remain required.
