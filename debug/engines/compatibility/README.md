# Conformidad de NativaX

Runners para medir la compatibilidad real de NativaX con suites oficiales, sin
escribir tests desde cero y sin usar un navegador.

## Suites

- [Test262](https://github.com/tc39/test262): lenguaje ECMAScript.
- [html5lib-tests](https://github.com/html5lib/html5lib-tests): tokenizer HTML.
- [WPT](https://github.com/web-platform-tests/wpt): DOM, eventos y selectores
  mediante un adaptador `testharness.js` mínimo.

Los checkouts se descargan en `.conformance/suites/` y **no se versionan**.

## Uso

```bash
cd debug/engines/compatibility

dart run bin/fetch_suites.dart --suite test262 --suite html5lib --suite wpt

dart run bin/run_test262.dart
dart run bin/run_html5lib.dart
dart run bin/run_wpt.dart --limit 400
dart run bin/run_all.dart
```

Cada runner escribe:

- `.conformance/results/<suite>-<timestamp>.jsonl`: un resultado por test.
- `.conformance/results/<suite>-<timestamp>.summary.json`: agregados.
- `.conformance/results/<suite>-<timestamp>.md`: archivo legible de la corrida
  (ignorado por git).
- `progress/reports/<suite>-latest.md`: último informe versionado. No se
  versionan reportes con timestamp.

## Estados

`PASS`, `FAIL`, `SKIP`, `ERROR`. Un `SKIP` nunca cuenta como compatibilidad:
indica que el runner no puede ejecutar el test o que la característica está
fuera de alcance, y siempre lleva un motivo.

## Opciones útiles

```bash
# Test262 acotado
dart run bin/run_test262.dart --limit 500 --skip-features Temporal,ShadowRealm

# Un archivo concreto de WPT
dart run bin/run_wpt.dart --dirs dom/nodes --grep Element-tagName
```

## Limitaciones del adaptador

Ver
[`../../.agents/skills/nativa-conformance/references/conformance.md`](../../../.agents/skills/nativa-conformance/references/conformance.md).
En resumen:
Test262 modules y APIs de host se saltan; html5lib se ejecuta solo desde Data
state; WPT no soporta reftests, testdriver, workers ni el testharness completo.
