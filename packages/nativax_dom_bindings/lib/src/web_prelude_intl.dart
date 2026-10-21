/// A compact `Intl` for engines built without ICU. Covers the options web
/// apps commonly use for en, es, pt, fr, de and it; other locales fall back
/// to English data with their region's separators where known.
const String webIntl = r'''
// ============================================================================
// Intl (used only when the engine has none)
// ============================================================================
const intlData = {
  en: {
    months: ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'],
    days: ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'],
    group: ',', decimal: '.', order: 'mdy', sep: '/', h12: true, am: 'AM', pm: 'PM', and: 'and', or: 'or',
    rel: { year: ['year', 'years'], quarter: ['quarter', 'quarters'], month: ['month', 'months'], week: ['week', 'weeks'], day: ['day', 'days'], hour: ['hour', 'hours'], minute: ['minute', 'minutes'], second: ['second', 'seconds'] },
    future: 'in {0}', past: '{0} ago', now: 'now', yesterday: 'yesterday', today: 'today', tomorrow: 'tomorrow',
    currencyAfter: false,
  },
  es: {
    months: ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'],
    days: ['domingo', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado'],
    group: '.', decimal: ',', order: 'dmy', sep: '/', h12: false, am: 'a. m.', pm: 'p. m.', and: 'y', or: 'o',
    rel: { year: ['año', 'años'], quarter: ['trimestre', 'trimestres'], month: ['mes', 'meses'], week: ['semana', 'semanas'], day: ['día', 'días'], hour: ['hora', 'horas'], minute: ['minuto', 'minutos'], second: ['segundo', 'segundos'] },
    future: 'dentro de {0}', past: 'hace {0}', now: 'ahora', yesterday: 'ayer', today: 'hoy', tomorrow: 'mañana',
    currencyAfter: true, minGroup: 5, of: 'de',
  },
  pt: {
    months: ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'],
    days: ['domingo', 'segunda-feira', 'terça-feira', 'quarta-feira', 'quinta-feira', 'sexta-feira', 'sábado'],
    group: '.', decimal: ',', order: 'dmy', sep: '/', h12: false, am: 'AM', pm: 'PM', and: 'e', or: 'ou',
    rel: { year: ['ano', 'anos'], quarter: ['trimestre', 'trimestres'], month: ['mês', 'meses'], week: ['semana', 'semanas'], day: ['dia', 'dias'], hour: ['hora', 'horas'], minute: ['minuto', 'minutos'], second: ['segundo', 'segundos'] },
    future: 'em {0}', past: 'há {0}', now: 'agora', yesterday: 'ontem', today: 'hoje', tomorrow: 'amanhã',
    currencyPrefixSpace: true, of: 'de',
  },
  fr: {
    months: ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'],
    days: ['dimanche', 'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi'],
    group: ' ', decimal: ',', order: 'dmy', sep: '/', h12: false, am: 'AM', pm: 'PM', and: 'et', or: 'ou',
    rel: { year: ['an', 'ans'], quarter: ['trimestre', 'trimestres'], month: ['mois', 'mois'], week: ['semaine', 'semaines'], day: ['jour', 'jours'], hour: ['heure', 'heures'], minute: ['minute', 'minutes'], second: ['seconde', 'secondes'] },
    future: 'dans {0}', past: 'il y a {0}', now: 'maintenant', yesterday: 'hier', today: "aujourd’hui", tomorrow: 'demain',
    currencyAfter: true,
  },
  de: {
    months: ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'],
    days: ['Sonntag', 'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag'],
    group: '.', decimal: ',', order: 'dmy', sep: '.', h12: false, am: 'AM', pm: 'PM', and: 'und', or: 'oder',
    rel: { year: ['Jahr', 'Jahren'], quarter: ['Quartal', 'Quartalen'], month: ['Monat', 'Monaten'], week: ['Woche', 'Wochen'], day: ['Tag', 'Tagen'], hour: ['Stunde', 'Stunden'], minute: ['Minute', 'Minuten'], second: ['Sekunde', 'Sekunden'] },
    future: 'in {0}', past: 'vor {0}', now: 'jetzt', yesterday: 'gestern', today: 'heute', tomorrow: 'morgen',
    currencyAfter: true,
  },
  it: {
    months: ['gennaio', 'febbraio', 'marzo', 'aprile', 'maggio', 'giugno', 'luglio', 'agosto', 'settembre', 'ottobre', 'novembre', 'dicembre'],
    days: ['domenica', 'lunedì', 'martedì', 'mercoledì', 'giovedì', 'venerdì', 'sabato'],
    group: '.', decimal: ',', order: 'dmy', sep: '/', h12: false, am: 'AM', pm: 'PM', and: 'e', or: 'o',
    rel: { year: ['anno', 'anni'], quarter: ['trimestre', 'trimestri'], month: ['mese', 'mesi'], week: ['settimana', 'settimane'], day: ['giorno', 'giorni'], hour: ['ora', 'ore'], minute: ['minuto', 'minuti'], second: ['secondo', 'secondi'] },
    future: 'tra {0}', past: '{0} fa', now: 'ora', yesterday: 'ieri', today: 'oggi', tomorrow: 'domani',
    currencyAfter: true,
  },
};
const currencySymbols = { USD: '$', EUR: '€', GBP: '£', JPY: '¥', CNY: 'CN¥', MXN: 'MX$', BRL: 'R$', COP: 'COP', ARS: 'ARS', CLP: 'CLP', PEN: 'PEN', INR: '₹', KRW: '₩', CAD: 'CA$', AUD: 'A$', CHF: 'CHF' };
const resolveLocale = (locales) => {
  const list = locales === undefined ? [navigator.language] : (Array.isArray(locales) ? locales : [locales]);
  for (const l of list) {
    const tag = String(l);
    const lang = tag.split(/[-_]/)[0].toLowerCase();
    if (intlData[lang]) return { tag, lang };
  }
  return { tag: list[0] ? String(list[0]) : 'en-US', lang: 'en' };
};
const pad2 = (n) => String(n).padStart(2, '0');
const groupDigits = (int, sep, minGroup = 4) => {
  if (int.length < minGroup) return int;
  return int.replace(/\B(?=(\d{3})+(?!\d))/g, sep);
};
class IntlNumberFormat {
  constructor(locales, options = {}) {
    const { tag, lang } = resolveLocale(locales);
    const style = options.style || 'decimal';
    if (style === 'currency' && !options.currency) throw new TypeError('Currency code is required with currency style.');
    const minF = options.minimumFractionDigits ?? (style === 'currency' ? (options.currency === 'JPY' || options.currency === 'CLP' ? 0 : 2) : 0);
    const maxF = options.maximumFractionDigits ?? Math.max(minF, style === 'currency' ? minF : (style === 'percent' ? 0 : 3));
    if (minF > maxF) throw new RangeError('maximumFractionDigits value is out of range.');
    hidden(this, '_o', {
      locale: tag, lang, style, currency: options.currency ? String(options.currency).toUpperCase() : undefined,
      currencyDisplay: options.currencyDisplay || 'symbol', minF, maxF, useGrouping: options.useGrouping !== false,
      notation: options.notation || 'standard', compactDisplay: options.compactDisplay || 'short',
      unit: options.unit, unitDisplay: options.unitDisplay || 'short', signDisplay: options.signDisplay || 'auto',
      minimumIntegerDigits: options.minimumIntegerDigits || 1, maximumSignificantDigits: options.maximumSignificantDigits,
    });
  }
  format(value) {
    const o = this._o;
    const d = intlData[o.lang];
    let n = typeof value === 'bigint' ? Number(value) : Number(value);
    if (Number.isNaN(n)) return 'NaN';
    if (!Number.isFinite(n)) return (n < 0 ? '-' : '') + '∞';
    if (o.style === 'percent') n *= 100;
    let suffix = '';
    if (o.notation === 'compact') {
      const abs = Math.abs(n);
      const units = o.lang === 'es' ? [[1e12, ' B'], [1e9, ' mil M'], [1e6, ' M'], [1e3, ' mil']] : [[1e12, 'T'], [1e9, 'B'], [1e6, 'M'], [1e3, 'K']];
      for (const [v, s] of units) if (abs >= v) { n /= v; suffix = s; break; }
    }
    const neg = n < 0 || Object.is(n, -0);
    let abs = Math.abs(n);
    let text;
    if (o.maximumSignificantDigits) text = String(Number(abs.toPrecision(o.maximumSignificantDigits)));
    else {
      const maxF = suffix ? Math.max(o.maxF, abs < 10 ? 1 : 0) : o.maxF;
      text = abs.toFixed(maxF);
      if (text.includes('.')) {
        let [i, f] = text.split('.');
        while (f.length > o.minF && f.endsWith('0')) f = f.slice(0, -1);
        text = f ? `${i}.${f}` : i;
      }
    }
    let [int, frac] = text.split('.');
    int = int.padStart(o.minimumIntegerDigits, '0');
    if (o.useGrouping) int = groupDigits(int, d.group, d.minGroup || 4);
    let out = frac ? int + d.decimal + frac : int;
    out += suffix;
    if (o.style === 'percent') out += (o.lang === 'en' ? '%' : ' %');
    if (o.style === 'currency') {
      const sym = o.currencyDisplay === 'code' ? o.currency : (o.currencyDisplay === 'name' ? o.currency : (currencySymbols[o.currency] || o.currency));
      if (d.currencyAfter) out = out + ' ' + sym;
      else out = sym + (d.currencyPrefixSpace || sym.length > 1 && /^[A-Z]+$/.test(sym) ? ' ' : '') + out;
    }
    if (o.style === 'unit' && o.unit) {
      const units = { kilometer: 'km', meter: 'm', centimeter: 'cm', millimeter: 'mm', kilogram: 'kg', gram: 'g', liter: 'L',
        milliliter: 'mL', second: 's', millisecond: 'ms', minute: 'min', hour: 'h', day: 'd', byte: 'byte', kilobyte: 'kB',
        megabyte: 'MB', gigabyte: 'GB', percent: '%', celsius: '°C', fahrenheit: '°F', 'kilometer-per-hour': 'km/h' };
      const u = units[o.unit] || o.unit;
      out += u === '%' || u.startsWith('°') ? u : ' ' + u;
    }
    if (neg && abs !== 0) out = '-' + out;
    else if (o.signDisplay === 'always' || (o.signDisplay === 'exceptZero' && abs !== 0)) out = '+' + out;
    return out;
  }
  formatToParts(v) { return [{ type: 'literal', value: this.format(v) }]; }
  formatRange(a, b) { return `${this.format(a)}–${this.format(b)}`; }
  resolvedOptions() {
    const o = this._o;
    return { locale: o.locale, numberingSystem: 'latn', style: o.style, currency: o.currency, minimumIntegerDigits: o.minimumIntegerDigits, minimumFractionDigits: o.minF, maximumFractionDigits: o.maxF, useGrouping: o.useGrouping ? 'auto' : false, notation: o.notation, signDisplay: o.signDisplay };
  }
  static supportedLocalesOf(l) { return (Array.isArray(l) ? l : [l]).filter((x) => intlData[String(x).split('-')[0]]); }
}
const tzOffset = () => -new Date().getTimezoneOffset();
class IntlDateTimeFormat {
  constructor(locales, options = {}) {
    const { tag, lang } = resolveLocale(locales);
    const o = Object.assign({}, options);
    const hasAny = ['weekday', 'era', 'year', 'month', 'day', 'hour', 'minute', 'second', 'dateStyle', 'timeStyle', 'dayPeriod', 'fractionalSecondDigits', 'timeZoneName'].some((k) => o[k] !== undefined);
    if (!hasAny) { o.year = 'numeric'; o.month = 'numeric'; o.day = 'numeric'; }
    const hour12 = o.hour12 !== undefined ? !!o.hour12 : (o.hourCycle ? o.hourCycle === 'h12' || o.hourCycle === 'h11' : intlData[lang].h12);
    hidden(this, '_o', Object.assign(o, { locale: tag, lang, hour12, utc: o.timeZone === 'UTC' || o.timeZone === 'Etc/UTC' }));
  }
  _parts(date) {
    const o = this._o;
    const d = intlData[o.lang];
    const t = date === undefined ? new Date() : new Date(date);
    if (Number.isNaN(t.getTime())) throw new RangeError('Invalid time value');
    const g = (k) => (o.utc ? t['getUTC' + k]() : t['get' + k]());
    const Y = g('FullYear'), M = g('Month'), D = g('Date'), W = g('Day'), h = g('Hours'), m = g('Minutes'), s = g('Seconds');
    const date_ = [], time_ = [];
    let year = o.year, month = o.month, day = o.day, weekday = o.weekday, hour = o.hour, minute = o.minute, second = o.second;
    if (o.dateStyle) {
      ({ full: () => { weekday = 'long'; month = 'long'; day = 'numeric'; year = 'numeric'; },
        long: () => { month = 'long'; day = 'numeric'; year = 'numeric'; },
        medium: () => { month = 'short'; day = 'numeric'; year = 'numeric'; },
        short: () => { month = 'numeric'; day = 'numeric'; year = '2-digit'; } })[o.dateStyle]();
    }
    if (o.timeStyle) { hour = 'numeric'; minute = '2-digit'; if (o.timeStyle !== 'short') second = '2-digit'; }
    const monthName = (style) => style === 'long' ? d.months[M] : (style === 'short' ? d.months[M].slice(0, 3) + (o.lang === 'en' ? '' : '') : d.months[M][0]);
    const yearText = year === '2-digit' ? pad2(Y % 100) : String(Y);
    if (month === 'long' || month === 'short' || month === 'narrow') {
      const mt = monthName(month);
      const parts = [];
      if (o.lang === 'en') {
        if (weekday) parts.push(weekday === 'long' ? d.days[W] : d.days[W].slice(0, 3));
        const md = day ? `${mt} ${day === '2-digit' ? pad2(D) : D}` : mt;
        date_.push((parts.length ? parts.join(' ') + ', ' : '') + md + (year ? (day ? ', ' : ' ') + yearText : ''));
      } else {
        const of = d.of ? ` ${d.of} ` : ' ';
        if (weekday) parts.push((weekday === 'long' ? d.days[W] : d.days[W].slice(0, 3)) + ',');
        const dm = day ? `${day === '2-digit' ? pad2(D) : D}${o.lang === 'de' ? '.' : ''}${of}${mt}` : mt;
        date_.push([...parts, dm + (year ? of + yearText : '')].join(' '));
      }
    } else if (year || month || day) {
      const mm = month === '2-digit' ? pad2(M + 1) : String(M + 1);
      const dd = day === '2-digit' ? pad2(D) : String(D);
      const seq = { mdy: [month && mm, day && dd, year && yearText], dmy: [day && dd, month && mm, year && yearText] }[d.order];
      let text = seq.filter(Boolean).join(d.sep);
      if (weekday) text = (weekday === 'long' ? d.days[W] : d.days[W].slice(0, 3)) + ', ' + text;
      date_.push(text);
    } else if (weekday) {
      date_.push(weekday === 'long' ? d.days[W] : (weekday === 'short' ? d.days[W].slice(0, 3) : d.days[W][0]));
    }
    if (hour || minute || second) {
      let hh = h;
      let suffix = '';
      if (o.hour12 && hour) { suffix = ' ' + (h < 12 ? d.am : d.pm); hh = h % 12 === 0 ? 12 : h % 12; }
      const hText = hour ? (hour === '2-digit' || (!o.hour12 && o.lang !== 'en') ? pad2(hh) : String(hh)) : '';
      const bits = [hText, minute ? pad2(m) : '', second ? pad2(s) : ''].filter((x) => x !== '');
      time_.push(bits.join(':') + suffix);
    }
    if (o.timeZoneName) {
      const off = o.utc ? 0 : tzOffset();
      time_.push(off === 0 ? 'UTC' : `GMT${off > 0 ? '+' : '-'}${Math.floor(Math.abs(off) / 60)}${Math.abs(off) % 60 ? ':' + pad2(Math.abs(off) % 60) : ''}`);
    }
    return [date_.join(' '), time_.join(' ')];
  }
  format(date) {
    const [a, b] = this._parts(date);
    return a && b ? `${a}, ${b}` : (a || b);
  }
  formatToParts(date) { return [{ type: 'literal', value: this.format(date) }]; }
  formatRange(a, b) { return `${this.format(a)} – ${this.format(b)}`; }
  resolvedOptions() {
    const o = this._o;
    const off = tzOffset();
    return { locale: o.locale, calendar: 'gregory', numberingSystem: 'latn', timeZone: o.timeZone || (off === 0 ? 'UTC' : `Etc/GMT${off > 0 ? '-' : '+'}${Math.round(Math.abs(off) / 60)}`), hour12: o.hour12, year: o.year, month: o.month, day: o.day };
  }
  static supportedLocalesOf(l) { return IntlNumberFormat.supportedLocalesOf(l); }
}
class IntlRelativeTimeFormat {
  constructor(locales, options = {}) {
    const { tag, lang } = resolveLocale(locales);
    hidden(this, '_o', { locale: tag, lang, numeric: options.numeric || 'always', style: options.style || 'long' });
  }
  format(value, unit) {
    const o = this._o;
    const d = intlData[o.lang];
    let u = String(unit).replace(/s$/, '');
    if (!d.rel[u]) throw new RangeError(`Invalid unit argument for format() '${unit}'`);
    const n = Number(value);
    if (o.numeric === 'auto') {
      if (n === 0 && u === 'second') return d.now;
      if (u === 'day' && n === -1) return d.yesterday;
      if (u === 'day' && n === 0) return d.today;
      if (u === 'day' && n === 1) return d.tomorrow;
    }
    const abs = Math.abs(n);
    const word = d.rel[u][abs === 1 ? 0 : 1];
    const num = new IntlNumberFormat(o.locale).format(abs);
    const phrase = `${num} ${word}`;
    return (n < 0 || Object.is(n, -0) ? d.past : d.future).replace('{0}', phrase);
  }
  formatToParts(v, u) { return [{ type: 'literal', value: this.format(v, u) }]; }
  resolvedOptions() { const o = this._o; return { locale: o.locale, style: o.style, numeric: o.numeric, numberingSystem: 'latn' }; }
  static supportedLocalesOf(l) { return IntlNumberFormat.supportedLocalesOf(l); }
}
class IntlPluralRules {
  constructor(locales, options = {}) { const { tag, lang } = resolveLocale(locales); hidden(this, '_o', { locale: tag, lang, type: options.type || 'cardinal' }); }
  select(n) {
    n = Number(n);
    if (this._o.type === 'ordinal' && this._o.lang === 'en') {
      const a = n % 10, b = n % 100;
      if (a === 1 && b !== 11) return 'one';
      if (a === 2 && b !== 12) return 'two';
      if (a === 3 && b !== 13) return 'few';
      return 'other';
    }
    if (this._o.lang === 'fr' || this._o.lang === 'pt') return n >= 0 && n < 2 ? 'one' : 'other';
    return n === 1 ? 'one' : 'other';
  }
  resolvedOptions() { return { locale: this._o.locale, type: this._o.type, pluralCategories: ['one', 'other'] }; }
  static supportedLocalesOf(l) { return IntlNumberFormat.supportedLocalesOf(l); }
}
class IntlListFormat {
  constructor(locales, options = {}) { const { tag, lang } = resolveLocale(locales); hidden(this, '_o', { locale: tag, lang, type: options.type || 'conjunction', style: options.style || 'long' }); }
  format(list) {
    const items = [...list].map(String);
    const d = intlData[this._o.lang];
    const word = this._o.type === 'disjunction' ? d.or : d.and;
    if (this._o.type === 'unit') return items.join(', ');
    if (items.length <= 1) return items.join('');
    if (items.length === 2) return `${items[0]} ${word} ${items[1]}`;
    return `${items.slice(0, -1).join(', ')}${this._o.lang === 'en' ? ',' : ''} ${word} ${items[items.length - 1]}`;
  }
  formatToParts(list) { return [{ type: 'literal', value: this.format(list) }]; }
  resolvedOptions() { return { locale: this._o.locale, type: this._o.type, style: this._o.style }; }
}
class IntlCollator {
  constructor(locales, options = {}) { const { tag } = resolveLocale(locales); hidden(this, '_o', { locale: tag, sensitivity: options.sensitivity || 'variant', numeric: !!options.numeric }); this.compare = this.compare.bind(this); }
  compare(a, b) {
    let x = String(a), y = String(b);
    if (this._o.sensitivity === 'base' || this._o.sensitivity === 'accent') { x = x.toLowerCase(); y = y.toLowerCase(); }
    if (this._o.sensitivity === 'base') { x = x.normalize('NFD').replace(/[̀-ͯ]/g, ''); y = y.normalize('NFD').replace(/[̀-ͯ]/g, ''); }
    if (this._o.numeric) {
      const re = /(\d+)|(\D+)/g;
      const ax = x.match(re) || [], by = y.match(re) || [];
      for (let i = 0; i < Math.min(ax.length, by.length); i++) {
        const p = ax[i], q = by[i];
        if (/^\d/.test(p) && /^\d/.test(q)) { const d = Number(p) - Number(q); if (d) return d < 0 ? -1 : 1; }
        else if (p !== q) return p < q ? -1 : 1;
      }
      return ax.length - by.length;
    }
    return x < y ? -1 : x > y ? 1 : 0;
  }
  resolvedOptions() { return { locale: this._o.locale, usage: 'sort', sensitivity: this._o.sensitivity, numeric: this._o.numeric }; }
}
class IntlSegmenter {
  constructor(locales, options = {}) { hidden(this, '_g', options.granularity || 'grapheme'); }
  segment(text) {
    const s = String(text);
    const g = this._g;
    const parts = g === 'word' ? s.match(/\w+|\W+/g) || [] : (g === 'sentence' ? s.match(/[^.!?]+[.!?]*\s*/g) || [] : [...s]);
    let index = 0;
    const segs = parts.map((p) => { const r = { segment: p, index, input: s, isWordLike: g === 'word' ? /\w/.test(p) : undefined }; index += p.length; return r; });
    return { [Symbol.iterator]: () => segs[Symbol.iterator](), containing: (i) => segs.find((x) => i >= x.index && i < x.index + x.segment.length) };
  }
}
class IntlDisplayNames {
  constructor(locales, options = {}) { hidden(this, '_t', options.type); }
  of(code) { return String(code); }
}
const IntlPolyfill = {
  NumberFormat: IntlNumberFormat, DateTimeFormat: IntlDateTimeFormat, RelativeTimeFormat: IntlRelativeTimeFormat,
  PluralRules: IntlPluralRules, ListFormat: IntlListFormat, Collator: IntlCollator, Segmenter: IntlSegmenter,
  DisplayNames: IntlDisplayNames,
  getCanonicalLocales: (l) => (l === undefined ? [] : (Array.isArray(l) ? l : [l]).map(String)),
  supportedValuesOf: () => [],
};
if (typeof globalThis.Intl === 'undefined') {
  defineProperty(Number.prototype, 'toLocaleString', { value: function (l, o) { return new IntlNumberFormat(l, o).format(this); }, writable: true, configurable: true });
  defineProperty(Date.prototype, 'toLocaleDateString', { value: function (l, o = {}) { return new IntlDateTimeFormat(l, o).format(this); }, writable: true, configurable: true });
  defineProperty(Date.prototype, 'toLocaleTimeString', { value: function (l, o) { return new IntlDateTimeFormat(l, o || { hour: 'numeric', minute: '2-digit', second: '2-digit' }).format(this); }, writable: true, configurable: true });
  defineProperty(Date.prototype, 'toLocaleString', { value: function (l, o) { return new IntlDateTimeFormat(l, o || { year: 'numeric', month: 'numeric', day: 'numeric', hour: 'numeric', minute: '2-digit', second: '2-digit' }).format(this); }, writable: true, configurable: true });
  defineProperty(String.prototype, 'localeCompare', { value: function (that, l, o) { return new IntlCollator(l, o).compare(this, that); }, writable: true, configurable: true });
}
''';
