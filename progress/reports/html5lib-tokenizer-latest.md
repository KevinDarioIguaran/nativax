# Conformidad: html5lib-tokenizer

- Fecha: 2026-10-25T01:50:03.168060Z
- Duración: 0.5 s
- Commit de la suite: `c777c408b61078ea2eb4acefc2535f54dbc8b28a`
- Comando: `run_html5lib`
- Total: **6827** tests
- Tasa de éxito (sin SKIP): **99.26 %**

| Estado | Tests |
|---|---:|
| PASS | 5759 |
| FAIL | 43 |
| SKIP | 1025 |
| ERROR | 0 |

## Delta contra la línea base

- Corregidos: **0**
- Regresiones: **0**
- Siguen fallando: **43**
- Nuevos en esta ejecución: **0**
- Ausentes respecto a la base: **0**

## Por característica

| Grupo | PASS | FAIL | SKIP | ERROR | Éxito |
|---|---:|---:|---:|---:|---:|
| `html-tokenizer` | 5759 | 43 | 1025 | 0 | 99.3 % |
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
| `domjs.test#0 [tests] CR in bogus comment state` | 1 | 0 | 0 | 0 | 100.0 % |
| `domjs.test#1 [tests] CRLF in bogus comment state` | 1 | 0 | 0 | 0 | 100.0 % |
| `domjs.test#2 [tests] CRLFLF in bogus comment state` | 1 | 0 | 0 | 0 | 100.0 % |
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
| `domjs.test#33 [tests] --!NUL in comment ` | 1 | 0 | 0 | 0 | 100.0 % |
| `domjs.test#34 [tests] space EOF after doctype ` | 0 | 0 | 1 | 0 | 0.0 % |
| `domjs.test#35 [tests] CDATA in HTML content` | 1 | 0 | 0 | 0 | 100.0 % |
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
| `entities.test#14 [tests] Windows-1252 EURO SIGN numeric entity.` | 1 | 0 | 0 | 0 | 100.0 % |
| `entities.test#15 [tests] Windows-1252 REPLACEMENT CHAR numeric entity.` | 1 | 0 | 0 | 0 | 100.0 % |
| `entities.test#16 [tests] Windows-1252 SINGLE LOW-9 QUOTATION MARK numeric entity.` | 1 | 0 | 0 | 0 | 100.0 % |
| `entities.test#17 [tests] Windows-1252 LATIN SMALL LETTER F WITH HOOK numeric entity.` | 1 | 0 | 0 | 0 | 100.0 % |
| `entities.test#18 [tests] Windows-1252 DOUBLE LOW-9 QUOTATION MARK numeric entity.` | 1 | 0 | 0 | 0 | 100.0 % |
| `entities.test#19 [tests] Windows-1252 HORIZONTAL ELLIPSIS numeric entity.` | 1 | 0 | 0 | 0 | 100.0 % |
| `entities.test#20 [tests] Windows-1252 DAGGER numeric entity.` | 1 | 0 | 0 | 0 | 100.0 % |
| `entities.test#21 [tests] Windows-1252 DOUBLE DAGGER numeric entity.` | 1 | 0 | 0 | 0 | 100.0 % |
| `entities.test#22 [tests] Windows-1252 MODIFIER LETTER CIRCUMFLEX ACCENT numeric entity.` | 1 | 0 | 0 | 0 | 100.0 % |
| _(+6747 grupos)_ | | | | | |

## Fallos (43)

### `test1.test#22 [tests] Unfinished comment after start of nested comment`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!-- <!--"
expected: [["Comment"," <!"]]
actual:   [["Comment"," <!--"]]
errors: eof-in-comment@0
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

### `test3.test#106 [tests] <!-- -`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!-- -"
expected: [["Comment"," "]]
actual:   [["Comment"," -"]]
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

### `test3.test#178 [tests] <!----`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<!----"
expected: [["Comment",""]]
actual:   [["Comment","--"]]
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

### `test3.test#1158 [tests] <?`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<?"
expected: []
actual:   [["Comment","?"]]
errors: unexpected-question-mark-instead-of-tag-name@0
```

### `test3.test#1159 [tests] <?a`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<?a"
expected: []
actual:   [["Comment","?a"]]
errors: unexpected-question-mark-instead-of-tag-name@0
```

### `test3.test#1160 [tests] <?b`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<?b"
expected: []
actual:   [["Comment","?b"]]
errors: unexpected-question-mark-instead-of-tag-name@0
```

### `test3.test#1161 [tests] <?y`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<?y"
expected: []
actual:   [["Comment","?y"]]
errors: unexpected-question-mark-instead-of-tag-name@0
```

### `test3.test#1162 [tests] <?z`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<?z"
expected: []
actual:   [["Comment","?z"]]
errors: unexpected-question-mark-instead-of-tag-name@0
```

### `test3.test#1163 [tests] <?A`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<?A"
expected: []
actual:   [["Comment","?A"]]
errors: unexpected-question-mark-instead-of-tag-name@0
```

### `test3.test#1164 [tests] <?B`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<?B"
expected: []
actual:   [["Comment","?B"]]
errors: unexpected-question-mark-instead-of-tag-name@0
```

### `test3.test#1165 [tests] <?Y`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<?Y"
expected: []
actual:   [["Comment","?Y"]]
errors: unexpected-question-mark-instead-of-tag-name@0
```

### `test3.test#1166 [tests] <?Z`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<?Z"
expected: []
actual:   [["Comment","?Z"]]
errors: unexpected-question-mark-instead-of-tag-name@0
```

### `test3.test#1167 [tests] <?a a`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<?a a"
expected: []
actual:   [["Comment","?a a"]]
errors: unexpected-question-mark-instead-of-tag-name@0
```

### `test3.test#1168 [tests] <?b b`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<?b b"
expected: []
actual:   [["Comment","?b b"]]
errors: unexpected-question-mark-instead-of-tag-name@0
```

### `test3.test#1169 [tests] <?y y`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<?y y"
expected: []
actual:   [["Comment","?y y"]]
errors: unexpected-question-mark-instead-of-tag-name@0
```

### `test3.test#1170 [tests] <?z z`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<?z z"
expected: []
actual:   [["Comment","?z z"]]
errors: unexpected-question-mark-instead-of-tag-name@0
```

### `test3.test#1171 [tests] <?A A`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<?A A"
expected: []
actual:   [["Comment","?A A"]]
errors: unexpected-question-mark-instead-of-tag-name@0
```

### `test3.test#1172 [tests] <?B B`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<?B B"
expected: []
actual:   [["Comment","?B B"]]
errors: unexpected-question-mark-instead-of-tag-name@0
```

### `test3.test#1173 [tests] <?Y Y`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<?Y Y"
expected: []
actual:   [["Comment","?Y Y"]]
errors: unexpected-question-mark-instead-of-tag-name@0
```

### `test3.test#1174 [tests] <?Z Z?`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<?Z Z?"
expected: []
actual:   [["Comment","?Z Z?"]]
errors: unexpected-question-mark-instead-of-tag-name@0
```

### `test3.test#1175 [tests] <?a a?`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<?a a"
expected: []
actual:   [["Comment","?a a"]]
errors: unexpected-question-mark-instead-of-tag-name@0
```

### `test3.test#1176 [tests] <?b b?`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<?b b"
expected: []
actual:   [["Comment","?b b"]]
errors: unexpected-question-mark-instead-of-tag-name@0
```

### `test3.test#1177 [tests] <?y y?`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<?y y"
expected: []
actual:   [["Comment","?y y"]]
errors: unexpected-question-mark-instead-of-tag-name@0
```

### `test3.test#1178 [tests] <?z z?`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<?z z"
expected: []
actual:   [["Comment","?z z"]]
errors: unexpected-question-mark-instead-of-tag-name@0
```

### `test3.test#1179 [tests] <?A A?`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<?A A"
expected: []
actual:   [["Comment","?A A"]]
errors: unexpected-question-mark-instead-of-tag-name@0
```

### `test3.test#1180 [tests] <?B B?`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<?B B"
expected: []
actual:   [["Comment","?B B"]]
errors: unexpected-question-mark-instead-of-tag-name@0
```

### `test3.test#1181 [tests] <?Y Y?`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<?Y Y"
expected: []
actual:   [["Comment","?Y Y"]]
errors: unexpected-question-mark-instead-of-tag-name@0
```

### `test3.test#1182 [tests] <?Z Z?`

- Características: html-tokenizer
- Motivo: token stream differs from the fixture

```text
input: "<?Z Z"
expected: []
actual:   [["Comment","?Z Z"]]
errors: unexpected-question-mark-instead-of-tag-name@0
```

## SKIP agrupados por motivo

| Motivo | Tests |
|---|---:|
| DoctypeToken only exposes the name; public/system identifiers and the force-quirks flag are not available to the runner | 855 |
| tokenizer only runs from the Data state; arbitrary initial states are not exposed | 166 |
| runner does not implement xmlViolation mode | 4 |

---

_Generado por `tools/conformance`. Un SKIP no cuenta como compatibilidad; mide únicamente que el runner no pudo ejecutar el test o que la característica está fuera de alcance._
