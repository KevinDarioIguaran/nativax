# Benchmarks

La suite vive en [`tools/benchmark`](../tools/benchmark) y se ejecuta con:

```bash
cd tools/benchmark
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
[`tools/benchmark/README.md`](../tools/benchmark/README.md).

No se comparan V8 o JavaScriptCore como equivalentes: no hay una ejecución
documentada del DOM de NativaX en esos motores. Las cifras `dart.*` son una
referencia del mismo proceso, no una promesa de paridad.
