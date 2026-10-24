#!/usr/bin/env python3
"""Static, app-agnostic audit of HTML/CSS/JS used by a NativaX app."""
import json, re, sys
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path

CSS_PROP = re.compile(r'([-\w]+)\s*:\s*([^;{}]+)')
SELECTOR = re.compile(r'([^{}]+)\{')
AT_RULE = re.compile(r'@([-\w]+)')
JS_API = re.compile(r'\b(document|window|navigator|location|localStorage|sessionStorage|indexedDB|fetch|console|history|performance)\s*\.\s*([A-Za-z_$][\w$]*)')
JS_CALL = re.compile(r'\b([A-Za-z_$][\w$]*)\s*\(')
JS_MUT = re.compile(r'\.(textContent|innerHTML|innerText|className|value|checked|style|classList|setAttribute|removeAttribute|appendChild|insertBefore|removeChild|remove)\b')
SELECTOR_PSEUDO = re.compile(r'::?([-\w]+)')

class Tags(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.tags=Counter(); self.attrs=Counter()
    def handle_starttag(self, tag, attrs):
        self.tags[tag]+=1
        for k,_ in attrs: self.attrs[k]+=1

def walk(root):
    for p in root.rglob('*'):
        if p.is_file() and not any(x in p.parts for x in ('build','.dart_tool','node_modules','.git','.venv','__pycache__')):
            yield p

def js_clean(src):
    # strip comments and string/template bodies so API/mutation scans see code only
    src=re.sub(r'/\*.*?\*/','',src,flags=re.S)
    src=re.sub(r'//[^\n]*','',src)
    src=re.sub(r"'(?:\\.|[^'\\])*'", "''", src)
    src=re.sub(r'"(?:\\.|[^"\\])*"', '""', src)
    src=re.sub(r'`(?:\\.|[^`\\])*`','``',src,flags=re.S)
    return src

def analyze(root):
    tags=Tags(); css_props=Counter(); selectors=Counter(); pseudos=Counter(); at_rules=Counter()
    apis=Counter(); calls=Counter(); muts=Counter(); files=Counter()
    for p in walk(root):
        suf=p.suffix.lower(); rel=str(p.relative_to(root))
        try: text=p.read_text(errors='ignore')
        except OSError: continue
        if suf in ('.html','.htm'):
            files['html']+=1
            t=Tags(); t.feed(text); tags.tags.update(t.tags); tags.attrs.update(t.attrs)
            for m in re.finditer(r'<style[^>]*>(.*?)</style>',text,re.S|re.I):
                for prop,val in CSS_PROP.findall(m.group(1)): css_props[prop.lower()]+=1
                for sel in SELECTOR.findall(m.group(1)):
                    for part in sel.split(','):
                        part=part.strip()
                        if part and not part.startswith('@'): selectors[part]+=1
                for x in AT_RULE.findall(m.group(1)): at_rules[x.lower()]+=1
            for m in re.finditer(r'<script[^>]*>(.*?)</script>',text,re.S|re.I):
                js=js_clean(m.group(1));
                for a,b in JS_API.findall(js): apis[f'{a}.{b}']+=1
                for c in JS_CALL.findall(js): calls[c]+=1
                for x in JS_MUT.findall(js): muts[x]+=1
        elif suf=='.css':
            files['css']+=1
            for prop,val in CSS_PROP.findall(js_clean(text)): css_props[prop.lower()]+=1
            for sel in SELECTOR.findall(js_clean(text)):
                for part in sel.split(','):
                    part=part.strip()
                    if part and not part.startswith('@'): selectors[part]+=1
            for x in AT_RULE.findall(text): at_rules[x.lower()]+=1
            for pse in SELECTOR_PSEUDO.findall(js_clean(text)): pseudos[pse.lower()]+=1
        elif suf in ('.js','.mjs'):
            files['js']+=1
            js=js_clean(text)
            for a,b in JS_API.findall(js): apis[f'{a}.{b}']+=1
            for c in JS_CALL.findall(js): calls[c]+=1
            for x in JS_MUT.findall(js): muts[x]+=1
    return dict(files=files, tags=tags.tags, attrs=tags.attrs, css_props=css_props,
                selectors=selectors, pseudos=pseudos, at_rules=at_rules,
                apis=apis, calls=calls, mutations=muts)

def md(root, d):
    out=[f'# Static app report: `{root}`','']
    out.append('## Files')
    for k,v in d['files'].most_common(): out.append(f'- {k}: {v}')
    out.append('\n## HTML tags (top 40)')
    for k,v in d['tags'].most_common(40): out.append(f'- `{k}`: {v}')
    out.append('\n## HTML attributes (top 40)')
    for k,v in d['attrs'].most_common(40): out.append(f'- `{k}`: {v}')
    out.append('\n## CSS properties (top 80)')
    for k,v in d['css_props'].most_common(80): out.append(f'- `{k}`: {v}')
    out.append('\n## CSS pseudo-classes/elements (top 40)')
    for k,v in d['pseudos'].most_common(40): out.append(f'- `:{k}`: {v}')
    out.append('\n## JS DOM/BOM APIs (top 60)')
    for k,v in d['apis'].most_common(60): out.append(f'- `{k}`: {v}')
    out.append('\n## JS mutations (top 30)')
    for k,v in d['mutations'].most_common(30): out.append(f'- `{k}`: {v}')
    out.append('\n## JS calls (top 60)')
    for k,v in d['calls'].most_common(60): out.append(f'- `{k}()`: {v}')
    return '\n'.join(out)+'\n'

def main():
    if len(sys.argv)<2:
        print('usage: tools/analyze_app.py APP_DIR [OUT.md]', file=sys.stderr); return 2
    root=Path(sys.argv[1]).resolve(); d=analyze(root)
    out=Path(sys.argv[2]) if len(sys.argv)>2 else Path('tools/analysis')/(root.name+'.md')
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(md(root,d))
    json_path=out.with_suffix('.json'); json_path.write_text(json.dumps(d,indent=2))
    print(out); return 0

if __name__=='__main__': raise SystemExit(main())
