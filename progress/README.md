# Progreso de NativaX

Esta carpeta es la fuente de verdad del avance. `docs/status.md` es solo un
resumen de sesión; aquí están los números, las fases y el histórico.

## Archivos

- [`status.md`](status.md): estado actual, bloqueos y siguiente paso.
- [`phases.md`](phases.md): checklist por fase del plan maestro.
- [`conformance.md`](conformance.md): resultados de Test262/WPT/html5lib y
  brechas principales.
- [`log.md`](log.md): histórico de sesiones y comandos ejecutados.
- [`reports/`](reports/): informes generados por `debug/engines/compatibility`
  (`test262-latest.md`, `html5lib-tokenizer-latest.md`, `wpt-*.md`) y la
  última línea base visual (`visual-50projects50days-latest.md`) y la de
  rendimiento (`perf-latest.md`). El informe consolidado de capacidades y
  evidencia es [`nativa-quality-latest.md`](reports/nativa-quality-latest.md).
  [`recommendations-latest.md`](reports/recommendations-latest.md) se genera
  automáticamente con prioridades y evidencia, y
  [`test-matrix-300.md`](reports/test-matrix-300.md) documenta la matriz de
  cobertura. El historial de corridas se guarda en `.visual/history` y
  `.perf/history` y se compara desde la página **Historial**.

## Regla

Cada sesión que cambie código funcional debe actualizar `status.md` y añadir
una entrada a `log.md`. Los informes de conformidad se regeneran, no se
editan a mano.
