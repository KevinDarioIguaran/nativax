#!/usr/bin/env python3
"""Report Bible-app-specific terms outside tests/examples/docs."""
import re, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
TERMS=re.compile(r'\b(bible|biblia|verse|vers[ií]culo|chapter|cap[ií]tulo|torah|updateMobileRef|shlomo|sileot)\b', re.I)
SKIP={'tests','test','examples','docs','progress','build','.dart_tool','.git','assets','static','tools'}
bad=[]
for p in ROOT.rglob('*'):
    if not p.is_file() or p.suffix not in {'.dart','.md','.yaml','.xml','.json','.html','.css','.js'}:
        continue
    rel=p.relative_to(ROOT)
    if p.name in {'repomix-output.xml', 'COMPAT.md'}: continue
    if any(part in SKIP for part in rel.parts): continue
    try: text=p.read_text(errors='ignore')
    except OSError: continue
    for m in TERMS.finditer(text):
        line=text.count('\n',0,m.start())+1
        bad.append((str(rel),line,m.group(0)))
for rel,line,term in bad[:200]:
    print(f'{rel}:{line}: {term}')
print(f'found {len(bad)} term(s) outside tests/examples/docs/progress')
sys.exit(1 if bad else 0)
