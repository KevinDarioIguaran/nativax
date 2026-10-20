/// Named character references supported by NativaX. A deliberate subset of
/// the 2,231 HTML entities: the ones common in hand-written UI markup.
/// Unknown references are left as literal text (and reported).
const Map<String, String> namedEntities = {
  'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'",
  'nbsp': ' ', 'copy': '©', 'reg': '®', 'trade': '™',
  'hellip': '…', 'mdash': '—', 'ndash': '–', 'laquo': '«', 'raquo': '»',
  'lsquo': '‘', 'rsquo': '’', 'ldquo': '“', 'rdquo': '”', 'bull': '•',
  'middot': '·', 'deg': '°', 'plusmn': '±', 'times': '×', 'divide': '÷',
  'euro': '€', 'pound': '£', 'yen': '¥', 'cent': '¢', 'sect': '§',
  'para': '¶', 'iexcl': '¡', 'iquest': '¿', 'larr': '←', 'rarr': '→',
  'uarr': '↑', 'darr': '↓', 'harr': '↔', 'check': '✓', 'hearts': '♥',
  'star': '☆', 'aacute': 'á', 'eacute': 'é', 'iacute': 'í', 'oacute': 'ó',
  'uacute': 'ú', 'ntilde': 'ñ', 'Aacute': 'Á', 'Eacute': 'É',
  'Iacute': 'Í', 'Oacute': 'Ó', 'Uacute': 'Ú', 'Ntilde': 'Ñ', 'uuml': 'ü',
  'Uuml': 'Ü', 'ccedil': 'ç', 'Ccedil': 'Ç', 'agrave': 'à', 'egrave': 'è',
  'ograve': 'ò', 'acirc': 'â', 'ecirc': 'ê', 'ocirc': 'ô', 'atilde': 'ã',
  'otilde': 'õ', 'shy': '­', 'zwj': '‍', 'zwnj': '‌',
  'ensp': ' ', 'emsp': ' ', 'thinsp': ' ', //
};
