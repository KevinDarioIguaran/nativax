# Template engine

`NativaXTemplateEngine` is a small Jinja2-like string renderer. It is a
convenience for app-generated documents, not a browser template engine and not
a replacement for the HTML parser.

```dart
final engine = NativaXTemplateEngine(
  loader: (name) async => await rootBundle.loadString('templates/$name'),
  globals: {'appName': 'Demo'},
);

final html = await engine.render('page.html', {
  'title': 'Home',
  'items': ['one', 'two'],
});

await engine.renderString('Hello {{ name | upper }}', {'name': 'Ada'});
```

## Supported syntax

| Feature | Supported |
|---|---|
| `{{ expression }}` | Variables, attribute/index access, calls, operators, filters |
| `{% if %}` / `{% elif %}` / `{% else %}` / `{% endif %}` | Yes |
| `{% for x in xs %}` / `{% else %}` / `{% endfor %}` | Yes, with loop index helpers |
| `{% set name = expr %}` | Yes |
| `{% include "file" %}` | Yes, through the loader |
| `{% macro name(args) %}...{% endmacro %}` | Yes, positional/keyword args |
| `{% call macro(...) %}...{% endcall %}` | Yes, `caller()` |
| `{% trans %}...{% endtrans %}` | Basic translation block |
| `{% raw %}...{% endraw %}` | Yes |
| Template inheritance (`extends`, `block`) | No |
| Async/await in template expressions | No |
| Automatic HTML escaping | **No** (explicit `| e`/`| escape` required) |
| Sandboxing | **No**; templates can call provided functions |

Do not render untrusted templates. The engine is a developer tool with access to
the globals and callables you provide.

## Filters

Current filters include:

`default`/`d`, `length`/`count`, `string`, `int`, `float`, `trim`, `lower`,
`upper`, `capitalize`, `title`, `first`, `last`, `join`, `reverse`, `sort`,
`list`, `tojson`, `safe`, `escape`/`e`, `abs`, `round`, `replace`, `truncate`,
`attr`, `items`.

Tests (`is`): `defined`, `undefined`, `none`, `true`, `false`, `string`,
`number`, `integer`/`int`, `float`, `iterable`, `sequence`, `mapping`, `odd`,
`even`, `divisibleby`, `sameas`, `in`, `lower`, `upper`.

Built-ins injected into scope: `range`, `av`, `len`, `_` (default translator).
These are convenience functions; inspect `packages/nativax/lib/src/template_engine.dart`
for exact signatures.

## Escaping

The engine does **not** auto-escape HTML. A template like:

```html
<p>{{ userContent }}</p>
```

inserts the string as-is. Use `{{ userContent | e }}` or escape in the host
before rendering. Mark trusted markup with `| safe` only when you control it.

This is a security boundary for app code, not for page JavaScript.

## Loader

The loader receives a template name as written in `render`/`include` and returns
its source or null. The engine caches parsed templates. Relative includes are
resolved by the loader; there is no implicit filesystem root. For Flutter:

```dart
final engine = NativaXTemplateEngine(
  loader: (name) => rootBundle.loadString('assets/templates/$name'),
);
```

Include every asset subdirectory in `pubspec.yaml`. Do not let a loader accept
`..` or arbitrary absolute paths from untrusted input.

## Rendering into a page

Templates run in Dart, not in the page's JavaScript engine. A typical flow:

```dart
final html = await engine.render('index.html', context);
runApp(NativaXView(source: html));
```

The rendered string is parsed by `nativa_html` like any other document. A
template error is a Dart exception; handle it in the host and show an error. It
is not a page-level syntax error.

## Limitations

- No inheritance/blocks/macros imported across templates.
- No async filtering or arbitrary Dart method calls beyond what the expression
  evaluator supports.
- No autoescaping.
- No sandbox; functions/globals are trusted.
- Whitespace control is not a full Jinja implementation.
- Error messages point at template parsing/evaluation; they are not browser
  console errors.
- Not intended for user-authored templates or arbitrary untrusted content.

## Tests

Search for template tests:

```bash
grep -RIn 'NativaXTemplateEngine\|renderString' packages/nativax/test
```

If a feature is described here but no test exists, treat it as unverified.
