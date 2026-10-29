# Current task

Debug laboratory corpus replaced with 240 self-contained real-world examples.

## Verified (2026-10-29)

- Imported examples from:
  - zxuqian/html-css-examples (MIT)
  - keshavgbpecdelhi/Web-Development (Apache-2.0)
  - learning-zone/website-templates (license not declared upstream)
- Pinned commits recorded in `debug/lab/corpus.json` and `debug/lab/ATTRIBUTION.md`.
- Every case keeps its original HTML, CSS, JS and assets; no shared design template.
- Laboratory sections s01-s16 now register 15 cases each (240 total).
- Section s17 keeps 26 documented capability gaps.
- `debug/lab/run_lab.py --all` passes (blocked cases allowed unless --strict).

## Commands

```sh
python3 debug/tools/import_real_examples.py --force
python3 debug/lab/run_lab.py --list
python3 debug/lab/run_lab.py --all
```