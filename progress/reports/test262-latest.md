# Conformance: test262

- Started: 2026-10-26T19:49:32.413036+00:00
- Duration: 74.5 s
- Runner version: 0.2.0
- Suite revision: `d53ebc8b1931d9f1541e43d59650776e4b766248`
- Command: `run_test262 test/language/expressions test/language/statements test/language/types test/language/literals`
- Total: **21098** tests
- Pass rate (SKIP excluded): **99.76 %**

| Status | Tests |
|---|---:|
| PASS | 19943 |
| FAIL | 47 |
| SKIP | 1108 |
| ERROR | 0 |

## By feature

| Group | PASS | FAIL | SKIP | ERROR | Pass rate |
|---|---:|---:|---:|---:|---:|
| `destructuring-binding` | 6608 | 0 | 0 | 0 | 100.0 % |
| `async-iteration` | 4693 | 0 | 64 | 0 | 100.0 % |
| `class` | 4502 | 24 | 10 | 0 | 99.5 % |
| `core` | 4382 | 17 | 8 | 0 | 99.6 % |
| `generators` | 3882 | 1 | 3 | 0 | 100.0 % |
| `default-parameters` | 2268 | 0 | 0 | 0 | 100.0 % |
| `class-fields-public` | 2050 | 2 | 4 | 0 | 99.9 % |
| `class-methods-private` | 1671 | 0 | 6 | 0 | 100.0 % |
| `Symbol.iterator` | 1545 | 1 | 4 | 0 | 99.9 % |
| `class-static-methods-private` | 1478 | 0 | 3 | 0 | 100.0 % |
| `class-fields-private` | 1053 | 1 | 0 | 0 | 99.9 % |
| `dynamic-import` | 0 | 0 | 1000 | 0 | 0.0 % |
| `async-functions` | 617 | 0 | 2 | 0 | 100.0 % |
| `Symbol.asyncIterator` | 532 | 0 | 0 | 0 | 100.0 % |
| `computed-property-names` | 409 | 0 | 9 | 0 | 100.0 % |
| `object-rest` | 357 | 0 | 1 | 0 | 100.0 % |
| `class-static-fields-private` | 343 | 0 | 1 | 0 | 100.0 % |
| `source-phase-imports` | 0 | 0 | 239 | 0 | 0.0 % |
| `BigInt` | 211 | 0 | 4 | 0 | 100.0 % |
| `class-static-fields-public` | 207 | 1 | 5 | 0 | 99.5 % |
| `explicit-resource-management` | 178 | 0 | 12 | 0 | 100.0 % |
| `Symbol` | 139 | 0 | 25 | 0 | 100.0 % |
| `arrow-function` | 162 | 0 | 0 | 0 | 100.0 % |
| `import-defer` | 0 | 0 | 149 | 0 | 0.0 % |
| `destructuring-assignment` | 137 | 0 | 4 | 0 | 100.0 % |
| `object-spread` | 135 | 0 | 0 | 0 | 100.0 % |
| `numeric-separator-literal` | 113 | 0 | 0 | 0 | 100.0 % |
| `logical-assignment-operators` | 105 | 0 | 0 | 0 | 100.0 % |
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
| _(+7 groups)_ | | | | | |

## By directory

| Group | PASS | FAIL | SKIP | ERROR | Pass rate |
|---|---:|---:|---:|---:|---:|
| `language/statements/class` | 4346 | 15 | 6 | 0 | 99.7 % |
| `language/expressions/class` | 4033 | 9 | 17 | 0 | 99.8 % |
| `language/statements/for-await-of` | 1234 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/object` | 1168 | 1 | 1 | 0 | 99.9 % |
| `language/expressions/dynamic-import` | 0 | 0 | 1005 | 0 | 0.0 % |
| `language/statements/for-of` | 749 | 0 | 2 | 0 | 100.0 % |
| `language/expressions/async-generator` | 622 | 0 | 1 | 0 | 100.0 % |
| `language/expressions/assignment` | 478 | 7 | 0 | 0 | 98.6 % |
| `language/expressions/compound-assignment` | 443 | 11 | 0 | 0 | 97.6 % |
| `language/statements/function` | 451 | 0 | 0 | 0 | 100.0 % |
| `language/statements/for` | 381 | 0 | 4 | 0 | 100.0 % |
| `language/expressions/arrow-function` | 343 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/assignmenttargettype` | 318 | 0 | 6 | 0 | 100.0 % |
| `language/statements/async-generator` | 301 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/generators` | 289 | 0 | 1 | 0 | 100.0 % |
| `language/statements/generators` | 266 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/function` | 264 | 0 | 0 | 0 | 100.0 % |
| `language/literals/regexp` | 240 | 0 | 0 | 0 | 100.0 % |
| `language/statements/try` | 198 | 0 | 3 | 0 | 100.0 % |
| `language/statements/with` | 178 | 3 | 0 | 0 | 98.3 % |
| `language/statements/variable` | 178 | 0 | 0 | 0 | 100.0 % |
| `language/literals/numeric` | 157 | 0 | 0 | 0 | 100.0 % |
| `language/statements/let` | 145 | 0 | 0 | 0 | 100.0 % |
| `language/statements/const` | 136 | 0 | 0 | 0 | 100.0 % |
| `language/statements/for-in` | 119 | 0 | 0 | 0 | 100.0 % |
| `language/statements/switch` | 108 | 0 | 3 | 0 | 100.0 % |
| `language/statements/await-using` | 92 | 0 | 6 | 0 | 100.0 % |
| `language/expressions/super` | 93 | 0 | 1 | 0 | 100.0 % |
| `language/expressions/async-function` | 93 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/call` | 85 | 0 | 7 | 0 | 100.0 % |
| `language/statements/using` | 76 | 0 | 4 | 0 | 100.0 % |
| `language/expressions/logical-assignment` | 78 | 0 | 0 | 0 | 100.0 % |
| `language/statements/async-function` | 74 | 0 | 0 | 0 | 100.0 % |
| `language/literals/string` | 73 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/delete` | 69 | 0 | 0 | 0 | 100.0 % |
| `language/statements/if` | 67 | 0 | 2 | 0 | 100.0 % |
| `language/expressions/yield` | 63 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/async-arrow-function` | 60 | 0 | 0 | 0 | 100.0 % |
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
| `language/expressions/postfix-increment` | 38 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/right-shift` | 37 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/postfix-decrement` | 37 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/in` | 35 | 1 | 0 | 0 | 97.2 % |
| `language/statements/do-while` | 35 | 0 | 1 | 0 | 100.0 % |
| `language/expressions/prefix-decrement` | 34 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/prefix-increment` | 33 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/strict-does-not-equals` | 30 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/strict-equals` | 30 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/bitwise-or` | 30 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/bitwise-xor` | 30 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/bitwise-and` | 30 | 0 | 0 | 0 | 100.0 % |
| `language/types/reference` | 27 | 0 | 2 | 0 | 100.0 % |
| `language/expressions/tagged-template` | 24 | 0 | 3 | 0 | 100.0 % |
| `language/types/string` | 24 | 0 | 0 | 0 | 100.0 % |
| `language/statements/continue` | 24 | 0 | 0 | 0 | 100.0 % |
| `language/statements/labeled` | 21 | 0 | 3 | 0 | 100.0 % |
| `language/expressions/coalesce` | 22 | 0 | 2 | 0 | 100.0 % |
| `language/expressions/conditional` | 20 | 0 | 2 | 0 | 100.0 % |
| `language/expressions/await` | 22 | 0 | 0 | 0 | 100.0 % |
| `language/expressions/import.meta` | 5 | 0 | 17 | 0 | 100.0 % |
| _(+32 groups)_ | | | | | |

## Failures (47)

### `language/expressions/assignment/S11.13.1_A6_T1.js`

- Features: core
- Reason: [sloppy] Error: Test262Error: #1: innerX === undefined. Actual: 1

### `language/expressions/assignment/S11.13.1_A6_T2.js`

- Features: core
- Reason: [sloppy] Error: Test262Error: #1: innerX === 2. Actual: 1

### `language/expressions/assignment/destructuring/iterator-destructuring-property-reference-target-evaluation-order.js`

- Features: Symbol.iterator
- Reason: [sloppy] Error: Test262Error: Actual [source, iterator, target, target-key, target-key-tostring, iterator-step, iterator-done, set] and expected [source, iterator, target, target-key, iterator-step, iterator-done, target-key-tostring, set] should have the same contents. 

### `language/expressions/assignment/destructuring/keyed-destructuring-property-reference-target-evaluation-order-with-bindings.js`

- Features: Proxy
- Reason: [sloppy] Error: Test262Error: Actual [binding::source, binding::sourceKey, sourceKey, binding::target, binding::targetKey, targetKey, get source, binding::defaultValue, set target] and expected [binding::source, binding::sourceKey, sourceKey, binding::target, binding::targetKey, get source, binding::defaultValue, targetKey, set target] should have the same contents. 

### `language/expressions/assignment/destructuring/keyed-destructuring-property-reference-target-evaluation-order.js`

- Features: core
- Reason: [sloppy] Error: Test262Error: Actual [source, source-key, source-key-tostring, target, target-key, target-key-tostring, get, set] and expected [source, source-key, source-key-tostring, target, target-key, get, target-key-tostring, set] should have the same contents. 

### `language/expressions/assignment/target-member-computed-reference.js`

- Features: core
- Reason: [sloppy] Error: Test262Error: Expected a DummyError but got a Test262Error

### `language/expressions/assignment/target-super-computed-reference.js`

- Features: core
- Reason: [sloppy] Error: Test262Error: Expected a DummyError but got a Test262Error

### `language/expressions/class/decorator/syntax/class-valid/decorator-member-expr-private-identifier.js`

- Features: class, decorators
- Reason: [sloppy] SyntaxError: unexpected token in expression: '@'     at prod-ClassExpression:261:13 

### `language/expressions/class/decorator/syntax/valid/decorator-call-expr-identifier-reference-yield.js`

- Features: class, decorators
- Reason: [sloppy] SyntaxError: unexpected token in expression: '@'     at prod-ClassExpression:259:9 

### `language/expressions/class/decorator/syntax/valid/decorator-call-expr-identifier-reference.js`

- Features: class, decorators
- Reason: [sloppy] SyntaxError: unexpected token in expression: '@'     at prod-ClassExpression:266:9 

### `language/expressions/class/decorator/syntax/valid/decorator-member-expr-decorator-member-expr.js`

- Features: class, decorators
- Reason: [sloppy] SyntaxError: unexpected token in expression: '@'     at prod-ClassExpression:258:9 

### `language/expressions/class/decorator/syntax/valid/decorator-member-expr-identifier-reference-yield.js`

- Features: class, decorators
- Reason: [sloppy] SyntaxError: unexpected token in expression: '@'     at prod-ClassExpression:248:9 

### `language/expressions/class/decorator/syntax/valid/decorator-member-expr-identifier-reference.js`

- Features: class, decorators
- Reason: [sloppy] SyntaxError: unexpected token in expression: '@'     at prod-ClassExpression:255:9 

### `language/expressions/class/decorator/syntax/valid/decorator-parenthesized-expr-identifier-reference-yield.js`

- Features: class, decorators
- Reason: [sloppy] SyntaxError: unexpected token in expression: '@'     at prod-ClassExpression:266:9 

### `language/expressions/class/decorator/syntax/valid/decorator-parenthesized-expr-identifier-reference.js`

- Features: class, decorators
- Reason: [sloppy] SyntaxError: unexpected token in expression: '@'     at prod-ClassExpression:268:9 

### `language/expressions/class/elements/syntax/valid/grammar-field-accessor.js`

- Features: decorators, class
- Reason: [sloppy] SyntaxError: expecting ';'     at prod-ClassElement:233:12 

### `language/expressions/compound-assignment/S11.13.2_A6.10_T1.js`

- Features: core
- Reason: [sloppy] Error: Test262Error: #1: innerX === 2. Actual: 5

### `language/expressions/compound-assignment/S11.13.2_A6.11_T1.js`

- Features: core
- Reason: [sloppy] Error: Test262Error: #1: innerX === 2. Actual: 5

### `language/expressions/compound-assignment/S11.13.2_A6.1_T1.js`

- Features: core
- Reason: [sloppy] Error: Test262Error: #1: innerX === 2. Actual: 12

### `language/expressions/compound-assignment/S11.13.2_A6.2_T1.js`

- Features: core
- Reason: [sloppy] Error: Test262Error: #1: innerX === 2. Actual: 5

### `language/expressions/compound-assignment/S11.13.2_A6.3_T1.js`

- Features: core
- Reason: [sloppy] Error: Test262Error: #1: innerX === 2. Actual: 3

### `language/expressions/compound-assignment/S11.13.2_A6.4_T1.js`

- Features: core
- Reason: [sloppy] Error: Test262Error: #1: innerX === 2. Actual: 4

### `language/expressions/compound-assignment/S11.13.2_A6.5_T1.js`

- Features: core
- Reason: [sloppy] Error: Test262Error: #1: innerX === 2. Actual: 4

### `language/expressions/compound-assignment/S11.13.2_A6.6_T1.js`

- Features: core
- Reason: [sloppy] Error: Test262Error: #1: innerX === 2. Actual: 8

### `language/expressions/compound-assignment/S11.13.2_A6.7_T1.js`

- Features: core
- Reason: [sloppy] Error: Test262Error: #1: innerX === 2. Actual: 4

### `language/expressions/compound-assignment/S11.13.2_A6.8_T1.js`

- Features: core
- Reason: [sloppy] Error: Test262Error: #1: innerX === 2. Actual: 4

### `language/expressions/compound-assignment/S11.13.2_A6.9_T1.js`

- Features: core
- Reason: [sloppy] Error: Test262Error: #1: innerX === 2. Actual: 1

### `language/expressions/in/private-field-invalid-assignment-target.js`

- Features: class-fields-private, class-fields-private-in
- Reason: [sloppy] expected SyntaxError during parse, got Error: Test262: This statement should not be evaluated.

### `language/expressions/object/computed-property-name-topropertykey-before-value-evaluation.js`

- Features: core
- Reason: [sloppy] Error: Test262Error: Expected SameValue(«"bad"», «"ok"») to be true

### `language/statements/class/decorator/syntax/class-valid/decorator-member-expr-private-identifier.js`

- Features: class, decorators
- Reason: [sloppy] SyntaxError: unexpected token in expression: '@'     at prod-ClassDeclaration:262:5 

### `language/statements/class/decorator/syntax/valid/class-element-decorator-call-expr-identifier-reference.js`

- Features: class, decorators
- Reason: [sloppy] SyntaxError: invalid property name     at prod-ClassDeclaration:272:3 

### `language/statements/class/decorator/syntax/valid/class-element-decorator-member-expr-decorator-member-expr.js`

- Features: class, decorators
- Reason: [sloppy] SyntaxError: invalid property name     at prod-ClassDeclaration:264:3 

### `language/statements/class/decorator/syntax/valid/class-element-decorator-member-expr-identifier-reference.js`

- Features: class, decorators
- Reason: [sloppy] SyntaxError: invalid property name     at prod-ClassDeclaration:261:3 

### `language/statements/class/decorator/syntax/valid/class-element-decorator-parenthesized-expr-identifier-reference.js`

- Features: class, decorators
- Reason: [sloppy] SyntaxError: invalid property name     at prod-ClassDeclaration:274:3 

### `language/statements/class/decorator/syntax/valid/decorator-call-expr-identifier-reference-yield.js`

- Features: class, decorators
- Reason: [sloppy] SyntaxError: unexpected token in expression: '@'     at prod-ClassDeclaration:260:1 

### `language/statements/class/decorator/syntax/valid/decorator-call-expr-identifier-reference.js`

- Features: class, decorators
- Reason: [sloppy] SyntaxError: unexpected token in expression: '@'     at prod-ClassDeclaration:267:1 

### `language/statements/class/decorator/syntax/valid/decorator-member-expr-decorator-member-expr.js`

- Features: class, decorators
- Reason: [sloppy] SyntaxError: unexpected token in expression: '@'     at prod-ClassDeclaration:259:1 

### `language/statements/class/decorator/syntax/valid/decorator-member-expr-identifier-reference-yield.js`

- Features: class, decorators
- Reason: [sloppy] SyntaxError: unexpected token in expression: '@'     at prod-ClassDeclaration:249:1 

### `language/statements/class/decorator/syntax/valid/decorator-member-expr-identifier-reference.js`

- Features: class, decorators
- Reason: [sloppy] SyntaxError: unexpected token in expression: '@'     at prod-ClassDeclaration:256:1 

### `language/statements/class/decorator/syntax/valid/decorator-parenthesized-expr-identifier-reference-yield.js`

- Features: class, decorators
- Reason: [sloppy] SyntaxError: unexpected token in expression: '@'     at prod-ClassDeclaration:267:1 

### `language/statements/class/decorator/syntax/valid/decorator-parenthesized-expr-identifier-reference.js`

- Features: class, decorators
- Reason: [sloppy] SyntaxError: unexpected token in expression: '@'     at prod-ClassDeclaration:269:1 

### `language/statements/class/elements/syntax/valid/grammar-field-accessor.js`

- Features: decorators, class
- Reason: [sloppy] SyntaxError: expecting ';'     at prod-ClassElement:233:12 

### `language/statements/class/elements/syntax/valid/grammar-field-named-get-followed-by-generator-asi.js`

- Features: class-fields-public, class-static-fields-public, class, generators
- Reason: [sloppy] SyntaxError: invalid property name     at prod-ClassElement:255:3 

### `language/statements/class/elements/syntax/valid/grammar-field-named-set-followed-by-generator-asi.js`

- Features: class-fields-public, class
- Reason: [sloppy] SyntaxError: invalid property name     at prod-ClassElement:255:3 

### `language/statements/with/set-mutable-binding-binding-deleted-with-typed-array-in-proto-chain.js`

- Features: TypedArray
- Reason: [sloppy] Error: Test262Error: Expected SameValue(«[object Object]», «undefined») to be true

### `language/statements/with/set-mutable-binding-idref-compound-assign-with-proxy-env.js`

- Features: Proxy, Reflect
- Reason: [sloppy] Error: Test262Error: Actual [has:p, get:Symbol(Symbol.unscopables), get:p, set:p, getOwnPropertyDescriptor:p, defineProperty:p] and expected [has:p, get:Symbol(Symbol.unscopables), has:p, get:p, has:p, set:p, getOwnPropertyDescriptor:p, defineProperty:p] should have the same contents. 

### `language/statements/with/set-mutable-binding-idref-with-proxy-env.js`

- Features: Proxy, Reflect
- Reason: [sloppy] Error: Test262Error: Actual [has:p, get:Symbol(Symbol.unscopables), set:p, getOwnPropertyDescriptor:p, defineProperty:p] and expected [has:p, get:Symbol(Symbol.unscopables), has:p, set:p, getOwnPropertyDescriptor:p, defineProperty:p] should have the same contents. 

## SKIP grouped by reason

| Reason | Tests |
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

_Generated by `debug/engines/compatibility`. A SKIP never counts as compatibility; it only records that the runner could not execute the test or that the feature is out of scope._
