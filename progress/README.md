# Progreso de NativaX

Esta carpeta es la fuente de verdad del avance. `STATUS.md` (raíz) es solo un
resumen de sesión; aquí están los números, las fases y el histórico.

## Archivos

- [`status.md`](status.md): estado actual, bloqueos y siguiente paso.
- [`phases.md`](phases.md): checklist por fase del plan maestro.
- [`conformance.md`](conformance.md): resultados de Test262/WPT/html5lib y
  brechas principales.
- [`log.md`](log.md): histórico de sesiones y comandos ejecutados.
- [`reports/`](reports/): informes generados por `tools/conformance`
  (`test262-latest.md`, `html5lib-tokenizer-latest.md`, `wpt-*.md`).

## Regla

Cada sesión que cambie código funcional debe actualizar `status.md` y añadir
una entrada a `log.md`. Los informes de conformidad se regeneran, no se
editan a mano.
