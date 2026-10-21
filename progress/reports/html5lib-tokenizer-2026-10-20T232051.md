# Conformidad: html5lib-tokenizer

- Fecha: 2026-10-21T04:20:51.191960Z
- Duración: 0.1 s
- Commit de la suite: `c777c408b61078ea2eb4acefc2535f54dbc8b28a`
- Comando: `run_html5lib`
- Total: **6827** tests
- Tasa de éxito (sin SKIP): **96.95 %**

| Estado | Tests |
|---|---:|
| PASS | 5625 |
| FAIL | 177 |
| SKIP | 1025 |
| ERROR | 0 |

## Delta contra la línea base

- Corregidos: **0**
- Regresiones: **0**
- Siguen fallando: **177**
- Nuevos en esta ejecución: **0**
- Ausentes respecto a la base: **0**

## Por característica

| Grupo | PASS | FAIL | SKIP | ERROR | Éxito |
|---|---:|---:|---:|---:|---:|
| `html-tokenizer` | 5625 | 177 | 1025 | 0 | 96.9 % |
| `doctype` | 0 | 0 | 855 | 0 | 0.0 % |

## Por directorio

| Grupo | PASS | FAIL | SKIP | ERROR | Éxito |
|---|---:|---:|---:|---:|---:|
| `namedEntities.test#2134 [tests] Named entity: grave; with a semi-colon` | 1 | 0 | 0 | 0 | 100.0 % |
| `contentModelFlags.test#1 [tests] PLAINTEXT with seeming close tag` | 0 | 0 | 1 | 0 | 0.0 % |
| `contentModelFlags.test#2 [tests] End tag closing RCDATA or RAWTEXT` | 0 | 0 | 1 | 0 | 0.0 % |
| `contentModelFlags.test#3 [tests] End tag closing RCDATA or RAWTEXT (case-insensitivity)` | 0 | 0 | 1 | 0 | 0.0 % |
| `contentModelFlags.test#4 [tests] End tag closing RCDATA or RAWTEXT (ending with space)` | 0 | 0 | 1 | 0 | 0.0 % |
| `contentModelFlags.test#5 [tests] End tag closing RCDATA or RAWTEXT (ending with EOF)` | 0 | 0 | 1 | 0 | 0.0 % |
| `contentModelFlags.test#6 [tests] End tag closing RCDATA or RAWTEXT (ending with slash)` | 0 | 0 | 1 | 0 | 0.0 % |
| `contentModelFlags.test#7 [tests] End tag not closing RCDATA or RAWTEXT (ending with left-angle-bracket)` | 0 | 0 | 1 | 0 | 0.0 % |
| `contentModelFlags.test#8 [tests] End tag with incorrect name in RCDATA or RAWTEXT` | 0 | 0 | 1 | 0 | 0.0 % |
| `contentModelFlags.test#9 [tests] Partial end tags leading straight into partial end tags` | 0 | 0 | 1 | 0 | 0.0 % |
| `contentModelFlags.test#10 [tests] End tag with incorrect name in RCDATA or RAWTEXT (starting like correct name)` | 0 | 0 | 1 | 0 | 0.0 % |
| `contentModelFlags.test#11 [tests] End tag closing RCDATA or RAWTEXT, switching back to PCDATA` | 0 | 0 | 1 | 0 | 0.0 % |
| `contentModelFlags.test#12 [tests] RAWTEXT w/ something looking like an entity` | 0 | 0 | 1 | 0 | 0.0 % |
| `contentModelFlags.test#13 [tests] RCDATA w/ an entity` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#0 [tests] CR in bogus comment state` | 0 | 1 | 0 | 0 | 0.0 % |
| `domjs.test#1 [tests] CRLF in bogus comment state` | 0 | 1 | 0 | 0 | 0.0 % |
| `domjs.test#2 [tests] CRLFLF in bogus comment state` | 0 | 1 | 0 | 0 | 0.0 % |
| `domjs.test#3 [tests] Raw NUL replacement` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#4 [tests] NUL in CDATA section` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#5 [tests] NUL in script HTML comment` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#6 [tests] NUL in script HTML comment - double escaped` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#7 [tests] EOF in script HTML comment` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#8 [tests] EOF in script HTML comment after dash` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#9 [tests] EOF in script HTML comment after dash dash` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#10 [tests] EOF in script HTML comment double escaped after dash` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#11 [tests] EOF in script HTML comment double escaped after dash dash` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#12 [tests] EOF in script HTML comment - double escaped` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#13 [tests] Dash in script HTML comment` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#14 [tests] Dash less-than in script HTML comment` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#15 [tests] Dash at end of script HTML comment` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#16 [tests] </script> in script HTML comment` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#17 [tests] </script> in script HTML comment - double escaped` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#18 [tests] </script> in script HTML comment - double escaped with nested <script>` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#19 [tests] </script> in script HTML comment - double escaped with abrupt end` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#20 [tests] Incomplete start tag in script HTML comment double escaped` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#21 [tests] Unclosed start tag in script HTML comment double escaped` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#22 [tests] Incomplete end tag in script HTML comment double escaped` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#23 [tests] Unclosed end tag in script HTML comment double escaped` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#24 [tests] leading U+FEFF must pass through` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#25 [tests] Non BMP-charref in RCDATA` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#26 [tests] Bad charref in RCDATA` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#27 [tests] lowercase endtags` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#28 [tests] bad endtag (space before name)` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#29 [tests] bad endtag (not matching last start tag)` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#30 [tests] bad endtag (without close bracket)` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#31 [tests] bad endtag (trailing solidus)` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#32 [tests] Non BMP-charref in attribute` | 1 | 0 | 0 | 0 | 100.0 % |
| `domjs.test#33 [tests] --!NUL in comment ` | 0 | 1 | 0 | 0 | 0.0 % |
| `domjs.test#34 [tests] space EOF after doctype ` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#35 [tests] CDATA in HTML content` | 0 | 1 | 0 | 0 | 0.0 % |
| `domjs.test#36 [tests] CDATA content` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#37 [tests] CDATA followed by HTML content` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#38 [tests] CDATA with extra bracket` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#39 [tests] CDATA without end marker` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#40 [tests] CDATA with single bracket ending` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#41 [tests] CDATA with two brackets ending` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#42 [tests] HTML tag in script data` | 0 | 0 | 1 | 0 | 0.0 % |
| `entities.test#0 [tests] Undefined named entity in a double-quoted attribute value ending in semicolon and whose name starts with a known entity name.` | 1 | 0 | 0 | 0 | 100.0 % |
| `entities.test#1 [tests] Entity name requiring semicolon instead followed by the equals sign in a double-quoted attribute value.` | 1 | 0 | 0 | 0 | 100.0 % |
| `entities.test#2 [tests] Valid entity name followed by the equals sign in a double-quoted attribute value.` | 1 | 0 | 0 | 0 | 100.0 % |
| `entities.test#3 [tests] Undefined named entity in a single-quoted attribute value ending in semicolon and whose name starts with a known entity name.` | 1 | 0 | 0 | 0 | 100.0 % |
| `entities.test#4 [tests] Entity name requiring semicolon instead followed by the equals sign in a single-quoted attribute value.` | 1 | 0 | 0 | 0 | 100.0 % |
| `entities.test#5 [tests] Valid entity name followed by the equals sign in a single-quoted attribute value.` | 1 | 0 | 0 | 0 | 100.0 % |
| `entities.test#6 [tests] Undefined named entity in an unquoted attribute value ending in semicolon and whose name starts with a known entity name.` | 1 | 0 | 0 | 0 | 100.0 % |
| `entities.test#7 [tests] Entity name requiring semicolon instead followed by the equals sign in an unquoted attribute value.` | 1 | 0 | 0 | 0 | 100.0 % |
| `entities.test#8 [tests] Valid entity name followed by the equals sign in an unquoted attribute value.` | 1 | 0 | 0 | 0 | 100.0 % |
| `entities.test#9 [tests] Ambiguous ampersand.` | 1 | 0 | 0 | 0 | 100.0 % |
| `entities.test#10 [tests] Semicolonless named entity 'not' followed by 'i;' in body` | 1 | 0 | 0 | 0 | 100.0 % |
| `entities.test#11 [tests] Very long undefined named entity in body` | 1 | 0 | 0 | 0 | 100.0 % |
| `entities.test#12 [tests] CR as numeric entity` | 1 | 0 | 0 | 0 | 100.0 % |
| `entities.test#13 [tests] CR as hexadecimal numeric entity` | 1 | 0 | 0 | 0 | 100.0 % |
| `entities.test#14 [tests] Windows-1252 EURO SIGN numeric entity.` | 0 | 1 | 0 | 0 | 0.0 % |
| `entities.test#15 [tests] Windows-1252 REPLACEMENT CHAR numeric entity.` | 1 | 0 | 0 | 0 | 100.0 % |
| `entities.test#16 [tests] Windows-1252 SINGLE LOW-9 QUOTATION MARK numeric entity.` | 0 | 1 | 0 | 0 | 0.0 % |
| `entities.test#17 [tests] Windows-1252 LATIN SMALL LETTER F WITH HOOK numeric entity.` | 0 | 1 | 0 | 0 | 0.0 % |
| `entities.test#18 [tests] Windows-1252 DOUBLE LOW-9 QUOTATION MARK numeric entity.` | 0 | 1 | 0 | 0 | 0.0 % |
| `entities.test#19 [tests] Windows-1252 HORIZONTAL ELLIPSIS numeric entity.` | 0 | 1 | 0 | 0 | 0.0 % |
| `entities.test#20 [tests] Windows-1252 DAGGER numeric entity.` | 0 | 1 | 0 | 0 | 0.0 % |
| `entities.test#21 [tests] Windows-1252 DOUBLE DAGGER numeric entity.` | 0 | 1 | 0 | 0 | 0.0 % |
| `entities.test#22 [tests] Windows-1252 MODIFIER LETTER CIRCUMFLEX ACCENT numeric entity.` | 0 | 1 | 0 | 0 | 0.0 % |
| _(+6747 grupos)_ | | | | | |

## Fallos (177)

### `domjs.test#0 [tests] CR in bogus comment state`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<?\r"
expected: [["Comment","?\n"]]
actual:   [["Comment","?\r"]]
errors: unexpected-question-mark-instead-of-tag-name@0
```

### `domjs.test#1 [tests] CRLF in bogus comment state`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<?\r\n"
expected: [["Comment","?\n"]]
actual:   [["Comment","?\r\n"]]
errors: unexpected-question-mark-instead-of-tag-name@0
```

### `domjs.test#2 [tests] CRLFLF in bogus comment state`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<?\r\n\n"
expected: [["Comment","?\n\n"]]
actual:   [["Comment","?\r\n\n"]]
errors: unexpected-question-mark-instead-of-tag-name@0
```

### `domjs.test#33 [tests] --!NUL in comment `

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!----!\u0000-->"
expected: [["Comment","--!�"]]
actual:   [["Comment","--!\u0000"]]
```

### `domjs.test#35 [tests] CDATA in HTML content`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<![CDATA[foo]]>"
expected: [["Comment","[CDATA[foo]]"]]
actual:   [["Comment","![CDATA[foo]]"]]
errors: incorrectly-opened-comment@0
```

### `entities.test#14 [tests] Windows-1252 EURO SIGN numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#0128;"
expected: [["Character","€"]]
actual:   [["Character",""]]
```

### `entities.test#16 [tests] Windows-1252 SINGLE LOW-9 QUOTATION MARK numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#0130;"
expected: [["Character","‚"]]
actual:   [["Character",""]]
```

### `entities.test#17 [tests] Windows-1252 LATIN SMALL LETTER F WITH HOOK numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#0131;"
expected: [["Character","ƒ"]]
actual:   [["Character",""]]
```

### `entities.test#18 [tests] Windows-1252 DOUBLE LOW-9 QUOTATION MARK numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#0132;"
expected: [["Character","„"]]
actual:   [["Character",""]]
```

### `entities.test#19 [tests] Windows-1252 HORIZONTAL ELLIPSIS numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#0133;"
expected: [["Character","…"]]
actual:   [["Character",""]]
```

### `entities.test#20 [tests] Windows-1252 DAGGER numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#0134;"
expected: [["Character","†"]]
actual:   [["Character",""]]
```

### `entities.test#21 [tests] Windows-1252 DOUBLE DAGGER numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#0135;"
expected: [["Character","‡"]]
actual:   [["Character",""]]
```

### `entities.test#22 [tests] Windows-1252 MODIFIER LETTER CIRCUMFLEX ACCENT numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#0136;"
expected: [["Character","ˆ"]]
actual:   [["Character",""]]
```

### `entities.test#23 [tests] Windows-1252 PER MILLE SIGN numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#0137;"
expected: [["Character","‰"]]
actual:   [["Character",""]]
```

### `entities.test#24 [tests] Windows-1252 LATIN CAPITAL LETTER S WITH CARON numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#0138;"
expected: [["Character","Š"]]
actual:   [["Character",""]]
```

### `entities.test#25 [tests] Windows-1252 SINGLE LEFT-POINTING ANGLE QUOTATION MARK numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#0139;"
expected: [["Character","‹"]]
actual:   [["Character",""]]
```

### `entities.test#26 [tests] Windows-1252 LATIN CAPITAL LIGATURE OE numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#0140;"
expected: [["Character","Œ"]]
actual:   [["Character",""]]
```

### `entities.test#28 [tests] Windows-1252 LATIN CAPITAL LETTER Z WITH CARON numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#0142;"
expected: [["Character","Ž"]]
actual:   [["Character",""]]
```

### `entities.test#31 [tests] Windows-1252 LEFT SINGLE QUOTATION MARK numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#0145;"
expected: [["Character","‘"]]
actual:   [["Character",""]]
```

### `entities.test#32 [tests] Windows-1252 RIGHT SINGLE QUOTATION MARK numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#0146;"
expected: [["Character","’"]]
actual:   [["Character",""]]
```

### `entities.test#33 [tests] Windows-1252 LEFT DOUBLE QUOTATION MARK numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#0147;"
expected: [["Character","“"]]
actual:   [["Character",""]]
```

### `entities.test#34 [tests] Windows-1252 RIGHT DOUBLE QUOTATION MARK numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#0148;"
expected: [["Character","”"]]
actual:   [["Character",""]]
```

### `entities.test#35 [tests] Windows-1252 BULLET numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#0149;"
expected: [["Character","•"]]
actual:   [["Character",""]]
```

### `entities.test#36 [tests] Windows-1252 EN DASH numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#0150;"
expected: [["Character","–"]]
actual:   [["Character",""]]
```

### `entities.test#37 [tests] Windows-1252 EM DASH numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#0151;"
expected: [["Character","—"]]
actual:   [["Character",""]]
```

### `entities.test#38 [tests] Windows-1252 SMALL TILDE numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#0152;"
expected: [["Character","˜"]]
actual:   [["Character",""]]
```

### `entities.test#39 [tests] Windows-1252 TRADE MARK SIGN numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#0153;"
expected: [["Character","™"]]
actual:   [["Character",""]]
```

### `entities.test#40 [tests] Windows-1252 LATIN SMALL LETTER S WITH CARON numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#0154;"
expected: [["Character","š"]]
actual:   [["Character",""]]
```

### `entities.test#41 [tests] Windows-1252 SINGLE RIGHT-POINTING ANGLE QUOTATION MARK numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#0155;"
expected: [["Character","›"]]
actual:   [["Character",""]]
```

### `entities.test#42 [tests] Windows-1252 LATIN SMALL LIGATURE OE numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#0156;"
expected: [["Character","œ"]]
actual:   [["Character",""]]
```

### `entities.test#44 [tests] Windows-1252 EURO SIGN hexadecimal numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#x080;"
expected: [["Character","€"]]
actual:   [["Character",""]]
```

### `entities.test#46 [tests] Windows-1252 SINGLE LOW-9 QUOTATION MARK hexadecimal numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#x082;"
expected: [["Character","‚"]]
actual:   [["Character",""]]
```

### `entities.test#47 [tests] Windows-1252 LATIN SMALL LETTER F WITH HOOK hexadecimal numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#x083;"
expected: [["Character","ƒ"]]
actual:   [["Character",""]]
```

### `entities.test#48 [tests] Windows-1252 DOUBLE LOW-9 QUOTATION MARK hexadecimal numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#x084;"
expected: [["Character","„"]]
actual:   [["Character",""]]
```

### `entities.test#49 [tests] Windows-1252 HORIZONTAL ELLIPSIS hexadecimal numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#x085;"
expected: [["Character","…"]]
actual:   [["Character",""]]
```

### `entities.test#50 [tests] Windows-1252 DAGGER hexadecimal numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#x086;"
expected: [["Character","†"]]
actual:   [["Character",""]]
```

### `entities.test#51 [tests] Windows-1252 DOUBLE DAGGER hexadecimal numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#x087;"
expected: [["Character","‡"]]
actual:   [["Character",""]]
```

### `entities.test#52 [tests] Windows-1252 MODIFIER LETTER CIRCUMFLEX ACCENT hexadecimal numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#x088;"
expected: [["Character","ˆ"]]
actual:   [["Character",""]]
```

### `entities.test#53 [tests] Windows-1252 PER MILLE SIGN hexadecimal numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#x089;"
expected: [["Character","‰"]]
actual:   [["Character",""]]
```

### `entities.test#54 [tests] Windows-1252 LATIN CAPITAL LETTER S WITH CARON hexadecimal numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#x08A;"
expected: [["Character","Š"]]
actual:   [["Character",""]]
```

### `entities.test#55 [tests] Windows-1252 SINGLE LEFT-POINTING ANGLE QUOTATION MARK hexadecimal numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#x08B;"
expected: [["Character","‹"]]
actual:   [["Character",""]]
```

### `entities.test#56 [tests] Windows-1252 LATIN CAPITAL LIGATURE OE hexadecimal numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#x08C;"
expected: [["Character","Œ"]]
actual:   [["Character",""]]
```

### `entities.test#58 [tests] Windows-1252 LATIN CAPITAL LETTER Z WITH CARON hexadecimal numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#x08E;"
expected: [["Character","Ž"]]
actual:   [["Character",""]]
```

### `entities.test#61 [tests] Windows-1252 LEFT SINGLE QUOTATION MARK hexadecimal numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#x091;"
expected: [["Character","‘"]]
actual:   [["Character",""]]
```

### `entities.test#62 [tests] Windows-1252 RIGHT SINGLE QUOTATION MARK hexadecimal numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#x092;"
expected: [["Character","’"]]
actual:   [["Character",""]]
```

### `entities.test#63 [tests] Windows-1252 LEFT DOUBLE QUOTATION MARK hexadecimal numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#x093;"
expected: [["Character","“"]]
actual:   [["Character",""]]
```

### `entities.test#64 [tests] Windows-1252 RIGHT DOUBLE QUOTATION MARK hexadecimal numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#x094;"
expected: [["Character","”"]]
actual:   [["Character",""]]
```

### `entities.test#65 [tests] Windows-1252 BULLET hexadecimal numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#x095;"
expected: [["Character","•"]]
actual:   [["Character",""]]
```

### `entities.test#66 [tests] Windows-1252 EN DASH hexadecimal numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#x096;"
expected: [["Character","–"]]
actual:   [["Character",""]]
```

### `entities.test#67 [tests] Windows-1252 EM DASH hexadecimal numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#x097;"
expected: [["Character","—"]]
actual:   [["Character",""]]
```

### `entities.test#68 [tests] Windows-1252 SMALL TILDE hexadecimal numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#x098;"
expected: [["Character","˜"]]
actual:   [["Character",""]]
```

### `entities.test#69 [tests] Windows-1252 TRADE MARK SIGN hexadecimal numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#x099;"
expected: [["Character","™"]]
actual:   [["Character",""]]
```

### `entities.test#70 [tests] Windows-1252 LATIN SMALL LETTER S WITH CARON hexadecimal numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#x09A;"
expected: [["Character","š"]]
actual:   [["Character",""]]
```

### `entities.test#71 [tests] Windows-1252 SINGLE RIGHT-POINTING ANGLE QUOTATION MARK hexadecimal numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#x09B;"
expected: [["Character","›"]]
actual:   [["Character",""]]
```

### `entities.test#72 [tests] Windows-1252 LATIN SMALL LIGATURE OE hexadecimal numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#x09C;"
expected: [["Character","œ"]]
actual:   [["Character",""]]
```

### `entities.test#74 [tests] Windows-1252 LATIN SMALL LETTER Z WITH CARON hexadecimal numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#x09E;"
expected: [["Character","ž"]]
actual:   [["Character",""]]
```

### `entities.test#75 [tests] Windows-1252 LATIN CAPITAL LETTER Y WITH DIAERESIS hexadecimal numeric entity.`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "&#x09F;"
expected: [["Character","Ÿ"]]
actual:   [["Character",""]]
```

### `test1.test#4 [tests] Truncated doctype start`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!DOC>"
expected: [["Comment","DOC"]]
actual:   [["Comment","!DOC"]]
errors: incorrectly-opened-comment@0
```

### `test1.test#7 [tests] Empty end tag`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "</>"
expected: []
actual:   [["Character","<"]]
errors: missing-end-tag-name@0
```

### `test1.test#22 [tests] Unfinished comment after start of nested comment`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!-- <!--"
expected: [["Comment"," <!"]]
actual:   [["Comment"," <!--"]]
errors: eof-in-comment@0
```

### `test1.test#23 [tests] Start of a comment`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!-"
expected: [["Comment","-"]]
actual:   [["Comment","!-"]]
errors: incorrectly-opened-comment@0
```

### `test1.test#24 [tests] Short comment`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!-->"
expected: [["Comment",""]]
actual:   [["Comment",">"]]
errors: eof-in-comment@0
```

### `test1.test#25 [tests] Short comment two`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!--->"
expected: [["Comment",""]]
actual:   [["Comment","->"]]
errors: eof-in-comment@0
```

### `test2.test#31 [tests] Processing instruction`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<?namespace>"
expected: [["ProcessingInstruction","namespace",""]]
actual:   [["Comment","?namespace"]]
errors: unexpected-question-mark-instead-of-tag-name@0
```

### `test2.test#32 [tests] A processing instruction delimited by ?> doesn't contain the delimiting ?`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<?foo bar?>"
expected: [["ProcessingInstruction","foo","bar"]]
actual:   [["Comment","?foo bar?"]]
errors: unexpected-question-mark-instead-of-tag-name@0
```

### `test2.test#33 [tests] A processing instruction's data delimited by ?> contains the correct amount of ?`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<?foo bar??>"
expected: [["ProcessingInstruction","foo","bar?"]]
actual:   [["Comment","?foo bar??"]]
errors: unexpected-question-mark-instead-of-tag-name@0
```

### `test2.test#42 [tests] Empty end tag with following characters`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "a</>bc"
expected: [["Character","abc"]]
actual:   [["Character","a<bc"]]
errors: missing-end-tag-name@1
```

### `test2.test#43 [tests] Empty end tag with following tag`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "a</><b>c"
expected: [["Character","a"],["StartTag","b",{}],["Character","c"]]
actual:   [["Character","a<"],["StartTag","b",{}],["Character","c"]]
errors: missing-end-tag-name@1
```

### `test2.test#44 [tests] Empty end tag with following comment`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "a</><!--b-->c"
expected: [["Character","a"],["Comment","b"],["Character","c"]]
actual:   [["Character","a<"],["Comment","b"],["Character","c"]]
errors: missing-end-tag-name@1
```

### `test2.test#45 [tests] Empty end tag with following end tag`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "a</></b>c"
expected: [["Character","a"],["EndTag","b"],["Character","c"]]
actual:   [["Character","a<"],["EndTag","b"],["Character","c"]]
errors: missing-end-tag-name@1
```

### `test3.test#75 [tests] <!`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!"
expected: [["Comment",""]]
actual:   [["Comment","!"]]
errors: incorrectly-opened-comment@0
```

### `test3.test#76 [tests] <!\u0000`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!\u0000"
expected: [["Comment","�"]]
actual:   [["Comment","!\u0000"]]
errors: incorrectly-opened-comment@0
```

### `test3.test#77 [tests] <!\u0009`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!\t"
expected: [["Comment","\t"]]
actual:   [["Comment","!\t"]]
errors: incorrectly-opened-comment@0
```

### `test3.test#78 [tests] <!\u000A`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!\n"
expected: [["Comment","\n"]]
actual:   [["Comment","!\n"]]
errors: incorrectly-opened-comment@0
```

### `test3.test#79 [tests] <!\u000B`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!\u000b"
expected: [["Comment","\u000b"]]
actual:   [["Comment","!\u000b"]]
errors: incorrectly-opened-comment@0
```

### `test3.test#80 [tests] <!\u000C`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!\f"
expected: [["Comment","\f"]]
actual:   [["Comment","!\f"]]
errors: incorrectly-opened-comment@0
```

### `test3.test#81 [tests] <! `

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<! "
expected: [["Comment"," "]]
actual:   [["Comment","! "]]
errors: incorrectly-opened-comment@0
```

### `test3.test#82 [tests] <! \u0000`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<! \u0000"
expected: [["Comment"," �"]]
actual:   [["Comment","! \u0000"]]
errors: incorrectly-opened-comment@0
```

### `test3.test#83 [tests] <!!`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!!"
expected: [["Comment","!"]]
actual:   [["Comment","!!"]]
errors: incorrectly-opened-comment@0
```

### `test3.test#84 [tests] <!"`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!\""
expected: [["Comment","\""]]
actual:   [["Comment","!\""]]
errors: incorrectly-opened-comment@0
```

### `test3.test#85 [tests] <!&`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!&"
expected: [["Comment","&"]]
actual:   [["Comment","!&"]]
errors: incorrectly-opened-comment@0
```

### `test3.test#86 [tests] <!'`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!'"
expected: [["Comment","'"]]
actual:   [["Comment","!'"]]
errors: incorrectly-opened-comment@0
```

### `test3.test#87 [tests] <!-`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!-"
expected: [["Comment","-"]]
actual:   [["Comment","!-"]]
errors: incorrectly-opened-comment@0
```

### `test3.test#89 [tests] <!--\u0000`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!--\u0000"
expected: [["Comment","�"]]
actual:   [["Comment","\u0000"]]
errors: eof-in-comment@0
```

### `test3.test#95 [tests] <!-- \u0000`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!-- \u0000"
expected: [["Comment"," �"]]
actual:   [["Comment"," \u0000"]]
errors: eof-in-comment@0
```

### `test3.test#106 [tests] <!-- -`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!-- -"
expected: [["Comment"," "]]
actual:   [["Comment"," -"]]
errors: eof-in-comment@0
```

### `test3.test#107 [tests] <!-- -\u0000`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!-- -\u0000"
expected: [["Comment"," -�"]]
actual:   [["Comment"," -\u0000"]]
errors: eof-in-comment@0
```

### `test3.test#118 [tests] <!-- --`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!-- --"
expected: [["Comment"," "]]
actual:   [["Comment"," --"]]
errors: eof-in-comment@0
```

### `test3.test#166 [tests] <!---`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!---"
expected: [["Comment",""]]
actual:   [["Comment","-"]]
errors: eof-in-comment@0
```

### `test3.test#167 [tests] <!---\u0000`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!---\u0000"
expected: [["Comment","-�"]]
actual:   [["Comment","-\u0000"]]
errors: eof-in-comment@0
```

### `test3.test#178 [tests] <!----`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!----"
expected: [["Comment",""]]
actual:   [["Comment","--"]]
errors: eof-in-comment@0
```

### `test3.test#179 [tests] <!----\u0000`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!----\u0000"
expected: [["Comment","--�"]]
actual:   [["Comment","--\u0000"]]
errors: eof-in-comment@0
```

### `test3.test#185 [tests] <!---- -`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!---- -"
expected: [["Comment","-- "]]
actual:   [["Comment","-- -"]]
errors: eof-in-comment@0
```

### `test3.test#186 [tests] <!---- --`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!---- --"
expected: [["Comment","-- "]]
actual:   [["Comment","-- --"]]
errors: eof-in-comment@0
```

### `test3.test#190 [tests] <!----!`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!----!"
expected: [["Comment",""]]
actual:   [["Comment","--!"]]
errors: eof-in-comment@0
```

### `test3.test#191 [tests] <!----!>`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!----!>"
expected: [["Comment",""]]
actual:   [["Comment","--!>"]]
errors: eof-in-comment@0
```

### `test3.test#194 [tests] <!----!CR>`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!----!\r>"
expected: [["Comment","--!\n>"]]
actual:   [["Comment","--!\r>"]]
errors: eof-in-comment@0
```

### `test3.test#195 [tests] <!----!CRLF>`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!----!\r\n>"
expected: [["Comment","--!\n>"]]
actual:   [["Comment","--!\r\n>"]]
errors: eof-in-comment@0
```

### `test3.test#197 [tests] <!----!a-`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!----!a-"
expected: [["Comment","--!a"]]
actual:   [["Comment","--!a-"]]
errors: eof-in-comment@0
```

### `test3.test#198 [tests] <!----!a--`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!----!a--"
expected: [["Comment","--!a"]]
actual:   [["Comment","--!a--"]]
errors: eof-in-comment@0
```

### `test3.test#200 [tests] <!----!-`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!----!-"
expected: [["Comment","--!"]]
actual:   [["Comment","--!-"]]
errors: eof-in-comment@0
```

### `test3.test#201 [tests] <!----!--`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!----!--"
expected: [["Comment","--!"]]
actual:   [["Comment","--!--"]]
errors: eof-in-comment@0
```

### `test3.test#207 [tests] <!-----`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!-----"
expected: [["Comment","-"]]
actual:   [["Comment","---"]]
errors: eof-in-comment@0
```

### `test3.test#269 [tests] <!/`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!/"
expected: [["Comment","/"]]
actual:   [["Comment","!/"]]
errors: incorrectly-opened-comment@0
```

### `test3.test#270 [tests] <!0`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!0"
expected: [["Comment","0"]]
actual:   [["Comment","!0"]]
errors: incorrectly-opened-comment@0
```

### `test3.test#271 [tests] <!1`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!1"
expected: [["Comment","1"]]
actual:   [["Comment","!1"]]
errors: incorrectly-opened-comment@0
```

### `test3.test#272 [tests] <!9`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!9"
expected: [["Comment","9"]]
actual:   [["Comment","!9"]]
errors: incorrectly-opened-comment@0
```

### `test3.test#273 [tests] <!<`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!<"
expected: [["Comment","<"]]
actual:   [["Comment","!<"]]
errors: incorrectly-opened-comment@0
```

### `test3.test#274 [tests] <!=`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!="
expected: [["Comment","="]]
actual:   [["Comment","!="]]
errors: incorrectly-opened-comment@0
```

### `test3.test#275 [tests] <!>`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!>"
expected: [["Comment",""]]
actual:   [["Comment","!"]]
errors: incorrectly-opened-comment@0
```

### `test3.test#276 [tests] <!?`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!?"
expected: [["Comment","?"]]
actual:   [["Comment","!?"]]
errors: incorrectly-opened-comment@0
```

### `test3.test#277 [tests] <!@`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!@"
expected: [["Comment","@"]]
actual:   [["Comment","!@"]]
errors: incorrectly-opened-comment@0
```

### `test3.test#278 [tests] <!A`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!A"
expected: [["Comment","A"]]
actual:   [["Comment","!A"]]
errors: incorrectly-opened-comment@0
```

### `test3.test#279 [tests] <!B`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!B"
expected: [["Comment","B"]]
actual:   [["Comment","!B"]]
errors: incorrectly-opened-comment@0
```

### `test3.test#1104 [tests] <!Y`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!Y"
expected: [["Comment","Y"]]
actual:   [["Comment","!Y"]]
errors: incorrectly-opened-comment@0
```

### `test3.test#1105 [tests] <!Z`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!Z"
expected: [["Comment","Z"]]
actual:   [["Comment","!Z"]]
errors: incorrectly-opened-comment@0
```

### `test3.test#1106 [tests] <!``

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!`"
expected: [["Comment","`"]]
actual:   [["Comment","!`"]]
errors: incorrectly-opened-comment@0
```

### `test3.test#1107 [tests] <!a`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!a"
expected: [["Comment","a"]]
actual:   [["Comment","!a"]]
errors: incorrectly-opened-comment@0
```

### `test3.test#1108 [tests] <!b`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!b"
expected: [["Comment","b"]]
actual:   [["Comment","!b"]]
errors: incorrectly-opened-comment@0
```

### `test3.test#1109 [tests] <!y`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!y"
expected: [["Comment","y"]]
actual:   [["Comment","!y"]]
errors: incorrectly-opened-comment@0
```

_… y 57 fallos más (ver el JSONL)._

## SKIP agrupados por motivo

| Motivo | Tests |
|---|---:|
| DoctypeToken only exposes the name; public/system identifiers and the force-quirks flag are not available to the runner | 855 |
| tokenizer only runs from the Data state; arbitrary initial states are not exposed | 166 |
| runner does not implement xmlViolation mode | 4 |

---

_Generado por `tools/conformance`. Un SKIP no cuenta como compatibilidad; mide únicamente que el runner no pudo ejecutar el test o que la característica está fuera de alcance._
