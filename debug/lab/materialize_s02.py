"""Materialise section 2 (CSS selectors & cascade) fixtures.

Each case is a real, self-contained folder under debug/lab/cases/s02/NNN/
with index.html, style.css and app.js. Run once; the folders are committed.
"""
import shutil
from pathlib import Path

ROOT = Path("/workspaces/nativax")
SRC = ROOT / "debug/lab/cases/s01/001"
DST_ROOT = ROOT / "debug/lab/cases/s02"

SHELL_HTML = (SRC / "index.html").read_text()
SHELL_CSS = (SRC / "style.css").read_text()
SHELL_JS = (SRC / "app.js").read_text()


def make_html(title_label, case_html):
    s = SHELL_HTML
    s = s.replace("NativaX Lab · html.001 · basic div",
                  f"NativaX Lab · css.{title_label} · {title_label}")
    # replace the #case section body
    import re
    s = re.sub(r'(<section id="case"[^>]*>).*?(</section>)',
               lambda m: m.group(1) + "\n" + case_html + "\n  " + m.group(2),
               s, count=1, flags=re.S)
    # case id in footer/title-ish spots
    s = s.replace("window.__nativaxCase = 'html.001'", "window.__nativaxCase = 'css." + title_label + "'")
    return s


def make_css(extra):
    return SHELL_CSS + "\n/* case-specific */\n" + extra + "\n"


def make_js(cid):
    return SHELL_JS.replace("html.001", cid).replace("basic div", cid)


# --------------------------------------------------------------------------- #
# 100 case definitions: (suffix, name, case_html, css_extra)
# --------------------------------------------------------------------------- #
CASES = []

def add(suffix, name, html, css):
    CASES.append((f"{suffix:03d}", name, html, css))

# 2.1 basic selectors
for i in range(1, 11):
    add(i, f"basic selector variant {i}", "<div id=t class='target x' data-v='pre-mid-suf word'>x</div>",
        "div { color: #ff0000; }")
# override a few with distinct rules
CASES[-10] = ("001", "tag selector colours the element", "<div id=t class='target'>x</div>", "div { color: #ff0000; }")
CASES[-9] = ("002", "class selector colours the element", "<div id=t class='target'>x</div>", ".target { color: #00ff00; }")
CASES[-8] = ("003", "id selector colours the element", "<div id=t class='target'>x</div>", "#t { color: #0000ff; }")
CASES[-7] = ("004", "universal selector colours every element", "<div id=t class='target'>x</div>", "* { color: #ff00ff; }")
CASES[-6] = ("005", "attribute presence selector", "<div id=t class='target' data-x> x</div>", "[data-x] { color: #ffff00; }")
CASES[-5] = ("006", "attribute equals selector", "<div id=t class='target' data-v='7'>x</div>", "[data-v=\"7\"] { color: #00ffff; }")
CASES[-4] = ("007", "attribute contains selector", "<div id=t class='target' data-v='a-mid-b'>x</div>", "[data-v*=\"mid\"] { color: #ff8800; }")
CASES[-3] = ("008", "attribute starts-with selector", "<div id=t class='target' data-v='pre-fix'>x</div>", "[data-v^=\"pre\"] { color: #88ff00; }")
CASES[-2] = ("009", "attribute ends-with selector", "<div id=t class='target' data-v='fix-suf'>x</div>", "[data-v$=\"suf\"] { color: #0088ff; }")
CASES[-1] = ("010", "attribute word selector", "<div id=t class='target' data-v='a word b'>x</div>", "[data-v~=\"word\"] { color: #ff0088; }")

# 2.2 combinators
add(11, "descendant combinator", "<div class='wrap'><div id=t class='target'>x</div></div>", ".wrap .target { color: #ff0000; }")
add(12, "child combinator", "<div class='wrap'><div id=t class='target'>x</div></div>", ".wrap > .target { color: #00ff00; }")
add(13, "adjacent sibling combinator", "<div class='a'></div><div id=t class='target'>x</div>", ".a + .target { color: #0000ff; }")
add(14, "general sibling combinator", "<div class='a'></div><p>y</p><div id=t class='target'>x</div>", ".a ~ .target { color: #ff00ff; }")
add(15, "grouped selectors", "<div id=t class='target'>x</div>", ".nope, .target { color: #ffff00; }")
add(16, "deep descendant", "<div class='a'><div class='b'><div id=t class='target'>x</div></div></div>", ".a .b .target { color: #00ffff; }")
add(17, "child of id", "<div id='p'><div id=t class='target'>x</div></div>", "#p > .target { color: #ff8800; }")
add(18, "sibling with class filter", "<div class='a'></div><div id=t class='target x'>x</div>", ".a + .target.x { color: #88ff00; }")
add(19, "descendant with attribute", "<div class='wrap'><div id=t class='target' data-k='v'>x</div></div>", ".wrap .target[data-k='v'] { color: #0088ff; }")
add(20, "universal child", "<div class='wrap'><span id=t class='target'>x</span></div>", ".wrap > * { color: #ff0088; }")

# 2.3 pseudo-classes
add(21, "first-child pseudo-class", "<ul><li id=t class='target'>a</li><li>b</li></ul>", "li:first-child { color: #ff0000; }")
add(22, "last-child pseudo-class", "<ul><li>a</li><li id=t class='target'>b</li></ul>", "li:last-child { color: #00ff00; }")
add(23, "nth-child(2)", "<ul><li>a</li><li id=t class='target'>b</li><li>c</li></ul>", "li:nth-child(2) { color: #0000ff; }")
add(24, "nth-child(odd)", "<ul><li id=t class='target'>a</li><li>b</li><li>c</li></ul>", "li:nth-child(odd) { color: #ff00ff; }")
add(25, "nth-child(3n)", "<ul><li>a</li><li>b</li><li id=t class='target'>c</li></ul>", "li:nth-child(3n) { color: #ffff00; }")
add(26, "not() pseudo-class", "<div id=t class='target'>x</div><div class='skip'>y</div>", "div:not(.skip) { color: #00ffff; }")
add(27, "empty pseudo-class", "<div id=t class='target'></div>", "div:empty { color: #ff8800; }")
add(28, "first-of-type", "<p>a</p><div id=t class='target'>x</div><div>y</div>", "div:first-of-type { color: #88ff00; }")
add(29, "nth-of-type(2)", "<div>a</div><div id=t class='target'>x</div><div>y</div>", "div:nth-of-type(2) { color: #0088ff; }")
add(30, "last-of-type", "<div>a</div><div id=t class='target'>x</div>", "div:last-of-type { color: #ff0088; }")

# 2.4 specificity & cascade
add(31, "id beats class", "<p id=t class='c target'>x</p>", "#t { color: #00ff00; }\n.c { color: #ff0000; }")
add(32, "class beats element", "<p id=t class='c target'>x</p>", "p { color: #ff0000; }\n.c { color: #00ff00; }")
add(33, "later rule wins tie", "<p id=t class='target'>x</p>", "p { color: #ff0000; }\np { color: #00ff00; }")
add(34, "inline style wins", "<p id=t class='target' style='color:#0000ff'>x</p>", "p { color: #ff0000; }")
add(35, "important wins", "<p id=t class='target'>x</p>", "p { color: #ff0000 !important; }\np { color: #00ff00; }")
add(36, "important class beats id", "<p id=t class='c target'>x</p>", "#t { color: #ff0000; }\n.c { color: #00ff00 !important; }")
add(37, "two inline sheets order", "<style>p{color:#ff0000}</style><style>p{color:#00ff00}</style><p id=t class='target'>x</p>", "")
add(38, "media applies at wide viewport", "<p id=t class='target'>x</p>", "p { color: #ff0000; }\n@media (min-width: 320px) { p { color: #00ff00; } }")
add(39, "media does not apply at wide viewport", "<p id=t class='target'>x</p>", "p { color: #00ff00; }\n@media (max-width: 100px) { p { color: #ff0000; } }")
add(40, "color inherits from parent", "<div style='color:#0000ff'><p id=t class='target'>x</p></div>", "p { color: inherit; }")

# 2.5 inheritance & keywords
add(41, "color inherits", "<div class='parent'><p id=t class='target'>x</p></div>", ".parent { color: #0000ff; }\n.target { color: inherit; }")
add(42, "font-size inherits via em", "<div style='font-size:20px'><p id=t class='target'>x</p></div>", ".target { font-size: 1.5em; }")
add(43, "initial resets color", "<p id=t class='target' style='color:#ff0000'>x</p>", "p { color: initial; }")
add(44, "unset on color inherits", "<div style='color:#0000ff'><p id=t class='target'>x</p></div>", "p { color: unset; }")
add(45, "unset on margin resets", "<p id=t class='target' style='margin:10px'>x</p>", "p { margin: unset; }")
add(46, "inherit keyword on margin", "<div style='margin:12px'><p id=t class='target'>x</p></div>", "p { margin: inherit; }")
add(47, "currentColor border", "<div id=t class='target'>x</div>", ".target { color: #0000ff; border: 2px solid currentColor; }")
add(48, "transparent color", "<div id=t class='target'>x</div>", ".target { color: transparent; }")
add(49, "inherit from ancestor", "<section style='color:#ff00ff'><div><p id=t class='target'>x</p></div></section>", "p { color: inherit; }")
add(50, "default color black", "<div id=t class='target'>x</div>", "")

# 2.6 shorthand
add(51, "margin shorthand all", "<div id=t class='target'>x</div>", ".target { margin: 8px; }")
add(52, "margin two values", "<div id=t class='target'>x</div>", ".target { margin: 4px 8px; }")
add(53, "margin three values", "<div id=t class='target'>x</div>", ".target { margin: 4px 8px 12px; }")
add(54, "margin four values", "<div id=t class='target'>x</div>", ".target { margin: 1px 2px 3px 4px; }")
add(55, "padding shorthand", "<div id=t class='target'>x</div>", ".target { padding: 5px 10px; }")
add(56, "border shorthand", "<div id=t class='target'>x</div>", ".target { border: 3px solid #ff0000; }")
add(57, "border-top shorthand", "<div id=t class='target'>x</div>", ".target { border-top: 2px dashed #00ff00; }")
add(58, "background shorthand color", "<div id=t class='target'>x</div>", ".target { background: #0000ff; }")
add(59, "border-radius shorthand", "<div id=t class='target'>x</div>", ".target { border-radius: 4px 8px 12px 16px; }")
add(60, "font shorthand", "<div id=t class='target'>x</div>", ".target { font: 16px/1.5 sans-serif; }")

# 2.7 units
add(61, "length in px", "<div id=t class='target'>x</div>", ".target { width: 120px; }")
add(62, "length in em", "<div id=t class='target'>x</div>", ".target { font-size: 16px; margin: 2em; }")
add(63, "length in rem", "<div id=t class='target'>x</div>", ".target { font-size: 16px; padding: 1rem; }")
add(64, "length in percent", "<div id=t class='target'>x</div>", ".target { width: 50%; }")
add(65, "font-size px", "<div id=t class='target'>x</div>", ".target { font-size: 24px; }")
add(66, "font-size em", "<div style='font-size:16px'><div id=t class='target'>x</div></div>", ".target { font-size: 1.5em; }")
add(67, "line-height unitless", "<div id=t class='target'>x</div>", ".target { line-height: 1.6; }")
add(68, "border-width px", "<div id=t class='target'>x</div>", ".target { border: 4px solid #000; }")
add(69, "min-width px", "<div id=t class='target'>x</div>", ".target { min-width: 200px; }")
add(70, "max-width px", "<div id=t class='target'>x</div>", ".target { max-width: 100px; }")

# 2.8 colors
add(71, "hex 3-digit color", "<div id=t class='target'>x</div>", ".target { color: #f00; }")
add(72, "hex 6-digit color", "<div id=t class='target'>x</div>", ".target { color: #00ff00; }")
add(73, "rgb() color", "<div id=t class='target'>x</div>", ".target { color: rgb(0, 0, 255); }")
add(74, "rgba() color", "<div id=t class='target'>x</div>", ".target { color: rgba(255, 128, 0, 0.5); }")
add(75, "named color", "<div id=t class='target'>x</div>", ".target { color: red; }")
add(76, "hsl() color (unsupported)", "<div id=t class='target'>x</div>", ".target { color: hsl(120, 100%, 50%); }")
add(77, "transparent keyword", "<div id=t class='target'>x</div>", ".target { background-color: transparent; }")
add(78, "currentColor keyword", "<div id=t class='target'>x</div>", ".target { color: #0000ff; border: 1px solid currentColor; }")
add(79, "var() custom property (unsupported)", "<div id=t class='target'>x</div>", ":root { --c: #ff0000; }\n.target { color: var(--c); }")
add(80, "rgb percentages", "<div id=t class='target'>x</div>", ".target { color: rgb(100%, 0%, 0%); }")

# 2.9 media queries
add(81, "min-width media applies", "<p id=t class='target'>x</p>", "p { color: #ff0000; }\n@media (min-width: 320px) { p { color: #00ff00; } }")
add(82, "max-width media applies", "<p id=t class='target'>x</p>", "p { color: #ff0000; }\n@media (max-width: 2000px) { p { color: #00ff00; } }")
add(83, "min-width media not applies", "<p id=t class='target'>x</p>", "p { color: #00ff00; }\n@media (min-width: 9999px) { p { color: #ff0000; } }")
add(84, "orientation landscape applies", "<p id=t class='target'>x</p>", "p { color: #ff0000; }\n@media (orientation: landscape) { p { color: #00ff00; } }")
add(85, "orientation portrait not applies", "<p id=t class='target'>x</p>", "p { color: #00ff00; }\n@media (orientation: portrait) { p { color: #ff0000; } }")
add(86, "combined media range", "<p id=t class='target'>x</p>", "p { color: #ff0000; }\n@media (min-width: 320px) and (max-width: 2000px) { p { color: #00ff00; } }")
add(87, "min-height media", "<p id=t class='target'>x</p>", "p { color: #ff0000; }\n@media (min-height: 100px) { p { color: #00ff00; } }")
add(88, "max-height media", "<p id=t class='target'>x</p>", "p { color: #00ff00; }\n@media (max-height: 10px) { p { color: #ff0000; } }")
add(89, "screen media applies", "<p id=t class='target'>x</p>", "p { color: #ff0000; }\n@media screen { p { color: #00ff00; } }")
add(90, "print media not applies", "<p id=t class='target'>x</p>", "p { color: #00ff00; }\n@media print { p { color: #ff0000; } }")

# 2.10 at-rules / robustness
add(91, "keyframes rule is recorded", "<div id=t class='target'>x</div>", "@keyframes spin { from { opacity: 0; } to { opacity: 1; } }\n.target { animation: spin 1s; }")
add(92, "font-face at-rule is skipped safely", "<div id=t class='target'>x</div>", "@font-face { font-family: X; src: url(x.woff); }\n.target { color: #00ff00; }")
add(93, "supports at-rule is skipped", "<div id=t class='target'>x</div>", "@supports (color: red) { .target { color: #ff0000; } }\n.target { color: #00ff00; }")
add(94, "layer at-rule is skipped", "<div id=t class='target'>x</div>", "@layer base { .target { color: #ff0000; } }\n.target { color: #00ff00; }")
add(95, "nested media flattens", "<div id=t class='target'>x</div>", "@media screen { @media (min-width: 1px) { .target { color: #00ff00; } } }")
add(96, "unknown at-rule is skipped", "<div id=t class='target'>x</div>", "@frobulate { .target { color: #ff0000; } }\n.target { color: #00ff00; }")
add(97, "charset at-rule is skipped", "<div id=t class='target'>x</div>", "@charset \"UTF-8\";\n.target { color: #00ff00; }")
add(98, "empty stylesheet", "<div id=t class='target'>x</div>", "")
add(99, "multiple inline sheets order", "<style>.target { color: #ff0000; }</style><style>.target { color: #00ff00; }</style><div id=t class='target'>x</div>", "")
add(100, "important across sheets", "<style>.target { color: #ff0000 !important; }</style><style>.target { color: #00ff00; }</style><div id=t class='target'>x</div>", "")

# --------------------------------------------------------------------------- #
# materialise folders
# --------------------------------------------------------------------------- #
DST_ROOT.mkdir(parents=True, exist_ok=True)
for suffix, name, html, css_extra in CASES:
    num = int(suffix)
    folder = DST_ROOT / f"{num:03d}"
    folder.mkdir(parents=True, exist_ok=True)
    cid = f"css.{suffix}"
    (folder / "index.html").write_text(make_html(suffix, html))
    (folder / "style.css").write_text(make_css(css_extra))
    (folder / "app.js").write_text(make_js(cid))
print("materialised", len(CASES), "folders")
