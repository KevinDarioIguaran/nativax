# Report search audit

`audit.json` is written by `python3 debug/logic/search_audit.py`. It holds
precision and recall of `catalog.search` per query class, over a fixed
synthetic corpus of 240 report refs. Method and results: part B of
[`debug/architecture/metrics-microbenchmarks.md`](../../architecture/metrics-microbenchmarks.md).
