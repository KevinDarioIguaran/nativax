# Conformidad: wpt-url

- Fecha: 2026-10-21T22:22:34.626428Z
- Duración: 0.2 s
- Comando: `run_url`
- Total: **896** tests
- Tasa de éxito (sin SKIP): **74.22 %**

| Estado | Tests |
|---|---:|
| PASS | 665 |
| FAIL | 231 |
| SKIP | 0 |
| ERROR | 0 |

## Delta contra la línea base

- Corregidos: **18**
- Regresiones: **0**
- Siguen fallando: **231**
- Nuevos en esta ejecución: **0**
- Ausentes respecto a la base: **0**

## Por característica

| Grupo | PASS | FAIL | SKIP | ERROR | Éxito |
|---|---:|---:|---:|---:|---:|
| `url` | 665 | 231 | 0 | 0 | 74.2 % |

## Por directorio

| Grupo | PASS | FAIL | SKIP | ERROR | Éxito |
|---|---:|---:|---:|---:|---:|
| `#298 "http://10.0.0.xN--pokxncvks"` | 1 | 0 | 0 | 0 | 100.0 % |
| `#1 "http://user:pass@foo:21` | 1 | 0 | 0 | 0 | 100.0 % |
| `#2 "https://test:@test"` | 1 | 0 | 0 | 0 | 100.0 % |
| `#3 "https://:@test"` | 1 | 0 | 0 | 0 | 100.0 % |
| `#4 "non-special://test:@test` | 1 | 0 | 0 | 0 | 100.0 % |
| `#5 "non-special://:@test` | 1 | 0 | 0 | 0 | 100.0 % |
| `#6 "http:foo.com" base="http://example.org` | 1 | 0 | 0 | 0 | 100.0 % |
| `#7 "\t   :foo.com   \n" base="http://example.org` | 1 | 0 | 0 | 0 | 100.0 % |
| `#8 " foo.com  " base="http://example.org` | 1 | 0 | 0 | 0 | 100.0 % |
| `#9 "a:\t foo.com" base="http://example.org` | 0 | 1 | 0 | 0 | 0.0 % |
| `#10 "http://f:21` | 1 | 0 | 0 | 0 | 100.0 % |
| `#11 "lolscheme:x x#x x"` | 0 | 1 | 0 | 0 | 0.0 % |
| `#12 "http://f:` | 1 | 0 | 0 | 0 | 100.0 % |
| `#13 "http://f:0` | 1 | 0 | 0 | 0 | 100.0 % |
| `#14 "http://f:00000000000000` | 1 | 0 | 0 | 0 | 100.0 % |
| `#15 "http://f:00000000000000000000080` | 1 | 0 | 0 | 0 | 100.0 % |
| `#16 "http://f:b` | 1 | 0 | 0 | 0 | 100.0 % |
| `#17 "http://f: ` | 1 | 0 | 0 | 0 | 100.0 % |
| `#18 "http://f:\n` | 1 | 0 | 0 | 0 | 100.0 % |
| `#19 "http://f:fifty-two` | 1 | 0 | 0 | 0 | 100.0 % |
| `#20 "http://f:999999` | 1 | 0 | 0 | 0 | 100.0 % |
| `#21 "non-special://f:999999` | 1 | 0 | 0 | 0 | 100.0 % |
| `#22 "http://f: 21 ` | 1 | 0 | 0 | 0 | 100.0 % |
| `#23 "" base="http://example.org` | 1 | 0 | 0 | 0 | 100.0 % |
| `#24 "  \t" base="http://example.org` | 1 | 0 | 0 | 0 | 100.0 % |
| `#25 ":foo.com/" base="http:/` | 1 | 0 | 0 | 0 | 100.0 % |
| `#26 ":foo.com\\" base="http://example.org` | 1 | 0 | 0 | 0 | 100.0 % |
| `#27 ":" base="http://example.org` | 1 | 0 | 0 | 0 | 100.0 % |
| `#28 ":a" base="http://example.org` | 1 | 0 | 0 | 0 | 100.0 % |
| `#29 ":/" base="http:/` | 1 | 0 | 0 | 0 | 100.0 % |
| `#30 ":\\" base="http://example.org` | 1 | 0 | 0 | 0 | 100.0 % |
| `#31 ":#" base="http://example.org` | 1 | 0 | 0 | 0 | 100.0 % |
| `#32 "#" base="http://example.org` | 1 | 0 | 0 | 0 | 100.0 % |
| `#33 "#/" base="http:/` | 1 | 0 | 0 | 0 | 100.0 % |
| `#34 "#\\" base="http://example.org` | 0 | 1 | 0 | 0 | 0.0 % |
| `#35 "#;?" base="http://example.org` | 1 | 0 | 0 | 0 | 100.0 % |
| `#36 "?" base="http://example.org` | 1 | 0 | 0 | 0 | 100.0 % |
| `#37 "/" base="http:/` | 1 | 0 | 0 | 0 | 100.0 % |
| `#38 ":23" base="http://example.org` | 1 | 0 | 0 | 0 | 100.0 % |
| `#39 "/:23" base="http:/` | 1 | 0 | 0 | 0 | 100.0 % |
| `#40 "\\x" base="http://example.org` | 1 | 0 | 0 | 0 | 100.0 % |
| `#41 "\\\\x\\hello" base="http://example.org` | 1 | 0 | 0 | 0 | 100.0 % |
| `#42 "::" base="http://example.org` | 1 | 0 | 0 | 0 | 100.0 % |
| `#43 "::23" base="http://example.org` | 1 | 0 | 0 | 0 | 100.0 % |
| `#44 "foo://" base="http:` | 1 | 0 | 0 | 0 | 100.0 % |
| `#45 "http://a:b@c:29` | 1 | 0 | 0 | 0 | 100.0 % |
| `#46 "http://é@é"` | 0 | 1 | 0 | 0 | 0.0 % |
| `#47 "http://é@example.com"` | 1 | 0 | 0 | 0 | 100.0 % |
| `#48 "http::@c:29" base="http://example.org` | 1 | 0 | 0 | 0 | 100.0 % |
| `#49 "http://&a:foo(b]c@d:2` | 0 | 1 | 0 | 0 | 0.0 % |
| `#50 "http://::@c@d:2" base="http:` | 0 | 1 | 0 | 0 | 0.0 % |
| `#51 "http://foo.com:b@d` | 1 | 0 | 0 | 0 | 100.0 % |
| `#52 "http://foo.com` | 1 | 0 | 0 | 0 | 100.0 % |
| `#53 "http:\\\\foo.com\\" base="http://example.org` | 1 | 0 | 0 | 0 | 100.0 % |
| `#54 "http:\\\\a\\b:c\\d@foo.com\\" base="http://example.org` | 1 | 0 | 0 | 0 | 100.0 % |
| `#55 "http://a:b@c\\"` | 1 | 0 | 0 | 0 | 100.0 % |
| `#56 "ws://a@b\\c"` | 1 | 0 | 0 | 0 | 100.0 % |
| `#57 "foo:/" base="http:/` | 1 | 0 | 0 | 0 | 100.0 % |
| `#58 "foo:/bar.com/" base="http:` | 1 | 0 | 0 | 0 | 100.0 % |
| `#59 "foo://` | 1 | 0 | 0 | 0 | 100.0 % |
| `#60 "foo://` | 1 | 0 | 0 | 0 | 100.0 % |
| `#61 "foo://` | 1 | 0 | 0 | 0 | 100.0 % |
| `#62 "c:/foo" base="http:/` | 1 | 0 | 0 | 0 | 100.0 % |
| `#63 "//foo` | 1 | 0 | 0 | 0 | 100.0 % |
| `#64 "http://foo` | 0 | 1 | 0 | 0 | 0.0 % |
| `#65 "http://foo` | 1 | 0 | 0 | 0 | 100.0 % |
| `#66 "http://foo` | 1 | 0 | 0 | 0 | 100.0 % |
| `#67 "[61:24:74]:98" base="http://example.org` | 0 | 1 | 0 | 0 | 0.0 % |
| `#68 "http:[61:27]/:foo" base="http:/` | 0 | 1 | 0 | 0 | 0.0 % |
| `#69 "http://[1::2]:3:4" base="http:` | 1 | 0 | 0 | 0 | 100.0 % |
| `#70 "http://2001::1" base="http:` | 1 | 0 | 0 | 0 | 100.0 % |
| `#71 "http://2001::1]" base="http:` | 1 | 0 | 0 | 0 | 100.0 % |
| `#72 "http://2001::1]:80" base="http:` | 1 | 0 | 0 | 0 | 100.0 % |
| `#73 "http://[2001::1]" base="http:` | 1 | 0 | 0 | 0 | 100.0 % |
| `#74 "http://[::127.0.0.1]" base="http:` | 0 | 1 | 0 | 0 | 0.0 % |
| `#75 "http://[::127.0.0.1.]" base="http:` | 1 | 0 | 0 | 0 | 100.0 % |
| `#76 "http://[0:0:0:0:0:0:13.1.68.3]" base="http:` | 0 | 1 | 0 | 0 | 0.0 % |
| `#77 "http://[2001::1]:80" base="http:` | 1 | 0 | 0 | 0 | 100.0 % |
| `#78 "http:/example.com/" base="http:` | 0 | 1 | 0 | 0 | 0.0 % |
| `#79 "http:/" base="http:/` | 1 | 0 | 0 | 0 | 100.0 % |
| _(+816 grupos)_ | | | | | |

## Fallos (231)

### `#9 "a:\t foo.com" base="http://example.org/foo/bar"`

- Características: url
- Motivo: pathname: expected  foo.com, got %20foo.com

### `#11 "lolscheme:x x#x x"`

- Características: url
- Motivo: pathname: expected x x, got x%20x

### `#34 "#\\" base="http://example.org/foo/bar"`

- Características: url
- Motivo: hash: expected #\, got #%5C

### `#46 "http://é@é"`

- Características: url
- Motivo: URL parsing failed

### `#49 "http://&a:foo(b]c@d:2/" base="http://example.org/foo/bar"`

- Características: url
- Motivo: URL parsing failed

### `#50 "http://::@c@d:2" base="http://example.org/foo/bar"`

- Características: url
- Motivo: URL parsing failed

### `#64 "http://foo/path;a??e#f#g" base="http://example.org/foo/bar"`

- Características: url
- Motivo: hash: expected #f#g, got #f%23g

### `#67 "[61:24:74]:98" base="http://example.org/foo/bar"`

- Características: url
- Motivo: URL parsing failed

### `#68 "http:[61:27]/:foo" base="http://example.org/foo/bar"`

- Características: url
- Motivo: href: expected http://example.org/foo/[61:27]/:foo, got http://example.org/foo/%5B61:27%5D/:foo

```text
href: expected http://example.org/foo/[61:27]/:foo, got http://example.org/foo/%5B61:27%5D/:foo
pathname: expected /foo/[61:27]/:foo, got /foo/%5B61:27%5D/:foo
```

### `#74 "http://[::127.0.0.1]" base="http://example.org/foo/bar"`

- Características: url
- Motivo: URL parsing failed

### `#76 "http://[0:0:0:0:0:0:13.1.68.3]" base="http://example.org/foo/bar"`

- Características: url
- Motivo: URL parsing failed

### `#78 "http:/example.com/" base="http://example.org/foo/bar"`

- Características: url
- Motivo: href: expected http://example.org/example.com/, got http://example.com/

```text
href: expected http://example.org/example.com/, got http://example.com/
origin: expected http://example.org, got http://example.com
host: expected example.org, got example.com
hostname: expected example.org, got example.com
pathname: expected /example.com/, got /
```

### `#108 "/a%2fc" base="http://example.org/foo/bar"`

- Características: url
- Motivo: href: expected http://example.org/a%2fc, got http://example.org/a%2Fc

```text
href: expected http://example.org/a%2fc, got http://example.org/a%2Fc
pathname: expected /a%2fc, got /a%2Fc
```

### `#109 "/a/%2f/c" base="http://example.org/foo/bar"`

- Características: url
- Motivo: href: expected http://example.org/a/%2f/c, got http://example.org/a/%2F/c

```text
href: expected http://example.org/a/%2f/c, got http://example.org/a/%2F/c
pathname: expected /a/%2f/c, got /a/%2F/c
```

### `#114 "file:c:\\foo\\bar.html" base="file:///tmp/mock/path"`

- Características: url
- Motivo: href: expected file:///c:/foo/bar.html, got file:c:\foo\bar.html

### `#115 "  File:c|////foo\\bar.html" base="file:///tmp/mock/path"`

- Características: url
- Motivo: href: expected file:///c:////foo/bar.html, got File:c\|////foo\bar.html

```text
href: expected file:///c:////foo/bar.html, got File:c|////foo\bar.html
pathname: expected /c:////foo/bar.html, got /c%7C////foo/bar.html
```

### `#116 "C|/foo/bar" base="file:///tmp/mock/path"`

- Características: url
- Motivo: href: expected file:///C:/foo/bar, got file:///tmp/mock/C%7C/foo/bar

```text
href: expected file:///C:/foo/bar, got file:///tmp/mock/C%7C/foo/bar
pathname: expected /C:/foo/bar, got /tmp/mock/C%7C/foo/bar
```

### `#117 "/C|\\foo\\bar" base="file:///tmp/mock/path"`

- Características: url
- Motivo: href: expected file:///C:/foo/bar, got file:///C%7C/foo/bar

```text
href: expected file:///C:/foo/bar, got file:///C%7C/foo/bar
pathname: expected /C:/foo/bar, got /C%7C/foo/bar
```

### `#118 "//C|/foo/bar" base="file:///tmp/mock/path"`

- Características: url
- Motivo: URL parsing failed

### `#132 "file:test" base="file:///tmp/mock/path"`

- Características: url
- Motivo: href: expected file:///tmp/mock/test, got file:///test

```text
href: expected file:///tmp/mock/test, got file:///test
pathname: expected /tmp/mock/test, got /test
```

### `#133 "file:///w|m"`

- Características: url
- Motivo: href: expected file:///w\|m, got file:///w%7Cm

```text
href: expected file:///w|m, got file:///w%7Cm
pathname: expected /w|m, got /w%7Cm
```

### `#134 "file:///w||m"`

- Características: url
- Motivo: href: expected file:///w\|\|m, got file:///w%7C%7Cm

```text
href: expected file:///w||m, got file:///w%7C%7Cm
pathname: expected /w||m, got /w%7C%7Cm
```

### `#135 "file:///w|/m"`

- Características: url
- Motivo: href: expected file:///w:/m, got file:///w%7C/m

```text
href: expected file:///w:/m, got file:///w%7C/m
pathname: expected /w:/m, got /w%7C/m
```

### `#136 "file:C|/m/"`

- Características: url
- Motivo: href: expected file:///C:/m/, got file:C\|/m/

```text
href: expected file:///C:/m/, got file:C|/m/
pathname: expected /C:/m/, got /C%7C/m/
```

### `#137 "file:C||/m/"`

- Características: url
- Motivo: href: expected file:///C\|\|/m/, got file:C\|\|/m/

```text
href: expected file:///C||/m/, got file:C||/m/
pathname: expected /C||/m/, got /C%7C%7C/m/
```

### `#150 "http://example.com/foo/%2e%2"`

- Características: url
- Motivo: href: expected http://example.com/foo/%2e%2, got http://example.com/foo/.%252

```text
href: expected http://example.com/foo/%2e%2, got http://example.com/foo/.%252
pathname: expected /foo/%2e%2, got /foo/.%252
```

### `#151 "http://example.com/foo/%2e./%2e%2e/.%2e/%2e.bar"`

- Características: url
- Motivo: href: expected http://example.com/%2e.bar, got http://example.com/..bar

```text
href: expected http://example.com/%2e.bar, got http://example.com/..bar
pathname: expected /%2e.bar, got /..bar
```

### `#157 "http://example.com/foo%"`

- Características: url
- Motivo: href: expected http://example.com/foo%, got http://example.com/foo%25

```text
href: expected http://example.com/foo%, got http://example.com/foo%25
pathname: expected /foo%, got /foo%25
```

### `#158 "http://example.com/foo%2"`

- Características: url
- Motivo: href: expected http://example.com/foo%2, got http://example.com/foo%252

```text
href: expected http://example.com/foo%2, got http://example.com/foo%252
pathname: expected /foo%2, got /foo%252
```

### `#159 "http://example.com/foo%2zbar"`

- Características: url
- Motivo: href: expected http://example.com/foo%2zbar, got http://example.com/foo%252zbar

```text
href: expected http://example.com/foo%2zbar, got http://example.com/foo%252zbar
pathname: expected /foo%2zbar, got /foo%252zbar
```

### `#160 "http://example.com/foo%2Â©zbar"`

- Características: url
- Motivo: href: expected http://example.com/foo%2%C3%82%C2%A9zbar, got http://example.com/foo%252%C3%82%C2%A9zbar

```text
href: expected http://example.com/foo%2%C3%82%C2%A9zbar, got http://example.com/foo%252%C3%82%C2%A9zbar
pathname: expected /foo%2%C3%82%C2%A9zbar, got /foo%252%C3%82%C2%A9zbar
```

### `#161 "http://example.com/foo%41%7a"`

- Características: url
- Motivo: href: expected http://example.com/foo%41%7a, got http://example.com/fooAz

```text
href: expected http://example.com/foo%41%7a, got http://example.com/fooAz
pathname: expected /foo%41%7a, got /fooAz
```

### `#163 "http://example.com/foo%00%51"`

- Características: url
- Motivo: href: expected http://example.com/foo%00%51, got http://example.com/foo%00Q

```text
href: expected http://example.com/foo%00%51, got http://example.com/foo%00Q
pathname: expected /foo%00%51, got /foo%00Q
```

### `#165 "http://example.com/%3A%3a%3C%3c"`

- Características: url
- Motivo: href: expected http://example.com/%3A%3a%3C%3c, got http://example.com/%3A%3A%3C%3C

```text
href: expected http://example.com/%3A%3a%3C%3c, got http://example.com/%3A%3A%3C%3C
pathname: expected /%3A%3a%3C%3c, got /%3A%3A%3C%3C
```

### `#178 "http://192.0x00A80001"`

- Características: url
- Motivo: href: expected http://192.168.0.1/, got http://192.0x00a80001/

```text
href: expected http://192.168.0.1/, got http://192.0x00a80001/
origin: expected http://192.168.0.1, got http://192.0x00a80001
host: expected 192.168.0.1, got 192.0x00a80001
hostname: expected 192.168.0.1, got 192.0x00a80001
```

### `#179 "http://www/foo%2Ehtml"`

- Características: url
- Motivo: href: expected http://www/foo%2Ehtml, got http://www/foo.html

```text
href: expected http://www/foo%2Ehtml, got http://www/foo.html
pathname: expected /foo%2Ehtml, got /foo.html
```

### `#190 "ftp://foo:21/"`

- Características: url
- Motivo: href: expected ftp://foo/, got ftp://foo:21/

### `#194 "ws://foo:80/"`

- Características: url
- Motivo: href: expected ws://foo/, got ws://foo:80/

### `#200 "wss://foo:443/"`

- Características: url
- Motivo: href: expected wss://foo/, got wss://foo:443/

### `#267 "file:.." base="http://www.example.com/test"`

- Características: url
- Motivo: href: expected file:///, got file:..

### `#269 "file:."`

- Características: url
- Motivo: href: expected file:///, got file:.

### `#270 "file:." base="http://www.example.com/test"`

- Características: url
- Motivo: href: expected file:///, got file:.

### `#277 "http://GOO​⁠﻿goo.com" base="http://other.com/"`

- Características: url
- Motivo: URL parsing failed

### `#280 "non-special:opaque  ?hi"`

- Características: url
- Motivo: href: expected non-special:opaque %20?hi, got non-special:opaque  ?hi

```text
href: expected non-special:opaque %20?hi, got non-special:opaque  ?hi
pathname: expected opaque %20, got opaque%20%20
```

### `#281 "non-special:opaque  #hi"`

- Características: url
- Motivo: href: expected non-special:opaque %20#hi, got non-special:opaque  #hi

```text
href: expected non-special:opaque %20#hi, got non-special:opaque  #hi
pathname: expected opaque %20, got opaque%20%20
```

### `#282 "non-special:opaque  x?hi"`

- Características: url
- Motivo: pathname: expected opaque  x, got opaque%20%20x

### `#283 "non-special:opaque  x#hi"`

- Características: url
- Motivo: pathname: expected opaque  x, got opaque%20%20x

### `#284 "non-special:opaque \t\t  \t#hi"`

- Características: url
- Motivo: href: expected non-special:opaque  %20#hi, got non-special:opaque   #hi

```text
href: expected non-special:opaque  %20#hi, got non-special:opaque   #hi
pathname: expected opaque  %20, got opaque%20%20%20
```

### `#285 "non-special:opaque \t\t  #hi"`

- Características: url
- Motivo: href: expected non-special:opaque  %20#hi, got non-special:opaque   #hi

```text
href: expected non-special:opaque  %20#hi, got non-special:opaque   #hi
pathname: expected opaque  %20, got opaque%20%20%20
```

### `#286 "non-special:opaque\t\t  \r #hi"`

- Características: url
- Motivo: href: expected non-special:opaque  %20#hi, got non-special:opaque   #hi

```text
href: expected non-special:opaque  %20#hi, got non-special:opaque   #hi
pathname: expected opaque  %20, got opaque%20%20%20
```

### `#287 "http://www.foo。bar.com" base="http://other.com/"`

- Características: url
- Motivo: URL parsing failed

### `#299 "http://Ｇｏ.com" base="http://other.com/"`

- Características: url
- Motivo: URL parsing failed

### `#304 "http://你好你好" base="http://other.com/"`

- Características: url
- Motivo: URL parsing failed

### `#305 "https://faß.ExAmPlE/"`

- Características: url
- Motivo: URL parsing failed

### `#306 "sc://faß.ExAmPlE/"`

- Características: url
- Motivo: URL parsing failed

### `#310 "http://%30%78%63%30%2e%30%32%35%30.01" base="http://other.com/"`

- Características: url
- Motivo: href: expected http://192.168.0.1/, got http://0xc0.0250.01/

```text
href: expected http://192.168.0.1/, got http://0xc0.0250.01/
origin: expected http://192.168.0.1, got http://0xc0.0250.01
host: expected 192.168.0.1, got 0xc0.0250.01
hostname: expected 192.168.0.1, got 0xc0.0250.01
```

### `#311 "http://%30%78%63%30%2e%30%32%35%30.01%2e" base="http://other.com/"`

- Características: url
- Motivo: href: expected http://192.168.0.1/, got http://0xc0.0250.01./

```text
href: expected http://192.168.0.1/, got http://0xc0.0250.01./
origin: expected http://192.168.0.1, got http://0xc0.0250.01.
host: expected 192.168.0.1, got 0xc0.0250.01.
hostname: expected 192.168.0.1, got 0xc0.0250.01.
```

### `#316 "http://０Ｘｃ０．０２５０．０１" base="http://other.com/"`

- Características: url
- Motivo: URL parsing failed

### `#334 "https://localhost?q=🔥"`

- Características: url
- Motivo: href: expected https://localhost/?q=%F0%9F%94%A5, got https://localhost?q=%F0%9F%94%A5/

### `#335 "https://localhost#🔥"`

- Características: url
- Motivo: href: expected https://localhost/#%F0%9F%94%A5, got https://localhost#%F0%9F%94%A5/

### `#336 "#" base="test:test"`

- Características: url
- Motivo: URL parsing failed

### `#337 "#x" base="mailto:x@x.com"`

- Características: url
- Motivo: URL parsing failed

### `#338 "#x" base="data:,"`

- Características: url
- Motivo: URL parsing failed

### `#339 "#x" base="about:blank"`

- Características: url
- Motivo: URL parsing failed

### `#340 "#x:y" base="about:blank"`

- Características: url
- Motivo: URL parsing failed

### `#341 "#" base="test:test?test"`

- Características: url
- Motivo: URL parsing failed

### `#342 "https://@test@test@example:800/" base="http://doesnotmatter/"`

- Características: url
- Motivo: URL parsing failed

### `#343 "https://@@@example" base="http://doesnotmatter/"`

- Características: url
- Motivo: URL parsing failed

### `#344 "http://`{}:`{}@h/`{}?`{}" base="http://doesnotmatter/"`

- Características: url
- Motivo: href: expected http://%60%7B%7D:%60%7B%7D@h/%60%7B%7D?`{}, got http://%60%7B%7D:%60%7B%7D@h/%60%7B%7D?%60%7B%7D

```text
href: expected http://%60%7B%7D:%60%7B%7D@h/%60%7B%7D?`{}, got http://%60%7B%7D:%60%7B%7D@h/%60%7B%7D?%60%7B%7D
search: expected ?`{}, got ?%60%7B%7D
```

### `#345 "http://host/?'"`

- Características: url
- Motivo: href: expected http://host/?%27, got http://host/?'

```text
href: expected http://host/?%27, got http://host/?'
search: expected ?%27, got ?'
```

### `#352 "i" base="sc:/pa/pa"`

- Características: url
- Motivo: URL parsing failed

### `#357 "../i" base="sc:/pa/pa"`

- Características: url
- Motivo: URL parsing failed

### `#362 "/i" base="sc:/pa/pa"`

- Características: url
- Motivo: URL parsing failed

### `#367 "?i" base="sc:/pa/pa"`

- Características: url
- Motivo: URL parsing failed

### `#370 "#i" base="sc:sd"`

- Características: url
- Motivo: URL parsing failed

### `#371 "#i" base="sc:sd/sd"`

- Características: url
- Motivo: URL parsing failed

### `#372 "#i" base="sc:/pa/pa"`

- Características: url
- Motivo: URL parsing failed

### `#375 "about:/../"`

- Características: url
- Motivo: href: expected about:/, got about:/../

### `#377 "javascript:/../"`

- Características: url
- Motivo: href: expected javascript:/, got javascript:/../

### `#378 "mailto:/../"`

- Características: url
- Motivo: href: expected mailto:/, got mailto:/../

### `#379 "sc://ñ.test/"`

- Características: url
- Motivo: URL parsing failed

### `#380 "sc://%/"`

- Características: url
- Motivo: URL parsing failed

### `#385 "x" base="sc://ñ"`

- Características: url
- Motivo: URL parsing failed

### `#386 "sc:\\../"`

- Características: url
- Motivo: pathname: expected \../, got /

### `#388 "wow:%NBD"`

- Características: url
- Motivo: pathname: expected %NBD, got %25NBD

### `#389 "wow:%1G"`

- Características: url
- Motivo: pathname: expected %1G, got %251G

### `#390 "wow:￿"`

- Características: url
- Motivo: href: expected wow:%EF%BF%BF, got wow:￿

### `#396 "sc://a\\b/"`

- Características: url
- Motivo: expected URL parsing to fail, got {href: sc://a/b/, origin: null, protocol: sc:, username: , password: , host: a, hostname: a, port: , pathname: /b/, search: , hash: }

### `#490 "http://!\"$&'()*+,-.;=_`{}~/"`

- Características: url
- Motivo: URL parsing failed

### `#491 "sc://\u0001\u0002\u0003\u0004\u0005\u0006\u0007\b\u000b\f\u000e\u000f\u0010\u0011\u0012\u0013\u0014\u0015\u0016\u0017\u0018\u0019\u001a\u001b\u001c\u001d\u001e\u001f!\"$%&'()*+,-.;=_`{}~/"`

- Características: url
- Motivo: URL parsing failed

### `#496 "ftp://%e2%98%83"`

- Características: url
- Motivo: URL parsing failed

### `#497 "https://%e2%98%83"`

- Características: url
- Motivo: URL parsing failed

### `#505 "http:" base="https://example.org/foo/bar"`

- Características: url
- Motivo: expected URL parsing to fail, got {href: http://example.org/foo/bar, origin: http://example.org, protocol: http:, username: , password: , host: example.org, hostname: example.org, port: , pathname: /foo/bar, search: , hash: }

### `#513 "http://1.2.3.4./" base="http://other.com/"`

- Características: url
- Motivo: href: expected http://1.2.3.4/, got http://1.2.3.4./

```text
href: expected http://1.2.3.4/, got http://1.2.3.4./
origin: expected http://1.2.3.4, got http://1.2.3.4.
host: expected 1.2.3.4, got 1.2.3.4.
hostname: expected 1.2.3.4, got 1.2.3.4.
```

### `#514 "http://192.168.257" base="http://other.com/"`

- Características: url
- Motivo: href: expected http://192.168.1.1/, got http://192.168.257/

```text
href: expected http://192.168.1.1/, got http://192.168.257/
origin: expected http://192.168.1.1, got http://192.168.257
host: expected 192.168.1.1, got 192.168.257
hostname: expected 192.168.1.1, got 192.168.257
```

### `#515 "http://192.168.257." base="http://other.com/"`

- Características: url
- Motivo: href: expected http://192.168.1.1/, got http://192.168.257./

```text
href: expected http://192.168.1.1/, got http://192.168.257./
origin: expected http://192.168.1.1, got http://192.168.257.
host: expected 192.168.1.1, got 192.168.257.
hostname: expected 192.168.1.1, got 192.168.257.
```

### `#517 "http://256" base="http://other.com/"`

- Características: url
- Motivo: href: expected http://0.0.1.0/, got http://256/

```text
href: expected http://0.0.1.0/, got http://256/
origin: expected http://0.0.1.0, got http://256
host: expected 0.0.1.0, got 256
hostname: expected 0.0.1.0, got 256
```

### `#519 "http://999999999" base="http://other.com/"`

- Características: url
- Motivo: href: expected http://59.154.201.255/, got http://999999999/

```text
href: expected http://59.154.201.255/, got http://999999999/
origin: expected http://59.154.201.255, got http://999999999
host: expected 59.154.201.255, got 999999999
hostname: expected 59.154.201.255, got 999999999
```

### `#520 "http://999999999." base="http://other.com/"`

- Características: url
- Motivo: href: expected http://59.154.201.255/, got http://999999999./

```text
href: expected http://59.154.201.255/, got http://999999999./
origin: expected http://59.154.201.255, got http://999999999.
host: expected 59.154.201.255, got 999999999.
hostname: expected 59.154.201.255, got 999999999.
```

### `#524 "http://4294967295" base="http://other.com/"`

- Características: url
- Motivo: href: expected http://255.255.255.255/, got http://4294967295/

```text
href: expected http://255.255.255.255/, got http://4294967295/
origin: expected http://255.255.255.255, got http://4294967295
host: expected 255.255.255.255, got 4294967295
hostname: expected 255.255.255.255, got 4294967295
```

### `#528 "http://0xffffffff" base="http://other.com/"`

- Características: url
- Motivo: href: expected http://255.255.255.255/, got http://0xffffffff/

```text
href: expected http://255.255.255.255/, got http://0xffffffff/
origin: expected http://255.255.255.255, got http://0xffffffff
host: expected 255.255.255.255, got 0xffffffff
hostname: expected 255.255.255.255, got 0xffffffff
```

### `#531 "https://0x.0x.0"`

- Características: url
- Motivo: URL parsing failed

### `#532 "https://0x.0x.0x.0x"`

- Características: url
- Motivo: URL parsing failed

### `#533 "https://00.00.00.00"`

- Características: url
- Motivo: href: expected https://0.0.0.0/, got https://00.00.00.00/

```text
href: expected https://0.0.0.0/, got https://00.00.00.00/
origin: expected https://0.0.0.0, got https://00.00.00.00
host: expected 0.0.0.0, got 00.00.00.00
hostname: expected 0.0.0.0, got 00.00.00.00
```

### `#534 "https://0000000000000000000000000000000000000000177.0.0.1"`

- Características: url
- Motivo: href: expected https://127.0.0.1/, got https://0000000000000000000000000000000000000000177.0.0.1/

```text
href: expected https://127.0.0.1/, got https://0000000000000000000000000000000000000000177.0.0.1/
origin: expected https://127.0.0.1, got https://0000000000000000000000000000000000000000177.0.0.1
host: expected 127.0.0.1, got 0000000000000000000000000000000000000000177.0.0.1
hostname: expected 127.0.0.1, got 0000000000000000000000000000000000000000177.0.0.1
```

### `#546 "asdf://%43%7C/"`

- Características: url
- Motivo: URL parsing failed

### `#548 ".." base="file:///C:/"`

- Características: url
- Motivo: href: expected file:///C:/, got file:///

```text
href: expected file:///C:/, got file:///
pathname: expected /C:/, got /
```

### `#550 "/" base="file:///C:/a/b"`

- Características: url
- Motivo: href: expected file:///C:/, got file:///

```text
href: expected file:///C:/, got file:///
pathname: expected /C:/, got /
```

### `#551 "/" base="file://h/C:/a/b"`

- Características: url
- Motivo: href: expected file://h/C:/, got file://h/

```text
href: expected file://h/C:/, got file://h/
pathname: expected /C:/, got /
```

### `#553 "//d:" base="file:///C:/a/b"`

- Características: url
- Motivo: href: expected file:///d:, got file://d/

```text
href: expected file:///d:, got file://d/
host: expected , got d
hostname: expected , got d
pathname: expected /d:, got /
```

### `#554 "//d:/.." base="file:///C:/a/b"`

- Características: url
- Motivo: href: expected file:///d:/, got file://d/

```text
href: expected file:///d:/, got file://d/
host: expected , got d
hostname: expected , got d
pathname: expected /d:/, got /
```

### `#558 "file:" base="file:///test?test#test"`

- Características: url
- Motivo: href: expected file:///test?test, got file:///

```text
href: expected file:///test?test, got file:///
pathname: expected /test, got /
search: expected ?test, got
```

### `#560 "file:?x" base="file:///test?test#test"`

- Características: url
- Motivo: href: expected file:///test?x, got file:///?x

```text
href: expected file:///test?x, got file:///?x
pathname: expected /test, got /
```

### `#562 "file:#x" base="file:///test?test#test"`

- Características: url
- Motivo: href: expected file:///test?test#x, got file:///#x

```text
href: expected file:///test?test#x, got file:///#x
pathname: expected /test, got /
search: expected ?test, got
```

### `#580 "C|" base="file://host/dir/file"`

- Características: url
- Motivo: href: expected file://host/C:, got file://host/dir/C%7C

```text
href: expected file://host/C:, got file://host/dir/C%7C
pathname: expected /C:, got /dir/C%7C
```

### `#581 "C|" base="file://host/D:/dir1/dir2/file"`

- Características: url
- Motivo: href: expected file://host/C:, got file://host/D:/dir1/dir2/C%7C

```text
href: expected file://host/C:, got file://host/D:/dir1/dir2/C%7C
pathname: expected /C:, got /D:/dir1/dir2/C%7C
```

### `#582 "C|#" base="file://host/dir/file"`

- Características: url
- Motivo: href: expected file://host/C:#, got file://host/dir/C%7C#

```text
href: expected file://host/C:#, got file://host/dir/C%7C#
pathname: expected /C:, got /dir/C%7C
```

### `#583 "C|?" base="file://host/dir/file"`

- Características: url
- Motivo: href: expected file://host/C:?, got file://host/dir/C%7C?

```text
href: expected file://host/C:?, got file://host/dir/C%7C?
pathname: expected /C:, got /dir/C%7C
```

### `#584 "C|/" base="file://host/dir/file"`

- Características: url
- Motivo: href: expected file://host/C:/, got file://host/dir/C%7C/

```text
href: expected file://host/C:/, got file://host/dir/C%7C/
pathname: expected /C:/, got /dir/C%7C/
```

### `#585 "C|\n/" base="file://host/dir/file"`

- Características: url
- Motivo: href: expected file://host/C:/, got file://host/dir/C%7C/

```text
href: expected file://host/C:/, got file://host/dir/C%7C/
pathname: expected /C:/, got /dir/C%7C/
```

_… y 111 fallos más (ver el JSONL)._

---

_Generado por `tools/conformance`. Un SKIP no cuenta como compatibilidad; mide únicamente que el runner no pudo ejecutar el test o que la característica está fuera de alcance._
