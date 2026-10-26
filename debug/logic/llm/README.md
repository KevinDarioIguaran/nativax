# LLM debug pack

Deterministic pre-analysis of every diagnostic engine's evidence into small
minified JSON files, so a model reads conclusions with their numbers instead
of raw output. No model is called anywhere in this pipeline.

```bash
python3 debug/run.py llm                 # all areas -> debug/artifacts/llm/
python3 debug/run.py llm --budget 1500   # estimated-token budget of index.json
python3 debug/run.py llm --area perf     # rebuild one area, keep the others
python3 debug/logic/llm/test_pack.py     # tests
```

| File | Content |
|---|---|
| `legend.json` | meaning of every short key, priority rules, index row layout |
| `index.json` | area summaries, counts by priority, changes vs the previous pack (new/resolved), ranked rows `[id,p,area,trend,headline,tokens]` up to the budget |
| `items/<id>.json` | one problem with every measured detail, ≤ 1,500 estimated tokens |

What is pre-computed (instead of being left to the model):

- **Patterns** (`PAT-*`, listed first): the same computed-style divergence
  across pages, folded by property family; performance scenarios grouped by
  kind and dominant cost; each visual pattern linked to the audit issue that
  reports the same reference/NativaX values (priority 1 when two engines agree).
- **Visual** (`VIS-*`): scores, pixel stats, the engine's root-cause elements
  resolved to the fixture's HTML tag (selector, line) and author CSS rules,
  computed-style mismatches, geometry deltas, worst tiles, layout file by the
  parent's display, trend against the previous comparable run.
- **Performance** (`PERF-*`): NativaX/Chromium metrics, ratios, the dominant
  part of the engine's own work definition (`scenario_ms + render_ms`; load
  time excluded), and a warning when NativaX work is 0 ms (not measured) where
  the engine reports a misleading 0× ratio.
- **Conformance** (`COMP-*`): failures grouped by area and normalized reason
  (literals replaced), with counts and two complete examples per group, and the
  delta against the previous run of the same suite.
- **Memory / security** (`MEM-*`, `SEC-*`): non-passing cases with their
  recorded evidence.
- **Audit** (`NX-*`): the issue report reduced to classification, location,
  expected/actual, minimal scenario, necessary conditions, hypotheses, files.

Rules: absent keys mean not measured; truncated lists say how many entries were
omitted (`o`); token counts use `tiktoken` when installed, otherwise
`ceil(bytes/4)` (labelled in `index.json` `tok`). Data sources are chosen as the
result file with the most measured items (newest on a tie) and named in each
area summary; `--visual`, `--perf`, `--audit` override them.
