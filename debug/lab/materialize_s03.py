"""Materialise section 3 (box model & layout) fixtures."""
import sys, re
sys.path.insert(0, "/workspaces/nativax/debug/lab")
# reuse shell helpers from materialize_s02
import materialize_s02 as M02

ROOT = __import__("pathlib").Path("/workspaces/nativax")
DST_ROOT = ROOT / "debug/lab/cases/s03"
SHELL_HTML = (ROOT/"debug/lab/cases/s01/001/index.html").read_text()
SHELL_CSS = (ROOT/"debug/lab/cases/s01/001/style.css").read_text()
SHELL_JS = (ROOT/"debug/lab/cases/s01/001/app.js").read_text()

import re as _re
def make_html(title_label, case_html):
    s = SHELL_HTML
    s = s.replace("NativaX Lab · html.001 · basic div",
                  f"NativaX Lab · box.{title_label} · {title_label}")
    s = _re.sub(r'(<section id="case"[^>]*>).*?(</section>)',
               lambda m: m.group(1) + "\n" + case_html + "\n  " + m.group(2),
               s, count=1, flags=_re.S)
    return s

def make_css(extra):
    return SHELL_CSS + "\n/* case-specific */\n" + extra + "\n"

def make_js(cid):
    return SHELL_JS.replace("html.001", cid)

CASES = []
def add(suf, name, html, css):
    CASES.append((f"{suf:03d}", name, html, css))

# 3.1 display
for i,(v,nm) in enumerate([("block","block"),("inline","inline"),("inline-block","inline-block"),
                            ("flex","flex"),("grid","grid"),("none","none"),
                            ("contents","contents"),("list-item","list-item"),
                            ("inline-flex","inline-flex"),("inline-grid","inline-grid")],1):
    add(i, f"display: {v}", f"<div id=t class='target' style='display:{v}'>x</div>", "")
# 3.2 width/height
vals = [("120px","width 120px"),("50%","width 50%"),("auto","width auto"),
        ("200px","min-width 200px"),("100px","max-width 100px"),
        ("80px","height 80px"),("40%","height 40%"),("auto","height auto"),
        ("60px","min-height 60px"),("30px","max-height 30px")]
for i,(v,nm) in enumerate(vals,11):
    if "min-width" in nm:
        css = ".target { min-width: 200px; }"
    elif "max-width" in nm:
        css = ".target { max-width: 100px; }"
    elif "min-height" in nm:
        css = ".target { min-height: 60px; }"
    elif "max-height" in nm:
        css = ".target { max-height: 30px; }"
    elif "width" in nm and "auto" not in nm and "%" not in v and "min" not in nm and "max" not in nm:
        css = f".target {{ width: {v}; }}"
    elif "height" in nm and "auto" not in nm and "%" not in v:
        css = f".target {{ height: {v}; }}"
    elif "%" in v and "width" in nm:
        css = f".target {{ width: {v}; }}"
    elif "%" in v and "height" in nm:
        css = f".target {{ height: {v}; }}"
    else:
        css = ""
    add(i+10, nm, "<div id=t class='target'>x</div>", css)
# 3.3 margin
for i in range(21,31):
    add(i, f"margin variant {i-20}", "<div id=t class='target'>x</div>",
        [".target { margin: 8px; }",".target { margin: 4px 8px; }",".target { margin: 4px 8px 12px; }",
         ".target { margin: 1px 2px 3px 4px; }",".target { margin: -4px; }",
         ".target { margin-top: 10px; }",".target { margin-right: 10px; }",
         ".target { margin-bottom: 10px; }",".target { margin-left: 10px; }",
         ".target { margin: 0 auto; }"][i-21])
# 3.4 padding
for i in range(31,41):
    add(i, f"padding variant {i-30}", "<div id=t class='target'>x</div>",
        [".target { padding: 8px; }",".target { padding: 4px 8px; }",".target { padding: 4px 8px 12px; }",
         ".target { padding: 1px 2px 3px 4px; }",".target { padding-top: 10px; }",
         ".target { padding-right: 10px; }",".target { padding-bottom: 10px; }",
         ".target { padding-left: 10px; }",".target { padding: 0; }",
         ".target { padding: 12px 20px; }"][i-31])
# 3.5 border
for i in range(41,51):
    add(i, f"border variant {i-40}", "<div id=t class='target'>x</div>",
        [".target { border: 1px solid #ff0000; }",".target { border: 2px dashed #00ff00; }",
         ".target { border: 3px dotted #0000ff; }",".target { border-top: 4px solid #ff00ff; }",
         ".target { border-right: 1px solid #ffff00; }",".target { border-bottom: 2px solid #00ffff; }",
         ".target { border-left: 3px solid #ff8800; }",".target { border-radius: 8px; }",
         ".target { border-radius: 4px 8px 12px 16px; }",".target { border-color: #ff0000; border-width: 2px; border-style: solid; }"][i-41])
# 3.6 box-sizing
for i in range(51,61):
    add(i, f"box-sizing variant {i-50}", "<div id=t class='target'>x</div>",
        [".target { box-sizing: content-box; width: 100px; padding: 10px; border: 2px solid #000; }",
         ".target { box-sizing: border-box; width: 100px; padding: 10px; border: 2px solid #000; }",
         ".target { box-sizing: content-box; }",".target { box-sizing: border-box; }",
         ".target { width: 100px; }",".target { width: 100px; padding: 8px; }",
         ".target { width: 100px; border: 1px solid #000; }",
         ".target { max-width: 50%; }",".target { min-width: 10px; }",
         ".target { width: auto; }"][i-51])
# 3.7 overflow
for i in range(61,71):
    add(i, f"overflow variant {i-60}", "<div id=t class='target'>x</div>",
        [".target { overflow: hidden; }",".target { overflow: scroll; }",
         ".target { overflow: auto; }",".target { overflow: visible; }",
         ".target { overflow: clip; }",".target { overflow-x: hidden; }",
         ".target { overflow-y: scroll; }",".target { overflow: hidden; height: 20px; }",
         ".target { text-overflow: ellipsis; overflow: hidden; white-space: nowrap; }",
         ".target { overflow: auto; max-height: 40px; }"][i-61])
# 3.8 visibility/opacity
for i in range(71,81):
    add(i, f"visibility/opacity variant {i-70}", "<div id=t class='target'>x</div>",
        [".target { visibility: visible; }",".target { visibility: hidden; }",
         ".target { opacity: 1; }",".target { opacity: 0.5; }",".target { opacity: 0; }",
         ".target { opacity: 0.25; }",".target { visibility: visible; opacity: 0.8; }",
         ".target { visibility: hidden; opacity: 1; }",".target { opacity: 0.1; }",
         ".target { opacity: 0.9; }"][i-71])
# 3.9 position (style records; layout may not position)
for i in range(81,91):
    add(i, f"position variant {i-80}", "<div id=t class='target'>x</div>",
        [".target { position: static; }",".target { position: relative; }",
         ".target { position: absolute; top: 10px; left: 20px; }",
         ".target { position: fixed; top: 0; right: 0; }",
         ".target { position: sticky; top: 0; }",".target { position: relative; z-index: 2; }",
         ".target { position: absolute; bottom: 5px; }",".target { position: relative; top: 4px; }",
         ".target { position: static; z-index: auto; }",".target { position: relative; left: 8px; }"][i-81])
# 3.10 float/clear/z-index
for i in range(91,101):
    add(i, f"float/clear/z-index variant {i-90}", "<div id=t class='target'>x</div>",
        [".target { float: left; }",".target { float: right; }",".target { float: none; }",
         ".target { clear: both; }",".target { clear: left; }",".target { z-index: 1; }",
         ".target { z-index: 99; }",".target { float: left; clear: right; }",
         ".target { position: relative; z-index: 5; }",".target { float: none; clear: none; }"][i-91])

DST_ROOT.mkdir(parents=True, exist_ok=True)
for suffix, name, html, css in CASES:
    num = int(suffix)
    folder = DST_ROOT / f"{num:03d}"
    folder.mkdir(parents=True, exist_ok=True)
    cid = f"box.{suffix}"
    (folder / "index.html").write_text(make_html(suffix, html))
    (folder / "style.css").write_text(make_css(css))
    (folder / "app.js").write_text(make_js(cid))
print("materialised", len(CASES), "folders")