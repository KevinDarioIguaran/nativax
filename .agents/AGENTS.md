# NativaX debug workflow (.agents)

## Debugging protocol

1. Work visually and step by step. Run one laboratory section at a time,
   inspect the generated artifacts (DOM, styles, layout, display list, render)
   and the per-case failure/blocker messages before changing code.
2. For each test/section, iterate until it reaches 100% compatibility
   (all cases `pass`; `blocked` is only acceptable for genuinely unsupported
   capabilities that are documented in `debug/lab/sections/s17_gaps.py`).
3. When a section reaches 100%, move to the next section.
4. After a section reaches 100%, run the full laboratory (`--all`) and the
   quality gate so nothing else regresses.
5. Repeat this process for every section.
6. Never weaken assertions, fabricate results, or mark a blocked capability as
   passing without a real implementation behind it.
7. Resume from `debug/progress/current-task.md` and keep progress files updated.
