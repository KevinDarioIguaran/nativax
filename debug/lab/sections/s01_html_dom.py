"""Section 1 — HTML, DOM and parsing (100 hand-authored cases).

Each case lives in ``debug/lab/cases/s01/NNN/`` with three real files:
``index.html``, ``style.css`` and ``app.js``. The laboratory runs the native
pipeline over that folder; nothing is generated at run time.

Fixtures are real applications (header, hero, animated cards, clock and
buttons), not empty fragments. Assertions are scoped with ``#case`` so the
visual shell is never confused with the case content.
"""
from harness import case, close, contains, eq, falsy, gt, truthy


def nodes_of_kind(node, kind):
    out = []

    def walk(n):
        if n.kind == kind:
            out.append(n)
        for c in n.children:
            walk(c)

    walk(node)
    return out


# 1.1 tokenisation and element creation ----------------------------------
@case(1, "html.001", "basic div becomes an element")
def _(ctx):
    page = ctx.fixture("html.001")
    eq(page.require("#case > div").tag, "div")


@case(1, "html.002", "inline span stays inside a paragraph")
def _(ctx):
    page = ctx.fixture("html.002")
    eq(page.require("#case span").tag, "span")
    eq(page.text("#case span"), "inline text")


@case(1, "html.003", "paragraph text is attached to the p element")
def _(ctx):
    page = ctx.fixture("html.003")
    eq(page.text("#case p"), "hello world")


@case(1, "html.004", "heading elements h1..h6 are recognised")
def _(ctx):
    page = ctx.fixture("html.004")
    for i in range(1, 7):
        eq(page.text(f"#case h{i}"), f"h{i} · level {i}")


@case(1, "html.005", "an unordered list keeps its li children in order")
def _(ctx):
    page = ctx.fixture("html.005")
    eq([n.text_content() for n in page.find_all("#case ul > li")], ["a", "b", "c"])


@case(1, "html.006", "html, head and body are synthesised when absent")
def _(ctx):
    page = ctx.fixture("html.006")
    truthy(page.find("html"), "html element missing")
    truthy(page.find("html > head"), "head element missing")
    truthy(page.find("html > body"), "body element missing")


@case(1, "html.007", "uppercase tags are normalised to lowercase")
def _(ctx):
    page = ctx.fixture("html.007")
    eq(page.require("#case div").tag, "div")
    eq(page.require("#case span").tag, "span")


@case(1, "html.008", "a div can nest inside another div")
def _(ctx):
    page = ctx.fixture("html.008")
    truthy(page.find("#case #o > #i"), "nesting was lost")


@case(1, "html.009", "unknown elements are preserved, not discarded")
def _(ctx):
    page = ctx.fixture("html.009")
    node = page.require("#case foo")
    eq(node.attr("bar"), "1")
    eq(node.text_content(), "x")


@case(1, "html.010", "custom elements with a dash are parsed")
def _(ctx):
    page = ctx.fixture("html.010")
    node = page.require("#case my-widget")
    eq(node.attr("data-k"), "v")
    eq(node.text_content(), "w")


# 1.2 attributes --------------------------------------------------------------
@case(1, "html.011", "double-quoted attribute values are decoded")
def _(ctx):
    eq(ctx.fixture("html.011").require("#case div").attr("title"), "a b")


@case(1, "html.012", "single-quoted attribute values are decoded")
def _(ctx):
    eq(ctx.fixture("html.012").require("#case div").attr("title"), "a b")


@case(1, "html.013", "unquoted attribute values are accepted")
def _(ctx):
    eq(ctx.fixture("html.013").require("#case div").attr("data-n"), "42")


@case(1, "html.014", "boolean attributes have an empty value")
def _(ctx):
    node = ctx.fixture("html.014").require("#case input")
    truthy("disabled" in node.attrs, "disabled attribute missing")
    eq(node.attrs["disabled"], "")


@case(1, "html.015", "id and class are ordinary attributes")
def _(ctx):
    node = ctx.fixture("html.015").require("#case #x")
    eq(node.classes, ["a", "b", "demo"])


@case(1, "html.016", "data-* attributes survive parsing")
def _(ctx):
    node = ctx.fixture("html.016").require("#case div")
    eq(node.attr("data-a"), "1")
    eq(node.attr("data-b"), "two")


@case(1, "html.017", "aria-* attributes survive parsing")
def _(ctx):
    node = ctx.fixture("html.017").require("#case div")
    eq(node.attr("aria-label"), "close")
    eq(node.attr("role"), "button")


@case(1, "html.018", "attribute values may contain spaces and punctuation")
def _(ctx):
    eq(ctx.fixture("html.018").require("#case div").attr("title"), "a, b; c=d")


@case(1, "html.019", "duplicate attributes keep the first value")
def _(ctx):
    eq(ctx.fixture("html.019").require("#case div").attr("id"), "first")


@case(1, "html.020", "attribute names are lowercased")
def _(ctx):
    node = ctx.fixture("html.020").require("#case div")
    eq(node.attr("data-x"), "1")
    eq(node.attrs.get("class"), "demo")


# 1.3 tree construction -------------------------------------------------
@case(1, "html.021", "parent-child chains follow the markup")
def _(ctx):
    truthy(ctx.fixture("html.021").find("#case > section > article > p"), "cadena rota")


@case(1, "html.022", "sibling elements keep document order")
def _(ctx):
    page = ctx.fixture("html.022")
    eq([n.id for n in page.find_all("#case > div")], ["a", "b", "c"])


@case(1, "html.023", "head content stays out of body")
def _(ctx):
    page = ctx.fixture("html.023")
    truthy(page.find("head > title"), "title fuera de head")
    falsy(page.find("body > title"), "title leaked into body")


@case(1, "html.024", "body-only markup is wrapped in html/head/body")
def _(ctx):
    truthy(ctx.fixture("html.024").find("#case > main"), "main is not under body")


@case(1, "html.025", "nested lists preserve hierarchy")
def _(ctx):
    truthy(ctx.fixture("html.025").find("#case ul > li > ul > li"), "lista anidada perdida")


@case(1, "html.026", "table rows and cells keep the table hierarchy")
def _(ctx):
    page = ctx.fixture("html.026")
    truthy(page.find("#case table > tbody > tr"), "tbody is missing")
    eq([n.text_content() for n in page.find_all("#case tr > td")], ["a", "b"])


@case(1, "html.027", "deep nesting is preserved to 20 levels")
def _(ctx):
    page = ctx.fixture("html.027")
    gt(page.summary["dom"]["max_depth"], 19)
    truthy(page.find("#case > div > div > div"), "nested levels are missing")


@case(1, "html.028", "multiple top-level elements share one body")
def _(ctx):
    eq(len(ctx.fixture("html.028").find_all("#case > *")), 3)


@case(1, "html.029", "inline elements may sit inside blocks")
def _(ctx):
    eq(ctx.fixture("html.029").text("#case > div"), "ab")


@case(1, "html.030", "whitespace text nodes between elements are kept")
def _(ctx):
    page = ctx.fixture("html.030")
    text_nodes = [n for n in page.require("#ws").children if n.kind == "text"]
    truthy(text_nodes, "se perdieron los espacios entre elementos")


# 1.4 void elements and raw text ------------------------------------------
@case(1, "html.031", "br is a void element")
def _(ctx):
    page = ctx.fixture("html.031")
    eq(page.require("#case br").children, [])
    eq(page.text("#case p"), "ab")


@case(1, "html.032", "img keeps its src attribute and has no children")
def _(ctx):
    node = ctx.fixture("html.032").require("#case img")
    eq(node.attr("src"), "a.png")
    eq(node.attr("alt"), "A")
    eq(node.children, [])


@case(1, "html.033", "input is void and keeps value/type")
def _(ctx):
    node = ctx.fixture("html.033").require("#case input")
    eq(node.attr("type"), "text")
    eq(node.attr("value"), "hi")


@case(1, "html.034", "hr is void and does not absorb following content")
def _(ctx):
    page = ctx.fixture("html.034")
    eq(page.require("#case hr").children, [])
    eq(page.text("#case p"), "after")


@case(1, "html.035", "meta and link are void elements in head")
def _(ctx):
    page = ctx.fixture("html.035")
    eq(page.require('meta[name="case"]').children, [])
    eq(page.require("head > link").children, [])
    truthy(page.find('head > meta[name="case"]'), "meta fuera de head")


@case(1, "html.036", "script text is raw: markup inside is not parsed")
def _(ctx):
    page = ctx.fixture("html.036")
    eq(page.text("script"), 'var a = "<div>";')
    falsy(page.find("script div"), "markup inside script was parsed")


@case(1, "html.037", "style text is raw: braces and markup stay as text")
def _(ctx):
    page = ctx.fixture("html.037")
    eq(page.text("style"), ".a{color:red}")
    falsy(page.find("style p"), "markup inside style was parsed")


@case(1, "html.038", "textarea content is raw text, not elements")
def _(ctx):
    page = ctx.fixture("html.038")
    eq(page.text("#case textarea"), "<b>x</b>")
    falsy(page.find("textarea b"), "markup inside textarea was parsed")


@case(1, "html.039", "the self-closing slash on a non-void element is ignored")
def _(ctx):
    page = ctx.fixture("html.039")
    truthy(page.find("#case div > span"), "span should stay inside the div")
    eq(page.text("#case span"), "x")


@case(1, "html.040", "a new p autocloses the previous p")
def _(ctx):
    page = ctx.fixture("html.040")
    paras = page.find_all("#case > p")
    eq(len(paras), 2)
    eq([n.text_content().strip() for n in paras], ["one", "two"])


# 1.5 text, entities and whitespace -------------------------------------------
@case(1, "html.041", "plain text is preserved verbatim")
def _(ctx):
    eq(ctx.fixture("html.041").text("#case p"), "Hello, native world!")


@case(1, "html.042", "&amp; decodes to &")
def _(ctx):
    eq(ctx.fixture("html.042").text("#case p"), "a & b")


@case(1, "html.043", "&lt; and &gt; decode to angle brackets")
def _(ctx):
    eq(ctx.fixture("html.043").text("#case p"), "<tag>")


@case(1, "html.044", "&quot; decodes to a double quote")
def _(ctx):
    eq(ctx.fixture("html.044").text("#case p"), '"x"')


@case(1, "html.045", "decimal numeric references decode")
def _(ctx):
    eq(ctx.fixture("html.045").text("#case p"), "AB")


@case(1, "html.046", "hexadecimal numeric references decode")
def _(ctx):
    eq(ctx.fixture("html.046").text("#case p"), "AB")


@case(1, "html.047", "&nbsp; decodes to a non-breaking space")
def _(ctx):
    eq(ctx.fixture("html.047").text("#case p"), "a\u00a0b")


@case(1, "html.048", "internal whitespace in a text node is kept")
def _(ctx):
    eq(ctx.fixture("html.048").text("#case p"), "a   b")


@case(1, "html.049", "UTF-8 text survives the parse")
def _(ctx):
    eq(ctx.fixture("html.049").text("#case p"), "áéíóú 日本語 🚀")


@case(1, "html.050", "text split by an inline element concatenates")
def _(ctx):
    page = ctx.fixture("html.050")
    eq(page.text("#case p"), "abc")
    eq(page.text("#case em"), "b")


# 1.6 comments, doctype and case -------------------------------------
@case(1, "html.051", "comments are not elements")
def _(ctx):
    page = ctx.fixture("html.051")
    eq([n for n in page.elements() if n.tag == "#comment"], [])
    truthy(page.find("#case #x"), "element after the comment is missing")


@case(1, "html.052", "comment text is retained in the tree")
def _(ctx):
    page = ctx.fixture("html.052")
    comments = nodes_of_kind(page.root, "comment")
    truthy(comments, "comment was not found")
    eq(comments[0].text, " hello ")


@case(1, "html.053", "doctype does not become an element")
def _(ctx):
    page = ctx.fixture("html.053")
    eq([n for n in page.elements() if "doctype" in n.tag.lower()], [])
    eq(page.text("#case p"), "x")


@case(1, "html.054", "uppercase closing tags match lowercase opens")
def _(ctx):
    eq(ctx.fixture("html.054").text("#case div > p"), "x")


@case(1, "html.055", "mixed-case attribute names are lowercased")
def _(ctx):
    eq(ctx.fixture("html.055").require("#case div").attr("data-foo"), "1")


@case(1, "html.056", "implicit html/head/body have the expected order")
def _(ctx):
    html = ctx.fixture("html.056").require("html")
    eq([c.tag for c in html.children if c.kind == "element"], ["head", "body"])


@case(1, "html.057", "title text is preserved in the head")
def _(ctx):
    eq(ctx.fixture("html.057").text("title"), "NativaX")


@case(1, "html.058", "several comments are all retained")
def _(ctx):
    page = ctx.fixture("html.058")
    eq(len(nodes_of_kind(page.root, "comment")), 3)


@case(1, "html.059", "a comment inside an element does not close it")
def _(ctx):
    eq(ctx.fixture("html.059").text("#case > div > span"), "y")


@case(1, "html.060", "doctype plus uppercase markup parses as one document")
def _(ctx):
    eq(ctx.fixture("html.060").require("#case #a").text_content(), "x")


# 1.7 malformed input and recovery -------------------------------------
@case(1, "html.061", "an unclosed div is recovered at end of input")
def _(ctx):
    eq(ctx.fixture("html.061").text("#case > div").strip(), "x")


@case(1, "html.062", "a stray closing tag is ignored")
def _(ctx):
    page = ctx.fixture("html.062")
    eq(page.text("#case > p"), "x")
    eq(len(page.find_all("#case > div")), 0)


@case(1, "html.063", "misnested inline tags keep the inner element")
def _(ctx):
    page = ctx.fixture("html.063")
    truthy(page.find("#case b > i"), "b > i was lost")
    eq(page.text("#case b"), "x")


@case(1, "html.064", "an unclosed paragraph still renders its text")
def _(ctx):
    eq(ctx.fixture("html.064").text("#case p").strip(), "dangling")


@case(1, "html.065", "an unterminated attribute quote does not crash the parser")
def _(ctx):
    page = ctx.fixture("html.065")
    truthy(page.find("html"), "no se produjo documento")
    truthy(page.summary["dom"]["elements"] >= 3, "empty tree")


@case(1, "html.066", "a bare < in text is treated as text")
def _(ctx):
    contains(ctx.fixture("html.066").text("#case p"), "<")


@case(1, "html.067", "an empty document still produces html/head/body")
def _(ctx):
    page = ctx.fixture("html.067")
    eq([n.tag for n in page.find_all("html > *")], ["head", "body"])


@case(1, "html.068", "whitespace-only markup produces an empty body")
def _(ctx):
    eq(ctx.fixture("html.068").require("body").text_content().strip(), "")


@case(1, "html.069", "duplicate ids produce two distinct element nodes")
def _(ctx):
    page = ctx.fixture("html.069")
    ids = page.find_all("#case #a")
    eq(len(ids), 2)
    falsy(ids[0].slot == ids[1].slot, "los slots deben diferir")


@case(1, "html.070", "mismatched nested lists do not lose their items")
def _(ctx):
    text = ctx.fixture("html.070").text("#case")
    for item in ("a", "b", "c"):
        contains(text, item)


# 1.8 DOM queries ----------------------------------------------------------
@case(1, "html.071", "tag selector finds the first element")
def _(ctx):
    eq(ctx.fixture("html.071").find("#case p").text_content(), "a")


@case(1, "html.072", "id selector matches exactly one node")
def _(ctx):
    eq(ctx.fixture("html.072").require("#case #only").id, "only")


@case(1, "html.073", "class selector matches all nodes with the class")
def _(ctx):
    eq([n.tag for n in ctx.fixture("html.073").find_all("#case .k")], ["i", "b"])


@case(1, "html.074", "descendant combinator matches nested elements")
def _(ctx):
    truthy(ctx.fixture("html.074").find("#case div span"), "descendant combinator failed")


@case(1, "html.075", "child combinator requires a direct parent")
def _(ctx):
    page = ctx.fixture("html.075")
    falsy(page.find("#case div > span"), "a grandchild matched")
    truthy(page.find("#case div > section"), "direct child is missing")


@case(1, "html.076", "attribute presence selector")
def _(ctx):
    page = ctx.fixture("html.076")
    eq(len(page.find_all("#case a[href]")), 1)


@case(1, "html.077", "attribute equals selector")
def _(ctx):
    page = ctx.fixture("html.077")
    eq(page.require('#case input[type="checkbox"]').attr("type"), "checkbox")


@case(1, "html.078", "first-child selector")
def _(ctx):
    eq(ctx.fixture("html.078").require("#case li:first-child").text_content(), "a")


@case(1, "html.079", "nth-child selector matches position 2")
def _(ctx):
    eq(ctx.fixture("html.079").require("#case li:nth-child(2)").text_content(), "b")


@case(1, "html.080", "not() excludes matching elements")
def _(ctx):
    eq([n.text_content() for n in ctx.fixture("html.080").find_all("#case div:not(.x)")],
       ["b"])


# 1.9 document statistics and shape ------------------------------------
@case(1, "html.081", "summary counts the elements of the case")
def _(ctx):
    page = ctx.fixture("html.081")
    eq(len(page.find_all("#case *")), 2)


@case(1, "html.082", "summary counts text nodes")
def _(ctx):
    page = ctx.fixture("html.082")
    p = page.require("#case p")
    eq(len([c for c in p.children if c.kind == "text"]), 2)
    truthy(page.summary["dom"]["text"] >= 3, "too few text nodes")


@case(1, "html.083", "summary counts comments")
def _(ctx):
    page = ctx.fixture("html.083")
    eq(len(nodes_of_kind(page.root, "comment")), 2)


@case(1, "html.084", "summary reports max depth for nested markup")
def _(ctx):
    page = ctx.fixture("html.084")
    gt(page.summary["dom"]["max_depth"], 5)
    truthy(page.find("#case > div > div > div"), "third nesting level is missing")


@case(1, "html.085", "the JSON DOM dump lists every element tag")
def _(ctx):
    dumped = [n.tag for n in ctx.fixture("html.085").elements()]
    for tag in ("html", "head", "body", "main", "article", "h2"):
        contains(dumped, tag)


@case(1, "html.086", "text_content() is a deep concatenation")
def _(ctx):
    eq(ctx.fixture("html.086").require("#case div").text_content(), "abcd")


@case(1, "html.087", "element order in the dump is pre-order")
def _(ctx):
    page = ctx.fixture("html.087")
    ids = [n.id for n in page.elements() if n.id in ("a", "b", "c")]
    eq(ids, ["a", "b", "c"])


@case(1, "html.088", "node slots are unique for element nodes")
def _(ctx):
    slots = [n.slot for n in ctx.fixture("html.088").elements()]
    eq(len(slots), len(set(slots)))


@case(1, "html.089", "empty elements have no child nodes")
def _(ctx):
    eq(ctx.fixture("html.089").require("#case #e").children, [])


@case(1, "html.090", "comments and text are distinguishable node kinds")
def _(ctx):
    page = ctx.fixture("html.090")
    kinds = {c.kind for c in page.require("#case > div").children}
    eq(kinds, {"text", "comment"})


# 1.10 style sheets and scripts -------------------------------------------
@case(1, "html.091", "an inline style sheet contributes rules")
def _(ctx):
    page = ctx.fixture("html.091")
    hits = [r for r in page.rules()
            if r["selector"].startswith("p")
            and any(d["name"] == "color" for d in r["decls"])]
    eq(len(hits), 1)


@case(1, "html.092", "an inline style rule changes the computed color")
def _(ctx):
    st = ctx.fixture("html.092").style("#case p")
    close(st["color"][2], 1.0, 0.01)
    close(st["color"][0], 0.0, 0.01)


@case(1, "html.093", "a class rule applies to a matching element")
def _(ctx):
    st = ctx.fixture("html.093").style("#case .hot")
    close(st["bg"][0], 1.0, 0.01)
    close(st["bg"][3], 1.0, 0.01)


@case(1, "html.094", "the id rule wins over the class rule")
def _(ctx):
    st = ctx.fixture("html.094").style("#case #x")
    close(st["color"][1], 1.0, 0.01)
    close(st["color"][0], 0.0, 0.01)


@case(1, "html.095", "the style attribute wins over author rules")
def _(ctx):
    st = ctx.fixture("html.095").style("#case p")
    close(st["color"][2], 1.0, 0.01)


@case(1, "html.096", "script source is preserved byte-for-byte")
def _(ctx):
    src = "function f(){\n  return 1 < 2 && 'a';\n}\n"
    eq(ctx.fixture("html.096").text("script"), src)


@case(1, "html.097", "the script element is not laid out")
def _(ctx):
    page = ctx.fixture("html.097")
    eq(page.style("#case script")["display"], "none")
    eq(page.box("#case script"), None)


@case(1, "html.098", "the style element is not laid out")
def _(ctx):
    page = ctx.fixture("html.098")
    eq(page.style("#case style")["display"], "none")
    eq(page.box("#case style"), None)


@case(1, "html.099", "an external sheet supplied by the case applies")
def _(ctx):
    page = ctx.fixture("html.099")
    eq(page.summary["css"]["files"], 1)
    close(page.style("#case p")["color"][0], 1.0, 0.01)


@case(1, "html.100", "inline sheet order follows document order")
def _(ctx):
    st = ctx.fixture("html.100").style("#case p")
    close(st["color"][2], 1.0, 0.01)
    close(st["color"][0], 0.0, 0.01)
