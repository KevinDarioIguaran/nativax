# Conformidad: test262

- Fecha: 2026-10-21T04:20:57.787582Z
- Duración: 45.0 s
- Commit de la suite: `d53ebc8b1931d9f1541e43d59650776e4b766248`
- Comando: `run_test262 test/language/expressions test/language/statements test/language/types test/language/literals`
- Total: **21098** tests
- Tasa de éxito (sin SKIP): **97.93 %**

| Estado | Tests |
|---|---:|
| PASS | 19577 |
| FAIL | 413 |
| SKIP | 1108 |
| ERROR | 0 |

## Delta contra la línea base

- Corregidos: **0**
- Regresiones: **0**
- Siguen fallando: **413**
- Nuevos en esta ejecución: **0**
- Ausentes respecto a la base: **0**

## Por característica

| Grupo | PASS | FAIL | SKIP | ERROR | Éxito |
|---|---:|---:|---:|---:|---:|
| `destructuring-binding` | 6545 | 63 | 0 | 0 | 99.0 % |
| `async-iteration` | 4671 | 22 | 64 | 0 | 99.5 % |
| `class` | 4502 | 24 | 10 | 0 | 99.5 % |
| `core` | 4145 | 254 | 8 | 0 | 94.2 % |
| `generators` | 3867 | 16 | 3 | 0 | 99.6 % |
| `default-parameters` | 2265 | 3 | 0 | 0 | 99.9 % |
| `class-fields-public` | 2050 | 2 | 4 | 0 | 99.9 % |
| `class-methods-private` | 1671 | 0 | 6 | 0 | 100.0 % |
| `Symbol.iterator` | 1545 | 1 | 4 | 0 | 99.9 % |
| `class-static-methods-private` | 1478 | 0 | 3 | 0 | 100.0 % |
| `class-fields-private` | 1053 | 1 | 0 | 0 | 99.9 % |
| `dynamic-import` | 0 | 0 | 1000 | 0 | 0.0 % |
| `async-functions` | 612 | 5 | 2 | 0 | 99.2 % |
| `Symbol.asyncIterator` | 532 | 0 | 0 | 0 | 100.0 % |
| `computed-property-names` | 409 | 0 | 9 | 0 | 100.0 % |
| `object-rest` | 357 | 0 | 1 | 0 | 100.0 % |
| `class-static-fields-private` | 343 | 0 | 1 | 0 | 100.0 % |
| `source-phase-imports` | 0 | 0 | 239 | 0 | 0.0 % |
| `BigInt` | 211 | 0 | 4 | 0 | 100.0 % |
| `class-static-fields-public` | 207 | 1 | 5 | 0 | 99.5 % |
| `explicit-resource-management` | 178 | 0 | 12 | 0 | 100.0 % |
| `Symbol` | 139 | 0 | 25 | 0 | 100.0 % |
| `arrow-function` | 154 | 8 | 0 | 0 | 95.1 % |
| `import-defer` | 0 | 0 | 149 | 0 | 0.0 % |
| `destructuring-assignment` | 121 | 16 | 4 | 0 | 88.3 % |
| `object-spread` | 127 | 8 | 0 | 0 | 94.1 % |
| `numeric-separator-literal` | 113 | 0 | 0 | 0 | 100.0 % |
| `logical-assignment-operators` | 91 | 14 | 0 | 0 | 86.7 % |
| `source-phase-imports-module-source` | 0 | 0 | 105 | 0 | 0.0 % |
| `rest-parameters` | 96 | 0 | 0 | 0 | 100.0 % |
| `regexp-modifiers` | 83 | 0 | 0 | 0 | 100.0 % |
| `exponentiation` | 71 | 0 | 1 | 0 | 100.0 % |
| `import-attributes` | 0 | 0 | 65 | 0 | 0.0 % |
| `class-static-block` | 64 | 0 | 0 | 0 | 100.0 % |
| `Symbol.toPrimitive` | 62 | 0 | 0 | 0 | 100.0 % |
| `regexp-named-groups` | 56 | 0 | 0 | 0 | 100.0 % |
| `optional-chaining` | 56 | 0 | 0 | 0 | 100.0 % |
| `let` | 51 | 0 | 0 | 0 | 100.0 % |
| `new.target` | 49 | 0 | 1 | 0 | 100.0 % |
| `TypedArray` | 47 | 1 | 0 | 0 | 97.9 % |
| `Symbol.unscopables` | 36 | 0 | 0 | 0 | 100.0 % |
| `tail-call-optimization` | 0 | 0 | 34 | 0 | 0.0 % |
| `Proxy` | 23 | 3 | 4 | 0 | 88.5 % |
| `coalesce-expression` | 23 | 0 | 2 | 0 | 100.0 % |
| `decorators` | 2 | 22 | 0 | 0 | 8.3 % |
| `globalThis` | 24 | 0 | 0 | 0 | 100.0 % |
| `import.meta` | 5 | 0 | 18 | 0 | 100.0 % |
| `Symbol.toStringTag` | 0 | 0 | 20 | 0 | 0.0 % |
| `class-fields-private-in` | 18 | 1 | 0 | 0 | 94.7 % |
| `cross-realm` | 0 | 0 | 18 | 0 | 0.0 % |
| `top-level-await` | 0 | 0 | 18 | 0 | 0.0 % |
| `Reflect` | 7 | 2 | 3 | 0 | 77.8 % |
| `const` | 10 | 0 | 0 | 0 | 100.0 % |
| `Map` | 7 | 0 | 0 | 0 | 100.0 % |
| `Set` | 7 | 0 | 0 | 0 | 100.0 % |
| `resizable-arraybuffer` | 6 | 0 | 0 | 0 | 100.0 % |
| `export-star-as-namespace-from-module` | 0 | 0 | 6 | 0 | 0.0 % |
| `u180e` | 6 | 0 | 0 | 0 | 100.0 % |
| `optional-catch-binding` | 5 | 0 | 0 | 0 | 100.0 % |
| `for-in-order` | 4 | 0 | 0 | 0 | 100.0 % |
| `Symbol.hasInstance` | 4 | 0 | 0 | 0 | 100.0 % |
| `WeakSet` | 4 | 0 | 0 | 0 | 100.0 % |
| `json-superset` | 4 | 0 | 0 | 0 | 100.0 % |
| `Reflect.construct` | 4 | 0 | 0 | 0 | 100.0 % |
| `WeakMap` | 4 | 0 | 0 | 0 | 100.0 % |
| `for-of` | 4 | 0 | 0 | 0 | 100.0 % |
| `super` | 3 | 0 | 0 | 0 | 100.0 % |
| `WeakRef` | 2 | 0 | 0 | 0 | 100.0 % |
| `Int32Array` | 2 | 0 | 0 | 0 | 100.0 % |
| `Float64Array` | 2 | 0 | 0 | 0 | 100.0 % |
| `Float32Array` | 2 | 0 | 0 | 0 | 100.0 % |
| `DataView` | 2 | 0 | 0 | 0 | 100.0 % |
| `ArrayBuffer` | 2 | 0 | 0 | 0 | 100.0 % |
| `Promise` | 2 | 0 | 0 | 0 | 100.0 % |
| `AggregateError` | 2 | 0 | 0 | 0 | 100.0 % |
| `Int8Array` | 2 | 0 | 0 | 0 | 100.0 % |
| `SharedArrayBuffer` | 2 | 0 | 0 | 0 | 100.0 % |
| `__proto__` | 2 | 0 | 0 | 0 | 100.0 % |
| `Uint8Array` | 2 | 0 | 0 | 0 | 100.0 % |
| `Int16Array` | 2 | 0 | 0 | 0 | 100.0 % |
| _(+7 grupos)_ | | | | | |

## Por directorio

| Grupo | PASS | FAIL | SKIP | ERROR | Éxito |
|---|---:|---:|---:|---:|---:|
| `language/statements/class` | 4346 | 15 | 6 | 0 | 99.7 % |
| `language/expressions/class` | 4033 | 9 | 17 | 0 | 99.8 % |
| `language/statements/for-await-of` | 1227 | 7 | 0 | 0 | 99.4 % |
| `language/expressions/object` | 1157 | 12 | 1 | 0 | 99.0 % |
| `language/expressions/dynamic-import` | 0 | 0 | 1005 | 0 | 0.0 % |
| `language/statements/for-of` | 729 | 20 | 2 | 0 | 97.3 % |
| `language/expressions/async-generator` | 611 | 11 | 1 | 0 | 98.2 % |
| `language/expressions/assignment` | 438 | 47 | 0 | 0 | 90.3 % |
| `language/expressions/compound-assignment` | 387 | 67 | 0 | 0 | 85.2 % |
| `language/statements/function` | 430 | 21 | 0 | 0 | 95.3 % |
| `language/statements/for` | 381 | 0 | 4 | 0 | 100.0 % |
| `language/expressions/arrow-function` | 326 | 17 | 0 | 0 | 95.0 % |
| `language/expressions/assignmenttargettype` | 314 | 4 | 6 | 0 | 98.7 % |
| `language/statements/async-generator` | 299 | 2 | 0 | 0 | 99.3 % |
| `language/expressions/generators` | 281 | 8 | 1 | 0 | 97.2 % |
| `language/statements/generators` | 264 | 2 | 0 | 0 | 99.2 % |
| `language/expressions/function` | 254 | 10 | 0 | 0 | 96.2 % |
| `language/literals/regexp` | 240 | 0 | 0 | 0 | 100.0 % |
| `language/statements/try` | 194 | 4 | 3 | 0 | 98.0 % |
| `language/statements/with` | 173 | 8 | 0 | 0 | 95.6 % |
| `language/statements/variable` | 140 | 38 | 0 | 0 | 78.7 % |
| `language/literals/numeric` | 146 | 11 | 0 | 0 | 93.0 % |
| `language/statements/let` | 144 | 1 | 0 | 0 | 99.3 % |
| `language/statements/const` | 136 | 0 | 0 | 0 | 100.0 % |
| `language/statements/for-in` | 97 | 22 | 0 | 0 | 81.5 % |
| `language/statements/switch` | 107 | 1 | 3 | 0 | 99.1 % |
| `language/statements/await-using` | 92 | 0 | 6 | 0 | 100.0 % |
| `language/expressions/super` | 91 | 2 | 1 | 0 | 97.8 % |
| `language/expressions/async-function` | 87 | 6 | 0 | 0 | 93.5 % |
| `language/expressions/call` | 84 | 1 | 7 | 0 | 98.8 % |
| `language/statements/using` | 76 | 0 | 4 | 0 | 100.0 % |
| `language/expressions/logical-assignment` | 64 | 14 | 0 | 0 | 82.1 % |
| `language/statements/async-function` | 69 | 5 | 0 | 0 | 93.2 % |
| `language/literals/string` | 67 | 6 | 0 | 0 | 91.8 % |
| `language/expressions/delete` | 60 | 9 | 0 | 0 | 87.0 % |
| `language/statements/if` | 59 | 8 | 2 | 0 | 88.1 % |
| `language/expressions/yield` | 62 | 1 | 0 | 0 | 98.4 % |
| `language/expressions/async-arrow-function` | 58 | 2 | 0 | 0 | 96.7 % |
| `language/expressions/new` | 58 | 0 | 1 | 0 | 100.0 % |
| `language/literals/bigint` | 59 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/template-literal` | 57 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/array` | 52 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/greater-than` | 49 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/addition` | 48 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/less-than-or-equal` | 47 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/equals` | 47 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/less-than` | 45 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/unsigned-right-shift` | 45 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/left-shift` | 45 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/division` | 45 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/exponentiation` | 44 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/greater-than-or-equal` | 43 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/instanceof` | 43 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/modulus` | 40 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/multiplication` | 40 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/subtraction` | 38 | 0 | 0 | 0 | 100.0 % |
| `language/statements/while` | 37 | 0 | 1 | 0 | 100.0 % |
| `language/expressions/does-not-equals` | 38 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/optional-chaining` | 38 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/postfix-increment` | 35 | 3 | 0 | 0 | 92.1 % |
| `language/expressions/right-shift` | 37 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/postfix-decrement` | 35 | 2 | 0 | 0 | 94.6 % |
| `language/expressions/in` | 34 | 2 | 0 | 0 | 94.4 % |
| `language/statements/do-while` | 35 | 0 | 1 | 0 | 100.0 % |
| `language/expressions/prefix-decrement` | 31 | 3 | 0 | 0 | 91.2 % |
| `language/expressions/prefix-increment` | 31 | 2 | 0 | 0 | 93.9 % |
| `language/expressions/strict-does-not-equals` | 30 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/strict-equals` | 30 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/bitwise-or` | 30 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/bitwise-xor` | 30 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/bitwise-and` | 30 | 0 | 0 | 0 | 100.0 % |
| `language/types/reference` | 22 | 5 | 2 | 0 | 81.5 % |
| `language/expressions/tagged-template` | 22 | 2 | 3 | 0 | 91.7 % |
| `language/types/string` | 24 | 0 | 0 | 0 | 100.0 % |
| `language/statements/continue` | 24 | 0 | 0 | 0 | 100.0 % |
| `language/statements/labeled` | 18 | 3 | 3 | 0 | 85.7 % |
| `language/expressions/coalesce` | 22 | 0 | 2 | 0 | 100.0 % |
| `language/expressions/conditional` | 20 | 0 | 2 | 0 | 100.0 % |
| `language/expressions/await` | 22 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/import.meta` | 5 | 0 | 17 | 0 | 100.0 % |
| _(+32 grupos)_ | | | | | |

## Fallos (413)

### `language/expressions/arrow-function/dstr/syntax-error-ident-ref-implements-escaped.js`

- Características: arrow-function, destructuring-assignment
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/arrow-function/dstr/syntax-error-ident-ref-interface-escaped.js`

- Características: arrow-function, destructuring-assignment
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/arrow-function/dstr/syntax-error-ident-ref-let-escaped.js`

- Características: arrow-function, destructuring-assignment
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/arrow-function/dstr/syntax-error-ident-ref-package-escaped.js`

- Características: arrow-function, destructuring-assignment
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/arrow-function/dstr/syntax-error-ident-ref-private-escaped.js`

- Características: arrow-function, destructuring-assignment
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/arrow-function/dstr/syntax-error-ident-ref-protected-escaped.js`

- Características: arrow-function, destructuring-assignment
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/arrow-function/dstr/syntax-error-ident-ref-public-escaped.js`

- Características: arrow-function, destructuring-assignment
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/arrow-function/dstr/syntax-error-ident-ref-static-escaped.js`

- Características: arrow-function, destructuring-assignment
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/arrow-function/param-dflt-yield-id-strict.js`

- Características: default-parameters
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/arrow-function/strict.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a ReferenceError to be thrown but no exception was thrown at all

### `language/expressions/arrow-function/syntax/early-errors/arrowparameters-bindingidentifier-identifier-strict-futurereservedword.js`

- Características: core
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/arrow-function/syntax/early-errors/arrowparameters-bindingidentifier-no-arguments.js`

- Características: core
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/arrow-function/syntax/early-errors/arrowparameters-bindingidentifier-no-eval.js`

- Características: core
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/arrow-function/syntax/early-errors/arrowparameters-bindingidentifier-no-yield.js`

- Características: core
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/arrow-function/syntax/early-errors/arrowparameters-cover-no-arguments.js`

- Características: core
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/arrow-function/syntax/early-errors/arrowparameters-cover-no-eval.js`

- Características: core
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/arrow-function/syntax/early-errors/arrowparameters-cover-no-yield.js`

- Características: core
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/assignment/11.13.1-1-s.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a TypeError to be thrown but no exception was thrown at all

### `language/expressions/assignment/11.13.1-2-s.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a TypeError to be thrown but no exception was thrown at all

### `language/expressions/assignment/11.13.1-3-s.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a TypeError to be thrown but no exception was thrown at all

### `language/expressions/assignment/11.13.1-4-14-s.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a TypeError to be thrown but no exception was thrown at all

### `language/expressions/assignment/11.13.1-4-27-s.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a TypeError to be thrown but no exception was thrown at all

### `language/expressions/assignment/11.13.1-4-28gs.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a TypeError to be thrown but no exception was thrown at all

### `language/expressions/assignment/11.13.1-4-29gs.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a TypeError to be thrown but no exception was thrown at all

### `language/expressions/assignment/11.13.1-4-3-s.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a TypeError to be thrown but no exception was thrown at all

### `language/expressions/assignment/11.13.1-4-6-s.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a TypeError to be thrown but no exception was thrown at all

### `language/expressions/assignment/8.14.4-8-b_2.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a TypeError to be thrown but no exception was thrown at all

### `language/expressions/assignment/S11.13.1_A6_T1.js`

- Características: core
- Motivo: [sloppy] Error: Test262Error: #1: innerX === undefined. Actual: 1

### `language/expressions/assignment/S11.13.1_A6_T2.js`

- Características: core
- Motivo: [sloppy] Error: Test262Error: #1: innerX === 2. Actual: 1

### `language/expressions/assignment/destructuring/iterator-destructuring-property-reference-target-evaluation-order.js`

- Características: Symbol.iterator
- Motivo: [sloppy] Error: Test262Error: Actual [source, iterator, target, target-key, target-key-tostring, iterator-step, iterator-done, set] and expected [source, iterator, target, target-key, iterator-step, iterator-done, target-key-tostring, set] should have the same contents. 

### `language/expressions/assignment/destructuring/keyed-destructuring-property-reference-target-evaluation-order-with-bindings.js`

- Características: Proxy
- Motivo: [sloppy] Error: Test262Error: Actual [binding::source, binding::sourceKey, sourceKey, binding::target, binding::targetKey, targetKey, get source, binding::defaultValue, set target] and expected [binding::source, binding::sourceKey, sourceKey, binding::target, binding::targetKey, get source, binding::defaultValue, targetKey, set target] should have the same contents. 

### `language/expressions/assignment/destructuring/keyed-destructuring-property-reference-target-evaluation-order.js`

- Características: core
- Motivo: [sloppy] Error: Test262Error: Actual [source, source-key, source-key-tostring, target, target-key, target-key-tostring, get, set] and expected [source, source-key, source-key-tostring, target, target-key, get, target-key-tostring, set] should have the same contents. 

### `language/expressions/assignment/dstr/array-elem-init-yield-ident-invalid.js`

- Características: destructuring-binding
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/assignment/dstr/array-elem-nested-array-yield-ident-invalid.js`

- Características: destructuring-binding
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/assignment/dstr/array-elem-nested-obj-yield-ident-invalid.js`

- Características: destructuring-binding
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/assignment/dstr/array-elem-put-unresolvable-strict.js`

- Características: destructuring-binding
- Motivo: [strict] Error: Test262Error: Expected a ReferenceError to be thrown but no exception was thrown at all

### `language/expressions/assignment/dstr/array-elem-target-simple-strict.js`

- Características: destructuring-binding
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/assignment/dstr/array-elem-target-yield-invalid.js`

- Características: destructuring-binding
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/assignment/dstr/array-rest-nested-array-yield-ident-invalid.js`

- Características: destructuring-binding
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/assignment/dstr/array-rest-nested-obj-yield-ident-invalid.js`

- Características: destructuring-binding
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/assignment/dstr/array-rest-put-unresolvable-strict.js`

- Características: destructuring-binding
- Motivo: [strict] Error: Test262Error: Expected a ReferenceError to be thrown but no exception was thrown at all

### `language/expressions/assignment/dstr/array-rest-yield-ident-invalid.js`

- Características: destructuring-binding
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/assignment/dstr/obj-id-identifier-yield-ident-invalid.js`

- Características: destructuring-binding
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/assignment/dstr/obj-id-init-simple-strict.js`

- Características: destructuring-binding
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/assignment/dstr/obj-id-init-yield-ident-invalid.js`

- Características: destructuring-binding
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/assignment/dstr/obj-id-put-unresolvable-strict.js`

- Características: destructuring-binding
- Motivo: [strict] Error: Test262Error: Expected a ReferenceError to be thrown but no exception was thrown at all

### `language/expressions/assignment/dstr/obj-id-simple-strict.js`

- Características: destructuring-binding
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/assignment/dstr/obj-prop-elem-init-yield-ident-invalid.js`

- Características: destructuring-binding
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/assignment/dstr/obj-prop-elem-target-yield-ident-invalid.js`

- Características: destructuring-binding
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/assignment/dstr/obj-prop-nested-array-yield-ident-invalid.js`

- Características: destructuring-binding
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/assignment/dstr/obj-prop-nested-obj-yield-ident-invalid.js`

- Características: destructuring-binding
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/assignment/dstr/obj-prop-put-unresolvable-strict.js`

- Características: destructuring-binding
- Motivo: [strict] Error: Test262Error: Expected a ReferenceError to be thrown but no exception was thrown at all

### `language/expressions/assignment/dstr/syntax-error-ident-ref-implements-escaped.js`

- Características: destructuring-assignment
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/assignment/dstr/syntax-error-ident-ref-interface-escaped.js`

- Características: destructuring-assignment
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/assignment/dstr/syntax-error-ident-ref-let-escaped.js`

- Características: destructuring-assignment
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/assignment/dstr/syntax-error-ident-ref-package-escaped.js`

- Características: destructuring-assignment
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/assignment/dstr/syntax-error-ident-ref-private-escaped.js`

- Características: destructuring-assignment
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/assignment/dstr/syntax-error-ident-ref-protected-escaped.js`

- Características: destructuring-assignment
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/assignment/dstr/syntax-error-ident-ref-public-escaped.js`

- Características: destructuring-assignment
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/assignment/dstr/syntax-error-ident-ref-static-escaped.js`

- Características: destructuring-assignment
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/assignment/id-arguments-strict.js`

- Características: core
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/assignment/id-eval-strict.js`

- Características: core
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/assignment/target-member-computed-reference.js`

- Características: core
- Motivo: [sloppy] Error: Test262Error: Expected a DummyError but got a Test262Error

### `language/expressions/assignment/target-super-computed-reference.js`

- Características: core
- Motivo: [sloppy] Error: Test262Error: Expected a DummyError but got a Test262Error

### `language/expressions/assignmenttargettype/direct-identifierreference-arguments-strict.js`

- Características: core
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/assignmenttargettype/direct-identifierreference-eval-strict.js`

- Características: core
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/assignmenttargettype/parenthesized-identifierreference-arguments-strict.js`

- Características: core
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/assignmenttargettype/parenthesized-identifierreference-eval-strict.js`

- Características: core
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/async-arrow-function/early-errors-arrow-arguments-in-formal-parameters.js`

- Características: core
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/async-arrow-function/early-errors-arrow-eval-in-formal-parameters.js`

- Características: core
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/async-function/early-errors-expression-binding-identifier-arguments.js`

- Características: core
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/async-function/early-errors-expression-binding-identifier-eval.js`

- Características: core
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/async-function/early-errors-expression-eval-in-formal-parameters.js`

- Características: core
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/async-function/named-strict-error-reassign-fn-name-in-body-in-arrow.js`

- Características: async-functions
- Motivo: [strict] Test262Error: Test262Error: Expected SameValue(«0», «1») to be true

### `language/expressions/async-function/named-strict-error-reassign-fn-name-in-body-in-eval.js`

- Características: async-functions
- Motivo: [strict] Test262Error: Test262Error: Expected SameValue(«0», «1») to be true

### `language/expressions/async-function/named-strict-error-reassign-fn-name-in-body.js`

- Características: async-functions
- Motivo: [strict] Test262Error: Test262Error: Expected SameValue(«0», «1») to be true

### `language/expressions/async-generator/early-errors-expression-arguments-in-formal-parameters.js`

- Características: async-iteration
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/async-generator/early-errors-expression-binding-identifier-arguments.js`

- Características: async-iteration
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/async-generator/early-errors-expression-binding-identifier-eval.js`

- Características: async-iteration
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/async-generator/early-errors-expression-eval-in-formal-parameters.js`

- Características: async-iteration
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/async-generator/named-strict-error-reassign-fn-name-in-body-in-arrow.js`

- Características: async-iteration
- Motivo: [strict] Test262Error: Test262Error: Expected SameValue(«0», «1») to be true

### `language/expressions/async-generator/named-strict-error-reassign-fn-name-in-body-in-eval.js`

- Características: async-iteration
- Motivo: [strict] Test262Error: Test262Error: Expected SameValue(«0», «1») to be true

### `language/expressions/async-generator/named-strict-error-reassign-fn-name-in-body.js`

- Características: async-iteration
- Motivo: [strict] Test262Error: Test262Error: Expected SameValue(«0», «1») to be true

### `language/expressions/async-generator/named-yield-identifier-spread-strict.js`

- Características: object-spread, async-iteration
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/async-generator/named-yield-identifier-strict.js`

- Características: async-iteration
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/async-generator/yield-identifier-spread-strict.js`

- Características: object-spread, async-iteration
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/async-generator/yield-identifier-strict.js`

- Características: async-iteration
- Motivo: [strict] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/call/eval-strictness-inherit-strict.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a SyntaxError to be thrown but no exception was thrown at all

### `language/expressions/class/decorator/syntax/class-valid/decorator-member-expr-private-identifier.js`

- Características: class, decorators
- Motivo: [sloppy] SyntaxError: unexpected token in expression: '@'     at prod-ClassExpression:279:13 

### `language/expressions/class/decorator/syntax/valid/decorator-call-expr-identifier-reference-yield.js`

- Características: class, decorators
- Motivo: [sloppy] SyntaxError: unexpected token in expression: '@'     at prod-ClassExpression:277:9 

### `language/expressions/class/decorator/syntax/valid/decorator-call-expr-identifier-reference.js`

- Características: class, decorators
- Motivo: [sloppy] SyntaxError: unexpected token in expression: '@'     at prod-ClassExpression:284:9 

### `language/expressions/class/decorator/syntax/valid/decorator-member-expr-decorator-member-expr.js`

- Características: class, decorators
- Motivo: [sloppy] SyntaxError: unexpected token in expression: '@'     at prod-ClassExpression:276:9 

### `language/expressions/class/decorator/syntax/valid/decorator-member-expr-identifier-reference-yield.js`

- Características: class, decorators
- Motivo: [sloppy] SyntaxError: unexpected token in expression: '@'     at prod-ClassExpression:266:9 

### `language/expressions/class/decorator/syntax/valid/decorator-member-expr-identifier-reference.js`

- Características: class, decorators
- Motivo: [sloppy] SyntaxError: unexpected token in expression: '@'     at prod-ClassExpression:273:9 

### `language/expressions/class/decorator/syntax/valid/decorator-parenthesized-expr-identifier-reference-yield.js`

- Características: class, decorators
- Motivo: [sloppy] SyntaxError: unexpected token in expression: '@'     at prod-ClassExpression:284:9 

### `language/expressions/class/decorator/syntax/valid/decorator-parenthesized-expr-identifier-reference.js`

- Características: class, decorators
- Motivo: [sloppy] SyntaxError: unexpected token in expression: '@'     at prod-ClassExpression:286:9 

### `language/expressions/class/elements/syntax/valid/grammar-field-accessor.js`

- Características: decorators, class
- Motivo: [sloppy] SyntaxError: expecting ';'     at prod-ClassElement:251:12 

### `language/expressions/compound-assignment/11.13.2-23-s.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a TypeError to be thrown but no exception was thrown at all

### `language/expressions/compound-assignment/11.13.2-24-s.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a TypeError to be thrown but no exception was thrown at all

### `language/expressions/compound-assignment/11.13.2-25-s.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a TypeError to be thrown but no exception was thrown at all

### `language/expressions/compound-assignment/11.13.2-26-s.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a TypeError to be thrown but no exception was thrown at all

### `language/expressions/compound-assignment/11.13.2-27-s.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a TypeError to be thrown but no exception was thrown at all

### `language/expressions/compound-assignment/11.13.2-28-s.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a TypeError to be thrown but no exception was thrown at all

### `language/expressions/compound-assignment/11.13.2-29-s.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a TypeError to be thrown but no exception was thrown at all

### `language/expressions/compound-assignment/11.13.2-30-s.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a TypeError to be thrown but no exception was thrown at all

### `language/expressions/compound-assignment/11.13.2-31-s.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a TypeError to be thrown but no exception was thrown at all

### `language/expressions/compound-assignment/11.13.2-32-s.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a TypeError to be thrown but no exception was thrown at all

### `language/expressions/compound-assignment/11.13.2-33-s.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a TypeError to be thrown but no exception was thrown at all

### `language/expressions/compound-assignment/11.13.2-34-s.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a TypeError to be thrown but no exception was thrown at all

### `language/expressions/compound-assignment/11.13.2-35-s.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a TypeError to be thrown but no exception was thrown at all

### `language/expressions/compound-assignment/11.13.2-36-s.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a TypeError to be thrown but no exception was thrown at all

### `language/expressions/compound-assignment/11.13.2-37-s.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a TypeError to be thrown but no exception was thrown at all

### `language/expressions/compound-assignment/11.13.2-38-s.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a TypeError to be thrown but no exception was thrown at all

### `language/expressions/compound-assignment/11.13.2-39-s.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a TypeError to be thrown but no exception was thrown at all

### `language/expressions/compound-assignment/11.13.2-40-s.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a TypeError to be thrown but no exception was thrown at all

### `language/expressions/compound-assignment/11.13.2-41-s.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a TypeError to be thrown but no exception was thrown at all

### `language/expressions/compound-assignment/11.13.2-42-s.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a TypeError to be thrown but no exception was thrown at all

### `language/expressions/compound-assignment/11.13.2-43-s.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a TypeError to be thrown but no exception was thrown at all

### `language/expressions/compound-assignment/11.13.2-44-s.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a TypeError to be thrown but no exception was thrown at all

### `language/expressions/compound-assignment/11.13.2-45-s.js`

- Características: core
- Motivo: [strict] Error: Test262Error: Expected a TypeError to be thrown but no exception was thrown at all

_… y 293 fallos más (ver el JSONL)._

## SKIP agrupados por motivo

| Motivo | Tests |
|---|---:|
| runner limitation: no module loader/import hooks (dynamic-import) | 523 |
| runner limitation: no module loader/import hooks (import-defer, dynamic-import) | 142 |
| runner limitation: no module loader/import hooks (source-phase-imports, dynamic-import) | 132 |
| runner limitation: no module loader/import hooks (source-phase-imports, source-phase-imports-module-source, dynamic-import) | 105 |
| module tests need JS_EVAL_TYPE_MODULE; the FFI bridge only evaluates global scripts | 89 |
| runner limitation: no module loader/import hooks (import-attributes, dynamic-import) | 42 |
| engine gap: QuickJS-ng does not implement tail-call optimization | 34 |
| runner limitation: no module loader/import hooks (dynamic-import, import-attributes) | 23 |
| runner limitation: $262.createRealm is a host-only Test262 API | 18 |

---

_Generado por `tools/conformance`. Un SKIP no cuenta como compatibilidad; mide únicamente que el runner no pudo ejecutar el test o que la característica está fuera de alcance._
