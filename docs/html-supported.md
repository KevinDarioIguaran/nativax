# HTML soportado (0.1)

El parser es propio (tokenizer + tree builder), no usa regex sobre el markup y
aplica límites de nodos/profundidad/errores.

## Soportado

- Elementos y atributos, comillas simples/dobles/sin comillas, entidades HTML5
  completas (2.125 nombres + legacy).
- `html`, `head`, `body` implícitos; elementos de head (`title`, `meta`,
  `link`, `style`, `script`, `base`, `noscript`, `template`).
- Void elements, raw text (`script`/`style`), RCDATA (`textarea`/`title`).
- Cierre implícito de `p`, `li`, `dd`, `dt`, `option`, headings.
- Recuperación de etiquetas no cerradas y end tags huérfanos.
- Comentarios, `DOCTYPE` (name/publicId/systemId) y `<?...>` como comentario.
- `<template>` en head y contenido básico dentro del template.
- Inserción implícita de `tbody`/`tr` en tablas.
- Adoption agency simplificada para formato mal anidado (`b`, `i`, `a`, etc.).
- `parseFragment` para `innerHTML` (sin html/head/body implícitos).
- Foreign content (SVG/MathML): `/>` cierra elementos, puntos de
  integración HTML (`foreignObject`, `desc`, `title`) y etiquetas HTML que
  rompen el contenido extranjero.

## Limitaciones conocidas

- Adoption agency no es la implementación completa del estándar.
- Foster parenting de tablas incompleto.
- `<template>` no usa un content fragment separado.
- Sin quirks mode.
- Sin `DocumentType` público/system completo en todos los casos.
- Sin `noscript` con scripting on/off.
- El tokenizer no implementa todos los estados WHATWG (CDATA, script escaped,
  etc.).

## Diagnóstico

`HtmlParseResult.errors` contiene `code`, offset, línea/columna y detalle. Los
límites se configuran con `HtmlParserLimits` y `DocumentLimits`.
