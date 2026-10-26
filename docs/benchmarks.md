# Benchmarks

## Rendimiento de UI contra un navegador

La suite de rendimiento de página completa está en
[`debug/engines/performance`](../debug/engines/performance): Chromium headless contra NativaX offscreen, con
escenarios de filas, scroll y JS, métricas de nodos/layout/RSS/CPU, objetivos
(frame p95, ratio, idle 250 MB) y panel Tkinter. Contrato y límites en
[`performance-suite.md`](performance-suite.md).

```bash
dart run debug/engines/performance/bin/perf.dart run --app-idle --out .perf/latest
python3 debug/engines/performance/gui/perf_gui.py
```

## Microbenchmarks del motor

La suite de microbenchmarks vive en [`debug/engines/microbenchmarks`](../debug/engines/microbenchmarks) y
se ejecuta con:

```bash
cd debug/engines/microbenchmarks
dart run bin/benchmark.dart run --warmup 3 --rounds 15
```

Resultados: `benchmarks/results/*.json` y `*.md` (ignorados por git).

Para comparar y detectar regresiones:

```bash
dart run bin/benchmark.dart compare \
  --baseline benchmarks/results/base.json \
  --current benchmarks/results/current.json \
  --threshold 10 --noise 2
```

Definiciones, límites de medición y criterios de ruido están en
[`debug/engines/microbenchmarks/README.md`](../debug/engines/microbenchmarks/README.md).

No se comparan V8 o JavaScriptCore como equivalentes: no hay una ejecución
documentada del DOM de NativaX en esos motores. Las cifras `dart.*` son una
referencia del mismo proceso, no una promesa de paridad.
