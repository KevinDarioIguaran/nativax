# Debug laboratory

This directory contains the NativaX debug laboratory. It is the single,
honest entry point for exercising the engine: nothing is simulated and every
case either passes against artifacts produced by the real binaries or is
reported as `blocked` because the capability does not exist.

## Layout

```
debug/
  bootstrap.py          # installs deps, builds, smoke-tests, writes lab/env.json
  lab/
    harness.py          # case registry, DOM/selector engine, Page/Lab, assertions
    run_lab.py          # CLI runner
    sections/           # s01.py ... s17_gaps.py (15 real cases per section, except gaps)
    cases/              # 240 self-contained examples imported from public repos
    corpus.json         # manifest with provenance and independent expected facts
    ATTRIBUTION.md      # source repositories, commits and licences
  artifacts/lab/        # git-ignored run cache
  reports/lab/          # generated JSON + Markdown reports (git-ignored)
```

## Quick start

```bash
python3 debug/bootstrap.py          # install deps + build + smoke test
python3 debug/lab/run_lab.py --list # show sections and case counts
python3 debug/lab/run_lab.py --section 1
python3 debug/lab/run_lab.py --all   # 240 real cases + 26 capability gaps, ~minutes
```

## Case convention

- Every case lives in its own numbered folder `debug/lab/cases/sNN/NNN/`.
- Each folder contains a real example copied verbatim from one of the source
  repositories, plus a generated `case.json` with provenance and independent
  expected facts.
- Files keep their original names and assets; no shared design template or
  generated shell is used.
- Nothing is generated at run time: the laboratory runs `build/nativax-debug`
  and `build/nativax-runtime` over those files.
- All test names, descriptions, messages and fixture copy are in English.
- Responsive checks sweep widths 320..1280 px in 50 px steps for every folder and
  fail on horizontal overflow.

## Useful flags

- `--filter SUBSTR` filter case ids/names
- `--strict` treat `blocked` as failure
- `--no-responsive` skip the width sweep (debugging only)
- `--min-per-section N` enforce a minimum case count
- `--json` print the summary JSON

## Environment

`debug/bootstrap.py --check` verifies the toolchain without installing anything.
`debug/lab/env.json` records the detected environment (git-ignored).
EOF
echo written