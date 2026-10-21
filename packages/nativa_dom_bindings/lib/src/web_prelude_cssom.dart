/// A pragmatic CSSOM for `<style>`/`<link>` sheets. Rules are kept as CSS
/// text on the owner node; editing a sheet writes the element's text, which
/// the runtime reparses through the normal mutation path.
const String webCssom = r'''
// ============================================================================
// CSSOM: styleSheets, CSSStyleSheet, CSSStyleRule, CSSStyleDeclaration
// ============================================================================
const cssSheetByNode = new WeakMap();
const cssImportant = (v) => /!\s*important\s*$/i.test(v);
const cssTrimImportant = (v) => v.replace(/\s*!\s*important\s*$/i, '').trim();
const cssKebab = (s) => String(s).replace(/[A-Z]/g, (m) => '-' + m.toLowerCase()).replace(/^webkit-/, '-webkit-');
const cssSplitTop = (text, sep) => {
  const out = [];
  let start = 0, depth = 0, quote = '', i = 0;
  while (i < text.length) {
    const c = text[i];
    if (quote) {
      if (c === '\\') { i += 2; continue; }
      if (c === quote) quote = '';
      i++;
      continue;
    }
    if (c === '"' || c === "'") { quote = c; i++; continue; }
    if (c === '/' && text[i + 1] === '*') {
      const end = text.indexOf('*/', i + 2);
      i = end < 0 ? text.length : end + 2;
      continue;
    }
    if (c === '(' || c === '[') depth++;
    else if (c === ')' || c === ']') depth = Math.max(0, depth - 1);
    else if (c === '{') depth++;
    else if (c === '}') depth = Math.max(0, depth - 1);
    else if (!depth && c === sep) {
      out.push(text.slice(start, i));
      start = i + 1;
    }
    i++;
  }
  out.push(text.slice(start));
  return out.map((s) => s.trim()).filter(Boolean);
};

const cssRulesFromText = (text) => {
  const rules = [];
  let i = 0;
  while (i < text.length) {
    while (i < text.length && /\s/.test(text[i])) i++;
    if (i >= text.length) break;
    if (text.startsWith('/*', i)) {
      const end = text.indexOf('*/', i + 2);
      i = end < 0 ? text.length : end + 2;
      continue;
    }
    const start = i;
    let quote = '', depth = 0, open = -1, semicolon = -1;
    while (i < text.length) {
      const c = text[i];
      if (quote) {
        if (c === '\\') { i += 2; continue; }
        if (c === quote) quote = '';
        i++;
        continue;
      }
      if (c === '"' || c === "'") { quote = c; i++; continue; }
      if (c === '/' && text[i + 1] === '*') {
        const end = text.indexOf('*/', i + 2);
        i = end < 0 ? text.length : end + 2;
        continue;
      }
      if (c === '(' || c === '[') depth++;
      else if (c === ')' || c === ']') depth = Math.max(0, depth - 1);
      else if (!depth && c === ';' && open < 0) { semicolon = i; break; }
      else if (!depth && c === '{') { open = i; break; }
      else if (!depth && c === '}') break;
      i++;
    }
    if (open < 0) {
      if (semicolon >= 0) {
        rules.push({ kind: 'at', text: text.slice(start, semicolon + 1), prelude: text.slice(start, semicolon).trim(), body: '' });
        i = semicolon + 1;
      } else {
        const tail = text.slice(start).trim();
        if (tail) rules.push({ kind: 'at', text: tail, prelude: tail, body: '' });
        break;
      }
      continue;
    }
    const prelude = text.slice(start, open).trim();
    let j = open + 1, bodyQuote = '', bodyDepth = 0;
    while (j < text.length) {
      const c = text[j];
      if (bodyQuote) {
        if (c === '\\') { j += 2; continue; }
        if (c === bodyQuote) bodyQuote = '';
        j++;
        continue;
      }
      if (c === '"' || c === "'") { bodyQuote = c; j++; continue; }
      if (c === '/' && text[j + 1] === '*') {
        const end = text.indexOf('*/', j + 2);
        j = end < 0 ? text.length : end + 2;
        continue;
      }
      if (c === '(' || c === '[') bodyDepth++;
      else if (c === ')' || c === ']') bodyDepth = Math.max(0, bodyDepth - 1);
      else if (!bodyDepth && c === '{') bodyDepth++;
      else if (!bodyDepth && c === '}') break;
      j++;
    }
    const body = text.slice(open + 1, j);
    rules.push({
      kind: prelude.startsWith('@') ? 'at' : 'style',
      text: text.slice(start, Math.min(text.length, j + 1)),
      prelude,
      body,
    });
    i = j + 1;
  }
  return rules;
};

const cssRuleList = (rules, owner) => {
  const list = rules.slice();
  Object.defineProperty(list, 'item', { value: (i) => list[i] || null, enumerable: false });
  for (const r of list) hidden(r, '__owner', owner);
  return list;
};

class CSSRule {
  constructor(token, owner, data) {
    if (token !== cssSheetByNode) throw new TypeError('Illegal constructor');
    hidden(this, '__owner', owner);
    hidden(this, '__data', data);
  }
  get parentStyleSheet() { return this.__owner || null; }
  get parentRule() { return null; }
  get cssText() { return this.__data.text; }
  set cssText(v) {
    this.__data.text = String(v);
    const d = cssRulesFromText(this.__data.text)[0];
    if (d) this.__data = d;
    writeSheetText(this.__owner);
  }
}
CSSRule.STYLE_RULE = 1; CSSRule.MEDIA_RULE = 4; CSSRule.IMPORT_RULE = 3;
class CSSStyleRule extends CSSRule {
  constructor(token, owner, data) {
    super(token, owner, data);
    this.__style = null;
  }
  get type() { return 1; }
  get selectorText() { return this.__data.prelude; }
  set selectorText(v) {
    this.__data.prelude = String(v);
    this.__data.text = this.__data.prelude + '{' + this.__data.body + '}';
    writeSheetText(this.__owner);
  }
  get style() {
    if (!this.__style) this.__style = makeCssStyle(this, () => this.__data.body, (body) => {
      this.__data.body = body;
      this.__data.text = this.__data.prelude + '{' + body + '}';
      writeSheetText(this.__owner);
    });
    return this.__style;
  }
}
class CSSMediaRule extends CSSRule {
  get type() { return 4; }
  get cssRules() { return cssRuleList(cssRulesFromText(this.__data.body), this.__owner); }
  insertRule(rule, index = 0) {
    const nested = cssRulesFromText(this.__data.body);
    const text = String(rule);
    nested.splice(clampCssIndex(index, nested.length), 0, ...cssRulesFromText(text));
    this.__data.body = nested.map((r) => r.text).join('\n');
    this.__data.text = this.__data.prelude + '{' + this.__data.body + '}';
    writeSheetText(this.__owner);
    return index;
  }
  deleteRule(index) {
    const nested = cssRulesFromText(this.__data.body);
    if (index < 0 || index >= nested.length) throw new DOMException('index out of range', 'IndexSizeError');
    nested.splice(index, 1);
    this.__data.body = nested.map((r) => r.text).join('\n');
    this.__data.text = this.__data.prelude + '{' + this.__data.body + '}';
    writeSheetText(this.__owner);
  }
}
class CSSImportRule extends CSSRule {
  get type() { return 3; }
  get href() { const m = /url\(\s*["']?([^"')]+)/i.exec(this.__data.prelude); return m ? m[1] : ''; }
}
const clampCssIndex = (i, max) => {
  const n = Number(i);
  if (!Number.isFinite(n) || n < 0) throw new DOMException('index out of range', 'IndexSizeError');
  const x = Math.trunc(n);
  if (x > max) throw new DOMException('index out of range', 'IndexSizeError');
  return x;
};
const ruleFor = (owner, data) => data.kind === 'style'
  ? new CSSStyleRule(cssSheetByNode, owner, data)
  : (data.prelude.startsWith('@media') || data.prelude.startsWith('@supports'))
    ? new CSSMediaRule(cssSheetByNode, owner, data)
    : (data.prelude.startsWith('@import') ? new CSSImportRule(cssSheetByNode, owner, data) : new CSSRule(cssSheetByNode, owner, data));

const writeSheetText = (sheet) => {
  if (!sheet) return;
  const node = sheet.__node;
  if (!node) return;
  node.textContent = sheet.__rules.map((r) => r.text).join('\n');
};
const readSheetRules = (sheet) => {
  sheet.__rules = cssRulesFromText(sheet.__node ? sheet.__node.textContent : '');
  return sheet.__rules;
};

class CSSStyleSheet {
  constructor(token, node) {
    if (token !== cssSheetByNode) throw new TypeError('Illegal constructor');
    hidden(this, '__node', node);
    defineProperty(this, '__rules', { value: [], writable: true, enumerable: false, configurable: true });
    this.disabled = false;
    this.media = { mediaText: '', get length() { return 0; }, item() { return null; } };
  }
  get ownerNode() { return this.__node; }
  get href() { return this.__node && this.__node.localName === 'link' ? this.__node.href : null; }
  get title() { return this.__node ? (this.__node.getAttribute('title') || null) : null; }
  get type() { return 'text/css'; }
  get cssRules() {
    return cssRuleList(readSheetRules(this).map((r) => ruleFor(this, r)), this);
  }
  get rules() { return this.cssRules; }
  insertRule(rule, index = 0) {
    const text = String(rule).trim();
    if (!text) throw new DOMException('The rule is empty.', 'SyntaxError');
    if (!text.includes('{') && !text.endsWith(';')) throw new DOMException('The rule is not valid.', 'SyntaxError');
    const rules = readSheetRules(this);
    const at = clampCssIndex(index, rules.length);
    rules.splice(at, 0, ...cssRulesFromText(text));
    writeSheetText(this);
    return at;
  }
  deleteRule(index) {
    const rules = readSheetRules(this);
    const at = clampCssIndex(index, rules.length - 1);
    rules.splice(at, 1);
    writeSheetText(this);
  }
  replaceSync(text) {
    this.__node.textContent = String(text);
    readSheetRules(this);
  }
  replace(text) { this.replaceSync(text); return Promise.resolve(this); }
}

const cssStyleSheetFor = (node) => {
  if (!node || (node.localName !== 'style' && node.localName !== 'link')) return null;
  if (node.localName === 'link') {
    const rel = String(node.getAttribute('rel') || '').toLowerCase().split(/\s+/);
    if (!rel.includes('stylesheet')) return null;
  }
  let sheet = cssSheetByNode.get(node);
  if (!sheet) { sheet = new CSSStyleSheet(cssSheetByNode, node); cssSheetByNode.set(node, sheet); }
  return sheet;
};
const cssStyleSheets = () => document.querySelectorAll('style, link[rel~="stylesheet"]')
  .map(cssStyleSheetFor).filter(Boolean);
const cssStyleSheetList = () => {
  const list = cssStyleSheets();
  Object.defineProperty(list, 'item', { value: (i) => list[i] || null, enumerable: false });
  return list;
};

const cssDecls = (body) => cssSplitTop(String(body || ''), ';').map((part) => {
  const i = part.indexOf(':');
  if (i < 0) return null;
  const name = part.slice(0, i).trim().toLowerCase();
  let value = part.slice(i + 1).trim();
  const important = cssImportant(value);
  if (important) value = cssTrimImportant(value);
  return { name, value, important };
}).filter(Boolean);
const cssDeclText = (decls) => decls.map((d) => `${d.name}: ${d.value}${d.important ? ' !important' : ''}`).join('; ');

const makeCssStyle = (rule, getBody, setBody) => {
  const api = {
    getPropertyValue(name) {
      const key = String(name).toLowerCase();
      const d = cssDecls(getBody()).find((x) => x.name === key);
      return d ? d.value : '';
    },
    getPropertyPriority(name) {
      const key = String(name).toLowerCase();
      const d = cssDecls(getBody()).find((x) => x.name === key);
      return d && d.important ? 'important' : '';
    },
    setProperty(name, value, priority = '') {
      const key = String(name).toLowerCase();
      const decls = cssDecls(getBody()).filter((x) => x.name !== key);
      const v = value === null || value === undefined ? '' : String(value).trim();
      if (v) decls.push({ name: key, value: v, important: String(priority).toLowerCase() === 'important' });
      setBody(cssDeclText(decls));
    },
    removeProperty(name) {
      const key = String(name).toLowerCase();
      const old = api.getPropertyValue(key);
      setBody(cssDeclText(cssDecls(getBody()).filter((x) => x.name !== key)));
      return old;
    },
    get cssText() { return getBody(); },
    set cssText(v) { setBody(String(v)); },
    get length() { return cssDecls(getBody()).length; },
    item(i) { return cssDecls(getBody())[i]?.name || ''; },
  };
  return new Proxy(api, {
    get(t, p, r) {
      if (p in t) return t[p];
      if (typeof p !== 'string') return undefined;
      return t.getPropertyValue(cssKebab(p));
    },
    set(t, p, v) {
      if (p in t && p !== 'cssText') { t[p] = v; return true; }
      t.setProperty(cssKebab(p), v);
      return true;
    },
  });
};

// A style element's `sheet` is live and updates the runtime's StyleEngine
// because the node's text changes through the normal DOM mutation path.
accessor(EP, 'sheet', function () {
  return this.localName === 'style' ? cssStyleSheetFor(this) : null;
});
''';
